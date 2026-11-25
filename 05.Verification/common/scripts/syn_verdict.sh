#!/usr/bin/env bash
# Usage: syn_verdict.sh <run_dir> <log>
# A synthesis run is clean when nothing is left unresolved and no latch was inferred. Timing is
# reported, not judged: the target period is a choice of the run, not a pass or fail criterion.
set -euo pipefail

run_dir="$1"

if [[ ! -f "$run_dir/area.rpt" ]]; then
  echo "SYN FAIL: reports not found in $run_dir"
  exit 1
fi

if grep -q "nresolved reference" "$run_dir/check_design.rpt" 2>/dev/null; then
  if ! grep -q "No unresolved references" "$run_dir/check_design.rpt"; then
    echo "SYN FAIL: unresolved references ($run_dir/check_design.rpt)"
    exit 1
  fi
fi

# Latches are counted in the mapped netlist, not guessed from log prose: in gsclib045 a
# transparent latch is a TLAT cell, while DLY cells are delay buffers and DFF cells are
# flip-flops. An inferred latch in this design would mean an incomplete combinational block.
latches=$(awk '/^TLAT/ { n += $2 } END { print n + 0 }' "$run_dir/gates.rpt")
if [[ "$latches" != "0" ]]; then
  echo "SYN FAIL: $latches latch cell(s) in $run_dir/gates.rpt"
  exit 1
fi

flops=$(awk '/^(DFF|SDFF|EDFF)/ { n += $2 } END { print n + 0 }' "$run_dir/gates.rpt")

cells=$(awk '/^[a-z_]/ && NF >= 5 { print $3; exit }' "$run_dir/area.rpt")
area=$(awk '/^[a-z_]/ && NF >= 5 { print $6; exit }' "$run_dir/area.rpt")
slack=$(grep -m1 'Slack:=' "$run_dir/timing.rpt" 2>/dev/null | awk '{print $2}' || true)

echo "SYN OK: $(basename "$run_dir") celulas=${cells:-?} flipflops=${flops:-?} latches=0 area=${area:-?}um2 slack=${slack:-?}ps"
