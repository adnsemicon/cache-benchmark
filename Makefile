export SHELL=/bin/bash

REPO_ROOT := $(CURDIR)

TOP ?= simple_cache_tb

BUILD_DIR := $(REPO_ROOT)/build
LOG_DIR := $(REPO_ROOT)/log

XVLOG_CMD += -sv
# Packages must be compiled before modules that import them. Keep this list
# ordered instead of relying on find's filesystem-dependent output.
RTL_SOURCES := $(REPO_ROOT)/source/simple_cache_pkg.sv \
	$(sort $(filter-out $(REPO_ROOT)/source/simple_cache_pkg.sv,$(wildcard $(REPO_ROOT)/source/*.sv)))
TB_SOURCES := $(sort $(wildcard $(REPO_ROOT)/testbench/*.sv))
XVLOG_CMD += $(RTL_SOURCES) $(TB_SOURCES)

EW_HL = | sed "s/.*XSIM 43-4468.*//g" | grep -iE "error:|warning:|" --color=auto

XVLOG ?= xvlog
XELAB ?= xelab
XSIM  ?= xsim

$(BUILD_DIR) $(LOG_DIR):
	@mkdir -p $@
	@echo "*" > $@/.gitignore

$(BUILD_DIR)/snap_$(TOP): $(RTL_SOURCES) $(TB_SOURCES)
	@make -s $(BUILD_DIR)
	@make -s $(LOG_DIR)
	@cd $(BUILD_DIR) && $(XVLOG) $(XVLOG_CMD) -log $(LOG_DIR)/xvlog_$(shell date +%Y%m%d_%H%M%S).log
	@cd $(BUILD_DIR) && $(XELAB) $(TOP) -s snap_$(TOP) -debug all -log $(LOG_DIR)/xelab_$(TOP)_$(shell date +%Y%m%d_%H%M%S).log && (echo "" > $(BUILD_DIR)/snap_$(TOP))

.PHONY: simulate
simulate:
	@make -s $(LOG_DIR)
	@make -s $(BUILD_DIR)/snap_$(TOP)
	@cd $(BUILD_DIR) && $(XSIM) snap_$(TOP) -runall -log $(LOG_DIR)/xsim_$(TOP)_$(shell date +%Y%m%d_%H%M%S).log $(EW_HL)

.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR)

.PHONY: clean_full
clean_full:
	@make -s clean
	@rm -rf $(LOG_DIR)

.PHONY: fs
fs:
	@make -s clean_full
	@make -s simulate TOP=$(TOP)
