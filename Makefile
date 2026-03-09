#  @file  Makefile
#  @brief GHDL/OSVVM makefile for testbench simulation
#
#  Usage: make TB=src/my_tb
#  Example: make TB=src/tx_can_tb
#
#  Note: OSVVM must be compiled first in OsvvmLibraries/osvvm

# Project source files in strict dependency order
# 1. Packages
PACKAGES = \
	src/can_types_pkg.vhd \
	src/can_protocol_pkg.vhd \
	src/can_timing_pkg.vhd

# 2. Components and Sub-modules
COMPONENTS = \
	src/bit_stuffer_fd.vhd \
	src/crc_fd.vhd \
	src/tx_mac_ser.vhd \
	src/tx_mac_fsm.vhd

# 3. Layer wrappers and Top-level
LAYERS = \
	src/tx_mac.vhd \
	src/tx_pcs.vhd \
	src/tx_llc.vhd \
	src/llc_frame_adapter.vhd \
	src/tx_can.vhd

SRCFILES = $(PACKAGES) $(COMPONENTS) $(LAYERS)
VHDLEX = .vhd

# OSVVM library path (where TCL build compiled it)
OSVVM_LIB_PATH = $(CURDIR)/OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev

# Testbench configuration
TB ?=
TB_NOEXT = $(basename $(TB))
TESTBENCHFILE = $(notdir $(TB_NOEXT))
TESTBENCHPATH = $(TB_NOEXT)$(VHDLEX)

# GHDL configuration
GHDL_CMD = ghdl
GHDL_FLAGS = --std=08 --warn-no-vital-generic --warn-no-hide -P$(OSVVM_LIB_PATH) -P.

SIMDIR = sim
STOP_TIME ?= 100us
GHDL_SIM_OPT = --stop-time=$(STOP_TIME)
GHWFILE = ${SIMDIR}/${TESTBENCHFILE}.ghw

GTKWAVE_DIR = gtk_wave
GTKWFILE = ${GTKWAVE_DIR}/${TESTBENCHFILE}.gtkw

WAVEFORM_VIEWER = GIO_MODULE_DIR="" gtkwave

.PHONY: all compile run view clean

all: clean compile run view

compile:
	@if [ -z "$(TB)" ]; then \
		echo "Error: TB not set. Usage: make TB=src/my_tb"; \
		exit 1; \
	fi
	@if [ ! -d "$(OSVVM_LIB_PATH)/osvvm/v08" ]; then \
		echo "Error: OSVVM not compiled. Run: tclsh /tmp/build_osvvm3.tcl from project root"; \
		exit 1; \
	fi
	@mkdir -p $(SIMDIR)
	@cp -r OsvvmLibraries/OsvvmTemp_GHDL . 2>/dev/null || true
	@echo "Compiling design..."
	@for file in $(SRCFILES); do \
		echo "  Analyzing $$file"; \
		$(GHDL_CMD) -a $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $$file || exit 1; \
	done
	@echo "Compiling testbench $(TESTBENCHPATH)..."
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
