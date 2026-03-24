/* ================================================================
 * kws_top_noncpu — CPU-less KWS Top Module
 * ----------------------------------------------------------------
 * Phase 2A: Single-shot inference without RISC-V CPU.
 *
 * Flow:
 *   S_CAPTURE  — I2S → audio_ram[16000] (Q16)
 *   S_MELSPEC  — hls_ctrl drives cfu_hls: 32 frames → mel[1024]
 *   S_BNN      — mel → bnn_accel → inference
 *   S_UART     — dump "CLS=N L0=.. L1=.. L2=.. L3=.. L4=..\n"
 *   S_DONE     — LED update, then back to S_FLUSH
 *
 * Port list matches main.v for XDC compatibility.
 * LCD pins are driven to safe defaults (no LCD in this version).
 * ================================================================ */
`resetall `default_nettype none
`include "config.vh"
`timescale 1 ns / 1 ps

module kws_top_noncpu (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        rxd_i,
    output wire        txd_o,
    output wire [15:0] LED,
    output wire        i2s_SEL,
    output wire        i2s_LRCL,
    input  wire        i2s_DOUT,
    output wire        i2s_BCLK,
    output wire        st7789_SDA,
    output wire        st7789_SCL,
    output wire        st7789_DC,
    output wire        st7789_RES
);

    // LCD — safe defaults (active-low reset held low = keep in reset)
    assign st7789_SDA = 1'b0;
    assign st7789_SCL = 1'b0;
    assign st7789_DC  = 1'b0;
    assign st7789_RES = 1'b0;

    // ================================================================
    // Clock & Reset
    // ================================================================
    wire clk, locked;
`ifdef SYNTHESIS
    clk_wiz_0 clk_wiz_0 (
        .clk_out1 (clk),
        .reset    (!rst_ni),
        .locked   (locked),
        .clk_in1  (clk_i)
    );
`else
    assign clk    = clk_i;
    assign locked = 1'b1;
