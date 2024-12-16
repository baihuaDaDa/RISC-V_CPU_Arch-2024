`include "src/const_param.v"

module predictor(
    input clk_in,
    input rst_in,
    input rdy_in,

    input rob_valid,
    input [31:0] rob_instr_addr,
    input rob_is_jump,

    // combinatorial logic
    input [31:0] pc_in,
    output wire pred2if_result
);

    localparam PREDICTOR_SIZE = `PREDICTOR_SIZE;
    localparam PREDICTOR_SIZE_WIDTH = `PREDICTOR_SIZE_WIDTH;
    localparam PREDICTOR_MOD = PREDICTOR_SIZE - 1;

    reg [31:0] counter [PREDICTOR_SIZE-1:0];

    integer i;
    wire [31:0] index;
    
    assign index = (rob_instr_addr >> 2) & PREDICTOR_MOD;

    // predict
    assign pred2if_result = (counter[(pc_in >> 2) & PREDICTOR_MOD] > 1);

    // update
    always@(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            for (i = 0; i < PREDICTOR_SIZE; i = i + 1) begin
                counter[i] <= 0;
            end
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (rob_valid) begin
                if (rob_is_jump && counter[index] != 2'b11) begin
                    counter[index] <= counter[index] + 1;
                end else if (!rob_is_jump && counter[index] != 2'b00) begin
                    counter[index] <= counter[index] - 1;
                end
            end
        end
    end

endmodule