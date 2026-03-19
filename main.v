/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

`resetall `default_nettype none

`include "config.vh"

`define UART_CNT 120  // UART wait count, 120MHz / 120 = 1Mbaud  
module m_uart_rx (
    input  wire       w_clk,   // clock signal
    input  wire       w_rxd,   // UART rx, data line from PC to FPGA
    output wire [7:0] w_char,  // 8-bit data received
    output reg        r_en = 0 // data enable
 );
    reg [2:0] r_detect_cnt = 0; /* to detect the start bit */
    always @(posedge w_clk) r_detect_cnt <= (w_rxd) ? 0 : r_detect_cnt + 1;
    wire w_detected = (r_detect_cnt>2);

    reg       r_busy = 0; // r_busy is set while receiving 9-bits data
    reg [3:0] r_bit  = 0; // the number of received bits
    reg [7:0] r_cnt  = 0; // wait count for 1Mbaud
    always@(posedge w_clk) r_cnt <= (r_busy==0) ? 1 : (r_cnt==`UART_CNT) ? 1 : r_cnt + 1;

    reg [8:0] r_data = 0;
    always@(posedge w_clk) begin
        if (r_busy==0) begin
            {r_data, r_bit, r_en} <= 0;
            if (w_detected) r_busy <= 1;
        end
        else if (r_cnt>= `UART_CNT) begin
            r_bit <= r_bit + 1;
            r_data <= {w_rxd, r_data[8:1]};
            if (r_bit==8) begin r_en <= 1; r_busy <= 0; end
        end
    end
    assign w_char = r_data[7:0];
endmodule


module main (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire rxd_i,
    output wire txd_o,    // ★追加: PCへ送信するためのTXピン
    output wire [15:0] LED,
    output wire i2s_SEL,
    output wire i2s_LRCL,
    input  wire i2s_DOUT,
    output wire i2s_BCLK,
    output wire st7789_SDA,
    output wire st7789_SCL,
    output wire st7789_DC,
    output wire st7789_RES
);
//    reg rst_ni = 0; initial #15 rst_ni = 1;
    wire clk, locked;

    assign LED[15] = r_init_done;
    assign LED[0] = r_byte_cnt > 0;
    assign LED[1] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 1;
    assign LED[2] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 2;
    assign LED[3] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 3;
    assign LED[4] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 4;
    assign LED[5] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 5;
    assign LED[6] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 6;
    assign LED[7] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 7;
    assign LED[8] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 8;
    assign LED[9] = r_byte_cnt > (`IMEM_SIZE+`DMEM_SIZE)/10 * 9;
    
                    
`ifdef SYNTHESIS
    clk_wiz_0 clk_wiz_0 (
        .clk_out1 (clk),      // output clk_out1
        .reset    (!rst_ni),  // input reset
        .locked   (locked),   // output locked
        .clk_in1  (clk_i)     // input clk_in1
    );
`else
    assign clk    = clk_i;
    assign locked = 1'b1;
