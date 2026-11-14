#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root with the Vivado environment loaded.
python3 03.Reference/tools/generate_rtl_vectors.py --seed 2026
mkdir -p build/accel
cd build/accel
xvlog --sv ../../04.RTL/common/axil_if.sv \
    ../../04.RTL/accel/accel_systolic.sv ../../04.RTL/accel/accel_top.sv \
    ../../05.Verification/unit/accel_top_tb.sv
xelab accel_top_tb -s accel_top_tb_sim -timescale 1ns/1ps
xsim accel_top_tb_sim -runall -log accel_s2026.log
rg -q '^RESUMO: 9 OK, 0 ERRO$' accel_s2026.log
