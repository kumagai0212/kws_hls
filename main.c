#include <stdio.h>
#include <stdint.h>

// --- ヘッダファイルのインクルード ---
#include "st7789.h"
#include "my_printf.h"

// ==========================================
// 定数
// ==========================================
#define SCALE_FIXED 65536 // 1.0 = 65536

#define AUDIO_LEN 16000
#define HOP_LENGTH 512
#define N_FFT 2048
#define N_MELS 32
#define N_FRAMES (AUDIO_LEN / HOP_LENGTH + 1)

#define INPUT_SIZE (1 * 32 * 32)
#define NUM_CLASSES 5

// LCDカラー
#define C_BLACK    0
#define C_BLUE     1
#define C_GREEN    2
#define C_CYAN     3
#define C_RED      4
#define C_PURPLE   5
#define C_YELLOW   6
#define C_WHITE    7

int *const MMIO_RBUF = (int *)0x30000080;
volatile int *const UART_TX_ADDR = (int *)0x30000088;

// BNN RTL Accelerator MMIO (0x30001000 - 0x30001FFF)
// MEL书き込み: *(BNN_MEL_BASE + word_offset) = melspec_value
// Start:       *BNN_START = 1
// Status:      *BNN_STATUS → bit2=done, bit1=busy, bit0=idle
volatile int *const BNN_MEL_BASE = (int *)0x30001000;  // MEL data BRAM (1024 words)
volatile int *const BNN_START    = (int *)0x30001FFC;  // Start trigger
volatile int *const BNN_STATUS   = (int *)0x30001000;  // Status (R)
volatile int *const BNN_CLASS    = (int *)0x30001004;  // result_class (R)
volatile int *const BNN_LOGIT    = (int *)0x30001008;  // result_logit (R)
volatile int *const BNN_LOGIT0   = (int *)0x3000100C;  // logit[0] (R)
volatile int *const BNN_LOGIT1   = (int *)0x30001010;  // logit[1] (R)
volatile int *const BNN_LOGIT2   = (int *)0x30001014;  // logit[2] (R)
volatile int *const BNN_LOGIT3   = (int *)0x30001018;  // logit[3] (R)
volatile int *const BNN_LOGIT4   = (int *)0x3000101C;  // logit[4] (R)

// パフォーマンスカウンタ MMIO
volatile int *const PERF_CTRL  = (int *)0x40000000; // W: 0=reset, 1=start
volatile int *const PERF_CYCLE = (int *)0x40000004; // R: mcycle[31:0]

static inline void perf_reset(void) { *PERF_CTRL = 0; }
static inline void perf_start(void) { *PERF_CTRL = 1; }
static inline unsigned int perf_read(void) { return *PERF_CYCLE; }

// 1文字送信
void uart_putc(char c) {
    while ((*UART_TX_ADDR) & 0x01);
    *UART_TX_ADDR = c;
}

// 文字列送信
void uart_prints(const char *str) {
    while (*str) uart_putc(*str++);
}

// 数値送信
void uart_print_int(int val) {
    char buf[16];
    sprintf(buf, "%d\r\n", val);
    uart_prints(buf);
}

// ==========================================
// CFU (Custom Function Unit) ラッパー
//
// funct7=0: サンプル書き込み  frame_buf[src1] = src2
// funct7=1: 計算実行 (窓→FFT→パワー→メル→log)
// funct7=2: メル値読み出し    rslt = mel_out[src1]
// ==========================================
static inline unsigned int cfu_write_sample(unsigned int idx, unsigned int val) {
    unsigned int result;
    asm volatile(
        ".insn r CUSTOM_0, 0, 0, %0, %1, %2"
        : "=r"(result)
        : "r"(idx), "r"(val)
        :
    );
    return result;
}

static inline unsigned int cfu_compute(void) {
    unsigned int result;
    unsigned int dummy = 0;
    asm volatile(
        ".insn r CUSTOM_0, 0, 1, %0, %1, %2"
        : "=r"(result)
        : "r"(dummy), "r"(dummy)
        :
    );
    return result;
}

static inline int cfu_read_mel(unsigned int idx) {
    int result;
    unsigned int dummy = 0;
    asm volatile(
        ".insn r CUSTOM_0, 0, 2, %0, %1, %2"
        : "=r"(result)
        : "r"(idx), "r"(dummy)
        :
    );
    return result;
}

// ==========================================
// LCD 矩形描画関数 (バーチャート用)
// ==========================================
void lcd_draw_rect(int x1, int y1, int x2, int y2, int color) {
    x1 = (x1 < 0) ? 0 : (x1 > 239) ? 239 : x1;
    x2 = (x2 < 0) ? 0 : (x2 > 239) ? 239 : x2;
    y1 = (y1 < 0) ? 0 : (y1 > 239) ? 239 : y1;
    y2 = (y2 < 0) ? 0 : (y2 > 239) ? 239 : y2;
    
    for (int y = y1; y <= y2; y++) {
        for (int x = x1; x <= x2; x++) {
            pg_lcd_draw_point(x, y, color);
        }
    }
}

