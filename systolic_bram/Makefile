SIM = icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/rtl/datapath.sv $(PWD)/rtl/control.sv $(PWD)/rtl/chip.sv $(PWD)/rtl/array.sv $(PWD)/rtl/pe.sv $(PWD)/rtl/bram.sv
TOPLEVEL = chip
MODULE = testbench

# matrix dims: A is MxN, B is NxK, C is MxK
M ?= 4
N ?= 4
K ?= 4

# push params into the RTL (icarus) and the testbench (env)
COMPILE_ARGS += -Pchip.M=$(M) -Pchip.N=$(N) -Pchip.K=$(K)
export M
export N
export K

export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim