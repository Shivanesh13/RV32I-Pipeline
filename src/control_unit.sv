module control_unit(
    input logic branch_taken_i,
    input logic [31:0] branch_target_i,
    input logic jal_taken_i,
    input logic [31:0] jal_target_i,
    input invalid_inst_i,
    output logic br_fetch_o,
    output logic jal_fetch_o,
    output logic exception_fetch_o,
    output logic squash_decode_o,
    output logic squash_execute_o,
    output logic squash_memory_o,
    output logic squash_writeback_o
);


always_comb begin
    br_fetch_o = 1'b0;
    jal_fetch_o = 1'b0;
    exception_fetch_o = 1'b0;
    squash_decode_o = 1'b0;
    squash_execute_o = 1'b0;
    squash_memory_o = 1'b0;
    squash_writeback_o = 1'b0;

    if(branch_taken_i) begin
        br_fetch_o = 1'b1;
        squash_decode_o = 1'b1;
        squash_execute_o = 1'b1;
    end
    if(jal_taken_i) begin
        jal_fetch_o = 1'b1;
        squash_decode_o = 1'b1;
        squash_execute_o = 1'b1;
    end

    if(invalid_inst_i) begin
        exception_fetch_o = 1'b1;
        squash_decode_o = 1'b1;
        squash_execute_o = 1'b1;
    end
end




endmodule