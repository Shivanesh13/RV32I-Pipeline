`timescale 1ns/1ps
`include "defines.svh"
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
    initial begin
        $display("==================================================");
        $display("   STARTING DIRECTED STRESS TEST");
        $display("==================================================");

        // 1. Initialize Memories with Zeros
        for(int i = 0; i < 256; i++) begin
            imem[i] = 32'h00000000;
            //dmem[i] = 32'h00000000;
        end

        // --------------------------------------------------
        // DETERMINISTIC PAYLOADS
        // --------------------------------------------------
         // Hardcoded data at Address 0x14 (Word 5)
        
        // 2. Load the Assembly Program into IMEM
        // --------------------------------------------------
        
        // PC=0: LOAD $23, 0($2)  
        // Action: Load data from RAM (100) into Register 23.
        imem[0] = {LOAD_OPCODE, 5'd2, 5'd23, 16'h0000}; 
        
        // PC=4: ADD $19, $23, $7  
        // HAZARD: Load-Use on $23. R19 = 100 + 50 = 150.
        imem[1] = {R_OPCODE, 5'd23, 5'd7, 5'd19, 5'd0, ADD}; 

        // PC=8: SUB $5, $19, $23 
        // DOUBLE HAZARD: EX-to-EX on $19, MEM-to-EX on $23. R5 = 150 - 100 = 50.
        imem[2] = {R_OPCODE, 5'd19, 5'd23, 5'd5, 5'd0, SUB}; 

        // PC=12: ADD $31, $5, $19 
        // DOUBLE HAZARD: EX-to-EX on $5, MEM-to-EX on $19. R31 = 50 + 150 = 200.
        imem[3] = {R_OPCODE, 5'd5, 5'd19, 5'd31, 5'd0, ADD}; 

        // Add NOPs to let the pipeline flush safely
        imem[4] = 32'h00000000; 
        imem[5] = 32'h00000000; 
        imem[6] = 32'h00000000; 
        imem[7] = 32'h00000000; 

        // 3. Apply System Reset
        resetn = 0;
        #20;
        // 5. Release Reset
        resetn = 1;

        // 6. Monitor the Pipeline Math
        $monitor("Time: %3t | PC: %2h | EX_OPC: %2h | ID_RS1: %3d | ID_RS2: %3d || EX_ALU_OUT: %3d", 
                 $time, u_top.de_pc_o, u_top.ex_opcode, u_top.de_rs1, u_top.de_rs2, u_top.ex_alu_result);

        #150;
        
        $display("==================================================");
        $display("Test Complete.");
        $finish;
    end

endmodule