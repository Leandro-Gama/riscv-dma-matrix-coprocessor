#!/usr/bin/env bash
# Usage: uvm_verdict.sh <log> <xrun_exit_code>
# Pass criterion: xrun exited 0, no simulator errors and a UVM summary with zero UVM_ERROR/UVM_FATAL.
set -euo pipefail

log="$1"
rc="${2:-}"

if [[ ! -f "$log" ]]; then
  echo "SIM FAIL: log not found: $log"
  exit 1
fi

if grep -q '\*F,NOLICN' "$log"; then
  echo "SIM BLOCKED: no license (run cadence-check / cadence-login)"
  exit 2
fi

if [[ -z "$rc" || "$rc" != "0" ]]; then
  echo "SIM FAIL: xrun exit code '${rc}' ($log)"
  exit 1
fi

if grep -E '\*[EF],' "$log"; then
  echo "SIM FAIL: simulator errors in $log"
  exit 1
fi

errors=$(awk '/^UVM_ERROR :/ {print $3}' "$log" | tail -n 1)
fatals=$(awk '/^UVM_FATAL :/ {print $3}' "$log" | tail -n 1)

if [[ -z "$errors" || -z "$fatals" ]]; then
  echo "SIM FAIL: UVM report summary not found in $log"
  exit 1
fi

if [[ "$errors" != "0" || "$fatals" != "0" ]]; then
  echo "SIM FAIL: UVM_ERROR=$errors UVM_FATAL=$fatals ($log)"
  exit 1
fi

echo "SIM PASS: UVM_ERROR=0 UVM_FATAL=0 ($log)"
