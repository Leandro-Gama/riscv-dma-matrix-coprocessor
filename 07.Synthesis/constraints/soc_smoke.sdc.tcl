# Sourced by the flow with $period already set, so one file serves every target frequency.
create_clock -name clk -period $period [get_ports clk_i]
set_clock_uncertainty [expr {$period * 0.05}] clk

# The interconnect is mostly combinational between ports, so the boundary has to be constrained
# or its real critical path would not be timed at all.
set_input_delay -clock clk [expr {$period * 0.2}] \
  [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay -clock clk [expr {$period * 0.2}] [all_outputs]

set_false_path -from [get_ports rst_ni]
