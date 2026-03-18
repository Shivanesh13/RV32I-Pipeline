`include "defines.svh"
import defines::*;

module write_back(
    input logic clk,
    input logic resetn,

    // ─────────────────────────────────────────
    // Inputs from Memory Stage (MEM/WB Boundary)
    // ─────────────────────────────────────────
    // These come directly from the pipeline registers in mem.sv
    input logic [DATA_WIDTH-1:0]   wb_mem_data_i,   
    input logic [OPCODE_WIDTH-1:0] wb_opcode_i,     
    input logic [REG_WIDTH-1:0]    wb_rd_i,         
    input logic                    wb_reg_write_i,  
    input logic                    mem_valid_i,     

    // ─────────────────────────────────────────
    // Pipeline Control & Handshaking
    // ─────────────────────────────────────────
    output logic wb_ready_o,       // Tells the Memory stage "I am ready"
    input  logic stall_i,          

    // ─────────────────────────────────────────
    // Outputs to Decode Stage (Register File Write Port)
    // ─────────────────────────────────────────
    output logic                   reg_write_o,     
    output logic [REG_WIDTH-1:0]   rd_addr_o,       
    output logic [DATA_WIDTH-1:0]  reg_data_o       
);


assign wb_ready_o = 1'b1;
assign reg_write_o = (mem_valid_i && !stall_i) ? wb_reg_write_i : 1'b0;
assign rd_addr_o  = wb_rd_i;
assign reg_data_o = wb_mem_data_i;


endmodule