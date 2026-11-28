`uvm_analysis_imp_decl(_cpu)
`uvm_analysis_imp_decl(_dma)
`uvm_analysis_imp_decl(_op_start)
`uvm_analysis_imp_decl(_op_end)

/* What the system promises about who does what, checked on the bus. While an operation runs, the
   CPU only talks to the DMA registers and the parameter block: it never reads or writes A, B or
   C, nor the accelerator, so the data moves by the DMA alone. And what the CPU wrote into the
   DMA registers before START is what the parameter block asked for. */
class mm_autonomy_checker extends uvm_component;
  `uvm_component_utils(mm_autonomy_checker)

  uvm_analysis_imp_cpu #(axil_item, mm_autonomy_checker) cpu_export;
  uvm_analysis_imp_dma #(axil_item, mm_autonomy_checker) dma_export;
  uvm_analysis_imp_op_start #(mm_item, mm_autonomy_checker) start_export;
  uvm_analysis_imp_op_end #(mm_item, mm_autonomy_checker) end_export;

  mm_env_cfg cfg;
  mm_item cur;
  bit [31:0] programmed[6];
  bit [5:0] seen;
  bit [31:0] control;
  bit started;
  int unsigned cpu_accesses, dma_reads, dma_writes;
  int unsigned ops, total_dma_accesses, total_cpu_accesses, violations;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cpu_export = new("cpu_export", this);
    dma_export = new("dma_export", this);
    start_export = new("start_export", this);
    end_export = new("end_export", this);
    if (!uvm_config_db#(mm_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_AUTONOMY", "environment configuration 'cfg' not found")
  endfunction

  function bit inside_range(input bit [31:0] addr, input bit [31:0] base,
                            input longint unsigned bytes);
    return (addr >= base) && (64'(addr) < 64'(base) + bytes);
  endfunction

  // A, B or C of the running operation, or the accelerator.
  function bit is_matrix(input bit [31:0] addr);
    longint unsigned eb = cur.elem_bytes();
    return inside_range(addr, cur.addr_a, eb * cur.m * cur.k) ||
        inside_range(addr, cur.addr_b, eb * cur.k * cur.n) ||
        inside_range(addr, cur.addr_c, longint'(cur.c_bytes()) * cur.m * cur.n) ||
        inside_range(addr, ACCEL_BASE, ACCEL_BYTES);
  endfunction

  function void write_op_start(mm_item t);
    cur = t;
    seen = '0;
    started = 1'b0;
    cpu_accesses = 0;
    dma_reads = 0;
    dma_writes = 0;
  endfunction

  function void write_cpu(axil_item t);
    if (cur == null) return;
    cpu_accesses++;
    if (is_matrix(t.addr)) begin
      violations++;
      `uvm_error("MM_AUTONOMY", $sformatf(
                 "op %0d: the CPU %s 0x%08h, inside A, B, C or the accelerator, during the operation",
                 cur.op_id, t.write ? "wrote" : "read", t.addr))
    end
    if (t.write && inside_range(t.addr, DMAREG_BASE, DMAREG_BYTES)) begin
      int unsigned off = t.addr - DMAREG_BASE;
      if (off == DMA_REG_CONTROL && t.data[DMA_CONTROL_START_BIT]) begin
        started = 1'b1;
        control = t.data;
      end else if (off < DMA_REG_CONTROL && off % 4 == 0) begin
        programmed[off/4] = t.data;
        seen[off/4] = 1'b1;
      end
    end
  endfunction

  function void write_dma(axil_item t);
    if (cur == null) return;
    if (t.write) dma_writes++;
    else dma_reads++;
  endfunction

  function void expect_reg(input string name, input int index, input bit [31:0] want);
    if (!seen[index]) begin
      violations++;
      `uvm_error("MM_AUTONOMY", $sformatf("op %0d: the firmware never wrote %s", cur.op_id, name))
    end else if (programmed[index] != want) begin
      violations++;
      `uvm_error("MM_AUTONOMY", $sformatf(
                 "op %0d: the firmware wrote %s = 0x%0h, the parameter block asks for 0x%0h",
                 cur.op_id, name, programmed[index], want))
    end
  endfunction

  function void write_op_end(mm_item t);
    if (cur == null) return;
    if (!t.aborted) begin
      ops++;
      total_cpu_accesses += cpu_accesses;
      total_dma_accesses += dma_reads + dma_writes;
      if (!started) begin
        violations++;
        `uvm_error("MM_AUTONOMY", $sformatf("op %0d ended without a START from the CPU",
                                            t.op_id))
      end else if (control[DMA_CONTROL_IRQ_EN_BIT] != t.irq_en) begin
        violations++;
        `uvm_error("MM_AUTONOMY", $sformatf("op %0d: IRQ_EN written as %0d, asked %0d", t.op_id,
                                            control[DMA_CONTROL_IRQ_EN_BIT], t.irq_en))
      end
      expect_reg("ADDR_A", 0, t.addr_a);
      expect_reg("ADDR_B", 1, t.addr_b);
      expect_reg("ADDR_C", 2, t.addr_c);
      expect_reg("DIM_M", 3, t.m);
      expect_reg("DIM_K", 4, t.k);
      expect_reg("DIM_N", 5, t.n);
      `uvm_info("MM_AUTONOMY", $sformatf(
                "op %0d: the CPU made %0d accesses (DMA registers and parameter block only), the DMA made %0d reads and %0d writes",
                t.op_id, cpu_accesses, dma_reads, dma_writes), UVM_MEDIUM)
    end
    cur = null;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MM_AUTONOMY_SUMMARY", $sformatf(
              "%0d operation(s): %0d bus accesses by the DMA, %0d by the CPU, %0d violation(s)",
              ops, total_dma_accesses, total_cpu_accesses, violations), UVM_NONE)
  endfunction

endclass
