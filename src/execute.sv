`include "defines.svh"
import defines::*;

module execute(
    input  logic                         clk,
    input  logic                         resetn,

    // ─────────────────────────────────────────
    // Inputs from Decode Stage (ID/EX Boundary)
    // ─────────────────────────────────────────
    input  logic [OPCODE_WIDTH-1:0]      opcode_i,
    input  logic [FUNCT_WIDTH-1:0]       funct_i,
    input  logic [DATA_WIDTH-1:0]        rs1_i,
    input  logic [DATA_WIDTH-1:0]        rs2_i,
    input  logic [IMM_WIDTH-1:0]         imm_i,
    input  logic [JUMP_TARGET_WIDTH-1:0] jump_target_i,
    input  logic [DATA_WIDTH-1:0]        pc_i,
    input  logic [REG_WIDTH-1:0]         rd_i,
    input  logic                         decode_valid_i,

    // ─────────────────────────────────────────
    // Pipeline Handshaking
    // ─────────────────────────────────────────
    output logic                         execute_ready_o,
    input  logic                         mem_ready_i,
    input  logic                         stall_i,
    output logic                         execute_valid_o,

    // ─────────────────────────────────────────
    // Outputs to Memory Stage (EX/MEM Boundary)
    // ─────────────────────────────────────────
    output logic [DATA_WIDTH-1:0]        alu_result_o,
    output logic [DATA_WIDTH-1:0]        mem_addr_o,   // Dedicated Address Wire
    output logic [DATA_WIDTH-1:0]        mem_data_o,   // Store Data
    output logic [OPCODE_WIDTH-1:0]      opcode_o,
    output logic [REG_WIDTH-1:0]         rd_o,
    output logic                         reg_write_o,
    output logic                         mem_read_o,
    output logic                         mem_write_o,

    // ─────────────────────────────────────────
    // Control Flow (Branches & Jumps to Fetch)
    // ─────────────────────────────────────────
    output logic                         branch_taken_o,
    output logic [DATA_WIDTH-1:0]        branch_target_o,
    output logic                         jal_taken_o,
    output logic [DATA_WIDTH-1:0]        jal_target_o,

    output logic [REG_WIDTH-1:0]        reg_loopback_o,
    output logic [DATA_WIDTH-1:0]       data_loopback_o,
    output logic                         load_op_o,
    input logic                          squash_execute_i
);

    // ==========================================
    // 1. COMBINATIONAL: ALU & Control Logic
    // ==========================================
    logic [DATA_WIDTH-1:0] alu_math_result;
    logic [DATA_WIDTH-1:0] calculated_mem_addr;
    logic                  is_mem_read;
    logic                  is_mem_write;
    logic                  is_reg_write;

    // Pipeline Readiness
    assign execute_ready_o = mem_ready_i && !stall_i;
    assign reg_loopback_o = rd_i;
    assign data_loopback_o = alu_math_result;
    assign load_op_o = is_mem_read;


    always_comb begin
        // Default Control Signals
        alu_math_result     = 32'h0;
        calculated_mem_addr = 32'h0;
        is_mem_read         = 1'b0;
        is_mem_write        = 1'b0;
        is_reg_write        = 1'b0;
        branch_taken_o      = 1'b0;
        branch_target_o     = 32'h0;
        jal_taken_o         = 1'b0;
        jal_target_o        = 32'h0;

        if (decode_valid_i ) begin
            case (opcode_i)
                R_OPCODE: begin
                    is_reg_write = 1'b1;
                    case (funct_i)
                        ADD: alu_math_result = rs1_i + rs2_i;
                        SUB: alu_math_result = rs1_i - rs2_i;
                        AND: alu_math_result = rs1_i & rs2_i;
                        OR:  alu_math_result = rs1_i | rs2_i;
                        XOR: alu_math_result = rs1_i ^ rs2_i;
                        MUL: alu_math_result = rs1_i * rs2_i;
                        default: alu_math_result = 32'h0;
                    endcase
                end

                LOAD_OPCODE: begin
                    // AGU: Calculate RAM Address
                    calculated_mem_addr = rs1_i + {{16{imm_i[15]}}, imm_i}; // Sign-extended immediate
                    is_mem_read  = 1'b1;
                    is_reg_write = 1'b1;
                end

                STORE_OPCODE: begin
                    // AGU: Calculate RAM Address
                    calculated_mem_addr = rs1_i + {{16{imm_i[15]}}, imm_i};
                    is_mem_write = 1'b1;
                end

                BRANCH_OPCODE: begin
                    // BEQ: target = PC_of_branch + (sign_ext(imm) << 2)  (no extra +4)
                    if (rs1_i == rs2_i) begin
                        branch_taken_o  = 1'b1;
                        branch_target_o = pc_i + {{14{imm_i[15]}}, imm_i, 2'b00};
                    end
                end

                JAL_OPCODE: begin
                    jal_taken_o     = 1'b1;
                    jal_target_o    = {pc_i[31:28], jump_target_i, 2'b00}; // Absolute jump target
                    alu_math_result = pc_i + 4; // Save Return Address
                    is_reg_write    = 1'b1;
                end

                default: ; // Do nothing
            endcase
        end
    end

    // ==========================================
    // 2. SYNCHRONOUS: EX/MEM Pipeline Registers
    // ==========================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            alu_result_o    <= 32'h0;
            mem_addr_o      <= 32'h0;
            mem_data_o      <= 32'h0;
            opcode_o        <= 'h0;
            rd_o            <= 5'h0;
            reg_write_o     <= 1'b0;
            mem_read_o      <= 1'b0;
            mem_write_o     <= 1'b0;
            execute_valid_o <= 1'b0;
        end else begin
            if (decode_valid_i && !stall_i && mem_ready_i && !squash_execute_i) begin
                // Lock in the ALU and AGU calculations
                alu_result_o    <= alu_math_result;
                mem_addr_o      <= calculated_mem_addr;
                if(is_mem_write) 
                    mem_data_o      <= rs2_i; // Pass RS2 straight through for STORE instructions
                else    
                    mem_data_o      <= 32'h0;
                
                // Pass control signals forward
                opcode_o        <= opcode_i;
                rd_o            <= rd_i;
                reg_write_o     <= is_reg_write;
                mem_read_o      <= is_mem_read;
                mem_write_o     <= is_mem_write;
                execute_valid_o <= 1'b1;
            end 
            else if (!stall_i || squash_execute_i) begin
                // Pipeline Bubble
                alu_result_o    <= 32'h0;
                mem_addr_o      <= 32'h0;
                mem_data_o      <= 32'h0;
                opcode_o        <= 'h0;
                rd_o            <= 5'h0;
                reg_write_o     <= 1'b0;
                mem_read_o      <= 1'b0;
                mem_write_o     <= 1'b0;
                execute_valid_o <= 1'b0;
            end
        end
    end

endmodule