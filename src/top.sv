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

    // Data Memory Interface
    output logic [31:0] d_mem_addr,
    output logic [31:0] d_mem_data,
    output logic        d_mem_read,
    output logic        d_mem_write,
    input  logic [31:0] d_mem_data_i, 
    input  logic        d_mem_ready_i 
);

// ─────────────────────────────────────────
// Inter-Stage Wires
// ─────────────────────────────────────────

// Fetch → Decode
logic [31:0] fd_pc;
logic [31:0] fd_inst;
logic        fd_inst_valid;

// Decode → Execute
logic [OPCODE_WIDTH-1:0]      de_opcode;
logic [FUNCT_WIDTH-1:0]       de_funct;
logic [DATA_WIDTH-1:0]        de_rs1;
logic [DATA_WIDTH-1:0]        de_rs2;
logic [IMM_WIDTH-1:0]         de_imm;
logic [JUMP_TARGET_WIDTH-1:0] de_jump_target;
logic [DATA_WIDTH-1:0]        de_pc_o;
logic [REG_WIDTH-1:0]         de_rd;
logic                         de_valid;
logic                         de_pc_valid;

// Execute → Memory
logic [DATA_WIDTH-1:0]   ex_alu_result;
logic [DATA_WIDTH-1:0]   ex_mem_addr;    
logic [DATA_WIDTH-1:0]   ex_mem_data;    
logic [OPCODE_WIDTH-1:0] ex_opcode;
logic [REG_WIDTH-1:0]    ex_rd;
logic                    ex_reg_write;
logic                    ex_mem_read;
logic                    ex_mem_write;
logic                    ex_valid;

// Memory → Write-Back 
logic [DATA_WIDTH-1:0]   mem_wb_data;
logic [OPCODE_WIDTH-1:0] mem_wb_opcode;
logic [REG_WIDTH-1:0]    mem_wb_rd;
logic                    mem_wb_reg_write;
logic                    mem_valid;

// Writeback → Decode (Register file write)
logic                    wb_reg_write;
logic [REG_WIDTH-1:0]    wb_rd_addr;
logic [DATA_WIDTH-1:0]   wb_data;

// Handshaking Signals
logic decode_ready;
logic execute_ready;
logic mem_ready;
logic wb_ready;

// ─────────────────────────────────────────
// Forwarding Loopback Wires
// ─────────────────────────────────────────
logic [REG_WIDTH-1:0]  ex_reg_loopback;
logic [DATA_WIDTH-1:0] ex_data_loopback;
logic                  ex_load_op;
logic [REG_WIDTH-1:0]  mem_reg_loopback;
logic [DATA_WIDTH-1:0] mem_data_loopback;

// ─────────────────────────────────────────
// Control Flow & Squash Wires (NEW)
// ─────────────────────────────────────────
logic                  ex_branch_taken;
logic [DATA_WIDTH-1:0] ex_branch_target;
logic                  ex_jal_taken;
logic [DATA_WIDTH-1:0] ex_jal_target;

logic cu_br_fetch;
logic cu_jal_fetch;
logic cu_exception_fetch;
logic cu_squash_fetch;
logic cu_squash_decode;
logic cu_squash_execute;
logic cu_squash_memory;
logic cu_squash_writeback;

// Global stall placeholder (Decode handles Load-Use internally)
logic global_stall;
assign global_stall = 1'b0;


