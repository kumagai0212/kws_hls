/* ================================================================
 * m_bnn_inference — BNN (Binary Neural Network) 推論 RTL
 * ----------------------------------------------------------------
 * MelSpectrogram BRAM (31×32) → 5クラス分類結果
 *
 * BiFSMN-BNN モデル構成:
 *   1. Frontend Layer 0: DW Conv(1→1, 5×5, s2) + PW Conv(1→16, 1-bit)
 *   2. Frontend Layer 3: DW Conv(16, 5×5, s2, 1-bit) + PW Conv(16→32, 1-bit)
 *   3. FC1: 256→128, 1-bit, ×8 timesteps
 *   4. BiDFSMN: Memory(128, k5, 1-bit) + FC0(128→256) + FC4(256→128)
 *   5. GAP: 128×8 → 128
 *   6. Classifier: 128→5, Q16
 *
 * 共通パターン:
 *   - BNN層: sign(input) XNOR weight → popcount → folding activation
 *   - Folding: sum > T[c] → Apos*sum + Bpos, else Aneg*sum + Bneg
 *
 * バッファ:
 *   buf_A[4096] — メインデータバッファ (最大: Layer0 PW 出力 16×16×16)
 *   buf_B[2048] — セカンダリバッファ (BiDFSMN fc_mid: 256×8)
 *
 * 重み ROM:
 *   bw_rom[3122]     — バイナリ重み (packed uint32_t)
 *   fold_T/Apos/Bpos/Aneg/Bneg[705] — Folding パラメータ
 *   dw0_w_rom[25]    — Layer0 DW 重み (Q16)
 *   cls_w_rom[640]   — Classifier 重み (Q16)
 *   cls_b_rom[5]     — Classifier バイアス (Q16)
 * ================================================================ */
