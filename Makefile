export SHELL=/bin/bash

REPO_ROOT := $(CURDIR)

TOP := hello

BUILD_DIR := $(REPO_ROOT)/build
LOG_DIR := $(REPO_ROOT)/log

XVLOG_CMD += -i $(REPO_ROOT)/package
XVLOG_CMD += $(shell find $(REPO_ROOT)/package -name "*.sv")
XVLOG_CMD += $(shell find $(REPO_ROOT)/source -name "*.sv")
XVLOG_CMD += $(shell find $(REPO_ROOT)/testbench -name "*.sv")

EW_HL = | sed "s/.*XSIM 43-4468.*//g" | grep -iE "error:|warning:|" --color=auto

XVLOG ?= xvlog
XELAB ?= xelab
XSIM  ?= xsim

$(BUILD_DIR) $(LOG_DIR):
	@mkdir -p $@
	@echo "*" > $@/.gitignore

$(BUILD_DIR)/snap_$(TOP):
	@make -s $(BUILD_DIR)
	@make -s $(LOG_DIR)
	@cd $(BUILD_DIR) && $(XVLOG) -sv -d USE_DRRIP $(XVLOG_CMD) -log $(LOG_DIR)/xvlog_$(shell date +%Y%m%d_%H%M%S).log
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

.PHONY: f 
f: 
	@make -s clean_full
	@make -s simulate