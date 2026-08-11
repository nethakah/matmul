SIM = icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/rtl/datapath.sv $(PWD)/rtl/control.sv $(PWD)/rtl/chip.sv
TOPLEVEL = chip
MODULE = testbench

N ?= 4
COMPILE_ARGS += -Pchip.N=$(N)

export N
export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim