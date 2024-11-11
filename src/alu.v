module ALU(
    input valid,
	input [31:0] opr1_in, opr2_in,
    input [`ROB_WIDTH-1:0] rob_id_in,
	input [`ROB_WIDTH-1:0] alu_op_L1_in,
    input alu_op_L2_in,
    input clk_in,
    input rst_in,
    input rdy_in,
	output reg [31:0] value_out,
    output reg [`ROB_WIDTH-1:0] rob_id_out,
    output ready
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
    
    always @(posedge clk_in) begin
        if (rst_in) begin
            value_out <= 32'b0;
            rob_id_out <= 0;
            ready <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (valid) begin
                case (alu_op_L1_in)
                    ALU_ADD_SUB: value_out <= case (alu_op_L2_in)
                        ALU_ADD: opr1_in + opr2_in;
                        ALU_SUB: opr1_in - opr2_in;
                    endcase
                    ALU_SLL: value_out <= opr1_in << opr2_in[4:0];
                    ALU_SLT: value_out <= ($signed(opr1_in) < $signed(opr2_in));
                    ALU_SLTU: value_out <= opr1_in < opr2_in;
                    ALU_XOR: value_out <= opr1_in ^ opr2_in;
                    ALU_SRL_SRA: value_out <= case (alu_op_L2_in)
                        ALU_SRL: opr1_in >> opr2_in[4:0];
                        ALU_SRA: $signed(opr1_in) >>> opr2_in[4:0];
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