/* ================================================================
 * bnn_accel — BNN RTL Accelerator MMIO Wrapper
 * ----------------------------------------------------------------
 * CPU から MMIO 経由で制御する bnn_inference ラッパー。
 *
 * MMIO レジスタマップ (ベース: 0x30001000):
 *   0x000 [W] : MEL データ書き込み (addr = src[9:0] ← dbus_addr[11:2], data = wdata)
 *   0x000 [R] : ステータス {29'd0, done, busy, idle}
 *   0x004 [R] : result_class (3-bit)
 *   0x008 [R] : result_logit (Q16)
 *   0x00C [R] : logit0
 *   0x010 [R] : logit1
 *   0x014 [R] : logit2
 *   0x018 [R] : logit3
 *   0x01C [R] : logit4
 *
 * 制御は MEL BRAM 最終アドレス (1023) への書き込みで自動 start。
 * または 0xFFC [W] に任意値書き込みで即 start。
 * ================================================================ */
`default_nettype none

module bnn_accel (
    input  wire        clk_i,
    input  wire        rst_i,

    // MMIO バスインタフェース
    input  wire        we_i,          // 書き込みイネーブル
    input  wire        re_i,          // 読み出しイネーブル
    input  wire [11:0] addr_i,        // アドレス (0x000 .. 0xFFF 内オフセット)
    input  wire [31:0] wdata_i,       // 書き込みデータ
    output reg  [31:0] rdata_o        // 読み出しデータ
);

    // ================================================================
    // MelSpec 入力 BRAM (1024 × 32-bit, dual-port)
    // ================================================================
    reg signed [31:0] mel_bram [0:1023];

    // Port A: CPU 書き込み (0xFFC の書き込みで mel BRAM 書き込み + start トリガが同時に発生)
    wire        mel_we    = we_i;
    wire [9:0]  mel_waddr = addr_i[11:2];  // word address

    always @(posedge clk_i) begin
        if (mel_we)
            mel_bram[mel_waddr] <= wdata_i;
    end

    // Port B: BNN 読み出し
    wire [9:0]  bnn_mel_addr;
    reg  [31:0] bnn_mel_data;
    always @(posedge clk_i) bnn_mel_data <= mel_bram[bnn_mel_addr];

    // ================================================================
    // Start トリガ
    // ================================================================
    // 方法1: アドレス 0xFFC (= addr_i[11:0] == 12'hFFC) に書き込み → start
    // 方法2: mel_bram の最終エントリ (addr=1023) 書き込み後に自動 start
    reg r_start;
    always @(posedge clk_i) begin
        if (rst_i)
            r_start <= 1'b0;
        else
            r_start <= we_i && (addr_i == 12'hFFC);
    end

    // ================================================================
    // BNN Inference インスタンス
    // ================================================================
    wire        bnn_busy;
    wire        bnn_done;
    wire [2:0]  bnn_class;
    wire [31:0] bnn_logit;
    wire signed [31:0] bnn_logit0, bnn_logit1, bnn_logit2, bnn_logit3, bnn_logit4;

    // Done ラッチ — done パルスを CPU が読むまで保持
    reg r_done_latch;
    always @(posedge clk_i) begin
        if (rst_i || r_start)
            r_done_latch <= 1'b0;
        else if (bnn_done)
            r_done_latch <= 1'b1;
    end

    m_bnn_inference m_bnn (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .start_i        (r_start),
        .busy_o         (bnn_busy),
        .done_o         (bnn_done),
        .mel_rd_addr_o  (bnn_mel_addr),
        .mel_rd_data_i  (bnn_mel_data),
        .result_class_o (bnn_class),
        .result_logit_o (bnn_logit),
        .dbg_logit0_o   (bnn_logit0),
        .dbg_logit1_o   (bnn_logit1),
        .dbg_logit2_o   (bnn_logit2),
        .dbg_logit3_o   (bnn_logit3),
        .dbg_logit4_o   (bnn_logit4),
        .dbg_state_o    (),
        .dbg_layer_id_o (),
        .dbg_pack_cnt_o (),
        .dbg_pack_total_o(),
        .dbg_pack_word_o(),
        .dbg_pack_bit_o (),
        .dbg_gap_ch_o   (),
        .dbg_gap_t_o    (),
        .dbg_cls_oc_o   (),
        .dbg_cls_ic_o   ()
    );

    // ================================================================
    // 読み出しマルチプレクサ
    // ================================================================
    // addr_i[11:2] = word offset within 0x30001000..0x30001FFF
    // Status/result レジスタは上位アドレス (0xC00以降) に配置
    always @(posedge clk_i) begin
        if (re_i) begin
            case (addr_i[5:2])
                4'd0: rdata_o <= {29'd0, r_done_latch, bnn_busy, ~bnn_busy & ~r_start};  // status
                4'd1: rdata_o <= {29'd0, bnn_class};      // result_class
                4'd2: rdata_o <= bnn_logit;                // result_logit
                4'd3: rdata_o <= bnn_logit0;               // logit[0]
                4'd4: rdata_o <= bnn_logit1;               // logit[1]
                4'd5: rdata_o <= bnn_logit2;               // logit[2]
                4'd6: rdata_o <= bnn_logit3;               // logit[3]
                4'd7: rdata_o <= bnn_logit4;               // logit[4]
                default: rdata_o <= 32'd0;
            endcase
        end
    end

endmodule

`default_nettype wire
