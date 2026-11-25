/* The request rules the interface contract states for the accelerator shell, as assertions. They
   watch the adapter side, which is ours, so the real accelerator can be dropped in later and the
   same rules keep being checked. */
module accel_shell_checker
  import soc_pkg::*;
(
    input logic clk_i,
    input logic rst_ni,
    input logic data_req,
    input logic data_we,
    input logic [15:0] data_addr,
    input logic [AXIL_DATA_WIDTH-1:0] data_wdata,
    input logic data_ready,
    input logic load,
    input logic start,
    input logic clr_error
);

  default clocking cb @(posedge clk_i);
  endclocking
  default disable iff (!rst_ni);

  // A request stays up, unchanged, until the shell says it is done.
  req_held : assert property (data_req && !data_ready |=> data_req &&
                              $stable({data_we, data_addr, data_wdata}));

  // Done without a request means the shell answered something nobody asked for.
  ready_needs_req : assert property (data_ready |-> data_req);

  // Each command bit is a pulse of exactly one cycle, never a level.
  load_pulse : assert property (load |=> !load);
  start_pulse : assert property (start |=> !start);
  clr_error_pulse : assert property (clr_error |=> !clr_error);

endmodule
