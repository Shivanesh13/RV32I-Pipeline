# ==============================================================================
# QuestaSim / ModelSim Makefile for Quant-RV
# ==============================================================================

# Directories
SRC_DIR = src
TB_DIR  = sim

# Simulator Tools
VLIB = vlib
VLOG = vlog
VSIM = vsim

# Compilation Flags
# -sv: Enables SystemVerilog parsing
# +incdir+: Tells the compiler where to look for `include "defines.svh"
VLOG_FLAGS = -sv +incdir+$(SRC_DIR)

# Top-level Testbench Module Name
TOP_MODULE = tb_top

# Phony targets (targets that don't represent actual files)
.PHONY: all lib compile sim gui clean

# Default target when you just type 'make'
all: clean compile sim

# ------------------------------------------------------------------------------
# 1. Create the Working Library
# ------------------------------------------------------------------------------
lib:
	$(VLIB) work

# ------------------------------------------------------------------------------
# 2. Compile the RTL and Testbench
# ------------------------------------------------------------------------------
compile: lib
	@echo "========================================"
	@echo " Compiling SystemVerilog Sources..."
	@echo "========================================"
	$(VLOG) $(VLOG_FLAGS) ../$(SRC_DIR)/*.sv ../$(TB_DIR)/tb_top.sv

compile_advanced: lib
	@echo "========================================"
	@echo " Compiling SystemVerilog Sources..."
	@echo "========================================"
	$(VLOG) $(VLOG_FLAGS) ../$(SRC_DIR)/*.sv ../$(TB_DIR)/tb_advanced.sv

# ------------------------------------------------------------------------------
# 3. Run Simulation in Console (Batch Mode)
# ------------------------------------------------------------------------------
# -c: Command-line mode (no GUI)
# -do: Executes a TCL command (run everything, then quit)
sim: compile
	@echo "========================================"
	@echo " Running Simulation (Console Mode)..."
	@echo "========================================"
	$(VSIM) -c -do "run -all; quit" work.$(TOP_MODULE)

# ------------------------------------------------------------------------------
# 4. Run Simulation in GUI Mode (Waveform Debugging)
# ------------------------------------------------------------------------------
# -voptargs=+acc: Prevents Questa from optimizing away internal signals so you can see them in waveforms
gui: compile
	@echo "========================================"
	@echo " Launching QuestaSim GUI..."
	@echo "========================================"
	$(VSIM) -voptargs=+acc -do "add wave -r /*; log -r *; run -all" work.$(TOP_MODULE)

gui_advanced: compile_advanced
	@echo "========================================"
	@echo " Launching QuestaSim GUI..."
	@echo "========================================"
	$(VSIM) -voptargs=+acc -do "add wave -r /*; log -r *; run -all" work.tb_advanced

# ------------------------------------------------------------------------------
# 5. Clean Generated Files
# ------------------------------------------------------------------------------
clean:
	@echo "Cleaning up simulation files..."
	rm -rf work transcript vsim.wlf *.wlf modelsim.ini