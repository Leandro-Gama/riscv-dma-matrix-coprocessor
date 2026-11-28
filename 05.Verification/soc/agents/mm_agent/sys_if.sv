/* System pins of the DUT (clock, reset, interrupt) and the backdoor to its memories. The
   interfaces are the only place with hierarchical references, so the classes never name a path
   inside the DUT: each harness tells, by define, where its memories are. */
`ifndef MM_DMEM_PATH
`define MM_DMEM_PATH tb_subsys.u_dut.u_dmem.mem
`endif

interface sys_if (
    input logic clk
);
  import soc_pkg::*;

  logic rst_n;
  logic irq;
  longint unsigned cycle = 0;

  always @(posedge clk) cycle <= cycle + 1;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output rst_n;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n;
    input irq;
  endclocking

  function automatic int unsigned dmem_words();
    return $size(`MM_DMEM_PATH);
  endfunction

  function automatic int unsigned dmem_index(input logic [31:0] addr);
    return int'((addr - DMEM_BASE) >> 2);
  endfunction

  function automatic logic [31:0] dmem_read(input logic [31:0] addr);
    return `MM_DMEM_PATH[dmem_index(addr)];
  endfunction

  function automatic void dmem_write(input logic [31:0] addr, input logic [31:0] data);
    `MM_DMEM_PATH[dmem_index(addr)] = data;
  endfunction

`ifdef MM_IMEM_PATH
  function automatic void imem_load(input string file);
    $readmemh(file, `MM_IMEM_PATH);
  endfunction

  function automatic logic [31:0] imem_read(input int unsigned index);
    return `MM_IMEM_PATH[index];
  endfunction
`else
  function automatic void imem_load(input string file);
    $fatal(1, "sys_if: this harness has no instruction memory (%s)", file);
  endfunction

  function automatic logic [31:0] imem_read(input int unsigned index);
    return 'x;
  endfunction
`endif

endinterface
