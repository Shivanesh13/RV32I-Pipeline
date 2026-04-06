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

# Compiler bridge
COMPILER_DIR = ../compiler
TEXT_BASE ?= 0x3000
file ?=
PROGRAM ?= $(if $(file),$(file),program)
SRC_C ?= $(COMPILER_DIR)/$(PROGRAM).c
ASM_OUT ?= $(COMPILER_DIR)/$(PROGRAM).asm
JSON_OPCODES ?= $(COMPILER_DIR)/$(PROGRAM)_opcodes.json
IMEM_MEM ?= ./$(PROGRAM)_opcodes.mem
DMEM_MEM ?= ./$(PROGRAM)_dmem.mem

# Phony targets (targets that don't represent actual files)
.PHONY: all lib compile sim sim_advanced gui clean build_program json_to_mem asm_to_dmem prepare_program sim_program run_program prep_code run_code gui_program run_code_gui gui_code

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

sim_advanced: compile_advanced
	@echo "========================================"
	@echo " Running Advanced Default Program..."
	@echo "========================================"
	$(VSIM) -c -do "run -all; quit" work.tb_advanced

build_program:
	@echo "========================================"
	@echo " Building compiler outputs from C source..."
	@echo "========================================"
	@if [ ! -f "$(SRC_C)" ]; then echo "Missing source file: $(SRC_C)"; exit 1; fi
	cd "$(COMPILER_DIR)" && python3 -m minicc "$(notdir $(SRC_C))" -o "$(notdir $(ASM_OUT))" --opcode-map "$(notdir $(JSON_OPCODES))" --text-base "$(TEXT_BASE)"

json_to_mem:
	@echo "========================================"
	@echo " Converting opcode JSON to IMEM mem..."
	@echo "========================================"
	python3 ./json_to_imem.py --json "$(JSON_OPCODES)" --out "$(IMEM_MEM)"

asm_to_dmem:
	@echo "========================================"
	@echo " Converting ASM .data to DMEM mem..."
	@echo "========================================"
	@if [ ! -f "$(ASM_OUT)" ]; then echo "Missing asm file: $(ASM_OUT)"; exit 1; fi
	python3 ./asm_data_to_dmem.py --asm "$(ASM_OUT)" --out "$(DMEM_MEM)"

prepare_program: build_program json_to_mem asm_to_dmem
	@echo "========================================"
	@echo " Program memories are ready."
	@echo " Generated: $(IMEM_MEM)"
	@echo " Generated: $(DMEM_MEM)"
	@echo "========================================"

sim_program: compile
	@echo "========================================"
	@echo " Running C-program-driven Simulation..."
	@echo "========================================"
	@if [ ! -f "$(IMEM_MEM)" ]; then \
		echo "Missing opcode memory file: $(IMEM_MEM)"; \
		echo "Run: make prep_code file=$(PROGRAM)"; \
		exit 1; \
	fi
	@if [ ! -f "$(DMEM_MEM)" ]; then \
		echo "Missing data memory file: $(DMEM_MEM)"; \
		echo "Run: make prep_code file=$(PROGRAM)"; \
		exit 1; \
	fi
	$(VSIM) -c -do "run -all; quit" work.$(TOP_MODULE) +OPCODES_MEM=$(IMEM_MEM) +DMEM_MEM=$(DMEM_MEM)

# Convenience target:
#   make prep_code file=foo
# expects ../compiler/foo.c and generates foo.asm, foo_opcodes.json, sim/foo_opcodes.mem
#
# Then run:
#   make run_code file=foo
# to compile RTL/testbench and run simulation with sim/foo_opcodes.mem
run_program: sim_program
prep_code: prepare_program
run_code:
	@if [ -n "$(file)" ]; then \
		$(MAKE) run_program PROGRAM="$(file)"; \
	else \
		$(MAKE) sim_advanced; \
	fi

# Optional shorthand:
#   make foo
# behaves like:
#   make prepare_program PROGRAM=foo
#   make run_program PROGRAM=foo
%:
	@if [ -f "$(COMPILER_DIR)/$@.c" ]; then \
		$(MAKE) prepare_program PROGRAM=$@ && $(MAKE) run_program PROGRAM=$@; \
	else \
		echo "Unknown target '$@' and source file $(COMPILER_DIR)/$@.c not found."; \
		exit 1; \
	fi

# ------------------------------------------------------------------------------
# 4. Run Simulation in GUI Mode (Waveform Debugging)
# ------------------------------------------------------------------------------
# -voptargs=+acc: Prevents Questa from optimizing away internal signals so you can see them in waveforms
gui: compile
	@echo "========================================"
	@echo " Launching QuestaSim GUI..."
	@echo "========================================"
	$(VSIM) -voptargs=+acc -do "add wave -r /*; log -r *; run -all" work.$(TOP_MODULE)

gui_program: compile
	@echo "========================================"
	@echo " Launching C-program-driven QuestaSim GUI..."
	@echo "========================================"
	@if [ ! -f "$(IMEM_MEM)" ]; then \
		echo "Missing opcode memory file: $(IMEM_MEM)"; \
		echo "Run: make prep_code file=$(PROGRAM)"; \
		exit 1; \
	fi
	@if [ ! -f "$(DMEM_MEM)" ]; then \
		echo "Missing data memory file: $(DMEM_MEM)"; \
		echo "Run: make prep_code file=$(PROGRAM)"; \
		exit 1; \
	fi
	$(VSIM) -voptargs=+acc -do "add wave -r /*; log -r *; run -all" work.$(TOP_MODULE) +OPCODES_MEM=$(IMEM_MEM) +DMEM_MEM=$(DMEM_MEM)

run_code_gui:
	@if [ -n "$(file)" ]; then \
		$(MAKE) gui_program PROGRAM="$(file)"; \
	else \
		$(MAKE) gui_advanced; \
	fi

gui_code: run_code_gui

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