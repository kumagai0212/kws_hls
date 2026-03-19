set SynModuleInfo {
  {SRCNAME cfu_hls_Pipeline_HANN_LOOP MODELNAME cfu_hls_Pipeline_HANN_LOOP RTLNAME cfu_hls_cfu_hls_Pipeline_HANN_LOOP
    SUBMODULES {
      {MODELNAME cfu_hls_mul_17ns_32s_48_5_1 RTLNAME cfu_hls_mul_17ns_32s_48_5_1 BINDTYPE op TYPE mul IMPL auto LATENCY 4 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_cfu_hls_Pipeline_HANN_LOOP_hann_window_fixed_ROM_AUTO_1R RTLNAME cfu_hls_cfu_hls_Pipeline_HANN_LOOP_hann_window_fixed_ROM_AUTO_1R BINDTYPE storage TYPE rom IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_flow_control_loop_pipe_sequential_init RTLNAME cfu_hls_flow_control_loop_pipe_sequential_init BINDTYPE interface TYPE internal_upc_flow_control INSTNAME cfu_hls_flow_control_loop_pipe_sequential_init_U}
    }
  }
  {SRCNAME cfu_hls_Pipeline_BITREV_LOOP MODELNAME cfu_hls_Pipeline_BITREV_LOOP RTLNAME cfu_hls_cfu_hls_Pipeline_BITREV_LOOP}
  {SRCNAME cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY MODELNAME cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY RTLNAME cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY
    SUBMODULES {
      {MODELNAME cfu_hls_mul_32s_17s_48_5_1 RTLNAME cfu_hls_mul_32s_17s_48_5_1 BINDTYPE op TYPE mul IMPL auto LATENCY 4 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_mul_32s_18s_48_5_1 RTLNAME cfu_hls_mul_32s_18s_48_5_1 BINDTYPE op TYPE mul IMPL auto LATENCY 4 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_mul_10s_10s_10_5_1 RTLNAME cfu_hls_mul_10s_10s_10_5_1 BINDTYPE op TYPE mul IMPL auto LATENCY 4 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_cos_table_fixed_ROM_AUTO_1R RTLNAME cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_cos_table_fixed_ROM_AUTO_1R BINDTYPE storage TYPE rom IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_sin_table_fixed_ROM_AUTO_1R RTLNAME cfu_hls_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_sin_table_fixed_ROM_AUTO_1R BINDTYPE storage TYPE rom IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
    }
  }
  {SRCNAME cfu_hls_Pipeline_POWER_LOOP MODELNAME cfu_hls_Pipeline_POWER_LOOP RTLNAME cfu_hls_cfu_hls_Pipeline_POWER_LOOP
    SUBMODULES {
      {MODELNAME cfu_hls_mul_32s_32s_58_5_1 RTLNAME cfu_hls_mul_32s_32s_58_5_1 BINDTYPE op TYPE mul IMPL auto LATENCY 4 ALLOW_PRAGMA 1}
    }
  }
  {SRCNAME cfu_hls_Pipeline_MEL_ACCUM MODELNAME cfu_hls_Pipeline_MEL_ACCUM RTLNAME cfu_hls_cfu_hls_Pipeline_MEL_ACCUM
    SUBMODULES {
      {MODELNAME cfu_hls_mul_16ns_32s_48_5_1 RTLNAME cfu_hls_mul_16ns_32s_48_5_1 BINDTYPE op TYPE mul IMPL auto LATENCY 4 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_cfu_hls_Pipeline_MEL_ACCUM_mel_weights_compact_fixed_ROM_AUTO_1R RTLNAME cfu_hls_cfu_hls_Pipeline_MEL_ACCUM_mel_weights_compact_fixed_ROM_AUTO_1R BINDTYPE storage TYPE rom IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
    }
  }
  {SRCNAME cfu_hls MODELNAME cfu_hls RTLNAME cfu_hls IS_TOP 1
    SUBMODULES {
      {MODELNAME cfu_hls_lshr_32ns_5ns_32_2_1 RTLNAME cfu_hls_lshr_32ns_5ns_32_2_1 BINDTYPE op TYPE lshr IMPL auto_pipe LATENCY 1}
      {MODELNAME cfu_hls_frame_buf_RAM_AUTO_1R1W RTLNAME cfu_hls_frame_buf_RAM_AUTO_1R1W BINDTYPE storage TYPE ram IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_real_buf_RAM_2P_BRAM_1R1W RTLNAME cfu_hls_real_buf_RAM_2P_BRAM_1R1W BINDTYPE storage TYPE ram_2p IMPL bram LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_power_buf_RAM_AUTO_1R1W RTLNAME cfu_hls_power_buf_RAM_AUTO_1R1W BINDTYPE storage TYPE ram IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_mel_k_start_fixed_ROM_AUTO_1R RTLNAME cfu_hls_mel_k_start_fixed_ROM_AUTO_1R BINDTYPE storage TYPE rom IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_mel_k_len_fixed_ROM_AUTO_1R RTLNAME cfu_hls_mel_k_len_fixed_ROM_AUTO_1R BINDTYPE storage TYPE rom IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
      {MODELNAME cfu_hls_mel_out_RAM_AUTO_1R1W RTLNAME cfu_hls_mel_out_RAM_AUTO_1R1W BINDTYPE storage TYPE ram IMPL auto LATENCY 2 ALLOW_PRAGMA 1}
    }
  }
}
