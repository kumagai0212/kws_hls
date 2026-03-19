// ==========================================
// CFU HLS: MelSpectrogram アクセラレータ
//
// CPU から固定小数点オーディオサンプルを受け取り、
// Hann窓 → FFT → パワースペクトル → メルフィルタ → log2
// を HW で実行し、32 個のメル値を返す。
//
// コマンド (funct7):
//   0: サンプル書き込み  frame_buf[src1] = src2
//   1: 計算実行 (窓→FFT→パワー→メル→log)
//   2: メル値読み出し    rslt = mel_out[src1]
// ==========================================

#include <stdint.h>
#include "mel_filter_fixed_sparce.h"

#define MUL_Q16(a, b) ((int32_t)(((int64_t)(a) * (b)) >> 16))

// window_norm_sq >> 16 = 50331632 ≈ 2^25.58
// 近似: pwr >> 26 (除算を右シフトに置換してタイミング違反を回避)
#define NORM_SHIFT 26

void cfu_hls(
    char   funct3_i,
    char   funct7_i,
    int    src1_i,
    int    src2_i,
    int*   rslt_o)
{
    // 作業バッファ (static → BRAM, 呼び出し間で保持)
    static int32_t frame_buf[N_FFT];
    static int32_t real_buf[N_FFT];
    static int32_t imag_buf[N_FFT];
    static int32_t power_buf[N_FREQS];
    static int32_t mel_out[N_MELS];

    // HLS pragma: デュアルポートBRAMで読み書き同時アクセスを許可
#pragma HLS BIND_STORAGE variable=real_buf type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=imag_buf type=ram_2p impl=bram

    switch (funct7_i) {

    // ---- コマンド 0: サンプル書き込み ----
    case 0:
        frame_buf[src1_i & 0x7FF] = src2_i;
        *rslt_o = 0;
        break;

    // ---- コマンド 1: 計算実行 ----
    case 1: {
        int i, j, k;

        // 1. Hann窓適用
        HANN_LOOP:
        for (i = 0; i < N_FFT; i++) {
#pragma HLS PIPELINE II=1
            real_buf[i] = MUL_Q16(frame_buf[i], hann_window_fixed[i]);
            imag_buf[i] = 0;
        }

        // 2. ビット反転並べ替え (11ビット: log2(2048))
        BITREV_LOOP:
        for (i = 0; i < N_FFT; i++) {
#pragma HLS PIPELINE II=1
            int x = i;
            int r = 0;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1); x >>= 1;
            r = (r << 1) | (x & 1);
            j = r;
            if (j > i) {
                int32_t tr = real_buf[i]; real_buf[i] = real_buf[j]; real_buf[j] = tr;
                int32_t ti = imag_buf[i]; imag_buf[i] = imag_buf[j]; imag_buf[j] = ti;
            }
        }

        // 3. FFT バタフライ演算 (11ステージ, 各1024バタフライ)
        //    ステージごとにループ分離し、inner loop に PIPELINE を適用
        FFT_STAGE:
        for (int stage = 0; stage < 11; stage++) {
            int half_size = 1 << stage;
            int table_step = 1024 >> stage;
            FFT_BUTTERFLY:
            for (k = 0; k < 1024; k++) {
#pragma HLS PIPELINE II=1
#pragma HLS DEPENDENCE variable=real_buf inter false
#pragma HLS DEPENDENCE variable=imag_buf inter false
                int group = k >> stage;
                int jj = k & (half_size - 1);
                int idx  = (group << (stage + 1)) | jj;
                int idx2 = idx + half_size;

                int32_t wr = cos_table_fixed[jj * table_step];
                int32_t wi = sin_table_fixed[jj * table_step];
                int32_t r2 = real_buf[idx2];
                int32_t i2 = imag_buf[idx2];
                int32_t r1 = real_buf[idx];
                int32_t i1 = imag_buf[idx];
                int32_t tr = MUL_Q16(wr, r2) - MUL_Q16(wi, i2);
                int32_t ti = MUL_Q16(wr, i2) + MUL_Q16(wi, r2);
                real_buf[idx2] = r1 - tr;
                imag_buf[idx2] = i1 - ti;
                real_buf[idx]  = r1 + tr;
                imag_buf[idx]  = i1 + ti;
            }
        }

        // 4. パワースペクトル (除算をシフトに置換)
        POWER_LOOP:
        for (k = 0; k < N_FREQS; k++) {
#pragma HLS PIPELINE II=1
            int64_t r = (int64_t)real_buf[k];
            int64_t im = (int64_t)imag_buf[k];
            uint64_t pwr = (uint64_t)(r * r + im * im);
            power_buf[k] = (int32_t)(pwr >> NORM_SHIFT);
        }

        // 5. メルフィルタバンク + log2
        int weight_idx = 0;
        MEL_LOOP:
        for (int m = 0; m < N_MELS; m++) {
            int64_t mel_pwr = 0;
            int k_start = mel_k_start_fixed[m];
            int k_len   = mel_k_len_fixed[m];
            MEL_ACCUM:
            for (int ii = 0; ii < k_len; ii++) {
#pragma HLS PIPELINE II=1
                mel_pwr += (int64_t)power_buf[k_start + ii]
                         * mel_weights_compact_fixed[weight_idx++];
            }
            uint32_t mel_q16 = (uint32_t)(mel_pwr >> 16);
            if (mel_q16 == 0) mel_q16 = 1;

            // log2 近似 (MSB検出 + 線形補間)
            int msb = 0;
            LOG2_MSB:
            for (int b = 31; b >= 0; b--) {
#pragma HLS UNROLL
                if (mel_q16 & (1U << b)) { msb = b; break; }
            }
            int32_t frac = ((mel_q16 - (1U << msb)) << 16) >> msb;
            int32_t log2_val   = (msb << 16) + frac;
            int32_t log2_float = log2_val - (16 << 16);
            mel_out[m] = MUL_Q16(log2_float, 197283);
        }

        *rslt_o = 0;
        break;
    }

    // ---- コマンド 2: メル値読み出し ----
    case 2:
        *rslt_o = mel_out[src1_i & 0x1F];
        break;

    default:
        *rslt_o = 0;
        break;
    }
}
