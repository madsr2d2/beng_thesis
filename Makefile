#  @file  Makefile
#  @brief GHDL/OSVVM makefile for testbench simulation
#
#  Usage: make TB=src/my_tb
#  Example: make TB=src/bit_stuffer_tb
#
#  Note: OSVVM must be compiled first in OsvvmLibraries/osvvm

# VHDL design files (excluding testbenches)
# Leaf modules (no dependencies on other design files)
LEAF_MODULES = ./src/mod_n.vhd ./src/parity.vhd ./src/gray.vhd ./src/shift_reg.vhd

# Modules that depend on leaf modules
DEPENDENT_MODULES = ./src/bit_stuffer.vhd ./src/bit_stuffer_fd.vhd

SRCFILES = $(LEAF_MODULES) $(DEPENDENT_MODULES)
VHDLEX = .vhd

# OSVVM library path (where TCL build compiled it)
OSVVM_LIB_PATH = $(CURDIR)/OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-4.1.0

# Testbench configuration
TB ?=
TB_NOEXT = $(basename $(TB))
TESTBENCHFILE = $(notdir $(TB_NOEXT))
TESTBENCHPATH = $(TB_NOEXT)$(VHDLEX)

# GHDL configuration
GHDL_CMD = ghdl
GHDL_FLAGS = --std=08 --warn-no-vital-generic -P$(OSVVM_LIB_PATH) -P.

SIMDIR = sim
STOP_TIME = 10000ns
GHDL_SIM_OPT = --stop-time=$(STOP_TIME)
VCDFILE = ${SIMDIR}/${TESTBENCHFILE}.vcd

WAVEFORM_VIEWER = gtkwave

.PHONY: all compile run view clean

all: clean compile run view

compile:
	@if [ -z "$(TB)" ]; then \
		echo "Error: TB not set. Usage: make TB=src/my_tb"; \
		exit 1; \
	fi
	@if [ ! -d "$(OSVVM_LIB_PATH)/osvvm/v08" ]; then \
		echo "Error: OSVVM not compiled. Build it first in OsvvmLibraries/osvvm"; \
		exit 1; \
	fi
	@mkdir -p $(SIMDIR)
	@cp -r OsvvmLibraries/osvvm/OsvvmTemp_GHDL . 2>/dev/null || true
	@echo "Compiling design and testbench..."
	@$(GHDL_CMD) -a $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(SRCFILES)
	@$(GHDL_CMD) -a $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCHPATH)
	@echo "Elaborating $(TESTBENCHFILE)..."
	@$(GHDL_CMD) -m $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCHFILE)

run:
	@$(GHDL_CMD) -r $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCHFILE) --vcd=$(VCDFILE) $(GHDL_SIM_OPT)
	@echo "Simulation finished. Waveform saved to $(VCDFILE)"

view:
	@$(WAVEFORM_VIEWER) $(VCDFILE) &

clean:
	@rm -rf $(SIMDIR) OsvvmTemp_GHDL
