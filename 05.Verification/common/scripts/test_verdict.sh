#!/usr/bin/env bash
# Usage: test_verdict.sh <log> <xrun_exit_code> [pass|fail]
# The verdict is the TEST PASS / TEST FAIL line the harness prints at the very end of the
# simulation. Simulator errors, assertion failures included, fail the run even if that line says
# pass. With "fail" as the expected result, the run is accepted only when the test failed by its
# own checking: it ran to the end with no UVM_FATAL, so a wrong test name, a watchdog or a crash
# is never taken for the failure a fault injection should cause.
set -euo pipefail

log="$1"
rc="${2:-}"
expect="${3:-pass}"

if [[ "$expect" != "pass" && "$expect" != "fail" ]]; then
  echo "SIM FAIL: expected result must be pass or fail, got '${expect}' ($log)"
  exit 1
fi

if [[ ! -f "$log" ]]; then
  echo "SIM FAIL: log not found: $log"
  exit 1
fi

if grep -q '\*F,NOLICN' "$log"; then
  echo "SIM BLOCKED: no license (run cadence-check / cadence-login)"
  exit 2
fi

line=$(grep -E '^TEST (PASS|FAIL)' "$log" | tail -n 1 || true)
sim_errors=$(grep -cE '\*[EF],' "$log" || true)

if [[ -z "$line" ]]; then
  echo "SIM FAIL: no TEST PASS / TEST FAIL line, xrun exit '${rc}' ($log)"
  exit 1
fi

verdict=fail
if [[ "$line" == "TEST PASS"* && "$rc" == "0" && "$sim_errors" == "0" ]]; then
  verdict=pass
fi

if [[ "$expect" == "pass" ]]; then
  if [[ "$verdict" == "pass" ]]; then
    echo "SIM PASS: $line ($log)"
    exit 0
  fi
  echo "SIM FAIL: $line; xrun exit '${rc}'; ${sim_errors} simulator error line(s) ($log)"
  exit 1
fi

if [[ "$verdict" == "pass" ]]; then
  echo "SIM FAIL: a failure was expected, but the test passed: $line ($log)"
  exit 1
fi
sim_fatals=$(grep -cE '\*F,' "$log" || true)
if [[ "$line" == "TEST FAIL"* ]]; then
  if [[ "$line" != *"UVM_FATAL=0"* || "$line" != *"finished=1"* || "$sim_fatals" != "0" ]]; then
    echo "SIM FAIL: the test did not fail by its checking (fatal error or not finished): $line ($log)"
    exit 1
  fi
elif [[ "$rc" != "0" || "$sim_fatals" != "0" ]]; then
  # A pass line with simulator errors is a failure seen by an assertion; a crash is not.
  echo "SIM FAIL: the simulation did not end normally, xrun exit '${rc}' ($log)"
  exit 1
fi
echo "SIM PASS (failure expected and seen): $line ($log)"
exit 0
