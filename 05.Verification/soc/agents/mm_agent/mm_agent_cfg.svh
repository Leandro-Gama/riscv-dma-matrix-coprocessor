class mm_agent_cfg extends uvm_object;
  `uvm_object_utils(mm_agent_cfg)

  virtual sys_if sys_vif;
  virtual axil_bfm_if bfm_vif;
  // Passive view of the data port of the CPU, for the latency; optional.
  virtual axil_tap_if cpu_tap_vif;

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  bit has_cpu = 1'b0;

  int unsigned array_size = 4;
  int unsigned data_width = 8;
  // Width of each element of C in memory (decision 0002 proposes DATA_WIDTH).
  int unsigned c_width = 8;
  int unsigned dmem_bytes = DMEM_BYTES_DEFAULT;

  // Largest dimension a random operation may take; bigger matrices only make the run longer.
  int unsigned max_dim = 12;

  int unsigned reset_cycles = 5;
  int unsigned op_timeout_cycles = 200_000;
  int unsigned bus_timeout_cycles = 2_000;
  // Cycles after the end of an operation before the driver asks for the next one, so the monitor
  // always publishes an operation before the next one starts.
  int unsigned settle_cycles = 4;

  string fw_file = "mm_fw.hex";
  // Golden cases of generate_dma_vectors.py for this mesh and width (+VECTORS=<file>).
  string vectors_file = "";

  /* Fault to inject, so a run can prove that the checking catches it:
     fw_dim_k  the firmware programs K - 1 (C keeps its shape, the values change);
     c_flip    one bit of C is flipped in memory after the operation ends;
     hang      the firmware never reports the end, so the operation times out. */
  string fault = "";

  function new(string name = "mm_agent_cfg");
    super.new(name);
  endfunction

  function int unsigned elem_bytes();
    return data_width / 8;
  endfunction

  function bit in_dmem(input logic [31:0] addr, input int unsigned bytes);
    return (addr >= DMEM_BASE) && (64'(addr) + bytes <= 64'(DMEM_BASE) + dmem_bytes);
  endfunction

  function bit [31:0] fault_flags();
    if (fault == "fw_dim_k") return 32'h1 << FLAG_FAULT_DIM_K;
    if (fault == "hang") return 32'h1 << FLAG_FAULT_HANG;
    return 32'h0;
  endfunction

  function bit fault_known();
    return fault inside {"", "fw_dim_k", "c_flip", "hang"};
  endfunction

  function string convert2string();
    return $sformatf("has_cpu=%0d ARRAY_SIZE=%0d DATA_WIDTH=%0d DMEM=%0d bytes max_dim=%0d%s",
                     has_cpu, array_size, data_width, dmem_bytes, max_dim,
                     (fault == "") ? "" : {" FAULT=", fault});
  endfunction

endclass
