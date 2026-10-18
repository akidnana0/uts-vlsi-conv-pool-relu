`timescale 1ns / 1ps
module maxpool_unit #(
    parameter ACC_WIDTH = 20
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        update,      
    input  wire                        first,     
    input  wire signed [ACC_WIDTH-1:0] value_in,
    output reg  signed [ACC_WIDTH-1:0] max_value
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            max_value <= {ACC_WIDTH{1'b0}};
        else if (update && (first || (value_in > max_value)))
            max_value <= value_in;
    end

endmodule