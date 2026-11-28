`uvm_analysis_imp_decl(_start)

/* Compares, operation by operation, what the monitor found in memory with what the reference
   model predicts: STATUS always, C element by element when the operation is valid, and no byte
   written outside C. An operation that started and never got compared is reported at the end,
   so a run cut short cannot look clean. An operation aborted by reset is not compared. */
class mm_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mm_scoreboard)

  uvm_analysis_imp_start #(mm_item, mm_scoreboard) start_export;
  uvm_tlm_analysis_fifo #(mm_item) exp_fifo;
  uvm_tlm_analysis_fifo #(mm_item) act_fifo;

  mm_env_cfg cfg;
  int unsigned max_reports = 8;

  int unsigned started;
  int unsigned compared;
  int unsigned matched;
  int unsigned mismatched;
  int unsigned aborted;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    start_export = new("start_export", this);
    exp_fifo = new("exp_fifo", this);
    act_fifo = new("act_fifo", this);
    if (!uvm_config_db#(mm_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_SB", "environment configuration 'cfg' not found")
  endfunction

  function void write_start(mm_item t);
    started++;
  endfunction

  task run_phase(uvm_phase phase);
    mm_item exp, act;
    forever begin
      act_fifo.get(act);
      exp_fifo.get(exp);
      check_op(exp, act);
    end
  endtask

  function void check_op(mm_item exp, mm_item act);
    bit [31:0] mask = width_mask(cfg.c_width);
    int unsigned bad = 0;
    int unsigned errors = 0;

    if (act.aborted) begin
      aborted++;
      `uvm_info("MM_SB", $sformatf("op %0d aborted by reset, not compared", act.op_id), UVM_LOW)
      return;
    end
    compared++;
    mm_run_status::ops_compared++;

    if (act.status !== exp.status) begin
      errors++;
      `uvm_error("MM_SB_STATUS", $sformatf("op %0d: STATUS expected 0x%0h, got 0x%0h (%s)",
                                           act.op_id, exp.status, act.status,
                                           act.convert2string()))
    end
    if (act.oob_writes != 0) begin
      errors++;
      `uvm_error("MM_SB_OOB", $sformatf("op %0d: %0d byte(s) written outside C", act.op_id,
                                        act.oob_writes))
    end
    if (exp.status == STATUS_OK && act.status == STATUS_OK) begin
      if (act.c.size() != exp.c.size()) begin
        errors++;
        `uvm_error("MM_SB_SIZE", $sformatf("op %0d: C has %0d elements, expected %0d",
                                           act.op_id, act.c.size(), exp.c.size()))
      end else begin
        foreach (exp.c[idx]) begin
          logic [31:0] got = act.c[idx] & mask;
          logic [31:0] want = exp.c[idx] & mask;
          if (got !== want) begin
            bad++;
            if (bad <= max_reports) begin
              `uvm_error("MM_SB_MISMATCH", $sformatf(
                         "op %0d C[%0d][%0d]: expected %0d (0x%0h), got %s (0x%0h)", act.op_id,
                         idx / act.n, idx % act.n, signed_value(want, cfg.c_width), want,
                         $isunknown(got) ? "x" : $sformatf("%0d", signed_value(got, cfg.c_width)),
                         got))
            end
          end
        end
        if (bad > 0) begin
          errors++;
          `uvm_error("MM_SB_MISMATCH", $sformatf("op %0d: %0d of %0d elements of C differ%s",
                                                 act.op_id, bad, exp.c.size(),
                                                 act.matrix_string("C")))
        end
      end
    end

    if (errors == 0) begin
      matched++;
      `uvm_info("MM_SB", $sformatf("op %0d OK: %0dx%0dx%0d, %0d elements, %0d cycles", act.op_id,
                                   act.m, act.k, act.n, exp.c.size(), act.op_cycles), UVM_MEDIUM)
    end else begin
      mismatched++;
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (started != compared + aborted) begin
      `uvm_error("MM_SB_PENDING", $sformatf(
                 "%0d operation(s) started, but only %0d compared and %0d aborted", started,
                 compared, aborted))
    end
    if (act_fifo.used() != 0 || exp_fifo.used() != 0) begin
      `uvm_error("MM_SB_PENDING", $sformatf("%0d observed and %0d expected left unchecked",
                                            act_fifo.used(), exp_fifo.used()))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MM_SB_SUMMARY", $sformatf(
              "started=%0d compared=%0d ok=%0d wrong=%0d aborted=%0d", started, compared,
              matched, mismatched, aborted), UVM_NONE)
  endfunction

endclass
