module ALU(
	input [31:0] opr1, opr2,
    input [`ROB_WIDTH:0] rob_id,
	input [`ROB_WIDTH:0] alu_op_L1,
    input alu_op_L2,
    input clk,
    input rst,
	output reg [31:0] alu_out
);

    localparam (
        [2:0] ALU_ADD_SUB = 3'b000,
        [2:0] ALU_SLL = 3'b001;
        [2:0] ALU_SLT = 3'b010,
        [2:0] ALU_SLTU  = 3'b011,
        [2:0] ALU_XOR = 3'b100,
        [2:0] ALU_SRL_SRA = 3'b101,
        [2:0] ALU_OR = 3'b110,
        [2:0] ALU_AND= 3'b111,

        ALU_ADD = 1'b0,
        ALU_SUB = 1'b1,
        ALU_SRL = 1'b0,
        ALU_SRA = 1'b1
    )
    
    always @(posedge clk) begin
        case (alu_op_L1)
            ALU_ADD_SUB: alu_out <= case (alu_op_L2)
                ALU_ADD: opr1 + opr2;
                ALU_SUB: opr1 - opr2;
            endcase
            ALU_SLL: alu_out <= opr1 << opr2[4:0];
            ALU_SLT: alu_out <= ($signed(opr1) < $signed(opr2));
            ALU_SLTU: alu_out <= opr1 < opr2;
            ALU_XOR: alu_out <= opr1 ^ opr2;
            ALU_SRL_SRA: alu_out <= case (alu_op_L2)
                ALU_SRL: opr1 >> opr2[4:0];
                ALU_SRA: $signed(opr1) >>> opr2[4:0];
            endcase
            ALU_OR: alu_out <= opr1 | opr2;
            ALU_AND: alu_out <= opr1 & opr2;
            default: alu_out <= 32'b0;
        endcase
    end

endmodule