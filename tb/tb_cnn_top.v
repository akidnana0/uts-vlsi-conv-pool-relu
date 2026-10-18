`timescale 1ns / 1ps
//Stimulus dan acuan dibaca dari golden model (tb/vectors/*.hex)
//Memeriksa setiap tahap: konvolusi, maxpooling, ReLU, dan output 8-bit
//Mencetak matriks setiap tahap ke log
//Jalankan dari root repo: make sim
module tb_cnn_top;

    //Parameter
    localparam IMG_SIZE    = 16;
    localparam KERNEL_SIZE = 3;
    localparam NUM_KERNELS = 3;
    localparam DATA_WIDTH  = 8;
    localparam ACC_WIDTH   = 20;
    localparam CONV_SIZE   = IMG_SIZE - KERNEL_SIZE + 1;                  // 14
    localparam POOL_OUT    = CONV_SIZE / 2;                               // 7
    localparam NUM_PIXELS  = IMG_SIZE * IMG_SIZE;                         // 256
    localparam NUM_WEIGHTS = KERNEL_SIZE * KERNEL_SIZE * NUM_KERNELS;     // 27
    localparam CONV_COUNT  = CONV_SIZE * CONV_SIZE;                       // 196
    localparam POOL_COUNT  = POOL_OUT * POOL_OUT;                         // 49
    localparam CLK_PERIOD  = 10;

    //Sinyal
    reg                               clk       = 0;
    reg                               rst_n     = 0;
    reg                               start     = 0;
    reg                               in_valid  = 0;
    reg  [DATA_WIDTH-1:0]             pixel_in  = 0;
    reg  [DATA_WIDTH-1:0]             weight_in = 0;
    wire                              out_valid;
    wire [NUM_KERNELS*DATA_WIDTH-1:0] data_out;
    wire                              done;

    //Data golden model
    reg [DATA_WIDTH-1:0] image_vec  [0:NUM_PIXELS-1];
    reg [DATA_WIDTH-1:0] kernel_vec [0:NUM_WEIGHTS-1];
    reg [ACC_WIDTH-1:0]  conv_exp   [0:NUM_KERNELS*CONV_COUNT-1];
    reg [ACC_WIDTH-1:0]  pool_exp   [0:NUM_KERNELS*POOL_COUNT-1];
    reg [ACC_WIDTH-1:0]  relu_exp   [0:NUM_KERNELS*POOL_COUNT-1];
    reg [DATA_WIDTH-1:0] out_exp    [0:NUM_KERNELS*POOL_COUNT-1];

    //Hasil RTL
    reg [ACC_WIDTH-1:0]  conv_got   [0:NUM_KERNELS*CONV_COUNT-1];
    reg [ACC_WIDTH-1:0]  pool_got   [0:NUM_KERNELS*POOL_COUNT-1];
    reg [ACC_WIDTH-1:0]  relu_got   [0:NUM_KERNELS*POOL_COUNT-1];
    reg [DATA_WIDTH-1:0] out_got    [0:NUM_KERNELS*POOL_COUNT-1];

    integer conv_count = 0, pool_count = 0, out_count = 0;
    integer conv_err   = 0, pool_err   = 0, relu_err  = 0, out_err = 0;
    integer b, c, start_time, total_cycles;

    cnn_top dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .in_valid  (in_valid),
        .pixel_in  (pixel_in),
        .weight_in (weight_in),
        .out_valid (out_valid),
        .data_out  (data_out),
        .done      (done)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    function automatic is_match;
        input [ACC_WIDTH-1:0] got;
        input [ACC_WIDTH-1:0] expected;
        begin
            is_match = (^got !== 1'bx) && (got === expected);
        end
    endfunction

    //Cek hasil konvolusi
    integer window, sub, conv_row, conv_col, idx_conv;
    always @(negedge clk) begin
        if (rst_n && dut.pool_update) begin
            window   = conv_count / 4;
            sub      = conv_count % 4;
            conv_row = 2 * (window / POOL_OUT) + sub / 2;
            conv_col = 2 * (window % POOL_OUT) + sub % 2;
            for (c = 0; c < NUM_KERNELS; c = c + 1) begin
                idx_conv = c * CONV_COUNT + conv_row * CONV_SIZE + conv_col;
                conv_got[idx_conv] = dut.conv_results[c*ACC_WIDTH +: ACC_WIDTH];
                if (!is_match(conv_got[idx_conv], conv_exp[idx_conv])) begin
                    conv_err = conv_err + 1;
                    $display("FAIL conv ch%0d [%0d,%0d]: %0d, seharusnya %0d", c + 1, conv_row, conv_col, $signed(conv_got[idx_conv]), $signed(conv_exp[idx_conv]));
                end
            end
            conv_count = conv_count + 1;
        end
    end

    //Cek hasil pooling dan ReLU
    integer idx_pool;
    always @(negedge clk) begin
        if (rst_n && dut.output_load) begin
            for (c = 0; c < NUM_KERNELS; c = c + 1) begin
                idx_pool = c * POOL_COUNT + pool_count;
                pool_got[idx_pool] = dut.pool_results[c*ACC_WIDTH +: ACC_WIDTH];
                relu_got[idx_pool] = dut.relu_results[c*ACC_WIDTH +: ACC_WIDTH];
                if (!is_match(pool_got[idx_pool], pool_exp[idx_pool])) begin
                    pool_err = pool_err + 1;
                    $display("FAIL pool ch%0d [%0d,%0d]: %0d, seharusnya %0d", c + 1, pool_count / POOL_OUT, pool_count % POOL_OUT, $signed(pool_got[idx_pool]), $signed(pool_exp[idx_pool]));
                end
                if (!is_match(relu_got[idx_pool], relu_exp[idx_pool])) begin
                    relu_err = relu_err + 1;
                    $display("FAIL relu ch%0d [%0d,%0d]: %0d, seharusnya %0d", c + 1, pool_count / POOL_OUT, pool_count % POOL_OUT, $signed(relu_got[idx_pool]), $signed(relu_exp[idx_pool]));
                end
            end
            pool_count = pool_count + 1;
        end
    end

    //Cek output akhir
    integer idx_out;
    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            for (c = 0; c < NUM_KERNELS; c = c + 1) begin
                idx_out = c * POOL_COUNT + out_count;
                out_got[idx_out] = data_out[c*DATA_WIDTH +: DATA_WIDTH];
                if ((^out_got[idx_out] === 1'bx) || (out_got[idx_out] !== out_exp[idx_out])) begin
                    out_err = out_err + 1;
                    $display("FAIL output ch%0d [%0d,%0d]: %0d, seharusnya %0d", c + 1,
                             out_count / POOL_OUT, out_count % POOL_OUT,
                             out_got[idx_out], out_exp[idx_out]);
                end
            end
            out_count = out_count + 1;
        end
    end

    //Cetak matriks
    integer pr, pc;

    task print_conv;               // 14x14 per channel, signed
        input integer channel;
        begin
            $display("Hasil konvolusi channel %0d (14x14):", channel + 1);
            for (pr = 0; pr < CONV_SIZE; pr = pr + 1) begin
                for (pc = 0; pc < CONV_SIZE; pc = pc + 1)
                    $write("%8d", $signed(conv_got[channel*CONV_COUNT + pr*CONV_SIZE + pc]));
                $write("\n");
            end
        end
    endtask

    task print_pool;               // 7x7 per channel
        input integer channel;
        input integer stage;
        begin
            for (pr = 0; pr < POOL_OUT; pr = pr + 1) begin
                for (pc = 0; pc < POOL_OUT; pc = pc + 1) begin
                    if (stage == 0)      $write("%8d", $signed(pool_got[channel*POOL_COUNT + pr*POOL_OUT + pc]));
                    else if (stage == 1) $write("%8d", $signed(relu_got[channel*POOL_COUNT + pr*POOL_OUT + pc]));
                    else                 $write("%5d", out_got[channel*POOL_COUNT + pr*POOL_OUT + pc]);
                end
                $write("\n");
            end
        end
    endtask

    //Skenario
    initial begin
        $dumpfile("sim/tb_cnn_top.vcd");
        $dumpvars(0, tb_cnn_top);

        $readmemh("tb/vectors/image.hex",  image_vec);
        $readmemh("tb/vectors/kernel.hex", kernel_vec);
        $readmemh("tb/vectors/conv.hex",   conv_exp);
        $readmemh("tb/vectors/pool.hex",   pool_exp);
        $readmemh("tb/vectors/relu.hex",   relu_exp);
        $readmemh("tb/vectors/output.hex", out_exp);

        if (^image_vec[0] === 1'bx || ^kernel_vec[0] === 1'bx || ^out_exp[0] === 1'bx) begin
            $display("ERROR: file vektor tidak terbaca. Jalankan 'make golden' dulu.");
            $finish;
        end

        //Reset
        #20 rst_n = 1;

        //Pulsa start
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        start_time = $time - CLK_PERIOD/2;      // tepi naik saat start terbaca

        for (b = 0; b < NUM_PIXELS; b = b + 1) begin
            in_valid  = 1;
            pixel_in  = image_vec[b];
            weight_in = (b < NUM_WEIGHTS) ? kernel_vec[b] : 8'd0;
            @(negedge clk);
        end
        in_valid  = 0;
        pixel_in  = 0;
        weight_in = 0;

        wait (done);
        total_cycles = ($time - start_time) / CLK_PERIOD;
        repeat (2) @(negedge clk);

        //Cetak hasil setiap tahap
        $display("");
        $display("INPUT (16x16) :");
        for (pr = 0; pr < IMG_SIZE; pr = pr + 1) begin
            for (pc = 0; pc < IMG_SIZE; pc = pc + 1)
                $write("%5d", image_vec[pr*IMG_SIZE + pc]);
            $write("\n");
        end

        for (c = 0; c < NUM_KERNELS; c = c + 1) begin
            $display("");
            $display("CHANNEL %0d :", c + 1);
            $display("Kernel %0d: %0d %0d %0d | %0d %0d %0d | %0d %0d %0d", c + 1, $signed(kernel_vec[c*9+0]), $signed(kernel_vec[c*9+1]), $signed(kernel_vec[c*9+2]), $signed(kernel_vec[c*9+3]), $signed(kernel_vec[c*9+4]), $signed(kernel_vec[c*9+5]), $signed(kernel_vec[c*9+6]), $signed(kernel_vec[c*9+7]), $signed(kernel_vec[c*9+8]));
            print_conv(c);
            $display("Hasil maxpooling channel %0d (7x7):", c + 1);
            print_pool(c, 0);
            $display("Hasil ReLU channel %0d (7x7):", c + 1);
            print_pool(c, 1);
            $display("Output 8-bit channel %0d (7x7):", c + 1);
            print_pool(c, 2);
        end

        //Ringkasan
        $display("");
        $display("Tahap        | Cek | Salah");
        $display("-------------+-----+------");
        $display("Konvolusi    | %3d | %3d", conv_count * NUM_KERNELS, conv_err);
        $display("Maxpooling   | %3d | %3d", pool_count * NUM_KERNELS, pool_err);
        $display("ReLU         | %3d | %3d", pool_count * NUM_KERNELS, relu_err);
        $display("Output 8-bit | %3d | %3d", out_count  * NUM_KERNELS, out_err);
        $display("");
        $display("Total clock : %0d", total_cycles);

        if (conv_err + pool_err + relu_err + out_err == 0 &&
            conv_count == CONV_COUNT && pool_count == POOL_COUNT && out_count == POOL_COUNT)
            $display("HASIL: SEMUA LULUS");
        else
            $display("HASIL: GAGAL");

        $finish;
    end

endmodule