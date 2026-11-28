/* Checking side of the environment: reference model, scoreboard, functional coverage and the
   environment that ties them to the agent. */
package mm_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import soc_pkg::*;
  import mm_agent_pkg::*;
  import axil_agent_pkg::*;

  // What the verdict at the end of the simulation needs to know besides the report counts.
  class mm_run_status;
    static string test_name = "";
    static bit test_done = 1'b0;
    static int unsigned ops_compared = 0;
  endclass

  `include "mm_env_cfg.svh"
  `include "mm_ref_model.svh"
  `include "mm_scoreboard.svh"
  `include "mm_coverage.svh"
  `include "mm_autonomy_checker.svh"
  `include "mm_bus_coverage.svh"
  `include "mm_env.svh"

  /* Called from a final block of the harness, so it also runs after a fatal error. A pass needs a
     clean report, a test that reached its end and at least one operation compared: a test that
     checked nothing does not pass. */
  function automatic void mm_print_verdict();
    uvm_report_server rs = uvm_report_server::get_server();
    int errors = rs.get_severity_count(UVM_ERROR);
    int fatals = rs.get_severity_count(UVM_FATAL);
    if (errors == 0 && fatals == 0 && mm_run_status::test_done && mm_run_status::ops_compared > 0)
    begin
      $display("TEST PASS: %s UVM_ERROR=0 UVM_FATAL=0 ops=%0d", mm_run_status::test_name,
               mm_run_status::ops_compared);
    end else begin
      $display("TEST FAIL: %s UVM_ERROR=%0d UVM_FATAL=%0d ops=%0d finished=%0d",
               mm_run_status::test_name, errors, fatals, mm_run_status::ops_compared,
               mm_run_status::test_done);
    end
  endfunction

endpackage
