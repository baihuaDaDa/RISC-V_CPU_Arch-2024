`include "src/const_param.v"

module dec(
    input clk_in,
    input rst_in,
    input rdy_in,

    input if_valid,
    input [31:0] if_instr,
    input [31:0] if_instr_addr,
    input [31:0] if_age,
    input if_is_jump,
    input [31:0] if_jump_addr,

    input need_flush_in,

    input mem_busy,

    output reg dec2rob_ready,
    output reg [`ROB_TYPE_NUM_WIDTH-1:0] dec2rob_rob_type,
    output reg [`REG_NUM_WIDTH-1:0] dec2rob_dest,
    output reg [31:0] dec2rob_value,
    output reg [31:0] dec2rob_instr_addr,
    output reg [31:0] dec2rob_jump_addr,
    output reg [`ROB_STATE_NUM_WIDTH-1:0] dec2rob_rob_state,
    output reg dec2rob_is_jump,
    
    output reg dec2rs_ready,
    output reg [2:0] dec2rs_calc_op_L1,
    output reg dec2rs_calc_op_L2,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2rs_dependency1,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2rs_dependency2,
    output reg [31:0] dec2rs_value1,
    output reg [31:0] dec2rs_value2,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2rs_rob_id,

    output reg dec2lsb_ready,
    output reg [`MEM_TYPE_NUM_WIDTH-1:0] dec2lsb_mem_type,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2lsb_dependency1,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2lsb_dependency2,
    output reg [31:0] dec2lsb_value1,
    output reg [31:0] dec2lsb_value2,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2lsb_rob_id,
    output reg [31:0] dec2lsb_age,
    
    output reg dec2rf_ready,
    output reg [`REG_NUM_WIDTH-1:0] dec2rf_rd,
    output reg [`ROB_SIZE_WIDTH-1:0] dec2rf_dependency
);

    always @(posedge clk_in) begin
        if (rst_in) begin
            dec2rob_ready <= 0;
            dec2rs_ready <= 0;
            dec2lsb_ready <= 0;
            dec2rf_ready <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
            dec2rob_ready <= 0;
            dec2rs_ready <= 0;
            dec2lsb_ready <= 0;
            dec2rf_ready <= 0;
        end else begin
            if (!need_flush_in && if_valid) begin
                case (if_instr[1:0])
                    case 2'b00, 2'b01:
                    endcase
                    case 2'b11:
                endcase
            end else begin
                dec2rob_ready <= 0;
                dec2rs_ready <= 0;
                dec2lsb_ready <= 0;
                dec2rf_ready <= 0;
            end
        end
    end

endmodule