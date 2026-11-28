/* Top level of the system: the CPU, its instruction memory and the subsystem (interconnect, data
   memory, DMA, accelerator). The instruction memory sits outside the bus, on the instruction port
   of the CPU only, so fetching never competes with the DMA. The CPU is the module cpu_top with the
   ports of the interface contract; the file list decides whether that is the core or a model. */
module soc_top
  import soc_pkg::*;
#(
    parameter int ARRAY_SIZE = 4,
    parameter int DATA_WIDTH = 8,
    parameter int DMEM_BYTES = DMEM_BYTES_DEFAULT,
    parameter int IMEM_BYTES = IMEM_BYTES_DEFAULT,
    parameter logic [0:0] ARB_POLICY = ARB_DMA_PRIORITY
) (
    input  logic clk_i,
    input  logic rst_ni,
    output logic irq_o
);

  logic [AXIL_ADDR_WIDTH-1:0] imem_addr;
  logic [AXIL_DATA_WIDTH-1:0] imem_rdata;

  logic [AXIL_ADDR_WIDTH-1:0] cpu_awaddr, cpu_araddr;
  logic [AXIL_DATA_WIDTH-1:0] cpu_wdata, cpu_rdata;
  logic [AXIL_STRB_WIDTH-1:0] cpu_wstrb;
  logic [1:0] cpu_bresp, cpu_rresp;
  logic cpu_awvalid, cpu_awready, cpu_wvalid, cpu_wready, cpu_bvalid, cpu_bready;
  logic cpu_arvalid, cpu_arready, cpu_rvalid, cpu_rready;

  mem_instr #(
      .IMEM_BYTES(IMEM_BYTES)
  ) u_imem (
      .addr_i (imem_addr),
      .rdata_o(imem_rdata)
  );

  cpu_top u_cpu (
      .clk_i,
      .rst_ni,
      .imem_addr_o  (imem_addr),
      .imem_rdata_i (imem_rdata),
      .m_axi_awaddr (cpu_awaddr),
      .m_axi_awvalid(cpu_awvalid),
      .m_axi_awready(cpu_awready),
      .m_axi_wdata  (cpu_wdata),
      .m_axi_wstrb  (cpu_wstrb),
      .m_axi_wvalid (cpu_wvalid),
      .m_axi_wready (cpu_wready),
      .m_axi_bresp  (cpu_bresp),
      .m_axi_bvalid (cpu_bvalid),
      .m_axi_bready (cpu_bready),
      .m_axi_araddr (cpu_araddr),
      .m_axi_arvalid(cpu_arvalid),
      .m_axi_arready(cpu_arready),
      .m_axi_rdata  (cpu_rdata),
      .m_axi_rresp  (cpu_rresp),
      .m_axi_rvalid (cpu_rvalid),
      .m_axi_rready (cpu_rready),
      .irq_i        (irq_o)
  );

  soc_subsys #(
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .DMEM_BYTES(DMEM_BYTES),
      .ARB_POLICY(ARB_POLICY)
  ) u_subsys (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr (cpu_awaddr),
      .s_axi_awvalid(cpu_awvalid),
      .s_axi_awready(cpu_awready),
      .s_axi_wdata  (cpu_wdata),
      .s_axi_wstrb  (cpu_wstrb),
      .s_axi_wvalid (cpu_wvalid),
      .s_axi_wready (cpu_wready),
      .s_axi_bresp  (cpu_bresp),
      .s_axi_bvalid (cpu_bvalid),
      .s_axi_bready (cpu_bready),
      .s_axi_araddr (cpu_araddr),
      .s_axi_arvalid(cpu_arvalid),
      .s_axi_arready(cpu_arready),
      .s_axi_rdata  (cpu_rdata),
      .s_axi_rresp  (cpu_rresp),
      .s_axi_rvalid (cpu_rvalid),
      .s_axi_rready (cpu_rready),
      .irq_o
  );

endmodule
