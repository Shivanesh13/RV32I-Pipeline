`timescale 1ns/1ps
`include "../src/defines.svh"
import defines::*;

// =============================================================================
// Advanced system testbench for the pipelined core in ../src/top.sv
//
// ISA layout (matches decode.sv):
//   R-type:  [31:26]=R_OPCODE | [25:21]=rs | [20:16]=rt | [15:11]=rd |
//            [10:6]=0        | [5:0]=funct
//   LOAD:    [31:26]=LOAD    | [25:21]=base (rs) | [20:16]=dest (rt) | imm[15:0]
//   STORE:   [31:26]=STORE   | [25:21]=base      | [20:16]=src (rt)  | imm[15:0]
//   BRANCH:  [31:26]=BRANCH  | [25:21]=rs | [20:16]=rt | imm[15:0]  (BEQ if rs==rt)
//            branch_target = PC_branch + (sign_ext(imm) << 2)
//   JAL:     [31:26]=JAL     | [25:0]=26-bit word index field (see execute.sv concat)
//
// Reset assumptions (decode.sv register file):
//   r0 = 0, r1 = 100, r2 = 50; other GPRs 0 after reset.
//
// Exception vector (fetch.sv / defines.svh):
//   Invalid opcode -> PC = EXCEPTION_ADDR (32'h0000C000), IMEM word index = (EXCEPTION_ADDR >> 2).
//   NOTE: This is NOT address 0x0000; older TBs that only loaded imem[0] miss the handler.
// =============================================================================

