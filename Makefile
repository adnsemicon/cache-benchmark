FILE += $(shell find $(CURDIR)/source -type f -name "*.sv")

.PHONY: all
all:
	@make -s clean
	@make -s build
	@cd build && xvlog -sv $(FILE)
	@cd build && xelab tb -s tb -debug all
	@cd build && xsim tb -runall

.PHONY: clean
clean:
	@rm -rf build

build:
	@mkdir build
	@echo "*" > build/.gitignore
