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

    output reg [  `ROB_TYPE_NUM_WIDTH-1:0] rob_type_out,
    output reg [       `REG_NUM_WIDTH-1:0] rs1_out,
    output reg [       `REG_NUM_WIDTH-1:0] rs2_out,
    output reg [       `REG_NUM_WIDTH-1:0] dest_out,          // for rob, rf
    output reg [                     31:0] result_value_out,
    output reg [                     31:0] instr_addr_out,
    output reg [                     31:0] jump_addr_out,
    output reg [ `ROB_STATE_NUM_WIDTH-1:0] rob_state_out,
    output reg                             is_jump_out,
    output reg [`CALC_OP_L1_NUM_WIDTH-1:0] calc_op_L1_out,    // for rs
    output reg                             calc_op_L2_out,    // for rs
    output reg                             is_imm_out,        // for jalr, I-type
    output reg [                     31:0] imm_out,           // for load, store, jalr, I-type
    output reg [      `ROB_SIZE_WIDTH-1:0] rob_id_out,        // also for rf as dependency
    output reg [  `MEM_TYPE_NUM_WIDTH-1:0] mem_type_out,      // for lsb

    // combinatorial logic
    output wire [                3:0] dec_ready,       // [rf|lsb|rs|rob], 1 for ready
    input       [`ROB_SIZE_WIDTH-1:0] rob_next_rob_id,

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

    // assign rs1_out = 0;
    // assign rs2_out = 0;

    reg [3:0] tmp_dec_ready;

    assign dec_ready = tmp_dec_ready & {4{is_stall_out}};

    always @(posedge clk_in) begin
        if (rst_in !== 1'b0) begin
            rob_type_out <= 0;
            dest_out <= 0;
            result_value_out <= 0;
            instr_addr_out <= 0;
            jump_addr_out <= 0;
            rob_state_out <= 0;
            is_jump_out <= 0;
            calc_op_L1_out <= 0;
            calc_op_L2_out <= 0;
            rs1_out <= 0;
            rs2_out <= 0;
            is_imm_out <= 0;
            imm_out <= 0;
            rob_id_out <= 0;
            mem_type_out <= 0;
            tmp_dec_ready <= 4'b0000;
            is_stall_out <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            if (is_stall_out) begin
                case (tmp_dec_ready)
                    4'b1001: is_stall_out <= rob_full;
                    4'b1011, 4'b0011: is_stall_out <= rob_full || rs_full;
                    4'b0101: is_stall_out <= rob_full || sb_full;
                    4'b1101: is_stall_out <= rob_full || lb_full;
                    default: begin
                        $display("dec error.");
                        $finish;
                    end
                endcase
            end else if (!need_flush_in && if_valid) begin
                instr_addr_out <= if_instr_addr;
                rob_id_out <= rob_next_rob_id;
                jump_addr_out <= if_jump_addr;
                is_jump_out <= if_is_jump;
                // categorize
                case (is_C)
                    2'b00: begin
                        case (sub_op_C_L1)
                            3'b000: begin  // OP_IMM
                                tmp_dec_ready <= 4'b1011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                dest_out <= rs2_C_3;
                                calc_op_L1_out <= CALC_ADD_SUB;
                                calc_op_L2_out <= 1'b0;
                                rs1_out <= 2;
                                rs2_out <= 0;
                                is_imm_out <= 1;
                                imm_out <= imm_C_ADDI4SPN;
                            end  // C.ADDI4SPN
                            3'b010: begin  // OP_LOAD
                                tmp_dec_ready <= 4'b1101;
                                is_stall_out <= rob_full || lb_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                dest_out <= rs2_C_3;
                                mem_type_out <= MEM_LW;
                                rs1_out <= rs1_C_3;
                                rs2_out <= 0;
                                is_imm_out <= 0;
                                imm_out <= imm_C_LSW;
                            end  // C.LW
                            3'b110: begin  // OP_STORE
                                tmp_dec_ready <= 4'b0101;
                                is_stall_out <= rob_full || sb_full;
                                rob_type_out <= sub_op;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                mem_type_out <= MEM_SW;
                                rs1_out <= rs1_C_3;
                                rs2_out <= rs2_C_3;
                                is_imm_out <= 0;
                                imm_out <= imm_C_LSW;
                            end  // C.SW
                        endcase
                    end
                    2'b01: begin
                        case (sub_op_C_L1)
                            3'b000, 3'b010: begin  // OP_IMM
                                tmp_dec_ready <= 4'b1011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                dest_out <= rs1_C_5;
                                calc_op_L1_out <= CALC_ADD_SUB;
                                calc_op_L2_out <= 1'b0;
                                rs1_out <= sub_op_C_L1 == 3'b000 ? rs1_C_5 : 0;  // C.LI rs1 = x0
                                rs2_out <= 0;
                                is_imm_out <= 1;
                                imm_out <= imm_C_I;
                            end  // C.ADDI, C.LI
                            3'b001: begin  // OP_JAL
                                tmp_dec_ready <= 4'b1001;
                                is_stall_out <= rob_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_WRITE_RESULT;
                                dest_out <= 1;
                                result_value_out <= if_instr_addr + 4;  // TODO: +4?
                                is_imm_out <= 0;
                            end  // C.JAL
                            3'b011: begin
                                if (rs1_C_5 == 2) begin  // OP_IMM
                                    tmp_dec_ready <= 4'b1011;
                                    is_stall_out <= rob_full || rs_full;
                                    rob_type_out <= ROB_TYPE_REG;
                                    rob_state_out <= ROB_STATE_EXECUTE;
                                    dest_out <= 2;
                                    calc_op_L1_out <= CALC_ADD_SUB;
                                    calc_op_L2_out <= 1'b0;
                                    rs1_out <= 2;
                                    rs2_out <= 0;
                                    is_imm_out <= 1;
                                    imm_out <= imm_C_ADDI16SP;
                                end  // C.ADDI16SP
                                else begin  // OP_LUI
                                    tmp_dec_ready <= 4'b1001;
                                    is_stall_out <= rob_full;
                                    rob_type_out <= ROB_TYPE_REG;
                                    rob_state_out <= ROB_STATE_WRITE_RESULT;
                                    dest_out <= rs1_C_5;
                                    result_value_out <= imm_C_LUI;
                                    is_imm_out <= 0;
                                end  // C.LUI
                            end
                            3'b100: begin
                                case (sub_op_C_L3)
                                    2'b11: begin  // OP_REG
                                        tmp_dec_ready <= 4'b1011;
                                        is_stall_out <= rob_full || rs_full;
                                        rob_type_out <= ROB_TYPE_REG;
                                        rob_state_out <= ROB_STATE_EXECUTE;
                                        dest_out <= rs1_C_3;
                                        case (sub_op_C_L4)
                                            2'b00: calc_op_L1_out <= CALC_ADD_SUB;  // C.SUB
                                            2'b01: calc_op_L1_out <= CALC_XOR;  // C.XOR
                                            2'b10: calc_op_L1_out <= CALC_OR;  // C.OR
                                            2'b11: calc_op_L1_out <= CALC_AND;  // C.AND
                                        endcase
                                        calc_op_L2_out <= sub_op_C_L4 == 2'b00 ? 1'b1 : 1'b0;  // C.SUB 1
                                        rs1_out <= rs1_C_3;
                                        rs2_out <= rs2_C_3;
                                        is_imm_out <= 0;
                                    end
                                    default: begin  // OP_IMM
                                        tmp_dec_ready <= 4'b1011;
                                        is_stall_out <= rob_full || rs_full;
                                        rob_type_out <= ROB_TYPE_REG;
                                        rob_state_out <= ROB_STATE_EXECUTE;
                                        dest_out <= rs1_C_3;
                                        calc_op_L1_out <= sub_op_C_L3 == 2'b10 ? CALC_AND : CALC_SRL_SRA;
                                        calc_op_L2_out <= sub_op_C_L3 == 2'b01 ? 1'b1 : 1'b0;  // C.SRAI 1
                                        rs1_out <= rs1_C_3;
                                        rs2_out <= 0;
                                        is_imm_out <= 1;
                                        imm_out <= sub_op_C_L3 == 2'b10 ? imm_C_I : imm_C_UI;  // C.ANDI signed
                                    end  // C.SRLI, C.SRAI, C.ANDI
                                endcase
                            end
                            3'b101: begin  // OP_JAL
                                tmp_dec_ready <= 4'b1001;
                                is_stall_out <= rob_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_WRITE_RESULT;
                                dest_out <= 0;
                                result_value_out <= if_instr_addr + 4;  // TODO: +4?
                                is_imm_out <= 0;
                            end  // C.J
                            3'b110: begin  // OP_BRANCH
                                tmp_dec_ready <= 4'b0011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_BRANCH;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                calc_op_L1_out <= CALC_SEQ;
                                calc_op_L2_out <= 0;
                                rs1_out <= rs1_C_3;
                                rs2_out <= 0;
                                is_imm_out <= 0;
                            end  // C.BEQZ
                            3'b111: begin  // OP_BRANCH
                                tmp_dec_ready <= 4'b0011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_BRANCH;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                calc_op_L1_out <= CALC_SNE;
                                calc_op_L2_out <= 0;
                                rs1_out <= rs1_C_3;
                                rs2_out <= 0;
                                is_imm_out <= 0;
                            end  // C.BNEZ
                        endcase
                    end
                    2'b10: begin
                        case (sub_op_C_L1)
                            3'b000: begin  // OP_IMM
                                tmp_dec_ready <= 4'b1011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                dest_out <= rs1_C_5;
                                calc_op_L1_out <= CALC_SLL;
                                calc_op_L2_out <= 1'b0;
                                rs1_out <= rs1_C_5;
                                rs2_out <= 0;
                                is_imm_out <= 1;
                                imm_out <= imm_C_UI;
                            end  // C.SLLI
                            3'b010: begin  // OP_LOAD
                                tmp_dec_ready <= 4'b1101;
                                is_stall_out <= rob_full || lb_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                dest_out <= rs1_C_5;
                                mem_type_out <= MEM_LW;
                                rs1_out <= 2;
                                rs2_out <= 0;
                                is_imm_out <= 0;
                                imm_out <= imm_C_LWSP;
                            end  // C.LWSP
                            3'b100: begin
                                case (sub_op_C_L2)
                                    1'b0: begin
                                        if (rs2_C_5 == 0) begin  // OP_JALR
                                            tmp_dec_ready <= 4'b1011;
                                            is_stall_out <= rob_full || rs_full;
                                            rob_type_out <= ROB_TYPE_JALR;
                                            rob_state_out <= ROB_STATE_EXECUTE;
                                            dest_out <= 0;
                                            calc_op_L1_out <= CALC_ADD_SUB;
                                            calc_op_L2_out <= 0;  // ADD
                                            rs1_out <= rs1_C_5;
                                            rs2_out <= 0;
                                            is_imm_out <= 1;
                                            imm_out <= 0;
                                        end  // C.JR
                                        else begin  // OP_IMM
                                            tmp_dec_ready <= 4'b1011;
                                            is_stall_out <= rob_full || rs_full;
                                            rob_type_out <= ROB_TYPE_REG;
                                            rob_state_out <= ROB_STATE_EXECUTE;
                                            dest_out <= rs1_C_5;
                                            calc_op_L1_out <= CALC_ADD_SUB;
                                            calc_op_L2_out <= 1'b0;
                                            rs1_out <= rs2_C_5;
                                            rs2_out <= 0;
                                            is_imm_out <= 1;
                                            imm_out <= 0;
                                        end  // C.MV
                                    end
                                    1'b1: begin
                                        if (rs2_C_5 == 0) begin  // OP_JALR
                                            tmp_dec_ready <= 4'b1011;
                                            is_stall_out <= rob_full || rs_full;
                                            rob_type_out <= ROB_TYPE_JALR;
                                            rob_state_out <= ROB_STATE_EXECUTE;
                                            dest_out <= 1;
                                            calc_op_L1_out <= CALC_ADD_SUB;
                                            calc_op_L2_out <= 0;  // ADD
                                            rs1_out <= rs1_C_5;
                                            rs2_out <= 0;
                                            is_imm_out <= 1;
                                            imm_out <= 0;
                                        end  // C.JALR
                                        else begin  // OP_REG
                                            tmp_dec_ready <= 4'b1011;
                                            is_stall_out <= rob_full || rs_full;
                                            rob_type_out <= ROB_TYPE_REG;
                                            rob_state_out <= ROB_STATE_EXECUTE;
                                            dest_out <= rs1_C_5;
                                            calc_op_L1_out <= CALC_ADD_SUB;
                                            calc_op_L2_out <= 0;
                                            rs1_out <= rs1_C_5;
                                            rs2_out <= rs2_C_5;
                                            is_imm_out <= 0;
                                        end  // C.ADD
                                    end
                                endcase
                            end
                            3'b110: begin  // OP_STORE
                                tmp_dec_ready <= 4'b0101;
                                is_stall_out <= rob_full || sb_full;
                                rob_type_out <= sub_op;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                mem_type_out <= MEM_SW;
                                rs1_out <= 2;
                                rs2_out <= rs2_C_5;
                                is_imm_out <= 0;
                                imm_out <= imm_C_SWSP;
                            end  // C.SWSP
                        endcase
                    end
                    2'b11: begin
                        dest_out <= rd;
                        rs1_out <= rs1;
                        rs2_out <= rs2;
                        is_imm_out <= op == OP_JALR || op == OP_IMM;
                        case (op)
                            OP_LUI, OP_AUIPC, OP_JAL: begin
                                tmp_dec_ready <= 4'b1001;
                                is_stall_out  <= rob_full;
                                rob_type_out  <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_WRITE_RESULT;
                                case (op)
                                    OP_LUI:   result_value_out <= imm_32_U;
                                    OP_AUIPC: result_value_out <= imm_32_U + if_instr_addr;
                                    OP_JAL:   result_value_out <= if_instr_addr + 4;  // TODO: +4?
                                endcase
                            end
                            OP_JALR: begin
                                tmp_dec_ready <= 4'b1011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_JALR;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                calc_op_L1_out <= CALC_ADD_SUB;
                                calc_op_L2_out <= 0;  // ADD
                                imm_out <= imm_12_I;
                            end
                            OP_BRANCH: begin
                                tmp_dec_ready <= 4'b0011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_BRANCH;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                calc_op_L1_out <= sub_op == 3'b100 ? CALC_SLT : sub_op == 3'b110 ? CALC_SLTU : {1'b1, sub_op};
                                calc_op_L2_out <= 0;
                            end  // SLT and SLTU already exist
                            OP_LOAD: begin
                                tmp_dec_ready <= 4'b1101;
                                is_stall_out <= rob_full || lb_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                mem_type_out <= {1'b0, sub_op};
                                imm_out <= imm_12_I;
                            end
                            OP_STORE: begin
                                tmp_dec_ready <= 4'b0101;
                                is_stall_out <= rob_full || sb_full;
                                rob_type_out <= sub_op;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                mem_type_out <= {1'b1, sub_op};
                                imm_out <= imm_12_S;
                            end
                            OP_IMM: begin
                                tmp_dec_ready <= 4'b1011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                calc_op_L1_out <= {1'b0, sub_op};
                                calc_op_L2_out <= (sub_op == 3'b101 ? calc_op_L2 : 1'b0);
                                imm_out <= (sub_op == 3'b101 || sub_op == 3'b001 ? imm_5_shamt : imm_12_I);  // I-type doesn't have SUBI
                            end
                            OP_REG: begin
                                tmp_dec_ready <= 4'b1011;
                                is_stall_out <= rob_full || rs_full;
                                rob_type_out <= ROB_TYPE_REG;
                                rob_state_out <= ROB_STATE_EXECUTE;
                                calc_op_L1_out <= {1'b0, sub_op};
                                calc_op_L2_out <= calc_op_L2;
                            end
                        endcase
                    end
                endcase
            end else begin
                tmp_dec_ready <= 4'b0000;
                is_stall_out  <= 0;
            end
        end
    end

endmodule
