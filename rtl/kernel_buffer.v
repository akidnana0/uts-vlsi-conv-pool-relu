`timescale 1ns / 1ps
//Menyimpan NUM_KERNELS kernel KERNEL_SIZE x KERNEL_SIZE
module kernel_buffer #(
    parameter KERNEL_SIZE = 3,
    parameter NUM_KERNELS = 3,
    parameter DATA_WIDTH  = 8
) (
    input  wire                                              clk,
    input  wire                                              write_enable,
    input  wire [$clog2(KERNEL_SIZE*KERNEL_SIZE*NUM_KERNELS)-1:0] write_address,
    input  wire [DATA_WIDTH-1:0]                             write_data,
    input  wire [$clog2(KERNEL_SIZE)-1:0]                    kernel_row,
    input  wire [$clog2(KERNEL_SIZE)-1:0]                    kernel_column,
    output wire [NUM_KERNELS*DATA_WIDTH-1:0]                 weights
);

    localparam TAPS          = KERNEL_SIZE * KERNEL_SIZE;
    localparam NUM_WEIGHTS   = TAPS * NUM_KERNELS;
    localparam ADDRESS_WIDTH = $clog2(NUM_WEIGHTS);
    localparam INDEX_WIDTH   = $clog2(KERNEL_SIZE);
    localparam [ADDRESS_WIDTH-1:0] ROW_STRIDE = KERNEL_SIZE;

    reg [DATA_WIDTH-1:0] memory [0:NUM_WEIGHTS-1];

    wire [ADDRESS_WIDTH-1:0] tap =
        {{(ADDRESS_WIDTH - INDEX_WIDTH){1'b0}}, kernel_row} * ROW_STRIDE +
        {{(ADDRESS_WIDTH - INDEX_WIDTH){1'b0}}, kernel_column};

    always @(posedge clk) begin
        if (write_enable)
            memory[write_address] <= write_data;
    end

    genvar c;
    generate
        for (c = 0; c < NUM_KERNELS; c = c + 1) begin : gen_read
            localparam [ADDRESS_WIDTH-1:0] OFFSET = c * TAPS;
            assign weights[c*DATA_WIDTH +: DATA_WIDTH] = memory[OFFSET + tap];
        end
    endgenerate

endmodule