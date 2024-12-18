`include "src/const_param.v"

module rf (
    input clk_in,
    input rst_in,
    input rdy_in,

    input need_flush_in,

    input                     rob_valid,
    input [REG_NUM_WIDTH-1:0] rob_rd,
    input [             31:0] rob_value,
    input [`ROB_SIZE_WIDTH:0] rob_dependency,

    input [              3:0] dec_valid,
    input [REG_NUM_WIDTH-1:0] dec_rd,
    input [REG_NUM_WIDTH-1:0] dec_rs1,
    input [REG_NUM_WIDTH-1:0] dec_rs2,

    // combinatorial logic
    input [`ROB_SIZE_WIDTH:0] rob_new_dependency,
    input [REG_NUM_WIDTH-1:0] if_rs_jalr,

    output wire [             31:0] value1_out,
    output wire [             31:0] value2_out,
    output wire [`ROB_SIZE_WIDTH:0] dependency1_out,
    output wire [`ROB_SIZE_WIDTH:0] dependency2_out,
    output wire [             31:0] value_jalr_out
);

    localparam REG_NUM_WIDTH = `REG_NUM_WIDTH;
    localparam REG_NUM = `REG_NUM;

    reg     [             31:0]                           regs          [REG_NUM-1:0];
    reg     [`ROB_SIZE_WIDTH:0]                           reg_dependency[REG_NUM-1:0];
    integer                                               i;

    /* debug */
    wire    [             31:0] ra = regs[1];
    wire    [`ROB_SIZE_WIDTH:0] ra_d = reg_dependency[1];

    assign value1_out = (dec_rs1 == 0) ? 0 : (rob_valid && rob_rd == dec_rs1) ? rob_value : regs[dec_rs1];
    assign value2_out = (dec_rs2 == 0) ? 0 : (rob_valid && rob_rd == dec_rs2) ? rob_value : regs[dec_rs2];
    assign dependency1_out = (dec_rs1 == 0 || (rob_valid && rob_rd == dec_rs1 && rob_dependency == reg_dependency[dec_rs1])) ? -1 : reg_dependency[dec_rs1];
    assign dependency2_out = (dec_rs2 == 0 || (rob_valid && rob_rd == dec_rs2 && rob_dependency == reg_dependency[dec_rs2])) ? -1 : reg_dependency[dec_rs2];
    assign value_jalr_out = regs[if_rs_jalr];

    // assign value1_out = 0;
    // assign value2_out = 0;
    // assign dependency1_out = -1;
    // assign dependency2_out = -1;

    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            for (i = 0; i < REG_NUM; i = i + 1) begin
                reg_dependency[i] <= -1;
                regs[i] <= 0;
            end
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (need_flush_in) begin
                for (i = 0; i < REG_NUM; i = i + 1) begin
                    reg_dependency[i] <= -1;
                end
            end else begin
                if (rob_valid && rob_rd) begin
                    regs[rob_rd] <= rob_value;
                    if (reg_dependency[rob_rd] == rob_dependency) begin
                        reg_dependency[rob_rd] <= -1;
                    end
                end
                if (dec_valid[3] && dec_rd) begin
                    reg_dependency[dec_rd] <= rob_new_dependency;
                end
            end
        end
    end

endmodule
