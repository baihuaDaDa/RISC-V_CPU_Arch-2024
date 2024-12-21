// RISCV32 CPU top module
// port modification allowed for debugging purposes

`include "src/const_param.v"
// `include "src/instr_fetcher.v"
// `include "src/predictor.v"
// `include "src/dec.v"
// `include "src/rob.v"
// `include "src/lsb.v"
// `include "src/rs.v"
// `include "src/alu.v"
// `include "src/icache.v"
// `include "src/mem_controller.v"
// `include "src/rf.v"

module cpu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire io_buffer_full,  // 1 if uart buffer is full

    output wire [31:0] dbgreg_dout  // cpu register output (debugging demo)
);

    // implementation goes here

    // Specifications:
    // - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
    // - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
    // - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
    // - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
    // - 0x30000 read: read a byte from input
    // - 0x30000 write: write a byte to output (write 0x00 is ignored)
    // - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
    // - 0x30004 write: indicates program stop (will output '\0' through uart tx)

    // TODO: io_buffer_full is not considered in simulation stage.

    // instr_fetcher
    wire                             if2dec_ready;
    wire [                     31:0] if2dec_instr;
    wire [                     31:0] if2dec_instr_addr;
    wire                             if2dec_is_jump;
    wire [                     31:0] if2dec_jump_addr;
    wire                             if2ic_fetch_enable;
    wire [                     31:0] if_pc;
    wire [       `REG_NUM_WIDTH-1:0] if2rf_rs_jalr;

    // predictor
    wire                             pred2if_result;

    // dec
    wire                             dec_is_stall;
    wire [                      3:0] dec_ready;
    wire                             dec_is_C;
    wire [  `ROB_TYPE_NUM_WIDTH-1:0] dec_rob_type;
    wire [       `REG_NUM_WIDTH-1:0] dec_dest;  // for rob, rf
    wire [       `REG_NUM_WIDTH-1:0] dec_rs1;
    wire [       `REG_NUM_WIDTH-1:0] dec_rs2;
    wire [                     31:0] dec_result_value;
    wire [                     31:0] dec_instr_addr;
    wire [                     31:0] dec_jump_addr;
    wire [ `ROB_STATE_NUM_WIDTH-1:0] dec_rob_state;
    wire                             dec_is_jump;
    wire [`CALC_OP_L1_NUM_WIDTH-1:0] dec_calc_op_L1;  // for rs
    wire                             dec_calc_op_L2;  // for rs
    wire                             dec_is_imm;
    wire [                     31:0] dec_imm;  // for lsb (store)
    wire [  `MEM_TYPE_NUM_WIDTH-1:0] dec_mem_type;  // for lsb

    // rob
    wire                             rob2rf_ready;
    wire                             rob2mem_ready;
    wire                             rob2lsb_pop_sb;
    wire                             rob2pred_ready;
    wire                             rob_need_flush;

    wire [       `REG_NUM_WIDTH-1:0] rob_rd;  // for rf
    wire [                     31:0] rob_value;  // for rf and mem
    wire [        `ROB_SIZE_WIDTH:0] rob_dependency;  // for rf
    wire [`STORE_TYPE_NUM_WIDTH-1:0] rob_store_type;  // for mem
    wire [                     31:0] rob_data_addr;  // for mem
    wire [                     31:0] rob_jump_addr;  // for if, valid only if need_flush_out is high
    wire [                     31:0] rob_instr_addr;  // for pred
    wire                             rob_is_jump;  // for pred
    wire                             rob_is_found_1;
    wire [                     31:0] rob_value1;
    wire                             rob_is_found_2;
    wire [                     31:0] rob_value2;
    wire                             rob_full;
    wire [      `ROB_SIZE_WIDTH-1:0] rob_rear_next;  // also for rf as dependency

    // lsb
    wire                             lb2mem_ready;
    wire [ `LOAD_TYPE_NUM_WIDTH-1:0] lb2mem_load_type;
    wire [                     31:0] lb2mem_addr;
    wire [        `ROB_SIZE_WIDTH:0] lb2mem_dependency;
    wire                             sb2rob_ready;
    wire [      `ROB_SIZE_WIDTH-1:0] sb2rob_rob_id;
    wire [                     31:0] sb2rob_dest;
    wire [                     31:0] sb2rob_value;
    wire                             lb_full;
    wire                             sb_full;

    // rs
    wire                             rs2alu_ready;
    wire [`CALC_OP_L1_NUM_WIDTH-1:0] rs2alu_op_L1;
    wire                             rs2alu_op_L2;
    wire [                     31:0] rs2alu_opr1;
    wire [                     31:0] rs2alu_opr2;
    wire [        `ROB_SIZE_WIDTH:0] rs2alu_dependency;
    wire                             rs_full;

    // alu
    wire                             alu_ready;
    wire [                     31:0] alu_value;
    wire [        `ROB_SIZE_WIDTH:0] alu_dependency;

    // icache
    wire                             ic2mem_miss;
    wire [                     31:0] ic2mem_instr_addr;
    wire                             ic2if_hit;
    wire                             ic2if_miss_ready;
    wire [                     31:0] ic2if_instr;

    // mem_controller
    wire                             mem_busy;
    wire                             mem_dout_ready;
    wire                             mem_iout_ready;
    wire [                     31:0] mem_out;
    wire [        `ROB_SIZE_WIDTH:0] mem_dependency;

    // rf
    wire [                     31:0] rf_value1;
    wire [                     31:0] rf_value2;
    wire [        `ROB_SIZE_WIDTH:0] rf_dependency1;
    wire [        `ROB_SIZE_WIDTH:0] rf_dependency2;
    wire [                     31:0] rf_value_jalr;

    instr_fetcher if0 (
        .clk_in           (clk_in),
        .rst_in           (rst_in),
        .rdy_in           (rdy_in),
        .need_flush_in    (rob_need_flush),
        .is_stall_in      (dec_is_stall),
        .rob_jump_addr    (rob_jump_addr),
        .if2dec_ready     (if2dec_ready),
        .if2dec_instr     (if2dec_instr),
        .if2dec_instr_addr(if2dec_instr_addr),
        .if2dec_is_jump   (if2dec_is_jump),
        .if2dec_jump_addr (if2dec_jump_addr),
        // combinatorial logic
        .pred_is_jump     (0),
        .ic_hit           (ic2if_hit),
        .ic_miss_ready    (ic2if_miss_ready),
        .ic_instr         (ic2if_instr),
        .rf_value_jalr    (rf_value_jalr),
        .fetch_enable_out (if2ic_fetch_enable),
        .pc_out           (if_pc),
        .rf_jalr_out      (if2rf_rs_jalr)
    );

    // predictor pred0 (
    //     .clk_in        (clk_in),
    //     .rst_in        (rst_in),
    //     .rdy_in        (rdy_in),
    //     .rob_valid     (rob2pred_ready),
    //     .rob_instr_addr(rob_instr_addr),
    //     .rob_is_jump   (rob_is_jump),
    //     // combinatorial logic
    //     .pc_in         (if_pc),
    //     .pred2if_result(pred2if_result)
    // );

    dec dec0 (
        .clk_in          (clk_in),
        .rst_in          (rst_in),
        .rdy_in          (rdy_in),
        .if_valid        (if2dec_ready),
        .if_instr        (if2dec_instr),
        .if_instr_addr   (if2dec_instr_addr),
        .if_is_jump      (if2dec_is_jump),
        .if_jump_addr    (if2dec_jump_addr),
        .need_flush_in   (rob_need_flush),
        .is_stall_out    (dec_is_stall),
        .dec_ready       (dec_ready),
        .is_C_out        (dec_is_C),
        .rob_type_out    (dec_rob_type),
        .dest_out        (dec_dest),
        .rs1_out         (dec_rs1),
        .rs2_out         (dec_rs2),
        .result_value_out(dec_result_value),
        .instr_addr_out  (dec_instr_addr),
        .jump_addr_out   (dec_jump_addr),
        .rob_state_out   (dec_rob_state),
        .is_jump_out     (dec_is_jump),
        .calc_op_L1_out  (dec_calc_op_L1),
        .calc_op_L2_out  (dec_calc_op_L2),
        .is_imm_out      (dec_is_imm),
        .imm_out         (dec_imm),
        .mem_type_out    (dec_mem_type),
        // combinatorial logic
        .rob_full        (rob_full),
        .rs_full         (rs_full),
        .lb_full         (lb_full),
        .sb_full         (sb_full)
    );

    rob rob0 (
        .clk_in         (clk_in),
        .rst_in         (rst_in),
        .rdy_in         (rdy_in),
        .dec_valid      (dec_ready),
        .dec_is_C       (dec_is_C),
        .dec_rob_type   (dec_rob_type),
        .dec_dest       (dec_dest),
        .dec_value      (dec_result_value),
        .dec_instr_addr (dec_instr_addr),
        .dec_jump_addr  (dec_jump_addr),
        .dec_rob_state  (dec_rob_state),
        .dec_is_jump    (dec_is_jump),
        .alu_valid      (alu_ready),
        .alu_dependency (alu_dependency),
        .alu_value      (alu_value),
        .mem_valid      (mem_dout_ready),
        .mem_dependency (mem_dependency),
        .mem_value      (mem_out),
        .mem_busy       (mem_busy),
        .lsb_valid      (sb2rob_ready),
        .lsb_rob_id     (sb2rob_rob_id),
        .lsb_dest       (sb2rob_dest),
        .lsb_value      (sb2rob_value),
        .rob2rf_ready   (rob2rf_ready),
        .rob2mem_ready  (rob2mem_ready),
        .rob2lsb_pop_sb (rob2lsb_pop_sb),
        .rob2pred_ready (rob2pred_ready),
        .need_flush_out (rob_need_flush),
        .rd_out         (rob_rd),
        .value_out      (rob_value),
        .dependency_out (rob_dependency),
        .store_type_out (rob_store_type),
        .data_addr_out  (rob_data_addr),
        .jump_addr_out  (rob_jump_addr),
        .instr_addr_out (rob_instr_addr),
        .is_jump_out    (rob_is_jump),
        // combinatorial logic
        .rf_dependency1 (rf_dependency1),
        .rf_dependency2 (rf_dependency2),
        .is_found_1_out (rob_is_found_1),
        .value1_out     (rob_value1),
        .is_found_2_out (rob_is_found_2),
        .value2_out     (rob_value2),
        .buffer_full_out(rob_full),
        .rear_next_out  (rob_rear_next)
    );

    lsb lsb0 (
        .clk_in           (clk_in),
        .rst_in           (rst_in),
        .rdy_in           (rdy_in),
        .dec_valid        (dec_ready),
        .dec_mem_type     (dec_mem_type),
        .dec_imm          (dec_imm),
        .alu_valid        (alu_ready),
        .alu_dependency   (alu_dependency),
        .alu_value        (alu_value),
        .mem_valid        (mem_dout_ready),
        .mem_dependency   (mem_dependency),
        .mem_value        (mem_out),
        .mem_busy         (mem_busy),
        .rob_pop_sb       (rob2lsb_pop_sb),
        .need_flush_in    (rob_need_flush),
        .lb2mem_ready     (lb2mem_ready),
        .lb2mem_load_type (lb2mem_load_type),
        .lb2mem_addr      (lb2mem_addr),
        .lb2mem_dependency(lb2mem_dependency),
        .sb2rob_ready     (sb2rob_ready),
        .sb2rob_rob_id    (sb2rob_rob_id),
        .sb2rob_dest      (sb2rob_dest),
        .sb2rob_value     (sb2rob_value),
        // combinatorial logic
        .rob_new_rob_id   (rob_rear_next),
        .rf_value1        (rf_value1),
        .rf_value2        (rf_value2),
        .rf_dependency1   (rf_dependency1),
        .rf_dependency2   (rf_dependency2),
        .rob_value1       (rob_value1),
        .rob_value2       (rob_value2),
        .rob_is_found_1   (rob_is_found_1),
        .rob_is_found_2   (rob_is_found_2),
        .lb_full_out      (lb_full),
        .sb_full_out      (sb_full)
    );

    rs rs0 (
        .clk_in           (clk_in),
        .rst_in           (rst_in),
        .rdy_in           (rdy_in),
        .need_flush_in    (rob_need_flush),
        .alu_valid        (alu_ready),
        .alu_value        (alu_value),
        .alu_dependency   (alu_dependency),
        .mem_valid        (mem_dout_ready),
        .mem_value        (mem_out),
        .mem_dependency   (mem_dependency),
        .dec_valid        (dec_ready),
        .dec_calc_op_L1   (dec_calc_op_L1),
        .dec_calc_op_L2   (dec_calc_op_L2),
        .dec_is_imm       (dec_is_imm),
        .dec_imm          (dec_imm),
        .rs2alu_ready     (rs2alu_ready),
        .rs2alu_op_L1     (rs2alu_op_L1),
        .rs2alu_op_L2     (rs2alu_op_L2),
        .rs2alu_opr1      (rs2alu_opr1),
        .rs2alu_opr2      (rs2alu_opr2),
        .rs2alu_dependency(rs2alu_dependency),
        // combinatorial logic
        .rob_new_rob_id   (rob_rear_next),
        .rf_value1        (rf_value1),
        .rf_value2        (rf_value2),
        .rf_dependency1   (rf_dependency1),
        .rf_dependency2   (rf_dependency2),
        .rob_value1       (rob_value1),
        .rob_value2       (rob_value2),
        .rob_is_found_1   (rob_is_found_1),
        .rob_is_found_2   (rob_is_found_2),
        .station_full_out (rs_full)
    );

    alu alu0 (
        .clk_in        (clk_in),
        .rst_in        (rst_in),
        .rdy_in        (rdy_in),
        .need_flush_in (rob_need_flush),
        .valid_in      (rs2alu_ready),
        .opr1_in       (rs2alu_opr1),
        .opr2_in       (rs2alu_opr2),
        .dependency_in (rs2alu_dependency),
        .alu_op_L1_in  (rs2alu_op_L1),
        .alu_op_L2_in  (rs2alu_op_L2),
        .ready_out     (alu_ready),
        .value_out     (alu_value),
        .dependency_out(alu_dependency)
    );

    icache icache0 (
        .clk_in        (clk_in),
        .rst_in        (rst_in),
        .rdy_in        (rdy_in),
        .need_flush_in (rob_need_flush),
        .mem_busy      (mem_busy),
        .mem_valid     (mem_iout_ready),
        .mem_instr     (mem_out),
        .miss_out      (ic2mem_miss),
        .instr_addr_out(ic2mem_instr_addr),
        // combinatorial logic
        .if_valid      (if2ic_fetch_enable),
        .if_instr_addr (if_pc),
        .hit_out       (ic2if_hit),
        .miss_ready_out(ic2if_miss_ready),
        .instr_out     (ic2if_instr)
    );

    mem_controller mem0 (
        .clk_in        (clk_in),
        .rst_in        (rst_in),
        .rdy_in        (rdy_in),
        .need_flush_in (rob_need_flush),
        .io_buffer_full(io_buffer_full),
        .byte_dout     (mem_din),
        .byte_din      (mem_dout),
        .byte_a        (mem_a),
        .byte_wr       (mem_wr),
        .ic_valid      (ic2mem_miss),
        .ic_aout       (ic2mem_instr_addr),
        .rob_valid     (rob2mem_ready),
        .rob_din       (rob_value),
        .rob_ain       (rob_data_addr),
        .rob_store_type(rob_store_type),
        .lsb_valid     (lb2mem_ready),
        .lsb_aout      (lb2mem_addr),
        .lsb_dependency(lb2mem_dependency),
        .lsb_load_type (lb2mem_load_type),
        .dout_ready    (mem_dout_ready),
        .iout_ready    (mem_iout_ready),
        .out           (mem_out),
        .dependency_out(mem_dependency),
        .busy_out      (mem_busy)
    );

    rf rf0 (
        .clk_in            (clk_in),
        .rst_in            (rst_in),
        .rdy_in            (rdy_in),
        .need_flush_in     (rob_need_flush),
        .rob_valid         (rob2rf_ready),
        .rob_rd            (rob_rd),
        .rob_value         (rob_value),
        .rob_dependency    (rob_dependency),
        .dec_valid         (dec_ready),
        .dec_rs1           (dec_rs1),
        .dec_rs2           (dec_rs2),
        .dec_rd            (dec_dest),
        // combinatorial logic
        .rob_new_dependency({1'b0, rob_rear_next}),
        .if_rs_jalr        (if2rf_rs_jalr),
        .value1_out        (rf_value1),
        .value2_out        (rf_value2),
        .dependency1_out   (rf_dependency1),
        .dependency2_out   (rf_dependency2),
        .value_jalr_out    (rf_value_jalr)
    );

endmodule
