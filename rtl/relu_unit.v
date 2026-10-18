`timescale 1ns / 1ps
module relu_unit #(
    parameter ACC_WIDTH = 20
) (
    input  wire signed [ACC_WIDTH-1:0] value_in,
    output wire signed [ACC_WIDTH-1:0] value_out
);

    assign value_out = value_in[ACC_WIDTH-1] ? {ACC_WIDTH{1'b0}} : value_in;

endmodule