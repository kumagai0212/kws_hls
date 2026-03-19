set moduleName cfu_hls
set isTopModule 1
set isCombinational 0
set isDatapathOnly 0
set isPipelined 0
set pipeline_type none
set FunctionProtocol ap_ctrl_hs
set isOneStateSeq 0
set ProfileFlag 0
set StallSigGenFlag 0
set isEnableWaveformDebug 1
set hasInterrupt 0
set DLRegFirstOffset 0
set DLRegItemOffset 0
set svuvm_can_support 1
set cdfgNum 8
set C_modelName {cfu_hls}
set C_modelType { void 0 }
set ap_memory_interface_dict [dict create]
set C_modelArgList {
	{ funct3_i int 8 unused  }
	{ funct7_i int 8 regular  }
	{ src1_i int 32 regular  }
	{ src2_i int 32 regular  }
	{ rslt_o int 32 regular {pointer 1}  }
}
set hasAXIMCache 0
set l_AXIML2Cache [list]
set AXIMCacheInstDict [dict create]
set C_modelArgMapList {[ 
	{ "Name" : "funct3_i", "interface" : "wire", "bitwidth" : 8, "direction" : "READONLY"} , 
 	{ "Name" : "funct7_i", "interface" : "wire", "bitwidth" : 8, "direction" : "READONLY"} , 
 	{ "Name" : "src1_i", "interface" : "wire", "bitwidth" : 32, "direction" : "READONLY"} , 
 	{ "Name" : "src2_i", "interface" : "wire", "bitwidth" : 32, "direction" : "READONLY"} , 
 	{ "Name" : "rslt_o", "interface" : "wire", "bitwidth" : 32, "direction" : "WRITEONLY"} ]}
# RTL Port declarations: 
set portNum 10
set portList { 
	{ ap_clk sc_in sc_logic 1 clock -1 } 
	{ ap_start sc_in sc_logic 1 start -1 } 
	{ ap_done sc_out sc_logic 1 predone -1 } 
	{ ap_idle sc_out sc_logic 1 done -1 } 
	{ ap_ready sc_out sc_logic 1 ready -1 } 
	{ funct3_i sc_in sc_lv 8 signal 0 } 
	{ funct7_i sc_in sc_lv 8 signal 1 } 
	{ src1_i sc_in sc_lv 32 signal 2 } 
	{ src2_i sc_in sc_lv 32 signal 3 } 
	{ rslt_o sc_out sc_lv 32 signal 4 } 
}
set NewPortList {[ 
	{ "name": "ap_clk", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "clock", "bundle":{"name": "ap_clk", "role": "default" }} , 
 	{ "name": "ap_start", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "start", "bundle":{"name": "ap_start", "role": "default" }} , 
 	{ "name": "ap_done", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "predone", "bundle":{"name": "ap_done", "role": "default" }} , 
 	{ "name": "ap_idle", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "done", "bundle":{"name": "ap_idle", "role": "default" }} , 
 	{ "name": "ap_ready", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "ready", "bundle":{"name": "ap_ready", "role": "default" }} , 
 	{ "name": "funct3_i", "direction": "in", "datatype": "sc_lv", "bitwidth":8, "type": "signal", "bundle":{"name": "funct3_i", "role": "default" }} , 
 	{ "name": "funct7_i", "direction": "in", "datatype": "sc_lv", "bitwidth":8, "type": "signal", "bundle":{"name": "funct7_i", "role": "default" }} , 
 	{ "name": "src1_i", "direction": "in", "datatype": "sc_lv", "bitwidth":32, "type": "signal", "bundle":{"name": "src1_i", "role": "default" }} , 
 	{ "name": "src2_i", "direction": "in", "datatype": "sc_lv", "bitwidth":32, "type": "signal", "bundle":{"name": "src2_i", "role": "default" }} , 
 	{ "name": "rslt_o", "direction": "out", "datatype": "sc_lv", "bitwidth":32, "type": "signal", "bundle":{"name": "rslt_o", "role": "default" }}  ]}

set RtlHierarchyInfo {[
	{"ID" : "0", "Level" : "0", "Path" : "`AUTOTB_DUT_INST", "Parent" : "", "Child" : ["1", "2", "3", "4", "5", "6", "7", "8", "12", "14", "23", "27", "31"],
		"CDFG" : "cfu_hls",
		"Protocol" : "ap_ctrl_hs",
		"ControlExist" : "1", "ap_start" : "1", "ap_ready" : "1", "ap_done" : "1", "ap_continue" : "0", "ap_idle" : "1", "real_start" : "0",
		"Pipeline" : "None", "UnalignedPipeline" : "0", "RewindPipeline" : "0", "ProcessNetwork" : "0",
		"II" : "0",
		"VariableLatency" : "1", "ExactLatency" : "-1", "EstimateLatencyMin" : "4", "EstimateLatencyMax" : "37774",
		"Combinational" : "0",
		"Datapath" : "0",
		"ClockEnable" : "0",
		"HasSubDataflow" : "0",
		"InDataflowNetwork" : "0",
		"HasNonBlockingOperation" : "0",
		"IsBlackBox" : "0",
		"Port" : [
			{"Name" : "funct3_i", "Type" : "None", "Direction" : "I"},
			{"Name" : "funct7_i", "Type" : "None", "Direction" : "I"},
			{"Name" : "src1_i", "Type" : "None", "Direction" : "I"},
			{"Name" : "src2_i", "Type" : "None", "Direction" : "I"},
			{"Name" : "rslt_o", "Type" : "None", "Direction" : "O"},
			{"Name" : "frame_buf", "Type" : "Memory", "Direction" : "IO",
				"SubConnect" : [
					{"ID" : "8", "SubInstance" : "grp_cfu_hls_Pipeline_HANN_LOOP_fu_485", "Port" : "frame_buf", "Inst_start_state" : "2", "Inst_end_state" : "5"}]},
			{"Name" : "hann_window_fixed", "Type" : "Memory", "Direction" : "I",
				"SubConnect" : [
					{"ID" : "8", "SubInstance" : "grp_cfu_hls_Pipeline_HANN_LOOP_fu_485", "Port" : "hann_window_fixed", "Inst_start_state" : "2", "Inst_end_state" : "5"}]},
			{"Name" : "real_buf", "Type" : "Memory", "Direction" : "IO",
				"SubConnect" : [
					{"ID" : "8", "SubInstance" : "grp_cfu_hls_Pipeline_HANN_LOOP_fu_485", "Port" : "real_buf", "Inst_start_state" : "2", "Inst_end_state" : "5"},
					{"ID" : "12", "SubInstance" : "grp_cfu_hls_Pipeline_BITREV_LOOP_fu_497", "Port" : "real_buf", "Inst_start_state" : "6", "Inst_end_state" : "7"},
					{"ID" : "14", "SubInstance" : "grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505", "Port" : "real_buf", "Inst_start_state" : "8", "Inst_end_state" : "9"},
					{"ID" : "23", "SubInstance" : "grp_cfu_hls_Pipeline_POWER_LOOP_fu_517", "Port" : "real_buf", "Inst_start_state" : "10", "Inst_end_state" : "11"}]},
			{"Name" : "imag_buf", "Type" : "Memory", "Direction" : "IO",
				"SubConnect" : [
					{"ID" : "8", "SubInstance" : "grp_cfu_hls_Pipeline_HANN_LOOP_fu_485", "Port" : "imag_buf", "Inst_start_state" : "2", "Inst_end_state" : "5"},
					{"ID" : "12", "SubInstance" : "grp_cfu_hls_Pipeline_BITREV_LOOP_fu_497", "Port" : "imag_buf", "Inst_start_state" : "6", "Inst_end_state" : "7"},
					{"ID" : "14", "SubInstance" : "grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505", "Port" : "imag_buf", "Inst_start_state" : "8", "Inst_end_state" : "9"},
					{"ID" : "23", "SubInstance" : "grp_cfu_hls_Pipeline_POWER_LOOP_fu_517", "Port" : "imag_buf", "Inst_start_state" : "10", "Inst_end_state" : "11"}]},
			{"Name" : "cos_table_fixed", "Type" : "Memory", "Direction" : "I",
				"SubConnect" : [
					{"ID" : "14", "SubInstance" : "grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505", "Port" : "cos_table_fixed", "Inst_start_state" : "8", "Inst_end_state" : "9"}]},
			{"Name" : "sin_table_fixed", "Type" : "Memory", "Direction" : "I",
				"SubConnect" : [
					{"ID" : "14", "SubInstance" : "grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505", "Port" : "sin_table_fixed", "Inst_start_state" : "8", "Inst_end_state" : "9"}]},
			{"Name" : "power_buf", "Type" : "Memory", "Direction" : "IO",
				"SubConnect" : [
					{"ID" : "23", "SubInstance" : "grp_cfu_hls_Pipeline_POWER_LOOP_fu_517", "Port" : "power_buf", "Inst_start_state" : "10", "Inst_end_state" : "11"},
					{"ID" : "27", "SubInstance" : "grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527", "Port" : "power_buf", "Inst_start_state" : "15", "Inst_end_state" : "16"}]},
			{"Name" : "mel_k_start_fixed", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "mel_k_len_fixed", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "mel_weights_compact_fixed", "Type" : "Memory", "Direction" : "I",
				"SubConnect" : [
					{"ID" : "27", "SubInstance" : "grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527", "Port" : "mel_weights_compact_fixed", "Inst_start_state" : "15", "Inst_end_state" : "16"}]},
			{"Name" : "mel_out", "Type" : "Memory", "Direction" : "IO"}],
		"Loop" : [
			{"Name" : "MEL_LOOP", "PipelineType" : "no",
				"LoopDec" : {"FSMBitwidth" : "34", "FirstState" : "ap_ST_fsm_state12", "LastState" : ["ap_ST_fsm_state31"], "QuitState" : ["ap_ST_fsm_state12"], "PreState" : ["ap_ST_fsm_state11"], "PostState" : ["ap_ST_fsm_state32"], "OneDepthLoop" : "0", "OneStateBlock": ""}}]},
	{"ID" : "1", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.frame_buf_U", "Parent" : "0"},
	{"ID" : "2", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.real_buf_U", "Parent" : "0"},
	{"ID" : "3", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.imag_buf_U", "Parent" : "0"},
	{"ID" : "4", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.power_buf_U", "Parent" : "0"},
	{"ID" : "5", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.mel_k_start_fixed_U", "Parent" : "0"},
	{"ID" : "6", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.mel_k_len_fixed_U", "Parent" : "0"},
	{"ID" : "7", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.mel_out_U", "Parent" : "0"},
	{"ID" : "8", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_HANN_LOOP_fu_485", "Parent" : "0", "Child" : ["9", "10", "11"],
		"CDFG" : "cfu_hls_Pipeline_HANN_LOOP",
		"Protocol" : "ap_ctrl_hs",
		"ControlExist" : "1", "ap_start" : "1", "ap_ready" : "1", "ap_done" : "1", "ap_continue" : "0", "ap_idle" : "1", "real_start" : "0",
		"Pipeline" : "None", "UnalignedPipeline" : "0", "RewindPipeline" : "0", "ProcessNetwork" : "0",
		"II" : "0",
		"VariableLatency" : "1", "ExactLatency" : "-1", "EstimateLatencyMin" : "2056", "EstimateLatencyMax" : "2056",
		"Combinational" : "0",
		"Datapath" : "0",
		"ClockEnable" : "0",
		"HasSubDataflow" : "0",
		"InDataflowNetwork" : "0",
		"HasNonBlockingOperation" : "0",
		"IsBlackBox" : "0",
		"Port" : [
			{"Name" : "frame_buf", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "hann_window_fixed", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "real_buf", "Type" : "Memory", "Direction" : "O"},
			{"Name" : "imag_buf", "Type" : "Memory", "Direction" : "O"}],
		"Loop" : [
			{"Name" : "HANN_LOOP", "PipelineType" : "UPC",
				"LoopDec" : {"FSMBitwidth" : "1", "FirstState" : "ap_ST_fsm_pp0_stage0", "FirstStateIter" : "ap_enable_reg_pp0_iter0", "FirstStateBlock" : "ap_block_pp0_stage0_subdone", "LastState" : "ap_ST_fsm_pp0_stage0", "LastStateIter" : "ap_enable_reg_pp0_iter7", "LastStateBlock" : "ap_block_pp0_stage0_subdone", "QuitState" : "ap_ST_fsm_pp0_stage0", "QuitStateIter" : "ap_enable_reg_pp0_iter7", "QuitStateBlock" : "ap_block_pp0_stage0_subdone", "OneDepthLoop" : "0", "has_ap_ctrl" : "1", "has_continue" : "0"}}]},
	{"ID" : "9", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_HANN_LOOP_fu_485.hann_window_fixed_U", "Parent" : "8"},
	{"ID" : "10", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_HANN_LOOP_fu_485.mul_17ns_32s_48_5_1_U1", "Parent" : "8"},
	{"ID" : "11", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_HANN_LOOP_fu_485.flow_control_loop_pipe_sequential_init_U", "Parent" : "8"},
	{"ID" : "12", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_BITREV_LOOP_fu_497", "Parent" : "0", "Child" : ["13"],
		"CDFG" : "cfu_hls_Pipeline_BITREV_LOOP",
		"Protocol" : "ap_ctrl_hs",
		"ControlExist" : "1", "ap_start" : "1", "ap_ready" : "1", "ap_done" : "1", "ap_continue" : "0", "ap_idle" : "1", "real_start" : "0",
		"Pipeline" : "None", "UnalignedPipeline" : "0", "RewindPipeline" : "0", "ProcessNetwork" : "0",
		"II" : "0",
		"VariableLatency" : "1", "ExactLatency" : "-1", "EstimateLatencyMin" : "6146", "EstimateLatencyMax" : "6146",
		"Combinational" : "0",
		"Datapath" : "0",
		"ClockEnable" : "0",
		"HasSubDataflow" : "0",
		"InDataflowNetwork" : "0",
		"HasNonBlockingOperation" : "0",
		"IsBlackBox" : "0",
		"Port" : [
			{"Name" : "real_buf", "Type" : "Memory", "Direction" : "IO"},
			{"Name" : "imag_buf", "Type" : "Memory", "Direction" : "IO"}],
		"Loop" : [
			{"Name" : "BITREV_LOOP", "PipelineType" : "UPC",
				"LoopDec" : {"FSMBitwidth" : "3", "FirstState" : "ap_ST_fsm_state1", "FirstStateIter" : "", "FirstStateBlock" : "ap_ST_fsm_state1_blk", "LastState" : "ap_ST_fsm_state3", "LastStateIter" : "", "LastStateBlock" : "ap_ST_fsm_state3_blk", "QuitState" : "ap_ST_fsm_state3", "QuitStateIter" : "", "QuitStateBlock" : "ap_ST_fsm_state3_blk", "OneDepthLoop" : "1", "has_ap_ctrl" : "1", "has_continue" : "0"}}]},
	{"ID" : "13", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_BITREV_LOOP_fu_497.flow_control_loop_pipe_sequential_init_U", "Parent" : "12"},
	{"ID" : "14", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505", "Parent" : "0", "Child" : ["15", "16", "17", "18", "19", "20", "21", "22"],
		"CDFG" : "cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY",
		"Protocol" : "ap_ctrl_hs",
		"ControlExist" : "1", "ap_start" : "1", "ap_ready" : "1", "ap_done" : "1", "ap_continue" : "0", "ap_idle" : "1", "real_start" : "0",
		"Pipeline" : "None", "UnalignedPipeline" : "0", "RewindPipeline" : "0", "ProcessNetwork" : "0",
		"II" : "0",
		"VariableLatency" : "1", "ExactLatency" : "-1", "EstimateLatencyMin" : "22543", "EstimateLatencyMax" : "22543",
		"Combinational" : "0",
		"Datapath" : "0",
		"ClockEnable" : "0",
		"HasSubDataflow" : "0",
		"InDataflowNetwork" : "0",
		"HasNonBlockingOperation" : "0",
		"IsBlackBox" : "0",
		"Port" : [
			{"Name" : "cos_table_fixed", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "sin_table_fixed", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "real_buf", "Type" : "Memory", "Direction" : "IO"},
			{"Name" : "imag_buf", "Type" : "Memory", "Direction" : "IO"}],
		"Loop" : [
			{"Name" : "FFT_STAGE_FFT_BUTTERFLY", "PipelineType" : "UPC",
				"LoopDec" : {"FSMBitwidth" : "2", "FirstState" : "ap_ST_fsm_pp0_stage0", "FirstStateIter" : "ap_enable_reg_pp0_iter0", "FirstStateBlock" : "ap_block_pp0_stage0_subdone", "LastState" : "ap_ST_fsm_pp0_stage1", "LastStateIter" : "ap_enable_reg_pp0_iter7", "LastStateBlock" : "ap_block_pp0_stage1_subdone", "QuitState" : "ap_ST_fsm_pp0_stage1", "QuitStateIter" : "ap_enable_reg_pp0_iter7", "QuitStateBlock" : "ap_block_pp0_stage1_subdone", "OneDepthLoop" : "0", "has_ap_ctrl" : "1", "has_continue" : "0"}}]},
	{"ID" : "15", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.cos_table_fixed_U", "Parent" : "14"},
	{"ID" : "16", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.sin_table_fixed_U", "Parent" : "14"},
	{"ID" : "17", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.mul_32s_17s_48_5_1_U9", "Parent" : "14"},
	{"ID" : "18", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.mul_32s_17s_48_5_1_U10", "Parent" : "14"},
	{"ID" : "19", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.mul_32s_18s_48_5_1_U11", "Parent" : "14"},
	{"ID" : "20", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.mul_32s_18s_48_5_1_U12", "Parent" : "14"},
	{"ID" : "21", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.mul_10s_10s_10_5_1_U13", "Parent" : "14"},
	{"ID" : "22", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505.flow_control_loop_pipe_sequential_init_U", "Parent" : "14"},
	{"ID" : "23", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_POWER_LOOP_fu_517", "Parent" : "0", "Child" : ["24", "25", "26"],
		"CDFG" : "cfu_hls_Pipeline_POWER_LOOP",
		"Protocol" : "ap_ctrl_hs",
		"ControlExist" : "1", "ap_start" : "1", "ap_ready" : "1", "ap_done" : "1", "ap_continue" : "0", "ap_idle" : "1", "real_start" : "0",
		"Pipeline" : "None", "UnalignedPipeline" : "0", "RewindPipeline" : "0", "ProcessNetwork" : "0",
		"II" : "0",
		"VariableLatency" : "1", "ExactLatency" : "-1", "EstimateLatencyMin" : "1034", "EstimateLatencyMax" : "1034",
		"Combinational" : "0",
		"Datapath" : "0",
		"ClockEnable" : "0",
		"HasSubDataflow" : "0",
		"InDataflowNetwork" : "0",
		"HasNonBlockingOperation" : "0",
		"IsBlackBox" : "0",
		"Port" : [
			{"Name" : "real_buf", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "imag_buf", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "power_buf", "Type" : "Memory", "Direction" : "O"}],
		"Loop" : [
			{"Name" : "POWER_LOOP", "PipelineType" : "UPC",
				"LoopDec" : {"FSMBitwidth" : "1", "FirstState" : "ap_ST_fsm_pp0_stage0", "FirstStateIter" : "ap_enable_reg_pp0_iter0", "FirstStateBlock" : "ap_block_pp0_stage0_subdone", "LastState" : "ap_ST_fsm_pp0_stage0", "LastStateIter" : "ap_enable_reg_pp0_iter8", "LastStateBlock" : "ap_block_pp0_stage0_subdone", "QuitState" : "ap_ST_fsm_pp0_stage0", "QuitStateIter" : "ap_enable_reg_pp0_iter8", "QuitStateBlock" : "ap_block_pp0_stage0_subdone", "OneDepthLoop" : "0", "has_ap_ctrl" : "1", "has_continue" : "0"}}]},
	{"ID" : "24", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_POWER_LOOP_fu_517.mul_32s_32s_58_5_1_U21", "Parent" : "23"},
	{"ID" : "25", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_POWER_LOOP_fu_517.mul_32s_32s_58_5_1_U22", "Parent" : "23"},
	{"ID" : "26", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_POWER_LOOP_fu_517.flow_control_loop_pipe_sequential_init_U", "Parent" : "23"},
	{"ID" : "27", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527", "Parent" : "0", "Child" : ["28", "29", "30"],
		"CDFG" : "cfu_hls_Pipeline_MEL_ACCUM",
		"Protocol" : "ap_ctrl_hs",
		"ControlExist" : "1", "ap_start" : "1", "ap_ready" : "1", "ap_done" : "1", "ap_continue" : "0", "ap_idle" : "1", "real_start" : "0",
		"Pipeline" : "None", "UnalignedPipeline" : "0", "RewindPipeline" : "0", "ProcessNetwork" : "0",
		"II" : "0",
		"VariableLatency" : "1", "ExactLatency" : "-1", "EstimateLatencyMin" : "24", "EstimateLatencyMax" : "167",
		"Combinational" : "0",
		"Datapath" : "0",
		"ClockEnable" : "0",
		"HasSubDataflow" : "0",
		"InDataflowNetwork" : "0",
		"HasNonBlockingOperation" : "0",
		"IsBlackBox" : "0",
		"Port" : [
			{"Name" : "weight_idx", "Type" : "None", "Direction" : "I"},
			{"Name" : "weight_idx_2", "Type" : "None", "Direction" : "I"},
			{"Name" : "k_start", "Type" : "None", "Direction" : "I"},
			{"Name" : "mel_pwr_out", "Type" : "Vld", "Direction" : "O"},
			{"Name" : "power_buf", "Type" : "Memory", "Direction" : "I"},
			{"Name" : "mel_weights_compact_fixed", "Type" : "Memory", "Direction" : "I"}],
		"Loop" : [
			{"Name" : "MEL_ACCUM", "PipelineType" : "UPC",
				"LoopDec" : {"FSMBitwidth" : "1", "FirstState" : "ap_ST_fsm_pp0_stage0", "FirstStateIter" : "ap_enable_reg_pp0_iter0", "FirstStateBlock" : "ap_block_pp0_stage0_subdone", "LastState" : "ap_ST_fsm_pp0_stage0", "LastStateIter" : "ap_enable_reg_pp0_iter8", "LastStateBlock" : "ap_block_pp0_stage0_subdone", "QuitState" : "ap_ST_fsm_pp0_stage0", "QuitStateIter" : "ap_enable_reg_pp0_iter8", "QuitStateBlock" : "ap_block_pp0_stage0_subdone", "OneDepthLoop" : "0", "has_ap_ctrl" : "1", "has_continue" : "0"}}]},
	{"ID" : "28", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527.mel_weights_compact_fixed_U", "Parent" : "27"},
	{"ID" : "29", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527.mul_16ns_32s_48_5_1_U27", "Parent" : "27"},
	{"ID" : "30", "Level" : "2", "Path" : "`AUTOTB_DUT_INST.grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527.flow_control_loop_pipe_sequential_init_U", "Parent" : "27"},
	{"ID" : "31", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.lshr_32ns_5ns_32_2_1_U35", "Parent" : "0"}]}


set ArgLastReadFirstWriteLatency {
	cfu_hls {
		funct3_i {Type I LastRead -1 FirstWrite -1}
		funct7_i {Type I LastRead 0 FirstWrite -1}
		src1_i {Type I LastRead 0 FirstWrite -1}
		src2_i {Type I LastRead 0 FirstWrite -1}
		rslt_o {Type O LastRead -1 FirstWrite 1}
		frame_buf {Type IO LastRead -1 FirstWrite -1}
		hann_window_fixed {Type I LastRead -1 FirstWrite -1}
		real_buf {Type IO LastRead -1 FirstWrite -1}
		imag_buf {Type IO LastRead -1 FirstWrite -1}
		cos_table_fixed {Type I LastRead -1 FirstWrite -1}
		sin_table_fixed {Type I LastRead -1 FirstWrite -1}
		power_buf {Type IO LastRead -1 FirstWrite -1}
		mel_k_start_fixed {Type I LastRead -1 FirstWrite -1}
		mel_k_len_fixed {Type I LastRead -1 FirstWrite -1}
		mel_weights_compact_fixed {Type I LastRead -1 FirstWrite -1}
		mel_out {Type IO LastRead -1 FirstWrite -1}}
	cfu_hls_Pipeline_HANN_LOOP {
		frame_buf {Type I LastRead 0 FirstWrite -1}
		hann_window_fixed {Type I LastRead -1 FirstWrite -1}
		real_buf {Type O LastRead -1 FirstWrite 7}
		imag_buf {Type O LastRead -1 FirstWrite 1}}
	cfu_hls_Pipeline_BITREV_LOOP {
		real_buf {Type IO LastRead 1 FirstWrite 1}
		imag_buf {Type IO LastRead 1 FirstWrite 1}}
	cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY {
		cos_table_fixed {Type I LastRead -1 FirstWrite -1}
		sin_table_fixed {Type I LastRead -1 FirstWrite -1}
		real_buf {Type IO LastRead 12 FirstWrite 14}
		imag_buf {Type IO LastRead 12 FirstWrite 14}}
	cfu_hls_Pipeline_POWER_LOOP {
		real_buf {Type I LastRead 0 FirstWrite -1}
		imag_buf {Type I LastRead 0 FirstWrite -1}
		power_buf {Type O LastRead -1 FirstWrite 8}}
	cfu_hls_Pipeline_MEL_ACCUM {
		weight_idx {Type I LastRead 0 FirstWrite -1}
		weight_idx_2 {Type I LastRead 0 FirstWrite -1}
		k_start {Type I LastRead 0 FirstWrite -1}
		mel_pwr_out {Type O LastRead -1 FirstWrite 8}
		power_buf {Type I LastRead 1 FirstWrite -1}
		mel_weights_compact_fixed {Type I LastRead -1 FirstWrite -1}}}

set hasDtUnsupportedChannel 0

set PerformanceInfo {[
	{"Name" : "Latency", "Min" : "4", "Max" : "37774"}
	, {"Name" : "Interval", "Min" : "5", "Max" : "37775"}
]}

set PipelineEnableSignalInfo {[
]}

set Spec2ImplPortList { 
	funct3_i { ap_none {  { funct3_i in_data 0 8 } } }
	funct7_i { ap_none {  { funct7_i in_data 0 8 } } }
	src1_i { ap_none {  { src1_i in_data 0 32 } } }
	src2_i { ap_none {  { src2_i in_data 0 32 } } }
	rslt_o { ap_none {  { rslt_o out_data 1 32 } } }
}

set maxi_interface_dict [dict create]

# RTL port scheduling information:
set fifoSchedulingInfoList { 
}

# RTL bus port read request latency information:
set busReadReqLatencyList { 
}

# RTL bus port write response latency information:
set busWriteResLatencyList { 
}

# RTL array port load latency information:
set memoryLoadLatencyList { 
}
