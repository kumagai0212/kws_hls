# KWS HLS アクセラレータ 進捗レポート

## 概要

キーワード音声認識 (KWS) システムの前処理部分（MelSpectrogram 計算）を、
RISC-V CPU 上のソフトウェア実装から Vitis HLS によるハードウェアアクセラレータに置き換えるプロジェクト。

- **ベースライン**: `fft_mic/main.c`（全処理をソフトウェアで実行）
- **作業フォルダ**: `kws_hls/`
- **ターゲットFPGA**: Xilinx xc7a35tcsg324-1（Nexys A7）
- **CPU**: RV32IM カスタム RISC-V コア, 120MHz

---

## システムアーキテクチャ

```
┌──────────────────────────────────────────────────────┐
│  FPGA (xc7a35tcsg324-1)                             │
│                                                      │
│  ┌──────────────────────────────────────┐            │
│  │  RISC-V CPU (proc.v)                │            │
│  │  RV32IM, 120MHz                     │            │
│  │                                      │            │
│  │  EX ステージ                         │            │
│  │    ├─ ALU                           │            │
│  │    ├─ MUL/DIV                       │            │
│  │    └─ CFU (cfu.v) ──────────────────┼────┐       │
│  └──────────────────────────────────────┘    │       │
│                                              ▼       │
│  ┌──────────────────────────────────────────────┐   │
│  │  HLS MelSpec アクセラレータ (cfu_hls)        │   │
│  │  (Vitis HLS で cfu_hls.c から自動生成)       │   │
│  │                                              │   │
│  │  ┌─────┐  ┌─────┐  ┌───────┐  ┌─────┐      │   │
│  │  │Hann │→│ FFT │→│Power  │→│ Mel │→log2 │   │
│  │  │窓   │  │2048p│  │Spec   │  │Filter│      │   │
│  │  └─────┘  └─────┘  └───────┘  └─────┘      │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  main.c (ソフトウェア)                               │
│    ├─ オーディオ取得                                 │
│    ├─ CFU 経由で MelSpec 計算 ← HW アクセラレーション│
│    ├─ BNN 推論 (DS-CNN + BiFSMN)                    │
│    └─ LCD 表示                                       │
└──────────────────────────────────────────────────────┘
```

### 処理の流れ

1. **main.c** (CPU ソフトウェア) がオーディオサンプルを取得
2. CUSTOM_0 命令でサンプルを CFU に書き込み (`funct7=0`)
3. CUSTOM_0 命令で計算を起動 (`funct7=1`) → CPU はストールして待機
4. HLS 回路が Hann窓 → FFT → パワースペクトル → メルフィルタ → log2 を実行
5. 完了後 CPU が再開し、メル値を読み出し (`funct7=2`)
6. **main.c** が BNN 推論（1bit 重み DS-CNN + BiFSMN）を実行
7. 分類結果を LCD に表示

---

## HLS 設計 (cfu_hls.c)

### CFU コマンドインタフェース

| funct7 | 動作 | 入力 | 出力 |
|--------|------|------|------|
| 0 | サンプル書き込み | `src1`=index, `src2`=値 | 0 |
| 1 | 計算実行 | (なし) | 0 (完了まで CPU ストール) |
| 2 | メル値読み出し | `src1`=index (0-31) | mel_out[index] |

### CPU との接続

