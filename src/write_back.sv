`include "defines.svh"
import defines::*;

module write_back(
    input logic clk,
    input logic resetn,

    // ─────────────────────────────────────────
    // Inputs from Memory Stage (MEM/WB Boundary)
    // ─────────────────────────────────────────
    // These come directly from the pipeline registers in mem.sv
    input logic [DATA_WIDTH-1:0]   wb_mem_data_i,   // The final data (ALU math or RAM data)
    input logic [OPCODE_WIDTH-1:0] wb_opcode_i,     // Passed along for debugging/tracking
    input logic [REG_WIDTH-1:0]    wb_rd_i,         // The destination register address
    input logic                    wb_reg_write_i,  // The write-enable flag
    input logic                    mem_valid_i,     // Is the data coming from MEM valid?

    // ─────────────────────────────────────────
    // Pipeline Control & Handshaking
    // ─────────────────────────────────────────
    output logic wb_ready_o,       // Tells the Memory stage "I am ready"
    input  logic stall_i,          // Global stall signal

    // ─────────────────────────────────────────
    // Outputs to Decode Stage (Register File Write Port)
    // ─────────────────────────────────────────
    output logic                   reg_write_o,     // Triggers the Register File write
    output logic [REG_WIDTH-1:0]   rd_addr_o,       // Points to the correct register (e.g., $5)
    output logic [DATA_WIDTH-1:0]  reg_data_o       // The actual 32-bit data to save
);


assign wb_ready_o = 1'b1;
assign reg_write_o = (mem_valid_i && !stall_i) ? wb_reg_write_i : 1'b0;
assign rd_addr_o  = wb_rd_i;
assign reg_data_o = wb_mem_data_i;


endmodule