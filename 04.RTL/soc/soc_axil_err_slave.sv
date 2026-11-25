/* Answers the addresses that belong to no slave. It reuses the slave front end with the decode
   error code, so an unmapped access gets a response in the same number of cycles as a real slave
   instead of hanging the master forever. */
module soc_axil_err_slave
  import soc_pkg::*;
(
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

  logic req, we;
  logic [AXIL_ADDR_WIDTH-1:0] addr;
  logic [AXIL_STRB_WIDTH-1:0] be;
  logic [AXIL_DATA_WIDTH-1:0] wdata;

  axil_slave_port #(
      .ERR_RESP(RESP_DECERR)
  ) u_port (
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
      // The access is refused as soon as it is seen, so there is nothing to wait for.
      .ack_i(req),
      .rdata_i('0),
      .err_i(1'b1)
  );

  logic unused;
  assign unused = we | (|addr) | (|be) | (|wdata);

endmodule