// ==========================================
// 前処理: CFU を使ったメルスペクトログラム計算
// ==========================================
void process_audio_to_melspec_cfu(const float* audio_in, int32_t *output_transposed) {
    for (int f = 0; f < N_FRAMES; f++) {
        int center_idx = f * HOP_LENGTH;

        // 1. フレームのオーディオサンプルを CFU に送信
        //    (リフレクトパディング + float→Q16変換は CPU 側で実施)
        for (int i = 0; i < N_FFT; i++) {
            int audio_idx = center_idx - N_FFT / 2 + i;
            if (audio_idx < 0) audio_idx = -audio_idx;
            else if (audio_idx >= AUDIO_LEN) audio_idx = 2 * AUDIO_LEN - 2 - audio_idx;

            int32_t audio_val_fixed = (int32_t)(audio_in[audio_idx] * SCALE_FIXED);
            cfu_write_sample(i, (unsigned int)audio_val_fixed);
        }

        // 2. CFU で FFT + パワースペクトル + メルフィルタ + log 計算
        cfu_compute();

        // 3. 結果読み出し (転置しながら格納)
        for (int m = 0; m < N_MELS; m++) {
            output_transposed[m * N_FRAMES + f] = cfu_read_mel(m);
        }
    }
}

// ==========================================
// メイン処理 (エンドツーエンド推論 & 画面描画)
// ==========================================
int main() {
    static float audio_buffer[AUDIO_LEN];
    
    // 推論バッファ (メルスペクトログラムと最終出力のみ — 中間バッファはRTLが処理)
    static int32_t input_mel_transposed_fixed[INPUT_SIZE];
    static int32_t final_out_fixed[NUM_CLASSES];
    
    const char* class_names[] = {"unknown", "silence", "go", "stop", "backward"};

    volatile int audio_data; 
    int count[5] = {0};
    
    static uint8_t draw_pos[240] = {0};

    pg_lcd_fill(C_BLACK); 
    pg_lcd_set_pos(0, 0);
    pg_lcd_prints_color("Booting BiFSMN...", C_WHITE);

    int step = 0;

    while(1) {
        step++;
        char step_buf[32];
        pg_lcd_set_pos(0, 5);
        sprintf(step_buf, "Step: %d      ", step);
        pg_lcd_prints_color(step_buf, C_WHITE);

        // =======================================================
        // 1. トリガー待ち ＆ プレロール（過去録音）
        // =======================================================
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("1. Flush Old Audio...", C_CYAN);

        // 1-1. 推論中に溜まった古いマイクデータをすべて捨てる
        while(1){
            audio_data = *(MMIO_RBUF);
            int audio_empty = ((audio_data >> 30) & 0x1);
            if(audio_empty) break; 
        }

        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("1. Waiting Voice...  ", C_YELLOW);

        // 1-2. トリガー待ち 兼 過去音声のリングバッファ (0.25秒 = 4000サンプル)
        static float pre_roll[4000];
        int p_idx = 0;
        int trigger_val = 0;

        while(1) {
            while(1){
                audio_data = *(MMIO_RBUF);
                int audio_empty = ((audio_data >> 30) & 0x1);
                if(!audio_empty) break;
            }
            trigger_val = ((audio_data << 14) >> 14);
            pre_roll[p_idx] = (float)trigger_val;
            p_idx = (p_idx + 1) % 4000;
            
            if (trigger_val > 10000 || trigger_val < -10000) {
                break; 
            }
        }

        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("1. Recording (1s)... ", C_RED);

        // 1-3. 本録音の生成
        for (int i = 0; i < 4000; i++) {
            audio_buffer[i] = pre_roll[(p_idx + i) % 4000];
        }
        
        float sum = 0;
        for (int i = 0; i < 4000; i++) sum += audio_buffer[i];
        
        for (size_t i = 4000; i < 16000; i++){ 
            while(1){
                audio_data = *(MMIO_RBUF);
                int audio_empty = ((audio_data >> 30) & 0x1);
                if(!audio_empty) break;
            }
            audio_buffer[i] = (float)((audio_data << 14) >> 14);
            sum += audio_buffer[i];
        }
        
        // =======================================================
        // 正規化と音量増幅
        // =======================================================
        float offset = sum / AUDIO_LEN;
        float max_amp = 0.00001f; 
        int max_idx = AUDIO_LEN / 2;
        
        for (int i = 0; i < AUDIO_LEN; i++) {
            float val = (audio_buffer[i] - offset) / 131072.0f;
            audio_buffer[i] = val;
            
            float abs_val = (val < 0.0f) ? -val : val;
            if (abs_val > max_amp) {
                max_amp = abs_val;
                max_idx = i;
            }
        }

        char amp_buf[32];
        pg_lcd_set_pos(0, 7);
        sprintf(amp_buf, "Mic Peak: %d / 10000  ", (int)(max_amp * 10000.0f));
        pg_lcd_prints_color(amp_buf, C_GREEN);
        
        if (max_amp > 1e-6f) { 
            float gain = 1.0f / max_amp; 
            for (int i = 0; i < AUDIO_LEN; i++) {
                audio_buffer[i] *= gain;
            }
        }
        
        // --- 2. 特徴量抽出 (CFU HLS アクセラレータ使用) ---
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("2. FFT & MelSpec(HW)", C_CYAN);
        perf_reset(); perf_start();
        process_audio_to_melspec_cfu(audio_buffer, input_mel_transposed_fixed);
        unsigned int t_prepro = perf_read(); perf_reset();

        // --- DEBUG: フレーム16(中央)のメル値をUARTに出力 ---
        uart_prints("MEL_HW:");
        for (int m = 0; m < N_MELS; m++) {
            char dbuf[16];
            sprintf(dbuf, " %d", input_mel_transposed_fixed[m * N_FRAMES + 16]);
            uart_prints(dbuf);
        }
        uart_prints("\r\n");

        // --- 3. BNN 推論パイプライン (RTL Accelerator) ---
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("3. NN Inference(HW) ", C_CYAN);
        perf_start();

        // MelSpec データを BNN RTL の BRAM に転送
        // bnn_inference.v は mel_bram[bin*32+frame] = mel_rd_data のレイアウト
        // input_mel_transposed_fixed は [mel*N_FRAMES+frame] で格納済み → そのまま転送
        for (int m = 0; m < N_MELS; m++) {
            for (int f = 0; f < N_FRAMES; f++) {
                BNN_MEL_BASE[m * 32 + f] = input_mel_transposed_fixed[m * N_FRAMES + f];
            }
        }

        // BNN RTL 推論開始
        // mel BRAM 最終アドレス(1023)への書き込みで start 自動トリガ済み
        // (明示的な BNN_START 書き込みは不要 — 二重 start で mel_bram[1023] が破壊されるため削除)

        // 完了待ち (status bit2 = done)
        while (!((*BNN_STATUS) & 0x04));

        // 結果読み出し
        int pred_label = *BNN_CLASS;
        final_out_fixed[0] = *BNN_LOGIT0;
        final_out_fixed[1] = *BNN_LOGIT1;
        final_out_fixed[2] = *BNN_LOGIT2;
        final_out_fixed[3] = *BNN_LOGIT3;
        final_out_fixed[4] = *BNN_LOGIT4;

        unsigned int t_infer = perf_read(); perf_reset();

        // --- UART: タイミング出力 ---
        {
            char tbuf[64];
            sprintf(tbuf, "PREPRO: %u  INFER: %u  TOTAL: %u\r\n",
                    t_prepro, t_infer, t_prepro + t_infer);
            uart_prints(tbuf);
        }

        // --- 4. 結果表示 ---
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("4. Updating LCD...  ", C_CYAN);

        int32_t max_val = final_out_fixed[pred_label];
        // pred_label は RTL argmax 結果を使用済み

        // --- UART: RTL ロジット出力 (デバッグ用) ---
        uart_prints("BNN_RTL:");
        for (int i = 0; i < NUM_CLASSES; i++) {
            char dbuf[16];
            sprintf(dbuf, " %d", final_out_fixed[i]);
            uart_prints(dbuf);
        }
        uart_prints("\r\n");

        char buf[32];
        count[pred_label]++; 
        
        for (int i = 0; i < NUM_CLASSES; i++) {
            pg_lcd_set_pos(0, i);
            sprintf(buf, "%-7s: %4d\n", class_names[i], count[i]);
            if (i == pred_label) pg_lcd_prints_color(buf, C_YELLOW);
            else pg_lcd_prints_color(buf, C_WHITE);
        }

        // ==============================================================
        // 5. 画面描画 (時間波形を表示)
        // ==============================================================
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("5. Draw Waveform... ", C_CYAN);

        int wave_y_base = 160; 
        
        for (int x = 0; x < 240; x++) {
            if (draw_pos[x] != 0) {
                pg_lcd_draw_point(x, draw_pos[x], C_BLACK); 
            }
            
            int idx = x * 66; 
            if (idx >= AUDIO_LEN) idx = AUDIO_LEN - 1;
            
            int y_pos = wave_y_base + (int)(audio_buffer[idx] * 200.0f); 
            
            if (y_pos > 239) y_pos = 239;
            if (y_pos < 80) y_pos = 80;
            
            pg_lcd_draw_point(x, y_pos, C_YELLOW);
            draw_pos[x] = y_pos;
        }
        
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("Done.               ", C_GREEN);
    }
    return 0;
}
