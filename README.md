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
* **C-like Program Validation:** You can also write C-like input programs in `compiler/<name>.c` and use the compiler flow to generate instruction/data memories, then run those programs directly on the CPU to validate end-to-end behavior.

## 🛠️ Compile Flow Details

The compile pipeline for file-driven testing is:

1. **C source -> Assembly (`.asm`)**
   * `minicc` compiles `compiler/<name>.c` into `compiler/<name>.asm`.
2. **Assembly text section -> Opcode map (`.json`)**
   * The compiler emits `compiler/<name>_opcodes.json` for instruction addresses and encoded words.
3. **Opcode map -> IMEM file (`.mem`)**
   * `sim/json_to_imem.py` converts opcode JSON to `sim/<name>_opcodes.mem`.
4. **Assembly data section -> DMEM file (`.mem`)**
   * `sim/asm_data_to_dmem.py` extracts `.data` `.word` values into `sim/<name>_dmem.mem`.
5. **Simulation launch**
   * `tb_top.sv` loads `+OPCODES_MEM` into IMEM and `+DMEM_MEM` into DMEM, then runs until the last instruction is fetched plus safety cycles.

Use this command to run the full compile pipeline:

```bash
cd sim
make prep_code file=<name>
```

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

## 📊 Performance Characterization

To characterize the microarchitecture's IPC ceiling, a controlled benchmark suite was run using array sum reduction (`N=40`, expected sum = `820`) across four software optimization levels.

Methodology note: Data memory is modeled as single-cycle (zero latency) to isolate pipeline structural hazards from cache effects. Results represent the upper-bound IPC of the pipeline under pure hazard conditions (branch tax and load-use stalls only).

| Test | Optimization | Retired Instr. | Total Cycles | IPC | Speedup |
|---|---|---:|---:|---:|---:|
| x1 | Unroll x1 (baseline) | 247 | 461 | 0.5358 | 1.00x |
| x2 | Unroll x2 | 167 | 261 | 0.6398 | 1.76x |
| x3 | Unroll x4 | 127 | 181 | 0.7017 | 2.54x |
| x4 | Unroll x8 | 107 | 141 | 0.7589 | 3.26x |

### Key Findings

- **IPC paradox (LICM):** Applying Loop Invariant Code Motion caused IPC to decrease even as runtime improved. The compiler eliminated cheap ALU instructions, leaving a higher concentration of expensive memory and branch operations. The metric worsened because only the hard work remained.
- **Physical ceiling at x8:** Test x4 issues 8 back-to-back loads before any `ADD`, saturating the load queue. The diminishing return from x4 to x8 reflects the pipeline approaching its scalar IPC limit, not a scheduling failure.
- **Optimization-pressure bug discovery:** Aggressive unroll levels exposed two latent microarchitectural bugs that were not visible in standard directed tests.

### Bugs Found Under Optimization Pressure

- **WB-to-ID hazard:** Register file lacked internal bypassing. This was mostly invisible in standard tests but catastrophic at x8 unroll. Fixed by implementing WB-to-Decode forwarding.
- **Phantom write bug:** Non-writing instructions (`STORE`, `BRANCH`) were latching stale `rd` addresses, causing the forwarding unit to inject incorrect values into the ALU. Fixed by explicitly zeroing `rd` for non-write opcodes.
