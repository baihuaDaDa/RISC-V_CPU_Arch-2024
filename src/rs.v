module rs (
    input clk_in,
    input rst_in,
    input rdy_in,
    input alu_valid,
    input [31:0] alu_value,
    input [`ROB_WIDTH-1:0] alu_dependency,
    input mem_valid,
    input [31:0] mem_value,
    input [`ROB_WIDTH-1:0] mem_dependency,
    input dec_valid,
    input [2:0] calc_op_L1_in,
    input calc_op_L2_in,
    input [31:0] value1_in, value2_in,
    input [`ROB_WIDTH-1:0] query1_in, query2_in,
    input [`ROB_WIDTH-1:0] new_rob_id_in,
    output reg [2:0] rs2alu_op_L1,
    output reg rs2alu_op_L2,
    output reg [31:0] rs2alu_opr1, rs2alu_opr2,
    output reg [`ROB_WIDTH-1:0] rs2alu_rob_id
    output reg ready,
    output wire station_full = ((station_cnt + dec_valid) == `RS_SIZE)
);

    reg [2:0] station_calc_op_L1[`RS_SIZE-1:0];
    reg calc_op_L2[`RS_SIZE-1:0];
    reg [31:0] station_v1[`RS_SIZE-1:0];
    reg [31:0] station_v2[`RS_SIZE-1:0];
    reg signed [`ROB_WIDTH-1:0] station_q1[`RS_SIZE-1:0];
    reg signed [`ROB_WIDTH-1:0] station_q2[`RS_SIZE-1:0];
    reg [`ROB_WIDTH-1:0] station_rob_id[`RS_SIZE-1:0];
    reg station_busy[`RS_SIZE-1:0];
    reg [`RS_WIDTH:0] station_cnt; // 多一位

    reg break_flag;

    always @(posedge clk_in) begin
        if (rst_in) begin
            for (int i = 0; i < `RS_SIZE; i++) begin
                station_busy[i] <= 0;
            end
            station_cnt <= 0;
            station_full <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (dec_valid) begin
                add_entry(calc_op_L1_in, calc_op_L2_in, value1_in, value2_in, query1_in, query2_in, new_rob_id_in);
            end
            if (alu_valid) begin
                update_dependency(alu_value, alu_dependency);
            end
            if (mem_valid) begin
                update_dependency(mem_value, mem_dependency);
            end
            break_flag = 0;
            for (int i = 0; i < `RS_SIZE && !flag; i++) begin
                if (station_busy[i] == 1) begin
                    if (station_q1[i] == -1 && station_q2[i] == -1) begin
                        station_busy[i] <= 0;
                        rs2alu_op_L1 <= station_calc_op_L1[i];
                        rs2alu_op_L2 <= station_calc_op_L2[i];
                        rs2alu_opr1 <= station_v1[i];
                        ra2alu_opr2 <= station_v2[i];
                        rs2alu_rob_id <= station_rob_id[i];
                        break_flag = 1; // break
                    end
                end
            end
            ready <= break_flag;
        end
    end

    task add_entry;
        input [2:0] calc_op_L1;
        input calc_op_L2;
        input [31:0] value1, value2;
        input [`ROB_WIDTH-1:0] query1, query2;
        input [`ROB_WIDTH-1:0] new_rob_id;
        
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
        input [`ROB_WIDTH-1:0] dependency;

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