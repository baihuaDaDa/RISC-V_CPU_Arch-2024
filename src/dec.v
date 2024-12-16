`include "src/const_param.v"

module dec (
    input clk_in,
    input rst_in,
    input rdy_in,

    input        if_valid,
    input [31:0] if_instr,
    input [31:0] if_instr_addr,
    input        if_is_jump,
    input [31:0] if_jump_addr,

    input need_flush_in,

    output reg is_stall_out,

    output reg dec2rob_ready,
    output reg dec2rs_ready,
    output reg dec2lsb_ready,
    output reg dec2rf_ready,

    output reg [  `ROB_TYPE_NUM_WIDTH-1:0] rob_type_out,
    output reg [       `REG_NUM_WIDTH-1:0] dest_out,          // for rob, rf
    output reg [                     31:0] result_value_out,
    output reg [                     31:0] instr_addr_out,
    output reg [                     31:0] jump_addr_out,
    output reg [ `ROB_STATE_NUM_WIDTH-1:0] rob_state_out,
    output reg                             is_jump_out,
    output reg [`CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_out,    // for rs
    output reg                             calc_op_L2_out,    // for rs
    output reg [      `ROB_SIZE_WIDTH-1:0] dependency1_out,
    output reg [      `ROB_SIZE_WIDTH-1:0] dependency2_out,
    output reg [                     31:0] value1_out,
    output reg [                     31:0] value2_out,
    output reg [                     31:0] imm_out,           // for lsb (store)
    output reg [      `ROB_SIZE_WIDTH-1:0] rob_id_out,        // also for rf as dependency
    output reg [  `MEM_TYPE_NUM_WIDTH-1:0] mem_type_out,      // for lsb

    // combinatorial logic
    input [`ROB_SIZE_WIDTH-1:0] rob_next_rob_id,

    input [`ROB_SIZE_WIDTH-1:0] rf_dependency1,
    input [`ROB_SIZE_WIDTH-1:0] rf_dependency2,
    input [               31:0] rf_value1,
    input [               31:0] rf_value2,
    input                       rob_is_found_1,
    input [               31:0] rob_value1,
    input                       rob_is_found_2,
    input [               31:0] rob_value2,

    input rob_full,
    input rs_full,
    input lb_full,
    input sb_full,

    output wire [`REG_NUM_WIDTH-1:0] rs1_out,
    output wire [`REG_NUM_WIDTH-1:0] rs2_out
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

    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_ADD_SUB = 4'b0000;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SLL = 4'b0001;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SLT = 4'b0010;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SLTU = 4'b0011;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_XOR = 4'b0100;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SRL_SRA = 4'b0101;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_OR = 4'b0110;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_AND = 4'b0111;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SEQ = 4'b1000;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SNE = 4'b1001;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SGE = 4'b1101;
    localparam [`CALC_OP_L1_NUM_WIDTH-1:0] CALC_SGEU = 4'b1111;

    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_LB = 4'b0000;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_LH = 4'b0001;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_LW = 4'b0010;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_LBU = 4'b0100;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_LHU = 4'b0101;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_SB = 4'b1000;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_SH = 4'b1001;
    localparam [`MEM_TYPE_NUM_WIDTH-1:0] MEM_SW = 4'b1010;

    localparam [4:0] OP_LUI = 5'b01101;
    localparam [4:0] OP_AUIPC = 5'b00101;
    localparam [4:0] OP_JAL = 5'b11011;
    localparam [4:0] OP_JALR = 5'b11001;
    localparam [4:0] OP_BRANCH = 5'b11000;
    localparam [4:0] OP_LOAD = 5'b00000;
    localparam [4:0] OP_STORE = 5'b01000;
    localparam [4:0] OP_IMM = 5'b00100;
    localparam [4:0] OP_REG = 5'b01100;

    wire [4:0] op = if_instr[6:2];
    wire [1:0] is_C = if_instr[1:0];
    wire [2:0] sub_op = if_instr[14:12];  // branch, load, store, calc_L1
    wire calc_op_L2 = if_instr[30];
    wire [`REG_NUM_WIDTH-1:0] rd = if_instr[11:7];
    wire [`REG_NUM_WIDTH-1:0] rs1 = if_instr[19:15];
    wire [`REG_NUM_WIDTH-1:0] rs2 = if_instr[24:20];
    wire [31:0] imm_32_U = if_instr[31:12] << 12;  // upper
    wire [31:0] imm_21_J = {
        {12{if_instr[31]}}, if_instr[19:12], if_instr[20], if_instr[30:21], 1'b0
    };
    wire [31:0] imm_12_I = {{20{if_instr[31]}}, if_instr[31:20]};  // except SRAI, SRLI, SLLI
    wire [31:0] imm_5_shamt = if_instr[24:20];  // unsigned
    wire [31:0] imm_13_B = {{20{if_instr[31]}}, if_instr[7], if_instr[30:25], if_instr[11:8], 1'b0};
    wire [31:0] imm_12_S = {{20{if_instr[31]}}, if_instr[31:25], if_instr[11:7]};
    wire [2:0] op_C = if_instr[15:13];
    wire [2:0] sub_op_C_L1 = if_instr[15:13];
    wire sub_op_C_L2 = if_instr[12];
    wire [1:0] sub_op_C_L3 = if_instr[11:10];
    wire [1:0] sub_op_C_L4 = if_instr[6:5];
    wire [`REG_NUM_WIDTH-1:0] rs1_C_3 = if_instr[9:7];  // rs1/rd 3-bit
    wire [`REG_NUM_WIDTH-1:0] rs2_C_3 = if_instr[4:2];  // rs2/rd 3-bit
    wire [`REG_NUM_WIDTH-1:0] rs1_C_5 = if_instr[11:7];  // rs1/rd 5-bit
    wire [`REG_NUM_WIDTH-1:0] rs2_C_5 = if_instr[6:2];  // rs2/rd 5-bit
    wire [31:0] imm_C_LSW = {
        if_instr[5], if_instr[12:10], if_instr[6], 2'b00
    };  // uimm[5:3], uimm[2|6], for C.LW, C.SW
    wire [31:0] imm_C_ADDI4SPN = {
        if_instr[10:7], if_instr[12:11], if_instr[5], if_instr[6], 2'b00
    };  // uimm[5:4|9:6|2|3], for C.ADDI4SPN
    wire [31:0] imm_C_I = {{27{if_instr[12]}}, if_instr[6:2]};  // for I-type imm
    wire [31:0] imm_C_UI = {if_instr[12], if_instr[6:2]};  // for unsigned I-type imm
    wire [31:0] imm_C_J = {
        {21{if_instr[12]}},
        if_instr[8],
        if_instr[10:9],
        if_instr[6],
        if_instr[7],
        if_instr[2],
        if_instr[11],
        if_instr[5:3],
        1'b0
    };  // imm[11|4|9:8|10|6|7|3:1|5], for C.JAL and C.J (J-type)
    wire [31:0] imm_C_ADDI16SP = {
        {23{if_instr[12]}}, if_instr[4:3], if_instr[5], if_instr[2], if_instr[6], 4'b0000
    };  // imm[9], imm[4|6|8:7|5], for C.ADDI16SP
    wire [31:0] imm_C_LUI = {
        {15{if_instr[12]}}, if_instr[6:2], 12'b0000_0000_0000
    };  // imm[17], imm[16:12], for C.LUI
    wire [31:0] imm_C_B = {
        {24{if_instr[12]}}, if_instr[6:5], if_instr[2], if_instr[11:10], if_instr[4:3], 1'b0
    };  // imm[8|4:3], imm[7:6|2:1|5], for C.BEQZ, C.BNEZ (B-type)
    wire [31:0] imm_C_LWSP = {
        if_instr[3:2], if_instr[12], if_instr[6:4], 2'b00
    };  // uimm[5], uimm[4:2|7:6]
    wire [31:0] imm_C_SWSP = {if_instr[8:7], if_instr[12:9], 2'b00};  // uimm[5:2|7:6]

    // decode rs1, rs2
    assign rs1_out = (is_C == 2'b11) ? rs1 :
                     ((is_C == 2'b00 && sub_op_C_L1 == 3'b000) || (is_C == 2'b01 && (sub_op_C_L1 == 3'b11 && rs1_C_5 == 2)) || (is_C == 2'b10 && sub_op_C_L1 == 3'b010)) ? 2 :
                     ((is_C == 2'b00 && sub_op_C_L1 != 3'b010) || (is_C == 2'b01 && (sub_op_C_L1 == 3'b100 || sub_op_C_L1 == 3'b110 || sub_op_C_L1 == 3'b111))) ? rs1_C_3 :
                     ((is_C == 2'b01 && sub_op_C_L1 == 3'b000) || (is_C == 2'b10 && (sub_op_C_L1 == 3'b000 || (sub_op_C_L1 == 3'b100 && (sub_op_C_L2 != 0 || rs2_C_5 == 0))))) ? rs1_C_5 :
                     (is_C == 2'b10 && sub_op_C_L1 == 3'b100 && sub_op_C_L2 == 0 && rs2_C_5 != 0) ? rs2_C_5 : 0;
    assign rs2_out = (is_C == 2'b11) ? rs2 :
                     ((is_C == 2'b00 && sub_op_C_L1 == 3'b110) || (is_C == 2'b01 && (sub_op_C_L1 == 3'b100 && sub_op_C_L3 == 2'b11))) ? rs2_C_3 :
                     (is_C == 2'b10 && ((sub_op_C_L1 == 3'b100 && sub_op_C_L1 == 1 && rs2_C_5 != 0) || sub_op_C_L1 == 3'b110)) ? rs2_C_5 : 0;

    wire [`ROB_SIZE_WIDTH-1:0] dependency1;
    wire [`ROB_SIZE_WIDTH-1:0] dependency2;
    wire [               31:0] value1;
    wire [               31:0] value2;

    assign dependency1 = (&rf_dependency1) ? -1 : (rob_is_found_1 ? -1 : rf_dependency1);
    assign dependency2 = (&rf_dependency2) ? -1 : (rob_is_found_2 ? -1 : rf_dependency2);
    assign value1 = (&rf_dependency1) ? rf_value1 : (rob_is_found_1 ? rob_value1 : 0);
    assign value2 = (&rf_dependency2) ? rf_value2 : (rob_is_found_2 ? rob_value2 : 0);

    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            dec2rob_ready <= 0;
            dec2rs_ready  <= 0;
            dec2lsb_ready <= 0;
            dec2rf_ready  <= 0;
            is_stall_out  <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (!need_flush_in && if_valid) begin
                case (is_C)
                    2'b00: begin
                        case (sub_op_C_L1)
                            3'b000:
                            I_type(rs2_C_3, CALC_ADD_SUB, 0, imm_C_ADDI4SPN);  // C.ADDI4SPN
                            3'b010: load_type(rs2_C_3, MEM_LW, imm_C_LSW);  // C.LW
                            3'b110: S_type(MEM_SW, imm_C_LSW);  // C.SW
                        endcase
                    end
                    2'b01: begin
                        case (sub_op_C_L1)
                            3'b000: I_type(rs1_C_5, CALC_ADD_SUB, 0, imm_C_I);  // C.ADDI
                            3'b001: U_J_type(1, OP_JAL, imm_C_J);  // C.JAL
                            3'b010: I_type(rs1_C_5, CALC_ADD_SUB, 0, imm_C_I);  // C.LI
                            3'b011: begin
                                if (rs1_C_5 == 2)
                                    I_type(2, CALC_ADD_SUB, 0, imm_C_ADDI16SP);  // C.ADDI16SP
                                else U_J_type(rs1_C_5, OP_LUI, imm_C_LUI);  // C.LUI
                            end
                            3'b100: begin
                                case (sub_op_C_L3)
                                    2'b00: I_type(rs1_C_3, CALC_SRL_SRA, 0, imm_C_UI);  // C.SRLI
                                    2'b01: I_type(rs1_C_3, CALC_SRL_SRA, 1, imm_C_UI);  // C.SRAI
                                    2'b10: I_type(rs1_C_3, CALC_AND, 0, imm_C_I);  // C.ANDI
                                    2'b11: begin
                                        case (sub_op_C_L4)
                                            2'b00: R_type(rs1_C_3, CALC_ADD_SUB, 1);  // C.SUB
                                            2'b01: R_type(rs1_C_3, CALC_XOR, 0);  // C.XOR
                                            2'b10: R_type(rs1_C_3, CALC_OR, 0);  // C.OR
                                            2'b11: R_type(rs1_C_3, CALC_AND, 0);  // C.AND
                                        endcase
                                    end
                                endcase
                            end
                            3'b101: U_J_type(0, OP_JAL, imm_C_J);  // C.J
                            3'b110: B_type(CALC_SEQ, 0);  // C.BEQZ
                            3'b111: B_type(CALC_SNE, 0);  // C.BNEZ
                        endcase
                    end
                    2'b10: begin
                        case (sub_op_C_L1)
                            3'b000: I_type(rs1_C_5, CALC_SLL, 0, imm_C_UI);  // C.SLLI
                            3'b010: load_type(rs1_C_5, MEM_LW, imm_C_LWSP);  // C.LWSP
                            3'b100: begin
                                case (sub_op_C_L2)
                                    1'b0: begin
                                        if (rs2_C_5 == 0) jalr_type(0, 0);  // C.JR
                                        else I_type(rs1_C_5, CALC_ADD_SUB, 0, 0);  // C.MV
                                    end
                                    1'b1: begin
                                        if (rs2_C_5 == 0) jalr_type(1, 0);  // C.JALR
                                        else R_type(rs1_C_5, CALC_ADD_SUB, 0);  // C.ADD
                                    end
                                endcase
                            end
                            3'b110: S_type(MEM_SW, imm_C_SWSP);  // C.SWSP
                        endcase
                    end
                    2'b11: begin
                        case (op)
                            OP_LUI, OP_AUIPC, OP_JAL: U_J_type(rd, op, imm_32_U);
                            OP_JALR: jalr_type(rd, imm_12_I);
                            OP_BRANCH:
                            B_type(
                                sub_op == 3'b100 ? CALC_SLT : sub_op == 3'b110 ? CALC_SLTU : {1'b1, sub_op},
                                0);  // SLT and SLTU already exist
                            OP_LOAD: load_type(rd, {1'b0, sub_op}, imm_12_I);
                            OP_STORE: S_type({1'b1, sub_op}, imm_12_S);
                            OP_IMM:
                            I_type(rd, {1'b0, sub_op}, (sub_op == 3'b101 ? calc_op_L2 : 1'b0),
                                   (sub_op == 3'b101 || sub_op == 3'b001 ? imm_5_shamt : imm_12_I));  // I-type doesn't have SUBI
                            OP_REG: R_type(rd, {1'b0, sub_op}, calc_op_L2);
                        endcase
                    end
                endcase
            end else begin
                dec2rob_ready <= 0;
                dec2rs_ready  <= 0;
                dec2lsb_ready <= 0;
                dec2rf_ready  <= 0;
                is_stall_out  <= 0;
            end
        end
    end

    task U_J_type;
        input [`REG_NUM_WIDTH-1:0] rd_U_J;
        input [4:0] op_U_J;
        input [31:0] imm_U_J;
        begin
            if (rob_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2rf_ready  <= 0;
            end else begin
                is_stall_out <= 0;
                dec2rob_ready <= 1;
                dec2rf_ready <= 1;
                rob_type_out <= ROB_TYPE_REG;
                dest_out <= rd_U_J;
                instr_addr_out <= if_instr_addr;
                rob_state_out <= ROB_STATE_WRITE_RESULT;
                rob_id_out <= rob_next_rob_id;
                case (op_U_J)
                    OP_LUI: begin
                        result_value_out <= imm_U_J;
                        is_jump_out <= if_is_jump;
                    end
                    OP_AUIPC: begin
                        result_value_out <= imm_U_J;
                        is_jump_out <= if_is_jump + if_instr_addr;
                    end
                    OP_JAL: begin
                        result_value_out <= if_instr_addr + 4;
                        is_jump_out <= 1;
                        jump_addr_out <= if_jump_addr;
                    end
                endcase
            end
            dec2rs_ready  <= 0;
            dec2lsb_ready <= 0;
        end
    endtask

    task jalr_type;
        input [`REG_NUM_WIDTH-1:0] rd_JALR;
        input [31:0] imm_JALR;
        begin
            if (rob_full || rs_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2rf_ready  <= 0;
                dec2rs_ready  <= 0;
            end else begin
                is_stall_out <= 0;
                dec2rob_ready <= 1;
                dec2rf_ready <= 1;
                dec2rs_ready <= 1;
                rob_type_out <= ROB_TYPE_JALR;
                dest_out <= rd_JALR;
                instr_addr_out <= if_instr_addr;
                jump_addr_out <= if_jump_addr;
                rob_state_out <= ROB_STATE_EXECUTE;
                is_jump_out <= 1;
                rob_id_out <= rob_next_rob_id;
                calc_op_L1_out <= CALC_ADD_SUB;
                calc_op_L2_out <= 0;  // ADD
                dependency1_out <= dependency1;
                dependency2_out <= -1;
                value1_out <= value1;
                value2_out <= imm_JALR;
            end
            dec2lsb_ready <= 0;
        end
    endtask

    task B_type;
        input [`CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_B;
        input calc_op_L2_B;
        begin
            if (rob_full || rs_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2rs_ready  <= 0;
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
                calc_op_L1_out <= calc_op_L1_B;
                calc_op_L2_out <= calc_op_L2_B;
                dependency1_out <= dependency1;
                dependency2_out <= dependency2;
                value1_out <= value1;
                value2_out <= value2;
            end
            dec2lsb_ready <= 0;
            dec2rf_ready  <= 0;
        end
    endtask

    task load_type;
        input [`REG_NUM_WIDTH-1:0] rd_L;
        input [`MEM_TYPE_NUM_WIDTH-1:0] mem_type_L;
        input [31:0] imm_L;
        begin
            if (rob_full || lb_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2rf_ready  <= 0;
                dec2lsb_ready <= 0;
            end else begin
                is_stall_out <= 0;
                dec2rob_ready <= 1;
                dec2rf_ready <= 1;
                dec2lsb_ready <= 1;
                rob_type_out <= ROB_TYPE_REG;
                dest_out <= rd_L;
                instr_addr_out <= if_instr_addr;
                rob_state_out <= ROB_STATE_EXECUTE;
                is_jump_out <= 0;
                rob_id_out <= rob_next_rob_id;
                mem_type_out <= mem_type_L;
                dependency1_out <= dependency1;
                dependency2_out <= -1;
                value1_out <= value1;
                value2_out <= imm_L;
            end
            dec2rs_ready <= 0;
        end
    endtask

    task S_type;
        input [`MEM_TYPE_NUM_WIDTH-1:0] mem_type_S;
        input [31:0] imm_S;
        begin
            if (rob_full || sb_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2lsb_ready <= 0;
            end else begin
                is_stall_out <= 0;
                dec2rob_ready <= 1;
                dec2lsb_ready <= 1;
                rob_type_out <= mem_type_S[`ROB_TYPE_NUM_WIDTH-1:0];
                instr_addr_out <= if_instr_addr;
                rob_state_out <= ROB_STATE_EXECUTE;
                is_jump_out <= 0;
                mem_type_out <= mem_type_S;
                rob_id_out <= rob_next_rob_id;
                dependency1_out <= dependency1;
                dependency2_out <= dependency2;
                value1_out <= value1;
                value2_out <= value2;
                imm_out <= imm_S;
            end
            dec2rf_ready <= 0;
            dec2rs_ready <= 0;
        end
    endtask

    task I_type;
        input [`REG_NUM_WIDTH-1:0] rd_I;
        input [`CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_I;
        input calc_op_L2_I;
        input [31:0] imm_I;
        begin
            if (rob_full || rs_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2rf_ready  <= 0;
                dec2rs_ready  <= 0;
            end else begin
                is_stall_out <= 0;
                dec2rob_ready <= 1;
                dec2rf_ready <= 1;
                dec2rs_ready <= 1;
                rob_type_out <= ROB_TYPE_REG;
                dest_out <= rd_I;
                instr_addr_out <= if_instr_addr;
                rob_state_out <= ROB_STATE_EXECUTE;
                is_jump_out <= 0;
                rob_id_out <= rob_next_rob_id;
                calc_op_L1_out <= calc_op_L1_I;
                calc_op_L2_out <= calc_op_L2_I;
                dependency1_out <= dependency1;
                dependency2_out <= -1;
                value1_out <= value1;
                value2_out <= imm_I;
            end
            dec2lsb_ready <= 0;
        end
    endtask

    task R_type;
        input [`REG_NUM_WIDTH-1:0] rd_R;
        input [`CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_R;
        input calc_op_L2_R;
        begin
            if (rob_full || rs_full) begin
                is_stall_out  <= 1;
                dec2rob_ready <= 0;
                dec2rf_ready  <= 0;
                dec2rs_ready  <= 0;
            end else begin
                is_stall_out <= 0;
                dec2rob_ready <= 1;
                dec2rf_ready <= 1;
                dec2rs_ready <= 1;
                rob_type_out <= ROB_TYPE_REG;
                dest_out <= rd_R;
                instr_addr_out <= if_instr_addr;
                rob_state_out <= ROB_STATE_EXECUTE;
                is_jump_out <= 0;
                rob_id_out <= rob_next_rob_id;
                calc_op_L1_out <= calc_op_L1_R;
                calc_op_L2_out <= calc_op_L2_R;
                dependency1_out <= dependency1;
                dependency2_out <= dependency2;
                value1_out <= value1;
                value2_out <= value2;
            end
            dec2lsb_ready <= 0;
        end
    endtask

endmodule
