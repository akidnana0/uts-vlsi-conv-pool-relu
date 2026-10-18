`timescale 1ns / 1ps
module requant_unit #(
    parameter ACC_WIDTH  = 20,
    parameter DATA_WIDTH = 8,
    parameter SHIFT      = 8
) (
    input  wire [ACC_WIDTH-1:0]  value_in,
    output wire [DATA_WIDTH-1:0] value_out
);

    wire [ACC_WIDTH-1:0] shifted  = value_in >> SHIFT;
    wire                 overflow = |shifted[ACC_WIDTH-1:DATA_WIDTH];

    assign value_out = overflow ? {DATA_WIDTH{1'b1}} : shifted[DATA_WIDTH-1:0];

endmodule