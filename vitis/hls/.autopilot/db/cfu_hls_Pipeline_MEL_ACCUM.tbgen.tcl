set moduleName cfu_hls_Pipeline_MEL_ACCUM
set isTopModule 0
set isCombinational 0
set isDatapathOnly 0
set isPipelined 1
set pipeline_type loop_auto_rewind
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
set C_modelName {cfu_hls_Pipeline_MEL_ACCUM}
set C_modelType { void 0 }
set ap_memory_interface_dict [dict create]
dict set ap_memory_interface_dict power_buf { MEM_WIDTH 32 MEM_SIZE 4100 MASTER_TYPE BRAM_CTRL MEM_ADDRESS_MODE WORD_ADDRESS PACKAGE_IO port READ_LATENCY 1 }
set C_modelArgList {
	{ weight_idx int 13 regular  }
	{ weight_idx_2 int 13 regular  }
	{ k_start int 10 regular  }
	{ mel_pwr_out int 48 regular {pointer 1}  }
	{ power_buf int 32 regular {array 1025 { 1 3 } 1 1 } {global 0}  }
}
set hasAXIMCache 0
set l_AXIML2Cache [list]
set AXIMCacheInstDict [dict create]
set C_modelArgMapList {[ 
	{ "Name" : "weight_idx", "interface" : "wire", "bitwidth" : 13, "direction" : "READONLY"} , 
 	{ "Name" : "weight_idx_2", "interface" : "wire", "bitwidth" : 13, "direction" : "READONLY"} , 
 	{ "Name" : "k_start", "interface" : "wire", "bitwidth" : 10, "direction" : "READONLY"} , 
 	{ "Name" : "mel_pwr_out", "interface" : "wire", "bitwidth" : 48, "direction" : "WRITEONLY"} , 
 	{ "Name" : "power_buf", "interface" : "memory", "bitwidth" : 32, "direction" : "READONLY", "extern" : 0} ]}
# RTL Port declarations: 
set portNum 13
set portList { 
	{ ap_clk sc_in sc_logic 1 clock -1 } 
	{ ap_start sc_in sc_logic 1 start -1 } 
	{ ap_done sc_out sc_logic 1 predone -1 } 
	{ ap_idle sc_out sc_logic 1 done -1 } 
	{ ap_ready sc_out sc_logic 1 ready -1 } 
	{ weight_idx sc_in sc_lv 13 signal 0 } 
	{ weight_idx_2 sc_in sc_lv 13 signal 1 } 
	{ k_start sc_in sc_lv 10 signal 2 } 
	{ mel_pwr_out sc_out sc_lv 48 signal 3 } 
	{ mel_pwr_out_ap_vld sc_out sc_logic 1 outvld 3 } 
	{ power_buf_address0 sc_out sc_lv 11 signal 4 } 
	{ power_buf_ce0 sc_out sc_logic 1 signal 4 } 
	{ power_buf_q0 sc_in sc_lv 32 signal 4 } 
}
set NewPortList {[ 
	{ "name": "ap_clk", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "clock", "bundle":{"name": "ap_clk", "role": "default" }} , 
 	{ "name": "ap_start", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "start", "bundle":{"name": "ap_start", "role": "default" }} , 
 	{ "name": "ap_done", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "predone", "bundle":{"name": "ap_done", "role": "default" }} , 
 	{ "name": "ap_idle", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "done", "bundle":{"name": "ap_idle", "role": "default" }} , 
 	{ "name": "ap_ready", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "ready", "bundle":{"name": "ap_ready", "role": "default" }} , 
 	{ "name": "weight_idx", "direction": "in", "datatype": "sc_lv", "bitwidth":13, "type": "signal", "bundle":{"name": "weight_idx", "role": "default" }} , 
 	{ "name": "weight_idx_2", "direction": "in", "datatype": "sc_lv", "bitwidth":13, "type": "signal", "bundle":{"name": "weight_idx_2", "role": "default" }} , 
 	{ "name": "k_start", "direction": "in", "datatype": "sc_lv", "bitwidth":10, "type": "signal", "bundle":{"name": "k_start", "role": "default" }} , 
 	{ "name": "mel_pwr_out", "direction": "out", "datatype": "sc_lv", "bitwidth":48, "type": "signal", "bundle":{"name": "mel_pwr_out", "role": "default" }} , 
 	{ "name": "mel_pwr_out_ap_vld", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "outvld", "bundle":{"name": "mel_pwr_out", "role": "ap_vld" }} , 
 	{ "name": "power_buf_address0", "direction": "out", "datatype": "sc_lv", "bitwidth":11, "type": "signal", "bundle":{"name": "power_buf", "role": "address0" }} , 
 	{ "name": "power_buf_ce0", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "power_buf", "role": "ce0" }} , 
 	{ "name": "power_buf_q0", "direction": "in", "datatype": "sc_lv", "bitwidth":32, "type": "signal", "bundle":{"name": "power_buf", "role": "q0" }}  ]}

set RtlHierarchyInfo {[
	{"ID" : "0", "Level" : "0", "Path" : "`AUTOTB_DUT_INST", "Parent" : "", "Child" : ["1", "2", "3"],
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
	{"ID" : "1", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.mel_weights_compact_fixed_U", "Parent" : "0"},
	{"ID" : "2", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.mul_16ns_32s_48_5_1_U27", "Parent" : "0"},
	{"ID" : "3", "Level" : "1", "Path" : "`AUTOTB_DUT_INST.flow_control_loop_pipe_sequential_init_U", "Parent" : "0"}]}


set ArgLastReadFirstWriteLatency {
	cfu_hls_Pipeline_MEL_ACCUM {
		weight_idx {Type I LastRead 0 FirstWrite -1}
		weight_idx_2 {Type I LastRead 0 FirstWrite -1}
		k_start {Type I LastRead 0 FirstWrite -1}
		mel_pwr_out {Type O LastRead -1 FirstWrite 8}
		power_buf {Type I LastRead 1 FirstWrite -1}
		mel_weights_compact_fixed {Type I LastRead -1 FirstWrite -1}}}

set hasDtUnsupportedChannel 0

set PerformanceInfo {[
	{"Name" : "Latency", "Min" : "24", "Max" : "167"}
	, {"Name" : "Interval", "Min" : "24", "Max" : "167"}
]}

set PipelineEnableSignalInfo {[
	{"Pipeline" : "0", "EnableSignal" : "ap_enable_pp0"}
]}

set Spec2ImplPortList { 
	weight_idx { ap_none {  { weight_idx in_data 0 13 } } }
	weight_idx_2 { ap_none {  { weight_idx_2 in_data 0 13 } } }
	k_start { ap_none {  { k_start in_data 0 10 } } }
	mel_pwr_out { ap_vld {  { mel_pwr_out out_data 1 48 }  { mel_pwr_out_ap_vld out_vld 1 1 } } }
	power_buf { ap_memory {  { power_buf_address0 mem_address 1 11 }  { power_buf_ce0 mem_ce 1 1 }  { power_buf_q0 mem_dout 0 32 } } }
}
