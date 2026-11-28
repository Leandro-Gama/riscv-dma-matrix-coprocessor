`timescale 1ns / 1ps

`ifndef MM_ARRAY_SIZE
`define MM_ARRAY_SIZE 4
`endif
`ifndef MM_DATA_WIDTH
`define MM_DATA_WIDTH 8
`endif

/* Harness without CPU: the DUT is the subsystem (interconnect, data memory, DMA, accelerator) and
   a bus functional model takes the place of the data port of the CPU. The UVM environment is the
   same as on the top level; only the driver changes, by factory override. */
module tb_subsys;

  import uvm_pkg::*;
  import mm_test_pkg::*;

  localparam int ARRAY_SIZE = `MM_ARRAY_SIZE;
  localparam int DATA_WIDTH = `MM_DATA_WIDTH;
  localparam int DMEM_BYTES = soc_pkg::DMEM_BYTES_DEFAULT;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  sys_if sys (.clk(clk));
  axil_bfm_if bfm (
      .clk  (clk),
      .rst_n(sys.rst_n)
  );

  soc_subsys #(
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .DMEM_BYTES(DMEM_BYTES)
  ) u_dut (
      .clk_i        (clk),
      .rst_ni       (sys.rst_n),
      .s_axi_awaddr (bfm.awaddr),
      .s_axi_awvalid(bfm.awvalid),
      .s_axi_awready(bfm.awready),
      .s_axi_wdata  (bfm.wdata),
      .s_axi_wstrb  (bfm.wstrb),
      .s_axi_wvalid (bfm.wvalid),
      .s_axi_wready (bfm.wready),
      .s_axi_bresp  (bfm.bresp),
      .s_axi_bvalid (bfm.bvalid),
      .s_axi_bready (bfm.bready),
      .s_axi_araddr (bfm.araddr),
      .s_axi_arvalid(bfm.arvalid),
      .s_axi_arready(bfm.arready),
      .s_axi_rdata  (bfm.rdata),
      .s_axi_rresp  (bfm.rresp),
      .s_axi_rvalid (bfm.rvalid),
      .s_axi_rready (bfm.rready),
      .irq_o        (sys.irq)
  );

  // Passive views of the two masters, for the bus agents, the latency and the autonomy check.
  axil_tap_if cpu_tap (
      .clk  (clk),
      .rst_n(sys.rst_n)
  );
  axil_tap_if dma_tap (
      .clk  (clk),
      .rst_n(sys.rst_n)
  );

  `MM_TAP(cpu_tap, bfm., )
  `MM_TAP(dma_tap, u_dut.mst_, [soc_pkg::MST_DMA])

  initial begin
    uvm_config_db#(virtual sys_if)::set(null, "uvm_test_top", "sys_vif", sys);
    uvm_config_db#(virtual axil_tap_if)::set(null, "uvm_test_top", "cpu_tap_vif", cpu_tap);
    uvm_config_db#(virtual axil_tap_if)::set(null, "uvm_test_top", "dma_tap_vif", dma_tap);
    uvm_config_db#(virtual axil_bfm_if)::set(null, "uvm_test_top", "bfm_vif", bfm);
    uvm_config_db#(bit)::set(null, "uvm_test_top", "has_cpu", 1'b0);
    uvm_config_db#(int)::set(null, "uvm_test_top", "array_size", ARRAY_SIZE);
    uvm_config_db#(int)::set(null, "uvm_test_top", "data_width", DATA_WIDTH);
    uvm_config_db#(int)::set(null, "uvm_test_top", "dmem_bytes", DMEM_BYTES);
    run_test();
  end

  final mm_env_pkg::mm_print_verdict();

endmodule