`endif

    /**** Program loader ****/
    wire       w_valid;
    wire [7:0] w_uart_data ;
    m_uart_rx uart_rx1 (clk, rxd_i, w_uart_data, w_valid);

    reg  [31:0] r_byte_cnt  = 0;
    reg         r_init_v    = 0;
    reg  [31:0] r_init_addr = 0;
    reg  [31:0] r_init_data = 0;
    reg         r_init_done = 0;
    always @(posedge clk) begin
        if (!rst_ni || !locked) begin
            r_byte_cnt  <= 0;
            r_init_v    <= 0;
            r_init_addr <= 0;
            r_init_data <= 0;
            r_init_done <= 0;
        end
        else begin
            r_init_v    <= (w_valid && (r_byte_cnt[1:0]==2'b11));
            r_init_addr <= (r_init_v) ? r_init_addr+4 : r_init_addr;
            r_init_data <= (w_valid) ? {w_uart_data, r_init_data[31:8]} : r_init_data;
            if (r_byte_cnt>=(`IMEM_SIZE+`DMEM_SIZE)) begin
                r_init_done <= 1;
            end
            if (w_valid) begin
                r_byte_cnt <= r_byte_cnt+1;
            end
        end
    end
    
    wire                        rst = !rst_ni || !locked || !r_init_done;;
    wire [`IBUS_ADDR_WIDTH-1:0] imem_raddr;
    wire [`IBUS_DATA_WIDTH-1:0] imem_rdata;
    wire                        dbus_we;
    wire [`DBUS_ADDR_WIDTH-1:0] dbus_addr;
    wire [`DBUS_DATA_WIDTH-1:0] dbus_wdata;
    wire [`DBUS_STRB_WIDTH-1:0] dbus_wstrb;
    wire [`DBUS_DATA_WIDTH-1:0] dbus_rdata;
    wire                        insnret;
    
    reg rdata_sel = 0;
    reg rdata_sel_rbuf = 0;
    reg rdata_sel_uart = 0;
    always @(posedge clk) begin
        rdata_sel <= dbus_addr[30];
        rdata_sel_rbuf <= (dbus_addr[29:28]==2'b11) & (dbus_addr[7:2] == 6'b1000_00);
        rdata_sel_uart <= (dbus_addr == 32'h30000088); // ★追加
    end
    assign dbus_rdata = (rdata_sel) ? perf_rdata : 
                        (rdata_sel_rbuf) ? mmio_rbuf_rdata :
                        (rdata_sel_uart) ? {31'd0, !uart_ready} : // ★追加: busyフラグ(!ready)をBit0で返す 
                        dmem_rdata;

    // ===================================================
    // 自作 uart_bridge のインスタンス化とMMIO (0x30000088)
    // ===================================================
    wire uart_ready;
    reg [7:0] r_uart_tx_data = 0;
    reg r_uart_tx_en = 0;

    uart_bridge #(
        .SYSTEM_CLOCK(120000000), // FPGAのクロック周波数 (120MHz)
        .UART_CLOCK(1000000)      // ★高速化のため 1Mbaud に設定
    ) my_uart (
        .clk_i(clk),
        .tx_o(txd_o),
        .rx_i(1'b1),             // RXは既存と共有でOK
        .wdata_i(r_uart_tx_data), // 送信データ
        .we_i(r_uart_tx_en),      // 送信トリガー
        .data_frame_o(),          // (RX受信データは今回は使わない)
        .data_valid_o(),
        .ready_o(uart_ready)      // IDLEなら1、送信中なら0
    );

    // CPUからの書き込み処理 (アドレス 0x30000088)
    always @(posedge clk) begin
        r_uart_tx_en <= 0; 
        if (dbus_we && dbus_addr == 32'h30000088) begin
            r_uart_tx_data <= dbus_wdata[7:0];
            // r_uart_tx_data <= 8'h41;
            r_uart_tx_en <= 1;
        end
    end

    cpu cpu (
        .clk_i         (clk),         // input  wire
        .rst_i         (rst),         // input  wire
        .stall_i       (0),           // input  wire
        .ibus_araddr_o (imem_raddr),  // output wire [`IBUS_ADDR_WIDTH-1:0]
        .ibus_rdata_i  (imem_rdata),  // input  wire [`IBUS_DATA_WIDTH-1:0]
        .dbus_addr_o   (dbus_addr),   // output wire [`DBUS_ADDR_WIDTH-1:0]
        .dbus_wvalid_o (dbus_we),     // output wire
        .dbus_wdata_o  (dbus_wdata),  // output wire [`DBUS_DATA_WIDTH-1:0]
        .dbus_wstrb_o  (dbus_wstrb),  // output wire [`DBUS_STRB_WIDTH-1:0]
        .dbus_rdata_i  (dbus_rdata),  // input  wire [`DBUS_DATA_WIDTH-1:0]
        .insnret       (insnret)      // output wire             
    );
