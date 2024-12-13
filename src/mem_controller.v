`include "src/const_param.v"

module mem_unit(
    input clk_in,
    input rst_in,
    input rdy_in,

    // port with ram, combinatorial logic
    input io_buffer_full,  // 1 if uart buffer is full
    input [7:0] byte_dout,
    output wire [7:0] byte_din,
    output wire [31:0] byte_a,
    output wire byte_wr,  // write/read signal (1 for write)

    input ic_valid,
    input [31:0] ic_aout,

    input rob_valid,
    input [31:0] rob_din,
    input [31:0] rob_ain,

    input lsb_valid,
    input [31:0] lsb_aout,

    output reg iout_ready,
    output reg [31:0] iout,
    output reg dout_ready,
    output reg [31:0] dout,
    output reg [`ROB_SIZE_WIDTH-1:0] dependency_out
);

    always @(posedge clk_in) begin
        if (rst_in) begin
            iout_ready <= 0;
            dout_ready <= 0;
        end else if (!rdy_in) begin
            /* do nothing */
        end else begin
            iout_ready <= ic_valid;
            iout <= ic_aout;
            dout_ready <= rob_valid || lsb_valid;
            dout <= rob_valid ? rob_din : lsb_aout;
        end
    end

endmodule