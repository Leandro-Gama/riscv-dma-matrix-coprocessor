`timescale 1ns / 1ps

`ifndef MM_ARRAY_SIZE
`define MM_ARRAY_SIZE 4
`endif
`ifndef MM_DATA_WIDTH
`define MM_DATA_WIDTH 8
`endif

/* Harness of the top level: the DUT is soc_top, whose only pins are clock, reset and interrupt.
   The CPU runs the test firmware, which alone writes the registers of the DMA; the environment
   only reaches the memories, by backdoor through sys_if. */
module tb_soc;

  import uvm_pkg::*;
  import mm_test_pkg::*;

  localparam int ARRAY_SIZE = `MM_ARRAY_SIZE;
  localparam int DATA_WIDTH = `MM_DATA_WIDTH;
  localparam int DMEM_BYTES = soc_pkg::DMEM_BYTES_DEFAULT;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  sys_if sys (.clk(clk));

  soc_top #(
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .DMEM_BYTES(DMEM_BYTES)
  ) u_dut (
      .clk_i (clk),
      .rst_ni(sys.rst_n),
      .irq_o (sys.irq)
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

  `MM_TAP(cpu_tap, u_dut.cpu_, )
  `MM_TAP(dma_tap, u_dut.u_subsys.mst_, [soc_pkg::MST_DMA])

  initial begin
    uvm_config_db#(virtual sys_if)::set(null, "uvm_test_top", "sys_vif", sys);
    uvm_config_db#(virtual axil_tap_if)::set(null, "uvm_test_top", "cpu_tap_vif", cpu_tap);
    uvm_config_db#(virtual axil_tap_if)::set(null, "uvm_test_top", "dma_tap_vif", dma_tap);
    uvm_config_db#(bit)::set(null, "uvm_test_top", "has_cpu", 1'b1);
    uvm_config_db#(int)::set(null, "uvm_test_top", "array_size", ARRAY_SIZE);
    uvm_config_db#(int)::set(null, "uvm_test_top", "data_width", DATA_WIDTH);
    uvm_config_db#(int)::set(null, "uvm_test_top", "dmem_bytes", DMEM_BYTES);
    run_test();
  end

  final mm_env_pkg::mm_print_verdict();

endmodule
