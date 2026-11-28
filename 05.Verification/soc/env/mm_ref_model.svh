/* Reference model, fed by TLM with the operation the monitor saw. It predicts the STATUS the DMA
   must end with and, when the operation is valid, C = A x B with signed elements, wrapped to the
   width of C. A 64-bit sum wraps the same way as the hardware modulo 2^C_WIDTH, so the order in
   which the tiles add their partial sums does not change the result. */
class mm_ref_model extends uvm_component;
  `uvm_component_utils(mm_ref_model)

  uvm_analysis_imp #(mm_item, mm_ref_model) analysis_export;
  uvm_analysis_port #(mm_item) ap;

  mm_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_export = new("analysis_export", this);
    ap = new("ap", this);
    if (!uvm_config_db#(mm_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_REF", "environment configuration 'cfg' not found")
  endfunction

  /* With a golden vector file, the model first checks itself against the Python golden model:
     its own C for every case must equal the C in the file. The same cases then go through the
     DUT, so the scoreboard compares the DUT with a model that was just shown to agree. */
  function void start_of_simulation_phase(uvm_phase phase);
    mm_vector cases[$];
    logic [31:0] c[];
    bit [31:0] mask = width_mask(cfg.c_width);
    int unsigned bad = 0;
    super.start_of_simulation_phase(phase);
    if (cfg.agent_cfg.vectors_file == "") return;
    mm_vector::read_file(cfg.agent_cfg.vectors_file, cases);
    foreach (cases[i]) begin
      multiply(c, cases[i].a, cases[i].b, cases[i].m, cases[i].k, cases[i].n,
               cfg.agent_cfg.data_width);
      foreach (c[j]) begin
        if ((c[j] & mask) !== (cases[i].c[j] & mask)) begin
          bad++;
          `uvm_error("MM_REF_GOLDEN", $sformatf(
                     "case %s C[%0d]: this model gives 0x%0h, the Python golden model 0x%0h",
                     cases[i].case_name, j, c[j] & mask, cases[i].c[j] & mask))
        end
      end
    end
    `uvm_info("MM_REF_GOLDEN", $sformatf("%0d golden cases from %s: %0d element(s) differ",
                                         cases.size(), cfg.agent_cfg.vectors_file, bad),
              UVM_NONE)
  endfunction

  function void write(mm_item t);
    mm_item exp;
    $cast(exp, t.clone());
    exp.c.delete();
    if (!t.aborted) begin
      exp.status = predict_status(t);
      if (exp.status == STATUS_OK) multiply(exp.c, t.a, t.b, t.m, t.k, t.n, t.data_width);
    end
    ap.write(exp);
  endfunction

  /* The DMA stops with DONE and ERROR when a dimension is zero or when any access gets an error
     response, which is what an address outside the memory gets. */
  function bit [31:0] predict_status(mm_item t);
    mm_agent_cfg ac = cfg.agent_cfg;
    int unsigned eb = t.elem_bytes();
    if (t.m == 0 || t.k == 0 || t.n == 0) return STATUS_FAIL;
    if (!ac.in_dmem(t.addr_a, t.m * t.k * eb) || !ac.in_dmem(t.addr_b, t.k * t.n * eb) ||
        !ac.in_dmem(t.addr_c, t.m * t.n * t.c_bytes())) begin
      return STATUS_FAIL;
    end
    return STATUS_OK;
  endfunction

  function void multiply(ref logic [31:0] c[], input bit [31:0] a[], input bit [31:0] b[],
                         input int unsigned m, input int unsigned k, input int unsigned n,
                         input int unsigned width);
    bit [31:0] mask = width_mask(cfg.c_width);
    c = new[m * n];
    for (int unsigned i = 0; i < m; i++) begin
      for (int unsigned j = 0; j < n; j++) begin
        longint acc = 0;
        for (int unsigned p = 0; p < k; p++) begin
          acc += signed_value(a[i*k+p], width) * signed_value(b[p*n+j], width);
        end
        c[i*n+j] = 32'(acc) & mask;
      end
    end
  endfunction

endclass
