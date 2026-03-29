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

    // Simulated Memory Arrays (Associative arrays to handle sparse addresses like 0x3000 and 0x0000)
    logic [31:0] imem [int];
    logic [31:0] dmem [int]; 

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

    // IMEM: combinational ROM (same-cycle data for i_mem_addr). i_mem_valid not from i_mem_read
    // avoids comb loop: i_mem_read -> valid -> inst_o -> decode_ready -> id_ready -> i_mem_read.
    always_comb begin
        if (!resetn) begin
            i_mem_data  = 32'h0;
            i_mem_valid = 1'b0;
        end else begin
            if (imem.exists(i_mem_addr >> 2))
                i_mem_data = imem[i_mem_addr >> 2];
            else
                i_mem_data = {NO_OPERATION, 26'b0};
            i_mem_valid = 1'b1;
        end
    end

    // DMEM: Combinational Read / Synchronous Write
    always_comb begin
        if(!resetn) begin
            d_mem_data_i = 32'h00000000;
        end else begin
            if(d_mem_read) begin
                if (dmem.exists(d_mem_addr >> 2)) begin
                    d_mem_data_i = dmem[d_mem_addr >> 2];
                end else begin
                    d_mem_data_i = 32'h00000000;
                end
            end else begin
                d_mem_data_i = 32'h00000000;
            end
        end
    end

    // Handle memory writes synchronously to prevent combinational loops in simulation
    always_ff @(posedge clk) begin
        if (resetn && d_mem_write) begin
            dmem[d_mem_addr >> 2] = d_mem_data;
            $display("[%0t] MEM WRITE: Addr=0x%h, Data=%0d", $time, d_mem_addr, d_mem_data);
        end
    end

    // ==========================================
    // Test Sequence: The Full Pipeline Test
    // ==========================================
// ==========================================
    // Test Sequence: The Full Pipeline Test
    // ==========================================
// ==========================================
    // Test Sequence: The Full Pipeline Test
    // ==========================================
    initial begin
        // Declarations MUST be at the top of the block!
        int base_addr      = 32'h3000 >> 2; // 3072
        int exception_addr = 32'h0000 >> 2; // 0

        $display("==================================================");
        $display("   STARTING RISC-V FULL PIPELINE & EXCEPTION TEST");
        $display("==================================================");

        // =========================================================
        // MAIN PROGRAM MEMORY (Starts at 0x3000)
        // Assuming r1=100, r2=50 (Initialized in decode.sv)
        // =========================================================
        
        // 1. ADD r3, r1, r2  --> r3 = 100 + 50 = 150
        // CURRENT PC: 0x3000 (Index: 3072)
        imem[base_addr + 0] = {R_OPCODE, 5'd1, 5'd2, 5'd3, 5'd0, ADD}; 
        
        // 2. STORE r3, 0(r0) --> DMEM[0] = 150
        // CURRENT PC: 0x3004 (Index: 3073)
        imem[base_addr + 1] = {STORE_OPCODE, 5'd0, 5'd3, 16'h0000}; 

        // 3. LOAD r4, 0(r0)  --> r4 = DMEM[0] = 150
        // CURRENT PC: 0x3008 (Index: 3074)
        imem[base_addr + 2] = {LOAD_OPCODE, 5'd0, 5'd4, 16'h0000}; 

        // ---------------------------------------------------------
        // 4. BEQ r1, r1, imm=4  (target = PC + imm*4 = 0x300C + 16 = 0x301C)
        // CURRENT PC: 0x300C (Index: 3075)
        // ---------------------------------------------------------
        imem[base_addr + 3] = {BRANCH_OPCODE, 5'd1, 5'd1, 16'sd4}; 

        // =========================================================
        // --- SQUASH ZONE (The "Not Taken" Path) ---
        // The Fetch unit will grab these by default, but the 
        // Execute stage must squash them because the branch IS taken.
        // =========================================================
        
        // 5. ADD r5, r1, r2 --> MUST BE SQUASHED (r5 should remain 0)
        // CURRENT PC: 0x3010 (Index: 3076)
        imem[base_addr + 4] = {R_OPCODE, 5'd1, 5'd2, 5'd5, 5'd0, ADD}; 

        // 6. LOAD r6, 0(r0) --> MUST BE SQUASHED (r6 should remain 0)
        // CURRENT PC: 0x3014 (Index: 3077)
        imem[base_addr + 5] = {LOAD_OPCODE, 5'd0, 5'd6, 16'h0000}; 

        // 7. SUB r7, r1, r2 --> MUST BE SQUASHED (r7 should remain 0)
        // CURRENT PC: 0x3018 (Index: 3078)
        imem[base_addr + 6] = {R_OPCODE, 5'd1, 5'd2, 5'd7, 5'd0, SUB}; 

        // =========================================================
        // --- BRANCH LANDING ZONE ---
        // =========================================================
        
        // 8. XOR r8, r1, r2 --> r8 = 100 ^ 50
        // CURRENT PC: 0x301C (Index: 3079) - Branch successfully lands here!
        imem[base_addr + 7] = {R_OPCODE, 5'd1, 5'd2, 5'd8, 5'd0, XOR}; 

        // 9. OR r9, r1, r2 --> r9 = 100 | 50
        // CURRENT PC: 0x3020 (Index: 3080)
        imem[base_addr + 8] = {R_OPCODE, 5'd1, 5'd2, 5'd9, 5'd0, OR}; 

        // ---------------------------------------------------------
        // 10. JAL -> Absolute Jump 
        // CURRENT PC: 0x3024 (Index: 3081)
        // EXECUTE MATH: {PC[31:28], target, 2'b00} --> {0x0, 0x000C0D, 00} = 0x003034
        // DESTINATION: PC 0x3034 (Index: 3085 / base_addr + 13)
        // ---------------------------------------------------------
        imem[base_addr + 9] = {JAL_OPCODE, 26'h0000C0D}; 

        // 11-13. NOPs --> Should be squashed by the JAL!
        // CURRENT PC: 0x3028, 0x302C, 0x3030
        imem[base_addr + 10] = {NO_OPERATION, 26'b0}; 
        imem[base_addr + 11] = {NO_OPERATION, 26'b0}; 
        imem[base_addr + 12] = {NO_OPERATION, 26'b0}; 

        // ---------------------------------------------------------
        // 14. INVALID INSTRUCTION
        // CURRENT PC: 0x3034 (Index: 3085) - We landed the JAL here!
        // EXECUTE MATH: Trigger exception, Control Unit overrides PC to 0x0000
        // DESTINATION: PC 0x0000 (Index: 0)
        // ---------------------------------------------------------
        imem[base_addr + 13] = {6'b111111, 26'b0}; 

        // =========================================================
        // EXCEPTION HANDLER MEMORY (Starts at 0x0000)
        // =========================================================
        
        // 0. SUB r10, r1, r2 --> r10 = 100 - 50 = 50. Confirms we landed here!
        // CURRENT PC: 0x0000 (Index: 0)
        imem[exception_addr + 0] = {R_OPCODE, 5'd1, 5'd2, 5'd10, 5'd0, SUB}; 


        // =========================================================
        // Execute Sequence
        // =========================================================
        resetn = 0;
        #25;
        resetn = 1;

        // Monitor the Pipeline Math, Exceptions, and Squashes
        $monitor("Time: %3t | PC: %h | Inst: %h | EX_ALU: %3d | SqshID: %b | Excep: %b", 
                 $time, u_top.fd_pc, u_top.fd_inst, $signed(u_top.ex_alu_result), 
                 u_top.cu_squash_decode, u_top.cu_exception_fetch);

        // Extended delay to allow all pipeline flushes and memory operations to finish
        #800; 
        
        $display("==================================================");
        $display("Test Complete.");
        $finish;
    end

endmodule