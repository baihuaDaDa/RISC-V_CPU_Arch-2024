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

    /* debug
    wire    [             31:0] ra = regs[1];
    wire    [`ROB_SIZE_WIDTH:0] ra_d = reg_dependency[1];
    wire    [             31:0] sp = regs[2];
    wire    [`ROB_SIZE_WIDTH:0] sp_d = reg_dependency[2];
    wire    [             31:0] gp = regs[3];
    wire    [`ROB_SIZE_WIDTH:0] gp_d = reg_dependency[3];
    wire    [             31:0] tp = regs[4];
    wire    [`ROB_SIZE_WIDTH:0] tp_d = reg_dependency[4];
    wire    [             31:0] t0 = regs[5];
    wire    [`ROB_SIZE_WIDTH:0] t0_d = reg_dependency[5];
    wire    [             31:0] t1 = regs[6];
    wire    [`ROB_SIZE_WIDTH:0] t1_d = reg_dependency[6];
    wire    [             31:0] t2 = regs[7];
    wire    [`ROB_SIZE_WIDTH:0] t2_d = reg_dependency[7];
    wire    [             31:0] s0 = regs[8];
    wire    [`ROB_SIZE_WIDTH:0] s0_d = reg_dependency[8];
    wire    [             31:0] s1 = regs[9];
    wire    [`ROB_SIZE_WIDTH:0] s1_d = reg_dependency[9];
    wire    [             31:0] a0 = regs[10];
    wire    [`ROB_SIZE_WIDTH:0] a0_d = reg_dependency[10];
    wire    [             31:0] a1 = regs[11];
    wire    [`ROB_SIZE_WIDTH:0] a1_d = reg_dependency[11];
    wire    [             31:0] a2 = regs[12];
    wire    [`ROB_SIZE_WIDTH:0] a2_d = reg_dependency[12];
    wire    [             31:0] a3 = regs[13];
    wire    [`ROB_SIZE_WIDTH:0] a3_d = reg_dependency[13];
    wire    [             31:0] a4 = regs[14];
    wire    [`ROB_SIZE_WIDTH:0] a4_d = reg_dependency[14];
    wire    [             31:0] a5 = regs[15];
    wire    [`ROB_SIZE_WIDTH:0] a5_d = reg_dependency[15];
    wire    [             31:0] a6 = regs[16];
    wire    [`ROB_SIZE_WIDTH:0] a6_d = reg_dependency[16];
    wire    [             31:0] a7 = regs[17];
    wire    [`ROB_SIZE_WIDTH:0] a7_d = reg_dependency[17];
    wire    [             31:0] s2 = regs[18];
    wire    [`ROB_SIZE_WIDTH:0] s2_d = reg_dependency[18];
    wire    [             31:0] s3 = regs[19];
    wire    [`ROB_SIZE_WIDTH:0] s3_d = reg_dependency[19];
    wire    [             31:0] s4 = regs[20];
    wire    [`ROB_SIZE_WIDTH:0] s4_d = reg_dependency[20];
    wire    [             31:0] s5 = regs[21];
    wire    [`ROB_SIZE_WIDTH:0] s5_d = reg_dependency[21];
    wire    [             31:0] s6 = regs[22];
    wire    [`ROB_SIZE_WIDTH:0] s6_d = reg_dependency[22];
    wire    [             31:0] s7 = regs[23];
    wire    [`ROB_SIZE_WIDTH:0] s7_d = reg_dependency[23];
    wire    [             31:0] s8 = regs[24];
    wire    [`ROB_SIZE_WIDTH:0] s8_d = reg_dependency[24];
    wire    [             31:0] s9 = regs[25];
    wire    [`ROB_SIZE_WIDTH:0] s9_d = reg_dependency[25];
    wire    [             31:0] s10 = regs[26];
    wire    [`ROB_SIZE_WIDTH:0] s10_d = reg_dependency[26];
    wire    [             31:0] s11 = regs[27];
    wire    [`ROB_SIZE_WIDTH:0] s11_d = reg_dependency[27];
    wire    [             31:0] t3 = regs[28];
    wire    [`ROB_SIZE_WIDTH:0] t3_d = reg_dependency[28];
    wire    [             31:0] t4 = regs[29];
    wire    [`ROB_SIZE_WIDTH:0] t4_d = reg_dependency[29];
    wire    [             31:0] t5 = regs[30];
    wire    [`ROB_SIZE_WIDTH:0] t5_d = reg_dependency[30];
    wire    [             31:0] t6 = regs[31];
    wire    [`ROB_SIZE_WIDTH:0] t6_d = reg_dependency[31];
    */


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
