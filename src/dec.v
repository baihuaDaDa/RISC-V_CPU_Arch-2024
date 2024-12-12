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

    output reg is_stall_out,

    output reg dec2rob_ready,
    output reg dec2rs_ready,
    output reg dec2lsb_ready,
    output reg dec2rf_ready,

    output reg [`ROB_TYPE_NUM_WIDTH-1:0] rob_type_out,
    output reg [`REG_NUM_WIDTH-1:0] dest_out, // for rob, rf
    output reg [31:0] result_value_out,
    output reg [31:0] instr_addr_out,
    output reg [31:0] jump_addr_out,
    output reg [`ROB_STATE_NUM_WIDTH-1:0] rob_state_out,
    output reg is_jump_out,
    output reg [`CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_out, // for rs
    output reg calc_op_L2_out, // for rs
    output reg [`ROB_SIZE_WIDTH-1:0] dependency1_out,
    output reg [`ROB_SIZE_WIDTH-1:0] dependency2_out,
    output reg [31:0] value1_out,
    output reg [31:0] value2_out,
    output reg [31:0] imm_out, // for lsb (store)
    output reg [`ROB_SIZE_WIDTH-1:0] rob_id_out, // also for rf as dependency
    output reg [`MEM_TYPE_NUM_WIDTH-1:0] mem_type_out, // for lsb
    output reg [31:0] age_out, // for lsb

    // combinatorial logic
    input [`ROB_SIZE_WIDTH-1:0] rob_next_rob_id,

    input [`ROB_SIZE_WIDTH-1:0] rf_dependency1,
    input [`ROB_SIZE_WIDTH-1:0] rf_dependency2,
    input [31:0] rf_value1,
    input [31:0] rf_value2,
    input rob_is_found_1,
    input [31:0] rob_value1,
    input rob_is_found_2,
    input [31:0] rob_value2,

    input rob_full,
    input rs_full,
    input lb_full,
    input sb_full
);

    localparam [`ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_COMMIT = 2'b00;
    localparam [`ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_EXECUTE = 2'b01;
    localparam [`ROB_STATE_NUM_WIDTH-1:0] ROB_STATE_WRITE_RESULT = 2'b10;

    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_BYTE = 3'b000;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_HALF = 3'b001;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_STORE_WORD = 3'b010;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_REG = 3'b011;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_JALR = 3'b100;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_BRANCH = 3'b101;
    localparam [`ROB_TYPE_NUM_WIDTH-1:0] ROB_TYPE_EXIT = 3'b110;

    wire [4:0] op = if_instr[6:2];
    wire [1:0] is_C = if_instr[1:0];
    wire [2:0] sub_op = if_instr[14:12]; // branch, load, store, calc_L1
    wire calc_op_L2 = if_instr[30];
    wire [`REG_NUM_WIDTH-1:0] rd = if_instr[11:7];
    wire [`REG_NUM_WIDTH-1:0] rs1 = if_instr[19:15];
    wire [`REG_NUM_WIDTH-1:0] rs2 = if_instr[24:20];
    wire [31:0] imm_32_U = if_instr[31:12] << 12;
    wire [31:0] imm_21_J = {if_instr[31], if_instr[19:12], if_instr[20], if_instr[30:21], 1'b0};
    wire [31:0] imm_12_I = if_instr[31:20]; // except SRAI, SRLI, SLLI
    wire [31:0] imm_5_shamt = if_instr[24:20];
    wire [31:0] imm_13_B = {if_instr[31], if_instr[7], if_instr[30:25], if_instr[11:8], 1'b0};
    wire [31:0] imm_12_S = {if_instr[31:25], if_instr[11:7]};
    wire [2:0] op_C = if_instr[15:13];
    wire [2:0] sub_op_C_L1 = if_instr[15:13];
    wire sub_op_C_L2 = if_instr[12];
    wire [1:0] sub_op_C_L3 = if_instr[11:10];
    wire [1:0] sub_op_C_L4 = if_instr[6:5];
    wire [`REG_NUM_WIDTH-1:0] rs1_C_3 = if_instr[9:7]; // rs1/rd 3-bit
    wire [`REG_NUM_WIDTH-1:0] rs2_C_3 = if_instr[4:2]; // rs2/rd 3-bit
    wire [`REG_NUM_WIDTH-1:0] rs1_C_5 = if_instr[11:7]; // rs1/rd 5-bit
    wire [`REG_NUM_WIDTH-1:0] rs2_C_5 = if_instr[6:2]; // rs2/rd 5-bit
    wire [31:0] imm_C_LSW = {if_instr[5], if_instr[12:10], if_instr[6], 2'b00};// uimm[5:3], uimm[2|6], for C.LW, C.SW
    wire [31:0] imm_C_ADDI4SPN = {if_instr[10:7], if_instr[12:11], if_instr[5], if_instr[6], 2'b00}; // uimm[5:4|9:6|2|3], for C.ADDI4SPN
    wire [31:0] imm_C_I = {if_instr[12], if_instr[6:2]}; // for I-type
    // imm[11|4|9:8|10|6|7|3:1|5], for C.JAL and C.J (J-type)
    wire [31:0] imm_C_J = {if_instr[12], if_instr[8], if_instr[10:9], if_instr[6], if_instr[7], if_instr[2], if_instr[11], if_instr[5:3], 1'b0};
    // imm[9], imm[4|6|8:7|5], for C.ADDI16SP
    wire [31:0] imm_C_ADDI16SP = {if_instr[12], if_instr[4:3], if_instr[5], if_instr[2], if_instr[6], 4'b0000};
    wire [31:0] imm_C_LUI = {if_instr[12], if_instr[6:2], 12'b0000_0000_0000}; // imm[17], imm[16:12], for C.LUI
    wire [31:0] imm_C_B = {if_instr[12], if_instr[6:5], if_instr[2], if_instr[11:10], if_instr[4:3], 1'b0}; // imm[8|4:3], imm[7:6|2:1|5], for C.BEQZ, C.BNEZ (B-type)
    wire [31:0] imm_C_LWSP = {if_instr[3:2], if_instr[12], if_instr[6:4], 2'b00}; // uimm[5], uimm[4:2|7:6]
    wire [31:0] imm_C_SWSP = {if_instr[8:7], if_instr[12:9], 2'b00}; // uimm[5:2|7:6]

    wire [`ROB_SIZE_WIDTH-1:0] dependency1;
    wire [`ROB_SIZE_WIDTH-1:0] dependency2;
    wire [31:0] value1;
    wire [31:0] value2;

    assign dependency1 = (rf_dependency1 == -1) ? -1 : (rob_is_found_1 ? -1 : rf_dependency1);
    assign dependency2 = (rf_dependency2 == -1) ? -1 : (rob_is_found_2 ? -1 : rf_dependency2);
    assign value1 = (rf_dependency1 == -1) ? rf_value1 : (rob_is_found_1 ? rob_value1 : 0);
    assign value2 = (rf_dependency2 == -1) ? rf_value2 : (rob_is_found_2 ? rob_value2 : 0);

    always @(posedge clk_in) begin
        if (rst_in) begin
            dec2rob_ready <= 0;
            dec2rs_ready <= 0;
            dec2lsb_ready <= 0;
            dec2rf_ready <= 0;
            is_stall_out <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
            dec2rob_ready <= 0;
            dec2rs_ready <= 0;
            dec2lsb_ready <= 0;
            dec2rf_ready <= 0;
            is_stall_out <= 0;
        end else begin
            if (!need_flush_in && if_valid) begin
                case (is_C)
                    2'b00: begin
                        case (sub_op_C_L1)
                            3'b000: begin // C.ADDI4SPN
                            end
                            3'b010: begin // C.LW
                            end
                            3'b110: begin // C.SW
                            end
                        endcase
                    end
                    2'b01: begin
                        case (sub_op_C_L1)
                            3'b000: begin // C.ADDI
                            end
                            3'b001: begin // C.JAL
                            end
                            3'b010: begin // C.LI
                            end
                            3'b011: begin // C.ADDI16SP, C.LUI
                            end
                            3'b100: begin
                                case (sub_op_C_L3)
                                    2'b00: begin // C.SRLI
                                    end
                                    2'b01: begin // C.SRAI
                                    end
                                    2'b10: begin // C.ANDI
                                    end
                                    2'b11: begin
                                        case (sub_op_C_L4)
                                            2'b00: begin // C.SUB
                                            end
                                            2'b01: begin // C.XOR
                                            end
                                            2'b10: begin // C.OR
                                            end
                                            2'b11: begin // C.AND
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            3'b101: begin // C.J
                            end
                            3'b110: begin // C.BEQZ
                            end
                            3'b111: begin // C.BNEZ
                            end
                        endcase
                    end
                    2'b10: begin
                        case (sub_op_C_L1)
                            3'b000: begin // C.SLLI
                            end
                            3'b010: begin // C.LWSP
                            end
                            3'b100: begin
                                case (sub_op_C_L2)
                                    1'b0: begin // C.JR, C.MV
                                    end
                                    1'b1: begin // C.JALR, C.ADD
                                    end
                                endcase
                            end
                            3'b110: begin // C.SWSP
                            end
                        endcase
                    end
                    2'b11: begin
                    case (op)
                    5'b01101, 5'b00101, 5'b11011: begin // lui, auipc, jal
                        if (rob_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2rf_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2rf_ready <= 1;
                            rob_type_out <= ROB_TYPE_REG;
                            dest_out <= rd;
                            instr_addr_out <= if_instr_addr;
                            rob_state_out <= ROB_STATE_WRITE_RESULT;
                            rob_id_out <= rob_next_rob_id;
                            case (op)
                            5'b01101: begin // lui
                                result_value_out <= imm_32_U;
                                is_jump_out <= if_is_jump;
                            end
                            5'b00101: begin // auipc
                                result_value_out <= imm_32_U;
                                is_jump_out <= if_is_jump + if_instr_addr;
                            end
                            5'b11011: begin // jal
                                result_value_out <= if_instr_addr + 4;
                                is_jump_out <= 1;
                                jump_addr_out <= if_jump_addr;
                            end
                            endcase
                        end
                        dec2rs_ready <= 0;
                        dec2lsb_ready <= 0;
                    end
                    5'b11001: begin // jalr
                        if (rob_full || rs_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2rf_ready <= 0;
                            dec2rs_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2rf_ready <= 1;
                            dec2rs_ready <= 1;
                            rob_type_out <= ROB_TYPE_JALR;
                            dest_out <= rd;
                            instr_addr_out <= if_instr_addr;
                            jump_addr_out <= if_jump_addr;
                            rob_state_out <= ROB_STATE_EXECUTE;
                            is_jump_out <= 1;
                            rob_id_out <= rob_next_rob_id;
                            calc_op_L1_out <= 4'b0000;
                            calc_op_L2_out <= 0; // ADD
                            dependency1_out <= dependency1;
                            dependency2_out <= -1;
                            value1_out <= value1;
                            value2_out <= imm_21_J;
                        end
                        dec2lsb_ready <= 0;
                    end
                    5'b11000: begin // B-type
                        if (rob_full || rs_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2rs_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2rs_ready <= 1;
                            rob_type_out <= ROB_TYPE_BRANCH;
                            instr_addr_out <= if_instr_addr;
                            jump_addr_out <= if_jump_addr;
                            rob_state_out <= ROB_STATE_EXECUTE;
                            is_jump_out <= if_is_jump;
                            rob_id_out <= rob_next_rob_id;
                            case (sub_op)
                                3'b100: calc_op_L1_out <= 4'b0010; // BLT
                                3'b110: calc_op_L1_out <= 4'b0011; // BLTU
                                default: calc_op_L1_out <= {1'b1, sub_op}; // others
                            endcase
                            calc_op_L2_out <= calc_op_L2;
                            dependency1_out <= dependency1;
                            dependency2_out <= dependency2;
                            value1_out <= value1;
                            value2_out <= value2;
                        end
                        dec2lsb_ready <= 0;
                        dec2rf_ready <= 0;
                    end
                    5'b00000: begin // L-type
                        if (rob_full || lb_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2rf_ready <= 0;
                            dec2lsb_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2rf_ready <= 1;
                            dec2lsb_ready <= 1;
                            rob_type_out <= ROB_TYPE_REG;
                            dest_out <= rd;
                            instr_addr_out <= if_instr_addr;
                            rob_state_out <= ROB_STATE_EXECUTE;
                            is_jump_out <= 0;
                            rob_id_out <= rob_next_rob_id;
                            mem_type_out <= {1'b0, sub_op};
                            age_out <= if_age;
                            dependency1_out <= dependency1;
                            dependency2_out <= -1;
                            value1_out <= value1;
                            value2_out <= 0;
                        end
                        dec2rs_ready <= 0;
                    end
                    5'b01000: begin // S-type
                        if (rob_full || sb_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2lsb_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2lsb_ready <= 1;
                            rob_type_out <= sub_op;
                            instr_addr_out <= if_instr_addr;
                            rob_state_out <= ROB_STATE_EXECUTE;
                            is_jump_out <= 0;
                            mem_type_out <= {1'b1, sub_op};
                            rob_id_out <= rob_next_rob_id;
                            age_out <= if_age;
                            dependency1_out <= dependency1;
                            dependency2_out <= dependency2;
                            value1_out <= value1;
                            value2_out <= value2;
                            imm_out <= imm_12_S;
                        end
                        dec2rf_ready <= 0;
                        dec2rs_ready <= 0;
                    end
                    5'b00100: begin // I-type
                        if (rob_full || rs_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2rf_ready <= 0;
                            dec2rs_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2rf_ready <= 1;
                            dec2rs_ready <= 1;
                            rob_type_out <= ROB_TYPE_REG;
                            dest_out <= rd;
                            instr_addr_out <= if_instr_addr;
                            rob_state_out <= ROB_STATE_EXECUTE;
                            is_jump_out <= 0;
                            rob_id_out <= rob_next_rob_id;
                            calc_op_L1_out <= {1'b0, sub_op};
                            calc_op_L2_out <= (sub_op == 3'b101 ? calc_op_L2 : 1'b0); // I-type doesn't have SUBI
                            dependency1_out <= dependency1;
                            dependency2_out <= -1;
                            value1_out <= value1;
                            value2_out <= imm_5_shamt;
                        end
                        dec2lsb_ready <= 0;
                    end
                    5'b01100: begin // R-type
                        if (rob_full || rs_full) begin
                            is_stall_out <= 1;
                            dec2rob_ready <= 0;
                            dec2rf_ready <= 0;
                            dec2rs_ready <= 0;
                        end else begin
                            is_stall_out <= 0;
                            dec2rob_ready <= 1;
                            dec2rf_ready <= 1;
                            dec2rs_ready <= 1;
                            rob_type_out <= ROB_TYPE_REG;
                            dest_out <= rd;
                            instr_addr_out <= if_instr_addr;
                            rob_state_out <= ROB_STATE_EXECUTE;
                            is_jump_out <= 0;
                            rob_id_out <= rob_next_rob_id;
                            calc_op_L1_out <= {1'b0, sub_op};
                            calc_op_L2_out <= calc_op_L2;
                            dependency1_out <= dependency1;
                            dependency2_out <= dependency2;
                            value1_out <= value1;
                            value2_out <= value2;
                        end
                        dec2lsb_ready <= 0;
                    end
                    endcase
                    end
                endcase
            end else begin
                dec2rob_ready <= 0;
                dec2rs_ready <= 0;
                dec2lsb_ready <= 0;
                dec2rf_ready <= 0;
                is_stall_out <= 0;
            end
        end
    end

endmodule