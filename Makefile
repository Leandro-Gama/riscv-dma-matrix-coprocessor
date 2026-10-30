# Entry point for the whole flow. Runs inside WSL (cademics-cepedi) from the repo root.
# All paths are relative: the absolute path of the repo contains spaces.

SHELL := /bin/bash

PYTHON      ?= python3
VERIBLE_DIR ?= /opt/verible/bin
XRUN        ?= xrun
SEED        ?= 1
TEST        ?= env_smoke_test

BUILD       := build
SCRIPTS     := 05.Verification/common/scripts
SMOKE_DIR   := 05.Verification/env_smoke
SMOKE_BUILD := $(BUILD)/env_smoke

XRUN_FLAGS  := -uvm -access +rwc -timescale 1ns/1ps

LINT_SRCS := $(shell find 04.RTL $(SMOKE_DIR) -name '*.sv' 2>/dev/null | sort)

.DEFAULT_GOAL := help

.PHONY: help check test lint elab-smoke sim-smoke clean

help:
	@echo "Targets (run inside WSL from the repo root):"
	@echo "  check       test + lint + elab-smoke (no license needed)"
	@echo "  test        Python unit tests of 03.Reference (stdlib unittest)"
	@echo "  lint        Verible lint of 04.RTL and the smoke environment"
	@echo "  elab-smoke  elaborate the UVM smoke environment"
	@echo "  sim-smoke   simulate the UVM smoke test (needs license), TEST=$(TEST) SEED=$(SEED)"
	@echo "  clean       remove $(BUILD)/"

check: test lint elab-smoke

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

clean:
	rm -rf $(BUILD)
