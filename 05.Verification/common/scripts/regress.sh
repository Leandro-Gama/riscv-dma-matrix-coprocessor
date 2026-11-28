#!/usr/bin/env bash
# Usage: regress.sh <tests.list> <harness: soc|subsys> <out dir> [meshes...]
# Runs every line of the list with make uvm, on every mesh, with coverage on. Writes the log of
# each run where make uvm leaves it, one line per run in <out>/regress.log and a table in
# <out>/regress.md. Exits non-zero if any run did not end as the list expects.
set -uo pipefail

list="$1"
tb="$2"
out="$3"
shift 3
meshes=("$@")
[[ ${#meshes[@]} -eq 0 ]] && meshes=(2 4 8)

mkdir -p "$out"
log="$out/regress.log"
table="$out/regress.md"
: > "$log"
{
  echo "| Teste | Malha | Largura | Seed | Esperado | Resultado | UVM_ERROR | Operacoes | Cobertura | Log |"
  echo "|---|---|---|---|---|---|---|---|---|---|"
} > "$table"

runs=0
bad=0
start=$(date +%s)

while read -r line; do
  line="${line%%#*}"
  [[ -z "${line// }" ]] && continue
  read -r test rest <<<"$line"
  seeds=()
  expect=""
  opts=()
  only=""
  for word in $rest; do
    if [[ -z "$expect" && "$word" =~ ^[0-9]+$ ]]; then
      seeds+=("$word")
    elif [[ -z "$expect" ]]; then
      expect="$word"
    elif [[ "$word" == MESH=* ]]; then
      only="${word#MESH=}"
    else
      opts+=("$word")
    fi
  done
  if [[ "$expect" != "pass" && "$expect" != "fail" ]]; then
    echo "FALHOU $test: the expected result must be pass or fail, got '${expect}'" | tee -a "$log"
    bad=$((bad + 1))
    continue
  fi
  width=8
  suffix=""
  for opt in "${opts[@]}"; do
    [[ "$opt" == DATA_WIDTH=* ]] && width="${opt#DATA_WIDTH=}"
    [[ "$opt" == BUG=* ]] && suffix="_bug_${opt#BUG=}"
  done

  for mesh in "${meshes[@]}"; do
    [[ -n "$only" && ",$only," != *",$mesh,"* ]] && continue
    for seed in "${seeds[@]}"; do
      runs=$((runs + 1))
      result=$(make --no-print-directory uvm TB="$tb" TEST="$test" SEED="$seed" ARRAY_SIZE="$mesh" \
        COV=1 WAVES=0 EXPECT="$expect" "${opts[@]}" < /dev/null 2>&1 | grep -E '^SIM ' | tail -n 1)
      run_log="build/uvm/${tb}_s${mesh}_w${width}${suffix}/${test}_s${seed}.log"
      verdict=$(grep -E '^TEST (PASS|FAIL)' "$run_log" 2>/dev/null | tail -n 1)
      errors=$(sed -nE 's/.*UVM_ERROR=([0-9]+).*/\1/p' <<<"$verdict")
      ops=$(sed -nE 's/.* ops=([0-9]+).*/\1/p' <<<"$verdict")
      cov=$(grep -h 'MM_COV_SUMMARY' "$run_log" 2>/dev/null | head -n 1 | sed -nE 's/.*total=([0-9.]+%).*/\1/p')
      if [[ "$result" == "SIM PASS"* ]]; then
        status="ok"
      else
        status="FALHOU"
        bad=$((bad + 1))
      fi
      echo "$status $test S=$mesh W=$width seed=$seed expect=$expect ${opts[*]} :: ${result:-no verdict}" \
        | tee -a "$log"
      word=$(sed -nE 's/^TEST (PASS|FAIL).*/\1/p' <<<"$verdict")
      echo "| $test ${opts[*]} | $mesh | $width | $seed | $expect | $status (${word:-sem veredito}) | ${errors:-?} | ${ops:-?} | ${cov:--} | $run_log |" \
        >> "$table"
    done
  done
done < "$list"

elapsed=$(( $(date +%s) - start ))
summary="REGRESS: $runs run(s), $((runs - bad)) as expected, $bad unexpected, ${elapsed}s, harness $tb, meshes ${meshes[*]}"
echo "$summary" | tee -a "$log"
echo "" >> "$table"
echo "$summary" >> "$table"
[[ $bad -eq 0 ]]
