`include "defines.svh"
import defines::*;

module memory(
    input logic clk,
    input logic resetn,

    // Inputs from Execute Stage
    input logic [DATA_WIDTH-1:0]   alu_result_i,  
    input logic [DATA_WIDTH-1:0]   mem_data_i,    
    input logic [DATA_WIDTH-1:0]   mem_addr_i,    // Your new dedicated address port
    input logic [OPCODE_WIDTH-1:0] opcode_i,      
    input logic [REG_WIDTH-1:0]    rd_i,          
    input logic                    reg_write_i,   
    input logic                    mem_read_i,    
    input logic                    mem_write_i,   
    input logic                    execute_valid_i,

    // Pipeline Control & Handshaking
    output logic mem_ready_o,      
    input  logic wb_ready_i,       
    input  logic stall_i,
    output logic mem_valid_o,      

    // External Data Memory Interface
    output logic [DATA_WIDTH-1:0]  dmem_addr_o,
    output logic [DATA_WIDTH-1:0]  dmem_data_o,
    output logic                   dmem_read_o,
    output logic                   dmem_write_o,
    input  logic [DATA_WIDTH-1:0]  dmem_data_i,   
    input  logic                   dmem_ready_i,  

    // Outputs to Write-Back Stage
    output logic [DATA_WIDTH-1:0]  wb_mem_data_o,   
    output logic [OPCODE_WIDTH-1:0] wb_opcode_o,    
    output logic [REG_WIDTH-1:0]   wb_rd_o,         
    output logic                   wb_reg_write_o  ,

    output logic [REG_WIDTH-1:0]           reg_loopback_o,
    output logic [DATA_WIDTH-1:0]           data_loopback_o
);

    // ==========================================
    // COMBINATIONAL ROUTING
    // ==========================================
    assign dmem_addr_o  = mem_addr_i;    // Using your new port
    assign dmem_data_o  = mem_data_i;
    assign dmem_read_o  = mem_read_i;
    assign dmem_write_o = mem_write_i;

    assign reg_loopback_o = rd_i;
    assign data_loopback_o = (opcode_i == LOAD_OPCODE) ? dmem_data_i : alu_result_i;

assign mem_ready_o = wb_ready_i && !stall_i;
    // ==========================================
    // SYNCHRONOUS PIPELINE REGISTERS
    // ==========================================
    // FIXED: Added negedge resetn
    always_ff @(posedge clk or negedge resetn) begin
        if(!resetn) begin
            wb_mem_data_o  <= 32'h00000000;
            wb_opcode_o    <= 0;
            wb_rd_o        <= 5'h0;
            wb_reg_write_o <= 1'b0;
            mem_valid_o    <= 1'b0;
        end else begin
            
            if(execute_valid_i && !stall_i) begin
                // FIXED: Trusting the control signals!
                wb_opcode_o    <= opcode_i;
                wb_rd_o        <= rd_i;
                wb_reg_write_o <= reg_write_i;
                mem_valid_o    <= 1'b1;

                // Data Mux: If LOAD, grab RAM data. Otherwise, pass ALU math.
                if(mem_read_i) begin
                    wb_mem_data_o <= dmem_data_i;
                end else begin
                    wb_mem_data_o <= alu_result_i;
                end

            end else if (!stall_i) begin
                // Pipeline Bubble
                mem_valid_o    <= 1'b0;
                wb_mem_data_o  <= 32'h00000000;
                wb_opcode_o    <= 0;
                wb_rd_o        <= 5'h0;
                wb_reg_write_o <= 1'b0;
            end
        end
    end

endmodule