/* Passive: everything it publishes comes from the memory of the DUT, never from the driver or the
   sequence. An operation starts when CMD turns non-zero out of reset and ends when the firmware
   counts it in DONE_COUNT. At the start it reads the parameter block, A and B and takes a copy
   of the whole data memory; at the end it reads C and the stored STATUS, and every byte that
   changed outside C and the parameter block counts as a write out of place. A reset in the
   middle publishes the operation as aborted.

   With a view of the data port of the CPU, the latency of each operation is the number of cycles
   from the write of START to the end the firmware can see: the rise of the interrupt when it is
   enabled, otherwise the first read of STATUS that shows DONE. */
class mm_monitor extends uvm_monitor;
  `uvm_component_utils(mm_monitor)

  uvm_analysis_port #(mm_item) ap;
  uvm_analysis_port #(mm_item) start_ap;

  mm_agent_cfg cfg;
  virtual sys_if vif;
  int unsigned op_count;

  protected logic [31:0] snapshot[];
  protected bit [31:0] done_before;
  protected bit fresh = 1'b1;
  protected int unsigned latency;
  protected bit latency_ready;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    start_ap = new("start_ap", this);
    if (!uvm_config_db#(mm_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_MON", "agent configuration 'cfg' not found")
    vif = cfg.sys_vif;
    if (vif == null) `uvm_fatal("MM_MON", "cfg.sys_vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    mm_item cur;
    fork
      track_latency();
    join_none
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) begin
        fresh = 1'b1;
        if (cur != null) begin
          cur.aborted = 1'b1;
          cur.end_cycle = vif.cycle;
          `uvm_info("MM_MON", cur.convert2string(), UVM_LOW)
          ap.write(cur);
          cur = null;
        end
      end else if (cur == null) begin
        if (vif.dmem_read(pb_addr(PB_CMD)) != 0) begin
          cur = capture_start();
          start_ap.write(cur);
        end
      end else if (vif.dmem_read(pb_addr(PB_DONE_COUNT)) != done_before) begin
        capture_end(cur);
        `uvm_info("MM_MON", cur.convert2string(), UVM_LOW)
        `uvm_info("MM_LATENCY", $sformatf(
                  "ARRAY_SIZE=%0d DATA_WIDTH=%0d M=%0d K=%0d N=%0d irq_en=%0d latency=%0d op_cycles=%0d",
                  cfg.array_size, cfg.data_width, cur.m, cur.k, cur.n, cur.irq_en,
                  cur.latency_cycles, cur.op_cycles), UVM_LOW)
        ap.write(cur);
        cur = null;
      end
    end
  endtask

  protected task track_latency();
    virtual axil_tap_if tap = cfg.cpu_tap_vif;
    longint unsigned t0;
    bit armed, by_irq, aw_control, irq_before;
    bit [31:0] read_addr;
    if (tap == null) return;
    forever begin
      @(tap.mon_cb);
      if (tap.mon_cb.rst_n !== 1'b1) begin
        armed = 1'b0;
        aw_control = 1'b0;
        irq_before = 1'b0;
        continue;
      end
      if (tap.mon_cb.awvalid && tap.mon_cb.awready) begin
        aw_control = (tap.mon_cb.awaddr == DMAREG_BASE + DMA_REG_CONTROL);
      end
      if (aw_control && tap.mon_cb.wvalid && tap.mon_cb.wready) begin
        aw_control = 1'b0;
        if (tap.mon_cb.wdata[DMA_CONTROL_START_BIT]) begin
          armed = 1'b1;
          by_irq = tap.mon_cb.wdata[DMA_CONTROL_IRQ_EN_BIT];
          t0 = vif.cycle;
        end
      end
      if (tap.mon_cb.arvalid && tap.mon_cb.arready) read_addr = tap.mon_cb.araddr;
      if (armed) begin
        if ((by_irq && vif.mon_cb.irq && !irq_before) ||
            (!by_irq && tap.mon_cb.rvalid && tap.mon_cb.rready &&
             read_addr == DMAREG_BASE + DMA_REG_STATUS &&
             tap.mon_cb.rdata[DMA_STATUS_DONE_BIT])) begin
          latency = int'(vif.cycle - t0);
          latency_ready = 1'b1;
          armed = 1'b0;
        end
      end
      irq_before = vif.mon_cb.irq;
    end
  endtask

  protected function mm_item capture_start();
    mm_item it = mm_item::type_id::create($sformatf("op%0d", op_count));
    bit [31:0] flags;
    int unsigned eb;

    it.set_sizes(cfg.data_width, cfg.array_size, cfg.max_dim, cfg.c_width);
    eb = it.elem_bytes();
    it.op_id = op_count++;
    it.start_cycle = vif.cycle;
    latency_ready = 1'b0;
    it.after_reset = fresh;
    fresh = 1'b0;
    it.addr_a = vif.dmem_read(pb_addr(PB_ADDR_A));
    it.addr_b = vif.dmem_read(pb_addr(PB_ADDR_B));
    it.addr_c = vif.dmem_read(pb_addr(PB_ADDR_C));
    it.m = vif.dmem_read(pb_addr(PB_DIM_M));
    it.k = vif.dmem_read(pb_addr(PB_DIM_K));
    it.n = vif.dmem_read(pb_addr(PB_DIM_N));
    flags = vif.dmem_read(pb_addr(PB_FLAGS));
    it.irq_en = flags[FLAG_IRQ_EN];
    it.fault = flags & ~32'h1;
    done_before = vif.dmem_read(pb_addr(PB_DONE_COUNT));

    // Matrices that do not fit in memory belong to error tests; their contents do not matter.
    if (cfg.in_dmem(it.addr_a, it.m * it.k * eb) && cfg.in_dmem(it.addr_b, it.k * it.n * eb)) begin
      it.a = new[it.m * it.k];
      it.b = new[it.k * it.n];
      foreach (it.a[i]) it.a[i] = read_elem(it.addr_a + 32'(i * eb), eb);
      foreach (it.b[i]) it.b[i] = read_elem(it.addr_b + 32'(i * eb), eb);
    end

    snapshot = new[vif.dmem_words()];
    foreach (snapshot[w]) snapshot[w] = vif.dmem_read(DMEM_BASE + 32'(4 * w));
    return it;
  endfunction

  protected function void capture_end(mm_item it);
    int unsigned cb = it.c_bytes();
    longint unsigned c_lo = it.addr_c;
    longint unsigned c_hi = 64'(it.addr_c) + 64'(it.m) * it.n * cb;
    bit [31:0] done_now = vif.dmem_read(pb_addr(PB_DONE_COUNT));

    it.end_cycle = vif.cycle;
    it.op_cycles = int'(it.end_cycle - it.start_cycle);
    it.latency_cycles = latency_ready ? latency : 0;
    latency_ready = 1'b0;
    it.status = vif.dmem_read(pb_addr(PB_STATUS));
    if (cfg.in_dmem(it.addr_c, it.m * it.n * cb)) begin
      it.c = new[it.m * it.n];
      foreach (it.c[i]) it.c[i] = read_elem(it.addr_c + 32'(i * cb), cb);
    end

    // The firmware ends an operation by clearing CMD and counting exactly one more.
    if (vif.dmem_read(pb_addr(PB_CMD)) != 0 || done_now != done_before + 1) begin
      `uvm_error("MM_MON_PROTOCOL", $sformatf(
                 "op %0d ended with CMD = 0x%0h and DONE_COUNT %0d -> %0d; expected 0 and one more",
                 it.op_id, vif.dmem_read(pb_addr(PB_CMD)), done_before, done_now))
    end

    /* Only the words the firmware answers in (CMD, STATUS, DONE_COUNT) may change outside C; the
       rest of the parameter block is the request and must stay as the environment wrote it. */
    it.oob_writes = 0;
    foreach (snapshot[w]) begin
      logic [31:0] now = vif.dmem_read(DMEM_BASE + 32'(4 * w));
      if (now !== snapshot[w] && !(w inside {PB_CMD, PB_STATUS, PB_DONE_COUNT})) begin
        for (int unsigned lane = 0; lane < 4; lane++) begin
          longint unsigned byte_addr = 64'(DMEM_BASE) + 4 * w + lane;
          if (now[8*lane+:8] !== snapshot[w][8*lane+:8] &&
              !(byte_addr >= c_lo && byte_addr < c_hi)) begin
            it.oob_writes++;
            if (it.oob_writes <= 4) begin
              `uvm_info("MM_MON", $sformatf("op %0d: byte 0x%08h changed outside C: %02h -> %02h",
                                            it.op_id, byte_addr, snapshot[w][8*lane+:8],
                                            now[8*lane+:8]), UVM_LOW)
            end
          end
        end
      end
    end
  endfunction

  protected function logic [31:0] read_elem(input logic [31:0] addr, input int unsigned eb);
    logic [31:0] word = vif.dmem_read({addr[31:2], 2'b00});
    logic [31:0] value = '0;
    int unsigned lane = addr[1:0];
    for (int unsigned i = 0; i < eb; i++) value[8*i+:8] = word[8*(lane+i)+:8];
    return value;
  endfunction

endclass
