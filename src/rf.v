`include "src/const_param.v"

module rf (
    input clk_in,
    input rst_in,
    input rdy_in,

    input is_flush_in,

    input                       rob_valid,
    input [  REG_NUM_WIDTH-1:0] rob_rd,
    input [               31:0] rob_value,
    input [`ROB_SIZE_WIDTH-1:0] rob_dependency,

    input                       dec_valid,
    input [  REG_NUM_WIDTH-1:0] dec_rd,
    input [`ROB_SIZE_WIDTH-1:0] dec_dependency
);

    localparam REG_NUM_WIDTH = `REG_NUM_WIDTH;
    localparam REG_NUM = `REG_NUM;

    reg [               31:0] regs         [REG_NUM-1:0];
    reg [`ROB_SIZE_WIDTH-1:0] regDependency[REG_NUM-1:0];
    integer i;

    always @(posedge clk_in) begin
        if (rst_in) begin
            flush();
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (is_flush_in) begin
                flush();
            end else begin
                if (rob_valid && rob_rd) begin
                    regs[rob_rd] <= rob_value;
                    if (regDependency[rob_rd] == rob_dependency) begin
                        regDependency[rob_rd] <= -1;
                    end
                end
                if (dec_valid && dec_rd) begin
                    regs[dec_rd] <= regs[dec_dependency];
                end
            end
        end
    end

    task flush;
        for (i = 0; i < REG_NUM; i++) begin
            regDependency[i] <= -1;
        end
    endtask

endmodule