/*
    m_imem imem (
        .clk_i   (clk),         // input  wire
        .raddr_i (imem_raddr),  // input  wire [ADDR_WIDTH-1:0]
        .rdata_o (imem_rdata)   // output reg  [DATA_WIDTH-1:0]
    );
*/

    m_imem imem (
        .clk_i  (clk),
        .we_i   (!r_init_done && r_init_v && (r_byte_cnt<`IMEM_SIZE)),
        .wdata_i(r_init_data),
        .raddr_i(r_init_done ? imem_raddr : r_init_addr),
        .rdata_o(imem_rdata)
    );
    
//    wire        dmem_we    = dbus_we & (dbus_addr[28]);
//    wire [31:0] dmem_addr  = dbus_addr;
//    wire [31:0] dmem_wdata = dbus_wdata;
//    wire  [3:0] dmem_wstrb = dbus_wstrb;
    wire        dmem_we    = r_init_done ? dbus_we & (dbus_addr[28]) : (r_init_v && (r_byte_cnt>=`IMEM_SIZE));
    wire [31:0] dmem_addr  = r_init_done ? dbus_addr : (r_init_addr - `IMEM_SIZE);
    wire [31:0] dmem_wdata = r_init_done ? dbus_wdata : r_init_data;
    wire [3:0]  dmem_wstrb = r_init_done ? dbus_wstrb : 4'b1111;
    wire        dmem_re    = r_init_done ? !dbus_we & (dbus_addr[28]) : 0;
    
    wire [31:0] dmem_rdata;
    m_dmem dmem (
        .clk_i   (clk),         // input  wire
        .we_i    (dmem_we),     // input  wire
        .re_i    (dmem_re),     // input  wire
        .addr_i  (dmem_addr),   // input  wire [ADDR_WIDTH-1:0]
        .wdata_i (dmem_wdata),  // input  wire [DATA_WIDTH-1:0]
        .wstrb_i (dmem_wstrb),  // input  wire [STRB_WIDTH-1:0]
        .rdata_o (dmem_rdata)   // output reg  [DATA_WIDTH-1:0]
    );

    wire        vmem_we    = dbus_we & (dbus_addr[29]);
    wire [15:0] vmem_addr  = dbus_addr[15:0];
    wire  [2:0] vmem_wdata = dbus_wdata[2:0];
    wire [15:0] vmem_raddr;
    wire  [2:0] vmem_rdata_t;
    vmem vmem (
        .clk_i   (clk),          // input wire
        .we_i    (vmem_we),      // input wire
        .waddr_i (vmem_addr),    // input wire [15:0]
        .wdata_i (vmem_wdata),   // input wire [15:0]
        .raddr_i (vmem_raddr),   // input wire [15:0]
        .rdata_o (vmem_rdata_t)  // output wire [15:0]
    );

    wire        perf_we    = dbus_we & (dbus_addr[30]);
    wire  [7:0] perf_addr  = dbus_addr[7:0];
    wire  [2:0] perf_wdata = dbus_wdata[2:0];
    wire [31:0] perf_rdata;
    perf_cntr perf (
        .clk_i   (clk),         // input  wire
        .rst_i   (rst),         // input  wire
        .addr_i  (perf_addr),   // input  wire [3:0]
        .wdata_i (perf_wdata),  // input  wire [2:0]
        .w_en_i  (perf_we),     // input  wire
        .insnret (insnret),     // input  wire
        .rdata_o (perf_rdata)   // output wire [31:0]
    );

    wire [15:0] vmem_rdata = {{5{vmem_rdata_t[2]}}, {6{vmem_rdata_t[1]}}, {5{vmem_rdata_t[0]}}};
    m_st7789_disp st7789_disp (
        .w_clk      (clk),         // input  wire
        .st7789_SDA (st7789_SDA),  // output wire
        .st7789_SCL (st7789_SCL),  // output wire
        .st7789_DC  (st7789_DC),   // output wire
        .st7789_RES (st7789_RES),  // output wire
        .w_raddr    (vmem_raddr),  // output wire [15:0]
        .w_rdata    (vmem_rdata)   // input  wire [15:0]
    );

    wire [17:0] i2s_data;    // 18-bit audio data
    wire        i2s_data_en; // data enable
    m_i2s_master i2s_master (
        .clk_i              (clk),
        .data_h_o           (i2s_data),
        .data_h_update_o    (i2s_data_en),
        .SEL                (i2s_SEL),
        .LRCL               (i2s_LRCL),
        .DOUT               (i2s_DOUT),
        .BCLK               (i2s_BCLK)
    );

    reg [1:0] fifo_cnt = 0;                                          // Note
    always @(posedge clk) if (i2s_data_en) fifo_cnt <= fifo_cnt + 1; // Note
    wire fifo_we = (fifo_cnt==0) && i2s_data_en;                     // Note
    wire        fifo_re = !dbus_we & (dbus_addr[29:28]==2'b11)  & (dbus_addr[7:2] == 6'b1000_00);; // Ex stage
    wire [17:0] fifo_rdata;
    wire        fifo_full;
    wire        fifo_empty;
        
    m_fifo #(
        .FIFO_DATAW  (18),  // 18-bit audio data
        .FIFO_DEPTH  (1024) // 1024 FFT point
    ) fifo (
        .clk_i       (clk),
        .rst_i       (rst),
        .we_i        (fifo_we),     // write enable
        .wdata_i     (i2s_data),    // write data
        .re_i        (fifo_re),     // read enable
        .full_o      (fifo_full),   // flag: fifo is full
        .empty_o     (fifo_empty),  // flag: fifo is empty
        .data_o      (fifo_rdata)   // output data
    );
    
    reg [31:0] mmio_rbuf_rdata = 0;
    always @(posedge clk) 
      mmio_rbuf_rdata <= {1'b0, fifo_empty, 12'd0, fifo_rdata}; // Ma stage
endmodule

module m_imem (
    input  wire        clk_i,
    input  wire        we_i,   
    input  wire [31:0] wdata_i,            
    input  wire [31:0] raddr_i,
    output wire [31:0] rdata_o
);
    (* ram_style = "block" *) reg [31:0] imem[0:`IMEM_ENTRIES-1];
    // `include "memi.txt"
    
    wire [`IMEM_ADDRW-1:0] valid_raddr = raddr_i[`IMEM_ADDRW+1:2];
    
    reg [31:0] rdata;
    always @(posedge clk_i) begin
        rdata <= imem[valid_raddr];
        if (we_i) imem[valid_raddr] <= wdata_i;
    end
    assign rdata_o = rdata;
endmodule

/*
module m_imem (
    input  wire        clk_i,
    input  wire [31:0] raddr_i,
    output wire [31:0] rdata_o
);

    (* ram_style = "block" *) reg [31:0] imem[0:`IMEM_ENTRIES-1];
    `include "memi.txt"

    wire [`IMEM_ADDRW-1:0] valid_raddr = raddr_i[`IMEM_ADDRW+1:2];

    reg [31:0] rdata = 0;
    always @(posedge clk_i) begin
        rdata <= imem[valid_raddr];
    end
    assign rdata_o = rdata;
endmodule
*/


module m_dmem (
    input  wire        clk_i,
    input  wire        re_i,
    input  wire        we_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    input  wire  [3:0] wstrb_i,
    output wire [31:0] rdata_o
);

    (* ram_style = "block", cascade_height = 1 *) reg [31:0] dmem[0:`DMEM_ENTRIES-1];
//    `include "memd.txt"

    wire [`DMEM_ADDRW-1:0] valid_addr = addr_i[`DMEM_ADDRW+1:2];

    reg [31:0] rdata = 0;
    always @(posedge clk_i) begin
        if (we_i) begin
            if (wstrb_i[0]) dmem[valid_addr][7:0]   <= wdata_i[7:0];
            if (wstrb_i[1]) dmem[valid_addr][15:8]  <= wdata_i[15:8];
            if (wstrb_i[2]) dmem[valid_addr][23:16] <= wdata_i[23:16];
            if (wstrb_i[3]) dmem[valid_addr][31:24] <= wdata_i[31:24];
        end
        // if (re_i)
        rdata <= dmem[valid_addr];
    end
    assign rdata_o = rdata;
endmodule

module perf_cntr (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire  [7:0] addr_i,
    input  wire  [2:0] wdata_i,
    input  wire        w_en_i,
    input  wire        insnret,
    output wire [31:0] rdata_o
);
    reg [63:0] mcycle   = 0;
    reg  [1:0] cnt_ctrl = 0;
    reg [31:0] rdata    = 0;

    reg [63:0] r_insnret = 0;
    always @(posedge clk_i) begin
        r_insnret <= (rst_i) ? 0 : (insnret) ? r_insnret + 1 : r_insnret;
    end
    
    always @(posedge clk_i) begin
        rdata <= (addr_i==8'h04) ? mcycle[31:0]  :
                 (addr_i==8'h08) ? mcycle[63:32] :
                 (addr_i==8'h10) ? r_insnret[31:0] : r_insnret[63:32];
        
        if (w_en_i && addr_i == 0) cnt_ctrl <= wdata_i[1:0];
        case (cnt_ctrl)
            0: mcycle <= 0;
            1: mcycle <= mcycle + 1;
            default: ;
        endcase
    end

    assign rdata_o = rdata;
endmodule

module vmem (
    input  wire        clk_i,
    input  wire        we_i,
    input  wire [15:0] waddr_i,
    input  wire  [2:0] wdata_i,
    input  wire [15:0] raddr_i,
    output wire  [2:0] rdata_o
);

    reg [2:0] vmem[0:65535];
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1) begin
            vmem[i] = 0;
        end
    end

    reg        we;
    reg  [2:0] wdata;
    reg [15:0] waddr;
    reg [15:0] raddr;
    reg  [2:0] rdata;

    always @(posedge clk_i) begin
        we    <= we_i;
        waddr <= waddr_i;
        wdata <= wdata_i;
        raddr <= raddr_i;

        if (we) begin
            vmem[waddr] <= wdata;
        end

        rdata <= vmem[raddr];
    end

    assign rdata_o = rdata;

`ifndef SYNTHESIS
    reg  [15:0] r_adr_p = 0;
    reg  [15:0] r_dat_p = 0;

    wire [15:0] data = {{5{wdata_i[2]}}, {6{wdata_i[1]}}, {5{wdata_i[0]}}};
    always @(posedge clk_i)
        if (we_i) begin
            if (vmem[waddr_i] != wdata_i) begin
                r_adr_p <= waddr_i;
                r_dat_p <= data;
                $write("@D%0d_%0d\n", waddr_i ^ r_adr_p, data ^ r_dat_p);
                $fflush();
            end
        end
`endif
endmodule

module m_st7789_disp (
    input  wire        w_clk,  // main clock signal (100MHz)
    output wire        st7789_SDA,
    output wire        st7789_SCL,
    output wire        st7789_DC,
    output wire        st7789_RES,
    output wire [15:0] w_raddr,
    input  wire [15:0] w_rdata
);
    reg [31:0] r_cnt = 1;
    always @(posedge w_clk) r_cnt <= (r_cnt == 0) ? 0 : r_cnt + 1;
    reg r_RES = 1;
    always @(posedge w_clk) begin
        r_RES <= (r_cnt == 100000) ? 0 : (r_cnt == 200000) ? 1 : r_RES;
    end
    assign st7789_RES = r_RES;

    wire       busy;
    reg        r_en      = 0;
    reg        init_done = 0;
    reg  [4:0] r_state   = 0;
    reg [19:0] r_state2  = 0;
    reg  [8:0] r_dat     = 0;
    reg [15:0] r_c       = 16'hf800;

    reg [31:0] r_bcnt = 0;
    always @(posedge w_clk) r_bcnt <= (busy) ? 0 : r_bcnt + 1;

    always @(posedge w_clk)
        if (!init_done) begin
            r_en <= (r_cnt > 1000000 && !busy && r_bcnt > 1000000);
        end else begin
            r_en <= (!busy);
        end

    always @(posedge w_clk) if (r_en && !init_done) r_state <= r_state + 1;

    always @(posedge w_clk)
        if (r_en && init_done) begin
            r_state2 <= (r_state2==115210) ? 0 : r_state2 + 1; // 11 + 240x240*2 = 11 + 115200 = 115211
        end

    reg [7:0] r_x = 0;
    reg [7:0] r_y = 0;
    always @(posedge w_clk)
        if (r_en && init_done && r_state2[0] == 1) begin
            r_x <= (r_state2 < 11 || r_x == 239) ? 0 : r_x + 1;
            r_y <= (r_state2 < 11) ? 0 : (r_x == 239) ? r_y + 1 : r_y;
        end

    wire [7:0] w_nx = 239 - r_x;
    wire [7:0] w_ny = 239 - r_y;
    assign w_raddr = (`LCD_ROTATE == 0) ? {r_y, r_x} :  // default
        (`LCD_ROTATE == 1) ? {r_x, w_ny} :  // 90 degree rotation
        (`LCD_ROTATE == 2) ? {w_ny, w_nx} : {w_nx, r_y};  //180 degree, 240 degree rotation

    reg [15:0] r_color = 0;
    always @(posedge w_clk) r_color <= w_rdata;

    always @(posedge w_clk) begin
        case (r_state2)  /////
            0: r_dat <= {1'b0, 8'h2A};  // Column Address Set
            1: r_dat <= {1'b1, 8'h00};  // [0]
            2: r_dat <= {1'b1, 8'h00};  // [0]
            3: r_dat <= {1'b1, 8'h00};  // [0]
            4: r_dat <= {1'b1, 8'd239};  // [239]
            5: r_dat <= {1'b0, 8'h2B};  // Row Address Set
            6: r_dat <= {1'b1, 8'h00};  // [0]
            7: r_dat <= {1'b1, 8'h00};  // [0]
            8: r_dat <= {1'b1, 8'h00};  // [0]
            9: r_dat <= {1'b1, 8'd239};  // [239]
            10: r_dat <= {1'b0, 8'h2C};  // Memory Write
            default: r_dat <= (r_state2[0]) ? {1'b1, r_color[15:8]} : {1'b1, r_color[7:0]};
        endcase
    end

    reg [8:0] r_init = 0;
    always @(posedge w_clk) begin
        case (r_state)  /////
            0: r_init <= {1'b0, 8'h01};  // Software Reset, wait 120msec
            1: r_init <= {1'b0, 8'h11};  // Sleep Out, wait 120msec
            2: r_init <= {1'b0, 8'h3A};  // Interface Pixel Format
            3: r_init <= {1'b1, 8'h55};  // [65K RGB, 16bit/pixel]
            4: r_init <= {1'b0, 8'h36};  // Memory Data Accell Control
            5: r_init <= {1'b1, 8'h00};  // [000000]
            6: r_init <= {1'b0, 8'h21};  // Display Inversion On
            7: r_init <= {1'b0, 8'h13};  // Normal Display Mode On
            8: r_init <= {1'b0, 8'h29};  // Display On
            9: init_done <= 1;
        endcase
    end

    wire [8:0] w_data = (init_done) ? r_dat : r_init;
    m_spi spi0 (
        w_clk,
        r_en,
        w_data,
        st7789_SDA,
        st7789_SCL,
        st7789_DC,
        busy
    );
endmodule

/****** SPI send module,  SPI_MODE_2, MSBFIRST                                           *****/
/*********************************************************************************************/
module m_spi (
    input  wire       w_clk,  // 100MHz input clock !!
    input  wire       en,     // write enable
    input  wire [8:0] d_in,   // data in
    output wire       SDA,    // Serial Data
    output wire       SCL,    // Serial Clock
    output wire       DC,     // Data/Control
    output wire       busy    // busy
);
    reg [5:0] r_state = 0;
    reg [7:0] r_cnt   = 0;
    reg       r_SCL   = 1;
    reg       r_DC    = 0;
    reg [7:0] r_data  = 0;
    reg       r_SDA   = 0;

    always @(posedge w_clk) begin
        if (en && r_state == 0) begin
            r_state <= 1;
            r_data  <= d_in[7:0];
            r_DC    <= d_in[8];
            r_cnt   <= 0;
        end else if (r_state == 1) begin
            r_SDA   <= r_data[7];
            r_data  <= {r_data[6:0], 1'b0};
            r_state <= 2;
            r_cnt   <= r_cnt + 1;
        end else if (r_state == 2) begin
            r_SCL   <= 0;
            r_state <= 3;
        end else if (r_state == 3) begin
            r_state <= 4;
        end else if (r_state == 4) begin
            r_SCL   <= 1;
            r_state <= (r_cnt == 8) ? 0 : 1;
        end
    end

    assign SDA  = r_SDA;
    assign SCL  = r_SCL;
    assign DC   = r_DC;
    assign busy = (r_state != 0 || en);
endmodule

/****** ring bufffer with overwrite                                                   *****/
/******************************************************************************************/

module m_ring_buffer #(
    parameter BUF_DATAW = 18,
    parameter BUF_DEPTH = 128
) (
    input  wire                 clk_i,
    input  wire                 rst_i,
    input  wire                 wvalid_i,
    input  wire [BUF_DATAW-1:0] wdata_i,
    output wire                 rvalid_o,
    input  wire                 rready_i,
    output wire [BUF_DATAW-1:0] rdata_o,
    output wire                 full_n_o, // info
    output wire                 err_ovfl_o  // info toggle by full
);
    localparam BUF_IDXW = $clog2(BUF_DEPTH);

    reg [BUF_DATAW-1:0] mem [0:BUF_DEPTH-1];
    integer i; initial for (i=0; i<BUF_DEPTH; i=i+1) mem[i] = 0;

    reg                r_err_overflow; // if full & w_we, then 1;
    reg                r_full_n;
    reg                r_empty_n;
    reg [BUF_IDXW-1:0] r_waddr;
    reg [BUF_IDXW-1:0] r_raddr;
    reg [BUF_IDXW:0]   r_dcnt;

    wire w_we = wvalid_i;
    wire w_re = rvalid_o && rready_i;
    always @(posedge clk_i) begin
        if (rst_i) begin
            r_err_overflow <= 0;
            r_full_n <= 1;
            r_empty_n <= 0;
            r_waddr <= 0;
            r_raddr <= 0;
            r_dcnt <= 0;
        end else
            case ({w_we, w_re})
                2'b00: begin
                end
                2'b01: begin
                    r_raddr <= r_raddr + 1;
                    r_full_n <= 1;
                    r_empty_n <= !(r_dcnt == 1); // go to empty
                    r_dcnt <= r_dcnt - 1;
                end
                2'b10: begin
                    r_waddr <= r_waddr + 1;
                    r_raddr <= (r_full_n) ? r_raddr : r_raddr + 1; // overwrite
                    r_full_n <= !(r_dcnt == BUF_DEPTH-1); // go to full
                    r_empty_n <= 1;
                    r_dcnt <= (r_full_n) ? r_dcnt + 1 : r_dcnt;
                    r_err_overflow <= (r_full_n) ? r_err_overflow : 1;
                end
                2'b11: begin
                    r_waddr <= r_waddr + 1;
                    r_raddr <= r_raddr + 1;
                    r_err_overflow <= (r_full_n) ? r_err_overflow : 1;
                end
            endcase
    end

    reg [BUF_DATAW-1:0] r_rdata;
    always @(posedge clk_i) begin
        if (w_we)
            mem[r_waddr] <= wdata_i;
        r_rdata <= mem[r_raddr];
    end

    assign rvalid_o = r_empty_n;
    assign rdata_o = r_rdata;
    assign full_n_o = r_full_n;
    assign err_ovfl_o = r_err_overflow;
endmodule

module m_fifo #(
    parameter FIFO_DATAW = 18,
    parameter FIFO_DEPTH = 128
) (
    input  wire                  clk_i   ,
    input  wire                  rst_i   ,
    input  wire                  we_i    ,  // write enable
    input  wire [FIFO_DATAW-1:0] wdata_i ,  // write data
    input  wire                  re_i    ,  // read enable
    output wire                  full_o  ,  // flag: full
    output wire                  empty_o ,  // flag: empty
    output reg  [FIFO_DATAW-1:0] data_o     // output data
);
    localparam IDXW = $clog2(FIFO_DEPTH);      // index width
    reg [FIFO_DATAW-1:0] mem [0:FIFO_DEPTH-1]; // memory

    reg [IDXW-1:0] r_head = 0;
    reg [IDXW-1:0] r_tail = 0;

    wire [IDXW-1:0] next_tail = r_tail + 1;
    assign full_o  = (r_head==next_tail);
    assign empty_o = (r_head==r_tail);

    always @(posedge clk_i) begin
        if (rst_i) begin
            r_tail <= 0;
            r_head <= 0;
        end else begin
            if (we_i) r_tail <= r_tail + 1;
            if ((re_i && !empty_o) || (we_i && full_o)) r_head <= r_head + 1;
        end
    end

    reg [FIFO_DATAW-1:0] r_rdata;
    always @(posedge clk_i) begin
        if (we_i) mem[r_tail] <= wdata_i;
        if (re_i) data_o <= mem[r_head];
    end
endmodule

/******************************************************************************************/
/****** simple I2S master for SPH0645LM4                                              *****/
// SPH0645LM4 : 32bit x 2 channel i2s loop: at 64 BCLK cycle
// After WS changes, DOUT is stable as MSB on the first falling edge of BCLK 
// Generate BCLK as 4MHz by counting the base clock of FREQ MHz 
// (Toggle BCLK by counting 125ns, which corresponds to 8MHz)
// Generate WS as BCLK/64 MHz by counting the base clock of FREQ MHz
// (Toggle WS by counting 8000ns, which corresponds to 8/64MHz)
// This ensure specification "WS changes with falling edge of BCLK"
// Data is shifted on every falling edge of BCLK
// Wvalid is asserted when the 18th falling edge occurs after WS changes.
// (Inform "18bit data have been captured")
/******************************************************************************************/
module m_i2s_master (
    input  wire        clk_i,       // x mhz input clock !! 1000ns at x cycle
    output wire [17:0] data_h_o,
    output wire        data_h_update_o,
    output wire        SEL,         // i2s sel
    output wire        LRCL,        // i2s ws
    input  wire        DOUT,        // i2s data
    output wire        BCLK        // i2s clk
);
    localparam CYCLE_125NS = (`CLK_FREQ_MHZ / 8); // BCLK toggle cnt, BCLK 4 MHz
    localparam CYCLE_250NS = (CYCLE_125NS * 2);     // BCLK loop
    localparam CYCLE_8000NS = (CYCLE_125NS * 64); // WS toggle cnt, WS 4/64 MHz
    localparam CYCLE_16000NS = (CYCLE_8000NS * 2);  // WS loop
    localparam CYCLE_12500NS = (CYCLE_250NS * (32+18)); // DATA VALID at ws = high. 18st BCLK down after WS change

    reg [17:0] r_data = 0;
    reg        r_wvalid = 0;
    reg        r_i2s_bclk = 0;
    reg        r_i2s_ws = 0;
    reg [8:0]  r_cnt_bclk = 0;
    reg [13:0] r_cnt_ws = 0;
    always @(posedge clk_i) begin
        r_cnt_bclk <= (r_cnt_bclk == CYCLE_250NS-1) ? 0 : r_cnt_bclk + 1;
        r_i2s_bclk <= (r_cnt_bclk == CYCLE_125NS-1) ? 1 : (r_cnt_bclk == CYCLE_250NS-1) ? 0 : r_i2s_bclk;
        r_data <= (r_cnt_bclk == CYCLE_250NS-1) ? (r_data << 1) | DOUT : r_data;
        r_cnt_ws <= (r_cnt_ws == CYCLE_16000NS-1) ? 0 : r_cnt_ws + 1;
        r_i2s_ws <= (r_cnt_ws == CYCLE_8000NS-1) ? 1 : (r_cnt_ws == CYCLE_16000NS-1) ? 0 : r_i2s_ws;
        r_wvalid <= (r_cnt_ws == CYCLE_12500NS-1) ? 1 : 0;
    end

    assign data_h_o = r_data;
    assign data_h_update_o = r_wvalid;
    assign SEL  = 1; // high
    assign LRCL = r_i2s_ws;
    assign BCLK = r_i2s_bclk;
endmodule
