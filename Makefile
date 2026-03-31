#  @file  Makefile
#  @brief GHDL/OSVVM makefile for testbench simulation
#
#  Usage: make TB=src/my_tb
#  Example: make TB=src/can_tx_tb
#
#  OSVVM setup:
#    OsvvmLibraries/
#      src/osvvm/     - OSVVM core sources (github.com/OSVVM/osvvm)
#      src/common/    - OSVVM Common sources (github.com/OSVVM/OSVVM-Common)
#      src/scripts/   - OSVVM TCL build scripts (github.com/OSVVM/OSVVM-Scripts)
#      lib/osvvm/     - Compiled osvvm library
#      lib/osvvm_common/ - Compiled osvvm_common library
#      OsvvmTemp_GHDL/  - OSVVM runtime temp directory
#
#  To rebuild OSVVM libraries:
#    tclsh OsvvmLibraries/build.tcl

# Project source files in strict dependency order
# 1. Packages
PACKAGES = \
	src/can_types_pkg.vhd \
	src/can_timing_pkg.vhd

# 2. Components and Sub-modules
COMPONENTS = \
	src/can_mac_bs.vhd \
	src/can_mac_crc.vhd \
	src/can_mac_ser_tx.vhd \
	src/can_mac_fsm_tx.vhd \
	src/can_fce.vhd

# 3. Layer wrappers and Top-level
LAYERS = \
	src/can_mac_tx.vhd \
	src/can_pcs_tx.vhd \
	src/can_llc_tx.vhd \
	src/can_tx.vhd

SRCFILES = $(PACKAGES) $(COMPONENTS) $(LAYERS)
VHDLEX = .vhd

# OSVVM compiled library paths
OSVVM_DIR     = $(CURDIR)/OsvvmLibraries
OSVVM_LIB     = $(OSVVM_DIR)/lib

# Testbench configuration
TB ?=
TB_NOEXT = $(basename $(TB))
TESTBENCHFILE = $(notdir $(TB_NOEXT))
TESTBENCHPATH = $(TB_NOEXT)$(VHDLEX)

# GHDL configuration
GHDL_CMD = ghdl
GHDL_FLAGS = --std=08 -fpsl -frelaxed --warn-no-vital-generic --warn-no-hide \
	-P$(OSVVM_LIB)/osvvm/v08 -P$(OSVVM_LIB)/osvvm_common/v08 -P$(OSVVM_LIB) -P.

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
	@if [ ! -d "$(OSVVM_LIB)/osvvm/v08" ]; then \
		echo "Error: OSVVM not compiled. Run: tclsh OsvvmLibraries/build.tcl"; \
		exit 1; \
	fi
	@mkdir -p $(SIMDIR)
	@mkdir -p $(OSVVM_DIR)/OsvvmTemp_GHDL
	@echo "Compiling design..."
	@for file in $(SRCFILES); do \
		echo "  Analyzing $$file"; \
		$(GHDL_CMD) -a $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $$file || exit 1; \
	done
	@echo "Compiling testbench $(TESTBENCHPATH)..."
	@$(GHDL_CMD) -a $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCHPATH)
	@echo "Elaborating $(TESTBENCHFILE)..."
	@$(GHDL_CMD) -m $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work -o $(SIMDIR)/$(TESTBENCHFILE) $(TESTBENCHFILE)

run:
	@$(SIMDIR)/$(TESTBENCHFILE) --wave=$(GHWFILE) --psl-report=$(SIMDIR)/$(TESTBENCHFILE)_psl.json $(GHDL_SIM_OPT)
	@echo "Simulation finished. Waveform saved to $(GHWFILE)"
	@if [ -f "$(SIMDIR)/$(TESTBENCHFILE)_psl.json" ]; then echo "PSL report saved to $(SIMDIR)/$(TESTBENCHFILE)_psl.json"; fi

view:
	@if [ -f "$(GTKWFILE)" ]; then \
		$(WAVEFORM_VIEWER) $(GHWFILE) $(GTKWFILE) & \
	else \
		echo "Warning: GTKWave config file not found at $(GTKWFILE)"; \
		$(WAVEFORM_VIEWER) $(GHWFILE) & \
	fi

clean:
	@rm -rf $(SIMDIR)
	@rm -f *.o e~*.o work-obj08.cf
