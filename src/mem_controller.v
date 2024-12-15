`include "src/const_param.v"

module mem_controller (
    input clk_in,
    input rst_in,
    input rdy_in,

    input need_flush_in,

    // port with ram, combinatorial logic
    input             io_buffer_full,  // 1 if uart buffer is full
    input      [ 7:0] byte_dout,
    output reg [ 7:0] byte_din,
    output reg [31:0] byte_a,
    output reg        byte_wr,         // write/read signal (1 for write)

    input        ic_valid,
    input [31:0] ic_aout,

    input                            rob_valid,
    input [                    31:0] rob_din,
    input [                    31:0] rob_ain,
    input [STORE_TYPE_NUM_WIDTH-1:0] rob_store_type,

    input                           lsb_valid,
    input [                   31:0] lsb_aout,
    input [    `ROB_SIZE_WIDTH-1:0] lsb_dependency,
    input [LOAD_TYPE_NUM_WIDTH-1:0] lsb_load_type,

    output reg                        dout_ready,
    output reg                        iout_ready,
    // 由于从 ram 读取数据只能在下一周期接收结果，所以用 wire 类型直接连接
    output wire [               31:0] out,
    output reg  [`ROB_SIZE_WIDTH-1:0] dependency_out,

    output wire busy_out
);

    localparam LOAD_TYPE_NUM_WIDTH = `LOAD_TYPE_NUM_WIDTH;
    localparam STORE_TYPE_NUM_WIDTH = `STORE_TYPE_NUM_WIDTH;

    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_BYTE = 3'b000;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_HALF = 3'b001;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_WORD = 3'b010;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_BYTE_UNSIGNED = 3'b100;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_HALF_UNSIGNED = 3'b101;

    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_BYTE = 2'b00;
    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_HALF = 2'b01;
    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_WORD = 2'b10;

    /* TODO: RoB 和 LSB 可能同时发出读/写请求，需要解决冲突。
             如果优化 RoB 阻塞 Store 的问题可以直接解决这个问题。*/
    // TODO: busy_out 可优化

    reg  [               31:0] tmp_result;
    reg                        working;
    reg  [                1:0] work_cycle;
    reg  [                1:0] work_time;
    // tmp input
    reg  [               31:0] tmp_din;
    reg  [               31:0] tmp_ain;
    reg  [`ROB_SIZE_WIDTH-1:0] tmp_lsb_dependency;
    reg                        tmp_wr;
    reg                        tmp_is_unsigned;  // 1 for unsigned, 0 for signed
    reg                        tmp_is_instr;

    wire                       wire_working;
    wire [                1:0] wire_work_time;
    wire [               31:0] wire_ain;
    wire                       cur_working;
    wire                       cur_work_time;
    wire [               31:0] cur_din;
    wire [               31:0] cur_ain;
    wire                       cur_wr;

    // 2'b00 -> byte; 2'b01 -> half; 2'b10 -> word
    assign wire_working = rob_valid || lsb_valid || ic_valid;
    assign wire_work_time = rob_valid ? rob_store_type : lsb_valid ? lsb_load_type[1:0] : 2'b10;
    assign wire_ain = rob_valid ? rob_ain : lsb_valid ? lsb_aout : ic_valid ? ic_aout : 0;
    // init 阶段的 tmp 状态还没更新，需要直接从 input 中获取状态和数据
    assign cur_working = work_cycle == 2'b00 ? wire_working : working;
    assign cur_work_time = work_cycle == 2'b00 ? wire_work_time : work_time;
    assign cur_din = work_cycle == 2'b00 ? rob_din : tmp_din;
    assign cur_ain = work_cycle == 2'b00 ? wire_ain : tmp_ain;
    assign cur_wr = work_cycle == 2'b00 ? rob_valid : tmp_wr;
    assign out = work_time == 2'b00 ? (tmp_is_unsigned ? {{24{byte_dout[7]}}, byte_dout} : byte_dout) :
                 work_time == 2'b01 ? (tmp_is_unsigned && !tmp_is_instr ? {{16{byte_dout[7]}}, byte_dout, tmp_result[7:0]} : {{16{1'b0}}, byte_dout, tmp_result[7:0]}) :
                 {byte_dout, tmp_result[23:0]};
    assign busy_out = cur_working;

    always @(posedge clk_in) begin
        if (rst_in) begin
            dout_ready <= 0;
            iout_ready <= 0;
            work_cycle <= 2'b00;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (need_flush_in) begin
                work_cycle <= 2'b00;
                dout_ready <= 0;
                iout_ready <= 0;
            end else begin
                if (!cur_working) begin
                    dout_ready <= 0;
                    iout_ready <= 0;
                end else begin
                    // init
                    if (work_cycle == 2'b00) begin
                        dout_ready <= 0;
                        iout_ready <= 0;
                        working <= wire_working;
                        work_time <= wire_work_time;
                        tmp_result <= 0;
                        tmp_din <= rob_din;
                        tmp_ain <= wire_ain;
                        tmp_lsb_dependency <= lsb_dependency;
                        tmp_wr <= rob_valid;
                        tmp_is_unsigned <= lsb_load_type[2];
                        tmp_is_instr <= ic_valid;
                    end
                    case (work_cycle)
                        2'b00: begin
                            byte_a   <= cur_ain;
                            byte_din <= cur_din[7:0];
                            byte_wr  <= cur_wr;
                            if (cur_work_time) begin
                                work_cycle <= 2'b01;
                            end else begin
                                work_cycle <= 2'b00;
                                working <= 0;
                                dout_ready <= cur_wr;
                                dependency_out <= tmp_lsb_dependency;
                            end
                        end
                        2'b01: begin
                            tmp_result[7:0] <= byte_dout;
                            byte_a <= cur_ain + 1;
                            byte_din <= cur_din[15:8];
                            byte_wr <= cur_wr;
                            if (cur_work_time <= 2'b01 || (tmp_is_instr && byte_dout[1:0] != 2'b11)) begin
                                if (tmp_is_instr) begin
                                    work_time  <= 2'b01;
                                    iout_ready <= 1;
                                end else begin
                                    dout_ready <= cur_wr;
                                    dependency_out <= tmp_lsb_dependency;
                                end
                                work_cycle <= 2'b00;
                                working <= 0;
                            end else begin
                                work_cycle <= 2'b10;
                            end
                        end
                        2'b10: begin
                            tmp_result[15:8] <= byte_dout;
                            work_cycle <= 2'b11;
                            byte_a <= cur_ain + 2;
                            byte_din <= cur_din[23:16];
                            byte_wr <= cur_wr;
                        end
                        2'b11: begin
                            tmp_result[23:16] <= byte_dout;
                            work_cycle <= 2'b00;
                            byte_a <= cur_ain + 3;
                            byte_din <= cur_din[31:24];
                            byte_wr <= cur_wr;
                            working <= 0;
                            if (tmp_is_instr) begin
                                iout_ready <= 1;
                            end else begin
                                dout_ready <= cur_wr;
                                dependency_out <= tmp_lsb_dependency;
                            end
                        end
                    endcase
                end
            end
        end
    end

endmodule
