/* The test catalog. Each test only picks a sequence and, when it needs to, a knob of the
   configuration; the environment, the checking and the harness are the same for all of them. */

// One operation the size of the mesh with known values: the first thing to run on a new DUT.
class mm_smoke_test extends mm_base_test;
  `uvm_component_utils(mm_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

// The cases of the Python golden model; the reference model is checked against them first.
class mm_vectors_test extends mm_base_test;
  `uvm_component_utils(mm_vectors_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure(mm_env_cfg c);
    c.agent_cfg.vectors_file = $sformatf("vectors/n%0d_w%0d.txt", c.agent_cfg.array_size,
                                         c.agent_cfg.data_width);
  endfunction

  function mm_base_seq make_sequence();
    return mm_vectors_seq::type_id::create("seq");
  endfunction

endclass

// The 64 combinations of the classes of M, K and N against the mesh.
class mm_tiling_test extends mm_base_test;
  `uvm_component_utils(mm_tiling_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function mm_base_seq make_sequence();
    return mm_tiling_seq::type_id::create("seq");
  endfunction

endclass

// Minimum, maximum, zero, minus one, identity: the values that make sums wrap.
class mm_limits_test extends mm_base_test;
  `uvm_component_utils(mm_limits_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function mm_base_seq make_sequence();
    return mm_limits_seq::type_id::create("seq");
  endfunction

endclass

// Operations one after another without reset: nothing may leak from one to the next.
class mm_b2b_test extends mm_base_test;
  `uvm_component_utils(mm_b2b_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    num_ops = 8;
  endfunction

  function mm_base_seq make_sequence();
    return mm_b2b_seq::type_id::create("seq");
  endfunction

endclass

// The two ways an operation can end for the firmware: interrupt enabled or polling alone.
class mm_irq_poll_test extends mm_base_test;
  `uvm_component_utils(mm_irq_poll_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function mm_base_seq make_sequence();
    return mm_irq_poll_seq::type_id::create("seq");
  endfunction

endclass

// Operations that must end with ERROR, each followed by one that must work.
class mm_error_test extends mm_base_test;
  `uvm_component_utils(mm_error_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function mm_base_seq make_sequence();
    return mm_error_seq::type_id::create("seq");
  endfunction

endclass

// Resets in the middle of an operation; the system must come back clean.
class mm_reset_midop_test extends mm_base_test;
  `uvm_component_utils(mm_reset_midop_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function mm_base_seq make_sequence();
    return mm_reset_seq::type_id::create("seq");
  endfunction

endclass

// NUM_OPS random operations (20 by default), everything random within the configuration.
class mm_rand_test extends mm_base_test;
  `uvm_component_utils(mm_rand_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    num_ops = 20;
  endfunction

  function mm_base_seq make_sequence();
    return mm_rand_seq::type_id::create("seq");
  endfunction

endclass

// Cycle counts for the sizes of the DMA documentation, to compare the meshes.
class mm_latency_test extends mm_base_test;
  `uvm_component_utils(mm_latency_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function mm_base_seq make_sequence();
    return mm_latency_seq::type_id::create("seq");
  endfunction

endclass

/* Must FAIL: random operations with the fault given by +FAULT (fw_dim_k, c_flip). It proves the
   checking catches a wrong result; a run without +FAULT is refused. */
class mm_fault_test extends mm_base_test;
  `uvm_component_utils(mm_fault_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    num_ops = 3;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.agent_cfg.fault == "") `uvm_fatal("MM_TEST", "mm_fault_test needs +FAULT=<name>")
  endfunction

  function mm_base_seq make_sequence();
    return mm_rand_seq::type_id::create("seq");
  endfunction

endclass

/* Must FAIL, without hanging: the firmware never reports the end of the operation. The driver
   gives up after the timeout, reports it and resets the DUT. */
class mm_timeout_test extends mm_base_test;
  `uvm_component_utils(mm_timeout_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure(mm_env_cfg c);
    c.agent_cfg.fault = "hang";
    c.agent_cfg.op_timeout_cycles = 5_000;
  endfunction

endclass
