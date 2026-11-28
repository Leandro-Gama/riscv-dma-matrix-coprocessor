/* Passive AXI4-Lite agent: a monitor that turns the handshakes of one port into one transaction
   per access, published when the response completes. Address and data are kept in order, so it
   also follows a master with more than one access in flight. */
package axil_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class axil_item extends uvm_sequence_item;
    `uvm_object_utils(axil_item)

    string port;
    bit write;
    bit [31:0] addr;
    bit [31:0] data;
    bit [3:0] strb;
    bit [1:0] resp;
    longint unsigned start_cycle;
    longint unsigned end_cycle;

    function new(string name = "axil_item");
      super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
      axil_item t;
      super.do_copy(rhs);
      if (!$cast(t, rhs)) `uvm_fatal("AXIL_ITEM", "do_copy: not an axil_item")
      port = t.port;
      write = t.write;
      addr = t.addr;
      data = t.data;
      strb = t.strb;
      resp = t.resp;
      start_cycle = t.start_cycle;
      end_cycle = t.end_cycle;
    endfunction

    function string convert2string();
      return $sformatf("%s %s 0x%08h data=0x%08h strb=%b resp=%0d cycles %0d..%0d", port,
                       write ? "write" : "read ", addr, data, strb, resp, start_cycle,
                       end_cycle);
    endfunction

  endclass

  class axil_agent_cfg extends uvm_object;
    `uvm_object_utils(axil_agent_cfg)

    virtual axil_tap_if vif;
    string port = "axil";

    function new(string name = "axil_agent_cfg");
      super.new(name);
    endfunction

  endclass

  class axil_monitor extends uvm_monitor;
    `uvm_component_utils(axil_monitor)

    uvm_analysis_port #(axil_item) ap;
    axil_agent_cfg cfg;
    longint unsigned cycle;
    int unsigned writes;
    int unsigned reads;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db#(axil_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("AXIL_MON", "configuration 'cfg' not found")
      if (cfg.vif == null) `uvm_fatal("AXIL_MON", "cfg.vif is null")
    endfunction

    task run_phase(uvm_phase phase);
      axil_item aw_q[$], w_q[$], ar_q[$];
      virtual axil_tap_if vif = cfg.vif;
      forever begin
        @(vif.mon_cb);
        cycle++;
        if (vif.mon_cb.rst_n !== 1'b1) begin
          aw_q.delete();
          w_q.delete();
          ar_q.delete();
          continue;
        end
        if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
          axil_item t = axil_item::type_id::create("aw");
          t.port = cfg.port;
          t.write = 1'b1;
          t.addr = vif.mon_cb.awaddr;
          t.start_cycle = cycle;
          aw_q.push_back(t);
        end
        if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
          axil_item t = axil_item::type_id::create("w");
          t.data = vif.mon_cb.wdata;
          t.strb = vif.mon_cb.wstrb;
          w_q.push_back(t);
        end
        if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
          if (aw_q.size() == 0 || w_q.size() == 0) begin
            `uvm_error("AXIL_MON", $sformatf("%s: write response without address or data",
                                             cfg.port))
          end else begin
            axil_item t = aw_q.pop_front();
            axil_item d = w_q.pop_front();
            t.data = d.data;
            t.strb = d.strb;
            t.resp = vif.mon_cb.bresp;
            t.end_cycle = cycle;
            writes++;
            ap.write(t);
          end
        end
        if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
          axil_item t = axil_item::type_id::create("ar");
          t.port = cfg.port;
          t.write = 1'b0;
          t.addr = vif.mon_cb.araddr;
          t.start_cycle = cycle;
          ar_q.push_back(t);
        end
        if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
          if (ar_q.size() == 0) begin
            `uvm_error("AXIL_MON", $sformatf("%s: read data without address", cfg.port))
          end else begin
            axil_item t = ar_q.pop_front();
            t.data = vif.mon_cb.rdata;
            t.resp = vif.mon_cb.rresp;
            t.end_cycle = cycle;
            reads++;
            ap.write(t);
          end
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("AXIL_MON", $sformatf("%s: %0d writes, %0d reads", cfg.port, writes, reads),
                UVM_LOW)
    endfunction

  endclass

  class axil_agent extends uvm_agent;
    `uvm_component_utils(axil_agent)

    axil_monitor mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = axil_monitor::type_id::create("mon", this);
    endfunction

  endclass

endpackage
