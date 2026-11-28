/* System rules no single block can check alone, written against the signals inside the
   subsystem and bound to it. A failure is a UVM error, so it counts in the verdict of the test. */
module soc_sva
  import soc_pkg::*;
(
    input logic clk_i,
    input logic rst_ni,
    input logic irq_o,

    input logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] mst_awaddr,
    input logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] mst_araddr,
    input logic [NUM_MASTERS-1:0] mst_awvalid,
    input logic [NUM_MASTERS-1:0] mst_wvalid,
    input logic [NUM_MASTERS-1:0] mst_arvalid,
    input logic [NUM_MASTERS-1:0] mst_bvalid,
    input logic [NUM_MASTERS-1:0] mst_rvalid,

    input logic [1:0][AXIL_ADDR_WIDTH-1:0] acc_awaddr,
    input logic [1:0][AXIL_ADDR_WIDTH-1:0] acc_araddr,
    input logic [1:0] acc_awvalid,
    input logic [1:0] acc_awready,
    input logic [1:0] acc_arvalid,
    input logic [1:0] acc_arready,

    input logic acc_load,
    input logic acc_start,
    input logic [AXIL_DATA_WIDTH-1:0] acc_status
);

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam logic [31:0] DATA_IN_BASE = ACCEL_BASE + ACCEL_OFF_DATA_IN;
  localparam logic [31:0] DATA_OUT_BASE = ACCEL_BASE + ACCEL_OFF_DATA_OUT;

  logic acc_idle;
  logic acc_done;
  logic cpu_in_accel;
  logic dma_quiet;

  assign acc_idle = (acc_status[1:0] == ACCEL_STATE_IDLE);
  assign acc_done = acc_status[ACCEL_STATUS_DONE_BIT];
  assign cpu_in_accel =
      (mst_awvalid[MST_CPU] && soc_in_region(mst_awaddr[MST_CPU], ACCEL_BASE, ACCEL_BYTES)) ||
      (mst_arvalid[MST_CPU] && soc_in_region(mst_araddr[MST_CPU], ACCEL_BASE, ACCEL_BYTES));
  assign dma_quiet = !mst_awvalid[MST_DMA] && !mst_wvalid[MST_DMA] && !mst_arvalid[MST_DMA] &&
      !mst_bvalid[MST_DMA] && !mst_rvalid[MST_DMA];

  default clocking cb @(posedge clk_i);
  endclocking
  default disable iff (!rst_ni);

  // A command reaches the accelerator only while it is idle.
  cmd_when_idle :
  assert property ((acc_load || acc_start) |-> acc_idle)
  else `uvm_error("SOC_SVA", "LOAD or START reached the accelerator while it was busy")

  // The DONE of the previous command is gone the cycle after a new one, so it is never read stale.
  done_cleared :
  assert property ((acc_load || acc_start) |=> !acc_done)
  else `uvm_error("SOC_SVA", "STATUS still showed DONE one cycle after a command")

  // The result buffer is only read with the accelerator idle, so a read never sees a half result.
  out_read_idle :
  assert property ((acc_arvalid[1] && acc_arready[1] && acc_araddr[1] >= DATA_OUT_BASE) |->
                   acc_idle)
  else `uvm_error("SOC_SVA", "DATA_OUT read while the accelerator was loading or computing")

  // The input buffer is only written with the accelerator idle.
  in_write_idle :
  assert property ((acc_awvalid[1] && acc_awready[1] && acc_awaddr[1] < DATA_OUT_BASE &&
                    acc_awaddr[1] >= DATA_IN_BASE) |-> acc_idle)
  else `uvm_error("SOC_SVA", "DATA_IN written while the accelerator was loading or computing")

  // When the interrupt rises the DMA has nothing left on the bus: the last write of C is done.
  irq_after_last_access :
  assert property ($rose(irq_o) |-> dma_quiet)
  else `uvm_error("SOC_SVA", "the interrupt rose while the DMA still had an access on the bus")

  // The CPU never addresses the accelerator: data moves by the DMA alone.
  cpu_not_in_accel :
  assert property (!cpu_in_accel)
  else `uvm_error("SOC_SVA", "the CPU addressed the accelerator")

endmodule
