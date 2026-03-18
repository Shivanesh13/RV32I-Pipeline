`include "defines.svh"
import defines::*;
module decode(
    input logic clk,
    input logic resetn,

    // Instruction Memory Interface
    input logic [31:0] pc_i,
    input logic [31:0] inst_i,
    input logic inst_valid_i,

    // Instruction Register Interface
    output logic pc_valid_o,
    output logic [DATA_WIDTH-1:0] pc_o,
    // Pipeline Control
    input logic stall_i,
    output logic decode_ready_o,
    input logic execute_ready_i,

    // Outputs to Execute Stage
    output logic [OPCODE_WIDTH-1:0] opcode_o,
    output logic [FUNCT_WIDTH-1:0] funct_o,
    output logic [DATA_WIDTH-1:0] rs1_o,
    output logic [DATA_WIDTH-1:0] rs2_o,
    //output logic [DATA_WIDTH-1:0] rd_o,
    output logic [IMM_WIDTH-1:0] imm_o,
    output logic [JUMP_TARGET_WIDTH-1:0] jump_target_o,
    output logic [REG_WIDTH-1:0] rd_o,

    output logic decode_valid_o,
    input logic memory_valid_i,
    output logic memory_ready_o,
    input logic [DATA_WIDTH-1:0] memory_data_i,
    input logic [ADDR_WIDTH-1:0] memory_addr_i,

    input logic [REG_WIDTH-1:0] reg_loopback_o,
    input logic [DATA_WIDTH-1:0] data_loopback_o,
    input logic load_op_o,


    input logic [REG_WIDTH-1:0] reg_mem_loopback_i,
    input logic [DATA_WIDTH-1:0] data_mem_loopback_i,
    input logic squash_decode_i,

    output logic invalid_inst_o
);

logic [DATA_WIDTH-1:0] pc_reg;
logic [DATA_WIDTH-1:0] instr_reg;
logic [DATA_WIDTH-1:0] MEM_DATA[0:31];


logic [REG_WIDTH-1:0] mem_rd;
logic [REG_WIDTH-1:0] ex_rd, reg_data_0, reg_data_1;



always_ff @(posedge clk or negedge resetn) begin : blockName
    if(!resetn) begin
            // Hardwire r0 to 0 (RISC-V standard)
            MEM_DATA[0] <= 32'h00000000;
            MEM_DATA[1] <= 32'd100;
            MEM_DATA[2] <= 32'd50; 
            for(int i = 3; i < 32; i++) begin
                MEM_DATA[i] <= 32'h00000000;
            end
            memory_ready_o <= 1'b0;
    end else begin
        memory_ready_o <= 1'b1;
        if(memory_valid_i) begin
            if(memory_addr_i != 5'b00000)begin
                MEM_DATA[memory_addr_i] <= memory_data_i;
            end
        end
    end
end


logic [DATA_WIDTH-1:0] rs1_reg, rs2_reg;
logic inst_valid_i_d;

always_comb begin
    decode_ready_o = execute_ready_i && !stall_i;
    if(reg_mem_loopback_i == inst_i[25:21]) begin
        rs1_reg = data_mem_loopback_i;
    end 
    else if(reg_loopback_o == inst_i[25:21]) begin
        rs1_reg = data_loopback_o;
        decode_ready_o = execute_ready_i && !stall_i && !load_op_o;
    end else if(memory_addr_i == inst_i[25:21]) begin
        rs1_reg = memory_data_i;
    end else begin
        rs1_reg = MEM_DATA[inst_i[25:21]];
    end

    if(reg_mem_loopback_i == inst_i[20:16]) begin
        rs2_reg = data_mem_loopback_i;
    end else if(reg_loopback_o == inst_i[20:16]) begin
        rs2_reg = data_loopback_o;
        decode_ready_o = execute_ready_i && !stall_i && !load_op_o;
    end else if(memory_addr_i == inst_i[20:16]) begin
        rs2_reg = memory_data_i;
    end else begin
        rs2_reg = MEM_DATA[inst_i[20:16]];
    end
end 

always_ff @(posedge clk or negedge resetn) begin
    if(!resetn) begin
        pc_valid_o <= 1'b0;
        pc_o <= 32'h00000000;
        opcode_o <= 6'b000000;
        funct_o <= 6'b000000;
        rs1_o <= 32'h00000000;
        rs2_o <= 32'h00000000;
        rd_o <= 5'b00000;
        imm_o <= 16'h0000;
        jump_target_o <= 26'h0000000;
        //decode_ready_o <= 1'b0;
        invalid_inst_o <= 1'b0;
        decode_valid_o <= 1'b0;
    end else begin
        if(squash_decode_i) begin
            invalid_inst_o <= 1'b0;
            decode_valid_o <= 1'b0;
            pc_valid_o <= 1'b0;
            pc_o <= 32'h00000000;
            opcode_o <= 6'b000000;
            funct_o <= 6'b000000;
            rs1_o <= 32'h00000000;
            rs2_o <= 32'h00000000;
        end
        else if(inst_valid_i && decode_ready_o) begin
            pc_o <= pc_i;
            case(inst_i[31:26])
                R_OPCODE: begin
                    opcode_o <= R_OPCODE;
                    funct_o <= inst_i[5:0];
                    rs1_o <= rs1_reg;
                    rs2_o <= rs2_reg;
                    rd_o <= inst_i[15:11];
                    pc_valid_o <= 1'b1;
                    invalid_inst_o <= 1'b0;
                end
                LOAD_OPCODE: begin
                    opcode_o <= LOAD_OPCODE;
                    rs1_o <= rs1_reg;
                    rd_o <= inst_i[20:16];
                    imm_o <= inst_i[15:0];
                    invalid_inst_o <= 1'b0;
                end
                STORE_OPCODE: begin
                    opcode_o <= STORE_OPCODE;
                    rs1_o <= rs1_reg;
                    rs2_o <= rs2_reg;
                    imm_o <= inst_i[15:0];
                    pc_valid_o <= 1'b1;
                    invalid_inst_o <= 1'b0;
                end
                BRANCH_OPCODE: begin
                    opcode_o <= BRANCH_OPCODE;
                    rs1_o <= rs1_reg;
                    rs2_o <= rs2_reg;
                    imm_o <= inst_i[15:0];
                    pc_valid_o <= 1'b1;
                    invalid_inst_o <= 1'b0;
                end
                JAL_OPCODE: begin
                    opcode_o <= JAL_OPCODE;
                    jump_target_o <= inst_i[25:0];
                    pc_valid_o <= 1'b1;
                    invalid_inst_o <= 1'b0;
                end
                default: begin
                    opcode_o <= 6'b000000;
                    funct_o <= 6'b000000;
                    rs1_o <= 32'h00000000;
                    rs2_o <= 32'h00000000;
                    rd_o <= 5'b00000;
                    imm_o <= 16'h0000;
                    pc_valid_o <= 1'b0;
                    invalid_inst_o <= 1'b1;
                end
            endcase
            decode_valid_o <= 1'b1;
        end else begin
            decode_valid_o <= 1'b0;
            pc_valid_o <= 1'b0;
            pc_o <= 32'h00000000;
            opcode_o <= 6'b000000;
            funct_o <= 6'b000000;
            rs1_o <= 32'h00000000;
            rs2_o <= 32'h00000000;
            rd_o <= 5'b00000;
            imm_o <= 16'h0000;
            jump_target_o <= 26'h0000000;
        end
    end
end 

endmodule