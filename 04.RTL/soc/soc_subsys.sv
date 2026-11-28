/* Everything of the system except the CPU and its instruction memory: interconnect, data memory,
   DMA and accelerator. The data port of the CPU comes in as an AXI4-Lite slave port, so a bus
   functional model can stand in for the CPU while the core does not exist, and the top level only
   adds the core and the instruction memory around this block.

   The accelerator is a single slave of the interconnect. A local decoder right behind that port
   sends CTRL/STATUS to the adapter and the buffers to the AXI4-Lite port of the accelerator,
   which decodes them itself (decision 0003). */
module soc_subsys
  import soc_pkg::*;
#(
    parameter int ARRAY_SIZE = 4,
    parameter int DATA_WIDTH = 8,
    parameter int DMEM_BYTES = DMEM_BYTES_DEFAULT,
    parameter logic [0:0] ARB_POLICY = ARB_DMA_PRIORITY
) (
    input logic clk_i,
    input logic rst_ni,

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

    output logic irq_o
);

  localparam int CSR_BYTES = int'(ACCEL_OFF_DATA_IN);
  localparam logic [AXIL_ADDR_WIDTH-1:0] ACCEL_BUF_BASE = ACCEL_BASE + ACCEL_OFF_DATA_IN;
  localparam logic [AXIL_ADDR_WIDTH-1:0] ACCEL_OUT_BASE = ACCEL_BASE + ACCEL_OFF_DATA_OUT;

  logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] mst_awaddr, mst_araddr;
  logic [NUM_MASTERS-1:0][AXIL_DATA_WIDTH-1:0] mst_wdata, mst_rdata;
  logic [NUM_MASTERS-1:0][AXIL_STRB_WIDTH-1:0] mst_wstrb;
  logic [NUM_MASTERS-1:0][1:0] mst_bresp, mst_rresp;
  logic [NUM_MASTERS-1:0] mst_awvalid, mst_awready, mst_wvalid, mst_wready;
  logic [NUM_MASTERS-1:0] mst_bvalid, mst_bready, mst_arvalid, mst_arready;
  logic [NUM_MASTERS-1:0] mst_rvalid, mst_rready;

  logic [NUM_SLAVES-1:0][AXIL_ADDR_WIDTH-1:0] slv_awaddr, slv_araddr;
  logic [NUM_SLAVES-1:0][AXIL_DATA_WIDTH-1:0] slv_wdata, slv_rdata;
  logic [NUM_SLAVES-1:0][AXIL_STRB_WIDTH-1:0] slv_wstrb;
  logic [NUM_SLAVES-1:0][1:0] slv_bresp, slv_rresp;
  logic [NUM_SLAVES-1:0] slv_awvalid, slv_awready, slv_wvalid, slv_wready;
  logic [NUM_SLAVES-1:0] slv_bvalid, slv_bready, slv_arvalid, slv_arready;
  logic [NUM_SLAVES-1:0] slv_rvalid, slv_rready;

  logic [2:0] dma_awprot, dma_arprot;

  // Local decoder of the accelerator region: 0 = CTRL/STATUS (adapter), 1 = buffers.
  logic [1:0][AXIL_ADDR_WIDTH-1:0] acc_awaddr, acc_araddr;
  logic [1:0][AXIL_DATA_WIDTH-1:0] acc_wdata, acc_rdata;
  logic [1:0][AXIL_STRB_WIDTH-1:0] acc_wstrb;
  logic [1:0][2:0] acc_awprot, acc_arprot;
  logic [1:0][1:0] acc_bresp, acc_rresp;
  logic [1:0] acc_awvalid, acc_awready, acc_wvalid, acc_wready;
  logic [1:0] acc_bvalid, acc_bready, acc_arvalid, acc_arready;
  logic [1:0] acc_rvalid, acc_rready;

  logic acc_mode, acc_load, acc_start, acc_clr_error;
  logic shell_req;
  wire [AXIL_DATA_WIDTH-1:0] acc_status;

  assign mst_awaddr[MST_CPU] = s_axi_awaddr;
  assign mst_awvalid[MST_CPU] = s_axi_awvalid;
  assign s_axi_awready = mst_awready[MST_CPU];
  assign mst_wdata[MST_CPU] = s_axi_wdata;
  assign mst_wstrb[MST_CPU] = s_axi_wstrb;
  assign mst_wvalid[MST_CPU] = s_axi_wvalid;
  assign s_axi_wready = mst_wready[MST_CPU];
  assign s_axi_bresp = mst_bresp[MST_CPU];
  assign s_axi_bvalid = mst_bvalid[MST_CPU];
  assign mst_bready[MST_CPU] = s_axi_bready;
  assign mst_araddr[MST_CPU] = s_axi_araddr;
  assign mst_arvalid[MST_CPU] = s_axi_arvalid;
  assign s_axi_arready = mst_arready[MST_CPU];
  assign s_axi_rdata = mst_rdata[MST_CPU];
  assign s_axi_rresp = mst_rresp[MST_CPU];
  assign s_axi_rvalid = mst_rvalid[MST_CPU];
  assign mst_rready[MST_CPU] = s_axi_rready;

  soc_axil_xbar #(
      .DMEM_BYTES(DMEM_BYTES),
      .ARB_POLICY(ARB_POLICY)
  ) u_xbar (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr (mst_awaddr),
      .s_axi_awvalid(mst_awvalid),
      .s_axi_awready(mst_awready),
      .s_axi_wdata  (mst_wdata),
      .s_axi_wstrb  (mst_wstrb),
      .s_axi_wvalid (mst_wvalid),
      .s_axi_wready (mst_wready),
      .s_axi_bresp  (mst_bresp),
      .s_axi_bvalid (mst_bvalid),
      .s_axi_bready (mst_bready),
      .s_axi_araddr (mst_araddr),
      .s_axi_arvalid(mst_arvalid),
      .s_axi_arready(mst_arready),
      .s_axi_rdata  (mst_rdata),
      .s_axi_rresp  (mst_rresp),
      .s_axi_rvalid (mst_rvalid),
      .s_axi_rready (mst_rready),
      .m_axi_awaddr (slv_awaddr),
      .m_axi_awvalid(slv_awvalid),
      .m_axi_awready(slv_awready),
      .m_axi_wdata  (slv_wdata),
      .m_axi_wstrb  (slv_wstrb),
      .m_axi_wvalid (slv_wvalid),
      .m_axi_wready (slv_wready),
      .m_axi_bresp  (slv_bresp),
      .m_axi_bvalid (slv_bvalid),
      .m_axi_bready (slv_bready),
      .m_axi_araddr (slv_araddr),
      .m_axi_arvalid(slv_arvalid),
      .m_axi_arready(slv_arready),
      .m_axi_rdata  (slv_rdata),
      .m_axi_rresp  (slv_rresp),
      .m_axi_rvalid (slv_rvalid),
      .m_axi_rready (slv_rready)
  );

  mem_data #(
      .DMEM_BYTES(DMEM_BYTES)
  ) u_dmem (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr (slv_awaddr[SLV_DMEM]),
      .s_axi_awvalid(slv_awvalid[SLV_DMEM]),
      .s_axi_awready(slv_awready[SLV_DMEM]),
      .s_axi_wdata  (slv_wdata[SLV_DMEM]),
      .s_axi_wstrb  (slv_wstrb[SLV_DMEM]),
      .s_axi_wvalid (slv_wvalid[SLV_DMEM]),
      .s_axi_wready (slv_wready[SLV_DMEM]),
      .s_axi_bresp  (slv_bresp[SLV_DMEM]),
      .s_axi_bvalid (slv_bvalid[SLV_DMEM]),
      .s_axi_bready (slv_bready[SLV_DMEM]),
      .s_axi_araddr (slv_araddr[SLV_DMEM]),
      .s_axi_arvalid(slv_arvalid[SLV_DMEM]),
      .s_axi_arready(slv_arready[SLV_DMEM]),
      .s_axi_rdata  (slv_rdata[SLV_DMEM]),
      .s_axi_rresp  (slv_rresp[SLV_DMEM]),
      .s_axi_rvalid (slv_rvalid[SLV_DMEM]),
      .s_axi_rready (slv_rready[SLV_DMEM])
  );

  // The interconnect carries no protection attribute, so the DMA sees an unprivileged access.
  dma_top #(
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .ACCEL_BASE(ACCEL_BASE)
  ) u_dma (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr (slv_awaddr[SLV_DMAREG]),
      .s_axi_awprot (3'b000),
      .s_axi_awvalid(slv_awvalid[SLV_DMAREG]),
      .s_axi_awready(slv_awready[SLV_DMAREG]),
      .s_axi_wdata  (slv_wdata[SLV_DMAREG]),
      .s_axi_wstrb  (slv_wstrb[SLV_DMAREG]),
      .s_axi_wvalid (slv_wvalid[SLV_DMAREG]),
      .s_axi_wready (slv_wready[SLV_DMAREG]),
      .s_axi_bresp  (slv_bresp[SLV_DMAREG]),
      .s_axi_bvalid (slv_bvalid[SLV_DMAREG]),
      .s_axi_bready (slv_bready[SLV_DMAREG]),
      .s_axi_araddr (slv_araddr[SLV_DMAREG]),
      .s_axi_arprot (3'b000),
      .s_axi_arvalid(slv_arvalid[SLV_DMAREG]),
      .s_axi_arready(slv_arready[SLV_DMAREG]),
      .s_axi_rdata  (slv_rdata[SLV_DMAREG]),
      .s_axi_rresp  (slv_rresp[SLV_DMAREG]),
      .s_axi_rvalid (slv_rvalid[SLV_DMAREG]),
      .s_axi_rready (slv_rready[SLV_DMAREG]),
      .m_axi_awaddr (mst_awaddr[MST_DMA]),
      .m_axi_awprot (dma_awprot),
      .m_axi_awvalid(mst_awvalid[MST_DMA]),
      .m_axi_awready(mst_awready[MST_DMA]),
      .m_axi_wdata  (mst_wdata[MST_DMA]),
      .m_axi_wstrb  (mst_wstrb[MST_DMA]),
      .m_axi_wvalid (mst_wvalid[MST_DMA]),
      .m_axi_wready (mst_wready[MST_DMA]),
      .m_axi_bresp  (mst_bresp[MST_DMA]),
      .m_axi_bvalid (mst_bvalid[MST_DMA]),
      .m_axi_bready (mst_bready[MST_DMA]),
      .m_axi_araddr (mst_araddr[MST_DMA]),
      .m_axi_arprot (dma_arprot),
      .m_axi_arvalid(mst_arvalid[MST_DMA]),
      .m_axi_arready(mst_arready[MST_DMA]),
      .m_axi_rdata  (mst_rdata[MST_DMA]),
      .m_axi_rresp  (mst_rresp[MST_DMA]),
      .m_axi_rvalid (mst_rvalid[MST_DMA]),
      .m_axi_rready (mst_rready[MST_DMA]),
      .irq_o
  );

  soc_axil_decoder #(
      .NUM_SLAVES(2),
      .SLAVE_BASE({ACCEL_BUF_BASE, ACCEL_BASE}),
      .SLAVE_SIZE({32'(ACCEL_BYTES - CSR_BYTES), 32'(CSR_BYTES)})
  ) u_accel_dec (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr (slv_awaddr[SLV_ACCEL]),
      .s_axi_awprot (3'b000),
      .s_axi_awvalid(slv_awvalid[SLV_ACCEL]),
      .s_axi_awready(slv_awready[SLV_ACCEL]),
      .s_axi_wdata  (slv_wdata[SLV_ACCEL]),
      .s_axi_wstrb  (slv_wstrb[SLV_ACCEL]),
      .s_axi_wvalid (slv_wvalid[SLV_ACCEL]),
      .s_axi_wready (slv_wready[SLV_ACCEL]),
      .s_axi_bresp  (slv_bresp[SLV_ACCEL]),
      .s_axi_bvalid (slv_bvalid[SLV_ACCEL]),
      .s_axi_bready (slv_bready[SLV_ACCEL]),
      .s_axi_araddr (slv_araddr[SLV_ACCEL]),
      .s_axi_arprot (3'b000),
      .s_axi_arvalid(slv_arvalid[SLV_ACCEL]),
      .s_axi_arready(slv_arready[SLV_ACCEL]),
      .s_axi_rdata  (slv_rdata[SLV_ACCEL]),
      .s_axi_rresp  (slv_rresp[SLV_ACCEL]),
      .s_axi_rvalid (slv_rvalid[SLV_ACCEL]),
      .s_axi_rready (slv_rready[SLV_ACCEL]),
      .m_axi_awaddr (acc_awaddr),
      .m_axi_awprot (acc_awprot),
      .m_axi_awvalid(acc_awvalid),
      .m_axi_awready(acc_awready),
      .m_axi_wdata  (acc_wdata),
      .m_axi_wstrb  (acc_wstrb),
      .m_axi_wvalid (acc_wvalid),
      .m_axi_wready (acc_wready),
      .m_axi_bresp  (acc_bresp),
      .m_axi_bvalid (acc_bvalid),
      .m_axi_bready (acc_bready),
      .m_axi_araddr (acc_araddr),
      .m_axi_arprot (acc_arprot),
      .m_axi_arvalid(acc_arvalid),
      .m_axi_arready(acc_arready),
      .m_axi_rdata  (acc_rdata),
      .m_axi_rresp  (acc_rresp),
      .m_axi_rvalid (acc_rvalid),
      .m_axi_rready (acc_rready)
  );

  /* The decoder never routes a buffer address to the adapter, so its shell side stays idle. It is
     still tied to answer at once with an error, so a stray request would fail instead of hang. */
  accel_adapter #(
      .BASE_ADDR(ACCEL_BASE),
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .RESULT_WIDTH(DATA_WIDTH)
  ) u_adapter (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr (acc_awaddr[0]),
      .s_axi_awvalid(acc_awvalid[0]),
      .s_axi_awready(acc_awready[0]),
      .s_axi_wdata  (acc_wdata[0]),
      .s_axi_wstrb  (acc_wstrb[0]),
      .s_axi_wvalid (acc_wvalid[0]),
      .s_axi_wready (acc_wready[0]),
      .s_axi_bresp  (acc_bresp[0]),
      .s_axi_bvalid (acc_bvalid[0]),
      .s_axi_bready (acc_bready[0]),
      .s_axi_araddr (acc_araddr[0]),
      .s_axi_arvalid(acc_arvalid[0]),
      .s_axi_arready(acc_arready[0]),
      .s_axi_rdata  (acc_rdata[0]),
      .s_axi_rresp  (acc_rresp[0]),
      .s_axi_rvalid (acc_rvalid[0]),
      .s_axi_rready (acc_rready[0]),
      .mode_o       (acc_mode),
      .load_o       (acc_load),
      .start_o      (acc_start),
      .clr_error_o  (acc_clr_error),
      .status_i     (acc_status),
      .data_req_o   (shell_req),
      .data_we_o    (),
      .data_addr_o  (),
      .data_wdata_o (),
      .data_rdata_i ('0),
      .data_ready_i (shell_req),
      .data_error_i (1'b1)
  );

  axil_if acc_bus (
      .clk  (clk_i),
      .rst_n(rst_ni)
  );

  assign acc_bus.awaddr = acc_awaddr[1];
  assign acc_bus.awprot = acc_awprot[1];
  assign acc_bus.awvalid = acc_awvalid[1];
  assign acc_bus.wdata = acc_wdata[1];
  assign acc_bus.wstrb = acc_wstrb[1];
  assign acc_bus.wvalid = acc_wvalid[1];
  assign acc_bus.bready = acc_bready[1];
  assign acc_bus.araddr = acc_araddr[1];
  assign acc_bus.arprot = acc_arprot[1];
  assign acc_bus.arvalid = acc_arvalid[1];
  assign acc_bus.rready = acc_rready[1];
  assign acc_awready[1] = acc_bus.awready;
  assign acc_wready[1] = acc_bus.wready;
  assign acc_bresp[1] = acc_bus.bresp;
  assign acc_bvalid[1] = acc_bus.bvalid;
  assign acc_arready[1] = acc_bus.arready;
  assign acc_rdata[1] = acc_bus.rdata;
  assign acc_rresp[1] = acc_bus.rresp;
  assign acc_rvalid[1] = acc_bus.rvalid;

  accel_top #(
      .N(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .DATA_IN_BASE(ACCEL_BUF_BASE),
      .DATA_OUT_BASE(ACCEL_OUT_BASE)
  ) u_accel (
      .clk_i,
      .rst_ni,
      .mode_i     (acc_mode),
      .load_i     (acc_load),
      .start_i    (acc_start),
      .clr_error_i(acc_clr_error),
      .status_o   (acc_status),
      .s_axi      (acc_bus)
  );

endmodule
