`include "src/const_param.v"

module rob (

    input clk_in,
    input rst_in,
    input rdy_in,

    // TODO 地址的位宽是 32 还是 17 ？
    input                           dec_valid,
    input [ ROB_TYPE_NUM_WIDTH-1:0] dec_rob_type,
    input [     `REG_NUM_WIDTH-1:0] dec_dest,
    input [                   31:0] dec_value,
    input [                   31:0] dec_instr_addr,
    input [                   31:0] dec_jump_addr,
    input [ROB_STATE_NUM_WIDTH-1:0] dec_rob_state,
    input                           dec_is_jump,

    input                      alu_valid,
    input [ROB_SIZE_WIDTH-1:0] alu_dependency,
    input [              31:0] alu_value,

    input                      mem_valid,
    input [ROB_SIZE_WIDTH-1:0] mem_dependency,
    input [              31:0] mem_value,
    input                      mem_busy,

    input                      lsb_valid,
    input [ROB_SIZE_WIDTH-1:0] lsb_dependency,
    input [`REG_NUM_WIDTH-1:0] lsb_dest,
    input [              31:0] lsb_value,

    output reg [`REG_NUM_WIDTH-1:0] rob2rf_rd,
    output reg [              31:0] rob2rf_value,
    output reg [ROB_SIZE_WIDTH-1:0] rob2rf_rob_id,
    output reg                      rob2rf_ready,

    output reg [ 2:0] rob2mem_store_type,
    output reg [31:0] rob2mem_addr,
    output reg [31:0] rob2mem_value,
    output reg        rob2mem_ready,

    output reg rob2lsb_pop_sb,

    output reg [31:0] rob2if_jump_addr,

    output reg [31:0] rob2pred_instr_addr,
    output reg        rob2pred_is_jump,
    output reg        rob2pred_ready,

    output reg need_flush_out,

    // combinatorial logic
    input wire [`ROB_SIZE_WIDTH-1:0] dec_dependency1,
    input wire [`ROB_SIZE_WIDTH-1:0] dec_dependency2,

    output wire is_found_1_out,
    output wire [31:0] value1_out,
    output wire is_found_2_out,
    output wire [31:0] value2_out,
    output wire buffer_full_out,
    output wire next_rob_id_out
);

    localparam ROB_SIZE_WIDTH = `ROB_SIZE_WIDTH;
    localparam ROB_SIZE = `ROB_SIZE;
    localparam ROB_TYPE_NUM_WIDTH = `ROB_TYPE_NUM_WIDTH;
    localparam ROB_STATE_NUM_WIDTH = `ROB_STATE_NUM_WIDTH;
    localparam STORE_TYPE_NUM_WIDTH = `STORE_TYPE_NUM_WIDTH;

    localparam [ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_COMMIT = 2'b00;
    localparam [ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_EXECUTE = 2'b01;
    localparam [ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_WRITE_RESULT = 2'b10;

    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_BYTE = 3'b000;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_HALF = 3'b001;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_WORD = 3'b010;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_REG = 3'b011;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_JALR = 3'b100;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_BRANCH = 3'b101;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_EXIT = 3'b110;

    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_BYTE = 2'b00;
    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_HALF = 2'b01;
    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_WORD = 2'b10;

    // LoopQueue<RoBEntry, kBufferCapBin> buffer;
    reg [ROB_SIZE_WIDTH-1:0] buffer_head, buffer_rear, buffer_size;
    reg [ ROB_TYPE_NUM_WIDTH-1:0] buffer_rob_type  [ROB_SIZE:0];  // ROB_SIZE = 31
    reg [     `REG_NUM_WIDTH-1:0] buffer_dest      [ROB_SIZE:0];
    reg [                   31:0] buffer_value     [ROB_SIZE:0];
    reg [                   31:0] buffer_instr_addr[ROB_SIZE:0];
    reg [                   31:0] buffer_jump_addr [ROB_SIZE:0];
    reg [ROB_STATE_NUM_WIDTH-1:0] buffer_rob_state [ROB_SIZE:0];
    reg                           buffer_is_jump   [ROB_SIZE:0];

    wire [     ROB_SIZE_WIDTH-1:0] rear_next;
    wire [     ROB_SIZE_WIDTH-1:0] front;

    assign rear_next = (buffer_rear + 1) & ROB_SIZE;
    assign front = (buffer_head + 1) & ROB_SIZE;

    assign value1_out = (dec_valid && rear_next == dec_dependency1) ? dec_value :
                    (alu_valid && alu_dependency == dec_dependency1) ? alu_value :
                    (mem_valid && mem_dependency == dec_dependency1) ? mem_value :
                    (lsb_valid && lsb_dependency == dec_dependency1) ? lsb_value : buffer_value[dec_dependency1];
    assign is_found_1_out = (dec_valid && rear_next == dec_dependency1 && dec_rob_state == ROB_STATE_WRITE_RESULT) ||
                        (alu_valid && alu_dependency == dec_dependency1) ||
                        (mem_valid && mem_dependency == dec_dependency1) ||
                        (lsb_valid && lsb_dependency == dec_dependency1) ||
                        (buffer_rob_state[dec_dependency1] == ROB_STATE_WRITE_RESULT);
    assign value2_out = (dec_valid && rear_next == dec_dependency2) ? dec_value :
                    (alu_valid && alu_dependency == dec_dependency2) ? alu_value :
                    (mem_valid && mem_dependency == dec_dependency2) ? mem_value :
                    (lsb_valid && lsb_dependency == dec_dependency2) ? lsb_value : buffer_value[dec_dependency2];
    assign is_found_2_out = (dec_valid && rear_next == dec_dependency2 && dec_rob_state == ROB_STATE_WRITE_RESULT) ||
                        (alu_valid && alu_dependency == dec_dependency2) ||
                        (mem_valid && mem_dependency == dec_dependency2) ||
                        (lsb_valid && lsb_dependency == dec_dependency2) ||
                        (buffer_rob_state[dec_dependency2] == ROB_STATE_WRITE_RESULT);
    assign buffer_full_out = (buffer_size + dec_valid == ROB_SIZE);
    assign next_rob_id_out = (buffer_rear + 1 + dec_valid) & ROB_SIZE;

    // TODO store相关指令可以让RoB提交的时候返还给LSB，由LSB直接写回给Memory，
    //      flush的时候不要清楚LSB中正在写回的store指令，这样可以有效避免RoB被访存指令阻塞。
    always @(posedge clk_in) begin
        if (rst_in) begin
            buffer_head <= 0;
            buffer_rear <= 0;
            buffer_size <= 0;
            rob2rf_ready <= 0;
            rob2mem_ready <= 0;
            rob2lsb_pop_sb <= 0;
            rob2pred_ready <= 0;
            need_flush_out <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
            rob2rf_ready   <= 0;
            rob2mem_ready  <= 0;
            rob2lsb_pop_sb <= 0;
            rob2pred_ready <= 0;
            need_flush_out <= 0;
        end else begin
            if (need_flush_out) begin
                buffer_head <= 0;
                buffer_rear <= 0;
                buffer_size <= 0;
                rob2rf_ready <= 0;
                rob2mem_ready <= 0;
                rob2lsb_pop_sb <= 0;
                rob2pred_ready <= 0;
                need_flush_out <= 0;
            end else begin
                if (dec_valid) begin
                    buffer_rear <= rear_next;
                    buffer_size <= buffer_size + 1;
                    buffer_rob_type[rear_next] <= dec_rob_type;
                    buffer_dest[rear_next] <= dec_dest;
                    buffer_value[rear_next] <= dec_value;
                    buffer_instr_addr[rear_next] <= dec_instr_addr;
                    buffer_jump_addr[rear_next] <= dec_jump_addr;
                    buffer_rob_state[rear_next] <= dec_rob_state;
                    buffer_is_jump[rear_next] <= dec_is_jump;
                    buffer_rear <= rear_next;
                end
                if (alu_valid) begin
                    buffer_value[alu_dependency] <= alu_value;
                    buffer_rob_state[alu_dependency] <= ROB_STATE_WRITE_RESULT;
                end
                if (mem_valid) begin
                    buffer_value[mem_dependency] <= mem_value;
                    buffer_rob_state[mem_dependency] <= ROB_STATE_WRITE_RESULT;
                end
                if (lsb_valid) begin
                    buffer_dest[lsb_dependency] <= lsb_dest;
                    buffer_value[lsb_dependency] <= lsb_value;
                    buffer_rob_state[lsb_dependency] <= ROB_STATE_WRITE_RESULT;
                end
                if (buffer_rob_state[front] == ROB_STATE_WRITE_RESULT) begin
                    case (buffer_rob_type[front])
                        ROB_TYPE_REG: begin
                            rob2rf_rd <= buffer_dest[front];
                            rob2rf_value <= buffer_value[front];
                            rob2rf_rob_id <= front;
                            rob2rf_ready <= 1;
                            rob2mem_ready <= 0;
                            rob2lsb_pop_sb <= 0;
                            rob2pred_ready <= 0;
                            need_flush_out <= 0;
                        end
                        ROB_TYPE_JALR: begin
                            rob2rf_rd <= buffer_dest[front];
                            rob2rf_value <= buffer_instr_addr[front] + 4;
                            rob2rf_rob_id <= front;
                            rob2rf_ready <= 1;
                            rob2mem_ready <= 0;
                            rob2lsb_pop_sb <= 0;
                            rob2pred_ready <= 0;
                            if (buffer_jump_addr[front] != buffer_value[front]) begin
                                rob2if_jump_addr <= buffer_value[front];
                                need_flush_out   <= 1;
                            end else begin
                                need_flush_out <= 0;
                            end
                        end
                        ROB_TYPE_STORE_BYTE: begin
                            if (!mem_busy) begin
                                rob2mem_store_type <= STORE_BYTE;
                                rob2mem_addr <= buffer_dest[front];
                                rob2mem_value <= buffer_value[front];
                                rob2mem_ready <= 1;
                                rob2lsb_pop_sb <= 1;
                                rob2rf_ready <= 0;
                                rob2pred_ready <= 0;
                                need_flush_out <= 0;
                            end
                        end
                        ROB_TYPE_STORE_HALF: begin
                            if (!mem_busy) begin
                                rob2mem_store_type <= STORE_HALF;
                                rob2mem_addr <= buffer_dest[front];
                                rob2mem_value <= buffer_value[front];
                                rob2mem_ready <= 1;
                                rob2lsb_pop_sb <= 1;
                                rob2rf_ready <= 0;
                                rob2pred_ready <= 0;
                                need_flush_out <= 0;
                            end
                        end
                        ROB_TYPE_STORE_WORD: begin
                            if (!mem_busy) begin
                                rob2mem_store_type <= STORE_WORD;
                                rob2mem_addr <= buffer_dest[front];
                                rob2mem_value <= buffer_value[front];
                                rob2mem_ready <= 1;
                                rob2lsb_pop_sb <= 1;
                                rob2rf_ready <= 0;
                                rob2pred_ready <= 0;
                                need_flush_out <= 0;
                            end
                        end
                        ROB_TYPE_BRANCH: begin
                            rob2pred_instr_addr <= buffer_instr_addr[front];
                            rob2pred_is_jump <= (buffer_value[front] == 1);
                            rob2pred_ready <= 1;
                            rob2rf_ready <= 0;
                            rob2mem_ready <= 0;
                            rob2lsb_pop_sb <= 0;
                            if (buffer_value[front] != buffer_is_jump[front]) begin
                                rob2if_jump_addr <= (buffer_value[front] == 1) ? buffer_jump_addr[front] : buffer_instr_addr[front] + 4;
                                need_flush_out <= 1;
                            end else begin
                                need_flush_out <= 0;
                            end
                        end
                    endcase
                end
            end
        end
    end

endmodule
