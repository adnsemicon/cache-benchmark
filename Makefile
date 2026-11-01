SHELL := /bin/bash

TOP := simple_cache

BUILD_DIR := $(CURDIR)/build
LOG_DIR   := $(CURDIR)/log

# RTL source files
SRC_FILES := $(shell find $(CURDIR)/source \
	-mindepth 1 -maxdepth 1 -name "*.sv")

# Include directory
FILELIST := -i $(CURDIR)/source

# Simulation tools
XVLOG ?= xvlog
XELAB ?= xelab
XSIM  ?= xsim

# Test configuration
TN := default
TR := 1

# Create build and log directories
$(BUILD_DIR) $(LOG_DIR):
	@mkdir -p $@
	@echo "*" > $@/.gitignore

# Compile RTL
.PHONY: compile
compile: | $(BUILD_DIR) $(LOG_DIR)
	@echo "Compiling RTL source files..."
	@cd $(BUILD_DIR) && $(XVLOG) -sv $(FILELIST) $(SRC_FILES) \
		-log $(LOG_DIR)/xvlog.log

# Elaborate design
.PHONY: elaborate
elaborate: compile
	@echo "Elaborating $(TOP)..."
	@cd $(BUILD_DIR) && $(XELAB) $(TOP) \
		-s snap_$(TOP) -debug all \
		-log $(LOG_DIR)/xelab.log

# Run simulation
.PHONY: run
run: elaborate
	@echo "Running $(TOP)..."
	@echo "--testplusarg CLI_TEST_NAME=$(TN)" > $(BUILD_DIR)/xsim_args
	@echo "--testplusarg CLI_TEST_REPEATS=$(TR)" >> $(BUILD_DIR)/xsim_args
	@cd $(BUILD_DIR) && $(XSIM) snap_$(TOP) \
		-f xsim_args -runall \
		-log $(LOG_DIR)/xsim.log

# Build and run
.PHONY: all
all: run

# Clean generated files
.PHONY: clean
clean:
	@echo "Cleaning build and log directories..."
	@rm -rf $(BUILD_DIR) $(LOG_DIR)