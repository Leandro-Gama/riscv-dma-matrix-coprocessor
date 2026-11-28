class mm_sequencer extends uvm_sequencer #(mm_item);
  `uvm_component_utils(mm_sequencer)

  // Sequences read the sizes from here, so they size every item to the DUT being run.
  mm_agent_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