- `cfu.v` 内で `` `ifdef USE_HLS `` により HLS モジュールをインスタンス化
- HLS の `ap_start` / `ap_done` / `ap_idle` / `ap_ready` ハンドシェイクプロトコルで制御
- ストール信号: `stall_o = !ap_idle && !ap_done`
  - CFU が処理中は CPU パイプライン全体が停止
  - 除算 (DIV) 命令のストールと同じ仕組みで、レイテンシが長いだけ

### HLS 最適化プラグマ

| 対象 | プラグマ | 目的 |
|------|---------|------|
| `real_buf`, `imag_buf` | `BIND_STORAGE type=ram_2p impl=bram` | デュアルポート BRAM でR/W 同時アクセス |
| HANN_LOOP | `PIPELINE II=1` | 毎サイクル1反復 |
| FFT_BUTTERFLY | `PIPELINE II=1` + `DEPENDENCE inter false` | R/W 依存を打破しパイプライン化 |
| POWER_LOOP | `PIPELINE II=1` | 毎サイクル1反復 |
| MEL_ACCUM | `PIPELINE II=1` | 毎サイクル1反復 |
| LOG2_MSB | `UNROLL` | 32反復を完全展開 |

### タイミング設計上の工夫

- **パワースペクトルの正規化**: 除算 `pwr / 50331632` → 右シフト `pwr >> 26` に置換
  - 64bit 除算は 6.89ns で目標周期 4.056ns (180MHz) を超過していた
  - `2^26 = 67,108,864 ≈ 50,331,632` (約 0.75 倍のスケーリング差)
  - 後段の log2 計算で定数オフセットとして吸収されるため精度への影響は軽微

---

## HLS 合成結果

### ビルドコマンド

```bash
make vpp
# → /tools/Xilinx/2025.1/Vitis/bin/v++ -c --mode hls --config constr/cfu_hls.cfg --work_dir vitis
```

### 合成設定 (constr/cfu_hls.cfg)

| パラメータ | 値 |
|-----------|-----|
| ターゲットデバイス | xc7a35tcsg324-1 |
| 目標クロック | 180 MHz |
| トップモジュール | cfu_hls |
| リセット | none |
| FSM エンコーディング | auto |

### パフォーマンス (ループ別)

| ループ | 達成 II | 反復数 | 推定サイクル数 |
|--------|---------|--------|---------------|
| HANN_LOOP | 1 | 2,048 | ~2,048 |
| BITREV_LOOP | 3 | 2,048 | ~6,144 |
| FFT_BUTTERFLY | 2 | 1,024 × 11 | ~22,528 |
| POWER_LOOP | 1 | 1,024 | ~1,024 |
| MEL_ACCUM | 1 | ~200 (可変) | ~200 |
| **compute 合計** | | | **~32,000** |

### 推定 Fmax

- **151 MHz** (HLS レポートより)
- 動作クロック 120 MHz に対して十分なマージン

### 残存ワーニング (許容範囲)

| 箇所 | 内容 | 影響 |
|------|------|------|
| HANN_LOOP | 推定クロック 5.351ns > 目標 4.056ns | 実動作 120MHz (8.33ns) では問題なし |
| BITREV_LOOP | II=3 (目標 II=1 未達) | スワップ時の RAW 依存。全体への影響軽微 |
| FFT_BUTTERFLY 乗算 | 推定 6.604ns | 実動作クロックでは問題なし |

---

## ソフトウェア vs ハードウェア 性能比較

### MelSpectrogram 1フレーム (2048サンプル) あたりの推定サイクル数

| 方式 | 推定サイクル数 | 備考 |
|------|--------------|------|
| ソフトウェア (CPU のみ) | 300,000 〜 500,000 | ループ反復ごとに多数の命令実行 |
| **HLS ハードウェア** | **~32,000** | パイプライン化・並列実行 |
| **高速化倍率** | **約 10〜15 倍** | |

高速化の要因:
- **パイプライン化**: ループ反復を毎サイクル (II=1) または 2サイクル (II=2) で投入
- **並列実行**: 乗算・加算・メモリアクセスを同一サイクルで同時実行
- **命令オーバーヘッドなし**: フェッチ/デコードが不要、データパスが直接動作

---

## ファイル構成

```
kws_hls/
├── cfu_hls.c                  # HLS ソース (MelSpec アクセラレータ)
├── main.c                     # RISC-V ソフトウェア (CFU 経由の前処理 + BNN推論)
├── cfu.v                      # CFU ブリッジ (HLS モジュール ↔ CPU パイプライン)
├── proc.v                     # RISC-V CPU コア
├── main.v                     # トップモジュール (CPU + 周辺)
├── top.v                      # シミュレーション用テストベンチ
├── config.vh                  # システム設定 (120MHz, メモリサイズ等)
├── Makefile                   # ビルドシステム
├── constr/cfu_hls.cfg         # HLS 合成設定
├── mel_filter_fixed_sparce.h  # FFT/メルフィルタテーブル (Q16固定小数点)
├── folded_weights_fixed_dsbnn_gap_32bit.h  # BNN 重み (1bit + 折り畳みBN)
├── cfu/                       # HLS 生成 Verilog ファイル群
│   ├── cfu_hls.v              #   トップモジュール
│   ├── ...Pipeline_HANN_LOOP.v
│   ├── ...Pipeline_FFT_STAGE_FFT_BUTTERFLY.v
│   ├── ...Pipeline_POWER_LOOP.v
│   ├── ...Pipeline_MEL_ACCUM.v
│   ├── ...real_buf_RAM_2P_BRAM_1R1W.v
│   └── ... (ROM, 乗算器等 約25ファイル)
└── vitis/                     # HLS ワークディレクトリ
```

### HLS 統合の仕組み

```
cfu_hls.c  ──make vpp──→  cfu/*.v (Verilog)
                              │
cfu.v (ifdef USE_HLS) ────────┘  モジュール名 "cfu_hls" で結合
  │
proc.v (CPU EX ステージ) ── cfu インスタンス化
  │
make hls-sim: verilator -DUSE_HLS -Icfu *.v
make bit:     vivado (全 .v を合成)
```

---

## Makefile ターゲット

| コマンド | 動作 |
|---------|------|
| `make vpp` | Vitis HLS で cfu_hls.c → Verilog 合成 |
| `make prog` | RISC-V クロスコンパイル (main.c → main.elf) |
| `make hls-sim` | Verilator シミュレーション (`-DUSE_HLS -Icfu` 有効) |
| `make build` | Verilator ビルド (HLS なし) |
| `make bit` | Vivado 合成・配置配線 → ビットストリーム生成 |
| `make conf` | FPGA 書き込み |
| `make run` / `make drun` | シミュレーション実行 (drun は LCD エミュ付き) |

---

## 進捗状況

| 項目 | 状態 | 備考 |
|------|------|------|
| kws_hls フォルダ作成 | ✅ 完了 | fft_mic ベースにファイルをコピー |
| cfu_hls.c 設計・実装 | ✅ 完了 | Hann→FFT→Power→Mel→Log2 |
| HLS 最適化プラグマ | ✅ 完了 | PIPELINE, BIND_STORAGE, DEPENDENCE, UNROLL |
| HLS 合成 (`make vpp`) | ✅ 完了 | Fmax 151MHz, Verilog 生成済み |
| main.c CFU 統合 | ✅ 完了 | cfu_write/compute/read ラッパー関数 |
| Makefile 修正 | ✅ 完了 | tcl コピーエラー対応 |
| ソフトウェアコンパイル (`make prog`) | 🔲 未実施 | |
| Verilator シミュレーション (`make hls-sim`) | 🔲 未実施 | |
| 数値精度検証 | 🔲 未実施 | ソフトウェア版との出力比較 |
| ビットストリーム生成 (`make bit`) | 🔲 未実施 | |
| 実機動作確認 | ✅ 完了 | 下記「実機計測結果」参照 |

---

## デバッグ記録

### 問題1: 推論結果がすべて "silence" になる

**症状**: ビットストリームを書き込み推論を実行すると、すべての入力に対して "silence" と分類される。

**調査**: メル出力の UART ダンプを追加したところ、32 ビンすべてが同一値 `-3156528` であった。

```
MEL_HW: -3156528 -3156528 -3156528 -3156528 ... (全32個同一)
```

**原因分析**: `-3156528 = MUL_Q16(-(16 << 16), 197283)` であり、これは `mel_q16 = 0`（ゼロクランプ → 1）の場合の log2 出力に完全一致する。
つまり**パワースペクトルが全ゼロ** = **Hann 窓テーブルや FFT テーブルがゼロ初期化**されていた。

**根本原因**: HLS 生成 Verilog は `$readmemh("./cfu_hls_*.dat", ram)` で ROM/RAM を初期化するが、
`.dat` ファイル（Hann 窓、cos/sin テーブル、メルフィルタ係数等 10 ファイル）が `cfu/` ディレクトリにコピーされていなかった。
Vivado 合成時にファイルが見つからないため、すべての ROM がゼロに初期化された。

**修正**:

1. `.dat` ファイルを HLS 出力ディレクトリからコピー:
   ```bash
   cp vitis/hls/impl/verilog/*.dat cfu/
   ```

2. `build.tcl` を修正して `.dat` ファイルも Vivado プロジェクトに追加:
   ```tcl
   set dat_files [glob -nocomplain $top_dir/cfu/*.dat]
   if {[llength $dat_files] > 0} {
       add_files -force -norecurse $dat_files
       puts "Added [llength $dat_files] ROM data files from cfu/"
   }
   ```

**結果**: 修正後、マイク入力に対して正しい分類結果が得られるようになった。

### コピーされた ROM 初期化ファイル一覧

| ファイル名 | 内容 |
|-----------|------|
| `cfu_hls_cfu_hls_Pipeline_HANN_LOOP_hann_window_fixed_ROM_AUTO_1R.dat` | Hann 窓関数 (2048 点) |
| `cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_cos_table_fixed_ROM_AUTO_1R.dat` | FFT 余弦テーブル |
| `cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_sin_table_fixed_ROM_AUTO_1R.dat` | FFT 正弦テーブル |
| `cfu_hls_cfu_hls_Pipeline_MEL_ACCUM_mel_weights_compact_fixed_ROM_AUTO_1R.dat` | メルフィルタ係数 |
| `cfu_hls_mel_k_start_fixed_ROM_AUTO_1R.dat` | メルフィルタ開始インデックス |
| `cfu_hls_mel_k_len_fixed_ROM_AUTO_1R.dat` | メルフィルタ長 |
| `cfu_hls_frame_buf_RAM_AUTO_1R1W.dat` | フレームバッファ初期値 |
| `cfu_hls_mel_out_RAM_AUTO_1R1W.dat` | メル出力バッファ初期値 |
| `cfu_hls_power_buf_RAM_AUTO_1R1W.dat` | パワーバッファ初期値 |
| `cfu_hls_real_buf_RAM_2P_BRAM_1R1W.dat` | FFT 実部バッファ初期値 |

---

## 実機計測結果

### 計測方法

ハードウェアに搭載された `perf_cntr` モジュール（64bit サイクルカウンタ, MMIO `0x40000000` ベース）を使用。
前処理と推論の各区間でカウンタをリセット→スタート→読み取りし、サイクル数を UART に出力した。

```c
// パフォーマンスカウンタ MMIO
volatile int *const PERF_CTRL  = (int *)0x40000000; // W: 0=reset, 1=start
volatile int *const PERF_CYCLE = (int *)0x40000004; // R: mcycle[31:0]

// 使用例
perf_reset(); perf_start();
process_audio_to_melspec_xxx(...);
unsigned int t_prepro = perf_read(); perf_reset();
```

出力フォーマット: `PREPRO: <cycles>  INFER: <cycles>  TOTAL: <cycles>`

### Raw データ

**fft_mic (ソフトウェア前処理)**:
```
PREPRO: 53375866  INFER: 16943428  TOTAL: 70319294
PREPRO: 59020122  INFER: 17030124  TOTAL: 76050246
PREPRO: 59490309  INFER: 17035764  TOTAL: 76526073
PREPRO: 59532002  INFER: 17056364  TOTAL: 76588366
PREPRO: 59548790  INFER: 17065700  TOTAL: 76614490
```

**kws_hls (HLS ハードウェア前処理)**:
```
PREPRO: 10937260  INFER: 17051939  TOTAL: 27989199
PREPRO: 13099730  INFER: 17122282  TOTAL: 30222012
PREPRO: 13506065  INFER: 17117037  TOTAL: 30623102
PREPRO: 13501408  INFER: 17127905  TOTAL: 30629313
PREPRO: 13506081  INFER: 17121585  TOTAL: 30627666
```

※1行目は初回実行のためキャッシュ等の影響で変動あり。安定した2行目以降で比較する。

### 性能比較 (安定値の平均, 120 MHz 動作)

| 区間 | fft_mic (SW) | kws_hls (HW) | スピードアップ |
|------|-------------|--------------|---------------|
| **前処理 (PREPRO)** | 59,398,000 cycles (495 ms) | 13,403,000 cycles (112 ms) | **4.4 倍** |
| **推論 (INFER)** | 17,047,000 cycles (142 ms) | 17,122,000 cycles (143 ms) | 1.0 倍 (同等) |
| **合計 (TOTAL)** | 76,445,000 cycles (637 ms) | 30,526,000 cycles (254 ms) | **2.5 倍** |

### 考察

- **前処理が 4.4 倍高速化**: FFT (2048 点) × 31 フレームのバタフライ演算・パワースペクトル計算・メルフィルタ適用・log2 計算が HLS パイプラインにより大幅に高速化された
- **推論時間は同一**: BNN 推論は両方とも CPU ソフトウェアで実行しており、ほぼ同一サイクル数 (~17M cycles) で期待通り
- **全体で 2.5 倍の高速化**: 前処理の高速化により、合計処理時間が 637 ms → 254 ms に短縮
- **PREPRO の内訳**: HLS 版の ~13.4M cycles には CPU 側のオーバーヘッド（リフレクトパディング、float→Q16 変換、2048 サンプル × 31 フレームの CFU 書き込み）を含む。純粋な HLS 計算部分（~32,000 cycles/フレーム × 31 = ~1M cycles）に対し、データ転送オーバーヘッドが支配的
- **さらなる高速化の余地**: データ転送を DMA 化する、または音声サンプルを直接 HLS モジュールに接続することで、前処理時間のさらなる短縮が見込める

---

## 今後の展望

- **BNN 推論のハードウェア化**: 現在 CPU ソフトウェアで実行している BNN 推論（DS-CNN + BiFSMN）も HLS または手書き RTL でハードウェア化し、C 言語コードの完全排除を目指す
- **BNN のハードウェア化は特に有利**: 1bit 重みにより XNOR + popcount で畳み込みが実現可能、メモリ使用量も大幅削減
- **リソース見積**:  xc7a35t は LUT 20,800 / BRAM 50 / DSP48 90 を搭載。現在の MelSpec アクセラレータ + CPU の後、BNN 回路の追加可否は合成結果を見て判断
