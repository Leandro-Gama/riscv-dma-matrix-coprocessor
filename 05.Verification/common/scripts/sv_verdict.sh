#!/usr/bin/env bash
# Usage: sv_verdict.sh <log> <xrun_exit_code>
# Verdict for a plain SystemVerilog testbench (no UVM): xrun exited 0, no simulator errors and a
# "RESUMO: <n> OK, <m> ERRO" line with at least one check and zero failures.
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

summary=$(grep -E '^RESUMO:' "$log" | tail -n 1 || true)

if [[ -z "$summary" ]]; then
  echo "SIM FAIL: testbench summary not found in $log"
  exit 1
fi

passed=$(awk '{print $2}' <<<"$summary")
failed=$(awk '{print $4}' <<<"$summary")

if [[ ! "$passed" =~ ^[0-9]+$ || ! "$failed" =~ ^[0-9]+$ ]]; then
  echo "SIM FAIL: unreadable summary '$summary' ($log)"
  exit 1
fi

if [[ "$passed" == "0" ]]; then
  echo "SIM FAIL: no checks ran ($log)"
  exit 1
fi

if [[ "$failed" != "0" ]]; then
  echo "SIM FAIL: $summary ($log)"
  exit 1
fi

echo "SIM PASS: $summary ($log)"
