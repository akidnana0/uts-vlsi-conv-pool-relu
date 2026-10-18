`timescale 1ns / 1ps
//Menyimpan IMG_SIZE x IMG_SIZE
module image_buffer #(
    parameter IMG_SIZE   = 16,
    parameter DATA_WIDTH = 8
) (
    input  wire                              clk,
    input  wire                              write_enable,
    input  wire [$clog2(IMG_SIZE*IMG_SIZE)-1:0] write_address,
    input  wire [DATA_WIDTH-1:0]             write_data,
    input  wire [$clog2(IMG_SIZE)-1:0]       read_row,
    input  wire [$clog2(IMG_SIZE)-1:0]       read_column,
    output wire [DATA_WIDTH-1:0]             read_data
);

    localparam NUM_PIXELS   = IMG_SIZE * IMG_SIZE;
    localparam ADDRESS_WIDTH = $clog2(NUM_PIXELS);
    localparam INDEX_WIDTH   = $clog2(IMG_SIZE);
    localparam [ADDRESS_WIDTH-1:0] ROW_STRIDE = IMG_SIZE;

    reg [DATA_WIDTH-1:0] memory [0:NUM_PIXELS-1];

    wire [ADDRESS_WIDTH-1:0] read_address =
        {{(ADDRESS_WIDTH - INDEX_WIDTH){1'b0}}, read_row} * ROW_STRIDE +
        {{(ADDRESS_WIDTH - INDEX_WIDTH){1'b0}}, read_column};

    always @(posedge clk) begin
        if (write_enable)
            memory[write_address] <= write_data;
    end

    assign read_data = memory[read_address];

endmodule