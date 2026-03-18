`timescale 1ns/1ps
`include "../src/defines.svh"
import defines::*;

module tb_top;

    // System Signals
    logic clk;
    logic resetn;

    // IMEM Interface
    logic [31:0] i_mem_addr;
    logic [31:0] i_mem_data;
    logic        i_mem_valid;
    logic        i_mem_read;
    logic        i_mem_ready;

    // DMEM Interface 
    logic [31:0] d_mem_addr;
    logic [31:0] d_mem_data;
    logic        d_mem_read;
    logic        d_mem_write;
    logic [31:0] d_mem_data_i;
    logic        d_mem_ready_i;

    // Simulated Memory Arrays (1024 bytes / 256 words)
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255]; // NEW: Actual Data Memory Array

    // Instantiate the Top Module
    top u_top (
        .clk           (clk),
        .resetn        (resetn),
        .i_mem_addr    (i_mem_addr),
        .i_mem_data    (i_mem_data),
        .i_mem_valid   (i_mem_valid),
        .i_mem_read    (i_mem_read),
        .i_mem_ready   (i_mem_ready),
        .d_mem_addr    (d_mem_addr),
        .d_mem_data    (d_mem_data),
        .d_mem_read    (d_mem_read),
        .d_mem_write   (d_mem_write),
        .d_mem_data_i  (d_mem_data_i),  
        .d_mem_ready_i (d_mem_ready_i)  
    );

    // ==========================================
    // Clock Generation (100 MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // Simulated Memory Logic
    // ==========================================
    assign i_mem_ready   = 1'b1; 
    assign d_mem_ready_i = 1'b1; 

    // IMEM: Synchronous Read
    always_comb begin
        if(i_mem_read) begin
            i_mem_data  = imem[i_mem_addr >> 2];
            i_mem_valid = 1'b1;
        end else begin
            i_mem_data = 32'h0;
            i_mem_valid = 1'b0;
        end
    end

    // DMEM: Synchronous Write, Combinational Read
    //assign d_mem_data_i = (d_mem_read) ? dmem[d_mem_addr >> 2] : 32'h0;

    always_comb begin
        if(!resetn) begin
            d_mem_data_i = 32'h00000000;
            dmem[5] = 32'd100;
        end else begin
        if (d_mem_write) begin
            dmem[d_mem_addr >> 2] = d_mem_data;
        end
        if(d_mem_read) begin
            d_mem_data_i = dmem[d_mem_addr >> 2];
        end else begin
                d_mem_data_i = 32'h00000000;
            end
        end
    end

    // ==========================================
    // Test Sequence
    // ==========================================
// ==========================================
    // Test Sequence: The Directed Hazard Stress Test
    // ==========================================
// ==========================================
    // Test Sequence: The Branch Squash Test
    // ==========================================
    initial begin
        $display("==================================================");
        $display("   STARTING CONTROL HAZARD (BRANCH) TEST");
        $display("==================================================");

        // 1. Initialize Memories with Zeros
        for(int i = 0; i < 256; i++) begin
            imem[i] = 32'h00000000;
            //dmem[i] = 32'h00000000;
        end

        // 2. Load the Assembly Program into IMEM
        // --------------------------------------------------
        
        // PC=0: BEQ $1, $2, +4
        // ACTION: $1 and $2 are equal (both 100). Branch TAKEN!
        // TARGET: PC + (4 << 2) = PC + 16 = Address 16 (0x10).
        imem[0] = {BRANCH_OPCODE, 5'd1, 5'd2, 16'h0004}; 
        
        // PC=4: ADD $9, $1, $2 
        // HAZARD: This was fetched while the BEQ was decoding. 
        // EXPECTATION: MUST BE SQUASHED (Turned into NOP).
        imem[1] = {R_OPCODE, 5'd1, 5'd2, 5'd9, 5'd0, ADD}; 

        // PC=8: ADD $10, $1, $2 
        // HAZARD: This was fetched while the BEQ was executing.
        // EXPECTATION: MUST BE SQUASHED (Turned into NOP).
        imem[2] = {R_OPCODE, 5'd1, 5'd2, 5'd10, 5'd0, ADD}; 

        // PC=12: ADD $11, $1, $2 
        // EXPECTATION: Skipped entirely by the PC jump.
        imem[3] = {R_OPCODE, 5'd1, 5'd2, 5'd11, 5'd0, ADD}; 

        // PC=16 (0x10): SUB $31, $1, $2 
        // TARGET: This is where execution should safely resume!
        // RESULT: R31 = 100 - 100 = 0.
        imem[4] = {R_OPCODE, 5'd1, 5'd2, 5'd31, 5'd0, SUB}; 

        // Add NOPs to let the pipeline flush safely
        imem[5] = 32'h00000000; 
        imem[6] = 32'h00000000; 
        imem[7] = 32'h00000000; 

        // 3. Apply System Reset
        resetn = 0;
        #20;

        // 4. Backdoor load known variables into the Register File

        // 5. Release Reset
        resetn = 1;

        // 6. Monitor the Pipeline Math and Squashes
        $monitor("Time: %3t | IF_PC: %2h | EX_OPC: %2h | EX_ALU_OUT: %3d | Sqsh_ID: %b | Sqsh_EX: %b", 
                 $time, u_top.fd_pc, u_top.ex_opcode, u_top.ex_alu_result, u_top.cu_squash_decode, u_top.cu_squash_execute);

        #150;
        
        $display("==================================================");
        $display("Test Complete.");
        $finish;
    end

endmodule