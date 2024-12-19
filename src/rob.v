`include "src/const_param.v"

module rob (

    input clk_in,
    input rst_in,
    input rdy_in,

    input [                    3:0] dec_valid,
    input [ ROB_TYPE_NUM_WIDTH-1:0] dec_rob_type,
    input [     `REG_NUM_WIDTH-1:0] dec_dest,
    input [                   31:0] dec_value,
    input [                   31:0] dec_instr_addr,
    input [                   31:0] dec_jump_addr,
    input [ROB_STATE_NUM_WIDTH-1:0] dec_rob_state,
    input                           dec_is_jump,

    input                    alu_valid,
    input [ROB_SIZE_WIDTH:0] alu_dependency,
    input [            31:0] alu_value,

    input                    mem_valid,
    input [ROB_SIZE_WIDTH:0] mem_dependency,
    input [            31:0] mem_value,
    input                    mem_busy,

    input                      lsb_valid,
    input [ROB_SIZE_WIDTH-1:0] lsb_rob_id,
    input [              31:0] lsb_dest,
    input [              31:0] lsb_value,

    output reg rob2rf_ready,
    output reg rob2mem_ready,
    output reg rob2lsb_pop_sb,
    output reg rob2pred_ready,
    output reg need_flush_out,

    output reg [`REG_NUM_WIDTH-1:0] rd_out,  // for rf
    output reg [31:0] value_out,  // for rf and mem
    output reg [ROB_SIZE_WIDTH:0] dependency_out,  // for rf
    output reg [STORE_TYPE_NUM_WIDTH-1:0] store_type_out,  // for mem
    output reg [31:0] data_addr_out,  // for mem
    output reg [31:0] jump_addr_out,  // for if, valid only if need_flush_out is high
    output reg [31:0] instr_addr_out,  // for pred
    output reg is_jump_out,  // for pred

    // combinatorial logic
    input wire [`ROB_SIZE_WIDTH:0] rf_dependency1,
    input wire [`ROB_SIZE_WIDTH:0] rf_dependency2,

    output wire                      is_found_1_out,
    output wire [              31:0] value1_out,
    output wire                      is_found_2_out,
    output wire [              31:0] value2_out,
    output wire                      buffer_full_out,
    output wire [ROB_SIZE_WIDTH-1:0] rear_next_out
);

    localparam ROB_SIZE_WIDTH = `ROB_SIZE_WIDTH;
    localparam ROB_SIZE = `ROB_SIZE;
    localparam ROB_TYPE_NUM_WIDTH = `ROB_TYPE_NUM_WIDTH;
    localparam ROB_STATE_NUM_WIDTH = `ROB_STATE_NUM_WIDTH;
    localparam STORE_TYPE_NUM_WIDTH = `STORE_TYPE_NUM_WIDTH;

    localparam [ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_COMMIT = 2'b00;
    localparam [ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_EXECUTE = 2'b01;
    localparam [ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_WRITE_RESULT = 2'b10;

    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_BYTE = 3'b000;
    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_HALF = 3'b001;
    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_WORD = 3'b010;
    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_REG = 3'b011;
    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_JALR = 3'b100;
    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_BRANCH = 3'b101;
    localparam [ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_EXIT = 3'b110;

    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_BYTE = 2'b00;
    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_HALF = 2'b01;
    localparam [STORE_TYPE_NUM_WIDTH-1:0] STORE_WORD = 2'b10;

    // LoopQueue<RoBEntry, kBufferCapBin> buffer;
    reg [ROB_SIZE_WIDTH-1:0] buffer_head, buffer_rear, buffer_size;
    reg     [ ROB_TYPE_NUM_WIDTH-1:0] buffer_rob_type  [ROB_SIZE:0];  // ROB_SIZE = 31
    reg     [     `REG_NUM_WIDTH-1:0] buffer_dest_reg  [ROB_SIZE:0];
    reg     [                   31:0] buffer_dest_mem  [ROB_SIZE:0];  // for S-type
    reg     [                   31:0] buffer_value     [ROB_SIZE:0];
    reg     [                   31:0] buffer_instr_addr[ROB_SIZE:0];
    reg     [                   31:0] buffer_jump_addr [ROB_SIZE:0];
    reg     [ROB_STATE_NUM_WIDTH-1:0] buffer_rob_state [ROB_SIZE:0];
    reg                               buffer_is_jump   [ROB_SIZE:0];

    integer                           i;

    wire    [     ROB_SIZE_WIDTH-1:0] front;

    assign front = (buffer_head + 1) & ROB_SIZE;

    assign value1_out = (alu_valid && alu_dependency == rf_dependency1) ? alu_value :
                    (mem_valid && mem_dependency == rf_dependency1) ? mem_value : buffer_value[rf_dependency1];
    assign is_found_1_out = (alu_valid && alu_dependency == rf_dependency1) ||
                        (mem_valid && mem_dependency == rf_dependency1) ||
                        (buffer_rob_state[rf_dependency1] == ROB_STATE_WRITE_RESULT);
    assign value2_out = (alu_valid && alu_dependency == rf_dependency2) ? alu_value :
                    (mem_valid && mem_dependency == rf_dependency2) ? mem_value : buffer_value[rf_dependency2];
    assign is_found_2_out = (alu_valid && alu_dependency == rf_dependency2) ||
                        (mem_valid && mem_dependency == rf_dependency2) ||
                        (buffer_rob_state[rf_dependency2] == ROB_STATE_WRITE_RESULT);
    assign buffer_full_out = (buffer_size + dec_valid[0] == ROB_SIZE);
    assign rear_next_out = (buffer_rear + 1) & ROB_SIZE;

    // assign value1_out = 0;
    // assign is_found_1_out = 0;
    // assign value2_out = 0;
    // assign is_found_2_out = 0;

    /* debug */
    wire [ROB_TYPE_NUM_WIDTH-1:0] top_rob_type = buffer_rob_type[front];
    wire [`REG_NUM_WIDTH-1:0] top_dest_reg = buffer_dest_reg[front];
    wire [31:0] top_dest_mem = buffer_dest_mem[front];
    wire [31:0] top_value = buffer_value[front];
    wire [31:0] top_instr_addr = buffer_instr_addr[front];
    wire [31:0] top_jump_addr = buffer_jump_addr[front];
    wire [ROB_STATE_NUM_WIDTH-1:0] top_rob_state = buffer_rob_state[front];
    wire top_is_jump = buffer_is_jump[front];

    // TODO store相关指令可以让RoB提交的时候返还给LSB，由LSB直接写回给Memory，
    //      flush的时候不要清楚LSB中正在写回的store指令，这样可以有效避免RoB被访存指令阻塞。
    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            rob2rf_ready <= 0;
            rob2mem_ready <= 0;
            rob2lsb_pop_sb <= 0;
            rob2pred_ready <= 0;
            need_flush_out <= 0;
            rd_out <= 0;
            value_out <= 0;
            dependency_out <= -1;
            store_type_out <= 0;
            data_addr_out <= 0;
            jump_addr_out <= 0;
            instr_addr_out <= 0;
            is_jump_out <= 0;
            buffer_head <= 0;
            buffer_rear <= 0;
            buffer_size <= 0;
            for (i = 0; i <= ROB_SIZE; i = i + 1) begin
                buffer_rob_type[i] <= 0;
                buffer_dest_reg[i] <= 0;
                buffer_dest_mem[i] <= 0;
                buffer_value[i] <= 0;
                buffer_instr_addr[i] <= 0;
                buffer_jump_addr[i] <= 0;
                buffer_rob_state[i] <= 0;
                buffer_is_jump[i] <= 0;
            end
        end else if (!rdy_in) begin
            /* do nothing */
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
                if (dec_valid[0]) begin
                    buffer_rear <= rear_next_out;
                    buffer_rob_type[rear_next_out] <= dec_rob_type;
                    buffer_dest_reg[rear_next_out] <= dec_dest;
                    buffer_value[rear_next_out] <= dec_value;
                    buffer_instr_addr[rear_next_out] <= dec_instr_addr;
                    buffer_jump_addr[rear_next_out] <= dec_jump_addr;
                    buffer_rob_state[rear_next_out] <= dec_rob_state;
                    buffer_is_jump[rear_next_out] <= dec_is_jump;
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
                    buffer_dest_mem[lsb_rob_id] <= lsb_dest;
                    buffer_value[lsb_rob_id] <= lsb_value;
                    buffer_rob_state[lsb_rob_id] <= ROB_STATE_WRITE_RESULT;
                end
                if (buffer_size && buffer_rob_state[front] == ROB_STATE_WRITE_RESULT) begin
                    case (buffer_rob_type[front])
                        ROB_TYPE_REG: begin
                            rd_out <= buffer_dest_reg[front];
                            value_out <= buffer_value[front];
                            dependency_out <= front;
                            rob2rf_ready <= 1;
                            rob2mem_ready <= 0;
                            rob2lsb_pop_sb <= 0;
                            rob2pred_ready <= 0;
                            need_flush_out <= 0;
                        end
                        ROB_TYPE_JALR: begin
                            rd_out <= buffer_dest_reg[front];
                            value_out <= buffer_instr_addr[front] + 4;
                            dependency_out <= front;
                            rob2rf_ready <= 1;
                            rob2mem_ready <= 0;
                            rob2lsb_pop_sb <= 0;
                            rob2pred_ready <= 0;
                            if (buffer_jump_addr[front] != buffer_value[front]) begin
                                jump_addr_out  <= buffer_value[front];
                                need_flush_out <= 1;
                            end else begin
                                need_flush_out <= 0;
                            end
                        end
                        ROB_TYPE_STORE_BYTE, ROB_TYPE_STORE_HALF, ROB_TYPE_STORE_WORD: begin
                            if (!mem_busy) begin
                                store_type_out <= buffer_rob_type[front][1:0];
                                data_addr_out <= buffer_dest_mem[front];
                                value_out <= buffer_value[front];
                                rob2mem_ready <= 1;
                                rob2lsb_pop_sb <= 1;
                            end else begin
                                rob2mem_ready  <= 0;
                                rob2lsb_pop_sb <= 0;
                            end
                            rob2rf_ready   <= 0;
                            rob2pred_ready <= 0;
                            need_flush_out <= 0;
                        end
                        ROB_TYPE_BRANCH: begin
                            instr_addr_out <= buffer_instr_addr[front];
                            is_jump_out <= (buffer_value[front] == 1);
                            rob2pred_ready <= 1;
                            rob2rf_ready <= 0;
                            rob2mem_ready <= 0;
                            rob2lsb_pop_sb <= 0;
                            if (buffer_value[front] != buffer_is_jump[front]) begin
                                jump_addr_out <= (buffer_value[front] == 1) ? buffer_jump_addr[front] : buffer_instr_addr[front] + 4;
                                need_flush_out <= 1;
                            end else begin
                                need_flush_out <= 0;
                            end
                        end
                    endcase
                    if (!mem_busy || (buffer_rob_type[front] != ROB_TYPE_STORE_BYTE && buffer_rob_type[front] != ROB_TYPE_STORE_HALF && buffer_rob_type[front] != ROB_TYPE_STORE_WORD)) begin
                        buffer_head <= front;
                        buffer_size <= buffer_size + dec_valid[0] - 1;
                    end else begin
                        buffer_size <= buffer_size + dec_valid[0];
                    end
                end else begin
                    buffer_size <= buffer_size + dec_valid[0];
                    rob2rf_ready <= 0;
                    rob2mem_ready <= 0;
                    rob2lsb_pop_sb <= 0;
                    rob2pred_ready <= 0;
                    need_flush_out <= 0;
                end
            end
        end
    end

endmodule