module tb_advanced;

    logic clk;
    logic resetn;

    logic [31:0] i_mem_addr;
    logic [31:0] i_mem_data;
    logic        i_mem_valid;
    logic        i_mem_read;
    logic        i_mem_ready;

    logic [31:0] d_mem_addr;
    logic [31:0] d_mem_data;
    logic        d_mem_read;
    logic        d_mem_write;
    logic [31:0] d_mem_data_i;
    logic        d_mem_ready_i;

    logic [31:0] imem [int];
    logic [31:0] dmem [int];

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

    // -------------------------------------------------------------------------
    // Instruction builders (single place for encoding = easier audits)
    // -------------------------------------------------------------------------
    function automatic logic [31:0] insn_r_type(
        logic [4:0] rs,
        logic [4:0] rt,
        logic [4:0] rd,
        logic [5:0] funct
    );
        return {R_OPCODE, rs, rt, rd, 5'b0, funct};
    endfunction

    function automatic logic [31:0] insn_load(
        logic [4:0] base_rs,
        logic [4:0] dest_rt,
        logic [15:0] imm
    );
        return {LOAD_OPCODE, base_rs, dest_rt, imm};
    endfunction

    function automatic logic [31:0] insn_store(
        logic [4:0] base_rs,
        logic [4:0] src_rt,
        logic [15:0] imm
    );
        return {STORE_OPCODE, base_rs, src_rt, imm};
    endfunction

    // BEQ (execute.sv): branch_target = PC_branch + (sign_ext(imm) << 2)
    // imm_words = (pc_target - pc_branch) / 4  (signed)
    function automatic shortint branch_imm_words(
        logic [31:0] pc_branch,
        logic [31:0] pc_target
    );
        int d;
        d = int'(pc_target) - int'(pc_branch);
        if ((d & 3) != 0)
            $fatal(1, "branch_imm_words: (target-PC) must be multiple of 4 (got delta=%0d)", d);
        if (d > 32767 || d < -32768)
            $fatal(1, "branch_imm_words: offset out of 16-bit range");
        return shortint'(d / 4);
    endfunction

    function automatic logic [31:0] insn_beq(
        logic [4:0] rs,
        logic [4:0] rt,
        shortint imm_words
    );
        return {BRANCH_OPCODE, rs, rt, imm_words};
    endfunction

    // jal_target = { current_PC[31:28], target26, 2'b00 }; target26 = (byte_addr >> 2)
    function automatic logic [31:0] insn_jal_from_pc(
        logic [31:0] pc_at_execute,
        logic [31:0] byte_addr_dest
    );
        logic [25:0] t26;
        if (pc_at_execute[31:28] != byte_addr_dest[31:28]) begin
            $fatal(1, "JAL cross 256MB region not supported by ALU concat in execute.sv");
        end
        t26 = byte_addr_dest[27:2];
        return {JAL_OPCODE, t26};
    endfunction

    // -------------------------------------------------------------------------
    // Clock / memory models (DMEM same as tb_top)
    // IMEM: combinational ROM — data reflects i_mem_addr same cycle (matches fetch).
    // Do not drive i_mem_valid from i_mem_read (that created a comb loop through decode_ready).
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    assign i_mem_ready   = 1'b1;
    assign d_mem_ready_i = 1'b1;

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

    always_comb begin
        if (!resetn)
            d_mem_data_i = 32'h0;
        else if (d_mem_read) begin
            if (dmem.exists(d_mem_addr >> 2))
                d_mem_data_i = dmem[d_mem_addr >> 2];
            else
                d_mem_data_i = 32'h0;
        end else
            d_mem_data_i = 32'h0;
    end

    // Blocking write matches tb_top.sv (store visible to comb read after posedge in same time step)
    always_ff @(posedge clk) begin
        if (resetn && d_mem_write)
            dmem[d_mem_addr >> 2] = d_mem_data;
    end

    // -------------------------------------------------------------------------
    // GPR checks (hierarchical: register file lives inside decode)
    // -------------------------------------------------------------------------
    function automatic logic [31:0] gpr(input logic [4:0] r);
        return u_top.u_decode.MEM_DATA[r];
    endfunction

    task automatic check_gpr(input string name, input logic [4:0] r, input logic [31:0] expected);
        logic [31:0] v = gpr(r);
        if (v !== expected) begin
            $error("[%0t] CHECK FAIL: %s  r%0d = %0d (0x%h), expected %0d (0x%h)",
                   $time, name, r, v, v, expected, expected);
        end else
            $display("[%0t] CHECK OK:   %s  r%0d = %0d", $time, name, r, v);
    endtask

    // -------------------------------------------------------------------------
    // Program load: MAIN @ FETCH_START_ADDR, exception handler @ EXCEPTION_ADDR
    // -------------------------------------------------------------------------
    initial begin
        int unsigned main_base;      // word index for PC = FETCH_START_ADDR (32'h3000)
        int unsigned exc_base;       // word index for PC = EXCEPTION_ADDR   (32'hC000)
        int unsigned i;
        int unsigned pc_main;
        int unsigned pc_exc;

        main_base = FETCH_START_ADDR >> 2;  // 0xC00 = 3072
        exc_base  = EXCEPTION_ADDR   >> 2;  // 0x3000 = 12288  (NOT imem[0])

        pc_main = FETCH_START_ADDR;
        pc_exc  = EXCEPTION_ADDR;

        $display("=================================================================");
        $display(" ADVANCED TB: main IMEM base word=%0d (PC=0x%h), exc base word=%0d (PC=0x%h)",
                 main_base, pc_main, exc_base, pc_exc);
        $display("=================================================================");

        // ─────────────────────────────────────────────────────────────────
        // SECTION 1 — Baseline ALU + DMEM (r1=100, r2=50)
        // ─────────────────────────────────────────────────────────────────
        i = 0;
        // PC 0x3000: ADD r3,r1,r2 -> 150
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd3, ADD);
        i++;

        // PC 0x3004: STORE r3, 0(r0) -> DMEM[0]=150
        imem[main_base + i] = insn_store(5'd0, 5'd3, 16'h0000);
        i++;

        // PC 0x3008: LOAD r4, 0(r0) -> r4=150
        imem[main_base + i] = insn_load(5'd0, 5'd4, 16'h0000);
        i++;

        // PC 0x300C: MUL r5,r4,r3 -> 150*150 = 22500 (tests large ALU result)
        imem[main_base + i] = insn_r_type(5'd4, 5'd3, 5'd5, MUL);
        i++;

        // PC 0x3010: ADD r6,r4,r1 — uses r4 immediately after LOAD (load-use hazard stress)
        // EXPECT: decode_ready may bubble; final r6 = 150+100 = 250
        imem[main_base + i] = insn_r_type(5'd4, 5'd1, 5'd6, ADD);
        i++;

        // PC 0x3014: AND r7,r1,r2 -> 100&50 = 32
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd7, AND);
        i++;

        // PC 0x3018: OR r8,r7,r1 -> 32|100 = 100
        imem[main_base + i] = insn_r_type(5'd7, 5'd1, 5'd8, OR);
        i++;

        // PC 0x301C: XOR r9,r8,r2 -> 100^50 = 86
        imem[main_base + i] = insn_r_type(5'd8, 5'd2, 5'd9, XOR);
        i++;

        // ─────────────────────────────────────────────────────────────────
        // SECTION 2 — EX-stage forwarding: back-to-back dependent ADDs
        // ─────────────────────────────────────────────────────────────────
        // PC 0x3020: ADD r10,r1,r2 -> 150
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd10, ADD);
        i++;

        // PC 0x3024: ADD r11,r10,r1 -> 150+100 = 250 (r10 from previous EX/WB path)
        imem[main_base + i] = insn_r_type(5'd10, 5'd1, 5'd11, ADD);
        i++;

        // ─────────────────────────────────────────────────────────────────
        // SECTION 3 — Branch NOT taken (rs != rt), fall-through must run
        // ─────────────────────────────────────────────────────────────────
        // PC 0x3028: BEQ r1,r2 (not taken); if taken: 0x3028 + 3*4 = 0x3034 (imm=3)
        imem[main_base + i] = insn_beq(5'd1, 5'd2, branch_imm_words(32'h3028, 32'h3034));
        i++;

        // PC 0x302C: SUB r12,r1,r2 -> 50 (MUST execute)
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd12, SUB);
        i++;

        // ─────────────────────────────────────────────────────────────────
        // SECTION 4 — Taken BEQ + squash (target = PC + imm*4)
        // ─────────────────────────────────────────────────────────────────
        // PC 0x3030: BEQ r1,r1 -> land 0x3040  => imm = (0x3040-0x3030)/4 = 4
        imem[main_base + i] = insn_beq(5'd1, 5'd1, branch_imm_words(32'h3030, 32'h3040));
        i++;

        // PC 0x3034, 0x3038, 0x303C — fall-through (squashed when branch taken)
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd13, ADD);
        i++;
        imem[main_base + i] = insn_load(5'd0, 5'd14, 16'h0);
        i++;
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd15, SUB);
        i++;

        // PC 0x3040 — landing: XOR r16,r1,r2 -> 86
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd16, XOR);
        i++;

        // ─────────────────────────────────────────────────────────────────
        // SECTION 5 — Second forward BEQ + squash, then ALU chain (compact offset)
        // ─────────────────────────────────────────────────────────────────
        // PC 0x3044: ADD r18,r1,r0 -> 100
        imem[main_base + i] = insn_r_type(5'd1, 5'd0, 5'd18, ADD);
        i++;
        // PC 0x3048: BEQ r18,r18, imm=3 -> 0x3048+12=0x3054 (MUL). Only 0x304C and 0x3050 are
        // wrong-path (squashed when taken); 0x3054 is the target and must execute — not squashed.
        imem[main_base + i] = insn_beq(5'd18, 5'd18, branch_imm_words(32'h3048, 32'h3054));
        i++;
        // Wrong-path fall-through only (between branch PC and target)
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd22, ADD);
        i++;
        imem[main_base + i] = insn_load(5'd0, 5'd23, 16'h0);
        i++;
        // PC 0x3054 — branch target: MUL r19; then SUB r20
        imem[main_base + i] = insn_r_type(5'd2, 5'd2, 5'd19, MUL);
        i++;
        imem[main_base + i] = insn_r_type(5'd19, 5'd1, 5'd20, SUB);
        i++;

        // ─────────────────────────────────────────────────────────────────
        // SECTION 6 — Backward offset, branch NOT taken (tests negative imm encoding)
        // PC 0x305C: BEQ r1,r2 -> target 0x3044 if equal; imm = (0x3044-0x305C)/4 = -6
        // PC 0x3060: AND r24,r1,r2 -> 32 (must execute)
        // ─────────────────────────────────────────────────────────────────
        imem[main_base + i] = insn_beq(5'd1, 5'd2, branch_imm_words(32'h305C, 32'h3044));
        i++;
        imem[main_base + i] = insn_r_type(5'd1, 5'd2, 5'd24, AND);
        i++;

        // ─────────────────────────────────────────────────────────────────
        // SECTION 7 — JAL + illegal -> exception @ EXCEPTION_ADDR
        // PC 0x3064: JAL to 0x30C0
        // ─────────────────────────────────────────────────────────────────
        imem[main_base + i] = insn_jal_from_pc(32'h3064, 32'h30C0);
        i++;
        imem[main_base + i] = {NO_OPERATION, 26'b0};
        i++;
        imem[main_base + i] = {NO_OPERATION, 26'b0};
        i++;
        imem[32'h30C0 >> 2] = {6'b111111, 26'b0};

        // ─────────────────────────────────────────────────────────────────
        // SECTION 8 — Exception handler @ EXCEPTION_ADDR (0xC000)
        // ─────────────────────────────────────────────────────────────────
        // PC 0xC000: SUB r17,r1,r2 -> 50 (proves redirect)
        imem[exc_base + 0] = insn_r_type(5'd1, 5'd2, 5'd17, SUB);

        // PC 0xC004: NOP / halt padding
        imem[exc_base + 1] = {NO_OPERATION, 26'b0};

        // -----------------------------------------------------------------
        // Run
        // -----------------------------------------------------------------
        resetn = 0;
        #25;
        resetn = 1;

        $display("--- simulation running (allow deep pipeline + memory) ---");
        #(3500);

        $display("--- post-run GPR checks (golden values) ---");
        check_gpr("ADD r3",        5'd3,  32'd150);
        check_gpr("LOAD r4",       5'd4,  32'd150);
        check_gpr("MUL r5",        5'd5,  32'd22500);
        check_gpr("LOAD-use ADD r6", 5'd6, 32'd250);
        check_gpr("AND r7",        5'd7,  32'd32);
        check_gpr("OR r8",         5'd8,  32'd100);
        check_gpr("XOR r9",        5'd9,  32'd86);
        check_gpr("FWD ADD r10",   5'd10, 32'd150);
        check_gpr("FWD ADD r11",   5'd11, 32'd250);
        check_gpr("BNE fall SUB r12", 5'd12, 32'd50);
        check_gpr("squash r13",    5'd13, 32'd0);
        check_gpr("squash r14",    5'd14, 32'd0);
        check_gpr("squash r15",    5'd15, 32'd0);
        check_gpr("branch land XOR r16", 5'd16, 32'd86);
        check_gpr("2nd BEQ ADD r18", 5'd18, 32'd100);
        check_gpr("2nd BEQ MUL r19", 5'd19, 32'd2500);
        check_gpr("2nd BEQ SUB r20", 5'd20, 32'd2400);
        check_gpr("squash r22",    5'd22, 32'd0);
        check_gpr("squash r23",    5'd23, 32'd0);
        check_gpr("neg-imm AND r24", 5'd24, 32'd32);
        check_gpr("exception SUB r17", 5'd17, 32'd50);

        $display("=================================================================");
        $display(" Advanced TB finished.");
        $finish;
    end

endmodule
