module rs (
    input clk,
    input rst,
    input new_alu_result,
    input [31:0] alu_result,
    input [`ROB_WIDTH:0] alu_dependency,
    input new_mem_result,
    input [31:0] mem_result,
    input [`ROB_WIDTH:0] mem_dependency,
    input new_entry,
    input [2:0] calc_op_L1,
    input calc_op_L2,
    input [31:0] value1, value2,
    input [`ROB_WIDTH:0] query1, query2,
    input [`ROB_WIDTH:0] new_rob_id,
    output reg [2:0] rs2alu_op_L1,
    output reg rs2alu_op_L2,
    output reg [31:0] rs2alu_opr1, rs2alu_opr2,
    output reg [`ROB_WIDTH:0] rs2alu_rob_id
    output wire station_full = ((station_cnt + new_entry) == `RS_SIZE)
);

    reg [2:0] station_calc_op_L1[`RS_SIZE - 1:0];
    reg calc_op_L2[`RS_SIZE - 1:0];
    reg [31:0] station_v1[`RS_SIZE - 1:0];
    reg [31:0] station_v2[`RS_SIZE - 1:0];
    reg signed [`ROB_WIDTH:0] station_q1[`RS_SIZE - 1:0];
    reg signed [`ROB_WIDTH:0] station_q2[`RS_SIZE - 1:0];
    reg [`ROB_WIDTH:0] station_rob_id[`RS_SIZE - 1:0];
    reg station_busy[`RS_SIZE - 1:0];
    reg [`RS_WIDTH:0] station_cnt; // 多一位

    reg break_flag;

    always @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < `RS_SIZE; i++) begin
                station_busy[i] <= 0;
            end
            station_cnt <= 0;
            station_full <= 0;
        end else begin
            if (new_entry) begin
                add_entry(calc_op_L1, calc_op_L2, value1, value2, query1, query2, new_rob_id);
            end
            if (new_alu_result) begin
                update_dependency(alu_result, alu_dependency);
            end
            if (new_mem_result) begin
                update_dependency(mem_result, mem_dependency);
            end
            flag = 0;
            for (int i = 0; i < `RS_SIZE && !flag; i++) begin
                if (station_busy[i] == 1) begin
                    if (station_q1[i] == -1 && station_q2[i] == -1) begin
                        station_busy[i] <= 0;
                        rs2alu_op_L1 <= station_calc_op_L1[i];
                        rs2alu_op_L2 <= station_calc_op_L2[i];
                        rs2alu_opr1 <= station_v1[i];
                        ra2alu_opr2 <= station_v2[i];
                        rs2alu_rob_id <= station_rob_id[i];
                        // TODO 是否需要传递ready输出信号
                        flag = 1; // break
                    end
                end
            end
        end
    end

    task add_entry;
        input [2:0] calc_op_L1;
        input calc_op_L2;
        input [31:0] value1, value2;
        input [`ROB_WIDTH:0] query1, query2;
        input [`ROB_WIDTH:0] new_rob_id;
        
        for (int i = 0; i < `RS_SIZE; i++) begin
            if (station_busy[i] == 0) begin
                station_calc_op_L1[i] <= calc_op_L1;
                station_calc_op_L2[i] <= calc_op_L2;
                station_v1[i] <= value1;
                station_v2[i] <= value2;
                station_q1[i] <= query1;
                station_q2[i] <= query2;
                station_rob_id[i] <= new_rob_id;
                station_busy[i] <= 1;
                station_cnt <= station_cnt + 1;
            end
        end
    endtask

    task update_dependency;
        input [31:0] value;
        input [`ROB_WIDTH:0] dependency;

        for (int i = 0; i < `RS_SIZE; i++) begin
            if (station_busy[i] == 1) begin
                if (station_q1[i] == dependency) begin
                    station_v1[i] <= value;
                    station_q1[i] <= -1;
                end
                if (station_q2[i] == dependency) begin
                    station_v2[i] <= value;
                    station_q2[i] <= -1;
                end
            end
        end
    endtask

endmodule