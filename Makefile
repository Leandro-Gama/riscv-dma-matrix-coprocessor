# Entry point for the whole flow. Runs inside WSL (cademics-cepedi) from the repo root.
# All paths are relative: the absolute path of the repo contains spaces.

SHELL := /bin/bash

PYTHON      ?= python3
VERIBLE_DIR ?= /opt/verible/bin
XRUN        ?= xrun
SEED        ?= 1
EXTRA       ?=
TEST        ?=
UNIT_TOP    ?= tb_axil_port_loop

TB          ?= subsys
ARRAY_SIZE  ?= 4
DATA_WIDTH  ?= 8
NUM_OPS     ?=
COV         ?= 0
WAVES       ?= 0
FAULT       ?=
EXPECT      ?= pass
BUG         ?=

BUILD       := build
SCRIPTS     := 05.Verification/common/scripts
COMMON_DIR  := 05.Verification/common
SMOKE_DIR   := 05.Verification/env_smoke
SMOKE_BUILD := $(BUILD)/env_smoke
UNIT_DIR    := 05.Verification/unit/soc
UNIT_BUILD  := $(BUILD)/unit_soc
UNIT_TOPS   := tb_axil_port_loop tb_mem_data tb_mem_instr tb_axil_arbiter tb_axil_xbar tb_accel_adapter \
  tb_cpu_model tb_accel_link

SYN_DIR     := 07.Synthesis
GENUS       ?= genus
SYN_TOP     ?= soc_axil_xbar
SYN_RUN     ?= xbar_2ns
SYN_PERIOD  ?= 2.0
SYN_PARAMS  ?=
SYN_EFFORT  ?= medium

# UVM 1.2: plain -uvm loads the 1.1d library of this Xcelium release.
XRUN_FLAGS  := -uvm -uvmhome CDNS-1.2 -access +rwc -timescale 1ns/1ps

SMOKE_TEST  := $(or $(TEST),env_smoke_test)

# UVM environment of the system: one build directory per harness, mesh and data width.
UVM_TEST    := $(or $(TEST),mm_smoke_test)
UVM_F_subsys   := 05.Verification/subsys/subsys.f
UVM_TOP_subsys := tb_subsys
UVM_F_soc      := 05.Verification/soc/sim/soc.f
UVM_TOP_soc    := tb_soc
FW_SRC      := 05.Verification/soc/firmware/mm_fw.S
FW_HEX      := 05.Verification/soc/firmware/mm_fw.hex
UVM_PLUS_soc   := +MM_FW=../../../$(FW_HEX)
# BUG=<mutant> builds a modified copy of one RTL file in its own build directory.
UVM_BUILD   := $(BUILD)/uvm/$(TB)_s$(ARRAY_SIZE)_w$(DATA_WIDTH)$(if $(BUG),_bug_$(BUG))
UVM_LOG     := $(UVM_TEST)_s$(SEED).log
UVM_DEFS    := +define+MM_ARRAY_SIZE=$(ARRAY_SIZE) +define+MM_DATA_WIDTH=$(DATA_WIDTH)
UVM_FLIST   := $(if $(BUG),mutant.f,../../../$(UVM_F_$(TB)))
UVM_ARGS    := $(XRUN_FLAGS) -F $(UVM_FLIST) -top $(UVM_TOP_$(TB)) $(UVM_DEFS)
UVM_RUN     := +UVM_TESTNAME=$(UVM_TEST) -svseed $(SEED) $(UVM_PLUS_$(TB)) \
  $(if $(NUM_OPS),+NUM_OPS=$(NUM_OPS)) $(if $(FAULT),+FAULT=$(FAULT)) \
  $(if $(filter 1,$(COV)),+MM_COV -coverage functional -covoverwrite -covworkdir cov_work \
    -covtest $(UVM_TEST)_s$(SEED)) \
  $(if $(filter 1,$(WAVES)),-input ../../../05.Verification/soc/sim/waves.tcl)

# The files of the System must be clean; the blocks of the other owners are linted and reported,
# without failing the check, because only their owners change them.
LINT_DIRS := 04.RTL/common 04.RTL/soc $(COMMON_DIR) $(SMOKE_DIR) $(UNIT_DIR) \
  05.Verification/models 05.Verification/soc 05.Verification/subsys
LINT_SRCS := $(shell find $(LINT_DIRS) -name '*.sv' 2>/dev/null | sort)
LINT_TEAM := $(shell find 04.RTL/cpu 04.RTL/dma 04.RTL/accel -name '*.sv' 2>/dev/null | sort)

.DEFAULT_GOAL := help

.PHONY: help check uvm-elab-check test lint fw fw-check elab-smoke sim-smoke elab-unit \
  cpu-selftest sim-unit sim-unit-all uvm-mutant uvm-elab uvm-elab-all uvm uvm-gui regress \
  cov-merge syn-one clean

