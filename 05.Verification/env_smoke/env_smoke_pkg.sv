package env_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int WIDTH = 4;
  localparam int ENABLED_CYCLES = 20;

  typedef virtual env_smoke_if #(.WIDTH(WIDTH)) env_smoke_vif_t;

  class env_smoke_test extends uvm_test;
    `uvm_component_utils(env_smoke_test)

    env_smoke_vif_t vif;

    function new(string name = "env_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(env_smoke_vif_t)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface 'vif' not found in uvm_config_db")
      end
    endfunction

    task run_phase(uvm_phase phase);
      int unsigned expected;

      phase.raise_objection(this);
      vif.cb.rst_n <= 1'b0;
      vif.cb.en    <= 1'b0;
      repeat (2) @(vif.cb);
      vif.cb.rst_n <= 1'b1;
      @(vif.cb);
      vif.cb.en <= 1'b1;
      repeat (ENABLED_CYCLES) @(vif.cb);
      vif.cb.en <= 1'b0;
      @(vif.cb);

      expected = ENABLED_CYCLES % (1 << WIDTH);
      if (vif.cb.count !== expected) begin
        `uvm_error("SMOKE", $sformatf("count=%0d expected=%0d", vif.cb.count, expected))
      end else begin
        `uvm_info("SMOKE", $sformatf("count=%0d after %0d enabled cycles", vif.cb.count,
                                     ENABLED_CYCLES), UVM_NONE)
      end
      phase.drop_objection(this);
    endtask

  endclass

endpackage
