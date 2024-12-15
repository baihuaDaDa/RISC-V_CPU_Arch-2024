`include "src/const_param.v"

module icache(
    input clk_in,
    input rst_in,
    input rdy_in,

    input mem_busy,

    input mem_valid,
    input [31:0] mem_instr,

    output reg miss_out,
    output reg [31:0] instr_addr_out,

    // combinatorial logic
    input if_valid,
    input [31:0] if_instr_addr,

    output wire instr_ready_out,
    output wire [31:0] instr_out
);

    localparam CACHE_LINE_SIZE = `CACHE_LINE_SIZE;
    localparam CACHE_LINE_SIZE_WIDTH = `CACHE_LINE_SIZE_WIDTH;

    integer i;

    // 16-bit line, fit for C.extension, no block offset
    // 6-bit tag, 10-bit index, the lowest bit ignored for 2 bytes per line; cache size: 1024 lines * 16 bits per line
    reg valid [CACHE_LINE_SIZE-1:0];
    reg [16-CACHE_LINE_SIZE_WIDTH-1:0] tag [CACHE_LINE_SIZE-1:0];
    reg [15:0] data [CACHE_LINE_SIZE-1:0];

    wire [31:0] instr_addr_next;
    wire [CACHE_LINE_SIZE_WIDTH-1:0] index_16;
    wire [16-CACHE_LINE_SIZE_WIDTH-1:0] tag_in_16;
    wire [CACHE_LINE_SIZE_WIDTH-1:0] index_32;
    wire [16-CACHE_LINE_SIZE_WIDTH-1:0] tag_in_32;
    wire hit_32;
    wire hit_16;

    assign instr_addr_next = if_instr_addr + 2;
    assign index_16 = if_instr_addr[CACHE_LINE_SIZE_WIDTH:1];
    assign tag_in_16 = if_instr_addr[16:CACHE_LINE_SIZE_WIDTH+1];
    assign index_32 = instr_addr_next[CACHE_LINE_SIZE_WIDTH:1];
    assign tag_in_32 = instr_addr_next[16:CACHE_LINE_SIZE_WIDTH+1];
    assign hit_16 = if_valid && valid[index_16] && tag[index_16] == tag_in_16 && data[index_16][1:0] != 2'b11;
    assign hit_32 = if_valid &&
                    valid[index_16] && tag[index_16] == tag_in_16 && data[index_16][1:0] == 2'b11 &&
                    valid[index_32] && tag[index_32] == tag_in_32;
    assign instr_ready_out = mem_valid || hit_32 || hit_16;
    assign instr_out = mem_valid ? mem_instr : hit_16 ? data[index_16] : hit_32 ? {data[index_32], data[index_16]} : 0;

    always @(posedge clk_in) begin
        if (rst_in) begin
            miss_out <= 0;
            for (i = 0; i < CACHE_LINE_SIZE; i = i + 1) begin
                valid[i] <= 0;
            end
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            miss_out <= !mem_busy && if_valid && !hit_32 && !hit_16;
            instr_addr_out <= if_instr_addr;
            if (mem_valid) begin
                    valid[index_16] <= 1;
                    tag[index_16] <= tag_in_16;
                    data[index_16] <= mem_instr[15:0];
                if (mem_instr[1:0] == 2'b11) begin
                    valid[index_32] <= 1;
                    tag[index_32] <= tag_in_32;
                    data[index_32] <= mem_instr[31:16];
                end
            end
        end
    end

endmodule