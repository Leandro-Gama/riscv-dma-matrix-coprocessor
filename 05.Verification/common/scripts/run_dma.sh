#!/usr/bin/env bash
set -euo pipefail

# E3 testbench: DMA + memory + accelerator. Run from the repository root.
# SIM=xrun (default, Xcelium in the course WSL) or SIM=verilator.
SIM=${SIM:-xrun}
SEED=${SEED:-2026}
LOG=dma_subsys_s${SEED}.log

python3 03.Reference/tools/generate_dma_vectors.py --seed "$SEED"
mkdir -p build/dma
FILES=$(sed 's|^|../../|' 05.Verification/unit/dma/dma_subsys.f)
cd build/dma
rm -f "$LOG"

case "$SIM" in
    xrun)
        xrun -sv -timescale 1ns/1ps -access +rwc $FILES -top dma_subsys_tb -l "$LOG" > /dev/null || true
        ;;
    verilator)
        verilator --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
            --top-module dma_subsys_tb $FILES -o sim > build.log 2>&1
        ./obj_dir/sim | tee "$LOG" > /dev/null
        ;;
    *)
        echo "SIM must be xrun or verilator" >&2
        exit 2
        ;;
esac

grep -E '^(OK|ERRO)' "$LOG" | tail -n 5
grep -q '^RESUMO: [0-9]* OK, 0 ERRO$' "$LOG" && ! grep -q 'SVA:' "$LOG"
echo "SIM PASS: build/dma/$LOG"
