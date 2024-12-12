`include "src/const_param.v"

module ALU (
    input need_flush_in,

    input                            valid,
    input      [               31:0] opr1_in,
    input      [               31:0] opr2_in,
    input      [`ROB_SIZE_WIDTH-1:0] rob_id_in,
    input      [`ROB_SIZE_WIDTH-1:0] alu_op_L1_in,
    input                            alu_op_L2_in,
    input                            alu_is_I_type,
    input                            clk_in,
    input                            rst_in,
    input                            rdy_in,
    output reg [               31:0] value_out,
    output reg [`ROB_SIZE_WIDTH-1:0] rob_id_out,
    output reg                       ready
);

    localparam [2:0] ALU_ADD_SUB = 3'b000;
    localparam [2:0] ALU_SLL = 3'b001;
    localparam [2:0] ALU_SLT = 3'b010;
    localparam [2:0] ALU_SLTU = 3'b011;
    localparam [2:0] ALU_XOR = 3'b100;
    localparam [2:0] ALU_SRL_SRA = 3'b101;
    localparam [2:0] ALU_OR = 3'b110;
    localparam [2:0] ALU_AND = 3'b111;

    localparam ALU_ADD = 1'b0;
    localparam ALU_SUB = 1'b1;
    localparam ALU_SRL = 1'b0;
    localparam ALU_SRA = 1'b1;

    always @(posedge clk_in) begin
        if (rst_in) begin
            ready <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
            ready <= 0;
        end else begin
            if (!need_flush_in && valid) begin
                case (alu_op_L1_in)
                    ALU_ADD_SUB: begin
                        if (alu_is_I_type) begin
                            value_out <= opr1_in + opr2_in;
                        end else begin
                            case (alu_op_L2_in)
                                ALU_ADD: value_out <= opr1_in + opr2_in;
                                ALU_SUB: value_out <= opr1_in - opr2_in;
                            endcase
                        end
                    end
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
                endcase
                rob_id_out <= rob_id_in;
                ready <= 1;
            end else begin
                ready <= 0;
            end
        end
    end

endmodule
