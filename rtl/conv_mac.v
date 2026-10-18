`timescale 1ns / 1ps
module conv_mac #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 20
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear,   
    input  wire                         enable,   
    input  wire        [DATA_WIDTH-1:0] pixel,
    input  wire        [DATA_WIDTH-1:0] weight,
    output reg  signed [ACC_WIDTH-1:0]  accumulator
);

    localparam PRODUCT_WIDTH = 2 * DATA_WIDTH + 1;
    wire signed [PRODUCT_WIDTH-1:0] pixel_extended  = {{(DATA_WIDTH + 1){1'b0}}, pixel};
    wire signed [PRODUCT_WIDTH-1:0] weight_extended = {{(DATA_WIDTH + 1){weight[DATA_WIDTH-1]}}, weight};
    wire signed [PRODUCT_WIDTH-1:0] product         = pixel_extended * weight_extended;
    wire signed [ACC_WIDTH-1:0]     product_extended =
        {{(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            accumulator <= {ACC_WIDTH{1'b0}};
        else if (clear)
            accumulator <= {ACC_WIDTH{1'b0}};
        else if (enable)
            accumulator <= accumulator + product_extended;
    end

endmodule