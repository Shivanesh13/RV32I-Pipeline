package defines;
    parameter ID_WIDTH = 32;
    parameter INST_WIDTH = 32;
    parameter PC_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 5;
    parameter FUNCT_WIDTH = 6;
    parameter OPCODE_WIDTH = 6;
    parameter REG_WIDTH = 5;
    parameter IMM_WIDTH = 16;
    parameter JUMP_TARGET_WIDTH = 26;    
    parameter EXCEPTION_ADDR = 32'h0000C000;
    parameter FETCH_START_ADDR = 32'h00003000;

    parameter [5:0] R_OPCODE = 6'b000000;
    parameter [5:0] LOAD_OPCODE = 6'b10_0011; // Load
    parameter [5:0] STORE_OPCODE = 6'b10_1011; // Store
    parameter [5:0] BRANCH_OPCODE = 6'b00_0100; // Branch
    parameter [5:0] JAL_OPCODE = 6'b00_0010; // Jump 
    parameter [5:0] NO_OPERATION = 6'b00_0001; // No operation

    typedef enum logic [FUNCT_WIDTH-1:0]  {
        ADD = 6'b00_0001,   
        SUB = 6'b00_0010,
        MUL = 6'b00_0100,
        DIV = 6'b00_0101,
        AND = 6'b00_0110,
        OR = 6'b00_0111,
        XOR = 6'b00_1000,
        SLL = 6'b00_1001,
        SRL = 6'b001010
    } r_opcode_t;

endpackage