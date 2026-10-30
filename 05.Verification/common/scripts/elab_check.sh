#!/usr/bin/env bash
# Usage: elab_check.sh <log> <xrun_exit_code>
# Fails on a non-zero xrun exit, Xcelium errors and warnings that hide integration bugs
# (e.g. port width mismatch).
set -euo pipefail

log="$1"
rc="${2:-}"
critical_warnings="${CRITICAL_WARNINGS:-CUVMPW}"

if [[ ! -f "$log" ]]; then
  echo "ELAB FAIL: log not found: $log"
  exit 1
fi

if [[ -z "$rc" || "$rc" != "0" ]]; then
  echo "ELAB FAIL: xrun exit code '${rc}' ($log)"
  exit 1
fi

pattern='\*[EF],'
for w in $critical_warnings; do
  pattern+="|\\*W,${w}"
done

if grep -E "$pattern" "$log"; then
  echo "ELAB FAIL: errors or critical warnings in $log"
  exit 1
fi

echo "ELAB OK: $log"
