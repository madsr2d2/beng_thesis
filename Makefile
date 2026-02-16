#  @file  Makefile
#  @brief GHDL/OSVVM makefile for testbench simulation
#
#  Usage: make TB=src/my_tb
#  Example: make TB=src/bit_stuffer_tb
#
#  Note: OSVVM must be compiled first in OsvvmLibraries/osvvm

# VHDL design files (excluding testbenches)
# Automatically find all files, compile packages and leaf modules first
PACKAGES = $(shell find ./src \( -name "*package.vhd" -o -name "*_pkg.vhd" \) -size +0)
ALL_MODULES = $(shell find ./src -name "*.vhd" ! -name "*package.vhd" ! -name "*_pkg.vhd" ! -name "can_pkg.vhd" ! -name "tx_mac_fsm.vhd" ! -name "*_tb.vhd" -size +0)

# Separate modules into categories based on dependencies
# tx_can depends on mac_tx, tx_llc, and tx_pcs — compiled last
# mac_tx depends on all other MAC sub-modules — compiled second-to-last
TX_CAN = $(filter %tx_can.vhd,$(ALL_MODULES))
MAC_TX = $(filter %tx_mac.vhd,$(ALL_MODULES))
OTHER_MODULES = $(filter-out %tx_mac.vhd %tx_can.vhd,$(ALL_MODULES))

# Separate leaf modules (no dependencies on other design modules) from dependent modules
LEAF_MODULES = $(filter-out %_fd.vhd,$(OTHER_MODULES))
DEPENDENT_MODULES = $(filter %_fd.vhd,$(OTHER_MODULES))

SRCFILES = $(PACKAGES) $(LEAF_MODULES) $(DEPENDENT_MODULES) $(MAC_TX) $(TX_CAN)
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
STOP_TIME = 100us
GHDL_SIM_OPT = --stop-time=$(STOP_TIME)
GHWFILE = ${SIMDIR}/${TESTBENCHFILE}.ghw
VCDFILE = ${SIMDIR}/${TESTBENCHFILE}.vcd

GTKWAVE_DIR = gtk_wave
GTKWFILE = ${GTKWAVE_DIR}/${TESTBENCHFILE}.gtkw

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
	@$(GHDL_CMD) -r $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCHFILE) --wave=$(GHWFILE) $(GHDL_SIM_OPT)
	@echo "Simulation finished. Waveform saved to $(GHWFILE)"

view:
	@if [ -f "$(GTKWFILE)" ]; then \
		$(WAVEFORM_VIEWER) $(GHWFILE) $(GTKWFILE) & \
	else \
		echo "Warning: GTKWave config file not found at $(GTKWFILE)"; \
		$(WAVEFORM_VIEWER) $(GHWFILE) & \
	fi

clean:
	@rm -rf $(SIMDIR) OsvvmTemp_GHDL
