set ModuleHierarchy {[{
"Name" : "cfu_hls","ID" : "0","Type" : "sequential",
"SubInsts" : [
	{"Name" : "grp_cfu_hls_Pipeline_HANN_LOOP_fu_485","ID" : "1","Type" : "sequential",
		"SubLoops" : [
		{"Name" : "HANN_LOOP","ID" : "2","Type" : "pipeline"},]},
	{"Name" : "grp_cfu_hls_Pipeline_BITREV_LOOP_fu_497","ID" : "3","Type" : "sequential",
		"SubLoops" : [
		{"Name" : "BITREV_LOOP","ID" : "4","Type" : "pipeline"},]},
	{"Name" : "grp_cfu_hls_Pipeline_FFT_STAGE_FFT_BUTTERFLY_fu_505","ID" : "5","Type" : "sequential",
		"SubLoops" : [
		{"Name" : "FFT_STAGE_FFT_BUTTERFLY","ID" : "6","Type" : "pipeline"},]},
	{"Name" : "grp_cfu_hls_Pipeline_POWER_LOOP_fu_517","ID" : "7","Type" : "sequential",
		"SubLoops" : [
		{"Name" : "POWER_LOOP","ID" : "8","Type" : "pipeline"},]},],
"SubLoops" : [
	{"Name" : "MEL_LOOP","ID" : "9","Type" : "no",
	"SubInsts" : [
	{"Name" : "grp_cfu_hls_Pipeline_MEL_ACCUM_fu_527","ID" : "10","Type" : "sequential",
			"SubLoops" : [
			{"Name" : "MEL_ACCUM","ID" : "11","Type" : "pipeline"},]},]},]
}]}