help:
	@echo "Targets (run inside WSL from the repo root):"
	@echo "  check       test + lint + fw-check + elab-smoke + elab-unit + uvm-elab-check (no license)"
	@echo "  test        Python unit tests of 03.Reference (stdlib unittest)"
	@echo "  lint        Verible lint of the RTL and the verification sources"
	@echo "  fw          assemble the test firmware into $(FW_HEX)"
	@echo "  fw-check    fail if $(FW_HEX) is not up to date with its source"
	@echo "  elab-smoke  elaborate the UVM smoke environment"
	@echo "  sim-smoke   simulate the UVM smoke test (needs license), TEST=$(SMOKE_TEST) SEED=$(SEED)"
	@echo "  elab-unit   elaborate every system unit testbench: $(UNIT_TOPS)"
	@echo "  sim-unit    simulate one unit testbench (needs license), UNIT_TOP=$(UNIT_TOP) EXTRA="
	@echo "  sim-unit-all simulate every unit testbench (needs license), SEED=$(SEED)"
	@echo "  uvm-elab    elaborate the system UVM environment, TB=subsys|soc ARRAY_SIZE= DATA_WIDTH="
	@echo "  uvm-elab-all elaborate it for ARRAY_SIZE 2, 4 and 8 (TB=$(TB) DATA_WIDTH=$(DATA_WIDTH))"
	@echo "  uvm         run one test of the system environment (needs license):"
	@echo "              TB=$(TB) TEST=$(UVM_TEST) SEED=$(SEED) ARRAY_SIZE=$(ARRAY_SIZE) DATA_WIDTH=$(DATA_WIDTH)"
	@echo "              NUM_OPS= COV=0|1 WAVES=0|1 FAULT= BUG= EXPECT=pass|fail EXTRA="
	@echo "  uvm-gui     SimVision on the waves of the last WAVES=1 run of TB= ARRAY_SIZE= DATA_WIDTH="
	@echo "  regress     every line of 05.Verification/soc/sim/tests.list on MESHES=$(MESHES), TB=$(REGRESS_TB)"
	@echo "  cov-merge   functional coverage of all passing runs, per configuration"
	@echo "  syn-one     synthesise one block in Genus, SYN_TOP= SYN_RUN= SYN_PERIOD= SYN_PARAMS= SYN_EFFORT="
	@echo "  clean       remove $(BUILD)/"

check: test lint fw-check elab-smoke elab-unit uvm-elab-check

# Both harnesses of the system environment, on the middle mesh.
uvm-elab-check:
	@$(MAKE) --no-print-directory uvm-elab TB=subsys ARRAY_SIZE=4 DATA_WIDTH=8 BUG=
	@$(MAKE) --no-print-directory uvm-elab TB=soc ARRAY_SIZE=4 DATA_WIDTH=8 BUG=

test:
	$(PYTHON) -m unittest discover -s 03.Reference -t 03.Reference -p 'test_*.py'

lint:
	@if [ -z "$(LINT_SRCS)" ]; then echo "LINT: no sources"; exit 0; fi
	$(VERIBLE_DIR)/verible-verilog-lint --rules_config=.rules.verible_lint $(LINT_SRCS)
	@echo "LINT OK: $(words $(LINT_SRCS)) file(s)"
	@n=$$($(VERIBLE_DIR)/verible-verilog-lint --rules_config=.rules.verible_lint $(LINT_TEAM) \
	  2>&1 | grep -c '\.sv:' || true); \
	echo "LINT (other blocks, report only): $$n finding(s) in $(words $(LINT_TEAM)) file(s)"

fw:
	$(PYTHON) 03.Reference/tools/rv32i_asm.py $(FW_SRC) -o $(FW_HEX)

fw-check:
	$(PYTHON) 03.Reference/tools/rv32i_asm.py $(FW_SRC) -o $(FW_HEX) --check

