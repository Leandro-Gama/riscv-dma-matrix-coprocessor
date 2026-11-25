/* Shared data memory: the AXI4-Lite slave required by the interface contract, holding A, B, C and
   the firmware data. DMEM_BYTES is a parameter so synthesis can run a shallow instance, because
   at the full depth the memory flip-flops dominate area and hide the difference between meshes. */
module mem_data
  import soc_pkg::*;
#(
    parameter logic [AXIL_ADDR_WIDTH-1:0] BASE_ADDR = DMEM_BASE,
    parameter int DMEM_BYTES = DMEM_BYTES_DEFAULT
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [AXIL_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0] s_axi_wstrb,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [AXIL_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input  logic s_axi_rready
);

  localparam int WORDS = DMEM_BYTES / AXIL_STRB_WIDTH;
  localparam int IDX_WIDTH = $clog2(WORDS);

  logic req, we, ack, err;
  logic [AXIL_ADDR_WIDTH-1:0] addr;
  logic [AXIL_STRB_WIDTH-1:0] be;
  logic [AXIL_DATA_WIDTH-1:0] wdata, rdata;

  axil_slave_port u_port (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr,
      .s_axi_awvalid,
      .s_axi_awready,
      .s_axi_wdata,
      .s_axi_wstrb,
      .s_axi_wvalid,
      .s_axi_wready,
      .s_axi_bresp,
      .s_axi_bvalid,
      .s_axi_bready,
      .s_axi_araddr,
      .s_axi_arvalid,
      .s_axi_arready,
      .s_axi_rdata,
      .s_axi_rresp,
      .s_axi_rvalid,
      .s_axi_rready,
      .req_o(req),
      .we_o(we),
      .addr_o(addr),
      .be_o(be),
      .wdata_o(wdata),
      .ack_i(ack),
      .rdata_i(rdata),
      .err_i(err)
  );

  logic [AXIL_DATA_WIDTH-1:0] mem[WORDS];
  logic [AXIL_ADDR_WIDTH-1:0] off;
  logic [IDX_WIDTH-1:0] idx;
  logic oor, start;

  assign off = addr - BASE_ADDR;
  assign idx = off[IDX_WIDTH+1:2];
  /* An offset past the end of this instance is reported instead of aliasing, which is what lets
     the DMA detect a result address that does not fit the memory. */
  assign oor = !soc_in_region(addr, BASE_ADDR, DMEM_BYTES);
  assign start = req && !ack;

  // Byte lanes come from the strobe, so addr[1:0] plays no part in choosing the word.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ack <= 1'b0;
      err <= 1'b0;
      rdata <= '0;
    end else begin
      ack <= start;
      err <= start && oor;
      if (start && !we && !oor) begin
        rdata <= mem[idx];
      end
    end
  end

  // The array has no reset: a memory is loaded by the testbench, and resetting every word would
  // dominate the synthesis result.
  always_ff @(posedge clk_i) begin
    if (start && we && !oor) begin
      for (int b = 0; b < AXIL_STRB_WIDTH; b++) begin
        if (be[b]) mem[idx][8*b+:8] <= wdata[8*b+:8];
      end
    end
  end

endmodule
