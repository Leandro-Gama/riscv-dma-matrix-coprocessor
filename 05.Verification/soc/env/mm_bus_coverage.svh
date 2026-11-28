typedef enum {
  PATH_CPU_PB_RD,
  PATH_CPU_PB_WR,
  PATH_CPU_DMAREG_RD,
  PATH_CPU_DMAREG_WR,
  PATH_DMA_DATA_RD,
  PATH_DMA_DATA_WR,
  PATH_DMA_CTRL_WR,
  PATH_DMA_STATUS_RD,
  PATH_DMA_BUF_IN_WR,
  PATH_DMA_BUF_OUT_RD,
  PATH_OTHER
} mm_bus_path_e;

`uvm_analysis_imp_decl(_bus_cpu)
`uvm_analysis_imp_decl(_bus_dma)

/* Coverage of the traffic the two bus monitors saw: which master went where, in which direction,
   and which response came back. It is reported apart from the coverage of the operations. */
class mm_bus_coverage extends uvm_component;
  `uvm_component_utils(mm_bus_coverage)

  uvm_analysis_imp_bus_cpu #(axil_item, mm_bus_coverage) cpu_export;
  uvm_analysis_imp_bus_dma #(axil_item, mm_bus_coverage) dma_export;

  mm_bus_path_e path;
  bit [1:0] resp;
  bit is_dma;

  covergroup cg_bus;
    option.per_instance = 1;
    cp_path: coverpoint path {ignore_bins other = {PATH_OTHER};}
    cp_resp: coverpoint resp {
      bins okay = {RESP_OKAY};
      bins slverr = {RESP_SLVERR};
      bins decerr = {RESP_DECERR};
    }
    cp_master: coverpoint is_dma {bins cpu = {0}; bins dma = {1};}
    // The firmware only touches the parameter block and the DMA registers: it never gets an error.
    cx_master_resp: cross cp_master, cp_resp {
      ignore_bins cpu_error = binsof (cp_master.cpu) && binsof (cp_resp) intersect {RESP_SLVERR,
                                                                                   RESP_DECERR};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_bus = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cpu_export = new("cpu_export", this);
    dma_export = new("dma_export", this);
  endfunction

  static function bit in_region(input bit [31:0] a, input bit [31:0] base, input int unsigned n);
    return (a >= base) && (64'(a) < 64'(base) + n);
  endfunction

  function mm_bus_path_e classify(axil_item t, bit dma);
    bit [31:0] a = t.addr;
    if (!dma) begin
      if (in_region(a, PB_BASE, 4 * PB_WORDS)) return t.write ? PATH_CPU_PB_WR : PATH_CPU_PB_RD;
      if (in_region(a, DMAREG_BASE, DMAREG_BYTES)) begin
        return t.write ? PATH_CPU_DMAREG_WR : PATH_CPU_DMAREG_RD;
      end
      return PATH_OTHER;
    end
    if (in_region(a, DMEM_BASE, DMEM_BYTES_DEFAULT)) begin
      return t.write ? PATH_DMA_DATA_WR : PATH_DMA_DATA_RD;
    end
    if (a == ACCEL_BASE + ACCEL_OFF_CTRL && t.write) return PATH_DMA_CTRL_WR;
    if (a == ACCEL_BASE + ACCEL_OFF_STATUS && !t.write) return PATH_DMA_STATUS_RD;
    if (in_region(a, ACCEL_BASE + ACCEL_OFF_DATA_IN, 32'h1000) && t.write) begin
      return PATH_DMA_BUF_IN_WR;
    end
    if (in_region(a, ACCEL_BASE + ACCEL_OFF_DATA_OUT, 32'h1000) && !t.write) begin
      return PATH_DMA_BUF_OUT_RD;
    end
    return PATH_OTHER;
  endfunction

  function void sample(axil_item t, bit dma);
    path = classify(t, dma);
    resp = t.resp;
    is_dma = dma;
    cg_bus.sample();
  endfunction

  function void write_bus_cpu(axil_item t);
    sample(t, 1'b0);
  endfunction

  function void write_bus_dma(axil_item t);
    sample(t, 1'b1);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MM_BUS_COV_SUMMARY", $sformatf(
              "cg_bus=%0.2f%% (paths %0.2f%%, responses %0.2f%%, master x response %0.2f%%)",
              cg_bus.get_inst_coverage(), cg_bus.cp_path.get_inst_coverage(),
              cg_bus.cp_resp.get_inst_coverage(), cg_bus.cx_master_resp.get_inst_coverage()),
              UVM_NONE)
  endfunction

endclass
