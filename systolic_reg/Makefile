SIM = icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/rtl/datapath.sv $(PWD)/rtl/control.sv $(PWD)/rtl/chip.sv $(PWD)/rtl/array.sv $(PWD)/rtl/pe.sv
TOPLEVEL = chip
MODULE = testbench

export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim