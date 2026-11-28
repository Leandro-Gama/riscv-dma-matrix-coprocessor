class mm_agent extends uvm_agent;
  `uvm_component_utils(mm_agent)

  mm_agent_cfg cfg;
  mm_sequencer sqr;
  mm_driver_base drv;
  mm_monitor mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mm_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_AGENT", "agent configuration 'cfg' not found")
    uvm_config_db#(mm_agent_cfg)::set(this, "*", "cfg", cfg);
    mon = mm_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = mm_sequencer::type_id::create("sqr", this);
      // The test decides, by factory override, which of the two drivers this becomes.
      drv = mm_driver_base::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr.cfg = cfg;
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass
