/* Agent of one matrix multiplication: the transaction is a whole C = A x B, as the system does it
   seen from outside. The same agent serves the harness without CPU, where the driver plays the
   firmware on the bus, and the top level, where the firmware runs on the CPU. */
package mm_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import soc_pkg::*;

  // Parameter block of the test firmware, in 32-bit words from the start of the data memory.
  localparam logic [31:0] PB_BASE = DMEM_BASE;
  localparam int PB_CMD = 0;
  localparam int PB_ADDR_A = 1;
  localparam int PB_ADDR_B = 2;
  localparam int PB_ADDR_C = 3;
  localparam int PB_DIM_M = 4;
  localparam int PB_DIM_K = 5;
  localparam int PB_DIM_N = 6;
  localparam int PB_FLAGS = 7;
  localparam int PB_STATUS = 8;
  localparam int PB_DONE_COUNT = 9;
  localparam int PB_WORDS = 10;

  localparam int FLAG_IRQ_EN = 0;
  // Faults the firmware injects on request, so a test can prove that the checking catches them.
  localparam int FLAG_FAULT_DIM_K = 8;
  localparam int FLAG_FAULT_HANG = 9;

  localparam logic [31:0] REGION_A = 32'h1000_1000;
  localparam logic [31:0] REGION_B = 32'h1000_2000;
  localparam logic [31:0] REGION_C = 32'h1000_3000;
  localparam int REGION_BYTES = 4096;

  localparam logic [31:0] STATUS_OK = 32'h2;
  localparam logic [31:0] STATUS_FAIL = 32'h6;

  function automatic logic [31:0] pb_addr(input int word);
    return PB_BASE + 32'(4 * word);
  endfunction

  function automatic bit [31:0] width_mask(input int unsigned width);
    return (width >= 32) ? 32'hFFFF_FFFF : ((32'h1 << width) - 1);
  endfunction

  function automatic longint signed_value(input logic [31:0] raw, input int unsigned width);
    longint v = longint'(raw & width_mask(width));
    if (width < 64 && v[width-1]) v = v - (longint'(1) << width);
    return v;
  endfunction

  `include "mm_agent_cfg.svh"
  `include "mm_item.svh"
  `include "mm_sequencer.svh"
  `include "mm_driver_base.svh"
  `include "mm_driver_bfm.svh"
  `include "mm_driver_fw.svh"
  `include "mm_monitor.svh"
  `include "mm_agent.svh"
  `include "mm_vector_file.svh"
  `include "mm_seq_lib.svh"

endpackage
