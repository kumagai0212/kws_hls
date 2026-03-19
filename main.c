#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

// --- ヘッダファイルのインクルード ---
// メルフィルタテーブルは CFU (HLS) 内に格納されるため不要
#include "folded_weights_fixed_dsbnn_gap_32bit.h" // 抽出した32bit(Q16)重みファイル
#include "st7789.h"
#include "my_printf.h"

// ==========================================
// Q16固定小数点用のマクロと定数
// ==========================================
#define MUL_Q16(a, b) ((int32_t)(((int64_t)(a) * (b)) >> 16))
#define SCALE_FIXED 65536 // 1.0 = 65536

#define AUDIO_LEN 16000
#define HOP_LENGTH 512
#define N_FFT 2048
#define N_MELS 32
#define N_FRAMES (AUDIO_LEN / HOP_LENGTH + 1)

#define IN_HEIGHT 32
#define IN_WIDTH 32
#define CONV1_OUT_CH 16
#define OUT1_HEIGHT 16
#define OUT1_WIDTH 16
#define CONV2_OUT_CH 32
#define OUT2_HEIGHT 8
#define OUT2_WIDTH 8
#define KERNEL_H 5
#define KERNEL_W 5
#define PAD 2
#define STRIDE 2

#define FC1_IN 256   
#define FC1_OUT 128
#define TIME_STEPS 8

#define BB_CH 128
#define BB_MID_CH 256
#define BB_KERNEL 5
#define BB_PAD 2

#define INPUT_SIZE (1 * IN_HEIGHT * IN_WIDTH)                
#define LAYER2_SIZE (CONV1_OUT_CH * OUT1_HEIGHT * OUT1_WIDTH) 
#define FRONTEND_OUT_SIZE (CONV2_OUT_CH * OUT2_HEIGHT * OUT2_WIDTH)
#define BB_DATA_SIZE (BB_CH * TIME_STEPS)
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
// 2. 推論 (BNN & Q16固定小数点) — マクロ版
//    RV32コンパイラのインライン展開バグ回避のため、
//    関数呼び出しを一切使わずマクロで直接展開する
// ==========================================

// safe_shift_right マクロ: int64_t val → int32_t
#define SAFE_SHIFT_RIGHT(val) \
    ( ((val) >= 0) ? (int32_t)(((val) + 32768) >> 16) : (int32_t)(((val) + 32767) >> 16) )

// sign_activation_bit マクロ: int32_t → 0 or 1
#define SIGN_BIT(val) ( ((val) >= 0) ? 1 : 0 )

// apply_folded_fixed マクロ: sum_qx, channel index c, T/Apos/Bpos/Aneg/Bneg配列
#define APPLY_FOLDED(dest, sum_qx_val, c, T, Apos, Bpos, Aneg, Bneg) \
    do { \
        if ((sum_qx_val) > (T)[(c)]) { \
            (dest) = SAFE_SHIFT_RIGHT((int64_t)(Apos)[(c)] * (sum_qx_val)) + (Bpos)[(c)]; \
        } else { \
            (dest) = SAFE_SHIFT_RIGHT((int64_t)(Aneg)[(c)] * (sum_qx_val)) + (Bneg)[(c)]; \
        } \
    } while(0)

void front_conv2d_layer0_fixed(const int32_t *input, int32_t *output) {
    static int32_t dw_out[OUT1_HEIGHT * OUT1_WIDTH];
    for (int h = 0; h < OUT1_HEIGHT; h++) {
        for (int w = 0; w < OUT1_WIDTH; w++) {
            int64_t sum_q64 = 0;
            for (int kh = 0; kh < KERNEL_H; kh++) {
                for (int kw = 0; kw < KERNEL_W; kw++) {
                    int weight_idx = kh * KERNEL_W + kw;
                    int in_h = h * STRIDE + kh - PAD, in_w = w * STRIDE + kw - PAD;
                    if (in_h >= 0 && in_h < IN_HEIGHT && in_w >= 0 && in_w < IN_WIDTH) {
                        sum_q64 += (int64_t)input[in_h * IN_WIDTH + in_w] * fe_0_dw_w[weight_idx]; 
                    }
                }
            }
            int32_t sum_qx = SAFE_SHIFT_RIGHT(sum_q64);
            APPLY_FOLDED(dw_out[h * OUT1_WIDTH + w], sum_qx, 0, fe_0_dw_T, fe_0_dw_Apos, fe_0_dw_Bpos, fe_0_dw_Aneg, fe_0_dw_Bneg);
        }
    }
    for (int oc = 0; oc < CONV1_OUT_CH; oc++) {
        for (int h = 0; h < OUT1_HEIGHT; h++) {
            for (int w = 0; w < OUT1_WIDTH; w++) {
                int sum = 0;
                int w_bit = (fe_0_pw_w[oc / 32] >> (oc % 32)) & 1;
                int in_bit = SIGN_BIT(dw_out[h * OUT1_WIDTH + w]);
                if (in_bit == w_bit) sum++; else sum--;
                int32_t sum_qx = sum * SCALE_FIXED;
                APPLY_FOLDED(output[oc * (OUT1_HEIGHT * OUT1_WIDTH) + h * OUT1_WIDTH + w], sum_qx, oc, fe_0_pw_T, fe_0_pw_Apos, fe_0_pw_Bpos, fe_0_pw_Aneg, fe_0_pw_Bneg);
            }
        }
    }
}

