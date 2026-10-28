FILE += $(shell find $(CURDIR)/source -type f -name "*.sv")

.PHONY: all
all:
	@rm -rf build
	@mkdir build
	@echo "*" > build/.gitignore
	@cd build && xvlog -sv $(FILE)
	@cd build && xelab tb -s tb -debug all
	@cd build && xsim tb -runall