`endif

    wire rst = !rst_ni || !locked;

    // ================================================================
    // Constants
    // ================================================================
    localparam AUDIO_LEN = 16000;
    localparam AUDIO_AW  = 14;     // ceil(log2(16000)) = 14
    localparam NUM_CLASSES = 5;
    localparam [17:0] TRIGGER_THRESHOLD = 18'd12000;
    localparam PRE_ROLL  = 4000;                    // 0.25s of pre-trigger audio @ 16kHz
    localparam POST_ROLL = AUDIO_LEN - PRE_ROLL;    // 12000

    // ================================================================
    // Top-level FSM
    // ================================================================
    localparam [3:0]
        S_RESET    = 4'd0,
        S_FLUSH    = 4'd1,   // Discard old I2S samples
        S_WAIT_TRG = 4'd2,   // Wait for audio trigger
        S_CAPTURE  = 4'd3,   // Capture 16000 samples
        S_NORM     = 4'd4,   // Compute offset & normalize (simplified: skip for now)
        S_MELSPEC  = 4'd5,   // Run HLS melspec via hls_ctrl
        S_BNN_LOAD = 4'd6,   // Copy mel → bnn_accel BRAM
        S_BNN_WAIT = 4'd7,   // Wait for BNN done
        S_UART     = 4'd8,   // Dump result via UART
        S_DONE     = 4'd9;

    reg [3:0] state;

    // ================================================================
    // I2S Master (reuse from main.v — module defined there)
    // ================================================================
    wire [17:0] i2s_data;
    wire        i2s_data_en;
    m_i2s_master i2s_master (
        .clk_i           (clk),
        .data_h_o        (i2s_data),
        .data_h_update_o (i2s_data_en),
        .SEL             (i2s_SEL),
        .LRCL            (i2s_LRCL),
        .DOUT            (i2s_DOUT),
        .BCLK            (i2s_BCLK)
    );

    // Decimation: I2S @ ~62.5kHz, we want ~16kHz → take every 4th sample
    reg [1:0] i2s_div;
    always @(posedge clk) begin
        if (rst)
            i2s_div <= 2'd0;
        else if (i2s_data_en)
            i2s_div <= i2s_div + 1'b1;
    end
    wire i2s_sample_valid = (i2s_div == 2'd0) && i2s_data_en;

    // Sign-extend 18-bit I2S data to Q16 (divide by 4 = >>2 to fit 18→16 effective bits)
    // i2s_data is 18bit signed → Q16 = sign_extend to 32bit, already in integer domain
    // main.c: audio_buffer[i] = (float)((audio_data << 14) >> 14) → raw 18-bit value
    // For Q16: val * 65536 / 131072 = val / 2 (to normalize to ±1.0 range)
    // But main.c normalizes later. Here we just store the raw 18-bit sign-extended value as 32-bit.
    wire signed [31:0] i2s_sample_q16 = {{14{i2s_data[17]}}, i2s_data};

    // ================================================================
    // Audio RAM (16000 × 32-bit)
    // ================================================================
    reg  [AUDIO_AW-1:0] aud_waddr;
    reg                  aud_we;
    reg  [31:0]          aud_wdata;

    // Read port — shared between hls_ctrl (during melspec) and bnn_load/norm
    reg  [AUDIO_AW-1:0]  aud_raddr;
    wire [31:0]           aud_rdata;

    (* ram_style = "block" *) reg signed [31:0] audio_ram [0:AUDIO_LEN-1];

    always @(posedge clk) begin
        if (aud_we) audio_ram[aud_waddr] <= aud_wdata;
    end

    reg [31:0] aud_rdata_reg;
    always @(posedge clk) aud_rdata_reg <= audio_ram[aud_raddr];
    assign aud_rdata = aud_rdata_reg;

    // ================================================================
    // Mel BRAM (1024 × 32-bit) — shared between hls_ctrl write & bnn_load read
    // ================================================================
    reg  [9:0]  mel_waddr;
    reg  [31:0] mel_wdata;
    reg         mel_we;

    reg  [9:0]  mel_raddr;
    wire [31:0] mel_rdata;

    (* ram_style = "block" *) reg signed [31:0] mel_bram [0:1023];

    always @(posedge clk) begin
        if (mel_we) mel_bram[mel_waddr] <= mel_wdata;
    end

    reg [31:0] mel_rdata_reg;
    always @(posedge clk) mel_rdata_reg <= mel_bram[mel_raddr];
    assign mel_rdata = mel_rdata_reg;

    // ================================================================
    // hls_ctrl instance
    // ================================================================
    wire        hls_done;
    wire [13:0] hls_audio_addr;
    wire [9:0]  hls_mel_addr;
    wire [31:0] hls_mel_data;
    wire        hls_mel_we;

    reg hls_start;

    hls_ctrl u_hls_ctrl (
        .clk          (clk),
        .rst_n        (!rst),
        .start_i      (hls_start),
        .done_o       (hls_done),
        .audio_addr_o (hls_audio_addr),
        .audio_data_i (aud_rdata),
        .mel_addr_o   (hls_mel_addr),
        .mel_data_o   (hls_mel_data),
        .mel_we_o     (hls_mel_we)
    );

    // HLS address remapping for ring buffer
    wire [AUDIO_AW:0]   hls_phys_sum  = {1'b0, hls_audio_addr} + {1'b0, pre_offset};
    wire [AUDIO_AW-1:0] hls_phys_addr = (hls_phys_sum >= AUDIO_LEN)
                                         ? (hls_phys_sum[AUDIO_AW-1:0] - AUDIO_LEN[AUDIO_AW-1:0])
                                         : hls_phys_sum[AUDIO_AW-1:0];

    // ================================================================
    // BNN Inference (bnn_accel, reused with direct write port)
    // ================================================================
    // We reuse bnn_accel's existing interface:
    //   Write mel via we_i + addr_i + wdata_i
    //   Trigger via addr_i == 12'hFFC write
    //   Read status/results via re_i + addr_i
    reg         bnn_we;
    reg         bnn_re;
    reg  [11:0] bnn_addr;
    reg  [31:0] bnn_wdata;
    wire [31:0] bnn_rdata;

    bnn_accel u_bnn_accel (
        .clk_i   (clk),
        .rst_i   (rst),
        .we_i    (bnn_we),
        .re_i    (bnn_re),
        .addr_i  (bnn_addr),
        .wdata_i (bnn_wdata),
        .rdata_o (bnn_rdata)
    );

    // ================================================================
    // UART bridge
    // ================================================================
    wire uart_ready;
    reg [7:0] uart_tx_data;
    reg       uart_tx_en;

    uart_bridge #(
        .SYSTEM_CLOCK(`CLK_FREQ_MHZ * 1000000),
        .UART_CLOCK(`BAUD_RATE)
    ) u_uart (
        .clk_i       (clk),
        .tx_o        (txd_o),
        .rx_i        (rxd_i),
        .wdata_i     (uart_tx_data),
        .we_i        (uart_tx_en),
        /* verilator lint_off PINCONNECTEMPTY */
        .data_frame_o(),
        .data_valid_o(),
        /* verilator lint_on PINCONNECTEMPTY */
        .ready_o     (uart_ready)
    );

    // ================================================================
    // Counters & sub-state registers
    // ================================================================
    reg [AUDIO_AW-1:0] cap_cnt;       // Audio capture counter 0..15999
    reg [9:0]          bnn_load_cnt;   // Mel→BNN transfer counter 0..1023
    reg                bnn_load_phase; // 0=read mel, 1=write bnn
    reg [2:0]          bnn_poll_cnt;   // Stale-data skip counter for S_BNN_WAIT

    // UART dump sub-state
    localparam [3:0]
        U_PREFIX = 4'd0,   // Send field label
        U_VALUE  = 4'd1,   // Send hex digits
        U_DELIM  = 4'd2,   // Send space/newline
        U_DONE   = 4'd3;

    reg [3:0]  uart_sub;
    reg [2:0]  uart_field;     // 0=CLS, 1=L0, 2=L1, 3=L2, 4=L3, 5=L4
    reg [3:0]  uart_nibble;    // nibble index within field (7..0 for 8-hex-digit values)
    reg [31:0] uart_shift;     // shift register for hex output
    reg [3:0]  uart_pfx_idx;   // prefix string byte index

    // Result latches
    reg [2:0]  pred_class;
    reg signed [31:0] pred_logit [0:NUM_CLASSES-1];

    // Step counter for LED
    reg [15:0] step_cnt;

    // Flush counter
    reg [10:0] flush_cnt;

    // Ring buffer for pre-trigger audio
    reg [AUDIO_AW-1:0] ring_wr_ptr;    // Circular write pointer (wraps at AUDIO_LEN)
    reg [AUDIO_AW-1:0] pre_offset;     // Start offset for HLS address remapping
    reg [11:0]         ring_arm_cnt;   // Counts up to PRE_ROLL, then saturates

    // Trigger detection (unsigned-only: avoid signed/unsigned mix for Vivado)
    wire [17:0] i2s_abs = i2s_data[17] ? (~i2s_data + 18'd1) : i2s_data;
    wire triggered = (i2s_abs > TRIGGER_THRESHOLD);

    // Debug: triggering sample value (output via UART)
    reg [31:0] trig_val;

    // ================================================================
    // LED display
    // ================================================================
    reg [15:0] led_reg;
    assign LED = led_reg;

    // ================================================================
    // Hex-to-ASCII function
    // ================================================================
    function [7:0] hex_ascii;
        input [3:0] nib;
        hex_ascii = (nib < 4'd10) ? (8'h30 + {4'd0, nib}) : (8'h41 + {4'd0, nib} - 8'd10);
    endfunction

    // ================================================================
    // Prefix strings (stored as byte ROM)
    //   Field 0: "CLS="  Field 1: " L0="  Field 2: " L1="
    //   Field 3: " L2="  Field 4: " L3="  Field 5: " L4="
    // ================================================================
    reg [7:0] pfx_char;
    always @(*) begin
        case ({uart_field, uart_pfx_idx[1:0]})
            {3'd0, 2'd0}: pfx_char = "C";
            {3'd0, 2'd1}: pfx_char = "L";
            {3'd0, 2'd2}: pfx_char = "S";
            {3'd0, 2'd3}: pfx_char = "=";
            {3'd1, 2'd0}: pfx_char = " ";
            {3'd1, 2'd1}: pfx_char = "L";
            {3'd1, 2'd2}: pfx_char = "0";
            {3'd1, 2'd3}: pfx_char = "=";
            {3'd2, 2'd0}: pfx_char = " ";
            {3'd2, 2'd1}: pfx_char = "L";
            {3'd2, 2'd2}: pfx_char = "1";
            {3'd2, 2'd3}: pfx_char = "=";
            {3'd3, 2'd0}: pfx_char = " ";
            {3'd3, 2'd1}: pfx_char = "L";
            {3'd3, 2'd2}: pfx_char = "2";
            {3'd3, 2'd3}: pfx_char = "=";
            {3'd4, 2'd0}: pfx_char = " ";
            {3'd4, 2'd1}: pfx_char = "L";
            {3'd4, 2'd2}: pfx_char = "3";
            {3'd4, 2'd3}: pfx_char = "=";
            {3'd5, 2'd0}: pfx_char = " ";
            {3'd5, 2'd1}: pfx_char = "L";
            {3'd5, 2'd2}: pfx_char = "4";
            {3'd5, 2'd3}: pfx_char = "=";
            {3'd6, 2'd0}: pfx_char = " ";
            {3'd6, 2'd1}: pfx_char = "T";
            {3'd6, 2'd2}: pfx_char = "R";
            {3'd6, 2'd3}: pfx_char = "=";
            default:       pfx_char = " ";
        endcase
    end

    // ================================================================
    // Main FSM
    // ================================================================
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_RESET;
            aud_we         <= 1'b0;
            hls_start      <= 1'b0;
            bnn_we         <= 1'b0;
            bnn_re         <= 1'b0;
            uart_tx_en     <= 1'b0;
            mel_we         <= 1'b0;
            led_reg        <= 16'd0;
            step_cnt       <= 16'd0;
            cap_cnt        <= {AUDIO_AW{1'b0}};
            bnn_load_cnt   <= 10'd0;
            bnn_load_phase <= 1'b0;
            bnn_poll_cnt   <= 3'd0;
            flush_cnt      <= 11'd0;
            ring_wr_ptr    <= {AUDIO_AW{1'b0}};
            pre_offset     <= {AUDIO_AW{1'b0}};
            ring_arm_cnt   <= 12'd0;
            uart_sub       <= U_PREFIX;
            uart_field     <= 3'd0;
            uart_nibble    <= 4'd0;
            uart_shift     <= 32'd0;
            uart_pfx_idx   <= 4'd0;
            pred_class     <= 3'd0;
            trig_val       <= 32'd0;
            for (i = 0; i < NUM_CLASSES; i = i + 1)
                pred_logit[i] <= 32'd0;
        end else begin
            // One-cycle pulse defaults
            aud_we     <= 1'b0;
            hls_start  <= 1'b0;
            mel_we     <= 1'b0;
            uart_tx_en <= 1'b0;

            case (state)

            // ---- Reset init ----
            S_RESET: begin
                led_reg <= 16'h0001;
                state   <= S_FLUSH;
            end

            // ---- Flush old I2S samples (drain ~1024 samples) ----
            S_FLUSH: begin
                led_reg[1] <= 1'b1;
                if (i2s_sample_valid)
                    flush_cnt <= flush_cnt + 1'b1;
                if (flush_cnt[10]) begin  // >= 1024
                    flush_cnt <= 11'd0;
                    state     <= S_WAIT_TRG;
                end
            end

            // ---- Wait for audio trigger (ring buffer pre-roll) ----
            S_WAIT_TRG: begin
                led_reg[2] <= 1'b1;
                led_reg[3] <= 1'b0;
                if (i2s_sample_valid) begin
                    // Continuously write I2S samples into ring buffer
                    aud_waddr <= ring_wr_ptr;
                    aud_wdata <= i2s_sample_q16;
                    aud_we    <= 1'b1;
                    ring_wr_ptr <= (ring_wr_ptr == AUDIO_LEN[AUDIO_AW-1:0] - 1)
                                   ? {AUDIO_AW{1'b0}} : (ring_wr_ptr + 1'b1);
                    // Track fill level (saturate at PRE_ROLL)
                    if (ring_arm_cnt < PRE_ROLL[11:0])
                        ring_arm_cnt <= ring_arm_cnt + 1'b1;
                    // Trigger only after enough pre-roll data
                    if (triggered && ring_arm_cnt >= PRE_ROLL[11:0]) begin
                        trig_val <= {14'd0, i2s_abs};
                        // pre_offset = (ring_wr_ptr - PRE_ROLL + 1 + AUDIO_LEN) % AUDIO_LEN
                        pre_offset <= (ring_wr_ptr >= PRE_ROLL[AUDIO_AW-1:0] - 1)
                                      ? (ring_wr_ptr - PRE_ROLL[AUDIO_AW-1:0] + 1)
                                      : (ring_wr_ptr + AUDIO_LEN[AUDIO_AW-1:0] - PRE_ROLL[AUDIO_AW-1:0] + 1);
                        cap_cnt <= {AUDIO_AW{1'b0}};
                        state   <= S_CAPTURE;
                    end
                end
            end

            // ---- Capture POST_ROLL (12000) audio samples after trigger ----
            S_CAPTURE: begin
                led_reg[3] <= 1'b1;
                if (i2s_sample_valid) begin
                    aud_waddr <= ring_wr_ptr;
                    aud_wdata <= i2s_sample_q16;
                    aud_we    <= 1'b1;
                    ring_wr_ptr <= (ring_wr_ptr == AUDIO_LEN[AUDIO_AW-1:0] - 1)
                                   ? {AUDIO_AW{1'b0}} : (ring_wr_ptr + 1'b1);
                    if (cap_cnt == POST_ROLL[AUDIO_AW-1:0] - 1) begin
                        state <= S_NORM;
                    end else begin
                        cap_cnt <= cap_cnt + 1'b1;
                    end
                end
            end

            // ---- Normalization (Phase 2A: skip, pass raw Q16) ----
            S_NORM: begin
                led_reg[4] <= 1'b1;
                // TODO Phase 2B: offset removal + peak normalization
                // For now, go straight to melspec
                hls_start <= 1'b1;
                state     <= S_MELSPEC;
            end

            // ---- MelSpec computation via hls_ctrl ----
            S_MELSPEC: begin
                led_reg[5] <= 1'b1;
                // hls_ctrl drives audio_ram read — remap through ring buffer offset
                aud_raddr <= hls_phys_addr;
                if (hls_mel_we) begin
                    mel_waddr <= hls_mel_addr;
                    mel_wdata <= hls_mel_data;
                    mel_we    <= 1'b1;
                end
                if (hls_done) begin
                    bnn_load_cnt   <= 10'd0;
                    bnn_load_phase <= 1'b0;
                    state          <= S_BNN_LOAD;
                end
            end

            // ---- Transfer mel[1024] → bnn_accel BRAM ----
            S_BNN_LOAD: begin
                led_reg[6] <= 1'b1;
                bnn_we <= 1'b0;  // default off
                if (!bnn_load_phase) begin
                    // Phase 0: read mel_bram
                    mel_raddr      <= bnn_load_cnt;
                    bnn_load_phase <= 1'b1;
                end else begin
                    // Phase 1: write to bnn_accel (1 cycle after mel read)
                    bnn_addr  <= {bnn_load_cnt, 2'b00};  // byte addr offset = word_addr * 4 → addr_i[11:2] = bnn_load_cnt
                    bnn_wdata <= mel_rdata;
                    bnn_we    <= 1'b1;
                    bnn_load_phase <= 1'b0;

                    if (bnn_load_cnt == 10'd1023) begin
                        // All mel data transferred; last write to addr 1023 auto-triggers start
                        // But bnn_accel triggers on addr_i == 12'hFFC, which is word offset 1023
                        // Our addr = {1023, 2'b00} = 12'hFFC ✓ → auto start
                        bnn_poll_cnt <= 3'd0;
                        state <= S_BNN_WAIT;
                    end else begin
                        bnn_load_cnt <= bnn_load_cnt + 1'b1;
                    end
                end
            end

            // ---- Wait for BNN inference done ----
            S_BNN_WAIT: begin
                led_reg[7] <= 1'b1;
                bnn_we <= 1'b0;
                // Continuously read status register
                bnn_re   <= 1'b1;
                bnn_addr <= 12'h000;

                // Skip first 4 cycles: rdata_o carries stale data from
                // previous iteration (logit4 with bit2 possibly set) and
                // r_done_latch is not yet cleared by r_start propagation.
                if (bnn_poll_cnt < 3'd4)
                    bnn_poll_cnt <= bnn_poll_cnt + 1'b1;
                else if (bnn_rdata[2]) begin
                    // Done — start reading class register
                    bnn_addr <= 12'h004;
                    state    <= S_UART;
                    // Initialize UART sub-FSM
                    uart_sub     <= U_PREFIX;
                    uart_field   <= 3'd0;
                    uart_pfx_idx <= 4'd0;
                    uart_nibble  <= 4'd0;
                end
            end

            // ---- UART dump: "CLS=N L0=XXXXXXXX ... L4=XXXXXXXX\n" ----
            S_UART: begin
                led_reg[8] <= 1'b1;
                bnn_we <= 1'b0;

                // First, latch all BNN results synchronously (takes 7 cycles)
                // We pipeline reads: each cycle advance bnn_addr and latch previous result
                case (uart_sub)

                U_PREFIX: begin
                    // Pipeline fix: bnn_accel.rdata_o is registered (1-cycle latency).
                    // S_BNN_WAIT already issued addr=0x004, so rdata will contain class
                    // at pfx_idx 1. We advance addr one step ahead each cycle.
                    if (uart_field == 3'd0 && uart_pfx_idx == 4'd0) begin
                        // Cycle 0: discard stale rdata, issue logit0 addr
                        bnn_re   <= 1'b1;
                        bnn_addr <= 12'h00C;  // logit0 (class read already in flight from BNN_WAIT)
                        uart_pfx_idx <= 4'd1;
                    end else if (uart_pfx_idx == 4'd1) begin
                        // Cycle 1: rdata = class (from addr 0x004 issued in BNN_WAIT)
                        pred_class <= bnn_rdata[2:0];
                        bnn_addr   <= 12'h010;  // logit1
                        uart_pfx_idx <= 4'd2;
                    end else if (uart_pfx_idx == 4'd2) begin
                        // Cycle 2: rdata = logit0
                        pred_logit[0] <= bnn_rdata;
                        bnn_addr <= 12'h014;  // logit2
                        uart_pfx_idx <= 4'd3;
                    end else if (uart_pfx_idx == 4'd3) begin
                        // Cycle 3: rdata = logit1
                        pred_logit[1] <= bnn_rdata;
                        bnn_addr <= 12'h018;  // logit3
                        uart_pfx_idx <= 4'd4;
                    end else if (uart_pfx_idx == 4'd4) begin
                        // Cycle 4: rdata = logit2
                        pred_logit[2] <= bnn_rdata;
                        bnn_addr <= 12'h01C;  // logit4
                        uart_pfx_idx <= 4'd5;
                    end else if (uart_pfx_idx == 4'd5) begin
                        // Cycle 5: rdata = logit3
                        pred_logit[3] <= bnn_rdata;
                        bnn_re <= 1'b0;  // no more reads needed
                        uart_pfx_idx <= 4'd6;
                    end else if (uart_pfx_idx == 4'd6) begin
                        // Cycle 6: rdata = logit4
                        pred_logit[4] <= bnn_rdata;
                        // All results latched, start UART output
                        uart_pfx_idx <= 4'd0;
                        uart_field   <= 3'd0;
                        uart_sub     <= U_VALUE;
                    end
                end

                U_VALUE: begin
                    if (uart_ready && !uart_tx_en) begin
                        if (uart_field == 3'd0) begin
                            // Field 0: CLS — send prefix then single digit
                            if (uart_pfx_idx < 4'd4) begin
                                uart_tx_data <= pfx_char;
                                uart_tx_en   <= 1'b1;
                                uart_pfx_idx <= uart_pfx_idx + 1'b1;
                            end else begin
                                // Send class digit
                                uart_tx_data <= 8'h30 + {5'd0, pred_class};
                                uart_tx_en   <= 1'b1;
                                uart_field   <= 3'd1;
                                uart_pfx_idx <= 4'd0;
                                uart_nibble  <= 4'd7;
                                uart_shift   <= pred_logit[0];
                            end
                        end else begin
                            // Fields 1..5: logits — send prefix then 8 hex digits
                            if (uart_pfx_idx < 4'd4) begin
                                uart_tx_data <= pfx_char;
                                uart_tx_en   <= 1'b1;
                                uart_pfx_idx <= uart_pfx_idx + 1'b1;
                            end else begin
                                // Send hex nibble (MSB first)
                                uart_tx_data <= hex_ascii(uart_shift[31:28]);
                                uart_tx_en   <= 1'b1;
                                uart_shift   <= {uart_shift[27:0], 4'd0};
                                if (uart_nibble == 4'd0) begin
                                    // Done with this field
                                    if (uart_field == 3'd6) begin
                                        // All fields done (CLS + L0..L4 + TR)
                                        uart_sub <= U_DELIM;
                                    end else begin
                                        uart_field   <= uart_field + 1'b1;
                                        uart_pfx_idx <= 4'd0;
                                        uart_nibble  <= 4'd7;
                                        uart_shift   <= (uart_field == 3'd5) ? trig_val : pred_logit[uart_field];
                                    end
                                end else begin
                                    uart_nibble <= uart_nibble - 1'b1;
                                end
                            end
                        end
                    end
                end

                U_DELIM: begin
                    // Send "\r\n"
                    if (uart_ready && !uart_tx_en) begin
                        if (uart_pfx_idx == 4'd0) begin
                            uart_tx_data <= 8'h0D;  // \r
                            uart_tx_en   <= 1'b1;
                            uart_pfx_idx <= 4'd1;
                        end else begin
                            uart_tx_data <= 8'h0A;  // \n
                            uart_tx_en   <= 1'b1;
                            uart_sub     <= U_DONE;
                        end
                    end
                end

                U_DONE: begin
                    state <= S_DONE;
                end

                default: uart_sub <= U_DONE;
                endcase
            end

            // ---- Done: update LED, loop back ----
            S_DONE: begin
                led_reg  <= {13'd0, pred_class};
                step_cnt <= step_cnt + 1'b1;
                // Reset for next cycle
                cap_cnt      <= {AUDIO_AW{1'b0}};
                flush_cnt    <= 11'd0;
                ring_wr_ptr  <= {AUDIO_AW{1'b0}};
                ring_arm_cnt <= 12'd0;
                state        <= S_FLUSH;
            end

            default: state <= S_RESET;
            endcase
        end
    end

endmodule

`default_nettype wire