# Logs are removed first and the xrun exit code is checked, so a stale log never yields a pass.
elab-smoke:
	@mkdir -p $(SMOKE_BUILD) && rm -f $(SMOKE_BUILD)/elab.log
	rc=0; (cd $(SMOKE_BUILD) && $(XRUN) $(XRUN_FLAGS) -elaborate -F ../../$(SMOKE_DIR)/env_smoke.f \
	  -top tb_env_smoke -l elab.log > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/elab_check.sh $(SMOKE_BUILD)/elab.log $$rc

sim-smoke:
	@mkdir -p $(SMOKE_BUILD) && rm -f $(SMOKE_BUILD)/$(SMOKE_TEST)_s$(SEED).log
	rc=0; (cd $(SMOKE_BUILD) && $(XRUN) $(XRUN_FLAGS) -F ../../$(SMOKE_DIR)/env_smoke.f -top tb_env_smoke \
	  +UVM_TESTNAME=$(SMOKE_TEST) -svseed $(SEED) -l $(SMOKE_TEST)_s$(SEED).log > /dev/null) \
	  || rc=$$?; \
	bash $(SCRIPTS)/uvm_verdict.sh $(SMOKE_BUILD)/$(SMOKE_TEST)_s$(SEED).log $$rc

elab-unit:
	@mkdir -p $(UNIT_BUILD)
	@set -e; for top in $(UNIT_TOPS); do \
	  rm -f $(UNIT_BUILD)/elab_$${top}.log; \
	  rc=0; (cd $(UNIT_BUILD) && $(XRUN) $(XRUN_FLAGS) -elaborate -F ../../$(UNIT_DIR)/unit_soc.f \
	    -top $${top} -l elab_$${top}.log > /dev/null) || rc=$$?; \
	  bash $(SCRIPTS)/elab_check.sh $(UNIT_BUILD)/elab_$${top}.log $$rc; \
	done

# Programs and expected state of tb_cpu_model, from the Python reference model.
cpu-selftest:
	@$(PYTHON) 03.Reference/tools/cpu_selftest.py --out $(UNIT_BUILD)

sim-unit: cpu-selftest
	@mkdir -p $(UNIT_BUILD) && rm -f $(UNIT_BUILD)/$(UNIT_TOP)_s$(SEED).log
	rc=0; (cd $(UNIT_BUILD) && $(XRUN) $(XRUN_FLAGS) -F ../../$(UNIT_DIR)/unit_soc.f -top $(UNIT_TOP) \
	  -svseed $(SEED) $(EXTRA) -l $(UNIT_TOP)_s$(SEED).log > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/sv_verdict.sh $(UNIT_BUILD)/$(UNIT_TOP)_s$(SEED).log $$rc

sim-unit-all: cpu-selftest
	@mkdir -p $(UNIT_BUILD)
	@set -e; for top in $(UNIT_TOPS); do \
	  rm -f $(UNIT_BUILD)/$${top}_s$(SEED).log; \
	  rc=0; (cd $(UNIT_BUILD) && $(XRUN) $(XRUN_FLAGS) -F ../../$(UNIT_DIR)/unit_soc.f -top $${top} \
	    -svseed $(SEED) -l $${top}_s$(SEED).log > /dev/null) || rc=$$?; \
	  bash $(SCRIPTS)/sv_verdict.sh $(UNIT_BUILD)/$${top}_s$(SEED).log $$rc; \
	done

uvm-mutant:
	@mkdir -p $(UVM_BUILD)
	@$(if $(BUG),$(PYTHON) 03.Reference/tools/make_mutant.py --bug $(BUG) --filelist $(UVM_F_$(TB)) \
	  --out $(UVM_BUILD),true)

uvm-elab: uvm-mutant
	@mkdir -p $(UVM_BUILD) && rm -f $(UVM_BUILD)/elab.log
	rc=0; (cd $(UVM_BUILD) && $(XRUN) $(UVM_ARGS) -elaborate -l elab.log > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/elab_check.sh $(UVM_BUILD)/elab.log $$rc

uvm-elab-all:
	@set -e; for s in 2 4 8; do $(MAKE) --no-print-directory uvm-elab ARRAY_SIZE=$$s; done

# The golden vectors are regenerated each run: a few milliseconds, and never stale.
uvm: uvm-mutant
	@mkdir -p $(UVM_BUILD) && rm -f $(UVM_BUILD)/$(UVM_LOG)
	@$(PYTHON) 03.Reference/tools/generate_dma_vectors.py --output $(UVM_BUILD)/vectors > /dev/null
	rc=0; (cd $(UVM_BUILD) && MM_TOP=$(UVM_TOP_$(TB)) $(XRUN) $(UVM_ARGS) $(UVM_RUN) $(EXTRA) \
	  -l $(UVM_LOG) > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/test_verdict.sh $(UVM_BUILD)/$(UVM_LOG) $$rc $(EXPECT)

# Opens SimVision on the waves of the last run made with WAVES=1 in this configuration.
uvm-gui:
	cd $(UVM_BUILD) && MM_TOP=$(UVM_TOP_$(TB)) simvision \
	  -input ../../../05.Verification/soc/sim/sv_view.tcl &

# Every line of tests.list on every mesh, with coverage; then the coverage of all passing runs.
REGRESS_TB  ?= soc
MESHES      ?= 2 4 8
REGRESS_OUT := $(BUILD)/regress

regress:
	bash $(SCRIPTS)/regress.sh 05.Verification/soc/sim/tests.list $(REGRESS_TB) $(REGRESS_OUT) \
	  $(MESHES)

cov-merge:
	$(PYTHON) 03.Reference/tools/cov_merge.py $(BUILD)/uvm --out $(REGRESS_OUT)/coverage.md

# The library is not in the repository: 07.Synthesis/lib/ points at a local copy of gsclib045.
syn-one:
	@mkdir -p $(BUILD)/syn
	SYN_TOP=$(SYN_TOP) SYN_RUN=$(SYN_RUN) SYN_PERIOD=$(SYN_PERIOD) SYN_PARAMS='$(SYN_PARAMS)' SYN_EFFORT=$(SYN_EFFORT) 	  $(GENUS) -no_gui -f $(SYN_DIR)/scripts/syn_block.tcl -log $(BUILD)/syn/$(SYN_RUN).log > /dev/null
	@bash $(SCRIPTS)/syn_verdict.sh $(SYN_DIR)/runs/$(SYN_RUN) $(BUILD)/syn/$(SYN_RUN).log

clean:
	rm -rf $(BUILD)
