/* CPU model against the Python RV32I reference model. The first program uses every instruction the
   reference model runs, and the registers and data memory at the end must match what the model
   computed (cpu_selftest.py writes the expected file). The second program checks byte and
   half-word accesses by itself. The data memory is the real one of the system, at address 0 as in
   the reference model, so the bus handshake and the byte strobes are exercised too.
   Inputs: +ISS_HEX= +ISS_EXPECTED= +BYTES_HEX= (defaults in the build directory). */
module tb_cpu_model
  import soc_pkg::*;
();

  localparam int DMEM_TB_BYTES = 4096;
  localparam logic [31:0] RESULT_ADDR = 32'h2FC;
  localparam logic [31:0] SELF_JUMP = 32'h0000_006F;
  localparam int MAX_CYCLES = 20_000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] awaddr, wdata, araddr, rdata;
  logic [3:0] wstrb;
  logic [1:0] bresp, rresp;
  logic awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
  int unsigned n_ok, n_err;

  mem_instr u_imem (
      .addr_i (imem_addr),
      .rdata_o(imem_rdata)
  );

  mem_data #(
      .BASE_ADDR (32'h0),
      .DMEM_BYTES(DMEM_TB_BYTES)
  ) u_dmem (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .s_axi_awaddr (awaddr),
      .s_axi_awvalid(awvalid),
      .s_axi_awready(awready),
      .s_axi_wdata  (wdata),
      .s_axi_wstrb  (wstrb),
      .s_axi_wvalid (wvalid),
      .s_axi_wready (wready),
      .s_axi_bresp  (bresp),
      .s_axi_bvalid (bvalid),
      .s_axi_bready (bready),
      .s_axi_araddr (araddr),
      .s_axi_arvalid(arvalid),
      .s_axi_arready(arready),
      .s_axi_rdata  (rdata),
      .s_axi_rresp  (rresp),
      .s_axi_rvalid (rvalid),
      .s_axi_rready (rready)
  );

  cpu_top u_cpu (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .imem_addr_o  (imem_addr),
      .imem_rdata_i (imem_rdata),
      .m_axi_awaddr (awaddr),
      .m_axi_awvalid(awvalid),
      .m_axi_awready(awready),
      .m_axi_wdata  (wdata),
      .m_axi_wstrb  (wstrb),
      .m_axi_wvalid (wvalid),
      .m_axi_wready (wready),
      .m_axi_bresp  (bresp),
      .m_axi_bvalid (bvalid),
      .m_axi_bready (bready),
      .m_axi_araddr (araddr),
      .m_axi_arvalid(arvalid),
      .m_axi_arready(arready),
      .m_axi_rdata  (rdata),
      .m_axi_rresp  (rresp),
      .m_axi_rvalid (rvalid),
      .m_axi_rready (rready),
      .irq_i        (1'b0)
  );

  task automatic check(input string name, input logic cond);
    if (cond) begin
      n_ok++;
    end else begin
      n_err++;
      $display("ERRO %s", name);
    end
  endtask

  // Runs a program from reset until the core reaches the jump to itself that ends it.
  task automatic run_program(input string file, output int unsigned cycles);
    rst_n = 1'b0;
    for (int i = 0; i < DMEM_TB_BYTES / 4; i++) u_dmem.mem[i] = 32'h0;
    for (int i = 0; i < IMEM_BYTES_DEFAULT / 4; i++) u_imem.mem[i] = 32'h0000_0013;
    $readmemh(file, u_imem.mem);
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    cycles = 0;
    while (!(imem_rdata == SELF_JUMP && u_cpu.retired > 0) && cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++;
    end
    repeat (4) @(posedge clk);
  endtask

  initial begin
    string iss_hex = "cpu_selftest_iss.hex";
    string iss_expected = "cpu_selftest_iss.expected";
    string bytes_hex = "cpu_selftest_bytes.hex";
    int fd, index, code;
    string kind;
    logic [31:0] addr, value;
    logic [31:0] expected_mem[int unsigned];
    int unsigned cycles, bad_words;

    void'($value$plusargs("ISS_HEX=%s", iss_hex));
    void'($value$plusargs("ISS_EXPECTED=%s", iss_expected));
    void'($value$plusargs("BYTES_HEX=%s", bytes_hex));
    n_ok = 0;
    n_err = 0;

    run_program(iss_hex, cycles);
    check($sformatf("programa 1 termina em menos de %0d ciclos", MAX_CYCLES), cycles < MAX_CYCLES);
    check("programa 1 sem parada por erro", !u_cpu.halted);
    fd = $fopen(iss_expected, "r");
    if (fd == 0) $fatal(1, "tb_cpu_model: cannot open %s", iss_expected);
    while (!$feof(fd)) begin
      code = $fscanf(fd, "%s", kind);
      if (code != 1) break;
      if (kind == "//") begin
        void'($fgets(kind, fd));
      end else if (kind == "R") begin
        void'($fscanf(fd, "%d %h", index, value));
        check($sformatf("x%0d = %08h (modelo de referencia), cpu = %08h", index, value,
                        u_cpu.regs[index]), u_cpu.regs[index] === value);
      end else if (kind == "M") begin
        void'($fscanf(fd, "%h %h", addr, value));
        expected_mem[addr>>2] = value;
      end
    end
    $fclose(fd);
    // Every word is compared, so a stray store anywhere in the memory is caught too.
    bad_words = 0;
    for (int unsigned w = 0; w < DMEM_TB_BYTES / 4; w++) begin
      value = expected_mem.exists(w) ? expected_mem[w] : 32'h0;
      if (u_dmem.mem[w] !== value) begin
        bad_words++;
        $display("ERRO mem[%08h] = %08h, o modelo de referencia tem %08h", 4 * w, u_dmem.mem[w],
                 value);
      end
    end
    check($sformatf("memoria inteira igual a do modelo de referencia (%0d palavras com valor)",
                    expected_mem.size()), bad_words == 0 && expected_mem.size() > 0);
    $display("programa 1: %0d instrucoes em %0d ciclos", u_cpu.retired, cycles);

    run_program(bytes_hex, cycles);
    check("programa 2 sem parada por erro", !u_cpu.halted);
    check($sformatf("byte e meia palavra: resultado %08h (600d = ok, senao o numero do teste)",
                    u_dmem.mem[RESULT_ADDR>>2]), u_dmem.mem[RESULT_ADDR>>2] === 32'h600D);
    $display("programa 2: %0d instrucoes em %0d ciclos", u_cpu.retired, cycles);

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

endmodule
