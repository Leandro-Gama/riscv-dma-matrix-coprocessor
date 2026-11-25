# Entry point for the whole flow. Runs inside WSL (cademics-cepedi) from the repo root.
# All paths are relative: the absolute path of the repo contains spaces.

SHELL := /bin/bash

PYTHON      ?= python3
VERIBLE_DIR ?= /opt/verible/bin
XRUN        ?= xrun
SEED        ?= 1
EXTRA       ?=
TEST        ?= env_smoke_test
UNIT_TOP    ?= tb_axil_port_loop

BUILD       := build
SCRIPTS     := 05.Verification/common/scripts
COMMON_DIR  := 05.Verification/common
SMOKE_DIR   := 05.Verification/env_smoke
SMOKE_BUILD := $(BUILD)/env_smoke
UNIT_DIR    := 05.Verification/unit/soc
UNIT_BUILD  := $(BUILD)/unit_soc
UNIT_TOPS   := tb_axil_port_loop tb_mem_data tb_mem_instr tb_axil_arbiter tb_axil_xbar tb_accel_adapter

SYN_DIR     := 07.Synthesis
GENUS       ?= genus
SYN_TOP     ?= soc_axil_xbar
SYN_RUN     ?= xbar_2ns
SYN_PERIOD  ?= 2.0
SYN_PARAMS  ?=
SYN_EFFORT  ?= medium

XRUN_FLAGS  := -uvm -access +rwc -timescale 1ns/1ps

LINT_DIRS := 04.RTL $(COMMON_DIR) $(SMOKE_DIR) $(UNIT_DIR)
LINT_SRCS := $(shell find $(LINT_DIRS) -name '*.sv' 2>/dev/null | sort)

.DEFAULT_GOAL := help

.PHONY: help check test lint elab-smoke sim-smoke elab-unit sim-unit sim-unit-all syn-one clean

help:
	@echo "Targets (run inside WSL from the repo root):"
	@echo "  check       test + lint + elab-smoke + elab-unit (no license needed)"
	@echo "  test        Python unit tests of 03.Reference (stdlib unittest)"
	@echo "  lint        Verible lint of the RTL and the verification sources"
	@echo "  elab-smoke  elaborate the UVM smoke environment"
	@echo "  sim-smoke   simulate the UVM smoke test (needs license), TEST=$(TEST) SEED=$(SEED)"
	@echo "  elab-unit   elaborate every system unit testbench: $(UNIT_TOPS)"
	@echo "  sim-unit    simulate one unit testbench (needs license), UNIT_TOP=$(UNIT_TOP) EXTRA="
	@echo "  sim-unit-all simulate every unit testbench (needs license), SEED=$(SEED)"
	@echo "  syn-one     synthesise one block in Genus, SYN_TOP= SYN_RUN= SYN_PERIOD= SYN_PARAMS= SYN_EFFORT="
	@echo "  clean       remove $(BUILD)/"

check: test lint elab-smoke elab-unit

test:
	$(PYTHON) -m unittest discover -s 03.Reference -t 03.Reference -p 'test_*.py'

lint:
	@if [ -z "$(LINT_SRCS)" ]; then echo "LINT: no sources"; exit 0; fi
	$(VERIBLE_DIR)/verible-verilog-lint --rules_config=.rules.verible_lint $(LINT_SRCS)
	@echo "LINT OK: $(words $(LINT_SRCS)) file(s)"

# Logs are removed first and the xrun exit code is checked, so a stale log never yields a pass.
elab-smoke:
	@mkdir -p $(SMOKE_BUILD) && rm -f $(SMOKE_BUILD)/elab.log
	rc=0; (cd $(SMOKE_BUILD) && $(XRUN) $(XRUN_FLAGS) -elaborate -F ../../$(SMOKE_DIR)/env_smoke.f \
	  -top tb_env_smoke -l elab.log > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/elab_check.sh $(SMOKE_BUILD)/elab.log $$rc

sim-smoke:
	@mkdir -p $(SMOKE_BUILD) && rm -f $(SMOKE_BUILD)/$(TEST)_s$(SEED).log
	rc=0; (cd $(SMOKE_BUILD) && $(XRUN) $(XRUN_FLAGS) -F ../../$(SMOKE_DIR)/env_smoke.f -top tb_env_smoke \
	  +UVM_TESTNAME=$(TEST) -svseed $(SEED) -l $(TEST)_s$(SEED).log > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/uvm_verdict.sh $(SMOKE_BUILD)/$(TEST)_s$(SEED).log $$rc

elab-unit:
	@mkdir -p $(UNIT_BUILD)
	@set -e; for top in $(UNIT_TOPS); do \
	  rm -f $(UNIT_BUILD)/elab_$${top}.log; \
	  rc=0; (cd $(UNIT_BUILD) && $(XRUN) $(XRUN_FLAGS) -elaborate -F ../../$(UNIT_DIR)/unit_soc.f \
	    -top $${top} -l elab_$${top}.log > /dev/null) || rc=$$?; \
	  bash $(SCRIPTS)/elab_check.sh $(UNIT_BUILD)/elab_$${top}.log $$rc; \
	done

sim-unit:
	@mkdir -p $(UNIT_BUILD) && rm -f $(UNIT_BUILD)/$(UNIT_TOP)_s$(SEED).log
	rc=0; (cd $(UNIT_BUILD) && $(XRUN) $(XRUN_FLAGS) -F ../../$(UNIT_DIR)/unit_soc.f -top $(UNIT_TOP) \
	  -svseed $(SEED) $(EXTRA) -l $(UNIT_TOP)_s$(SEED).log > /dev/null) || rc=$$?; \
	bash $(SCRIPTS)/sv_verdict.sh $(UNIT_BUILD)/$(UNIT_TOP)_s$(SEED).log $$rc

sim-unit-all:
	@mkdir -p $(UNIT_BUILD)
	@set -e; for top in $(UNIT_TOPS); do \
	  rm -f $(UNIT_BUILD)/$${top}_s$(SEED).log; \
	  rc=0; (cd $(UNIT_BUILD) && $(XRUN) $(XRUN_FLAGS) -F ../../$(UNIT_DIR)/unit_soc.f -top $${top} \
	    -svseed $(SEED) -l $${top}_s$(SEED).log > /dev/null) || rc=$$?; \
	  bash $(SCRIPTS)/sv_verdict.sh $(UNIT_BUILD)/$${top}_s$(SEED).log $$rc; \
	done

# The library is not in the repository: 07.Synthesis/lib/ points at a local copy of gsclib045.
syn-one:
	@mkdir -p $(BUILD)/syn
	SYN_TOP=$(SYN_TOP) SYN_RUN=$(SYN_RUN) SYN_PERIOD=$(SYN_PERIOD) SYN_PARAMS='$(SYN_PARAMS)' SYN_EFFORT=$(SYN_EFFORT) 	  $(GENUS) -no_gui -f $(SYN_DIR)/scripts/syn_block.tcl -log $(BUILD)/syn/$(SYN_RUN).log > /dev/null
	@bash $(SCRIPTS)/syn_verdict.sh $(SYN_DIR)/runs/$(SYN_RUN) $(BUILD)/syn/$(SYN_RUN).log

clean:
	rm -rf $(BUILD)
