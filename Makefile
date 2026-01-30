# Makefile for GHDL Workflow

# Constants
GHDL = ghdl
FLAGS = --std=08
SIMDIR = sim
SIM_TIME = 2000

# Files
FILES = src/*.vhd

# Default Testbench (can be overridden via command line: make TB=src/my_tb.vhd)
TB ?= 
SIM_ENTITY = $(basename $(notdir $(TB)))
WAVE_FILE = $(SIMDIR)/$(SIM_ENTITY).vcd

# Default target
all: run

# Create simulation directory
$(SIMDIR):
	mkdir -p $(SIMDIR)

# Import sources
import: $(SIMDIR)
	$(GHDL) -i $(FLAGS) --workdir=$(SIMDIR) $(FILES)

# Check if TB variable is set
check_tb:
	@if [ -z "$(TB)" ]; then \
		echo "Error: TB variable not set. Usage: make TB=my_testbench"; \
		exit 1; \
	fi

# Build (Analyze + Elaborate automatically)
build: check_tb import
	$(GHDL) -m $(FLAGS) --workdir=$(SIMDIR) $(SIM_ENTITY)

# Run Simulation
run: build
	$(GHDL) -r $(FLAGS) --workdir=$(SIMDIR) $(SIM_ENTITY) --vcd=$(WAVE_FILE) --stop-time=$(SIM_TIME)ns
	@echo "Simulation finished. Waveform saved to $(WAVE_FILE)"

# View Waveform
wave: run
	gtkwave $(WAVE_FILE) &

# Clean up
clean:
	$(GHDL) --clean --workdir=$(SIMDIR)
	rm -rf $(SIMDIR)

.PHONY: all import check_tb build run wave clean
