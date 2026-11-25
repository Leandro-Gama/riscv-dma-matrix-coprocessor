/* AXI4-Lite master front end. A block drives one simple request (req/we/addr/be/wdata held until
   ack_o) and this module runs the five channels for it, so the DMA and the CPU do not implement
   the protocol themselves. rdata_o and resp_o are valid in the cycle of ack_o. */
module axil_master_port
  import soc_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic req_i,
    input  logic we_i,
    input  logic [AXIL_ADDR_WIDTH-1:0] addr_i,
    input  logic [AXIL_STRB_WIDTH-1:0] be_i,
    input  logic [AXIL_DATA_WIDTH-1:0] wdata_i,
    output logic ack_o,
    output logic [AXIL_DATA_WIDTH-1:0] rdata_o,
    output logic [1:0] resp_o,

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

  logic cap_req, resp_sel_wr;

  axil_master_port_ctrl u_ctrl (
      .clk_i,
      .rst_ni,
      .req_i,
      .we_i,
      .ack_o,
      .s_axi_awvalid(m_axi_awvalid),
      .s_axi_awready(m_axi_awready),
      .s_axi_wvalid(m_axi_wvalid),
      .s_axi_wready(m_axi_wready),
      .s_axi_bvalid(m_axi_bvalid),
      .s_axi_bready(m_axi_bready),
      .s_axi_arvalid(m_axi_arvalid),
      .s_axi_arready(m_axi_arready),
      .s_axi_rvalid(m_axi_rvalid),
      .s_axi_rready(m_axi_rready),
      .cap_req_o(cap_req),
      .resp_sel_wr_o(resp_sel_wr)
  );

  axil_master_port_dp u_dp (
      .clk_i,
      .rst_ni,
      .cap_req_i(cap_req),
      .addr_i,
      .be_i,
      .wdata_i,
      .s_axi_awaddr(m_axi_awaddr),
      .s_axi_wdata(m_axi_wdata),
      .s_axi_wstrb(m_axi_wstrb),
      .s_axi_araddr(m_axi_araddr)
  );

  assign rdata_o = m_axi_rdata;
  assign resp_o = resp_sel_wr ? m_axi_bresp : m_axi_rresp;

endmodule
