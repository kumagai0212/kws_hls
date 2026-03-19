/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

`default_nettype none

module top;
    reg clk   = 1; always #5 clk <= ~clk;
    reg rst_n = 0; initial #50 rst_n = 1;

//==============================================================================
// Perfomance Counter
//------------------------------------------------------------------------------
    reg [63:0] mcycle = 0;
    always @(posedge clk) if (!m0.rst && !cpu_sim_fini) mcycle <= mcycle + 1;

    reg [63:0] minstret     = 0;
    reg [63:0] br_pred_cntr = 0;
    reg [63:0] br_misp_cntr = 0;
    always @(posedge clk) if (!m0.rst && !cpu_sim_fini && !m0.cpu.stall_i) begin
        if (!m0.cpu.stall && m0.cpu.ExMa_v) minstret <= minstret + 1;
        if (m0.cpu.ExMa_v && m0.cpu.ExMa_is_ctrl_tsfr)
          br_pred_cntr <= br_pred_cntr + 1;
        if (m0.cpu.ExMa_v && m0.cpu.ExMa_is_ctrl_tsfr && m0.cpu.Ma_br_misp)
          br_misp_cntr <= br_misp_cntr + 1;
    end
//==============================================================================
// Dump
//------------------------------------------------------------------------------
/*
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, top);
    end
*/

//==============================================================================
// Condition for simulation to end
//------------------------------------------------------------------------------
    reg cpu_sim_fini = 0;
    always @(posedge clk) begin
        if (m0.cpu.dbus_addr_o[31] && m0.cpu.dbus_wvalid_o) begin
            if (m0.cpu.dbus_wdata == 32'h00020000) cpu_sim_fini <= 1;
            else begin $write("%c", m0.cpu.dbus_wdata[7:0]); $fflush(); end
            if (m0.cpu.dbus_addr < 32'h10000000) cpu_sim_fini <= 1;
        end
        if (cpu_sim_fini) begin
            $finish(1);
        end
    end

    final begin
        $write("\n");
        $write("===> mcycle                                 : %10d\n", mcycle);
        $write("===> minstret                               : %10d\n", minstret);
        $write("===> Total number of branch predictions     : %10d\n", br_pred_cntr);
        $write("===> Total number of branch mispredictions  : %10d\n", br_misp_cntr);
        $write("===> simulation finish!!\n");
        $write("\n");
    end

//==============================================================================
// Trace Dump
//------------------------------------------------------------------------------
/*
    integer i, j, fp;
    initial begin
        fp=$fopen("trace.txt","w");
        if(fp == 0)begin
            $display("File_Open_Error_!!!!!");
            $finish();
        end
    end
    always @(posedge clk) if (minstret < 32'h10000)begin
        if (!m0.rst && !cpu_sim_fini && !m0.cpu.stall && m0.cpu.MaWb_v && !m0.cpu.stall_i) begin
            $fwrite(fp, "%08d %08x %08x\n", minstret, m0.cpu.MaWb_pc, m0.cpu.MaWb_ir);
            for(i=0;i<4;i=i+1) begin
                for(j=0;j<8;j=j+1) begin
                    $fwrite(fp, "%08x",m0.cpu.xreg.ram[i*8+j]);
                    if(j==7)    $fwrite(fp, "\n");
                    else        $fwrite(fp, " ");
                end
            end
        end
    end
*/

//==============================================================================
// Debug Dump
//------------------------------------------------------------------------------
/*
    reg r_rst = 0;
    always @(posedge clk) r_rst <= !m0.rst;
    always @(posedge clk) if (r_rst) begin
        $write(" %06d: %x ", minstret, m0.cpu.r_pc);
        if (m0.cpu.IfId_v) $write("%x ", m0.cpu.IfId_pc); else $write("-------- ");
        if (m0.cpu.IdEx_v) $write("%x", m0.cpu.IdEx_pc); else $write("--------");
        if (m0.cpu.IdEx_v && m0.cpu.IdEx_bru_ctrl[0]) begin
          if(m0.cpu.IdEx_bru_ctrl[7:6]) $write("(J) "); else $write("(B) ");
        end
        else $write("( ) ");
        if (m0.cpu.ExMa_v) $write("%x ", m0.cpu.ExMa_pc); else $write("-------- ");
        if (m0.cpu.MaWb_v) $write("%x:", m0.cpu.MaWb_pc); else $write("--------:");
        if (m0.cpu.ExMa_v && m0.cpu.ExMa_is_ctrl_tsfr) begin
            $write(" JB_in_Ma:");
            if (m0.cpu.ExMa_is_ctrl_tsfr && m0.cpu.Ma_br_misp)
              $write(" miss"); else $write(" hit");
        end

        $write("\n");
    end
*/
    wire rxd_i;
    wire [15:0] LED;
    wire w_rst_ni = 1;
    wire sel, lrcl, bclk;
    wire dout = frame[frame_idx][data_idx];

    reg [31:0] frame [256];
    integer i; initial for (i=0; i<256; i++) frame[i][31:24] = i;
    reg [7:0] frame_idx = 0;
    reg [4:0] data_idx = 0;
    reg r_lrcl, r_bclk;
    always @(posedge clk) begin
        {r_lrcl, r_bclk} <= {lrcl, bclk};
        if (r_lrcl == 0 & lrcl == 1) begin
            frame_idx <= frame_idx + 1;
            data_idx <= 31;
        end else if (r_bclk == 1 & bclk == 0) 
            data_idx <= data_idx - 1;
    
    //     if(0)//if (m0.rbuf.w_we || m0.rbuf.w_re)
    //     $write("RBUF: we %x  re %x  wv_i %x  rr_i %x  wdata %x  waddr %x  fulln %x  rdata %x  raddr %x  rvalid %x \n",
    //         m0.rbuf.w_we, 
    //         m0.rbuf.w_re, 
    //         m0.rbuf.wvalid_i, 
    //         m0.rbuf.rready_i, 
    //         m0.rbuf.wdata_i,
    //         m0.rbuf.r_waddr, 
    //         m0.rbuf.r_full_n, 
    //         m0.rbuf.rdata_o,
    //         m0.rbuf.r_raddr, 
    //         m0.rbuf.rvalid_o);
    //     //if (m0.r_line_x == 255) $finish(1);
    end

    wire sda, scl, dc, res;
    main m0 (
        .clk_i      (clk),
        .rst_ni     (w_rst_ni),
        .rxd_i      (rxd_i),
        .txd_o      (),
        .LED        (LED),
        .i2s_SEL    (sel),
        .i2s_LRCL   (lrcl),
        .i2s_DOUT   (dout),
        .i2s_BCLK   (bclk),
        .st7789_SDA (sda),
        .st7789_SCL (scl),
        .st7789_DC  (dc),
        .st7789_RES (res)
    );
endmodule
