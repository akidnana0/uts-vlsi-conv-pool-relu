`timescale 1ns / 1ps
module cnn_control #(
    parameter IMG_SIZE    = 16,
    parameter KERNEL_SIZE = 3,
    parameter NUM_KERNELS = 3,
    parameter POOL_WINDOW = 2
) (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire in_valid,

    //Penulisan buffer
    output reg                                                load_enable,
    output wire [$clog2(IMG_SIZE*IMG_SIZE)-1:0]               load_address,
    output wire                                               kernel_write_enable,
    output wire [$clog2(KERNEL_SIZE*KERNEL_SIZE*NUM_KERNELS)-1:0] kernel_write_address,

    //Pembacaan buffer
    output wire [$clog2(IMG_SIZE)-1:0]                        read_row,
    output wire [$clog2(IMG_SIZE)-1:0]                        read_column,
    output reg  [$clog2(KERNEL_SIZE)-1:0]                     kernel_row,
    output reg  [$clog2(KERNEL_SIZE)-1:0]                     kernel_column,

    //Kontrol MAC, pooling, dan output
    output reg                                                mac_clear,
    output reg                                                mac_enable,
    output reg                                                pool_update,
    output wire                                               pool_first,
    output reg                                                output_load,
    output reg                                                done
);

    localparam CONV_SIZE   = IMG_SIZE - KERNEL_SIZE + 1;
    localparam POOL_OUT    = CONV_SIZE / POOL_WINDOW;
    localparam NUM_PIXELS  = IMG_SIZE * IMG_SIZE;
    localparam NUM_WEIGHTS = KERNEL_SIZE * KERNEL_SIZE * NUM_KERNELS;

    localparam LOAD_WIDTH   = $clog2(NUM_PIXELS);
    localparam WADDR_WIDTH  = $clog2(NUM_WEIGHTS);
    localparam INDEX_WIDTH  = $clog2(IMG_SIZE);
    localparam KINDEX_WIDTH = $clog2(KERNEL_SIZE);
    localparam SUB_WIDTH    = $clog2(POOL_WINDOW);
    localparam POOL_WIDTH   = $clog2(POOL_OUT);

    localparam [LOAD_WIDTH-1:0]   LAST_PIXEL   = NUM_PIXELS - 1;
    localparam [LOAD_WIDTH-1:0]   WEIGHT_COUNT = NUM_WEIGHTS;
    localparam [KINDEX_WIDTH-1:0] LAST_KERNEL  = KERNEL_SIZE - 1;
    localparam LAST_SUB_VALUE  = POOL_WINDOW - 1;
    localparam LAST_POOL_VALUE = POOL_OUT - 1;
    localparam [SUB_WIDTH-1:0]    LAST_SUB     = LAST_SUB_VALUE[SUB_WIDTH-1:0];
    localparam [POOL_WIDTH-1:0]   LAST_POOL    = LAST_POOL_VALUE[POOL_WIDTH-1:0];
    localparam [INDEX_WIDTH-1:0]  POOL_STEP    = POOL_WINDOW;

    //State
    localparam [2:0] STATE_IDLE   = 3'd0,
                     STATE_LOAD   = 3'd1,
                     STATE_MAC    = 3'd2,
                     STATE_POOL   = 3'd3,
                     STATE_OUTPUT = 3'd4,
                     STATE_DONE   = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;
    reg       clear_counters;

    //Counter
    reg [LOAD_WIDTH-1:0] load_count;
    reg [SUB_WIDTH-1:0]  sub_row;
    reg [SUB_WIDTH-1:0]  sub_column;
    reg [POOL_WIDTH-1:0] pool_row;
    reg [POOL_WIDTH-1:0] pool_column;

    wire last_load   = in_valid && (load_count == LAST_PIXEL);
    wire last_tap    = (kernel_row == LAST_KERNEL) && (kernel_column == LAST_KERNEL);
    wire last_sub    = (sub_row == LAST_SUB) && (sub_column == LAST_SUB);
    wire last_window = (pool_row == LAST_POOL) && (pool_column == LAST_POOL);

    assign load_address         = load_count;
    assign kernel_write_enable  = load_enable && (load_count < WEIGHT_COUNT);
    assign kernel_write_address = load_count[WADDR_WIDTH-1:0];
    assign pool_first           = (sub_row == {SUB_WIDTH{1'b0}}) && (sub_column == {SUB_WIDTH{1'b0}});

    assign read_row =
        {{(INDEX_WIDTH - POOL_WIDTH){1'b0}}, pool_row} * POOL_STEP +
        {{(INDEX_WIDTH - SUB_WIDTH){1'b0}}, sub_row} +
        {{(INDEX_WIDTH - KINDEX_WIDTH){1'b0}}, kernel_row};
    assign read_column =
        {{(INDEX_WIDTH - POOL_WIDTH){1'b0}}, pool_column} * POOL_STEP +
        {{(INDEX_WIDTH - SUB_WIDTH){1'b0}}, sub_column} +
        {{(INDEX_WIDTH - KINDEX_WIDTH){1'b0}}, kernel_column};

    //Register state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end

    //Transisi state
    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE:   if (start)     next_state = STATE_LOAD;
            STATE_LOAD:   if (last_load) next_state = STATE_MAC;
            STATE_MAC:    if (last_tap)  next_state = STATE_POOL;
            STATE_POOL:   next_state = last_sub    ? STATE_OUTPUT : STATE_MAC;
            STATE_OUTPUT: next_state = last_window ? STATE_DONE   : STATE_MAC;
            STATE_DONE:   if (start)     next_state = STATE_LOAD;
            default:      next_state = STATE_IDLE;
        endcase
    end

    //Sinyal kontrol tiap state
    always @(*) begin
        clear_counters = 1'b0;
        load_enable    = 1'b0;
        mac_clear      = 1'b0;
        mac_enable     = 1'b0;
        pool_update    = 1'b0;
        output_load    = 1'b0;
        done           = 1'b0;

        case (state)
            STATE_IDLE: begin
                clear_counters = 1'b1;
                mac_clear      = 1'b1;
            end
            STATE_LOAD: begin
                load_enable = in_valid;
                mac_clear   = 1'b1;
            end
            STATE_MAC: begin
                mac_enable = 1'b1;
            end
            STATE_POOL: begin
                pool_update = 1'b1;
                mac_clear   = 1'b1;
            end
            STATE_OUTPUT: begin
                output_load = 1'b1;
            end
            STATE_DONE: begin
                clear_counters = 1'b1;
                mac_clear      = 1'b1;
                done           = 1'b1;
            end
            default: ;
        endcase
    end

    //Counter LOAD
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_count <= {LOAD_WIDTH{1'b0}};
        else if (clear_counters)
            load_count <= {LOAD_WIDTH{1'b0}};
        else if (load_enable)
            load_count <= load_count + 1'b1;
    end

    //Counter kernel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kernel_row    <= {KINDEX_WIDTH{1'b0}};
            kernel_column <= {KINDEX_WIDTH{1'b0}};
        end else if (clear_counters) begin
            kernel_row    <= {KINDEX_WIDTH{1'b0}};
            kernel_column <= {KINDEX_WIDTH{1'b0}};
        end else if (mac_enable) begin
            if (kernel_column == LAST_KERNEL) begin
                kernel_column <= {KINDEX_WIDTH{1'b0}};
                kernel_row    <= (kernel_row == LAST_KERNEL) ? {KINDEX_WIDTH{1'b0}} : kernel_row + 1'b1;
            end else begin
                kernel_column <= kernel_column + 1'b1;
            end
        end
    end

    // Counter pooling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sub_row    <= {SUB_WIDTH{1'b0}};
            sub_column <= {SUB_WIDTH{1'b0}};
        end else if (clear_counters) begin
            sub_row    <= {SUB_WIDTH{1'b0}};
            sub_column <= {SUB_WIDTH{1'b0}};
        end else if (pool_update) begin
            if (sub_column == LAST_SUB) begin
                sub_column <= {SUB_WIDTH{1'b0}};
                sub_row    <= (sub_row == LAST_SUB) ? {SUB_WIDTH{1'b0}} : sub_row + 1'b1;
            end else begin
                sub_column <= sub_column + 1'b1;
            end
        end
    end

    // Counter pooling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool_row    <= {POOL_WIDTH{1'b0}};
            pool_column <= {POOL_WIDTH{1'b0}};
        end else if (clear_counters) begin
            pool_row    <= {POOL_WIDTH{1'b0}};
            pool_column <= {POOL_WIDTH{1'b0}};
        end else if (output_load) begin
            if (pool_column == LAST_POOL) begin
                pool_column <= {POOL_WIDTH{1'b0}};
                pool_row    <= (pool_row == LAST_POOL) ? {POOL_WIDTH{1'b0}} : pool_row + 1'b1;
            end else begin
                pool_column <= pool_column + 1'b1;
            end
        end
    end

endmodule