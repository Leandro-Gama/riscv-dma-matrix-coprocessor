class mm_env_cfg extends uvm_object;
  `uvm_object_utils(mm_env_cfg)

  mm_agent_cfg agent_cfg;
  // Passive views of the data port of the CPU and of the master port of the DMA; optional.
  virtual axil_tap_if cpu_tap_vif;
  virtual axil_tap_if dma_tap_vif;
  bit enable_cov = 1'b0;
  /* Width of each element of C. The accelerator keeps DATA_WIDTH bits and the DMA adds partial
     sums with the same wrap (decision 0002, still a proposal), so this is DATA_WIDTH unless the
     test is told otherwise. */
  int unsigned c_width = 8;

  function new(string name = "mm_env_cfg");
    super.new(name);
  endfunction

endclass
