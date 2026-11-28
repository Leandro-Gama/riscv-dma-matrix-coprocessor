/* Builds the environment from what the harness publishes and from the command line, and picks
   the driver by factory override: the bus driver when the harness has no CPU, the firmware
   driver when it has one. Derived tests only choose the sequence and its knobs, so every test
   runs on both harnesses unchanged.

   Command line: +NUM_OPS=<n> +MAX_DIM=<n> +OP_TIMEOUT=<cycles> +C_WIDTH=<bits> +MM_COV
   +FAULT=fw_dim_k|c_flip|hang */
class mm_base_test extends uvm_test;
  `uvm_component_utils(mm_base_test)

  mm_env env;
  mm_env_cfg cfg;
  int unsigned num_ops = 1;
  time global_timeout = 20ms;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    mm_agent_cfg ac;
    int value;
    bit has_cpu = 1'b0;

    super.build_phase(phase);
    cfg = mm_env_cfg::type_id::create("cfg");
    ac = mm_agent_cfg::type_id::create("agent_cfg");
    cfg.agent_cfg = ac;

    if (!uvm_config_db#(virtual sys_if)::get(this, "", "sys_vif", ac.sys_vif))
      `uvm_fatal("MM_TEST", "the harness did not publish 'sys_vif'")
    void'(uvm_config_db#(virtual axil_bfm_if)::get(this, "", "bfm_vif", ac.bfm_vif));
    void'(uvm_config_db#(virtual axil_tap_if)::get(this, "", "cpu_tap_vif", cfg.cpu_tap_vif));
    void'(uvm_config_db#(virtual axil_tap_if)::get(this, "", "dma_tap_vif", cfg.dma_tap_vif));
    ac.cpu_tap_vif = cfg.cpu_tap_vif;
    void'(uvm_config_db#(bit)::get(this, "", "has_cpu", has_cpu));
    if (uvm_config_db#(int)::get(this, "", "array_size", value)) ac.array_size = value;
    if (uvm_config_db#(int)::get(this, "", "data_width", value)) ac.data_width = value;
    if (uvm_config_db#(int)::get(this, "", "dmem_bytes", value)) ac.dmem_bytes = value;
    ac.has_cpu = has_cpu;
    ac.max_dim = 2 * ac.array_size + 3;
    cfg.c_width = ac.data_width;

    configure(cfg);

    if ($value$plusargs("NUM_OPS=%d", value)) num_ops = value;
    if ($value$plusargs("MAX_DIM=%d", value)) ac.max_dim = value;
    if ($value$plusargs("OP_TIMEOUT=%d", value)) ac.op_timeout_cycles = value;
    if ($value$plusargs("C_WIDTH=%d", value)) cfg.c_width = value;
    if ($test$plusargs("MM_COV")) cfg.enable_cov = 1'b1;
    void'($value$plusargs("FAULT=%s", ac.fault));
    void'($value$plusargs("VECTORS=%s", ac.vectors_file));
    ac.c_width = cfg.c_width;
    if (!ac.fault_known()) `uvm_fatal("MM_TEST", {"unknown fault '", ac.fault, "'"})

    if (has_cpu) begin
      mm_driver_base::type_id::set_type_override(mm_driver_fw::get_type());
    end else begin
      mm_driver_base::type_id::set_type_override(mm_driver_bfm::get_type());
    end

    uvm_config_db#(mm_env_cfg)::set(this, "env", "cfg", cfg);
    env = mm_env::type_id::create("env", this);

    mm_run_status::test_name = get_type_name();
    uvm_root::get().set_timeout(global_timeout, 1);
  endfunction

  // Hook for a derived test to change the configuration before the command line is applied.
  virtual function void configure(mm_env_cfg c);
  endfunction

  virtual function mm_base_seq make_sequence();
    return mm_smoke_seq::type_id::create("seq");
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_root::get().print_topology();
    `uvm_info("MM_TEST", $sformatf("%s: %s C_WIDTH=%0d coverage=%0d NUM_OPS=%0d",
                                   get_type_name(), cfg.agent_cfg.convert2string(), cfg.c_width,
                                   cfg.enable_cov, num_ops), UVM_NONE)
  endfunction

  task run_phase(uvm_phase phase);
    mm_base_seq seq;
    phase.raise_objection(this);
    seq = make_sequence();
    seq.num_ops = num_ops;
    seq.start(env.agent.sqr);
    phase.drop_objection(this);
  endtask

  // Only reached when the run phase ended by itself, not by a fatal error or the watchdog.
  function void extract_phase(uvm_phase phase);
    super.extract_phase(phase);
    mm_run_status::test_done = 1'b1;
  endfunction

endclass