// ─────────────────────────────────────────
// Control Unit (Global Hazard/Flush Manager)
// ─────────────────────────────────────────
control_unit u_control_unit (
    .branch_taken_i     (ex_branch_taken),
    .branch_target_i    (ex_branch_target),
    .jal_taken_i        (ex_jal_taken),
    .jal_target_i       (ex_jal_target),
    .exception_i        (1'b0), // Tied to 0 for now
    
    .br_fetch_o         (cu_br_fetch),
    .jal_fetch_o        (cu_jal_fetch),
    .exception_fetch_o  (cu_exception_fetch),
    .squash_fetch_o     (cu_squash_fetch),
    .squash_decode_o    (cu_squash_decode),
    .squash_execute_o   (cu_squash_execute),
    .squash_memory_o    (cu_squash_memory),
    .squash_writeback_o (cu_squash_writeback)
);

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
    
    .stall_i          (global_stall),
    .id_ready_i       (decode_ready),
    
    .pc_o             (fd_pc),
    .inst_o           (fd_inst),
    .inst_valid_o     (fd_inst_valid),
    
    // Control Flow Redirects
    .exception_i      (cu_exception_fetch),
    .exception_addr_i (32'h00000000),
    .branch_i         (cu_br_fetch),
    .branch_addr_i    (ex_branch_target),
    .jal_i            (cu_jal_fetch),
    .jal_addr_i       (ex_jal_target)
);

// ─────────────────────────────────────────
// Decode Stage
// ─────────────────────────────────────────
decode u_decode (
    .clk                 (clk),
    .resetn              (resetn),
    .pc_i                (fd_pc),
    .inst_i              (fd_inst),
    .inst_valid_i        (fd_inst_valid),
    .pc_valid_o          (de_pc_valid),
    .pc_o                (de_pc_o),
    
    .stall_i             (global_stall),
    .decode_ready_o      (decode_ready),
    .execute_ready_i     (execute_ready),
    
    .opcode_o            (de_opcode),
    .funct_o             (de_funct),
    .rs1_o               (de_rs1),
    .rs2_o               (de_rs2),
    .rd_o                (de_rd),
    .imm_o               (de_imm),
    .jump_target_o       (de_jump_target),
    .decode_valid_o      (de_valid),
    
    // Write-Back Loop
    .memory_valid_i      (wb_reg_write),
    .memory_ready_o      (),                
    .memory_data_i       (wb_data),
    .memory_addr_i       (wb_rd_addr),
    
    // Forwarding Loopbacks
    .reg_loopback_o      (ex_reg_loopback),
    .data_loopback_o     (ex_data_loopback),
    .load_op_o           (ex_load_op), 
    .reg_mem_loopback_i  (mem_reg_loopback),
    .data_mem_loopback_i (mem_data_loopback),
    
    // Branch Squash
    .squash_decode_i     (cu_squash_decode)
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
    .stall_i          (global_stall),
    .execute_valid_o  (ex_valid),
    
    // Outputs routed to Memory stage
    .alu_result_o     (ex_alu_result),
    .mem_addr_o       (ex_mem_addr), 
    .mem_data_o       (ex_mem_data),
    .opcode_o         (ex_opcode),
    .rd_o             (ex_rd),
    .reg_write_o      (ex_reg_write),
    .mem_read_o       (ex_mem_read),
    .mem_write_o      (ex_mem_write),
    
    // Control Flow Outputs (To Fetch & Control Unit)
    .branch_taken_o   (ex_branch_taken),
    .branch_target_o  (ex_branch_target),
    .jal_taken_o      (ex_jal_taken),
    .jal_target_o     (ex_jal_target),

    // Forwarding Loopbacks (To Decode)
    .reg_loopback_o   (ex_reg_loopback),
    .data_loopback_o  (ex_data_loopback),
    .load_op_o        (ex_load_op),
    
    // Branch Squash
    .squash_execute_i (cu_squash_execute)
);

// ─────────────────────────────────────────
// Memory Stage 
// ─────────────────────────────────────────
memory u_memory (
    .clk                 (clk),
    .resetn              (resetn),
    
    .alu_result_i        (ex_alu_result),
    .mem_data_i          (ex_mem_data),   
    .mem_addr_i          (ex_mem_addr),   
    .opcode_i            (ex_opcode),
    .rd_i                (ex_rd),
    .reg_write_i         (ex_reg_write),
    .mem_read_i          (ex_mem_read),    
    .mem_write_i         (ex_mem_write),   
    .execute_valid_i     (ex_valid),

    .mem_ready_o         (mem_ready),
    .wb_ready_i          (wb_ready),
    .stall_i             (global_stall),
    .mem_valid_o         (mem_valid),

    .dmem_addr_o         (d_mem_addr),
    .dmem_data_o         (d_mem_data),
    .dmem_read_o         (d_mem_read),
    .dmem_write_o        (d_mem_write),
    .dmem_data_i         (d_mem_data_i),  
    .dmem_ready_i        (d_mem_ready_i), 

    .wb_mem_data_o       (mem_wb_data),
    .wb_opcode_o         (mem_wb_opcode),
    .wb_rd_o             (mem_wb_rd),
    .wb_reg_write_o      (mem_wb_reg_write),
    
    // Forwarding Loopbacks (To Decode)
    .reg_loopback_o      (mem_reg_loopback), 
    .data_loopback_o     (mem_data_loopback) 
);

// ─────────────────────────────────────────
// Write-Back Stage 
// ─────────────────────────────────────────
write_back u_write_back (
    .clk              (clk),
    .resetn           (resetn),
    
    .wb_mem_data_i    (mem_wb_data),
    .wb_opcode_i      (mem_wb_opcode),
    .wb_rd_i          (mem_wb_rd),
    .wb_reg_write_i   (mem_wb_reg_write),
    .mem_valid_i      (mem_valid),

    .wb_ready_o       (wb_ready),
    .stall_i          (global_stall),

    .reg_write_o      (wb_reg_write),
    .rd_addr_o        (wb_rd_addr),
    .reg_data_o       (wb_data)
);

endmodule