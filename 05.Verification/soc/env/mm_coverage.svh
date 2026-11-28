typedef enum {
  DIM_SUB,
  DIM_ONE,
  DIM_MULTI,
  DIM_REM
} mm_dim_e;

typedef enum {
  EXT_NONE,
  EXT_MIN,
  EXT_MAX,
  EXT_BOTH
} mm_ext_e;

typedef enum {
  ST_OK,
  ST_ERR_DIM,
  ST_ERR_ADDR,
  ST_OTHER
} mm_status_e;

/* Functional coverage of what the monitor saw. Each coverpoint samples a class computed by a
   small function, and the same classes go to one log line per operation, so the coverage of a
   whole regression can be added up from the logs without a coverage database.

   A dimension is classed against the mesh: smaller than the mesh, exactly the mesh, a multiple of
   it, or larger with a remainder. Those four cases are where the DMA can go wrong (padding,
   edges, partial sums along K), and their cross over M, K and N is the main goal. */
class mm_coverage extends uvm_subscriber #(mm_item);
  `uvm_component_utils(mm_coverage)

  mm_env_cfg cfg;

  mm_dim_e dm, dk, dn;
  mm_ext_e ea, eb;
  bit zero_a, zero_b, wraps;
  bit irq, b2b, relocated;
  mm_status_e st;

  int unsigned samples;
  int unsigned hits[4][4][4];

  covergroup cg_tiling;
    option.per_instance = 1;
    cp_m: coverpoint dm;
    cp_k: coverpoint dk;
    cp_n: coverpoint dn;
    cx_mkn: cross cp_m, cp_k, cp_n;
  endgroup

  covergroup cg_data;
    option.per_instance = 1;
    cp_a: coverpoint ea;
    cp_b: coverpoint eb;
    cp_zero: coverpoint {zero_a, zero_b} {
      bins none = {2'b00};
      bins a_zero = {2'b10};
      bins b_zero = {2'b01};
      ignore_bins both = {2'b11};
    }
    cp_wrap: coverpoint wraps;
    cp_k: coverpoint dk;
    cx_wrap_k: cross cp_wrap, cp_k;
  endgroup

  covergroup cg_ctrl;
    option.per_instance = 1;
    cp_irq: coverpoint irq;
    cp_seq: coverpoint b2b {bins after_reset = {0}; bins back_to_back = {1};}
    cp_addr: coverpoint relocated {bins default_regions = {0}; bins relocated = {1};}
    cp_status: coverpoint st {
      bins ok = {ST_OK};
      bins err_dim = {ST_ERR_DIM};
      bins err_addr = {ST_ERR_ADDR};
      ignore_bins other = {ST_OTHER};
    }
    cx_irq_seq: cross cp_irq, cp_seq;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_tiling = new();
    cg_data = new();
    cg_ctrl = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mm_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MM_COV", "environment configuration 'cfg' not found")
  endfunction

  static function mm_dim_e dim_class(input int unsigned d, input int unsigned s);
    if (d < s) return DIM_SUB;
    if (d == s) return DIM_ONE;
    if (d % s == 0) return DIM_MULTI;
    return DIM_REM;
  endfunction

  static function mm_ext_e ext_class(input bit [31:0] v[], input bit [31:0] lo,
                                     input bit [31:0] hi);
    bit has_lo = 1'b0;
    bit has_hi = 1'b0;
    foreach (v[i]) begin
      if (v[i] == lo) has_lo = 1'b1;
      if (v[i] == hi) has_hi = 1'b1;
    end
    if (has_lo && has_hi) return EXT_BOTH;
    if (has_lo) return EXT_MIN;
    if (has_hi) return EXT_MAX;
    return EXT_NONE;
  endfunction

  static function bit all_zero(input bit [31:0] v[]);
    foreach (v[i]) if (v[i] != 0) return 1'b0;
    return 1'b1;
  endfunction

  // True when some element of C left the range of C_WIDTH bits before wrapping.
  function bit any_wrap(mm_item t);
    longint lo = -(longint'(1) << (cfg.c_width - 1));
    longint hi = (longint'(1) << (cfg.c_width - 1)) - 1;
    for (int unsigned i = 0; i < t.m; i++) begin
      for (int unsigned j = 0; j < t.n; j++) begin
        longint acc = 0;
        for (int unsigned p = 0; p < t.k; p++) begin
          acc += signed_value(t.a[i*t.k+p], t.data_width) *
              signed_value(t.b[p*t.n+j], t.data_width);
        end
        if (acc < lo || acc > hi) return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  function void write(mm_item t);
    int unsigned s = cfg.agent_cfg.array_size;
    if (t.aborted) return;
    samples++;

    dm = dim_class(t.m, s);
    dk = dim_class(t.k, s);
    dn = dim_class(t.n, s);
    irq = t.irq_en;
    b2b = !t.after_reset;
    relocated = (t.addr_a != REGION_A) || (t.addr_b != REGION_B) || (t.addr_c != REGION_C);
    if (t.status == STATUS_OK) st = ST_OK;
    else if (t.status == STATUS_FAIL && (t.m == 0 || t.k == 0 || t.n == 0)) st = ST_ERR_DIM;
    else if (t.status == STATUS_FAIL) st = ST_ERR_ADDR;
    else st = ST_OTHER;
    cg_ctrl.sample();

    if (st == ST_OK) begin
      ea = ext_class(t.a, t.data_min, t.data_max);
      eb = ext_class(t.b, t.data_min, t.data_max);
      zero_a = all_zero(t.a);
      zero_b = all_zero(t.b);
      wraps = any_wrap(t);
      hits[dm][dk][dn]++;
      cg_tiling.sample();
      cg_data.sample();
      `uvm_info("MM_COV", $sformatf(
                "op=%0d tiling=%s/%s/%s data=a:%s,b:%s,zero:%0d%0d,wrap:%0d ctrl=irq:%0d,b2b:%0d,reloc:%0d,status:%s",
                t.op_id, dm.name(), dk.name(), dn.name(), ea.name(), eb.name(), zero_a, zero_b,
                wraps, irq, b2b, relocated, st.name()), UVM_LOW)
    end else begin
      `uvm_info("MM_COV", $sformatf("op=%0d ctrl=irq:%0d,b2b:%0d,reloc:%0d,status:%s", t.op_id,
                                    irq, b2b, relocated, st.name()), UVM_LOW)
    end
  endfunction

  function void report_phase(uvm_phase phase);
    real t_cov = cg_tiling.get_inst_coverage();
    real d_cov = cg_data.get_inst_coverage();
    real c_cov = cg_ctrl.get_inst_coverage();
    string missing = "";
    int unsigned n_missing = 0;

    super.report_phase(phase);
    for (int i = 0; i < 4; i++) begin
      for (int j = 0; j < 4; j++) begin
        for (int l = 0; l < 4; l++) begin
          mm_dim_e ci = mm_dim_e'(i);
          mm_dim_e cj = mm_dim_e'(j);
          mm_dim_e cl = mm_dim_e'(l);
          if (hits[i][j][l] == 0) begin
            n_missing++;
            missing = {missing, $sformatf(" %s/%s/%s", ci.name(), cj.name(), cl.name())};
          end
        end
      end
    end
    `uvm_info("MM_COV_SUMMARY", $sformatf(
              "ARRAY_SIZE=%0d samples=%0d cg_tiling=%0.2f%% (cross M x K x N %0d/64) cg_data=%0.2f%% cg_ctrl=%0.2f%% total=%0.2f%%",
              cfg.agent_cfg.array_size, samples, t_cov, 64 - n_missing, d_cov, c_cov,
              (t_cov + d_cov + c_cov) / 3.0), UVM_NONE)
    if (n_missing != 0) begin
      `uvm_info("MM_COV_SUMMARY", $sformatf("M/K/N combinations not hit:%s", missing), UVM_NONE)
    end
  endfunction

endclass
