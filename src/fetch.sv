
module fetch(
    input  logic        clk,
    input  logic        resetn,
    
    // Instruction Memory Interface
    output logic [31:0] i_mem_addr,
    input  logic [31:0] i_mem_data,
    input  logic        i_mem_valid,
    output logic        i_mem_read,
    input  logic        i_mem_ready,
    
    // Pipeline Control
    input  logic        stall_i,
    input  logic        id_ready_i,       // Added: Signal from Decode stage
    
    // Outputs to Decode Stage
    output logic [31:0] pc_o,
    output logic [31:0] inst_o,
    output logic        inst_valid_o,
    
    // Control Flow 
    input  logic        exception_i,
    input  logic        branch_i,         // Added: Branch taken signal
    input  logic [31:0] branch_addr_i,     // Added: Branch target address
    input  logic        jal_i,
    input  logic [31:0] jal_addr_i
);

    logic [31:0] pc_reg, pc_next, pc_reg_d;
    logic        instruction_read; 
    logic [31:0] pc_prev;

    // Continuous assignments for memory interface
    assign i_mem_addr = pc_reg;
    assign i_mem_read = instruction_read;

    parameter EXCEPTION_ADDR = 32'h00000000;

    // dont think about branch and exception for now 

    always_comb begin
        pc_next = pc_reg;
        instruction_read = 1'b0;
        if(exception_i) begin
            pc_next = EXCEPTION_ADDR;
            instruction_read = 1'b1;
        end
        else if(branch_i) begin
            pc_next = branch_addr_i;
            instruction_read = 1'b1;
        end
        else if(jal_i) begin
            pc_next = jal_addr_i;
            instruction_read = 1'b1;
        end
        else if(id_ready_i && i_mem_ready && !stall_i) begin
            pc_next = pc_reg + 4;
            instruction_read = 1'b1;
        end
    end 


    always_ff @(posedge clk, negedge resetn) begin
        if(!resetn) begin
            pc_reg <= 'b0;
            pc_prev <= 'b0;
        end else begin
            if(i_mem_ready && id_ready_i && !stall_i) begin
                pc_reg <= pc_next;
                pc_prev <= pc_reg;
            end
            else 
                pc_reg <= pc_prev; 
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if(!resetn) begin
            pc_o         <= 32'h0;
            inst_o       <= 32'h0;
            inst_valid_o <= 1'b0;
        end 
        else if (!stall_i && id_ready_i) begin // If stalled, do NOTHING. Just hold old values.
            if (i_mem_valid) begin
                pc_o         <= pc_reg;
                inst_o       <= i_mem_data;
                inst_valid_o <= 1'b1;
            end else begin
                inst_valid_o <= 1'b0;
            end
        end
    end


endmodule