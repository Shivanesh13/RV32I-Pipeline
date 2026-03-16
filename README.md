# CPU Design: 5-Stage Pipelined RISC-V CPU

A 32-bit RISC-V (RV32I) processor core written in SystemVerilog, featuring a classic 5-stage in-order pipeline. This project focuses heavily on cycle-accurate hazard resolution, implementing full data forwarding and pipeline stalling to maximize Instructions Per Cycle (IPC).



## 🏗️ Architecture Overview

The pipeline consists of the classic 5 stages:
1.  **Fetch (IF):** PC generation and Instruction Memory access.
2.  **Decode (ID):** Instruction decoding, Register File read, and Hazard Detection.
3.  **Execute (EX):** ALU operations, Address Generation (AGU), and Branch target calculation.
4.  **Memory (MEM):** Data Memory access.
5.  **Write-Back (WB):** Committing results to the Register File.

## ⚡ Key Features & Hazard Resolution

This core does not rely on compiler-inserted NOPs. It handles all Read-After-Write (RAW) data hazards dynamically in hardware.

* **Full Data Forwarding (Bypassing):**
    * `EX-to-EX` Forwarding: Resolves back-to-back ALU dependencies with 0 stall cycles.
    * `MEM-to-EX` Forwarding: Resolves dependencies from older instructions.
    * `WB-to-EX` Forwarding: Safely catches data exiting the pipeline.
* **Dynamic Pipeline Stalling:**
    * **Load-Use Hazard Detection:** A dedicated hazard unit detects if an instruction requires data from a `LOAD` currently in the Execute stage.
    * **Pipeline Bubbles:** Automatically freezes the PC and IF/ID registers while injecting a deterministic "Bubble" (NOP) into the EX stage, resulting in exactly a 1-cycle penalty for Load-Use hazards.
* **Shadow Register Rollback:** The Fetch stage utilizes a shadow register to safely hold and re-request instruction addresses during pipeline stalls.

## 📂 Directory Structure

```text
├── src/
│   ├── defines.svh        # Global parameters, opcodes, and structs
│   ├── top.sv             # Top-level wrapper
│   ├── fetch.sv           # IF Stage & PC Logic
│   ├── decode.sv          # ID Stage & Hazard unit hookups
│   ├── execute.sv         # EX Stage & ALU
│   ├── memory.sv          # MEM Stage
│   └── write_back.sv      # WB Stage
├── tb/
│   └── tb_top.sv          # Main testbench with deterministic and random stress tests
└── README.md
