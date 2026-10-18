`timescale 1ns / 1ps
module cnn_top #(
    parameter IMG_SIZE    = 16,
    parameter KERNEL_SIZE = 3,
    parameter NUM_KERNELS = 3,
    parameter POOL_WINDOW = 2,
    parameter DATA_WIDTH  = 8,
    parameter ACC_WIDTH   = 20,
    parameter SHIFT       = 8
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start,
    input  wire                              in_valid,
    input  wire [DATA_WIDTH-1:0]             pixel_in,
    input  wire [DATA_WIDTH-1:0]             weight_in,
    output reg                               out_valid,
    output reg  [NUM_KERNELS*DATA_WIDTH-1:0] data_out,
    output wire                              done
);

    localparam LOAD_WIDTH   = $clog2(IMG_SIZE * IMG_SIZE);
    localparam WADDR_WIDTH  = $clog2(KERNEL_SIZE * KERNEL_SIZE * NUM_KERNELS);
    localparam INDEX_WIDTH  = $clog2(IMG_SIZE);
    localparam KINDEX_WIDTH = $clog2(KERNEL_SIZE);

    wire                    load_enable;
    wire [LOAD_WIDTH-1:0]   load_address;
    wire                    kernel_write_enable;
    wire [WADDR_WIDTH-1:0]  kernel_write_address;
    wire [INDEX_WIDTH-1:0]  read_row;
    wire [INDEX_WIDTH-1:0]  read_column;
    wire [KINDEX_WIDTH-1:0] kernel_row;
    wire [KINDEX_WIDTH-1:0] kernel_column;
    wire                    mac_clear;
    wire                    mac_enable;
    wire                    pool_update;
    wire                    pool_first;
    wire                    output_load;

    wire [DATA_WIDTH-1:0]             pixel;
    wire [NUM_KERNELS*DATA_WIDTH-1:0] weights;

    wire [NUM_KERNELS*ACC_WIDTH-1:0]  conv_results;
    wire [NUM_KERNELS*ACC_WIDTH-1:0]  pool_results;
    wire [NUM_KERNELS*ACC_WIDTH-1:0]  relu_results;
    wire [NUM_KERNELS*DATA_WIDTH-1:0] quant_results;

    //Control unit
    cnn_control #(
        .IMG_SIZE    (IMG_SIZE),
        .KERNEL_SIZE (KERNEL_SIZE),
        .NUM_KERNELS (NUM_KERNELS),
        .POOL_WINDOW (POOL_WINDOW)
    ) control_unit (
        .clk                  (clk),
        .rst_n                (rst_n),
        .start                (start),
        .in_valid             (in_valid),
        .load_enable          (load_enable),
        .load_address         (load_address),
        .kernel_write_enable  (kernel_write_enable),
        .kernel_write_address (kernel_write_address),
        .read_row             (read_row),
        .read_column          (read_column),
        .kernel_row           (kernel_row),
        .kernel_column        (kernel_column),
        .mac_clear            (mac_clear),
        .mac_enable           (mac_enable),
        .pool_update          (pool_update),
        .pool_first           (pool_first),
        .output_load          (output_load),
        .done                 (done)
    );

    //Buffer
    image_buffer #(
        .IMG_SIZE   (IMG_SIZE),
        .DATA_WIDTH (DATA_WIDTH)
    ) image_memory (
        .clk           (clk),
        .write_enable  (load_enable),
        .write_address (load_address),
        .write_data    (pixel_in),
        .read_row      (read_row),
        .read_column   (read_column),
        .read_data     (pixel)
    );

    kernel_buffer #(
        .KERNEL_SIZE (KERNEL_SIZE),
        .NUM_KERNELS (NUM_KERNELS),
        .DATA_WIDTH  (DATA_WIDTH)
    ) kernel_memory (
        .clk           (clk),
        .write_enable  (kernel_write_enable),
        .write_address (kernel_write_address),
        .write_data    (weight_in),
        .kernel_row    (kernel_row),
        .kernel_column (kernel_column),
        .weights       (weights)
    );

    genvar c;
    generate
        for (c = 0; c < NUM_KERNELS; c = c + 1) begin : gen_channel
            conv_mac #(
                .DATA_WIDTH (DATA_WIDTH),
                .ACC_WIDTH  (ACC_WIDTH)
            ) mac (
                .clk         (clk),
                .rst_n       (rst_n),
                .clear       (mac_clear),
                .enable      (mac_enable),
                .pixel       (pixel),
                .weight      (weights[c*DATA_WIDTH +: DATA_WIDTH]),
                .accumulator (conv_results[c*ACC_WIDTH +: ACC_WIDTH])
            );

            maxpool_unit #(
                .ACC_WIDTH (ACC_WIDTH)
            ) pool (
                .clk       (clk),
                .rst_n     (rst_n),
                .update    (pool_update),
                .first     (pool_first),
                .value_in  (conv_results[c*ACC_WIDTH +: ACC_WIDTH]),
                .max_value (pool_results[c*ACC_WIDTH +: ACC_WIDTH])
            );

            relu_unit #(
                .ACC_WIDTH (ACC_WIDTH)
            ) relu (
                .value_in  (pool_results[c*ACC_WIDTH +: ACC_WIDTH]),
                .value_out (relu_results[c*ACC_WIDTH +: ACC_WIDTH])
            );

            requant_unit #(
                .ACC_WIDTH  (ACC_WIDTH),
                .DATA_WIDTH (DATA_WIDTH),
                .SHIFT      (SHIFT)
            ) requant (
                .value_in  (relu_results[c*ACC_WIDTH +: ACC_WIDTH]),
                .value_out (quant_results[c*DATA_WIDTH +: DATA_WIDTH])
            );
        end
    endgenerate

    //Register output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            data_out  <= {(NUM_KERNELS*DATA_WIDTH){1'b0}};
        end else begin
            out_valid <= output_load;
            if (output_load)
                data_out <= quant_results;
        end
    end

endmodule