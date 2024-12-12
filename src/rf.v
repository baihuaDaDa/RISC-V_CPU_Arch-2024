`include "src/const_param.v"

module rf (
    input clk_in,
    input rst_in,
    input rdy_in,

    input need_flush_in,

    input                       rob_valid,
    input [  REG_NUM_WIDTH-1:0] rob_rd,
    input [               31:0] rob_value,
    input [`ROB_SIZE_WIDTH-1:0] rob_dependency,

    input                       dec_valid,
    input [  REG_NUM_WIDTH-1:0] dec_rd,
    input [`ROB_SIZE_WIDTH-1:0] dec_dependency,

    // combinatorial logic
    input [REG_NUM_WIDTH-1:0] dec_rs1,
    input [REG_NUM_WIDTH-1:0] dec_rs2,

    output wire [31:0] value1_out,
    output wire [31:0] value2_out,
    output wire [`ROB_SIZE_WIDTH-1:0] dependency1_out,
    output wire [`ROB_SIZE_WIDTH-1:0] dependency2_out
);

    localparam REG_NUM_WIDTH = `REG_NUM_WIDTH;
    localparam REG_NUM = `REG_NUM;

    reg     [               31:0] regs         [REG_NUM-1:0];
    reg     [`ROB_SIZE_WIDTH-1:0] reg_dependency[REG_NUM-1:0];
    integer                       i;

    assign value1_out = (rob_valid && rob_rd == dec_rs1) ? rob_value : regs[dec_rs1];
    assign value2_out = (rob_valid && rob_rd == dec_rs2) ? rob_value : regs[dec_rs2];
    assign dependency1_out = (dec_valid && dec_rd == dec_rs1) ? dec_dependency :
                         (rob_valid && rob_rd == dec_rs1 && rob_dependency == reg_dependency[dec_rs1]) ? -1 :
                         reg_dependency[dec_rs1];
    assign dependency2_out = (dec_valid && dec_rd == dec_rs2) ? dec_dependency :
                         (rob_valid && rob_rd == dec_rs2 && rob_dependency == reg_dependency[dec_rs1]) ? -1 :
                         reg_dependency[dec_rs2];

    always @(posedge clk_in) begin
        if (rst_in) begin
            flush();
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (need_flush_in) begin
                flush();
            end else begin
                if (rob_valid && rob_rd) begin
                    regs[rob_rd] <= rob_value;
                    if (reg_dependency[rob_rd] == rob_dependency) begin
                        reg_dependency[rob_rd] <= -1;
                    end
                end
                if (dec_valid && dec_rd) begin
                    regs[dec_rd] <= regs[dec_dependency];
                end
            end
        end
    end

    task flush;
    begin
        regs[0] <= 0;
        for (i = 0; i < REG_NUM; i++) begin
            reg_dependency[i] <= -1;
        end
    end
    endtask

endmodule
