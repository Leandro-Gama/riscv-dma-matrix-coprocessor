/* Shared driver for the plain SystemVerilog testbenches. It wraps the master front end and
   exposes write/read as tasks, so every unit testbench calls the same two tasks instead of
   repeating the handshake. The request is raised on a falling edge and ack is sampled on falling
   edges, so the testbench never races the registers that sample on the rising edge. */
module axil_master_drv
  import soc_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

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
    output logic m_axi_rready
);

  logic req, we, ack;
  logic [AXIL_ADDR_WIDTH-1:0] addr;
  logic [AXIL_STRB_WIDTH-1:0] be;
  logic [AXIL_DATA_WIDTH-1:0] wdata, rdata;
  logic [1:0] resp;

  logic [AXIL_DATA_WIDTH-1:0] last_rdata;
  logic [1:0] last_resp;

  axil_master_port u_port (
      .clk_i,
      .rst_ni,
      .req_i(req),
      .we_i(we),
      .addr_i(addr),
      .be_i(be),
      .wdata_i(wdata),
      .ack_o(ack),
      .rdata_o(rdata),
      .resp_o(resp),
      .m_axi_awaddr,
      .m_axi_awvalid,
      .m_axi_awready,
      .m_axi_wdata,
      .m_axi_wstrb,
      .m_axi_wvalid,
      .m_axi_wready,
      .m_axi_bresp,
      .m_axi_bvalid,
      .m_axi_bready,
      .m_axi_araddr,
      .m_axi_arvalid,
      .m_axi_arready,
      .m_axi_rdata,
      .m_axi_rresp,
      .m_axi_rvalid,
      .m_axi_rready
  );

  initial begin
    req = 1'b0;
    we = 1'b0;
    addr = '0;
    be = '0;
    wdata = '0;
    last_rdata = '0;
    last_resp = '0;
  end

  task automatic write(input logic [AXIL_ADDR_WIDTH-1:0] a,
                       input logic [AXIL_DATA_WIDTH-1:0] d,
                       input logic [AXIL_STRB_WIDTH-1:0] strb);
    @(negedge clk_i);
    req   = 1'b1;
    we    = 1'b1;
    addr  = a;
    wdata = d;
    be    = strb;
    @(negedge clk_i);
    while (!ack) @(negedge clk_i);
    last_resp  = resp;
    last_rdata = '0;
    req = 1'b0;
    we  = 1'b0;
  endtask

  task automatic read(input logic [AXIL_ADDR_WIDTH-1:0] a);
    @(negedge clk_i);
    req  = 1'b1;
    we   = 1'b0;
    addr = a;
    @(negedge clk_i);
    while (!ack) @(negedge clk_i);
    last_resp  = resp;
    last_rdata = rdata;
    req = 1'b0;
  endtask

endmodule