void front_conv2d_layer3_fixed(const int32_t *input, int32_t *output) {
    static int32_t dw_out[CONV1_OUT_CH * OUT2_HEIGHT * OUT2_WIDTH];
    for (int c = 0; c < CONV1_OUT_CH; c++) {
        for (int h = 0; h < OUT2_HEIGHT; h++) {
            for (int w = 0; w < OUT2_WIDTH; w++) {
                int sum = 0;
                for (int kh = 0; kh < KERNEL_H; kh++) {
                    for (int kw = 0; kw < KERNEL_W; kw++) {
                        int weight_idx = c * 25 + kh * 5 + kw;
                        int w_bit = (fe_3_dw_w[weight_idx / 32] >> (weight_idx % 32)) & 1;
                        int in_h = h * STRIDE + kh - PAD, in_w = w * STRIDE + kw - PAD;
                        if (in_h >= 0 && in_h < OUT1_HEIGHT && in_w >= 0 && in_w < OUT1_WIDTH) {
                            int in_bit = SIGN_BIT(input[c * OUT1_HEIGHT * OUT1_WIDTH + in_h * OUT1_WIDTH + in_w]);
                            if (in_bit == w_bit) sum++; else sum--;
                        }
                    }
                }
                int32_t sum_qx = sum * SCALE_FIXED;
                APPLY_FOLDED(dw_out[c * OUT2_HEIGHT * OUT2_WIDTH + h * OUT2_WIDTH + w], sum_qx, c, fe_3_dw_T, fe_3_dw_Apos, fe_3_dw_Bpos, fe_3_dw_Aneg, fe_3_dw_Bneg);
            }
        }
    }
    for (int oc = 0; oc < CONV2_OUT_CH; oc++) {
        for (int h = 0; h < OUT2_HEIGHT; h++) {
            for (int w = 0; w < OUT2_WIDTH; w++) {
                int sum = 0;
                for (int ic = 0; ic < CONV1_OUT_CH; ic++) {
                    int weight_idx = oc * CONV1_OUT_CH + ic;
                    int w_bit = (fe_3_pw_w[weight_idx / 32] >> (weight_idx % 32)) & 1;
                    int in_bit = SIGN_BIT(dw_out[ic * OUT2_HEIGHT * OUT2_WIDTH + h * OUT2_WIDTH + w]);
                    if (in_bit == w_bit) sum++; else sum--;
                }
                int32_t sum_qx = sum * SCALE_FIXED;
                APPLY_FOLDED(output[oc * OUT2_HEIGHT * OUT2_WIDTH + h * OUT2_WIDTH + w], sum_qx, oc, fe_3_pw_T, fe_3_pw_Apos, fe_3_pw_Bpos, fe_3_pw_Aneg, fe_3_pw_Bneg);
            }
        }
    }
}

void fc1_layer_fixed(const int32_t *input, int32_t *output) {
    static int32_t temp_out[TIME_STEPS * FC1_OUT]; 
    for (int t = 0; t < TIME_STEPS; t++) {
        for (int out_c = 0; out_c < FC1_OUT; out_c++) {
            int sum = 0;
            for (int w_idx = 0; w_idx < FC1_IN / 32; w_idx++) {
                uint32_t word = fc1_0_w[out_c * (FC1_IN / 32) + w_idx];
                for (int b = 0; b < 32; b++) {
                    int in_c = w_idx * 32 + b;
                    int in_bit = SIGN_BIT(input[in_c * TIME_STEPS + t]);
                    int w_bit = (word >> b) & 1;
                    if (in_bit == w_bit) sum++; else sum--;
                }
            }
            int32_t sum_qx = sum * SCALE_FIXED;
            APPLY_FOLDED(temp_out[t * FC1_OUT + out_c], sum_qx, out_c, fc1_0_T, fc1_0_Apos, fc1_0_Bpos, fc1_0_Aneg, fc1_0_Bneg);
        }
    }
    for (int t = 0; t < TIME_STEPS; t++) {
        for (int n = 0; n < FC1_OUT; n++) {
            output[n * TIME_STEPS + t] = temp_out[t * FC1_OUT + n];
        }
    }
}

