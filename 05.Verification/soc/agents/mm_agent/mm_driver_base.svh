/* What both drivers do: hold reset, put A, B and the parameter block in memory, write CMD last
   and wait for the firmware to count the operation as done. The firmware part itself is the
   hook play_firmware: on the top level the CPU runs it, without CPU the bus driver plays it.
   The class is concrete because the factory of this UVM release does not register abstract
   classes; the hooks simply do nothing here. */
class mm_driver_base extends uvm_driver #(mm_item);
  `uvm_component_utils(mm_driver_base)

  mm_agent_cfg cfg;
  virtual sys_if vif;
  int unsigned op_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mm_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_DRV", "agent configuration 'cfg' not found")
    vif = cfg.sys_vif;
    if (vif == null) `uvm_fatal("MM_DRV", "cfg.sys_vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    vif.rst_n = 1'b0;
    init_memory();
    prepare();
    apply_reset();
    forever begin
      seq_item_port.get_next_item(req);
      drive_op(req);
      seq_item_port.item_done();
    end
  endtask

  // Hooks for the two harnesses.
  virtual task prepare();
  endtask

  virtual task play_firmware(mm_item it);
  endtask

  virtual task recover();
  endtask

  /* The command is cleared while the DUT is in reset: a firmware coming out of reset would
     otherwise run the operation that was interrupted. */
  task apply_reset();
    vif.drv_cb.rst_n <= 1'b0;
    repeat (cfg.reset_cycles) @(vif.drv_cb);
    vif.dmem_write(pb_addr(PB_CMD), 32'h0);
    vif.drv_cb.rst_n <= 1'b1;
    repeat (2) @(vif.drv_cb);
  endtask

  /* The memory has no reset. Every word gets a value at time zero, so nothing the DMA reads is
     unknown, and the parameter block starts at zero. */
  function void init_memory();
    for (int unsigned w = 0; w < vif.dmem_words(); w++) begin
      vif.dmem_write(DMEM_BASE + 32'(4 * w), $urandom());
    end
    for (int w = 0; w < PB_WORDS; w++) vif.dmem_write(pb_addr(w), 32'h0);
  endfunction

  task drive_op(mm_item it);
    bit [31:0] done_before;
    bit finished;

    op_count++;
    it.fault |= cfg.fault_flags();
    `uvm_info("MM_DRV", $sformatf("driving %s", it.convert2string()), UVM_HIGH)
    // Backdoor writes land on the falling edge, away from the edge where the memory writes.
    @(negedge vif.clk);
    load_operands(it);
    done_before = vif.dmem_read(pb_addr(PB_DONE_COUNT));
    vif.dmem_write(pb_addr(PB_CMD), 32'h1);

    // A reset in the middle is part of the operation: the monitor publishes it as aborted.
    if (it.reset_after != 0) begin
      fork
        begin
          fork
            play_firmware(it);
          join_none
          repeat (it.reset_after) @(vif.drv_cb);
          disable fork;
        end
      join
      `uvm_info("MM_DRV", $sformatf("reset %0d cycles into the operation", it.reset_after),
                UVM_LOW)
      recover();
      apply_reset();
      repeat (cfg.settle_cycles) @(vif.drv_cb);
      return;
    end

    fork
      begin
        fork
          play_firmware(it);
          if (cfg.fault == "c_flip") corrupt_result(it);
        join_none
        wait_done(done_before, finished);
        disable fork;
      end
    join

    if (!finished) begin
      `uvm_error("MM_DRV_TIMEOUT", $sformatf(
                 "operation did not finish in %0d cycles: %s; resetting the DUT",
                 cfg.op_timeout_cycles, it.convert2string()))
      recover();
      apply_reset();
    end
    repeat (cfg.settle_cycles) @(vif.drv_cb);
  endtask

  task wait_done(input bit [31:0] count, output bit finished);
    finished = 1'b0;
    for (int unsigned i = 0; i < cfg.op_timeout_cycles; i++) begin
      @(vif.drv_cb);
      if (vif.dmem_read(pb_addr(PB_DONE_COUNT)) != count) begin
        finished = 1'b1;
        return;
      end
    end
  endtask

  /* The firmware clears CMD once the DMA is done and counts the operation a few cycles later, so
     a bit flipped in between is in memory when the monitor reads C. */
  task corrupt_result(mm_item it);
    logic [31:0] word;
    @(vif.drv_cb);
    while (vif.dmem_read(pb_addr(PB_CMD)) != 0) @(vif.drv_cb);
    @(negedge vif.clk);
    if (!cfg.in_dmem(it.addr_c, 4)) return;
    word = vif.dmem_read({it.addr_c[31:2], 2'b00});
    word[8*it.addr_c[1:0]] = ~word[8*it.addr_c[1:0]];
    vif.dmem_write({it.addr_c[31:2], 2'b00}, word);
    `uvm_info("MM_DRV", $sformatf("fault c_flip: bit 0 of C[0][0] flipped at 0x%08h", it.addr_c),
              UVM_LOW)
  endtask

  // C is filled with a random pattern, so an element the DMA never writes cannot pass by luck.
  function void load_operands(mm_item it);
    int unsigned eb = it.elem_bytes();
    int unsigned cb = it.c_bytes();
    foreach (it.a[i]) write_elem(it.addr_a + 32'(i * eb), it.a[i], eb);
    foreach (it.b[i]) write_elem(it.addr_b + 32'(i * eb), it.b[i], eb);
    for (int unsigned i = 0; i < it.m * it.n; i++) begin
      write_elem(it.addr_c + 32'(i * cb), $urandom(), cb);
    end
    vif.dmem_write(pb_addr(PB_ADDR_A), it.addr_a);
    vif.dmem_write(pb_addr(PB_ADDR_B), it.addr_b);
    vif.dmem_write(pb_addr(PB_ADDR_C), it.addr_c);
    vif.dmem_write(pb_addr(PB_DIM_M), it.m);
    vif.dmem_write(pb_addr(PB_DIM_K), it.k);
    vif.dmem_write(pb_addr(PB_DIM_N), it.n);
    vif.dmem_write(pb_addr(PB_FLAGS), it.flags());
    vif.dmem_write(pb_addr(PB_STATUS), 32'h0);
  endfunction

  // Addresses outside the memory belong to error tests: nothing to load there.
  function void write_elem(input logic [31:0] addr, input bit [31:0] value,
                           input int unsigned eb);
    logic [31:0] word;
    int unsigned lane = addr[1:0];
    if (!cfg.in_dmem(addr, eb)) return;
    word = vif.dmem_read({addr[31:2], 2'b00});
    for (int unsigned i = 0; i < eb; i++) word[8*(lane+i)+:8] = value[8*i+:8];
    vif.dmem_write({addr[31:2], 2'b00}, word);
  endfunction

endclass
