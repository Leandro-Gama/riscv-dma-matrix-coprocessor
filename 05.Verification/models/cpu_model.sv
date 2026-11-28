/* Behavioural RV32I core that stands in for the CPU until its owner delivers the RTL. It has the
   module name and the ports the interface contract gives the CPU, so the top level does not change
   when the real core replaces this file in the file list.

   One instruction per cycle; a load or a store holds the core until the bus answers, which is the
   stall the contract asks of the real core. Data accesses go out with the byte address and the
   strobes of the lanes, as the contract says. The system instructions (ECALL, EBREAK, CSR) are not
   implemented; an unknown instruction stops the core with an error. Every wait on the bus is
   bounded and reported, so a broken slave cannot hang the simulation silently.

   +CPU_TRACE=1 prints every instruction retired. */
// The file keeps the name of the model; the module takes the name of the core it replaces.
module cpu_top  // verilog_lint: waive module-filename
  import soc_pkg::*;
#(
    parameter logic [31:0] RESET_PC = IMEM_BASE,
    parameter int BUS_TIMEOUT = 10_000
) (
    input logic clk_i,
    input logic rst_ni,

    output logic [31:0] imem_addr_o,
    input  logic [31:0] imem_rdata_i,

    output logic [AXIL_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic m_axi_awvalid,
    input  logic m_axi_awready,
    output logic [AXIL_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [AXIL_STRB_WIDTH-1:0] m_axi_wstrb,
    output logic m_axi_wvalid,
    input  logic m_axi_wready,
    input  logic [1:0] m_axi_bresp,
    input  logic m_axi_bvalid,
    output logic m_axi_bready,
    output logic [AXIL_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic m_axi_arvalid,
    input  logic m_axi_arready,
    input  logic [AXIL_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0] m_axi_rresp,
    input  logic m_axi_rvalid,
    output logic m_axi_rready,

    input logic irq_i
);

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam logic [6:0] OP_LUI = 7'h37;
  localparam logic [6:0] OP_AUIPC = 7'h17;
  localparam logic [6:0] OP_JAL = 7'h6F;
  localparam logic [6:0] OP_JALR = 7'h67;
  localparam logic [6:0] OP_BRANCH = 7'h63;
  localparam logic [6:0] OP_LOAD = 7'h03;
  localparam logic [6:0] OP_STORE = 7'h23;
  localparam logic [6:0] OP_IMM = 7'h13;
  localparam logic [6:0] OP_REG = 7'h33;
  localparam logic [6:0] OP_FENCE = 7'h0F;

  logic [31:0] pc;
  logic [31:0] regs[32];
  logic halted;
  longint unsigned retired;
  bit trace;

  assign imem_addr_o = pc;

  initial if (!$value$plusargs("CPU_TRACE=%d", trace)) trace = 1'b0;

  function automatic logic [31:0] rd_reg(input logic [4:0] index);
    return (index == 0) ? 32'h0 : regs[index];
  endfunction

  task automatic bus_idle();
    m_axi_awvalid <= 1'b0;
    m_axi_wvalid <= 1'b0;
    m_axi_bready <= 1'b0;
    m_axi_arvalid <= 1'b0;
    m_axi_rready <= 1'b0;
  endtask

  task automatic reset_state();
    pc = RESET_PC;
    foreach (regs[i]) regs[i] = 32'h0;
    halted = 1'b0;
    retired = 0;
    m_axi_awaddr <= '0;
    m_axi_wdata <= '0;
    m_axi_wstrb <= '0;
    m_axi_araddr <= '0;
    bus_idle();
  endtask

  task automatic fail(input string what);
    `uvm_error("CPU_MODEL", $sformatf("pc=0x%08h: %s; the core stops", pc, what))
    halted = 1'b1;
  endtask

  // Outputs change with nonblocking assignments, so the bus sees them after the edge, like a flop.
  task automatic bus_write(input logic [31:0] addr, input logic [31:0] data,
                           input logic [3:0] strb, output bit ok);
    bit aw_done = 1'b0;
    bit w_done = 1'b0;
    int unsigned waited = 0;
    ok = 1'b0;
    m_axi_awaddr <= addr;
    m_axi_awvalid <= 1'b1;
    m_axi_wdata <= data;
    m_axi_wstrb <= strb;
    m_axi_wvalid <= 1'b1;
    m_axi_bready <= 1'b1;
    while (!(aw_done && w_done)) begin
      @(posedge clk_i);
      if (!aw_done && m_axi_awready) begin
        aw_done = 1'b1;
        m_axi_awvalid <= 1'b0;
      end
      if (!w_done && m_axi_wready) begin
        w_done = 1'b1;
        m_axi_wvalid <= 1'b0;
      end
      if (++waited > BUS_TIMEOUT) begin
        bus_idle();
        fail($sformatf("store to 0x%08h not accepted in %0d cycles", addr, BUS_TIMEOUT));
        return;
      end
    end
    do begin
      @(posedge clk_i);
      if (++waited > BUS_TIMEOUT) begin
        bus_idle();
        fail($sformatf("store to 0x%08h got no response in %0d cycles", addr, BUS_TIMEOUT));
        return;
      end
    end while (!m_axi_bvalid);
    m_axi_bready <= 1'b0;
    // The contract lets the CPU ignore error responses; they are only reported.
    if (m_axi_bresp != RESP_OKAY) begin
      `uvm_info("CPU_MODEL", $sformatf("store to 0x%08h answered 0x%0h", addr, m_axi_bresp),
                UVM_LOW)
    end
    ok = 1'b1;
  endtask

  task automatic bus_read(input logic [31:0] addr, output logic [31:0] data, output bit ok);
    int unsigned waited = 0;
    ok = 1'b0;
    data = 'x;
    m_axi_araddr <= addr;
    m_axi_arvalid <= 1'b1;
    m_axi_rready <= 1'b1;
    do begin
      @(posedge clk_i);
      if (++waited > BUS_TIMEOUT) begin
        bus_idle();
        fail($sformatf("load from 0x%08h not accepted in %0d cycles", addr, BUS_TIMEOUT));
        return;
      end
    end while (!m_axi_arready);
    m_axi_arvalid <= 1'b0;
    do begin
      @(posedge clk_i);
      if (++waited > BUS_TIMEOUT) begin
        bus_idle();
        fail($sformatf("load from 0x%08h got no response in %0d cycles", addr, BUS_TIMEOUT));
        return;
      end
    end while (!m_axi_rvalid);
    m_axi_rready <= 1'b0;
    data = m_axi_rdata;
    if (m_axi_rresp != RESP_OKAY) begin
      `uvm_info("CPU_MODEL", $sformatf("load from 0x%08h answered 0x%0h", addr, m_axi_rresp),
                UVM_LOW)
    end
    ok = 1'b1;
  endtask

  task automatic execute(input logic [31:0] instr);
    logic [6:0] opcode = instr[6:0];
    logic [4:0] rd = instr[11:7];
    logic [2:0] funct3 = instr[14:12];
    logic [4:0] rs1 = instr[19:15];
    logic [4:0] rs2 = instr[24:20];
    logic [6:0] funct7 = instr[31:25];
    logic [31:0] a = rd_reg(rs1);
    logic [31:0] b = rd_reg(rs2);
    logic [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    logic [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    logic [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    logic [31:0] imm_u = {instr[31:12], 12'h000};
    logic [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
    logic [31:0] next_pc = pc + 4;
    logic [31:0] result = 'x;
    logic [31:0] addr, word, shifted;
    logic [3:0] strb;
    bit write_rd = 1'b0;
    bit taken, ok;

    unique case (opcode)
      OP_LUI: begin
        result = imm_u;
        write_rd = 1'b1;
      end
      OP_AUIPC: begin
        result = pc + imm_u;
        write_rd = 1'b1;
      end
      OP_JAL: begin
        result = pc + 4;
        write_rd = 1'b1;
        next_pc = pc + imm_j;
      end
      OP_JALR: begin
        if (funct3 != 3'b000) begin
          fail($sformatf("unknown instruction 0x%08h", instr));
          return;
        end
        result = pc + 4;
        write_rd = 1'b1;
        next_pc = (a + imm_i) & ~32'h1;
      end
      OP_BRANCH: begin
        unique case (funct3)
          3'b000: taken = (a == b);
          3'b001: taken = (a != b);
          3'b100: taken = ($signed(a) < $signed(b));
          3'b101: taken = ($signed(a) >= $signed(b));
          3'b110: taken = (a < b);
          3'b111: taken = (a >= b);
          default: begin
            fail($sformatf("bad branch 0x%08h", instr));
            return;
          end
        endcase
        if (taken) next_pc = pc + imm_b;
      end
      OP_LOAD: begin
        addr = a + imm_i;
        if (!(funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101})) begin
          fail($sformatf("bad load 0x%08h", instr));
          return;
        end
        if ((funct3[1:0] == 2'b10 && addr[1:0] != 0) || (funct3[1:0] == 2'b01 && addr[0])) begin
          fail($sformatf("misaligned load from 0x%08h", addr));
          return;
        end
        bus_read(addr, word, ok);
        if (!ok) return;
        shifted = word >> (8 * addr[1:0]);
        unique case (funct3)
          3'b000: result = {{24{shifted[7]}}, shifted[7:0]};
          3'b001: result = {{16{shifted[15]}}, shifted[15:0]};
          3'b010: result = word;
          3'b100: result = {24'h0, shifted[7:0]};
          3'b101: result = {16'h0, shifted[15:0]};
          default: begin
            fail($sformatf("bad load 0x%08h", instr));
            return;
          end
        endcase
        write_rd = 1'b1;
      end
      OP_STORE: begin
        addr = a + imm_s;
        unique case (funct3)
          3'b000: strb = 4'b0001 << addr[1:0];
          3'b001: strb = 4'b0011 << addr[1:0];
          3'b010: strb = 4'b1111;
          default: begin
            fail($sformatf("bad store 0x%08h", instr));
            return;
          end
        endcase
        if ((funct3 == 3'b010 && addr[1:0] != 0) || (funct3 == 3'b001 && addr[0])) begin
          fail($sformatf("misaligned store to 0x%08h", addr));
          return;
        end
        bus_write(addr, b << (8 * addr[1:0]), strb, ok);
        if (!ok) return;
      end
      OP_IMM: begin
        write_rd = 1'b1;
        unique case (funct3)
          3'b000: result = a + imm_i;
          3'b010: result = 32'($signed(a) < $signed(imm_i));
          3'b011: result = 32'(a < imm_i);
          3'b100: result = a ^ imm_i;
          3'b110: result = a | imm_i;
          3'b111: result = a & imm_i;
          3'b001: result = a << instr[24:20];
          3'b101: result = instr[30] ? 32'($signed(a) >>> instr[24:20]) : a >> instr[24:20];
          default: ;
        endcase
        // Shifts by an immediate have a fixed upper field: 0, or 0x20 for SRAI.
        if ((funct3 == 3'b001 && funct7 != 7'h00) ||
            (funct3 == 3'b101 && !(funct7 inside {7'h00, 7'h20}))) begin
          fail($sformatf("unknown instruction 0x%08h", instr));
          return;
        end
      end
      OP_REG: begin
        write_rd = 1'b1;
        unique case ({funct7, funct3})
          {7'h00, 3'b000}: result = a + b;
          {7'h20, 3'b000}: result = a - b;
          {7'h00, 3'b001}: result = a << b[4:0];
          {7'h00, 3'b010}: result = 32'($signed(a) < $signed(b));
          {7'h00, 3'b011}: result = 32'(a < b);
          {7'h00, 3'b100}: result = a ^ b;
          {7'h00, 3'b101}: result = a >> b[4:0];
          {7'h20, 3'b101}: result = 32'($signed(a) >>> b[4:0]);
          {7'h00, 3'b110}: result = a | b;
          {7'h00, 3'b111}: result = a & b;
          default: begin
            fail($sformatf("unknown instruction 0x%08h", instr));
            return;
          end
        endcase
      end
      OP_FENCE: ;
      default: begin
        fail($sformatf("unknown instruction 0x%08h", instr));
        return;
      end
    endcase

    // Without the compressed extension every target is word aligned.
    if (next_pc[1:0] != 2'b00) begin
      fail($sformatf("jump or branch to misaligned 0x%08h", next_pc));
      return;
    end
    if (write_rd && rd != 0) regs[rd] = result;
    if (trace) begin
      $display("CPU %0t pc=%08h instr=%08h%s", $time, pc, instr,
               (write_rd && rd != 0) ? $sformatf(" x%0d=%08h", rd, result) : "");
    end
    retired++;
    pc = next_pc;
  endtask

  /* The core runs while reset is released; a reset in the middle of an instruction abandons it,
     as the real core would. */
  initial begin
    reset_state();
    forever begin
      wait (rst_ni === 1'b1);
      fork
        begin : run
          forever begin
            @(posedge clk_i);
            if (!halted) begin
              if ($isunknown(imem_rdata_i)) fail($sformatf("fetch at 0x%08h returned X", pc));
              else execute(imem_rdata_i);
            end
          end
        end
        @(negedge rst_ni);
      join_any
      disable fork;
      reset_state();
    end
  end

endmodule
