/* ================================================================
 * hls_ctrl — CPU-less HLS MelSpectrogram Control FSM
 * ----------------------------------------------------------------
 * cfu_hls を CPU 命令なしで RTL FSM から直接駆動する制御ラッパー。
 *
 * 手順 (32 フレーム分ループ):
 *   1. 音声 RAM から 2048 サンプル読出し → cfu_hls へ funct7=0 で書込み
 *      (リフレクトパディング適用)
 *   2. cfu_hls で計算実行 (funct7=1): Hann窓→FFT→パワー→メル→log
 *   3. メル値 32 個読出し (funct7=2) → mel 出力ポートへ書込み
 *
 * 音声 RAM は外部 (16000×32bit Q16, 1 サイクルレイテンシ)。
 * メル出力も外部 (1024×32bit, mel_bin*32+frame レイアウト)。
 * ================================================================ */
`default_nettype none
`timescale 1 ns / 1 ps

module hls_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        start_i,        // Pulse: begin full 32-frame processing
    output reg         done_o,         // High for 1 cycle when all frames complete

    // Audio RAM read port (16000 × 32-bit Q16, 1-cycle latency)
    output reg  [13:0] audio_addr_o,   // 0..15999
    input  wire [31:0] audio_data_i,

    // Mel output write port (1024 × 32-bit)
    output reg  [9:0]  mel_addr_o,     // mel_bin * 32 + frame
    output reg  [31:0] mel_data_o,
    output reg         mel_we_o
);

    // ================================================================
    // Constants
    // ================================================================
    localparam N_FFT      = 2048;
    localparam N_MELS     = 32;
    localparam N_FRAMES   = 32;   // 16000 / 512 + 1

    // ================================================================
    // FSM States
    // ================================================================
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_WR_ADDR    = 4'd1,   // Compute reflected audio address
        S_WR_RAM     = 4'd2,   // Wait 1 cycle for audio RAM read
        S_WR_HLS     = 4'd3,   // Issue HLS write (funct7=0)
        S_WR_WAIT    = 4'd4,   // Wait for HLS ap_done
        S_COMP_HLS   = 4'd5,   // Issue HLS compute (funct7=1)
        S_COMP_WAIT  = 4'd6,   // Wait for HLS ap_done
        S_RD_HLS     = 4'd7,   // Issue HLS read (funct7=2)
        S_RD_WAIT    = 4'd8,   // Wait for HLS ap_done, capture result
        S_RD_STORE   = 4'd9,   // Write mel value to output
        S_DONE       = 4'd10;

    reg [3:0] state;

    // ================================================================
    // Counters
    // ================================================================
    reg [4:0]  frame_cnt;    // 0..31
    reg [10:0] sample_cnt;   // 0..2047
    reg [4:0]  mel_cnt;      // 0..31

    // ================================================================
    // HLS handshake
    // ================================================================
    wire ap_done, ap_ready;
    /* verilator lint_off UNUSEDSIGNAL */
    wire ap_idle;  // kept for debug
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] hls_rslt;

    reg        hls_go;        // Pulse from FSM (1 cycle) to initiate transaction
    reg        hls_start_reg; // Sustains ap_start until ap_ready
    reg [7:0]  hls_funct7;
    reg [31:0] hls_src1;
    reg [31:0] hls_src2;

    wire hls_ap_start = hls_go || hls_start_reg;

    always @(posedge clk) begin
        if (!rst_n)
            hls_start_reg <= 1'b0;
        else if (ap_ready)
            hls_start_reg <= 1'b0;
        else if (hls_go)
            hls_start_reg <= 1'b1;
    end

    // ================================================================
    // cfu_hls instance
    // ================================================================
    cfu_hls u_cfu_hls (
        .ap_clk   (clk),
        .ap_start (hls_ap_start),
        .ap_done  (ap_done),
        .ap_idle  (ap_idle),
        .ap_ready (ap_ready),
        .funct3_i (8'd0),
        .funct7_i (hls_funct7),
        .src1_i   (hls_src1),
        .src2_i   (hls_src2),
        .rslt_o   (hls_rslt)
    );

    // ================================================================
    // Reflect padding (combinational)
    //   center  = frame_cnt * 512
    //   raw     = center - 1024 + sample_cnt
    //   if raw < 0          : audio_idx = -raw
    //   if raw >= 16000     : audio_idx = 31998 - raw
    //   else                : audio_idx = raw
    // ================================================================
    wire [13:0] center = {frame_cnt, 9'b0};  // frame_cnt << 9

    wire signed [15:0] raw_idx = $signed({2'b0, center})
                                 - 16'sd1024
                                 + $signed({5'b0, sample_cnt});

    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] neg_raw     = -raw_idx;        // upper bits always 0 for our range
    wire [15:0] reflect_hi = 16'sd31998 - raw_idx;
    /* verilator lint_on UNUSEDSIGNAL */

    reg [13:0] reflected_idx;
    always @(*) begin
        if (raw_idx < 0)
            reflected_idx = neg_raw[13:0];
        else if (raw_idx >= 16'sd16000)
            reflected_idx = reflect_hi[13:0];
        else
            reflected_idx = raw_idx[13:0];
    end

    // ================================================================
    // HLS result latch (for mel read)
    // ================================================================
    reg [31:0] hls_rslt_latched;

    // ================================================================
    // Main FSM
    // ================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            done_o          <= 1'b0;
            mel_we_o        <= 1'b0;
            hls_go          <= 1'b0;
            hls_funct7      <= 8'd0;
            hls_src1        <= 32'd0;
            hls_src2        <= 32'd0;
            frame_cnt       <= 5'd0;
            sample_cnt      <= 11'd0;
            mel_cnt         <= 5'd0;
            audio_addr_o    <= 14'd0;
            mel_addr_o      <= 10'd0;
            mel_data_o      <= 32'd0;
            hls_rslt_latched <= 32'd0;
        end else begin
            // Defaults: one-cycle pulses
            hls_go   <= 1'b0;
            mel_we_o <= 1'b0;
            done_o   <= 1'b0;

            case (state)

                // ---- Idle: wait for start ----
                S_IDLE: begin
                    if (start_i) begin
                        frame_cnt  <= 5'd0;
                        sample_cnt <= 11'd0;
                        state      <= S_WR_ADDR;
                    end
                end

                // ---- Write: compute reflected audio address ----
                S_WR_ADDR: begin
                    audio_addr_o <= reflected_idx;
                    state        <= S_WR_RAM;
                end

                // ---- Write: wait 1 cycle for audio RAM read latency ----
                S_WR_RAM: begin
                    state <= S_WR_HLS;
                end

                // ---- Write: issue HLS write (funct7=0) ----
                S_WR_HLS: begin
                    hls_funct7 <= 8'd0;
                    hls_src1   <= {21'd0, sample_cnt};
                    hls_src2   <= audio_data_i;
                    hls_go     <= 1'b1;
                    state      <= S_WR_WAIT;
                end

                // ---- Write: wait for HLS done ----
                S_WR_WAIT: begin
                    if (ap_done) begin
                        if (sample_cnt == 11'd2047) begin
                            state <= S_COMP_HLS;
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                            state      <= S_WR_ADDR;
                        end
                    end
                end

                // ---- Compute: issue HLS compute (funct7=1) ----
                S_COMP_HLS: begin
                    hls_funct7 <= 8'd1;
                    hls_src1   <= 32'd0;
                    hls_src2   <= 32'd0;
                    hls_go     <= 1'b1;
                    state      <= S_COMP_WAIT;
                end

                // ---- Compute: wait for HLS done ----
                S_COMP_WAIT: begin
                    if (ap_done) begin
                        mel_cnt <= 5'd0;
                        state   <= S_RD_HLS;
                    end
                end

                // ---- Read: issue HLS mel read (funct7=2) ----
                S_RD_HLS: begin
                    hls_funct7 <= 8'd2;
                    hls_src1   <= {27'd0, mel_cnt};
                    hls_src2   <= 32'd0;
                    hls_go     <= 1'b1;
                    state      <= S_RD_WAIT;
                end

                // ---- Read: wait for HLS done, capture result ----
                S_RD_WAIT: begin
                    if (ap_done) begin
                        hls_rslt_latched <= hls_rslt;
                        state            <= S_RD_STORE;
                    end
                end

                // ---- Read: write mel value to output port ----
                S_RD_STORE: begin
                    mel_addr_o <= {mel_cnt, frame_cnt};  // mel_cnt*32 + frame_cnt
                    mel_data_o <= hls_rslt_latched;
                    mel_we_o   <= 1'b1;

                    if (mel_cnt == 5'd31) begin
                        // All mels read for this frame
                        if (frame_cnt == 5'd31) begin
                            state <= S_DONE;
                        end else begin
                            frame_cnt  <= frame_cnt + 1'b1;
                            sample_cnt <= 11'd0;
                            state      <= S_WR_ADDR;
                        end
                    end else begin
                        mel_cnt <= mel_cnt + 1'b1;
                        state   <= S_RD_HLS;
                    end
                end

                // ---- Done ----
                S_DONE: begin
                    done_o <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
