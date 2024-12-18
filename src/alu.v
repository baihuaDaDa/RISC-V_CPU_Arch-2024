`include "src/const_param.v"

module alu (
    input clk_in,
    input rst_in,
    input rdy_in,

    input need_flush_in,

    input                            valid_in,
    input [                    31:0] opr1_in,
    input [                    31:0] opr2_in,
    input [       `ROB_SIZE_WIDTH:0] dependency_in,
    input [CALC_OP_L1_NUM_WIDTH-1:0] alu_op_L1_in,
    input                            alu_op_L2_in,

    output reg [             31:0] value_out,
    output reg [`ROB_SIZE_WIDTH:0] dependency_out,
    output reg                     ready_out
);

    localparam CALC_OP_L1_NUM_WIDTH = `CALC_OP_L1_NUM_WIDTH;

    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_ADD_SUB = 4'b0000;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SLL = 4'b0001;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SLT = 4'b0010;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SLTU = 4'b0011;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_XOR = 4'b0100;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SRL_SRA = 4'b0101;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_OR = 4'b0110;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_AND = 4'b0111;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SEQ = 4'b1000;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SNE = 4'b1001;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SGE = 4'b1101;
    localparam [CALC_OP_L1_NUM_WIDTH-1:0] ALU_SGEU = 4'b1111;

    localparam ALU_ADD = 1'b0;
    localparam ALU_SUB = 1'b1;
    localparam ALU_SRL = 1'b0;
    localparam ALU_SRA = 1'b1;

    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            ready_out <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (!need_flush_in && valid_in) begin
                case (alu_op_L1_in)
                    ALU_ADD_SUB:
                    case (alu_op_L2_in)
                        ALU_ADD: value_out <= opr1_in + opr2_in;
                        ALU_SUB: value_out <= opr1_in - opr2_in;
                    endcase
                    ALU_SLL: value_out <= opr1_in << opr2_in[4:0];
                    ALU_SLT: value_out <= ($signed(opr1_in) < $signed(opr2_in));
                    ALU_SLTU: value_out <= opr1_in < opr2_in;
                    ALU_XOR: value_out <= opr1_in ^ opr2_in;
                    ALU_SRL_SRA:
                    case (alu_op_L2_in)
                        ALU_SRL: value_out <= opr1_in >> opr2_in[4:0];
                        ALU_SRA: value_out <= $signed(opr1_in) >>> opr2_in[4:0];
                    endcase
                    ALU_OR: value_out <= opr1_in | opr2_in;
                    ALU_AND: value_out <= opr1_in & opr2_in;
                    ALU_SEQ: value_out <= opr1_in == opr2_in;
                    ALU_SNE: value_out <= opr1_in != opr2_in;
                    ALU_SGE: value_out <= ($signed(opr1_in) >= $signed(opr2_in));
                    ALU_SGEU: value_out <= opr1_in >= opr2_in;
                endcase
                dependency_out <= dependency_in;
                ready_out <= 1;
            end else begin
                ready_out <= 0;
            end
        end
    end

endmodule
