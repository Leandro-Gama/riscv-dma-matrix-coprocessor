/* The monitor feeds three consumers over TLM: the reference model, which feeds the expected
   side of the scoreboard, the observed side of the scoreboard, and the coverage. The start of
   each operation also goes to the scoreboard, so an operation that never ends is caught.
   When the harness gives a view of the two bus masters, two passive bus agents feed the
   autonomy checker and the coverage of the bus. */
class mm_env extends uvm_env;
  `uvm_component_utils(mm_env)

  mm_env_cfg cfg;
  mm_agent agent;
  mm_ref_model ref_model;
  mm_scoreboard sb;
  mm_coverage cov;
  axil_agent cpu_bus;
  axil_agent dma_bus;
  mm_autonomy_checker autonomy;
  mm_bus_coverage bus_cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mm_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_ENV", "environment configuration 'cfg' not found")
    uvm_config_db#(mm_env_cfg)::set(this, "*", "cfg", cfg);
    uvm_config_db#(mm_agent_cfg)::set(this, "agent", "cfg", cfg.agent_cfg);
    agent = mm_agent::type_id::create("agent", this);
    ref_model = mm_ref_model::type_id::create("ref_model", this);
    sb = mm_scoreboard::type_id::create("sb", this);
    if (cfg.enable_cov) cov = mm_coverage::type_id::create("cov", this);
    if (cfg.cpu_tap_vif != null && cfg.dma_tap_vif != null) begin
      axil_agent_cfg cpu_cfg = axil_agent_cfg::type_id::create("cpu_bus_cfg");
      axil_agent_cfg dma_cfg = axil_agent_cfg::type_id::create("dma_bus_cfg");
      cpu_cfg.vif = cfg.cpu_tap_vif;
      cpu_cfg.port = "cpu";
      dma_cfg.vif = cfg.dma_tap_vif;
      dma_cfg.port = "dma";
      uvm_config_db#(axil_agent_cfg)::set(this, "cpu_bus*", "cfg", cpu_cfg);
      uvm_config_db#(axil_agent_cfg)::set(this, "dma_bus*", "cfg", dma_cfg);
      cpu_bus = axil_agent::type_id::create("cpu_bus", this);
      dma_bus = axil_agent::type_id::create("dma_bus", this);
      autonomy = mm_autonomy_checker::type_id::create("autonomy", this);
      if (cfg.enable_cov) bus_cov = mm_bus_coverage::type_id::create("bus_cov", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(ref_model.analysis_export);
    agent.mon.ap.connect(sb.act_fifo.analysis_export);
    agent.mon.start_ap.connect(sb.start_export);
    ref_model.ap.connect(sb.exp_fifo.analysis_export);
    if (cov != null) agent.mon.ap.connect(cov.analysis_export);
    if (autonomy != null) begin
      cpu_bus.mon.ap.connect(autonomy.cpu_export);
      dma_bus.mon.ap.connect(autonomy.dma_export);
      agent.mon.start_ap.connect(autonomy.start_export);
      agent.mon.ap.connect(autonomy.end_export);
    end
    if (bus_cov != null) begin
      cpu_bus.mon.ap.connect(bus_cov.cpu_export);
      dma_bus.mon.ap.connect(bus_cov.dma_export);
    end
  endfunction

endclass