void bidfsmn_block_layer0_fixed(const int32_t *input, int32_t *output) {
    static int32_t memory_out[BB_DATA_SIZE];
    static int32_t fc_mid[BB_MID_CH * TIME_STEPS];
    static int32_t fc_out[BB_DATA_SIZE];

    for (int c = 0; c < BB_CH; c++) {
        for (int t = 0; t < TIME_STEPS; t++) {
            int sum = 0;
            for (int k = 0; k < BB_KERNEL; k++) {
                int weight_idx = c * BB_KERNEL + k;
                int w_bit = (bb_0_mem_w[weight_idx / 32] >> (weight_idx % 32)) & 1;
                int in_t = t + k - BB_PAD;
                int in_bit = (in_t >= 0 && in_t < TIME_STEPS) ? SIGN_BIT(input[c * TIME_STEPS + in_t]) : 1;
                if (in_bit == w_bit) sum++; else sum--;
            }
            int32_t sum_qx = sum * SCALE_FIXED;
            APPLY_FOLDED(memory_out[c * TIME_STEPS + t], sum_qx, c, bb_0_mem_T, bb_0_mem_Apos, bb_0_mem_Bpos, bb_0_mem_Aneg, bb_0_mem_Bneg);
        }
    }
    for (int i = 0; i < BB_DATA_SIZE; i++) memory_out[i] += input[i]; 

    for (int oc = 0; oc < BB_MID_CH; oc++) {
        for (int t = 0; t < TIME_STEPS; t++) {
            int sum = 0;
            for (int ic = 0; ic < BB_CH; ic++) {
                int w_bit = (bb_0_fc0_w[(oc * BB_CH + ic) / 32] >> ((oc * BB_CH + ic) % 32)) & 1;
                int in_bit = SIGN_BIT(memory_out[ic * TIME_STEPS + t]);
                if (in_bit == w_bit) sum++; else sum--;
            }
            int32_t sum_qx = sum * SCALE_FIXED;
            APPLY_FOLDED(fc_mid[oc * TIME_STEPS + t], sum_qx, oc, bb_0_fc0_T, bb_0_fc0_Apos, bb_0_fc0_Bpos, bb_0_fc0_Aneg, bb_0_fc0_Bneg);
        }
    }

    for (int oc = 0; oc < BB_CH; oc++) {
        for (int t = 0; t < TIME_STEPS; t++) {
            int sum = 0;
            for (int ic = 0; ic < BB_MID_CH; ic++) {
                int w_bit = (bb_0_fc4_w[(oc * BB_MID_CH + ic) / 32] >> ((oc * BB_MID_CH + ic) % 32)) & 1;
                int in_bit = SIGN_BIT(fc_mid[ic * TIME_STEPS + t]);
                if (in_bit == w_bit) sum++; else sum--;
            }
            int32_t sum_qx = sum * SCALE_FIXED;
            APPLY_FOLDED(fc_out[oc * TIME_STEPS + t], sum_qx, oc, bb_0_fc4_T, bb_0_fc4_Apos, bb_0_fc4_Bpos, bb_0_fc4_Aneg, bb_0_fc4_Bneg);
        }
    }
    for (int i = 0; i < BB_DATA_SIZE; i++) output[i] = fc_out[i] + memory_out[i]; 
}

void global_average_pooling_fixed(const int32_t *input, int32_t *output) {
    for (int c = 0; c < BB_CH; c++) { 
        int64_t sum = 0;
        for (int t = 0; t < TIME_STEPS; t++) { sum += (int64_t)input[c * TIME_STEPS + t]; }
        output[c] = (int32_t)(sum / TIME_STEPS); 
    }
}

void classifier_layer_fixed(const int32_t *input, int32_t *output) {
    for (int o = 0; o < NUM_CLASSES; o++) {
        int64_t sum_q64 = 0;
        for (int i = 0; i < BB_CH; i++) { sum_q64 += (int64_t)input[i] * cls_w[o * BB_CH + i]; }
        output[o] = cls_b[o] + SAFE_SHIFT_RIGHT(sum_q64);
    }
}


// ==========================================
// メイン処理 (エンドツーエンド推論 & 画面描画)
// ==========================================
int main() {
    static float audio_buffer[AUDIO_LEN];
    
    // 推論バッファ (すべて Q16 fixed-point int32_t)
    static int32_t input_mel_transposed_fixed[INPUT_SIZE];
    static int32_t layer2_out_fixed[LAYER2_SIZE], frontend_out_fixed[FRONTEND_OUT_SIZE];
    static int32_t bb_buf_A_fixed[BB_DATA_SIZE], bb_buf_B_fixed[BB_DATA_SIZE];
    static int32_t gap_out_fixed[BB_CH];
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

        // --- 3. BNN 推論パイプライン ---
        pg_lcd_set_pos(0, 6);
        pg_lcd_prints_color("3. NN Inference...  ", C_CYAN);
        perf_start();

        front_conv2d_layer0_fixed(input_mel_transposed_fixed, layer2_out_fixed);
        front_conv2d_layer3_fixed(layer2_out_fixed, frontend_out_fixed);
        fc1_layer_fixed(frontend_out_fixed, bb_buf_A_fixed);
        bidfsmn_block_layer0_fixed(bb_buf_A_fixed, bb_buf_B_fixed);
        global_average_pooling_fixed(bb_buf_B_fixed, gap_out_fixed);
        classifier_layer_fixed(gap_out_fixed, final_out_fixed);

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

        int pred_label = 0;
        int32_t max_val = final_out_fixed[0];
        for (int i = 1; i < NUM_CLASSES; i++) {
            if (final_out_fixed[i] > max_val) {
                max_val = final_out_fixed[i];
                pred_label = i;
            }
        }

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
