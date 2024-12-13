`include "src/const_param.v"

module rs (

    input clk_in,
    input rst_in,
    input rdy_in,

    input need_flush_in,

    input                     alu_valid,
    input [             31:0] alu_value,
    input [`ROB_SIZE_WIDTH:0] alu_dependency,

    input                     mem_valid,
    input [             31:0] mem_value,
    input [`ROB_SIZE_WIDTH:0] mem_dependency,

    input [                     3:0] dec_valid,
    input [CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_in,
    input                            calc_op_L2_in,
    input [                    31:0] value1_in,
    input [                    31:0] value2_in,
    input [       `ROB_SIZE_WIDTH:0] query1_in,
    input [       `ROB_SIZE_WIDTH:0] query2_in,
    input [     `ROB_SIZE_WIDTH-1:0] new_rob_id_in,

    output reg [CALC_OP_L1_NUM_WIDTH-1:0] rs2alu_op_L1,
    output reg                            rs2alu_op_L2,
    output reg [                    31:0] rs2alu_opr1,
    output reg [                    31:0] rs2alu_opr2,
    output reg [       `ROB_SIZE_WIDTH:0] rs2alu_dependency,
    output reg                            rs2alu_ready,

    // combinatorial logic
    output wire station_full_out
);

    localparam RS_SIZE_WIDTH = `RS_SIZE_WIDTH;
    localparam RS_SIZE = `RS_SIZE;
    localparam CALC_OP_L1_NUM_WIDTH = `CALC_OP_L1_NUM_WIDTH;

    reg        [CALC_OP_L1_NUM_WIDTH-1:0] station_calc_op_L1          [RS_SIZE-1:0];
    reg                                   station_calc_op_L2          [RS_SIZE-1:0];
    reg        [                    31:0] station_v1                  [RS_SIZE-1:0];
    reg        [                    31:0] station_v2                  [RS_SIZE-1:0];
    reg signed [       `ROB_SIZE_WIDTH:0] station_q1                  [RS_SIZE-1:0];
    reg signed [       `ROB_SIZE_WIDTH:0] station_q2                  [RS_SIZE-1:0];
    reg        [     `ROB_SIZE_WIDTH-1:0] station_rob_id              [RS_SIZE-1:0];
    reg                                   station_busy                [RS_SIZE-1:0];
    reg        [         RS_SIZE_WIDTH:0] station_size;  // 多一位

    assign station_full_out = (station_size + dec_valid[1]) == RS_SIZE;

    reg     break_flag;
    integer i;

    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            for (i = 0; i < RS_SIZE; i = i + 1) begin
                station_busy[i] <= 0;
            end
            station_size <= 0;
            rs2alu_ready <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (need_flush_in) begin
                for (i = 0; i < RS_SIZE; i = i + 1) begin
                    station_busy[i] <= 0;
                end
                station_size <= 0;
                rs2alu_ready <= 0;
            end else begin
                if (dec_valid[1]) begin
                    break_flag = 0;
                    for (i = 0; i < RS_SIZE && !break_flag; i = i + 1) begin
                        if (station_busy[i] == 0) begin
                            station_calc_op_L1[i] <= calc_op_L1_in;
                            station_calc_op_L2[i] <= calc_op_L2_in;
                            if (alu_valid && query1_in == alu_dependency) begin
                                station_q1[i] <= -1;
                                station_v1[i] <= alu_value;
                            end else if (mem_valid && query1_in == mem_dependency) begin
                                station_q1[i] <= -1;
                                station_v1[i] <= mem_value;
                            end else begin
                                station_q1[i] <= query1_in;
                                station_v1[i] <= value1_in;
                            end
                            if (alu_valid && query2_in == alu_dependency) begin
                                station_q2[i] <= -1;
                                station_v2[i] <= alu_value;
                            end else if (mem_valid && query2_in == mem_dependency) begin
                                station_q2[i] <= -1;
                                station_v2[i] <= mem_value;
                            end else begin
                                station_q2[i] <= query2_in;
                                station_v2[i] <= value2_in;
                            end
                            station_rob_id[i] <= new_rob_id_in;
                            station_busy[i]   <= 1;
                            break_flag = 1;
                        end
                    end
                end
                if (alu_valid) begin
                    for (i = 0; i < RS_SIZE; i = i + 1) begin
                        if (station_busy[i] == 1) begin
                            if (station_q1[i] == alu_dependency) begin
                                station_v1[i] <= alu_value;
                                station_q1[i] <= -1;
                            end
                            if (station_q2[i] == alu_dependency) begin
                                station_v2[i] <= alu_value;
                                station_q2[i] <= -1;
                            end
                        end
                    end
                end
                if (mem_valid) begin
                    for (i = 0; i < RS_SIZE; i = i + 1) begin
                        if (station_busy[i] == 1) begin
                            if (station_q1[i] == mem_dependency) begin
                                station_v1[i] <= mem_value;
                                station_q1[i] <= -1;
                            end
                            if (station_q2[i] == mem_dependency) begin
                                station_v2[i] <= mem_value;
                                station_q2[i] <= -1;
                            end
                        end
                    end
                end
                break_flag = 0;
                for (i = 0; i < RS_SIZE && !break_flag; i = i + 1) begin
                    if (station_busy[i] == 1) begin
                        if ((&station_q1[i]) && (&station_q2[i])) begin
                            station_busy[i] <= 0;
                            rs2alu_op_L1 <= station_calc_op_L1[i];
                            rs2alu_op_L2 <= station_calc_op_L2[i];
                            rs2alu_opr1 <= station_v1[i];
                            rs2alu_opr2 <= station_v2[i];
                            rs2alu_dependency <= {1'b0, station_rob_id[i]};
                            break_flag = 1;  // break
                        end
                    end
                end
                rs2alu_ready <= break_flag;
                station_size <= station_size + dec_valid[1] - break_flag;
            end
        end
    end

endmodule
