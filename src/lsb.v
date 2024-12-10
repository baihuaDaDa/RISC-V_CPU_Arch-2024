`include "src/const_param.v"

module lsb (
    input clk_in,
    input rst_in,
    input rdy_in,

    input                          dec_valid,
    input [MEM_TYPE_NUM_WIDTH-1:0] dec_mem_type,
    input [                  31:0] dec_value1,
    input [                  31:0] dec_value2,
    input [   `ROB_SIZE_WIDTH-1:0] dec_dependency1,
    input [   `ROB_SIZE_WIDTH-1:0] dec_dependency2,
    input [                  31:0] dec_imm,
    input [   `ROB_SIZE_WIDTH-1:0] dec_rob_id,
    input [                  31:0] dec_age,          // TODO 位宽待定

    input                       alu_valid,
    input [`ROB_SIZE_WIDTH-1:0] alu_dependency,
    input [               31:0] alu_value,

    input                       mem_valid,
    input [`ROB_SIZE_WIDTH-1:0] mem_dependency,
    input [               31:0] mem_value,
    input                       mem_busy,

    input rob_pop_sb,

    input need_flush_in,

    output reg [LOAD_TYPE_NUM_WIDTH-1:0] lb2mem_load_type,
    output reg [                   31:0] lb2mem_addr,
    output reg [    `ROB_SIZE_WIDTH-1:0] lb2mem_dependency,
    output reg                           lb2mem_ready,

    output reg [`ROB_SIZE_WIDTH-1:0] sb2rob_dependency,
    output reg [               31:0] sb2rob_dest,
    output reg [               31:0] sb2rob_value,
    output reg                       sb2rob_ready,

    output wire lb_full,
    output wire sb_full
);

    localparam LB_SIZE = `LB_SIZE;
    localparam LB_SIZE_WIDTH = `LB_SIZE_WIDTH;
    localparam SB_SIZE = `SB_SIZE;
    localparam SB_SIZE_WIDTH = `SB_SIZE_WIDTH;
    localparam MEM_TYPE_NUM_WIDTH = `MEM_TYPE_NUM_WIDTH;
    localparam LOAD_TYPE_NUM_WIDTH = `LOAD_TYPE_NUM_WIDTH;

    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_LB = 3'b000;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_LH = 3'b001;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_LW = 3'b010;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_LBU = 3'b011;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_LHU = 3'b100;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_SB = 3'b101;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_SH = 3'b110;
    localparam [MEM_TYPE_NUM_WIDTH-1:0] MEM_SW = 3'b111;

    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_BYTE = 3'b000;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_HALF = 3'b001;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_WORD = 3'b010;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_BYTE_UNSIGNED = 3'b011;
    localparam [LOAD_TYPE_NUM_WIDTH-1:0] LOAD_HALF_UNSIGNED = 3'b100;

    reg [      LB_SIZE_WIDTH-1:0] lb_size;
    reg                           lb_busy       [LB_SIZE-1:0];
    reg [LOAD_TYPE_NUM_WIDTH-1:0] lb_load_type  [LB_SIZE-1:0];
    reg [                   31:0] lb_value1     [LB_SIZE-1:0];
    reg [                   31:0] lb_value2     [LB_SIZE-1:0];
    reg [    `ROB_SIZE_WIDTH-1:0] lb_dependency1[LB_SIZE-1:0];
    reg [    `ROB_SIZE_WIDTH-1:0] lb_dependency2[LB_SIZE-1:0];
    reg [    `ROB_SIZE_WIDTH-1:0] lb_rob_id     [LB_SIZE-1:0];
    reg [                   31:0] lb_age        [LB_SIZE-1:0];  // TODO 位宽待定

    reg [SB_SIZE_WIDTH-1:0] sb_head, sb_rear, sb_size;
    reg     [               31:0] sb_value1     [SB_SIZE-1:0];
    reg     [               31:0] sb_value2     [SB_SIZE-1:0];
    reg     [`ROB_SIZE_WIDTH-1:0] sb_dependency1[SB_SIZE-1:0];
    reg     [`ROB_SIZE_WIDTH-1:0] sb_dependency2[SB_SIZE-1:0];
    reg     [               31:0] sb_imm        [SB_SIZE-1:0];
    reg     [`ROB_SIZE_WIDTH-1:0] sb_rob_id     [SB_SIZE-1:0];
    reg     [               31:0] sb_age        [SB_SIZE-1:0];  // TODO 位宽待定

    wire    [  SB_SIZE_WIDTH-1:0] sb_front;
    wire    [  SB_SIZE_WIDTH-1:0] sb_rear_next;
    wire    [  SB_SIZE_WIDTH-1:0] sb_ptr;
    reg                           break_flag;

    integer                       i;
    integer                       index;

    assign sb_front = (sb_head + 1) & SB_SIZE;
    assign sb_rear_next = (sb_rear + 1) & SB_SIZE;
    assign sb_ptr = (index + sb_head + 1) & SB_SIZE;

    assign lb_full = (lb_size + (dec_valid && dec_mem_type <= 3'b100) == LB_SIZE);
    assign sb_full = (sb_size + (dec_valid && dec_mem_type > 3'b100) - rob_pop_sb == SB_SIZE);

    always @(posedge clk_in) begin
        if (rst_in) begin
            for (i = 0; i < LB_SIZE; i = i + 1) begin
                lb_busy[i] <= 1'b0;
            end
            lb_size <= 0;
            sb_head <= 0;
            sb_rear <= 0;
            sb_size <= 0;
            lb2mem_ready <= 0;
            sb2rob_ready <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
            lb2mem_ready <= 0;
            sb2rob_ready <= 0;
        end else begin
            if (need_flush_in) begin
                for (i = 0; i < LB_SIZE; i = i + 1) begin
                    lb_busy[i] <= 1'b0;
                end
                lb_size <= 0;
                sb_head <= 0;
                sb_rear <= 0;
                sb_size <= 0;
                lb2mem_ready <= 0;
                sb2rob_ready <= 0;
            end else begin
                if (dec_valid) begin
                    if (dec_mem_type <= 3'b100) begin
                        break_flag = 0;
                        for (i = 0; i < LB_SIZE && !break_flag; i = i + 1) begin
                            if (!lb_busy[i]) begin
                                lb_busy[i] <= 1;
                                lb_load_type[i] <= dec_mem_type;
                                lb_value1[i] <= dec_value1;
                                lb_value2[i] <= dec_value2;
                                lb_dependency1[i] <= dec_dependency1;
                                lb_dependency2[i] <= dec_dependency2;
                                lb_rob_id[i] <= dec_rob_id;
                                lb_age[i] <= dec_age;
                                lb_size <= lb_size + 1;
                                break_flag = 1;
                            end
                        end
                    end else begin
                        sb_dependency1[sb_rear_next] <= dec_dependency1;
                        sb_dependency2[sb_rear_next] <= dec_dependency2;
                        sb_value1[sb_rear_next] <= dec_value1;
                        sb_value2[sb_rear_next] <= dec_value2;
                        sb_imm[sb_rear_next] <= dec_imm;
                        sb_rob_id[sb_rear_next] <= dec_rob_id;
                        sb_age[sb_rear_next] <= dec_age;
                        sb_size <= sb_size + 1;
                        sb_rear <= sb_rear_next;
                    end
                end
                if (alu_valid) begin
                    lb_update_dependency(alu_value, alu_dependency);
                    sb_update_dependency(alu_value, alu_dependency);
                end
                if (mem_valid) begin
                    lb_update_dependency(mem_value, mem_dependency);
                    sb_update_dependency(mem_value, mem_dependency);
                end
                if (rob_pop_sb) begin
                    sb_head <= (sb_head + 1) & SB_SIZE;
                    sb_size <= sb_size - 1;
                end
                if (sb_size && sb_dependency1[sb_front] == -1 && sb_dependency2[sb_front] == -1) begin
                    sb2rob_dependency <= sb_rob_id[sb_front];
                    sb2rob_dest <= sb_value1[sb_front] + sb_imm[sb_front];
                    sb2rob_value <= sb_value2[sb_front];
                    sb2rob_ready <= 1;
                end else begin
                    sb2rob_ready <= 0;
                end
                if (!mem_busy) begin
                    break_flag = 0;
                    for (i = 0; i < LB_SIZE && !break_flag; i = i + 1) begin
                        if (lb_busy[i] && lb_dependency1[i] == -1 && (sb_size == 0 || (sb_size && lb_age[i] < sb_age[sb_front]))) begin
                            lb2mem_load_type <= lb_load_type[i];
                            lb2mem_addr <= lb_value1[i] + lb_value2[i];
                            lb2mem_dependency <= lb_rob_id[i];
                            lb2mem_ready <= 1;
                            lb_busy[i] <= 0;
                            lb_size <= lb_size - 1;
                            break_flag = 1;
                        end
                    end
                    if (!break_flag) begin
                        lb2mem_ready <= 0;
                    end
                end else begin
                    lb2mem_ready <= 0;
                end
            end
        end
    end

    task lb_update_dependency;
        input [31:0] value;
        input [`ROB_SIZE_WIDTH-1:0] dependency;

        for (i = 0; i < LB_SIZE; i = i + 1) begin
            if (lb_busy[i] && lb_dependency1[i] == dependency) begin
                lb_value1[i] <= value;
                lb_dependency1[i] <= -1;
            end
        end
    endtask

    task sb_update_dependency;
        input [31:0] value;
        input [`ROB_SIZE_WIDTH-1:0] dependency;

        for (index = 0; index < sb_size; index = index + 1) begin
            if (sb_dependency1[sb_ptr] == dependency) begin
                sb_value1[sb_ptr] <= value;
                sb_dependency1[sb_ptr] <= -1;
            end
            if (sb_dependency2[sb_ptr] == dependency) begin
                sb_value2[sb_ptr] <= value;
                sb_dependency2[sb_ptr] <= -1;
            end
        end
    endtask

endmodule
