# CPU Design: 5-Stage Pipelined RISC-V CPU

A 32-bit RISC-V (RV32I) processor core written in SystemVerilog, featuring a classic 5-stage in-order pipeline. This project focuses heavily on cycle-accurate hazard resolution, implementing full data forwarding, dynamic pipeline stalling, and global branch squashing to maximize Instructions Per Cycle (IPC).

## 🏗️ Architecture Overview

The pipeline consists of the classic 5 stages, governed by a centralized Control Unit:

1. **Fetch (IF):** PC generation and Instruction Memory access.
2. **Decode (ID):** Instruction decoding, Register File read, and local Hazard Detection.
3. **Execute (EX):** ALU operations, Address Generation (AGU), and Branch target calculation.
4. **Memory (MEM):** Data Memory access.
5. **Write-Back (WB):** Committing results to the Register File.
* **Control Unit (CU):** A centralized hazard manager that monitors branch resolution and invalid states to globally flush affected pipeline stages.

## ⚡ Key Features & Hazard Resolution

This core does not rely on compiler-inserted NOPs. It handles RAW data hazards and control flow interruptions dynamically in hardware.

### Data Hazard Mitigation
* **Full Data Forwarding (Bypassing):**
  * `EX-to-EX` Forwarding: Resolves back-to-back ALU dependencies with 0 stall cycles.
  * `MEM-to-EX` Forwarding: Resolves dependencies from older instructions.
  * `WB-to-EX` Forwarding: Safely catches data exiting the pipeline.
* **Dynamic Pipeline Stalling:**
  * **Load-Use Hazard Detection:** A dedicated hazard unit detects if an instruction requires data from a `LOAD` currently in the Execute stage.
  * **Pipeline Bubbles:** Automatically freezes the PC and IF/ID registers while injecting a deterministic "Bubble" (NOP) into the EX stage, resulting in exactly a 1-cycle penalty for Load-Use hazards.
* **Shadow Register Rollback:** The Fetch stage utilizes a shadow register to safely hold and re-request instruction addresses during pipeline stalls.

### Control Flow & Exception Handling
* **Dynamic Branch Squashing:** Upon a taken `BEQ` (Branch if Equal), the Control Unit dynamically squashes the Fetch and Decode stages to clear inflight sequential instructions, ensuring safe control flow diversion.
* **Absolute Jumps (`JAL`):** Features hardware-level target calculation, Return Address saving, and automatic pipeline flushing for unconditional jumps.
* **Hardware Exception Trapping:** The pipeline actively monitors for invalid or unrecognized opcodes. Upon detection, it automatically flushes the pipeline and redirects the PC to a dedicated Exception Handler base address (`0x00000000`).

## 🧪 Verification & Testing

The processor is verified using a comprehensive SystemVerilog testbench (`tb_top.sv`).
* **Sparse-Memory Simulation:** Utilizes associative arrays to simulate a massive unified instruction and data memory space without memory overhead, allowing tests to jump cleanly between standard execution (`0x3000`) and exception handling (`0x0000`).
* **Directed Stress Testing:** Includes specific assembly sequences designed to verify forward/backward branch squashing, absolute jumps, and exception trapping cycle-by-cycle.

## 🚀 Quick Start (How to Run)

This project uses the `sim/Makefile` to support two workflows:

1. **Default built-in validation program** (advanced directed test)
2. **File-driven C program flow** (`compiler/<name>.c` -> IMEM/DMEM -> run)

### Default testbench run (no input file)

```bash
cd sim

# Console run (uses tb_advanced default program)
make run_code

# GUI run
make gui_code
```

### Run your own C program

```bash
cd sim

# 1) Build compiler artifacts and memory images from compiler/foo.c
make prep_code file=foo

# Generates:
#   compiler/foo.asm
#   compiler/foo_opcodes.json
#   sim/foo_opcodes.mem   (IMEM)
#   sim/foo_dmem.mem      (DMEM, from .data pool)

# 2) Run in console
make run_code file=foo

# 3) Run in GUI
make gui_code file=foo
```

### Useful low-level targets

```bash
# Compile RTL + tb_top only
make compile

# Compile RTL + tb_advanced only
make compile_advanced

# Clean generated simulation files
make clean
```