/* verilator lint_off DECLFILENAME */
`include "bnn_addr.vh"

module m_bnn_inference (
    input  wire        clk_i,
    input  wire        rst_i,

    // 制御
    input  wire        start_i,          // MelSpec 完了後の開始トリガ
    output reg         busy_o,
    output reg         done_o,           // 推論完了パルス

    // MelSpec BRAM 読み出しポート
    output reg  [9:0]  mel_rd_addr_o,
    input  wire [31:0] mel_rd_data_i,

    // 分類結果
    output reg  [2:0]  result_class_o,   // argmax クラス (0..4)
    output reg  [31:0] result_logit_o,   // 最大ロジット値 (Q16)

    // Debug: per-class logits (Q16)
    output wire signed [31:0] dbg_logit0_o,
    output wire signed [31:0] dbg_logit1_o,
    output wire signed [31:0] dbg_logit2_o,
    output wire signed [31:0] dbg_logit3_o,
    output wire signed [31:0] dbg_logit4_o,

    // Debug: FSM progress probes
    output wire [5:0]  dbg_state_o,
    output wire [3:0]  dbg_layer_id_o,
    output wire [7:0]  dbg_pack_cnt_o,
    output wire [8:0]  dbg_pack_total_o,
    output wire [2:0]  dbg_pack_word_o,
    output wire [4:0]  dbg_pack_bit_o,
    output wire [6:0]  dbg_gap_ch_o,
    output wire [2:0]  dbg_gap_t_o,
    output wire [2:0]  dbg_cls_oc_o,
    output wire [7:0]  dbg_cls_ic_o
);

    // ================================================================
    // パラメータ定義
    // ================================================================
    localparam IN_H = 32, IN_W = 32;
    localparam OUT1_H = 16, OUT1_W = 16;
    localparam OUT2_H = 8,  OUT2_W = 8;
    localparam KH = 5, KW = 5, PAD = 2, STRIDE = 2;
    localparam CONV1_CH = 16, CONV2_CH = 32;
    localparam FC1_IN = 256, FC1_OUT = 128;
    localparam TIME_STEPS = 8;
    localparam BB_CH = 128, BB_MID = 256, BB_K = 5, BB_PAD = 2;
    localparam N_CLS = 5;
    localparam Q16 = 65536;

    // ================================================================
    // 重み ROM
    // ================================================================

    // バイナリ重み ROM (packed bits)
    reg [31:0] bw_rom [0:4095];
    initial $readmemh("bnn_bw.hex", bw_rom);
    reg [11:0] bw_addr;
    reg [31:0] bw_data;
    always @(posedge clk_i) bw_data <= bw_rom[bw_addr];

    // Folding パラメータ ROM (5 並列ポート)
    reg signed [31:0] fold_T_rom    [0:1023];
    reg signed [31:0] fold_Apos_rom [0:1023];
    reg signed [31:0] fold_Bpos_rom [0:1023];
    reg signed [31:0] fold_Aneg_rom [0:1023];
    reg signed [31:0] fold_Bneg_rom [0:1023];
    initial begin
        $readmemh("bnn_fold_T.hex",    fold_T_rom);
        $readmemh("bnn_fold_Apos.hex", fold_Apos_rom);
        $readmemh("bnn_fold_Bpos.hex", fold_Bpos_rom);
        $readmemh("bnn_fold_Aneg.hex", fold_Aneg_rom);
        $readmemh("bnn_fold_Bneg.hex", fold_Bneg_rom);
    end
    reg [9:0]  fold_addr;
    reg signed [31:0] fold_T, fold_Ap, fold_Bp, fold_An, fold_Bn;
    always @(posedge clk_i) begin
        fold_T  <= fold_T_rom[fold_addr];
        fold_Ap <= fold_Apos_rom[fold_addr];
        fold_Bp <= fold_Bpos_rom[fold_addr];
        fold_An <= fold_Aneg_rom[fold_addr];
        fold_Bn <= fold_Bneg_rom[fold_addr];
    end

    // Layer0 DW 重み ROM (Q16)
    reg signed [31:0] dw0_w_rom [0:31];
    initial $readmemh("bnn_dw0_w.hex", dw0_w_rom);

    // Classifier 重み & バイアス ROM (Q16)
    reg signed [31:0] cls_w_rom [0:1023];
    reg signed [31:0] cls_b_rom [0:7];
    initial begin
        $readmemh("bnn_cls_w.hex", cls_w_rom);
        $readmemh("bnn_cls_b.hex", cls_b_rom);
    end
    reg [9:0]  cls_w_addr;
    reg signed [31:0] cls_w_data;
    always @(posedge clk_i) cls_w_data <= cls_w_rom[cls_w_addr];

    // ================================================================
    // データバッファ
    // ================================================================
    reg signed [31:0] buf_A [0:4095];  // メインバッファ
    reg signed [31:0] buf_B [0:2047];  // セカンダリバッファ

    // buf_A Port A: write
    reg        ba_we;
    reg [11:0] ba_waddr;
    reg signed [31:0] ba_wdata;
    always @(posedge clk_i) if (ba_we) buf_A[ba_waddr] <= ba_wdata;

    // buf_A Port B: read
    reg [11:0] ba_raddr;
    reg signed [31:0] ba_rdata;
    always @(posedge clk_i) ba_rdata <= buf_A[ba_raddr];

    // buf_B Port A: write
    reg        bb_we;
    reg [10:0] bb_waddr;
    reg signed [31:0] bb_wdata;
    always @(posedge clk_i) if (bb_we) buf_B[bb_waddr] <= bb_wdata;

    // buf_B Port B: read
    reg [10:0] bb_raddr;
    reg signed [31:0] bb_rdata;
    always @(posedge clk_i) bb_rdata <= buf_B[bb_raddr];

    // ================================================================
    // Popcount (32-bit) — 組合せ回路
    // ================================================================
    function [5:0] popcount32;
        input [31:0] x;
        integer i;
        begin
            popcount32 = 0;
            for (i = 0; i < 32; i = i + 1)
                popcount32 = popcount32 + x[i];
        end
    endfunction

    // ================================================================
    // Folding 演算: safe_shift_right(A * sum) + B
    // パイプライン: fold_addr → 1clk → fold_T/Ap/Bp/An/Bn valid
    //               → 比較 + 乗算(1clk) → 加算 + 出力(1clk)
    // ================================================================
    reg signed [31:0] fold_sum_q16;    // 入力 sum (Q16)
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [63:0] fold_prod_pos = $signed(fold_Ap) * fold_sum_q16;
    wire signed [63:0] fold_prod_neg = $signed(fold_An) * fold_sum_q16;
    /* verilator lint_on UNUSEDSIGNAL */

    // safe_shift_right: (val + 32768) >> 16 for non-negative, (val + 32767) >> 16 for negative
    wire signed [31:0] fold_shifted_pos = (fold_prod_pos >= 0)
        ? (fold_prod_pos + 64'sd32768) >>> 16
        : (fold_prod_pos + 64'sd32767) >>> 16;
    wire signed [31:0] fold_shifted_neg = (fold_prod_neg >= 0)
        ? (fold_prod_neg + 64'sd32768) >>> 16
        : (fold_prod_neg + 64'sd32767) >>> 16;

    wire signed [31:0] fold_result = (fold_sum_q16 > fold_T)
        ? (fold_shifted_pos + fold_Bp)
        : (fold_shifted_neg + fold_Bn);

    // ================================================================
    // メイン FSM
    // ================================================================
    localparam [5:0]
        S_IDLE    = 6'd0,
        // Layer 0 DW
        S_L0DW_INIT  = 6'd1,
        S_L0DW_ADDR  = 6'd2,
        S_L0DW_WAIT  = 6'd3,
        S_L0DW_MAC   = 6'd4,
        S_L0DW_FOLD1 = 6'd5,
        S_L0DW_FOLD2 = 6'd6,
        // Layer 0 PW
        S_L0PW_INIT  = 6'd7,
        S_L0PW_RD    = 6'd8,
        S_L0PW_FOLD1 = 6'd9,
        S_L0PW_FOLD2 = 6'd10,
        // Generic BNN layer (Layer3, FC1, BiDFSMN, etc.)
        S_BNN_INIT   = 6'd11,
        S_BNN_PACK   = 6'd12,   // sign bit packing / element read
        S_BNN_PACK_W = 6'd13,   // wait for BRAM read
        S_BNN_XNOR   = 6'd14,   // XNOR + popcount (element-wise)
        S_BNN_XNOR_W = 6'd15,   // pack sign bit from read data
        S_BNN_FOLD1  = 6'd16,
        S_BNN_FOLD2  = 6'd17,
        S_BNN_FOLD_WAIT = 6'd34,
        // FC-type XNOR+popcount (word-level)
        S_FC_XNOR_WAIT = 6'd18, // wait for bw_rom read
        S_FC_XNOR_ACC  = 6'd19, // XNOR+popcount accumulate
        // GAP
        S_GAP_INIT   = 6'd20,
        S_GAP_RD     = 6'd21,
        S_GAP_WAIT   = 6'd22,
        S_GAP_ACC    = 6'd23,
        // Classifier
        S_CLS_INIT   = 6'd24,
        S_CLS_RD     = 6'd25,
        S_CLS_WAIT   = 6'd26,
        S_CLS_MAC    = 6'd27,
        S_CLS_DONE   = 6'd28,
        // Residual add
        S_RES_INIT   = 6'd29,
        S_RES_RD     = 6'd30,
        S_RES_WAIT   = 6'd31,
        S_RES_ADD    = 6'd32,
        S_L0PW_CALC  = 6'd33,
        // Done
        S_DONE       = 6'd63;

    reg [5:0] state;

    // --- 層シーケンサ ---
    // 層番号: 0=L0DW, 1=L0PW, 2=L3DW, 3=L3PW, 4=FC1,
    //         5=BB_MEM, 6=BB_RES1, 7=BB_FC0, 8=BB_FC4, 9=BB_RES2,
    //         10=GAP, 11=CLS
    reg [3:0] layer_id;

    // --- 汎用ループカウンタ ---
    reg [4:0]  oh, ow;           // 出力 h, w (conv 用)
    reg [2:0]  kh, kw;           // カーネル h, w
    reg [4:0]  oc_h;             // 出力チャネル (上位)
    reg [7:0]  oc;               // 出力チャネル
    reg [7:0]  ic;               // 入力チャネル
    reg [2:0]  t_step;           // timestep (0..7)
    reg [3:0]  w_idx;            // weight word index

    // --- アキュムレータ ---
    reg signed [63:0] acc64;      // Q16 MAC 用
    reg signed [15:0] xnor_sum;   // BNN XNOR+popcount 用

    // --- sign bit packing ---
    reg [31:0] sign_packed [0:7]; // 最大 256 bit (8 words)
    reg [7:0]  pack_cnt;          // packing counter
    reg [8:0]  pack_total;        // 何個パックするか (up to 256)
    reg [4:0]  pack_bit;          // current bit position in word
    reg [2:0]  pack_word;         // current word index

    // --- BNN 層パラメータ (層ごとに設定) ---
    reg [11:0] bnn_w_base;        // bw_rom base address
    reg [9:0]  bnn_fold_base;     // fold_rom base address
    reg [7:0]  bnn_n_out;         // output neurons
    reg [7:0]  bnn_n_in;          // input size (per output)
    reg [3:0]  bnn_n_words;      // n_in / 32 (up to 8)

    // --- DW0/classifier 用 ---
    reg [4:0]  dw0_w_idx;         // dw0 weight index
    reg signed [31:0] dw0_w_val;  // latched weight value

    // --- Classifier ---
    reg signed [31:0] logits [0:4];
    reg [2:0]  cls_oc;            // classifier output class
    reg [7:0]  cls_ic;            // classifier input index

    // --- GAP ---
    reg signed [63:0] gap_acc;
    reg [6:0]  gap_ch;
    reg [2:0]  gap_t;
    reg signed [31:0] gap_out [0:127]; // GAP output (128 values)

    // Export internal logits for simulation comparison.
    assign dbg_logit0_o = logits[0];
    assign dbg_logit1_o = logits[1];
    assign dbg_logit2_o = logits[2];
    assign dbg_logit3_o = logits[3];
    assign dbg_logit4_o = logits[4];

    // Export FSM and counters for waveform/log debugging.
    assign dbg_state_o = state;
    assign dbg_layer_id_o = layer_id;
    assign dbg_pack_cnt_o = pack_cnt;
    assign dbg_pack_total_o = pack_total;
    assign dbg_pack_word_o = pack_word;
    assign dbg_pack_bit_o = pack_bit;
    assign dbg_gap_ch_o = gap_ch;
    assign dbg_gap_t_o = gap_t;
    assign dbg_cls_oc_o = cls_oc;
    assign dbg_cls_ic_o = cls_ic;

    // --- Residual ---
    reg [9:0]  res_idx;
    reg [10:0] res_len;
    reg signed [31:0] res_val_a, res_val_b;
    reg        elem_pad;  // 1 when current element is zero-padding (sign bit = 1)

    // ================================================================
    // メイン FSM
    // ================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            state      <= S_IDLE;
            busy_o     <= 0;
            done_o     <= 0;
            ba_we      <= 0;
            bb_we      <= 0;
        end else begin
            done_o <= 0;
            ba_we  <= 0;
            bb_we  <= 0;

            case (state)

            // --------------------------------------------------------
            S_IDLE: begin
                busy_o <= 0;
                if (start_i) begin
                    busy_o   <= 1;
                    layer_id <= 0;   // Start with Layer 0 DW
                    state    <= S_L0DW_INIT;
                end
            end

            // ============================================================
            // Layer 0 Depthwise Conv (Q16 full precision)
            // Input: MelSpec BRAM (32×32, transposed access)
            // Output: buf_B[0..255] (1×16×16)
            // ============================================================
            S_L0DW_INIT: begin
                oh <= 0;
                ow <= 0;
                kh <= 0;
                kw <= 0;
                acc64 <= 0;
                state <= S_L0DW_ADDR;
            end

            S_L0DW_ADDR: begin
                begin : l0dw_addr_blk
                    reg signed [5:0] ih, iw;
                    ih = {1'b0, oh} * STRIDE + {3'b0, kh} - PAD;
                    iw = {1'b0, ow} * STRIDE + {3'b0, kw} - PAD;

                    dw0_w_idx <= kh * KW + kw;

                    if (ih >= 0 && ih < IN_H && iw >= 0 && iw < IN_W) begin
                        // Match C reference indexing: input[in_h * IN_WIDTH + in_w]
                        mel_rd_addr_o <= ih[4:0] * 6'd32 + iw[4:0];
                        state <= S_L0DW_WAIT;
                    end else begin
                        // Zero padding — skip this kernel position
                        if (kw == KW - 1) begin
                            if (kh == KH - 1) begin
                                state <= S_L0DW_FOLD1;
                            end else begin
                                kh <= kh + 1;
                                kw <= 0;
                            end
                        end else begin
                            kw <= kw + 1;
                        end
                    end
                end
            end

            S_L0DW_WAIT: begin
                dw0_w_val <= dw0_w_rom[dw0_w_idx];
                state <= S_L0DW_MAC;
            end

            S_L0DW_MAC: begin
                acc64 <= acc64 + $signed(mel_rd_data_i) * dw0_w_val;

                if (kw == KW - 1) begin
                    if (kh == KH - 1) begin
                        state <= S_L0DW_FOLD1;
                    end else begin
                        kh <= kh + 1;
                        kw <= 0;
                        state <= S_L0DW_ADDR;
                    end
                end else begin
                    kw <= kw + 1;
                    state <= S_L0DW_ADDR;
                end
            end

            // Folding (fe_0_dw): fold_addr = FOLD_FE_0_DW + 0 = 0
            S_L0DW_FOLD1: begin
                // Match C safe_shift_right exactly: division truncates toward zero.
                fold_sum_q16 <= (acc64 >= 0)
                    ? (acc64 + 64'sd32768) / 64'sd65536
                    : (acc64 - 64'sd32768) / 64'sd65536;
                fold_addr <= `FOLD_FE_0_DW;
                state <= S_L0DW_FOLD2;
            end

            S_L0DW_FOLD2: begin
                // fold_T/Ap/Bp/An/Bn now valid (1 clk latency)
                // fold_result is combinational from fold_sum_q16 and fold params
                bb_we    <= 1;
                bb_waddr <= {3'd0, oh} * OUT1_W + {3'd0, ow};
                bb_wdata <= fold_result;

                // Next output pixel
                acc64 <= 0;
                kh <= 0;
                kw <= 0;
                if (ow == OUT1_W - 1) begin
                    ow <= 0;
                    if (oh == OUT1_H - 1) begin
                        // Layer 0 DW done → Layer 0 PW
                        state <= S_L0PW_INIT;
                    end else begin
                        oh <= oh + 1;
                        state <= S_L0DW_ADDR;
                    end
                end else begin
                    ow <= ow + 1;
                    state <= S_L0DW_ADDR;
                end
            end

            // ============================================================
            // Layer 0 Pointwise Conv (1-bit XNOR, 1→16 channels)
            // Input: buf_B[0..255] (1×16×16, DW folded output)
            // Output: buf_A[0..4095] (16×16×16)
            //
            // 特殊: 入力チャネル=1 なので XNOR は 1 bit のみ
            // sum = (sign(input) == weight_bit) ? +1 : -1
            // sum_q16 = sum * 65536
            // ============================================================
            S_L0PW_INIT: begin
                oc <= 0;
                oh <= 0;
                ow <= 0;
                state <= S_L0PW_RD;
            end

            S_L0PW_RD: begin
                // Read DW output from buf_B
                bb_raddr <= {3'd0, oh} * OUT1_W + {3'd0, ow};
                // Read PW weight (1 word, oc-th bit)
                bw_addr <= `BW_FE_0_PW_W;
                // Preload fold params for current oc to match ROM 1-cycle latency.
                fold_addr <= `FOLD_FE_0_PW + oc[3:0];
                state <= S_L0PW_FOLD1;
            end

            S_L0PW_FOLD1: begin
                // One-cycle wait for synchronous bb_rdata / fold ROM outputs.
                state <= S_L0PW_CALC;
            end

            S_L0PW_CALC: begin
                // bb_rdata and bw_data now valid
                begin : l0pw_blk
                    reg in_bit, w_bit;
                    reg signed [31:0] sum_val;
                    in_bit = (bb_rdata >= 0) ? 1'b1 : 1'b0;  // sign activation
                    w_bit  = bw_data[oc[4:0]];                // weight bit for this output channel
                    sum_val = (in_bit == w_bit) ? 32'sd65536 : -32'sd65536;

                    fold_sum_q16 <= sum_val;
                end
                state <= S_L0PW_FOLD2;
            end

            S_L0PW_FOLD2: begin
                // Write folded result to buf_A
                ba_we    <= 1;
                ba_waddr <= {4'd0, oc[3:0]} * (OUT1_H * OUT1_W) + {4'd0, oh} * OUT1_W + {4'd0, ow};
                ba_wdata <= fold_result;

                // Next output
                if (ow == OUT1_W - 1) begin
                    ow <= 0;
                    if (oh == OUT1_H - 1) begin
                        oh <= 0;
                        if (oc == CONV1_CH - 1) begin
                            // Layer 0 PW done → Layer 3 DW (BNN)
                            layer_id <= 2;
                            state <= S_BNN_INIT;
                        end else begin
                            oc <= oc + 1;
                            state <= S_L0PW_RD;
                        end
                    end else begin
                        oh <= oh + 1;
                        state <= S_L0PW_RD;
                    end
                end else begin
                    ow <= ow + 1;
                    state <= S_L0PW_RD;
                end
            end

            // ============================================================
            // Generic BNN Layer Engine
            // ============================================================
            // layer_id 2: L3 DW  (16 ch depthwise, per-channel 5×5 → 8×8)
            // layer_id 3: L3 PW  (16→32, 16 inputs per output)
            // layer_id 4: FC1    (256→128, ×8 timesteps)
            // layer_id 5: BB_MEM (128 ch, kernel 5, ×8 timesteps)
            // layer_id 7: BB_FC0 (128→256, ×8 timesteps)
            // layer_id 8: BB_FC4 (256→128, ×8 timesteps)
            //
            // 共通フロー:
            //   INIT → PACK (sign bit extraction) → XNOR (xnor+popcount)
            //   → FOLD → write output → next neuron
            // ============================================================
            S_BNN_INIT: begin
                oc <= 0;
                oh <= 0;
                ow <= 0;
                t_step <= 0;

                case (layer_id)
                4'd2: begin  // Layer 3 DW
                    // Depthwise: 16 channels, each 5×5 kernel, stride 2
                    // We process using the per-bit approach (not packing, since kernel=25)
                    ic <= 0;    // channel counter (used as oc for DW)
                    kh <= 0;
                    kw <= 0;
                    xnor_sum <= 0;
                    bnn_fold_base <= `FOLD_FE_3_DW;
                end
                4'd3: begin  // Layer 3 PW (element-wise, 16 inputs per output)
                    bnn_fold_base <= `FOLD_FE_3_PW;
                    bnn_n_out     <= CONV2_CH;  // 32
                    ic <= 0;
                    xnor_sum <= 0;
                    elem_pad <= 0;
                end
                4'd4: begin  // FC1
                    bnn_w_base    <= `BW_FC1_0_W;
                    bnn_fold_base <= `FOLD_FC1_0;
                    bnn_n_out     <= FC1_OUT;   // 128
                    bnn_n_in      <= FC1_IN;    // 256
                    bnn_n_words   <= FC1_IN / 32; // 8
                end
                4'd5: begin  // BB Memory
                    bnn_w_base    <= `BW_BB_0_MEM_W;
                    bnn_fold_base <= `FOLD_BB_0_MEM;
                    bnn_n_out     <= BB_CH;     // 128
                    kw <= 0;
                    xnor_sum <= 0;
                    elem_pad <= 0;
                end
                4'd7: begin  // BB FC0
                    bnn_w_base    <= `BW_BB_0_FC0_W;
                    bnn_fold_base <= `FOLD_BB_0_FC0;
                    bnn_n_out     <= BB_MID;    // 256
                    bnn_n_in      <= BB_CH;     // 128
                    bnn_n_words   <= BB_CH / 32; // 4
                end
                4'd8: begin  // BB FC4
                    bnn_w_base    <= `BW_BB_0_FC4_W;
                    bnn_fold_base <= `FOLD_BB_0_FC4;
                    bnn_n_out     <= BB_CH;     // 128
                    bnn_n_in      <= BB_MID;    // 256
                    bnn_n_words   <= BB_MID / 32; // 8
                end
                default: ;
                endcase

                // Element-wise layers: L3DW, L3PW, BB_MEM
                if (layer_id == 4'd2 || layer_id == 4'd3 || layer_id == 4'd5) begin
                    state <= S_BNN_PACK;
                end else begin
                    // FC-type layers: start sign packing
                    pack_cnt   <= 0;
                    pack_total <= (layer_id == 4'd4) ? FC1_IN :
                                  (layer_id == 4'd7) ? BB_CH : BB_MID;
                    pack_bit   <= 0;
                    pack_word  <= 0;
                    sign_packed[0] <= 0;
                    state <= S_BNN_PACK;
                end
            end

            // --------------------------------------------------------
            // Sign bit packing / direct element reading
            // --------------------------------------------------------
            S_BNN_PACK: begin
                case (layer_id)
                // --- Layer 3 DW: Read element from buf_A ---
                4'd2: begin
                    begin : l3dw_rd_blk
                        reg signed [5:0] ih_l3, iw_l3;
                        ih_l3 = {1'b0, oh} * STRIDE + {3'b0, kh} - PAD;
                        iw_l3 = {1'b0, ow} * STRIDE + {3'b0, kw} - PAD;

                        if (ih_l3 >= 0 && ih_l3 < OUT1_H &&
                            iw_l3 >= 0 && iw_l3 < OUT1_W) begin
                            // buf_A[c * 256 + ih * 16 + iw]
                            ba_raddr <= {4'd0, ic[3:0]} * (OUT1_H * OUT1_W)
                                      + ih_l3[4:0] * OUT1_W + iw_l3[4:0];
                            // weight bit
                            begin : l3dw_wbit_blk
                                reg [8:0] widx;
                                widx = {1'b0, ic[3:0], 4'd0} + ic[3:0] * 4'd9
                                     + kh * KW + kw;  // ic*25 + kh*5 + kw
                                bw_addr <= `BW_FE_3_DW_W + widx[8:5];
                            end
                            elem_pad <= 0;
                            state <= S_BNN_PACK_W;
                        end else begin
                            // Padding taps are skipped to match C reference behavior.
                            begin : l3dw_pad_blk
                                reg [8:0] widx_p;
                                widx_p = ic * 5'd25 + {5'd0, kh} * KW + {5'd0, kw};
                                bw_addr <= `BW_FE_3_DW_W + widx_p[8:5];
                            end
                            elem_pad <= 1;
                            state <= S_BNN_PACK_W;
                        end
                    end
                end

                // --- L3 PW: Read input element from buf_B + weight word ---
                4'd3: begin
                    // buf_B[ic * 64 + oh * 8 + ow] = L3 DW output
                    bb_raddr <= {3'd0, ic[3:0]} * (OUT2_H * OUT2_W)
                              + {3'd0, oh} * OUT2_W + {3'd0, ow};
                    // Weight word: fe_3_pw_w[oc/2] (2 outputs per word)
                    bw_addr <= `BW_FE_3_PW_W + {8'd0, oc[4:1]};
                    state <= S_BNN_PACK_W;
                end

                // --- BB Memory: Read element from buf_B ---
                4'd5: begin
                    begin : bbmem_rd_blk
                        reg signed [4:0] in_t;
                        in_t = $signed({1'b0, t_step}) + $signed({2'b00, kw}) - $signed(BB_PAD);

                        if (in_t >= 0 && in_t < TIME_STEPS) begin
                            // buf_B[c * 8 + in_t]
                            bb_raddr <= {3'd0, oc[6:0]} * TIME_STEPS + in_t[2:0];
                            // weight index: c * 5 + k
                            begin : bbmem_wbit_blk
                                reg [9:0] widx;
                                widx = oc * 3'd5 + {7'd0, kw[2:0]};
                                bw_addr <= `BW_BB_0_MEM_W + widx[9:5];
                            end
                            elem_pad <= 0;
                            state <= S_BNN_PACK_W;
                        end else begin
                            // Pad with 0: sign(0)=1 still participates in XNOR sum.
                            begin : bbmem_pad_blk
                                reg [9:0] widx_p;
                                widx_p = oc * 3'd5 + {7'd0, kw[2:0]};
                                bw_addr <= `BW_BB_0_MEM_W + widx_p[9:5];
                            end
                            elem_pad <= 1;
                            state <= S_BNN_PACK_W;
                        end
                    end
                end

                // --- FC-type layers: Pack sign bits ---
                default: begin
                    // Read input value for sign extraction
                    case (layer_id)
                    4'd4: begin  // FC1: read buf_A[in_c * TIME_STEPS + t_step]
                        ba_raddr <= {4'd0, pack_cnt} * TIME_STEPS + {9'd0, t_step};
                    end
                    4'd7: begin  // BB FC0: read buf_A[ic * TIME_STEPS + t_step]
                        ba_raddr <= {4'd0, pack_cnt[6:0]} * TIME_STEPS + {9'd0, t_step};
                    end
                    4'd8: begin  // BB FC4: read buf_A[ic * TIME_STEPS + t_step]
                        // FC4 input is FC0 output stored at buf_A[1024..3071]
                        ba_raddr <= 12'd1024 + {4'd0, pack_cnt} * TIME_STEPS + {9'd0, t_step};
                    end
                    default: ;
                    endcase
                    state <= S_BNN_PACK_W;
                end
                endcase
            end

            // --------------------------------------------------------
            S_BNN_PACK_W: begin
                // Wait 1 clock for BRAM read
                // Element-wise layers → S_BNN_XNOR, FC-type → S_BNN_XNOR_W (packing)
                state <= (layer_id == 4'd2 || layer_id == 4'd3 || layer_id == 4'd5)
                       ? S_BNN_XNOR : S_BNN_XNOR_W;
            end

            // --------------------------------------------------------
            // Element-wise XNOR: L3DW, L3PW, BB_MEM
            S_BNN_XNOR: begin
                case (layer_id)
                // --- L3 DW: single element XNOR ---
                4'd2: begin
                    begin : l3dw_xnor_blk
                        reg in_bit, w_bit;
                        reg [8:0] widx;
                        in_bit = (ba_rdata >= 0) ? 1'b1 : 1'b0;
                        widx = ic * 5'd25 + {5'd0, kh} * KW + {5'd0, kw};
                        w_bit = bw_data[widx[4:0]];
                        if (elem_pad)
                            xnor_sum <= xnor_sum;
                        else if (in_bit == w_bit)
                            xnor_sum <= xnor_sum + 1;
                        else
                            xnor_sum <= xnor_sum - 1;
                    end

                    // Advance kernel
                    if (kw == KW - 1) begin
                        kw <= 0;
                        if (kh == KH - 1) begin
                            state <= S_BNN_FOLD1;
                        end else begin
                            kh <= kh + 1;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        kw <= kw + 1;
                        state <= S_BNN_PACK;
                    end
                end

                // --- L3 PW: single element XNOR (16 inputs per output) ---
                4'd3: begin
                    begin : l3pw_xnor_blk
                        reg in_bit, w_bit;
                        in_bit = (bb_rdata >= 0) ? 1'b1 : 1'b0;
                        // Weight: flat packing, bit = {oc[0], ic[3:0]}
                        // oc even → bits 0..15, oc odd → bits 16..31
                        w_bit = bw_data[{oc[0], ic[3:0]}];
                        if (in_bit == w_bit)
                            xnor_sum <= xnor_sum + 1;
                        else
                            xnor_sum <= xnor_sum - 1;
                    end

                    // Advance input channel
                    if (ic == CONV1_CH - 1) begin
                        state <= S_BNN_FOLD1;
                    end else begin
                        ic <= ic + 1;
                        state <= S_BNN_PACK;
                    end
                end

                // --- BB Memory: single element XNOR ---
                4'd5: begin
                    begin : bbmem_xnor_blk
                        reg in_bit, w_bit;
                        reg [9:0] widx;
                        in_bit = elem_pad ? 1'b1 : ((bb_rdata >= 0) ? 1'b1 : 1'b0);
                        widx = oc * 3'd5 + {7'd0, kw[2:0]};
                        w_bit = bw_data[widx[4:0]];
                        if (in_bit == w_bit)
                            xnor_sum <= xnor_sum + 1;
                        else
                            xnor_sum <= xnor_sum - 1;
                    end

                    if (kw == BB_K - 1) begin
                        state <= S_BNN_FOLD1;
                    end else begin
                        kw <= kw + 1;
                        state <= S_BNN_PACK;
                    end
                end

                default: ;
                endcase
            end

            // --------------------------------------------------------
            // FC-type: extract sign bit and pack, then XNOR+popcount
            S_BNN_XNOR_W: begin
                // Pack sign bit from read data
                begin : pack_sign_blk
                    reg in_bit;
                    reg signed [31:0] rd_val;

                    // Select data source (FC-type layers read from buf_A)
                    rd_val = ba_rdata;
                    in_bit = (rd_val >= 0) ? 1'b1 : 1'b0;

                    sign_packed[pack_word] <= sign_packed[pack_word] | ({31'd0, in_bit} << pack_bit);
                end

                pack_cnt <= pack_cnt + 1;

                if (pack_bit == 5'd31) begin
                    pack_bit  <= 0;
                    pack_word <= pack_word + 1;
                    if (pack_cnt + 1 < pack_total)
                        sign_packed[pack_word + 1] <= 0;
                end else begin
                    pack_bit <= pack_bit + 1;
                end

                if (pack_cnt + 1 == pack_total) begin
                    // All sign bits packed — start FC-type XNOR+popcount
                    xnor_sum <= 0;
                    w_idx    <= 0;
                    // Read first weight word
                    bw_addr <= bnn_w_base + {4'd0, oc} * bnn_n_words;
                    state   <= S_FC_XNOR_WAIT;
                end else begin
                    state <= S_BNN_PACK;
                end
            end

            // --------------------------------------------------------
            // FC-type XNOR+popcount engine (word-level)
            // After sign packing, iterate over weight words:
            //   XNOR sign_packed[w_idx] with bw_data, popcount, accumulate
            // --------------------------------------------------------
            S_FC_XNOR_WAIT: begin
                // Wait 1 clock for bw_rom read latency
                state <= S_FC_XNOR_ACC;
            end

            S_FC_XNOR_ACC: begin
                // XNOR + popcount for current word
                begin : fc_xnor_blk
                    reg [31:0] xnor_word;
                    reg [5:0]  pop;
                    xnor_word = ~(sign_packed[w_idx] ^ bw_data);
                    pop = popcount32(xnor_word);
                    // sum += 2*matches - 32 (per 32-bit word)
                    xnor_sum <= xnor_sum + $signed({10'd0, pop, 1'b0}) - 16'sd32;
                end

                if (w_idx + 1 == bnn_n_words) begin
                    // All words processed → fold
                    state <= S_BNN_FOLD1;
                end else begin
                    w_idx   <= w_idx + 1;
                    bw_addr <= bw_addr + 12'd1;
                    state   <= S_FC_XNOR_WAIT;
                end
            end

            // --------------------------------------------------------
            // Folding Stage 1: Load fold params + compute fold_sum_q16
            S_BNN_FOLD1: begin
                fold_sum_q16 <= xnor_sum * 32'sd65536;

                case (layer_id)
                4'd2: fold_addr <= bnn_fold_base + ic[3:0];         // fe_3_dw
                4'd3: fold_addr <= bnn_fold_base + {2'd0, oc[4:0]}; // fe_3_pw
                4'd4: fold_addr <= bnn_fold_base + {2'd0, oc[6:0]}; // fc1_0
                4'd5: fold_addr <= bnn_fold_base + {2'd0, oc[6:0]}; // bb_0_mem
                4'd7: fold_addr <= bnn_fold_base + {2'd0, oc};      // bb_0_fc0
                4'd8: fold_addr <= bnn_fold_base + {2'd0, oc[6:0]}; // bb_0_fc4
                default: ;
                endcase
                // fold_* regs are loaded synchronously, so wait one cycle.
                state <= S_BNN_FOLD_WAIT;
            end

            S_BNN_FOLD_WAIT: begin
                state <= S_BNN_FOLD2;
            end

            // --------------------------------------------------------
            // Folding Stage 2: Write folded result
            S_BNN_FOLD2: begin
                case (layer_id)
                // L3 DW: write buf_B[c * 64 + oh * 8 + ow]
                4'd2: begin
                    bb_we    <= 1;
                    bb_waddr <= {3'd0, ic[3:0]} * (OUT2_H * OUT2_W)
                              + {3'd0, oh} * OUT2_W + {3'd0, ow};
                    bb_wdata <= fold_result;

                    xnor_sum <= 0;
                    kh <= 0; kw <= 0;

                    if (ow == OUT2_W - 1) begin
                        ow <= 0;
                        if (oh == OUT2_H - 1) begin
                            oh <= 0;
                            if (ic == CONV1_CH - 1) begin
                                // L3 DW done → L3 PW
                                layer_id <= 3;
                                state    <= S_BNN_INIT;
                            end else begin
                                ic <= ic + 1;
                                state <= S_BNN_PACK;
                            end
                        end else begin
                            oh <= oh + 1;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        ow <= ow + 1;
                        state <= S_BNN_PACK;
                    end
                end

                // L3 PW: write buf_A[oc * 64 + oh * 8 + ow]
                4'd3: begin
                    ba_we    <= 1;
                    ba_waddr <= {4'd0, oc[4:0]} * (OUT2_H * OUT2_W)
                              + {4'd0, oh[2:0]} * OUT2_W + {4'd0, ow[2:0]};
                    ba_wdata <= fold_result;

                    // Reset element-wise counters for next output
                    ic       <= 0;
                    xnor_sum <= 0;

                    if (ow == OUT2_W - 1) begin
                        ow <= 0;
                        if (oh == OUT2_H - 1) begin
                            oh <= 0;
                            if (oc == CONV2_CH - 1) begin
                                // L3 PW done → FC1
                                layer_id <= 4;
                                state    <= S_BNN_INIT;
                            end else begin
                                oc <= oc + 1;
                                state <= S_BNN_PACK;
                            end
                        end else begin
                            oh <= oh + 1;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        ow <= ow + 1;
                        state <= S_BNN_PACK;
                    end
                end

                // FC1: write buf_B[t * FC1_OUT + oc] → then transpose to buf_B[oc * 8 + t]
                4'd4: begin
                    // Store transposed: output[n * TIME_STEPS + t]
                    bb_we    <= 1;
                    bb_waddr <= {4'd0, oc[6:0]} * TIME_STEPS + {8'd0, t_step};
                    bb_wdata <= fold_result;

                    if (oc == FC1_OUT - 1) begin
                        oc <= 0;
                        if (t_step == TIME_STEPS - 1) begin
                            // FC1 done → BB Memory
                            layer_id <= 5;
                            state    <= S_BNN_INIT;
                        end else begin
                            t_step <= t_step + 1;
                            pack_cnt   <= 0;
                            pack_bit   <= 0;
                            pack_word  <= 0;
                            sign_packed[0] <= 0;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        oc <= oc + 1;
                        pack_cnt   <= 0;
                        pack_bit   <= 0;
                        pack_word  <= 0;
                        sign_packed[0] <= 0;
                        state <= S_BNN_PACK;
                    end
                end

                // BB Memory: write buf_A[c * 8 + t]
                4'd5: begin
                    ba_we    <= 1;
                    ba_waddr <= {5'd0, oc[6:0]} * TIME_STEPS + {9'd0, t_step};
                    ba_wdata <= fold_result;

                    xnor_sum <= 0;
                    kw <= 0;

                    if (t_step == TIME_STEPS - 1) begin
                        t_step <= 0;
                        if (oc == BB_CH - 1) begin
                            // BB Memory done → Residual 1
                            layer_id <= 6;
                            state    <= S_RES_INIT;
                        end else begin
                            oc <= oc + 1;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        t_step <= t_step + 1;
                        state  <= S_BNN_PACK;
                    end
                end

                // BB FC0: write buf_A[oc * 8 + t]  (overwrite, using buf_A[0..2047])
                4'd7: begin
                    ba_we    <= 1;
                    // Keep memory_out input intact in buf_A[0..1023].
                    // Place FC0 output into buf_A[1024..3071].
                    ba_waddr <= 12'd1024 + {4'd0, oc} * TIME_STEPS + {9'd0, t_step};
                    ba_wdata <= fold_result;

                    if (oc == BB_MID - 1) begin
                        oc <= 0;
                        if (t_step == TIME_STEPS - 1) begin
                            // BB FC0 done → BB FC4
                            layer_id <= 8;
                            state    <= S_BNN_INIT;
                        end else begin
                            t_step <= t_step + 1;
                            pack_cnt   <= 0;
                            pack_bit   <= 0;
                            pack_word  <= 0;
                            sign_packed[0] <= 0;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        oc <= oc + 1;
                        pack_cnt   <= 0;
                        pack_bit   <= 0;
                        pack_word  <= 0;
                        sign_packed[0] <= 0;
                        state <= S_BNN_PACK;
                    end
                end

                // BB FC4: write buf_B[oc * 8 + t]
                4'd8: begin
                    bb_we    <= 1;
                    bb_waddr <= {4'd0, oc[6:0]} * TIME_STEPS + {8'd0, t_step};
                    bb_wdata <= fold_result;

                    if (oc == BB_CH - 1) begin
                        oc <= 0;
                        if (t_step == TIME_STEPS - 1) begin
                            // BB FC4 done → Residual 2
                            layer_id <= 9;
                            state    <= S_RES_INIT;
                        end else begin
                            t_step <= t_step + 1;
                            pack_cnt   <= 0;
                            pack_bit   <= 0;
                            pack_word  <= 0;
                            sign_packed[0] <= 0;
                            state <= S_BNN_PACK;
                        end
                    end else begin
                        oc <= oc + 1;
                        pack_cnt   <= 0;
                        pack_bit   <= 0;
                        pack_word  <= 0;
                        sign_packed[0] <= 0;
                        state <= S_BNN_PACK;
                    end
                end

                default: state <= S_IDLE;
                endcase
            end

            // ============================================================
            // Residual Addition
            // ============================================================
            // layer_id 6: BB_RES1 → buf_A[i] += buf_B[i] for i in 0..1023
            //   (buf_A = memory_out, buf_B = fc1 output = original input)
            // layer_id 9: BB_RES2 → buf_A[i] = buf_B[i] + buf_A_saved[i]
            //   buf_B = fc4 output, buf_A saved via separate mechanism
            //   Actually, for RES2 we need memory_out+input (buf_B from FC1)
            //   But buf_B was overwritten by FC4... need different approach
            //
            // Re-design for RES2:
            //   After FC0 done, buf_A[0..2047] has fc_mid
            //   After FC4 done, buf_B[0..1023] has fc_out
            //   We need memory_out+input which was in buf_A[0..1023] before FC0
            //   But FC0 overwrote buf_A!
            //
            // Solution: Use buf_A[2048..3071] to save memory_out+input before FC0
            // ============================================================
            S_RES_INIT: begin
                res_idx <= 0;
                res_len <= (layer_id == 4'd6 || layer_id == 4'd9) ? 11'd1024 : 11'd0;
                state   <= S_RES_RD;
            end

            S_RES_RD: begin
                case (layer_id)
                4'd6: begin  // RES1: read buf_A[i] (memory_out) and buf_B[i] (fc1_input)
                    ba_raddr <= {2'd0, res_idx};
                    bb_raddr <= {1'b0, res_idx};
                end
                4'd9: begin  // RES2: read buf_B[i] (fc4_out) and buf_A[2048+i] (saved memory_out)
                    bb_raddr <= {1'b0, res_idx};
                    ba_raddr <= 12'd3072 + {2'd0, res_idx};
                end
                4'd10: begin // Copy: read buf_A[i]
                    ba_raddr <= {2'd0, res_idx};
                end
                default: ;
                endcase
                state <= S_RES_WAIT;
            end

            S_RES_WAIT: begin
                state <= S_RES_ADD;
            end

            S_RES_ADD: begin
                case (layer_id)
                4'd6: begin  // RES1: buf_A[i] = memory_out + input
                    ba_we    <= 1;
                    ba_waddr <= {2'd0, res_idx};
                    ba_wdata <= ba_rdata + bb_rdata;
                end
                4'd9: begin  // RES2: buf_A[i] = fc4_out + saved_memory_out
                    ba_we    <= 1;
                    ba_waddr <= {2'd0, res_idx};
                    ba_wdata <= bb_rdata + ba_rdata;  // fc4 + saved_mem_out
                end
                4'd10: begin // Copy: buf_A[2048+i] = buf_A[i]
                    ba_we    <= 1;
                    ba_waddr <= 12'd3072 + {2'd0, res_idx};
                    ba_wdata <= ba_rdata;
                end
                default: ;
                endcase

                if (res_idx == res_len - 1) begin
                    case (layer_id)
                    4'd6: begin
                        // RES1 done → Save buf_A[0..1023] to buf_A[2048..3071]
                        // before FC0 overwrites it
                        // Actually, we just did the add. Now copy to safe area.
                        layer_id <= 4'd10;  // Use temporary layer_id for copy
                        res_idx  <= 0;
                        state    <= S_RES_RD;
                    end
                    4'd9: begin
                        // RES2 done → GAP
                        layer_id <= 4'd11;  // GAP
                        state    <= S_GAP_INIT;
                    end
                    4'd10: begin
                        // Copy done → BB FC0
                        layer_id <= 7;
                        state    <= S_BNN_INIT;
                    end
                    default: state <= S_IDLE;
                    endcase
                end else begin
                    res_idx <= res_idx + 1;
                    state   <= S_RES_RD;
                end
            end

            // ============================================================
            // Global Average Pooling: buf_A[c*8+t] → gap_out[c]
            // gap_out[c] = sum(buf_A[c*8+0..7]) / 8
            // ============================================================
            S_GAP_INIT: begin
                gap_ch  <= 0;
                gap_t   <= 0;
                gap_acc <= 0;
                state   <= S_GAP_RD;
            end

            S_GAP_RD: begin
                ba_raddr <= {5'd0, gap_ch} * TIME_STEPS + {9'd0, gap_t};
                state    <= S_GAP_WAIT;
            end

            S_GAP_WAIT: begin
                state <= S_GAP_ACC;
            end

            S_GAP_ACC: begin
                gap_acc <= gap_acc + ba_rdata;

                if (gap_t == TIME_STEPS - 1) begin
                    // Divide by 8 (>> 3)
                    gap_out[gap_ch] <= (gap_acc + ba_rdata) / TIME_STEPS;
                    gap_acc <= 0;
                    gap_t   <= 0;

                    if (gap_ch == BB_CH - 1) begin
                        // GAP done → Classifier
                        state <= S_CLS_INIT;
                    end else begin
                        gap_ch <= gap_ch + 1;
                        state  <= S_GAP_RD;
                    end
                end else begin
                    gap_t <= gap_t + 1;
                    state <= S_GAP_RD;
                end
            end

            // ============================================================
            // Classifier: 128→5, Q16 MAC
            // logits[o] = cls_b[o] + sum(gap_out[i] * cls_w[o*128+i]) >> 16
            // ============================================================
            S_CLS_INIT: begin
                cls_oc <= 0;
                cls_ic <= 0;
                acc64  <= 0;
                state  <= S_CLS_RD;
            end

            S_CLS_RD: begin
                cls_w_addr <= {3'd0, cls_oc} * BB_CH + {2'd0, cls_ic};
                state      <= S_CLS_WAIT;
            end

            S_CLS_WAIT: begin
                state <= S_CLS_MAC;
            end

            S_CLS_MAC: begin
                acc64 <= acc64 + $signed(gap_out[cls_ic[6:0]]) * cls_w_data;

                if (cls_ic == BB_CH - 1) begin
                    // safe_shift_right + bias
                    begin : cls_result_blk
                        reg signed [31:0] shifted;
                        reg signed [63:0] sum_with_input;
                        sum_with_input = acc64 + $signed(gap_out[cls_ic[6:0]]) * cls_w_data;
                        shifted = (sum_with_input >= 0)
                            ? (sum_with_input + 64'sd32768) >>> 16
                            : (sum_with_input + 64'sd32767) >>> 16;
                        logits[cls_oc] <= cls_b_rom[cls_oc] + shifted;
                    end
                    acc64  <= 0;
                    cls_ic <= 0;

                    if (cls_oc == N_CLS - 1) begin
                        state <= S_CLS_DONE;
                    end else begin
                        cls_oc <= cls_oc + 1;
                        state  <= S_CLS_RD;
                    end
                end else begin
                    cls_ic <= cls_ic + 1;
                    state  <= S_CLS_RD;
                end
            end

            // ============================================================
            // Argmax & Done
            // ============================================================
            S_CLS_DONE: begin
                begin : argmax_blk
                    reg [2:0] best;
                    reg signed [31:0] best_val;
                    integer j;
                    best = 0;
                    best_val = logits[0];
                    for (j = 1; j < N_CLS; j = j + 1) begin
                        if (logits[j] > best_val) begin
                            best_val = logits[j];
                            best = j[2:0];
                        end
                    end
                    result_class_o <= best;
                    result_logit_o <= best_val;
                end
                done_o <= 1;
                state  <= S_DONE;
            end

            S_DONE: begin
                busy_o <= 0;
                state  <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
