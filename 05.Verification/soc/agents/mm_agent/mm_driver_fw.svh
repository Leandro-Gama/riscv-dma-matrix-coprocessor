/* Driver for the top level: the CPU runs the test firmware, so the driver only loads the
   program before the first reset and then puts each operation in memory. The registers of the
   DMA are written by the firmware alone. The image comes from +MM_FW=<file> or the
   configuration. */
class mm_driver_fw extends mm_driver_base;
  `uvm_component_utils(mm_driver_fw)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task prepare();
    string file = cfg.fw_file;
    void'($value$plusargs("MM_FW=%s", file));
    vif.imem_load(file);
    if ($isunknown(vif.imem_read(0))) begin
      `uvm_fatal("MM_FW", $sformatf("firmware image '%s' did not load", file))
    end
    `uvm_info("MM_FW", $sformatf("firmware loaded from %s", file), UVM_LOW)
  endtask

endclass
