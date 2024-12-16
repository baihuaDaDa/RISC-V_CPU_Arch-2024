`include "src/const_param.v"

module instr_fetcher (
    input clk_in,
    input rst_in,
    input rdy_in,

    input need_flush_in,
    input is_stall_in,

    input [31:0] rob_jump_addr,

    output reg        if2dec_ready,
    output reg [31:0] if2dec_instr,
    output reg [31:0] if2dec_instr_addr,
    output reg        if2dec_is_jump,
    output reg [31:0] if2dec_jump_addr,

    // combinatorial logic
    input        pred_is_jump,
    input        ic_hit,
    input        ic_miss_ready,
    input [31:0] ic_instr,
    input [31:0] rf_value_jalr,

    output wire                      fetch_enable_out,
    output wire [              31:0] pc_out,
    output wire [`REG_NUM_WIDTH-1:0] rs_jalr_out
);

    reg [31:0] pc;

    wire [31:0] imm_13_B = {{20{ic_instr[31]}}, ic_instr[7], ic_instr[30:25], ic_instr[11:8], 1'b0};
    wire [31:0] imm_21_J = {
        {12{ic_instr[31]}}, ic_instr[19:12], ic_instr[20], ic_instr[30:21], 1'b0
    };
    wire [31:0] imm_12_I = {{20{ic_instr[31]}}, ic_instr[31:20]};
    wire [31:0] imm_C_J = {
        {21{ic_instr[12]}},
        ic_instr[8],
        ic_instr[10:9],
        ic_instr[6],
        ic_instr[7],
        ic_instr[2],
        ic_instr[11],
        ic_instr[5:3],
        1'b0
    };  // imm[11|4|9:8|10|6|7|3:1|5], for C.JAL and C.J (J-type)
    wire [31:0] imm_C_B = {
        {24{ic_instr[12]}}, ic_instr[6:5], ic_instr[2], ic_instr[11:10], ic_instr[4:3], 1'b0
    };  // imm[8|4:3], imm[7:6|2:1|5], for C.BEQZ, C.BNEZ (B-type)

    assign fetch_enable_out = !need_flush_in && !is_stall_in && !ic_miss_ready;
    assign pc_out = pc;
    assign rs_jalr_out = (ic_hit || ic_miss_ready) && ic_instr[1:0] == 2'b11 && ic_instr[6:2] == 5'b11001 ? ic_instr[19:15] :
                         (ic_hit || ic_miss_ready) && ic_instr[1:0] != 2'b11 && ic_instr[15:13] == 3'b100 && ic_instr[6:2] == 0 ? ic_instr[11:7] : 5'b0;

    // TODO: when to stop?
    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            if2dec_ready <= 0;
            pc <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (need_flush_in) begin
                if2dec_ready <= 0;
                pc <= rob_jump_addr;
            end else if (is_stall_in) begin
                /* do nothing */
            end else begin
                if (ic_hit || ic_miss_ready) begin
                    if2dec_ready <= 1;
                    if2dec_instr <= ic_instr;
                    if2dec_instr_addr <= pc;
                    if2dec_is_jump <= pred_is_jump;
                    if (ic_instr[1:0] == 2'b11) begin
                        case (ic_instr[6:2])
                            5'b11011: begin  // JAL
                                pc <= pc + imm_21_J;
                                if2dec_jump_addr <= pc + imm_21_J;
                            end
                            5'b11001: begin  // JALR
                                pc <= rf_value_jalr + imm_12_I;
                                if2dec_jump_addr <= rf_value_jalr + imm_12_I;
                            end
                            5'b11000: begin  // B-type
                                if2dec_jump_addr <= pc + imm_13_B;
                                if (pred_is_jump) begin
                                    pc <= pc + imm_13_B;
                                end else begin
                                    pc <= pc + 4;
                                end
                            end
                            default: pc <= pc + 4;
                        endcase
                    end else begin
                        case (ic_instr[1:0])
                            2'b01: begin
                                case (ic_instr[15:13])
                                    3'b001, 3'b101: begin  // C.JAL, C.J
                                        pc <= pc + imm_C_J;
                                        if2dec_jump_addr <= pc + imm_C_J;
                                    end
                                    3'b110, 3'b111: begin  // C.BEQZ, C.BNEZ
                                        if2dec_jump_addr <= pc + imm_C_B;
                                        if (pred_is_jump) begin
                                            pc <= pc + imm_C_B;
                                        end else begin
                                            pc <= pc + 2;
                                        end
                                    end
                                    default: pc <= pc + 2;
                                endcase
                            end
                            2'b10: begin
                                if (ic_instr[15:13] == 3'b100 && ic_instr[6:2] == 0) begin // C.JR, C.JALR
                                    pc <= rf_value_jalr;
                                    if2dec_jump_addr <= rf_value_jalr;
                                end else begin  // C.MV, C.ADD
                                    pc <= pc + 2;
                                end
                            end
                            default: pc <= pc + 2;
                        endcase
                    end
                end else begin
                    if2dec_ready <= 0;
                end
            end
        end
    end

endmodule
