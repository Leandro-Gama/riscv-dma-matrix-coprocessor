# One block, one configuration. Everything that changes comes from the environment, so the same
# script serves the smoke runs and the final sweep over the three mesh sizes.
# Paths are relative to the repo root because the absolute path contains spaces.

set top    $env(SYN_TOP)
set run    $env(SYN_RUN)
set period $env(SYN_PERIOD)
set params $env(SYN_PARAMS)

set run_dir 07.Synthesis/runs/$run
file mkdir $run_dir

set_db init_lib_search_path 07.Synthesis/lib
read_libs slow_vdd1v0_basicCells.lib

read_hdl -sv [list \
  04.RTL/common/soc_pkg.sv \
  04.RTL/common/axil_slave_port_ctrl.sv \
  04.RTL/common/axil_slave_port_dp.sv \
  04.RTL/common/axil_slave_port.sv \
  04.RTL/common/axil_master_port_ctrl.sv \
  04.RTL/common/axil_master_port_dp.sv \
  04.RTL/common/axil_master_port.sv \
  04.RTL/common/mem_data.sv \
  04.RTL/common/mem_instr.sv \
  04.RTL/soc/soc_axil_addr_decoder.sv \
  04.RTL/soc/soc_axil_arbiter.sv \
  04.RTL/soc/soc_axil_err_slave.sv \
  04.RTL/soc/soc_axil_xbar.sv \
  04.RTL/soc/accel_adapter_ctrl.sv \
  04.RTL/soc/accel_adapter_dp.sv \
  04.RTL/soc/accel_adapter.sv \
]

if {[string length $params] > 0} {
  elaborate -parameters $params $top
} else {
  elaborate $top
}

source 07.Synthesis/constraints/soc_smoke.sdc.tcl

# Unresolved references would mean a block was left behind in the file list.
check_design -unresolved > $run_dir/check_design.rpt

# A memory built out of flip-flops is slow to optimise, so the effort is a knob: low is enough to
# measure how the cost grows with depth, and medium is for the blocks that go in the final report.
set effort medium
if {[info exists env(SYN_EFFORT)]} {
  set effort $env(SYN_EFFORT)
}

set_db syn_generic_effort $effort
syn_generic
set_db syn_map_effort $effort
syn_map
set_db syn_opt_effort $effort
syn_opt

report_timing -nworst 3 > $run_dir/timing.rpt
report_area > $run_dir/area.rpt
report_gates > $run_dir/gates.rpt

# A full depth memory netlist is hundreds of megabytes, so it is only written when asked for.
if {[info exists env(SYN_NETLIST)] && $env(SYN_NETLIST) == "1"} {
  write_hdl > $run_dir/netlist.v
}

puts "RESUMO_SINTESE $run top=$top period=$period params=$params"
