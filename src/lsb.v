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
    output reg [31:0] lb2mem_addr,
    output reg [`ROB_SIZE_WIDTH-1:0] lb2mem_dependency,
    output reg lb2mem_ready,

    output reg [`ROB_SIZE_WIDTH-1:0] sb2rob_dependency,
    output reg [31:0] sb2rob_dest,
    output reg [31:0] sb2rob_value,
    output reg sb2rob_ready,

    output wire lb_full,
    output wire sb_full
);

    localparam LB_SIZE = 16;
    localparam LB_SIZE_WIDTH = 4;
    localparam SB_SIZE = 16;
    localparam SB_SIZE_WIDTH = 4;
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

    reg                           lb_busy       [LB_SIZE-1:0];
    reg [LOAD_TYPE_NUM_WIDTH-1:0] lb_load_type  [LB_SIZE-1:0];
    reg [                   31:0] lb_value1     [LB_SIZE-1:0];
    reg [                   31:0] lb_value2     [LB_SIZE-1:0];
    reg [    `ROB_SIZE_WIDTH-1:0] lb_dependency1[LB_SIZE-1:0];
    reg [    `ROB_SIZE_WIDTH-1:0] lb_dependency2[LB_SIZE-1:0];
    reg [    `ROB_SIZE_WIDTH-1:0] lb_rob_id     [LB_SIZE-1:0];
    reg [                   31:0] lb_age        [LB_SIZE-1:0];  // TODO 位宽待定

    reg [SB_SIZE_WIDTH-1:0] sb_head, sb_rear, sb_size;
    reg [               31:0] sb_value1     [SB_SIZE-1:0];
    reg [               31:0] sb_value2     [SB_SIZE-1:0];
    reg [`ROB_SIZE_WIDTH-1:0] sb_dependency1[SB_SIZE-1:0];
    reg [`ROB_SIZE_WIDTH-1:0] sb_dependency2[SB_SIZE-1:0];
    reg [               31:0] sb_imm        [SB_SIZE-1:0];
    reg [`ROB_SIZE_WIDTH-1:0] sb_rob_id     [SB_SIZE-1:0];
    reg [               31:0] sb_age        [SB_SIZE-1:0];  // TODO 位宽待定

    integer i;

    always @(posedge clk_in) begin
        if (rst_in) begin
            for (i = 0; i < LB_SIZE; i = i + 1) begin
                lb_busy[i] <= 1'b0;
            end
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
                sb_head <= 0;
                sb_rear <= 0;
                sb_size <= 0;
                lb2mem_ready <= 0;
                sb2rob_ready <= 0;
            end else begin

            end
        end
    end

    task lb_update_dependency;
        input [31:0] value;
        input [`ROB_SIZE_WIDTH-1:0] dependency;
        
        for (i = 0; i < LB_SIZE; i = i + 1) begin
            if (lb_busy[i])
        end
    endtask

    task sb_update_dependency;
    endtask

endmodule
