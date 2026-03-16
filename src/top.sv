`include "defines.svh"
import defines::*;

module top (
    input logic clk,
    input logic resetn,

    // Instruction Memory Interface
    output logic [31:0] i_mem_addr,
    input  logic [31:0] i_mem_data,
    input  logic        i_mem_valid,
    output logic        i_mem_read,
    input  logic        i_mem_ready,

    // Data Memory Interface (Driven by Memory Stage)
    output logic [31:0] d_mem_addr,
    output logic [31:0] d_mem_data,
    output logic        d_mem_read,
    output logic        d_mem_write,
    input  logic [31:0] d_mem_data_i, // Data returning from RAM
    input  logic        d_mem_ready_i // RAM ready signal
);

// ─────────────────────────────────────────
// Fetch → Decode signals
// ─────────────────────────────────────────
logic [31:0] fd_pc;
logic [31:0] fd_inst;
logic        fd_inst_valid;

// ─────────────────────────────────────────
// Decode → Execute signals
// ─────────────────────────────────────────
logic [OPCODE_WIDTH-1:0]      de_opcode;
logic [FUNCT_WIDTH-1:0]       de_funct;
logic [DATA_WIDTH-1:0]        de_rs1;
logic [DATA_WIDTH-1:0]        de_rs2;
logic [IMM_WIDTH-1:0]         de_imm;
logic [JUMP_TARGET_WIDTH-1:0] de_jump_target;
logic [DATA_WIDTH-1:0]        de_pc;
logic [REG_WIDTH-1:0]         de_rd;
logic                         de_valid;
logic [DATA_WIDTH-1:0]        de_pc_o;
logic                         de_pc_valid;

// ─────────────────────────────────────────
// Execute → Memory signals 
// ─────────────────────────────────────────
logic [DATA_WIDTH-1:0]   ex_alu_result;
logic [DATA_WIDTH-1:0]   ex_mem_addr;    // NEW: Wire for the dedicated address port
logic [DATA_WIDTH-1:0]   ex_mem_data;    // Data to store
logic [OPCODE_WIDTH-1:0] ex_opcode;
logic [REG_WIDTH-1:0]    ex_rd;
logic                    ex_reg_write;
logic                    ex_mem_read;
logic                    ex_mem_write;
logic                    ex_valid;

// ─────────────────────────────────────────
// Memory → Write-Back signals 
// ─────────────────────────────────────────
logic [DATA_WIDTH-1:0]   mem_wb_data;
logic [OPCODE_WIDTH-1:0] mem_wb_opcode;
logic [REG_WIDTH-1:0]    mem_wb_rd;
logic                    mem_wb_reg_write;
logic                    mem_valid;

// ─────────────────────────────────────────
// Writeback → Decode (Register file write)
// ─────────────────────────────────────────
logic                    wb_reg_write;
logic [REG_WIDTH-1:0]    wb_rd_addr;
logic [DATA_WIDTH-1:0]   wb_data;

// ─────────────────────────────────────────
// Handshaking & Stall signals
// ─────────────────────────────────────────
logic fetch_stall;
logic decode_ready;
logic decode_stall;
logic execute_ready;
logic mem_ready;
logic wb_ready;

// Branch/Jump signals
logic                    ex_branch_taken;
logic [DATA_WIDTH-1:0]   ex_branch_target;
logic                    ex_jal_taken;
logic [DATA_WIDTH-1:0]   ex_jal_target;


logic [REG_WIDTH-1:0] ex_reg_loopback;
logic [DATA_WIDTH-1:0] ex_data_loopback;
logic ex_load_op;
logic [REG_WIDTH-1:0] mem_reg_loopback;
    logic [DATA_WIDTH-1:0] mem_data_loopback;


// Global stall logic (Placeholder)
assign fetch_stall  = 1'b0;
assign decode_stall = 1'b0;

// ─────────────────────────────────────────
// Fetch Stage
// ─────────────────────────────────────────
fetch u_fetch (
    .clk              (clk),
    .resetn           (resetn),
    .i_mem_addr       (i_mem_addr),
    .i_mem_data       (i_mem_data),
    .i_mem_valid      (i_mem_valid),
    .i_mem_read       (i_mem_read),
    .i_mem_ready      (i_mem_ready),
    .stall_i          (fetch_stall),
    .id_ready_i       (decode_ready),
    .pc_o             (fd_pc),
    .inst_o           (fd_inst),
    .inst_valid_o     (fd_inst_valid),
    .exception_i      (1'b0),
    .exception_addr_i (32'h00000000),
    .branch_i         (ex_branch_taken | ex_jal_taken),
    .branch_addr_i    (ex_jal_taken ? ex_jal_target : ex_branch_target)
);

// ─────────────────────────────────────────
// Decode Stage
// ─────────────────────────────────────────
decode u_decode (
    .clk              (clk),
    .resetn           (resetn),
    .pc_i             (fd_pc),
    .inst_i           (fd_inst),
    .inst_valid_i     (fd_inst_valid),
    .pc_valid_o       (de_pc_valid),
    .pc_o             (de_pc_o),
    .stall_i          (decode_stall),
    .decode_ready_o   (decode_ready),
    .execute_ready_i  (execute_ready),
    .opcode_o         (de_opcode),
    .funct_o          (de_funct),
    .rs1_o            (de_rs1),
    .rs2_o            (de_rs2),
    .rd_o             (de_rd),
    .imm_o            (de_imm),
    .jump_target_o    (de_jump_target),
    .decode_valid_o   (de_valid),
    
    // Write-Back Loop
    .memory_valid_i   (wb_reg_write),
    .memory_ready_o   (),                
    .memory_data_i    (wb_data),
    .memory_addr_i    (wb_rd_addr),
    .reg_loopback_o (ex_reg_loopback),
    .data_loopback_o (ex_data_loopback),
    .load_op_o (ex_load_op) ,
    .reg_mem_loopback_i (mem_reg_loopback),
    .data_mem_loopback_i (mem_data_loopback)
);

// ─────────────────────────────────────────
// Execute Stage
// ─────────────────────────────────────────
execute u_execute (
    .clk              (clk),
    .resetn           (resetn),
    .opcode_i         (de_opcode),
    .funct_i          (de_funct),
    .rs1_i            (de_rs1),
    .rs2_i            (de_rs2),
    .imm_i            (de_imm),
    .jump_target_i    (de_jump_target),
    .pc_i             (de_pc_o),
    .decode_valid_i   (de_valid),
    .rd_i             (de_rd),
    .execute_ready_o  (execute_ready),
    .mem_ready_i      (mem_ready),     
    .stall_i          (decode_stall),
    .execute_valid_o  (ex_valid),
    
    // Outputs routed to Memory stage
    .alu_result_o     (ex_alu_result),
    .opcode_o         (ex_opcode),
    .rd_o             (ex_rd),
    .reg_write_o      (ex_reg_write),
    
    // WIRED TO INTERNAL NETS (Not external ports)
    .mem_addr_o       (ex_mem_addr), 
    .mem_data_o       (ex_mem_data),
    .mem_read_o       (ex_mem_read),
    .mem_write_o      (ex_mem_write),
    
    // Control flow
    .branch_taken_o   (ex_branch_taken),
    .branch_target_o  (ex_branch_target),
    .jal_taken_o      (ex_jal_taken),
    .jal_target_o     (ex_jal_target),

    // WIRED TO INTERNAL NETS (Not external ports)
    .reg_loopback_o   (ex_reg_loopback),
    .data_loopback_o  (ex_data_loopback),
    .load_op_o        (ex_load_op)
);

// ─────────────────────────────────────────
// Memory Stage 
// ─────────────────────────────────────────
memory u_memory (
    .clk              (clk),
    .resetn           (resetn),
    
    // Inputs from Execute
    .alu_result_i     (ex_alu_result),
    .mem_data_i       (ex_mem_data),   
    .mem_addr_i       (ex_mem_addr),   // FIXED: Accepting the dedicated address wire
    .opcode_i         (ex_opcode),
    .rd_i             (ex_rd),
    .reg_write_i      (ex_reg_write),
    .mem_read_i       (ex_mem_read),    
    .mem_write_i      (ex_mem_write),   
    .execute_valid_i  (ex_valid),

    // Pipeline Control
    .mem_ready_o      (mem_ready),
    .wb_ready_i       (wb_ready),
    .stall_i          (decode_stall),
    .mem_valid_o      (mem_valid),

    // External Memory Ports (Driving the top module ports)
    .dmem_addr_o      (d_mem_addr),
    .dmem_data_o      (d_mem_data),
    .dmem_read_o      (d_mem_read),
    .dmem_write_o     (d_mem_write),
    .dmem_data_i      (d_mem_data_i),  
    .dmem_ready_i     (d_mem_ready_i), 

    // Outputs to Write-Back
    .wb_mem_data_o    (mem_wb_data),
    .wb_opcode_o      (mem_wb_opcode),
    .wb_rd_o          (mem_wb_rd),
    .wb_reg_write_o   (mem_wb_reg_write),
    .reg_loopback_o (mem_reg_loopback),
    .data_loopback_o (mem_data_loopback)
);

// ─────────────────────────────────────────
// Write-Back Stage 
// ─────────────────────────────────────────
write_back u_write_back (
    .clk              (clk),
    .resetn           (resetn),
    
    // Inputs from Memory
    .wb_mem_data_i    (mem_wb_data),
    .wb_opcode_i      (mem_wb_opcode),
    .wb_rd_i          (mem_wb_rd),
    .wb_reg_write_i   (mem_wb_reg_write),
    .mem_valid_i      (mem_valid),

    // Pipeline Control
    .wb_ready_o       (wb_ready),
    .stall_i          (decode_stall),

    // Outputs to Decode (Register File)
    .reg_write_o      (wb_reg_write),
    .rd_addr_o        (wb_rd_addr),
    .reg_data_o       (wb_data)
);

endmodule