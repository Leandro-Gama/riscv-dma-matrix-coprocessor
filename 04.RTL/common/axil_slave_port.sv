/* AXI4-Lite slave front end. It turns the five channels into one simple request so that every
   slave in the system (data memory, accelerator adapter) implements the protocol once, here.
   The request holds addr/we/be/wdata stable while req_o is high; rdata_i and err_i are sampled
   in the cycle of ack_i. */
module axil_slave_port
  import soc_pkg::*;
#(
    parameter logic [1:0] ERR_RESP = RESP_SLVERR
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
    input  logic s_axi_rready,

    output logic req_o,
    output logic we_o,
    output logic [AXIL_ADDR_WIDTH-1:0] addr_o,
    output logic [AXIL_STRB_WIDTH-1:0] be_o,
    output logic [AXIL_DATA_WIDTH-1:0] wdata_o,
    input  logic ack_i,
    input  logic [AXIL_DATA_WIDTH-1:0] rdata_i,
    input  logic err_i
);

  logic cap_aw, cap_w, cap_ar, cap_rsp;
  logic [1:0] resp;

  axil_slave_port_ctrl u_ctrl (
      .clk_i,
      .rst_ni,
      .s_axi_awvalid,
      .s_axi_awready,
      .s_axi_wvalid,
      .s_axi_wready,
      .s_axi_bvalid,
      .s_axi_bready,
      .s_axi_arvalid,
      .s_axi_arready,
      .s_axi_rvalid,
      .s_axi_rready,
      .cap_aw_o(cap_aw),
      .cap_w_o(cap_w),
      .cap_ar_o(cap_ar),
      .cap_rsp_o(cap_rsp),
      .req_o,
      .we_o,
      .ack_i
  );

  axil_slave_port_dp #(
      .ERR_RESP(ERR_RESP)
  ) u_dp (
      .clk_i,
      .rst_ni,
      .cap_aw_i(cap_aw),
      .cap_w_i(cap_w),
      .cap_ar_i(cap_ar),
      .cap_rsp_i(cap_rsp),
      .s_axi_awaddr,
      .s_axi_wdata,
      .s_axi_wstrb,
      .s_axi_araddr,
      .s_axi_rdata,
      .resp_o(resp),
      .addr_o,
      .be_o,
      .wdata_o,
      .rdata_i,
      .err_i
  );

  assign s_axi_bresp = resp;
  assign s_axi_rresp = resp;

endmodule
