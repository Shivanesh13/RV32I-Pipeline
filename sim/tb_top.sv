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

    task automatic load_imem_from_memfile(
        input string memfile,
        output int unsigned last_idx
    );
        int fd;
        int rc;
        int loaded;
        int unsigned idx;
        logic [31:0] word;
        // Ensure memfile-driven runs use only externally supplied instructions.
        imem.delete();
        loaded = 0;
        last_idx = 0;
        fd = $fopen(memfile, "r");
        if (fd == 0) begin
            $fatal(1, "Failed to open opcode memory file: %s", memfile);
        end
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h\n", idx, word);
            if (rc == 2) begin
                imem[idx] = word;
                loaded++;
                if (loaded == 1 || idx > last_idx) begin
                    last_idx = idx;
                end
            end
        end
        $fclose(fd);
        if (loaded == 0) begin
            $fatal(1, "Opcode memory file is empty: %s", memfile);
        end
        $display("[TB] Loaded %0d instructions from %s", loaded, memfile);
        $display("[TB] Highest IMEM index loaded: %0d", last_idx);
    endtask

    task automatic load_dmem_from_memfile(input string memfile);
        int fd;
        int rc;
        int loaded;
        int unsigned idx;
        logic [31:0] word;
        dmem.delete();
        loaded = 0;
        fd = $fopen(memfile, "r");
        if (fd == 0) begin
            $fatal(1, "Failed to open data memory file: %s", memfile);
        end
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h\n", idx, word);
            if (rc == 2) begin
                dmem[idx] = word;
                loaded++;
            end
        end
        $fclose(fd);
        $display("[TB] Loaded %0d data words from %s", loaded, memfile);
    endtask

    task automatic run_until_last_fetch(
        input int unsigned last_idx,
        input int unsigned tail_cycles,
        input int unsigned max_cycles
    );
        int cycles;
        bit seen_last;
        seen_last = 0;

        for (cycles = 0; cycles < max_cycles; cycles++) begin
            @(posedge clk);
            if (resetn && i_mem_read && ((i_mem_addr >> 2) == last_idx)) begin
                seen_last = 1;
                $display("[TB] Last instruction fetched at cycle %0d (IMEM idx=%0d, PC=0x%h)",
                         cycles, last_idx, i_mem_addr);
                break;
            end
        end

        if (!seen_last) begin
            $fatal(1, "[TB] Timed out waiting for last instruction fetch (idx=%0d)", last_idx);
        end

        repeat (tail_cycles) @(posedge clk);
    endtask

    task automatic dump_all_gprs();
        int r;
        $display("==================================================");
        $display(" Final Register Dump (r0-r31)");
        $display("==================================================");
        for (r = 0; r < 32; r++) begin
            $display("r%0d = 0x%08h (%0d)", r, u_top.u_decode.MEM_DATA[r], $signed(u_top.u_decode.MEM_DATA[r]));
        end
    endtask

    // ==========================================
    // Test Sequence
    // ==========================================
    initial begin
        int unsigned base_addr;
        int unsigned exception_addr;
        int unsigned program_end_idx;
        string opcodes_mem;
        string dmem_mem;

        base_addr      = FETCH_START_ADDR >> 2;
        exception_addr = EXCEPTION_ADDR >> 2;

        if ($value$plusargs("OPCODES_MEM=%s", opcodes_mem)) begin
            $display("==================================================");
            $display("   STARTING JSON-PROGRAM SIMULATION");
            $display("==================================================");
            load_imem_from_memfile(opcodes_mem, program_end_idx);
            if ($value$plusargs("DMEM_MEM=%s", dmem_mem)) begin
                load_dmem_from_memfile(dmem_mem);
            end else begin
                dmem.delete();
                $display("[TB] No DMEM_MEM provided. Data memory defaults to zeros.");
            end
            resetn = 0;
            #25;
            resetn = 1;
            $monitor("Time: %3t | PC: %h | Inst: %h | EX_ALU: %3d | SqshID: %b | Excep: %b",
                     $time, u_top.fd_pc, u_top.fd_inst, $signed(u_top.ex_alu_result),
                     u_top.cu_squash_decode, u_top.cu_exception_fetch);
            run_until_last_fetch(program_end_idx, 10, 5000);
            dump_all_gprs();
            $display("==================================================");
            $display("JSON program simulation complete.");
            $finish;
        end else begin

        $display("==================================================");
        $display("   STARTING DEFAULT ADVANCED-LIKE PIPELINE TEST");
        $display("==================================================");

        // =========================================================
        // MAIN PROGRAM MEMORY (Starts at 0x3000)
        // Assuming r1=100, r2=50 (Initialized in decode.sv)
        // =========================================================
        
        // 1. ADD r3, r1, r2  --> 150
        imem[base_addr + 0] = {R_OPCODE, 5'd1, 5'd2, 5'd3, 5'd0, ADD}; 
        
        // 2. STORE r3, 0(r0) --> DMEM[0] = 150
        imem[base_addr + 1] = {STORE_OPCODE, 5'd0, 5'd3, 16'h0000}; 

        // 3. LOAD r4, 0(r0)  --> 150
        imem[base_addr + 2] = {LOAD_OPCODE, 5'd0, 5'd4, 16'h0000}; 

        // 4. MUL r5, r4, r3 --> 150*150 = 22500
        imem[base_addr + 3] = {R_OPCODE, 5'd4, 5'd3, 5'd5, 5'd0, MUL};

        // 5. LOAD-use hazard check: ADD r6, r4, r1 --> 250
        imem[base_addr + 4] = {R_OPCODE, 5'd4, 5'd1, 5'd6, 5'd0, ADD};

        // 6. BEQ r1, r2, +3 (not taken): fall-through must execute
        imem[base_addr + 5] = {BRANCH_OPCODE, 5'd1, 5'd2, 16'sd3};

        // 7. SUB r12, r1, r2 --> 50 (must execute)
        imem[base_addr + 6] = {R_OPCODE, 5'd1, 5'd2, 5'd12, 5'd0, SUB};

        // 8. BEQ r1, r1, +3 (taken): next 2 instructions should be squashed
        imem[base_addr + 7] = {BRANCH_OPCODE, 5'd1, 5'd1, 16'sd3};

        // 9-10. Wrong-path instructions (expected squash)
        imem[base_addr + 8]  = {R_OPCODE, 5'd1, 5'd2, 5'd13, 5'd0, ADD};
        imem[base_addr + 9]  = {LOAD_OPCODE, 5'd0, 5'd14, 16'h0000};

        // 11. Branch landing instruction
        imem[base_addr + 10] = {R_OPCODE, 5'd1, 5'd2, 5'd16, 5'd0, XOR};

        // 12. JAL to a later slot, skip two NOPs
        // target byte addr = 0x3040 -> target field = 26'h000C10
        imem[base_addr + 11] = {JAL_OPCODE, 26'h000C10};
        imem[base_addr + 12] = {NO_OPERATION, 26'b0};
        imem[base_addr + 13] = {NO_OPERATION, 26'b0};

        // 13. At 0x3040: invalid opcode to force exception to EXCEPTION_ADDR
        imem[base_addr + 16] = {6'b111111, 26'b0};

        // =========================================================
        // EXCEPTION HANDLER MEMORY (Starts at EXCEPTION_ADDR)
        // =========================================================
        imem[exception_addr + 0] = {R_OPCODE, 5'd1, 5'd2, 5'd17, 5'd0, SUB};
        imem[exception_addr + 1] = {NO_OPERATION, 26'b0};

        // Last expected fetch in default test is exception handler NOP.
        program_end_idx = exception_addr + 1;


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

        run_until_last_fetch(program_end_idx, 10, 5000);
        dump_all_gprs();
        
        $display("==================================================");
        $display("Test Complete.");
        $finish;
        end
    end

endmodule