// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_0
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_0
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] e_p [ 0 : 8 ],
    input wire logic [ 4 : 0 ] c_src [ 0 : 8 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_CONSERVE_SOURCE_CREDIT_ACCOUNT: assert property (@(posedge clk) disable iff (!rst_ok)
        (((c_src[0] == (5'd16 - $past(rst_ok ? e_p[0] : 5'd0))) &&
        (c_src[1] == (5'd16 - $past(rst_ok ? e_p[1] : 5'd0))) &&
        (c_src[2] == (5'd16 - $past(rst_ok ? e_p[2] : 5'd0))) &&
        (c_src[3] == (5'd16 - $past(rst_ok ? e_p[3] : 5'd0))) &&
        (c_src[4] == (5'd16 - $past(rst_ok ? e_p[4] : 5'd0))) &&
        (c_src[5] == (5'd16 - $past(rst_ok ? e_p[5] : 5'd0))) &&
        (c_src[6] == (5'd16 - $past(rst_ok ? e_p[6] : 5'd0))) &&
        (c_src[7] == (5'd16 - $past(rst_ok ? e_p[7] : 5'd0))) &&
        (c_src[8] == (5'd16 - $past(rst_ok ? e_p[8] : 5'd0))))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_0
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_1
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_1
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_requests [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_MUTEX_ROUTE_REQ_ONEHOT_MESH: assert property (@(posedge clk) disable iff (!rst_ok)
    (($onehot0(mesh_requests[0])) &&
        ($onehot0(mesh_requests[1])) &&
        ($onehot0(mesh_requests[2])) &&
        ($onehot0(mesh_requests[3])) &&
        ($onehot0(mesh_requests[4])) &&
        ($onehot0(mesh_requests[5])) &&
        ($onehot0(mesh_requests[6])) &&
        ($onehot0(mesh_requests[7])) &&
        ($onehot0(mesh_requests[8])) &&
        ($onehot0(mesh_requests[9])) &&
        ($onehot0(mesh_requests[10])) &&
        ($onehot0(mesh_requests[11])) &&
        ($onehot0(mesh_requests[12])) &&
        ($onehot0(mesh_requests[13])) &&
        ($onehot0(mesh_requests[14])) &&
        ($onehot0(mesh_requests[15])) &&
        ($onehot0(mesh_requests[16])) &&
        ($onehot0(mesh_requests[17])) &&
        ($onehot0(mesh_requests[18])) &&
        ($onehot0(mesh_requests[19])) &&
        ($onehot0(mesh_requests[20])) &&
        ($onehot0(mesh_requests[21])) &&
        ($onehot0(mesh_requests[22])) &&
        ($onehot0(mesh_requests[23])) &&
        ($onehot0(mesh_requests[24])) &&
        ($onehot0(mesh_requests[25])) &&
        ($onehot0(mesh_requests[26])) &&
        ($onehot0(mesh_requests[27])) &&
        ($onehot0(mesh_requests[28])) &&
        ($onehot0(mesh_requests[29])) &&
        ($onehot0(mesh_requests[30])) &&
        ($onehot0(mesh_requests[31])) &&
        ($onehot0(mesh_requests[32])) &&
        ($onehot0(mesh_requests[33])) &&
        ($onehot0(mesh_requests[34])) &&
        ($onehot0(mesh_requests[35])) &&
        ($onehot0(mesh_requests[36])) &&
        ($onehot0(mesh_requests[37])) &&
        ($onehot0(mesh_requests[38])) &&
        ($onehot0(mesh_requests[39])) &&
        ($onehot0(mesh_requests[40])) &&
        ($onehot0(mesh_requests[41])) &&
        ($onehot0(mesh_requests[42])) &&
        ($onehot0(mesh_requests[43])) &&
        ($onehot0(mesh_requests[44])) &&
        ($onehot0(mesh_requests[45])) &&
        ($onehot0(mesh_requests[46])) &&
        ($onehot0(mesh_requests[47])) &&
        ($onehot0(mesh_requests[48])) &&
        ($onehot0(mesh_requests[49])) &&
        ($onehot0(mesh_requests[50])) &&
        ($onehot0(mesh_requests[51])) &&
        ($onehot0(mesh_requests[52])) &&
        ($onehot0(mesh_requests[53])) &&
        ($onehot0(mesh_requests[54])) &&
        ($onehot0(mesh_requests[55])) &&
        ($onehot0(mesh_requests[56])) &&
        ($onehot0(mesh_requests[57])) &&
        ($onehot0(mesh_requests[58])) &&
        ($onehot0(mesh_requests[59])) &&
        ($onehot0(mesh_requests[60])) &&
        ($onehot0(mesh_requests[61])) &&
        ($onehot0(mesh_requests[62])) &&
        ($onehot0(mesh_requests[63])) &&
        ($onehot0(mesh_requests[64])) &&
        ($onehot0(mesh_requests[65])) &&
        ($onehot0(mesh_requests[66])) &&
        ($onehot0(mesh_requests[67])) &&
        ($onehot0(mesh_requests[68])) &&
        ($onehot0(mesh_requests[69])) &&
        ($onehot0(mesh_requests[70])) &&
        ($onehot0(mesh_requests[71])) &&
        ($onehot0(mesh_requests[72])) &&
        ($onehot0(mesh_requests[73])) &&
        ($onehot0(mesh_requests[74])) &&
        ($onehot0(mesh_requests[75])) &&
        ($onehot0(mesh_requests[76])) &&
        ($onehot0(mesh_requests[77])) &&
        ($onehot0(mesh_requests[78])) &&
        ($onehot0(mesh_requests[79])) &&
        ($onehot0(mesh_requests[80])) &&
        ($onehot0(mesh_requests[81])) &&
        ($onehot0(mesh_requests[82])) &&
        ($onehot0(mesh_requests[83])) &&
        ($onehot0(mesh_requests[84])) &&
        ($onehot0(mesh_requests[85])) &&
        ($onehot0(mesh_requests[86])) &&
        ($onehot0(mesh_requests[87])) &&
        ($onehot0(mesh_requests[88])) &&
        ($onehot0(mesh_requests[89])) &&
        ($onehot0(mesh_requests[90])) &&
        ($onehot0(mesh_requests[91])) &&
        ($onehot0(mesh_requests[92])) &&
        ($onehot0(mesh_requests[93])) &&
        ($onehot0(mesh_requests[94])) &&
        ($onehot0(mesh_requests[95])) &&
        ($onehot0(mesh_requests[96])) &&
        ($onehot0(mesh_requests[97])) &&
        ($onehot0(mesh_requests[98])) &&
        ($onehot0(mesh_requests[99])) &&
        ($onehot0(mesh_requests[100])) &&
        ($onehot0(mesh_requests[101])) &&
        ($onehot0(mesh_requests[102])) &&
        ($onehot0(mesh_requests[103])) &&
        ($onehot0(mesh_requests[104])) &&
        ($onehot0(mesh_requests[105])) &&
        ($onehot0(mesh_requests[106])) &&
        ($onehot0(mesh_requests[107])) &&
        ($onehot0(mesh_requests[108])) &&
        ($onehot0(mesh_requests[109])) &&
        ($onehot0(mesh_requests[110])) &&
        ($onehot0(mesh_requests[111])) &&
        ($onehot0(mesh_requests[112])) &&
        ($onehot0(mesh_requests[113])) &&
        ($onehot0(mesh_requests[114])) &&
        ($onehot0(mesh_requests[115])) &&
        ($onehot0(mesh_requests[116])) &&
        ($onehot0(mesh_requests[117])) &&
        ($onehot0(mesh_requests[118])) &&
        ($onehot0(mesh_requests[119])) &&
        ($onehot0(mesh_requests[120])) &&
        ($onehot0(mesh_requests[121])) &&
        ($onehot0(mesh_requests[122])) &&
        ($onehot0(mesh_requests[123])) &&
        ($onehot0(mesh_requests[124])) &&
        ($onehot0(mesh_requests[125])) &&
        ($onehot0(mesh_requests[126])) &&
        ($onehot0(mesh_requests[127])) &&
        ($onehot0(mesh_requests[128])) &&
        ($onehot0(mesh_requests[129])) &&
        ($onehot0(mesh_requests[130])) &&
        ($onehot0(mesh_requests[131])) &&
        ($onehot0(mesh_requests[132])) &&
        ($onehot0(mesh_requests[133])) &&
        ($onehot0(mesh_requests[134])))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_1
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_2
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_2
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ],
    input wire logic [ 3 : 0 ] mesh_head [ 0 : 134 ],
    input wire logic [ 3 : 0 ] mesh_tail [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_BOUND_NIB_POINTER_CONSISTENT: assert property (@(posedge clk) disable iff (!rst_ok)
    ((mesh_occupancy[0][1:0] == $unsigned(2'(mesh_tail[0] - mesh_head[0]))) &&
        (mesh_occupancy[1][1:0] == $unsigned(2'(mesh_tail[1] - mesh_head[1]))) &&
        (mesh_occupancy[2][1:0] == $unsigned(2'(mesh_tail[2] - mesh_head[2]))) &&
        (mesh_occupancy[3][1:0] == $unsigned(2'(mesh_tail[3] - mesh_head[3]))) &&
        (mesh_occupancy[4][3:0] == $unsigned(4'(mesh_tail[4] - mesh_head[4]))) &&
        (mesh_occupancy[5][1:0] == $unsigned(2'(mesh_tail[5] - mesh_head[5]))) &&
        (mesh_occupancy[6][1:0] == $unsigned(2'(mesh_tail[6] - mesh_head[6]))) &&
        (mesh_occupancy[7][1:0] == $unsigned(2'(mesh_tail[7] - mesh_head[7]))) &&
        (mesh_occupancy[8][1:0] == $unsigned(2'(mesh_tail[8] - mesh_head[8]))) &&
        (mesh_occupancy[9][3:0] == $unsigned(4'(mesh_tail[9] - mesh_head[9]))) &&
        (mesh_occupancy[10][1:0] == $unsigned(2'(mesh_tail[10] - mesh_head[10]))) &&
        (mesh_occupancy[11][1:0] == $unsigned(2'(mesh_tail[11] - mesh_head[11]))) &&
        (mesh_occupancy[12][1:0] == $unsigned(2'(mesh_tail[12] - mesh_head[12]))) &&
        (mesh_occupancy[13][1:0] == $unsigned(2'(mesh_tail[13] - mesh_head[13]))) &&
        (mesh_occupancy[14][3:0] == $unsigned(4'(mesh_tail[14] - mesh_head[14]))) &&
        (mesh_occupancy[15][1:0] == $unsigned(2'(mesh_tail[15] - mesh_head[15]))) &&
        (mesh_occupancy[16][1:0] == $unsigned(2'(mesh_tail[16] - mesh_head[16]))) &&
        (mesh_occupancy[17][1:0] == $unsigned(2'(mesh_tail[17] - mesh_head[17]))) &&
        (mesh_occupancy[18][1:0] == $unsigned(2'(mesh_tail[18] - mesh_head[18]))) &&
        (mesh_occupancy[19][3:0] == $unsigned(4'(mesh_tail[19] - mesh_head[19]))) &&
        (mesh_occupancy[20][1:0] == $unsigned(2'(mesh_tail[20] - mesh_head[20]))) &&
        (mesh_occupancy[21][1:0] == $unsigned(2'(mesh_tail[21] - mesh_head[21]))) &&
        (mesh_occupancy[22][1:0] == $unsigned(2'(mesh_tail[22] - mesh_head[22]))) &&
        (mesh_occupancy[23][1:0] == $unsigned(2'(mesh_tail[23] - mesh_head[23]))) &&
        (mesh_occupancy[24][3:0] == $unsigned(4'(mesh_tail[24] - mesh_head[24]))) &&
        (mesh_occupancy[25][1:0] == $unsigned(2'(mesh_tail[25] - mesh_head[25]))) &&
        (mesh_occupancy[26][1:0] == $unsigned(2'(mesh_tail[26] - mesh_head[26]))) &&
        (mesh_occupancy[27][1:0] == $unsigned(2'(mesh_tail[27] - mesh_head[27]))) &&
        (mesh_occupancy[28][1:0] == $unsigned(2'(mesh_tail[28] - mesh_head[28]))) &&
        (mesh_occupancy[29][3:0] == $unsigned(4'(mesh_tail[29] - mesh_head[29]))) &&
        (mesh_occupancy[30][1:0] == $unsigned(2'(mesh_tail[30] - mesh_head[30]))) &&
        (mesh_occupancy[31][1:0] == $unsigned(2'(mesh_tail[31] - mesh_head[31]))) &&
        (mesh_occupancy[32][1:0] == $unsigned(2'(mesh_tail[32] - mesh_head[32]))) &&
        (mesh_occupancy[33][1:0] == $unsigned(2'(mesh_tail[33] - mesh_head[33]))) &&
        (mesh_occupancy[34][3:0] == $unsigned(4'(mesh_tail[34] - mesh_head[34]))) &&
        (mesh_occupancy[35][1:0] == $unsigned(2'(mesh_tail[35] - mesh_head[35]))) &&
        (mesh_occupancy[36][1:0] == $unsigned(2'(mesh_tail[36] - mesh_head[36]))) &&
        (mesh_occupancy[37][1:0] == $unsigned(2'(mesh_tail[37] - mesh_head[37]))) &&
        (mesh_occupancy[38][1:0] == $unsigned(2'(mesh_tail[38] - mesh_head[38]))) &&
        (mesh_occupancy[39][3:0] == $unsigned(4'(mesh_tail[39] - mesh_head[39]))) &&
        (mesh_occupancy[40][1:0] == $unsigned(2'(mesh_tail[40] - mesh_head[40]))) &&
        (mesh_occupancy[41][1:0] == $unsigned(2'(mesh_tail[41] - mesh_head[41]))) &&
        (mesh_occupancy[42][1:0] == $unsigned(2'(mesh_tail[42] - mesh_head[42]))) &&
        (mesh_occupancy[43][1:0] == $unsigned(2'(mesh_tail[43] - mesh_head[43]))) &&
        (mesh_occupancy[44][3:0] == $unsigned(4'(mesh_tail[44] - mesh_head[44]))) &&
        (mesh_occupancy[45][1:0] == $unsigned(2'(mesh_tail[45] - mesh_head[45]))) &&
        (mesh_occupancy[46][1:0] == $unsigned(2'(mesh_tail[46] - mesh_head[46]))) &&
        (mesh_occupancy[47][1:0] == $unsigned(2'(mesh_tail[47] - mesh_head[47]))) &&
        (mesh_occupancy[48][1:0] == $unsigned(2'(mesh_tail[48] - mesh_head[48]))) &&
        (mesh_occupancy[49][3:0] == $unsigned(4'(mesh_tail[49] - mesh_head[49]))) &&
        (mesh_occupancy[50][1:0] == $unsigned(2'(mesh_tail[50] - mesh_head[50]))) &&
        (mesh_occupancy[51][1:0] == $unsigned(2'(mesh_tail[51] - mesh_head[51]))) &&
        (mesh_occupancy[52][1:0] == $unsigned(2'(mesh_tail[52] - mesh_head[52]))) &&
        (mesh_occupancy[53][1:0] == $unsigned(2'(mesh_tail[53] - mesh_head[53]))) &&
        (mesh_occupancy[54][3:0] == $unsigned(4'(mesh_tail[54] - mesh_head[54]))) &&
        (mesh_occupancy[55][1:0] == $unsigned(2'(mesh_tail[55] - mesh_head[55]))) &&
        (mesh_occupancy[56][1:0] == $unsigned(2'(mesh_tail[56] - mesh_head[56]))) &&
        (mesh_occupancy[57][1:0] == $unsigned(2'(mesh_tail[57] - mesh_head[57]))) &&
        (mesh_occupancy[58][1:0] == $unsigned(2'(mesh_tail[58] - mesh_head[58]))) &&
        (mesh_occupancy[59][3:0] == $unsigned(4'(mesh_tail[59] - mesh_head[59]))) &&
        (mesh_occupancy[60][1:0] == $unsigned(2'(mesh_tail[60] - mesh_head[60]))) &&
        (mesh_occupancy[61][1:0] == $unsigned(2'(mesh_tail[61] - mesh_head[61]))) &&
        (mesh_occupancy[62][1:0] == $unsigned(2'(mesh_tail[62] - mesh_head[62]))) &&
        (mesh_occupancy[63][1:0] == $unsigned(2'(mesh_tail[63] - mesh_head[63]))) &&
        (mesh_occupancy[64][3:0] == $unsigned(4'(mesh_tail[64] - mesh_head[64]))) &&
        (mesh_occupancy[65][1:0] == $unsigned(2'(mesh_tail[65] - mesh_head[65]))) &&
        (mesh_occupancy[66][1:0] == $unsigned(2'(mesh_tail[66] - mesh_head[66]))) &&
        (mesh_occupancy[67][1:0] == $unsigned(2'(mesh_tail[67] - mesh_head[67]))) &&
        (mesh_occupancy[68][1:0] == $unsigned(2'(mesh_tail[68] - mesh_head[68]))) &&
        (mesh_occupancy[69][3:0] == $unsigned(4'(mesh_tail[69] - mesh_head[69]))) &&
        (mesh_occupancy[70][1:0] == $unsigned(2'(mesh_tail[70] - mesh_head[70]))) &&
        (mesh_occupancy[71][1:0] == $unsigned(2'(mesh_tail[71] - mesh_head[71]))) &&
        (mesh_occupancy[72][1:0] == $unsigned(2'(mesh_tail[72] - mesh_head[72]))) &&
        (mesh_occupancy[73][1:0] == $unsigned(2'(mesh_tail[73] - mesh_head[73]))) &&
        (mesh_occupancy[74][3:0] == $unsigned(4'(mesh_tail[74] - mesh_head[74]))) &&
        (mesh_occupancy[75][1:0] == $unsigned(2'(mesh_tail[75] - mesh_head[75]))) &&
        (mesh_occupancy[76][1:0] == $unsigned(2'(mesh_tail[76] - mesh_head[76]))) &&
        (mesh_occupancy[77][1:0] == $unsigned(2'(mesh_tail[77] - mesh_head[77]))) &&
        (mesh_occupancy[78][1:0] == $unsigned(2'(mesh_tail[78] - mesh_head[78]))) &&
        (mesh_occupancy[79][3:0] == $unsigned(4'(mesh_tail[79] - mesh_head[79]))) &&
        (mesh_occupancy[80][1:0] == $unsigned(2'(mesh_tail[80] - mesh_head[80]))) &&
        (mesh_occupancy[81][1:0] == $unsigned(2'(mesh_tail[81] - mesh_head[81]))) &&
        (mesh_occupancy[82][1:0] == $unsigned(2'(mesh_tail[82] - mesh_head[82]))) &&
        (mesh_occupancy[83][1:0] == $unsigned(2'(mesh_tail[83] - mesh_head[83]))) &&
        (mesh_occupancy[84][3:0] == $unsigned(4'(mesh_tail[84] - mesh_head[84]))) &&
        (mesh_occupancy[85][1:0] == $unsigned(2'(mesh_tail[85] - mesh_head[85]))) &&
        (mesh_occupancy[86][1:0] == $unsigned(2'(mesh_tail[86] - mesh_head[86]))) &&
        (mesh_occupancy[87][1:0] == $unsigned(2'(mesh_tail[87] - mesh_head[87]))) &&
        (mesh_occupancy[88][1:0] == $unsigned(2'(mesh_tail[88] - mesh_head[88]))) &&
        (mesh_occupancy[89][3:0] == $unsigned(4'(mesh_tail[89] - mesh_head[89]))) &&
        (mesh_occupancy[90][1:0] == $unsigned(2'(mesh_tail[90] - mesh_head[90]))) &&
        (mesh_occupancy[91][1:0] == $unsigned(2'(mesh_tail[91] - mesh_head[91]))) &&
        (mesh_occupancy[92][1:0] == $unsigned(2'(mesh_tail[92] - mesh_head[92]))) &&
        (mesh_occupancy[93][1:0] == $unsigned(2'(mesh_tail[93] - mesh_head[93]))) &&
        (mesh_occupancy[94][3:0] == $unsigned(4'(mesh_tail[94] - mesh_head[94]))) &&
        (mesh_occupancy[95][1:0] == $unsigned(2'(mesh_tail[95] - mesh_head[95]))) &&
        (mesh_occupancy[96][1:0] == $unsigned(2'(mesh_tail[96] - mesh_head[96]))) &&
        (mesh_occupancy[97][1:0] == $unsigned(2'(mesh_tail[97] - mesh_head[97]))) &&
        (mesh_occupancy[98][1:0] == $unsigned(2'(mesh_tail[98] - mesh_head[98]))) &&
        (mesh_occupancy[99][3:0] == $unsigned(4'(mesh_tail[99] - mesh_head[99]))) &&
        (mesh_occupancy[100][1:0] == $unsigned(2'(mesh_tail[100] - mesh_head[100]))) &&
        (mesh_occupancy[101][1:0] == $unsigned(2'(mesh_tail[101] - mesh_head[101]))) &&
        (mesh_occupancy[102][1:0] == $unsigned(2'(mesh_tail[102] - mesh_head[102]))) &&
        (mesh_occupancy[103][1:0] == $unsigned(2'(mesh_tail[103] - mesh_head[103]))) &&
        (mesh_occupancy[104][3:0] == $unsigned(4'(mesh_tail[104] - mesh_head[104]))) &&
        (mesh_occupancy[105][1:0] == $unsigned(2'(mesh_tail[105] - mesh_head[105]))) &&
        (mesh_occupancy[106][1:0] == $unsigned(2'(mesh_tail[106] - mesh_head[106]))) &&
        (mesh_occupancy[107][1:0] == $unsigned(2'(mesh_tail[107] - mesh_head[107]))) &&
        (mesh_occupancy[108][1:0] == $unsigned(2'(mesh_tail[108] - mesh_head[108]))) &&
        (mesh_occupancy[109][3:0] == $unsigned(4'(mesh_tail[109] - mesh_head[109]))) &&
        (mesh_occupancy[110][1:0] == $unsigned(2'(mesh_tail[110] - mesh_head[110]))) &&
        (mesh_occupancy[111][1:0] == $unsigned(2'(mesh_tail[111] - mesh_head[111]))) &&
        (mesh_occupancy[112][1:0] == $unsigned(2'(mesh_tail[112] - mesh_head[112]))) &&
        (mesh_occupancy[113][1:0] == $unsigned(2'(mesh_tail[113] - mesh_head[113]))) &&
        (mesh_occupancy[114][3:0] == $unsigned(4'(mesh_tail[114] - mesh_head[114]))) &&
        (mesh_occupancy[115][1:0] == $unsigned(2'(mesh_tail[115] - mesh_head[115]))) &&
        (mesh_occupancy[116][1:0] == $unsigned(2'(mesh_tail[116] - mesh_head[116]))) &&
        (mesh_occupancy[117][1:0] == $unsigned(2'(mesh_tail[117] - mesh_head[117]))) &&
        (mesh_occupancy[118][1:0] == $unsigned(2'(mesh_tail[118] - mesh_head[118]))) &&
        (mesh_occupancy[119][3:0] == $unsigned(4'(mesh_tail[119] - mesh_head[119]))) &&
        (mesh_occupancy[120][1:0] == $unsigned(2'(mesh_tail[120] - mesh_head[120]))) &&
        (mesh_occupancy[121][1:0] == $unsigned(2'(mesh_tail[121] - mesh_head[121]))) &&
        (mesh_occupancy[122][1:0] == $unsigned(2'(mesh_tail[122] - mesh_head[122]))) &&
        (mesh_occupancy[123][1:0] == $unsigned(2'(mesh_tail[123] - mesh_head[123]))) &&
        (mesh_occupancy[124][3:0] == $unsigned(4'(mesh_tail[124] - mesh_head[124]))) &&
        (mesh_occupancy[125][1:0] == $unsigned(2'(mesh_tail[125] - mesh_head[125]))) &&
        (mesh_occupancy[126][1:0] == $unsigned(2'(mesh_tail[126] - mesh_head[126]))) &&
        (mesh_occupancy[127][1:0] == $unsigned(2'(mesh_tail[127] - mesh_head[127]))) &&
        (mesh_occupancy[128][1:0] == $unsigned(2'(mesh_tail[128] - mesh_head[128]))) &&
        (mesh_occupancy[129][3:0] == $unsigned(4'(mesh_tail[129] - mesh_head[129]))) &&
        (mesh_occupancy[130][1:0] == $unsigned(2'(mesh_tail[130] - mesh_head[130]))) &&
        (mesh_occupancy[131][1:0] == $unsigned(2'(mesh_tail[131] - mesh_head[131]))) &&
        (mesh_occupancy[132][1:0] == $unsigned(2'(mesh_tail[132] - mesh_head[132]))) &&
        (mesh_occupancy[133][1:0] == $unsigned(2'(mesh_tail[133] - mesh_head[133]))) &&
        (mesh_occupancy[134][3:0] == $unsigned(4'(mesh_tail[134] - mesh_head[134]))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_2
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_3
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_3
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 2 : 0 ] mesh_output_credits [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_BOUND_OUTPUT_CREDIT_RANGE: assert property (@(posedge clk) disable iff (!rst_ok)
    ((mesh_output_credits[0] <= 3'd4) &&
        (mesh_output_credits[1] <= 3'd4) &&
        (mesh_output_credits[2] <= 3'd4) &&
        (mesh_output_credits[3] <= 3'd4) &&
        (mesh_output_credits[4] <= 3'd4) &&
        (mesh_output_credits[5] <= 3'd4) &&
        (mesh_output_credits[6] <= 3'd4) &&
        (mesh_output_credits[7] <= 3'd4) &&
        (mesh_output_credits[8] <= 3'd4) &&
        (mesh_output_credits[9] <= 3'd4) &&
        (mesh_output_credits[10] <= 3'd4) &&
        (mesh_output_credits[11] <= 3'd4) &&
        (mesh_output_credits[12] <= 3'd4) &&
        (mesh_output_credits[13] <= 3'd4) &&
        (mesh_output_credits[14] <= 3'd4) &&
        (mesh_output_credits[15] <= 3'd4) &&
        (mesh_output_credits[16] <= 3'd4) &&
        (mesh_output_credits[17] <= 3'd4) &&
        (mesh_output_credits[18] <= 3'd4) &&
        (mesh_output_credits[19] <= 3'd4) &&
        (mesh_output_credits[20] <= 3'd4) &&
        (mesh_output_credits[21] <= 3'd4) &&
        (mesh_output_credits[22] <= 3'd4) &&
        (mesh_output_credits[23] <= 3'd4) &&
        (mesh_output_credits[24] <= 3'd4) &&
        (mesh_output_credits[25] <= 3'd4) &&
        (mesh_output_credits[26] <= 3'd4) &&
        (mesh_output_credits[27] <= 3'd4) &&
        (mesh_output_credits[28] <= 3'd4) &&
        (mesh_output_credits[29] <= 3'd4) &&
        (mesh_output_credits[30] <= 3'd4) &&
        (mesh_output_credits[31] <= 3'd4) &&
        (mesh_output_credits[32] <= 3'd4) &&
        (mesh_output_credits[33] <= 3'd4) &&
        (mesh_output_credits[34] <= 3'd4) &&
        (mesh_output_credits[35] <= 3'd4) &&
        (mesh_output_credits[36] <= 3'd4) &&
        (mesh_output_credits[37] <= 3'd4) &&
        (mesh_output_credits[38] <= 3'd4) &&
        (mesh_output_credits[39] <= 3'd4) &&
        (mesh_output_credits[40] <= 3'd4) &&
        (mesh_output_credits[41] <= 3'd4) &&
        (mesh_output_credits[42] <= 3'd4) &&
        (mesh_output_credits[43] <= 3'd4) &&
        (mesh_output_credits[44] <= 3'd4) &&
        (mesh_output_credits[45] <= 3'd4) &&
        (mesh_output_credits[46] <= 3'd4) &&
        (mesh_output_credits[47] <= 3'd4) &&
        (mesh_output_credits[48] <= 3'd4) &&
        (mesh_output_credits[49] <= 3'd4) &&
        (mesh_output_credits[50] <= 3'd4) &&
        (mesh_output_credits[51] <= 3'd4) &&
        (mesh_output_credits[52] <= 3'd4) &&
        (mesh_output_credits[53] <= 3'd4) &&
        (mesh_output_credits[54] <= 3'd4) &&
        (mesh_output_credits[55] <= 3'd4) &&
        (mesh_output_credits[56] <= 3'd4) &&
        (mesh_output_credits[57] <= 3'd4) &&
        (mesh_output_credits[58] <= 3'd4) &&
        (mesh_output_credits[59] <= 3'd4) &&
        (mesh_output_credits[60] <= 3'd4) &&
        (mesh_output_credits[61] <= 3'd4) &&
        (mesh_output_credits[62] <= 3'd4) &&
        (mesh_output_credits[63] <= 3'd4) &&
        (mesh_output_credits[64] <= 3'd4) &&
        (mesh_output_credits[65] <= 3'd4) &&
        (mesh_output_credits[66] <= 3'd4) &&
        (mesh_output_credits[67] <= 3'd4) &&
        (mesh_output_credits[68] <= 3'd4) &&
        (mesh_output_credits[69] <= 3'd4) &&
        (mesh_output_credits[70] <= 3'd4) &&
        (mesh_output_credits[71] <= 3'd4) &&
        (mesh_output_credits[72] <= 3'd4) &&
        (mesh_output_credits[73] <= 3'd4) &&
        (mesh_output_credits[74] <= 3'd4) &&
        (mesh_output_credits[75] <= 3'd4) &&
        (mesh_output_credits[76] <= 3'd4) &&
        (mesh_output_credits[77] <= 3'd4) &&
        (mesh_output_credits[78] <= 3'd4) &&
        (mesh_output_credits[79] <= 3'd4) &&
        (mesh_output_credits[80] <= 3'd4) &&
        (mesh_output_credits[81] <= 3'd4) &&
        (mesh_output_credits[82] <= 3'd4) &&
        (mesh_output_credits[83] <= 3'd4) &&
        (mesh_output_credits[84] <= 3'd4) &&
        (mesh_output_credits[85] <= 3'd4) &&
        (mesh_output_credits[86] <= 3'd4) &&
        (mesh_output_credits[87] <= 3'd4) &&
        (mesh_output_credits[88] <= 3'd4) &&
        (mesh_output_credits[89] <= 3'd4) &&
        (mesh_output_credits[90] <= 3'd4) &&
        (mesh_output_credits[91] <= 3'd4) &&
        (mesh_output_credits[92] <= 3'd4) &&
        (mesh_output_credits[93] <= 3'd4) &&
        (mesh_output_credits[94] <= 3'd4) &&
        (mesh_output_credits[95] <= 3'd4) &&
        (mesh_output_credits[96] <= 3'd4) &&
        (mesh_output_credits[97] <= 3'd4) &&
        (mesh_output_credits[98] <= 3'd4) &&
        (mesh_output_credits[99] <= 3'd4) &&
        (mesh_output_credits[100] <= 3'd4) &&
        (mesh_output_credits[101] <= 3'd4) &&
        (mesh_output_credits[102] <= 3'd4) &&
        (mesh_output_credits[103] <= 3'd4) &&
        (mesh_output_credits[104] <= 3'd4) &&
        (mesh_output_credits[105] <= 3'd4) &&
        (mesh_output_credits[106] <= 3'd4) &&
        (mesh_output_credits[107] <= 3'd4) &&
        (mesh_output_credits[108] <= 3'd4) &&
        (mesh_output_credits[109] <= 3'd4) &&
        (mesh_output_credits[110] <= 3'd4) &&
        (mesh_output_credits[111] <= 3'd4) &&
        (mesh_output_credits[112] <= 3'd4) &&
        (mesh_output_credits[113] <= 3'd4) &&
        (mesh_output_credits[114] <= 3'd4) &&
        (mesh_output_credits[115] <= 3'd4) &&
        (mesh_output_credits[116] <= 3'd4) &&
        (mesh_output_credits[117] <= 3'd4) &&
        (mesh_output_credits[118] <= 3'd4) &&
        (mesh_output_credits[119] <= 3'd4) &&
        (mesh_output_credits[120] <= 3'd4) &&
        (mesh_output_credits[121] <= 3'd4) &&
        (mesh_output_credits[122] <= 3'd4) &&
        (mesh_output_credits[123] <= 3'd4) &&
        (mesh_output_credits[124] <= 3'd4) &&
        (mesh_output_credits[125] <= 3'd4) &&
        (mesh_output_credits[126] <= 3'd4) &&
        (mesh_output_credits[127] <= 3'd4) &&
        (mesh_output_credits[128] <= 3'd4) &&
        (mesh_output_credits[129] <= 3'd4) &&
        (mesh_output_credits[130] <= 3'd4) &&
        (mesh_output_credits[131] <= 3'd4) &&
        (mesh_output_credits[132] <= 3'd4) &&
        (mesh_output_credits[133] <= 3'd4) &&
        (mesh_output_credits[134] <= 3'd4))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_3
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_5
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_5
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 134 : 0 ] mesh_dequeue,
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_ALLOC_NO_DEQUEUE_WHEN_EMPTY: assert property (@(posedge clk) disable iff (!rst_ok)
    ((!mesh_dequeue[0] || (mesh_occupancy[0] != 5'd0)) &&
        (!mesh_dequeue[1] || (mesh_occupancy[1] != 5'd0)) &&
        (!mesh_dequeue[2] || (mesh_occupancy[2] != 5'd0)) &&
        (!mesh_dequeue[3] || (mesh_occupancy[3] != 5'd0)) &&
        (!mesh_dequeue[4] || (mesh_occupancy[4] != 5'd0)) &&
        (!mesh_dequeue[5] || (mesh_occupancy[5] != 5'd0)) &&
        (!mesh_dequeue[6] || (mesh_occupancy[6] != 5'd0)) &&
        (!mesh_dequeue[7] || (mesh_occupancy[7] != 5'd0)) &&
        (!mesh_dequeue[8] || (mesh_occupancy[8] != 5'd0)) &&
        (!mesh_dequeue[9] || (mesh_occupancy[9] != 5'd0)) &&
        (!mesh_dequeue[10] || (mesh_occupancy[10] != 5'd0)) &&
        (!mesh_dequeue[11] || (mesh_occupancy[11] != 5'd0)) &&
        (!mesh_dequeue[12] || (mesh_occupancy[12] != 5'd0)) &&
        (!mesh_dequeue[13] || (mesh_occupancy[13] != 5'd0)) &&
        (!mesh_dequeue[14] || (mesh_occupancy[14] != 5'd0)) &&
        (!mesh_dequeue[15] || (mesh_occupancy[15] != 5'd0)) &&
        (!mesh_dequeue[16] || (mesh_occupancy[16] != 5'd0)) &&
        (!mesh_dequeue[17] || (mesh_occupancy[17] != 5'd0)) &&
        (!mesh_dequeue[18] || (mesh_occupancy[18] != 5'd0)) &&
        (!mesh_dequeue[19] || (mesh_occupancy[19] != 5'd0)) &&
        (!mesh_dequeue[20] || (mesh_occupancy[20] != 5'd0)) &&
        (!mesh_dequeue[21] || (mesh_occupancy[21] != 5'd0)) &&
        (!mesh_dequeue[22] || (mesh_occupancy[22] != 5'd0)) &&
        (!mesh_dequeue[23] || (mesh_occupancy[23] != 5'd0)) &&
        (!mesh_dequeue[24] || (mesh_occupancy[24] != 5'd0)) &&
        (!mesh_dequeue[25] || (mesh_occupancy[25] != 5'd0)) &&
        (!mesh_dequeue[26] || (mesh_occupancy[26] != 5'd0)) &&
        (!mesh_dequeue[27] || (mesh_occupancy[27] != 5'd0)) &&
        (!mesh_dequeue[28] || (mesh_occupancy[28] != 5'd0)) &&
        (!mesh_dequeue[29] || (mesh_occupancy[29] != 5'd0)) &&
        (!mesh_dequeue[30] || (mesh_occupancy[30] != 5'd0)) &&
        (!mesh_dequeue[31] || (mesh_occupancy[31] != 5'd0)) &&
        (!mesh_dequeue[32] || (mesh_occupancy[32] != 5'd0)) &&
        (!mesh_dequeue[33] || (mesh_occupancy[33] != 5'd0)) &&
        (!mesh_dequeue[34] || (mesh_occupancy[34] != 5'd0)) &&
        (!mesh_dequeue[35] || (mesh_occupancy[35] != 5'd0)) &&
        (!mesh_dequeue[36] || (mesh_occupancy[36] != 5'd0)) &&
        (!mesh_dequeue[37] || (mesh_occupancy[37] != 5'd0)) &&
        (!mesh_dequeue[38] || (mesh_occupancy[38] != 5'd0)) &&
        (!mesh_dequeue[39] || (mesh_occupancy[39] != 5'd0)) &&
        (!mesh_dequeue[40] || (mesh_occupancy[40] != 5'd0)) &&
        (!mesh_dequeue[41] || (mesh_occupancy[41] != 5'd0)) &&
        (!mesh_dequeue[42] || (mesh_occupancy[42] != 5'd0)) &&
        (!mesh_dequeue[43] || (mesh_occupancy[43] != 5'd0)) &&
        (!mesh_dequeue[44] || (mesh_occupancy[44] != 5'd0)) &&
        (!mesh_dequeue[45] || (mesh_occupancy[45] != 5'd0)) &&
        (!mesh_dequeue[46] || (mesh_occupancy[46] != 5'd0)) &&
        (!mesh_dequeue[47] || (mesh_occupancy[47] != 5'd0)) &&
        (!mesh_dequeue[48] || (mesh_occupancy[48] != 5'd0)) &&
        (!mesh_dequeue[49] || (mesh_occupancy[49] != 5'd0)) &&
        (!mesh_dequeue[50] || (mesh_occupancy[50] != 5'd0)) &&
        (!mesh_dequeue[51] || (mesh_occupancy[51] != 5'd0)) &&
        (!mesh_dequeue[52] || (mesh_occupancy[52] != 5'd0)) &&
        (!mesh_dequeue[53] || (mesh_occupancy[53] != 5'd0)) &&
        (!mesh_dequeue[54] || (mesh_occupancy[54] != 5'd0)) &&
        (!mesh_dequeue[55] || (mesh_occupancy[55] != 5'd0)) &&
        (!mesh_dequeue[56] || (mesh_occupancy[56] != 5'd0)) &&
        (!mesh_dequeue[57] || (mesh_occupancy[57] != 5'd0)) &&
        (!mesh_dequeue[58] || (mesh_occupancy[58] != 5'd0)) &&
        (!mesh_dequeue[59] || (mesh_occupancy[59] != 5'd0)) &&
        (!mesh_dequeue[60] || (mesh_occupancy[60] != 5'd0)) &&
        (!mesh_dequeue[61] || (mesh_occupancy[61] != 5'd0)) &&
        (!mesh_dequeue[62] || (mesh_occupancy[62] != 5'd0)) &&
        (!mesh_dequeue[63] || (mesh_occupancy[63] != 5'd0)) &&
        (!mesh_dequeue[64] || (mesh_occupancy[64] != 5'd0)) &&
        (!mesh_dequeue[65] || (mesh_occupancy[65] != 5'd0)) &&
        (!mesh_dequeue[66] || (mesh_occupancy[66] != 5'd0)) &&
        (!mesh_dequeue[67] || (mesh_occupancy[67] != 5'd0)) &&
        (!mesh_dequeue[68] || (mesh_occupancy[68] != 5'd0)) &&
        (!mesh_dequeue[69] || (mesh_occupancy[69] != 5'd0)) &&
        (!mesh_dequeue[70] || (mesh_occupancy[70] != 5'd0)) &&
        (!mesh_dequeue[71] || (mesh_occupancy[71] != 5'd0)) &&
        (!mesh_dequeue[72] || (mesh_occupancy[72] != 5'd0)) &&
        (!mesh_dequeue[73] || (mesh_occupancy[73] != 5'd0)) &&
        (!mesh_dequeue[74] || (mesh_occupancy[74] != 5'd0)) &&
        (!mesh_dequeue[75] || (mesh_occupancy[75] != 5'd0)) &&
        (!mesh_dequeue[76] || (mesh_occupancy[76] != 5'd0)) &&
        (!mesh_dequeue[77] || (mesh_occupancy[77] != 5'd0)) &&
        (!mesh_dequeue[78] || (mesh_occupancy[78] != 5'd0)) &&
        (!mesh_dequeue[79] || (mesh_occupancy[79] != 5'd0)) &&
        (!mesh_dequeue[80] || (mesh_occupancy[80] != 5'd0)) &&
        (!mesh_dequeue[81] || (mesh_occupancy[81] != 5'd0)) &&
        (!mesh_dequeue[82] || (mesh_occupancy[82] != 5'd0)) &&
        (!mesh_dequeue[83] || (mesh_occupancy[83] != 5'd0)) &&
        (!mesh_dequeue[84] || (mesh_occupancy[84] != 5'd0)) &&
        (!mesh_dequeue[85] || (mesh_occupancy[85] != 5'd0)) &&
        (!mesh_dequeue[86] || (mesh_occupancy[86] != 5'd0)) &&
        (!mesh_dequeue[87] || (mesh_occupancy[87] != 5'd0)) &&
        (!mesh_dequeue[88] || (mesh_occupancy[88] != 5'd0)) &&
        (!mesh_dequeue[89] || (mesh_occupancy[89] != 5'd0)) &&
        (!mesh_dequeue[90] || (mesh_occupancy[90] != 5'd0)) &&
        (!mesh_dequeue[91] || (mesh_occupancy[91] != 5'd0)) &&
        (!mesh_dequeue[92] || (mesh_occupancy[92] != 5'd0)) &&
        (!mesh_dequeue[93] || (mesh_occupancy[93] != 5'd0)) &&
        (!mesh_dequeue[94] || (mesh_occupancy[94] != 5'd0)) &&
        (!mesh_dequeue[95] || (mesh_occupancy[95] != 5'd0)) &&
        (!mesh_dequeue[96] || (mesh_occupancy[96] != 5'd0)) &&
        (!mesh_dequeue[97] || (mesh_occupancy[97] != 5'd0)) &&
        (!mesh_dequeue[98] || (mesh_occupancy[98] != 5'd0)) &&
        (!mesh_dequeue[99] || (mesh_occupancy[99] != 5'd0)) &&
        (!mesh_dequeue[100] || (mesh_occupancy[100] != 5'd0)) &&
        (!mesh_dequeue[101] || (mesh_occupancy[101] != 5'd0)) &&
        (!mesh_dequeue[102] || (mesh_occupancy[102] != 5'd0)) &&
        (!mesh_dequeue[103] || (mesh_occupancy[103] != 5'd0)) &&
        (!mesh_dequeue[104] || (mesh_occupancy[104] != 5'd0)) &&
        (!mesh_dequeue[105] || (mesh_occupancy[105] != 5'd0)) &&
        (!mesh_dequeue[106] || (mesh_occupancy[106] != 5'd0)) &&
        (!mesh_dequeue[107] || (mesh_occupancy[107] != 5'd0)) &&
        (!mesh_dequeue[108] || (mesh_occupancy[108] != 5'd0)) &&
        (!mesh_dequeue[109] || (mesh_occupancy[109] != 5'd0)) &&
        (!mesh_dequeue[110] || (mesh_occupancy[110] != 5'd0)) &&
        (!mesh_dequeue[111] || (mesh_occupancy[111] != 5'd0)) &&
        (!mesh_dequeue[112] || (mesh_occupancy[112] != 5'd0)) &&
        (!mesh_dequeue[113] || (mesh_occupancy[113] != 5'd0)) &&
        (!mesh_dequeue[114] || (mesh_occupancy[114] != 5'd0)) &&
        (!mesh_dequeue[115] || (mesh_occupancy[115] != 5'd0)) &&
        (!mesh_dequeue[116] || (mesh_occupancy[116] != 5'd0)) &&
        (!mesh_dequeue[117] || (mesh_occupancy[117] != 5'd0)) &&
        (!mesh_dequeue[118] || (mesh_occupancy[118] != 5'd0)) &&
        (!mesh_dequeue[119] || (mesh_occupancy[119] != 5'd0)) &&
        (!mesh_dequeue[120] || (mesh_occupancy[120] != 5'd0)) &&
        (!mesh_dequeue[121] || (mesh_occupancy[121] != 5'd0)) &&
        (!mesh_dequeue[122] || (mesh_occupancy[122] != 5'd0)) &&
        (!mesh_dequeue[123] || (mesh_occupancy[123] != 5'd0)) &&
        (!mesh_dequeue[124] || (mesh_occupancy[124] != 5'd0)) &&
        (!mesh_dequeue[125] || (mesh_occupancy[125] != 5'd0)) &&
        (!mesh_dequeue[126] || (mesh_occupancy[126] != 5'd0)) &&
        (!mesh_dequeue[127] || (mesh_occupancy[127] != 5'd0)) &&
        (!mesh_dequeue[128] || (mesh_occupancy[128] != 5'd0)) &&
        (!mesh_dequeue[129] || (mesh_occupancy[129] != 5'd0)) &&
        (!mesh_dequeue[130] || (mesh_occupancy[130] != 5'd0)) &&
        (!mesh_dequeue[131] || (mesh_occupancy[131] != 5'd0)) &&
        (!mesh_dequeue[132] || (mesh_occupancy[132] != 5'd0)) &&
        (!mesh_dequeue[133] || (mesh_occupancy[133] != 5'd0)) &&
        (!mesh_dequeue[134] || (mesh_occupancy[134] != 5'd0)))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_5
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_6
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_6
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] e_p [ 0 : 8 ],
    input wire logic [ 8 : 0 ] crd
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_REQRSP_CREDIT_ONLY_ON_DEQUEUE: assert property (@(posedge clk) disable iff (!rst_ok)
        (((!crd[0] || (e_p[0] != 0)) &&
        (!crd[1] || (e_p[1] != 0)) &&
        (!crd[2] || (e_p[2] != 0)) &&
        (!crd[3] || (e_p[3] != 0)) &&
        (!crd[4] || (e_p[4] != 0)) &&
        (!crd[5] || (e_p[5] != 0)) &&
        (!crd[6] || (e_p[6] != 0)) &&
        (!crd[7] || (e_p[7] != 0)) &&
        (!crd[8] || (e_p[8] != 0)))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_6
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_7
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_7
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_input_grants [ 0 : 134 ],
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_PROTO_NO_GRANT_OF_EMPTY_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
    ((!(|mesh_input_grants[0]) || (mesh_occupancy[0] != 5'd0)) &&
        (!(|mesh_input_grants[1]) || (mesh_occupancy[1] != 5'd0)) &&
        (!(|mesh_input_grants[2]) || (mesh_occupancy[2] != 5'd0)) &&
        (!(|mesh_input_grants[3]) || (mesh_occupancy[3] != 5'd0)) &&
        (!(|mesh_input_grants[4]) || (mesh_occupancy[4] != 5'd0)) &&
        (!(|mesh_input_grants[5]) || (mesh_occupancy[5] != 5'd0)) &&
        (!(|mesh_input_grants[6]) || (mesh_occupancy[6] != 5'd0)) &&
        (!(|mesh_input_grants[7]) || (mesh_occupancy[7] != 5'd0)) &&
        (!(|mesh_input_grants[8]) || (mesh_occupancy[8] != 5'd0)) &&
        (!(|mesh_input_grants[9]) || (mesh_occupancy[9] != 5'd0)) &&
        (!(|mesh_input_grants[10]) || (mesh_occupancy[10] != 5'd0)) &&
        (!(|mesh_input_grants[11]) || (mesh_occupancy[11] != 5'd0)) &&
        (!(|mesh_input_grants[12]) || (mesh_occupancy[12] != 5'd0)) &&
        (!(|mesh_input_grants[13]) || (mesh_occupancy[13] != 5'd0)) &&
        (!(|mesh_input_grants[14]) || (mesh_occupancy[14] != 5'd0)) &&
        (!(|mesh_input_grants[15]) || (mesh_occupancy[15] != 5'd0)) &&
        (!(|mesh_input_grants[16]) || (mesh_occupancy[16] != 5'd0)) &&
        (!(|mesh_input_grants[17]) || (mesh_occupancy[17] != 5'd0)) &&
        (!(|mesh_input_grants[18]) || (mesh_occupancy[18] != 5'd0)) &&
        (!(|mesh_input_grants[19]) || (mesh_occupancy[19] != 5'd0)) &&
        (!(|mesh_input_grants[20]) || (mesh_occupancy[20] != 5'd0)) &&
        (!(|mesh_input_grants[21]) || (mesh_occupancy[21] != 5'd0)) &&
        (!(|mesh_input_grants[22]) || (mesh_occupancy[22] != 5'd0)) &&
        (!(|mesh_input_grants[23]) || (mesh_occupancy[23] != 5'd0)) &&
        (!(|mesh_input_grants[24]) || (mesh_occupancy[24] != 5'd0)) &&
        (!(|mesh_input_grants[25]) || (mesh_occupancy[25] != 5'd0)) &&
        (!(|mesh_input_grants[26]) || (mesh_occupancy[26] != 5'd0)) &&
        (!(|mesh_input_grants[27]) || (mesh_occupancy[27] != 5'd0)) &&
        (!(|mesh_input_grants[28]) || (mesh_occupancy[28] != 5'd0)) &&
        (!(|mesh_input_grants[29]) || (mesh_occupancy[29] != 5'd0)) &&
        (!(|mesh_input_grants[30]) || (mesh_occupancy[30] != 5'd0)) &&
        (!(|mesh_input_grants[31]) || (mesh_occupancy[31] != 5'd0)) &&
        (!(|mesh_input_grants[32]) || (mesh_occupancy[32] != 5'd0)) &&
        (!(|mesh_input_grants[33]) || (mesh_occupancy[33] != 5'd0)) &&
        (!(|mesh_input_grants[34]) || (mesh_occupancy[34] != 5'd0)) &&
        (!(|mesh_input_grants[35]) || (mesh_occupancy[35] != 5'd0)) &&
        (!(|mesh_input_grants[36]) || (mesh_occupancy[36] != 5'd0)) &&
        (!(|mesh_input_grants[37]) || (mesh_occupancy[37] != 5'd0)) &&
        (!(|mesh_input_grants[38]) || (mesh_occupancy[38] != 5'd0)) &&
        (!(|mesh_input_grants[39]) || (mesh_occupancy[39] != 5'd0)) &&
        (!(|mesh_input_grants[40]) || (mesh_occupancy[40] != 5'd0)) &&
        (!(|mesh_input_grants[41]) || (mesh_occupancy[41] != 5'd0)) &&
        (!(|mesh_input_grants[42]) || (mesh_occupancy[42] != 5'd0)) &&
        (!(|mesh_input_grants[43]) || (mesh_occupancy[43] != 5'd0)) &&
        (!(|mesh_input_grants[44]) || (mesh_occupancy[44] != 5'd0)) &&
        (!(|mesh_input_grants[45]) || (mesh_occupancy[45] != 5'd0)) &&
        (!(|mesh_input_grants[46]) || (mesh_occupancy[46] != 5'd0)) &&
        (!(|mesh_input_grants[47]) || (mesh_occupancy[47] != 5'd0)) &&
        (!(|mesh_input_grants[48]) || (mesh_occupancy[48] != 5'd0)) &&
        (!(|mesh_input_grants[49]) || (mesh_occupancy[49] != 5'd0)) &&
        (!(|mesh_input_grants[50]) || (mesh_occupancy[50] != 5'd0)) &&
        (!(|mesh_input_grants[51]) || (mesh_occupancy[51] != 5'd0)) &&
        (!(|mesh_input_grants[52]) || (mesh_occupancy[52] != 5'd0)) &&
        (!(|mesh_input_grants[53]) || (mesh_occupancy[53] != 5'd0)) &&
        (!(|mesh_input_grants[54]) || (mesh_occupancy[54] != 5'd0)) &&
        (!(|mesh_input_grants[55]) || (mesh_occupancy[55] != 5'd0)) &&
        (!(|mesh_input_grants[56]) || (mesh_occupancy[56] != 5'd0)) &&
        (!(|mesh_input_grants[57]) || (mesh_occupancy[57] != 5'd0)) &&
        (!(|mesh_input_grants[58]) || (mesh_occupancy[58] != 5'd0)) &&
        (!(|mesh_input_grants[59]) || (mesh_occupancy[59] != 5'd0)) &&
        (!(|mesh_input_grants[60]) || (mesh_occupancy[60] != 5'd0)) &&
        (!(|mesh_input_grants[61]) || (mesh_occupancy[61] != 5'd0)) &&
        (!(|mesh_input_grants[62]) || (mesh_occupancy[62] != 5'd0)) &&
        (!(|mesh_input_grants[63]) || (mesh_occupancy[63] != 5'd0)) &&
        (!(|mesh_input_grants[64]) || (mesh_occupancy[64] != 5'd0)) &&
        (!(|mesh_input_grants[65]) || (mesh_occupancy[65] != 5'd0)) &&
        (!(|mesh_input_grants[66]) || (mesh_occupancy[66] != 5'd0)) &&
        (!(|mesh_input_grants[67]) || (mesh_occupancy[67] != 5'd0)) &&
        (!(|mesh_input_grants[68]) || (mesh_occupancy[68] != 5'd0)) &&
        (!(|mesh_input_grants[69]) || (mesh_occupancy[69] != 5'd0)) &&
        (!(|mesh_input_grants[70]) || (mesh_occupancy[70] != 5'd0)) &&
        (!(|mesh_input_grants[71]) || (mesh_occupancy[71] != 5'd0)) &&
        (!(|mesh_input_grants[72]) || (mesh_occupancy[72] != 5'd0)) &&
        (!(|mesh_input_grants[73]) || (mesh_occupancy[73] != 5'd0)) &&
        (!(|mesh_input_grants[74]) || (mesh_occupancy[74] != 5'd0)) &&
        (!(|mesh_input_grants[75]) || (mesh_occupancy[75] != 5'd0)) &&
        (!(|mesh_input_grants[76]) || (mesh_occupancy[76] != 5'd0)) &&
        (!(|mesh_input_grants[77]) || (mesh_occupancy[77] != 5'd0)) &&
        (!(|mesh_input_grants[78]) || (mesh_occupancy[78] != 5'd0)) &&
        (!(|mesh_input_grants[79]) || (mesh_occupancy[79] != 5'd0)) &&
        (!(|mesh_input_grants[80]) || (mesh_occupancy[80] != 5'd0)) &&
        (!(|mesh_input_grants[81]) || (mesh_occupancy[81] != 5'd0)) &&
        (!(|mesh_input_grants[82]) || (mesh_occupancy[82] != 5'd0)) &&
        (!(|mesh_input_grants[83]) || (mesh_occupancy[83] != 5'd0)) &&
        (!(|mesh_input_grants[84]) || (mesh_occupancy[84] != 5'd0)) &&
        (!(|mesh_input_grants[85]) || (mesh_occupancy[85] != 5'd0)) &&
        (!(|mesh_input_grants[86]) || (mesh_occupancy[86] != 5'd0)) &&
        (!(|mesh_input_grants[87]) || (mesh_occupancy[87] != 5'd0)) &&
        (!(|mesh_input_grants[88]) || (mesh_occupancy[88] != 5'd0)) &&
        (!(|mesh_input_grants[89]) || (mesh_occupancy[89] != 5'd0)) &&
        (!(|mesh_input_grants[90]) || (mesh_occupancy[90] != 5'd0)) &&
        (!(|mesh_input_grants[91]) || (mesh_occupancy[91] != 5'd0)) &&
        (!(|mesh_input_grants[92]) || (mesh_occupancy[92] != 5'd0)) &&
        (!(|mesh_input_grants[93]) || (mesh_occupancy[93] != 5'd0)) &&
        (!(|mesh_input_grants[94]) || (mesh_occupancy[94] != 5'd0)) &&
        (!(|mesh_input_grants[95]) || (mesh_occupancy[95] != 5'd0)) &&
        (!(|mesh_input_grants[96]) || (mesh_occupancy[96] != 5'd0)) &&
        (!(|mesh_input_grants[97]) || (mesh_occupancy[97] != 5'd0)) &&
        (!(|mesh_input_grants[98]) || (mesh_occupancy[98] != 5'd0)) &&
        (!(|mesh_input_grants[99]) || (mesh_occupancy[99] != 5'd0)) &&
        (!(|mesh_input_grants[100]) || (mesh_occupancy[100] != 5'd0)) &&
        (!(|mesh_input_grants[101]) || (mesh_occupancy[101] != 5'd0)) &&
        (!(|mesh_input_grants[102]) || (mesh_occupancy[102] != 5'd0)) &&
        (!(|mesh_input_grants[103]) || (mesh_occupancy[103] != 5'd0)) &&
        (!(|mesh_input_grants[104]) || (mesh_occupancy[104] != 5'd0)) &&
        (!(|mesh_input_grants[105]) || (mesh_occupancy[105] != 5'd0)) &&
        (!(|mesh_input_grants[106]) || (mesh_occupancy[106] != 5'd0)) &&
        (!(|mesh_input_grants[107]) || (mesh_occupancy[107] != 5'd0)) &&
        (!(|mesh_input_grants[108]) || (mesh_occupancy[108] != 5'd0)) &&
        (!(|mesh_input_grants[109]) || (mesh_occupancy[109] != 5'd0)) &&
        (!(|mesh_input_grants[110]) || (mesh_occupancy[110] != 5'd0)) &&
        (!(|mesh_input_grants[111]) || (mesh_occupancy[111] != 5'd0)) &&
        (!(|mesh_input_grants[112]) || (mesh_occupancy[112] != 5'd0)) &&
        (!(|mesh_input_grants[113]) || (mesh_occupancy[113] != 5'd0)) &&
        (!(|mesh_input_grants[114]) || (mesh_occupancy[114] != 5'd0)) &&
        (!(|mesh_input_grants[115]) || (mesh_occupancy[115] != 5'd0)) &&
        (!(|mesh_input_grants[116]) || (mesh_occupancy[116] != 5'd0)) &&
        (!(|mesh_input_grants[117]) || (mesh_occupancy[117] != 5'd0)) &&
        (!(|mesh_input_grants[118]) || (mesh_occupancy[118] != 5'd0)) &&
        (!(|mesh_input_grants[119]) || (mesh_occupancy[119] != 5'd0)) &&
        (!(|mesh_input_grants[120]) || (mesh_occupancy[120] != 5'd0)) &&
        (!(|mesh_input_grants[121]) || (mesh_occupancy[121] != 5'd0)) &&
        (!(|mesh_input_grants[122]) || (mesh_occupancy[122] != 5'd0)) &&
        (!(|mesh_input_grants[123]) || (mesh_occupancy[123] != 5'd0)) &&
        (!(|mesh_input_grants[124]) || (mesh_occupancy[124] != 5'd0)) &&
        (!(|mesh_input_grants[125]) || (mesh_occupancy[125] != 5'd0)) &&
        (!(|mesh_input_grants[126]) || (mesh_occupancy[126] != 5'd0)) &&
        (!(|mesh_input_grants[127]) || (mesh_occupancy[127] != 5'd0)) &&
        (!(|mesh_input_grants[128]) || (mesh_occupancy[128] != 5'd0)) &&
        (!(|mesh_input_grants[129]) || (mesh_occupancy[129] != 5'd0)) &&
        (!(|mesh_input_grants[130]) || (mesh_occupancy[130] != 5'd0)) &&
        (!(|mesh_input_grants[131]) || (mesh_occupancy[131] != 5'd0)) &&
        (!(|mesh_input_grants[132]) || (mesh_occupancy[132] != 5'd0)) &&
        (!(|mesh_input_grants[133]) || (mesh_occupancy[133] != 5'd0)) &&
        (!(|mesh_input_grants[134]) || (mesh_occupancy[134] != 5'd0)))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_7
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_8
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_8
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 2 : 0 ] e_w [ 0 : 8 ],
    input wire logic [ 2 : 0 ] e_n [ 0 : 8 ],
    input wire logic [ 7 : 0 ] mesh_link_valid
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_PROTO_NO_SEND_WITHOUT_SPACE: assert property (@(posedge clk) disable iff (!rst_ok)
    ((!mesh_link_valid[0] || (e_w[1] <= 3'd3)) &&
        (!mesh_link_valid[1] || (e_w[2] <= 3'd3)) &&
        (!mesh_link_valid[2] || (e_w[4] <= 3'd3)) &&
        (!mesh_link_valid[3] || (e_w[5] <= 3'd3)) &&
        (!mesh_link_valid[4] || (e_w[7] <= 3'd3)) &&
        (!mesh_link_valid[5] || (e_w[8] <= 3'd3)) &&
        (!mesh_link_valid[6] || (e_n[5] <= 3'd3)) &&
        (!mesh_link_valid[7] || (e_n[8] <= 3'd3)))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_8
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_12
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_12
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ],
    input wire logic [ 134 : 0 ] mesh_planned,
    input wire logic [ 2 : 0 ] mesh_route [ 0 : 134 ],
    input wire logic [ 2 : 0 ] mesh_output_credits [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_RESET_MESH_EMPTY_AND_IDLE: assert property (@(posedge clk) disable iff (!rst_ok)
    (rst_ok && !$past(rst_ok)) |-> (((mesh_occupancy[0] == 5'd0) && !mesh_planned[0] && (mesh_route[0] == 3'd0) && (mesh_output_credits[0] == 3'd4)) &&
        ((mesh_occupancy[1] == 5'd0) && !mesh_planned[1] && (mesh_route[1] == 3'd0) && (mesh_output_credits[1] == 3'd4)) &&
        ((mesh_occupancy[2] == 5'd0) && !mesh_planned[2] && (mesh_route[2] == 3'd0) && (mesh_output_credits[2] == 3'd4)) &&
        ((mesh_occupancy[3] == 5'd0) && !mesh_planned[3] && (mesh_route[3] == 3'd0) && (mesh_output_credits[3] == 3'd4)) &&
        ((mesh_occupancy[4] == 5'd0) && !mesh_planned[4] && (mesh_route[4] == 3'd0) && (mesh_output_credits[4] == 3'd4)) &&
        ((mesh_occupancy[5] == 5'd0) && !mesh_planned[5] && (mesh_route[5] == 3'd0) && (mesh_output_credits[5] == 3'd4)) &&
        ((mesh_occupancy[6] == 5'd0) && !mesh_planned[6] && (mesh_route[6] == 3'd0) && (mesh_output_credits[6] == 3'd4)) &&
        ((mesh_occupancy[7] == 5'd0) && !mesh_planned[7] && (mesh_route[7] == 3'd0) && (mesh_output_credits[7] == 3'd4)) &&
        ((mesh_occupancy[8] == 5'd0) && !mesh_planned[8] && (mesh_route[8] == 3'd0) && (mesh_output_credits[8] == 3'd4)) &&
        ((mesh_occupancy[9] == 5'd0) && !mesh_planned[9] && (mesh_route[9] == 3'd0) && (mesh_output_credits[9] == 3'd4)) &&
        ((mesh_occupancy[10] == 5'd0) && !mesh_planned[10] && (mesh_route[10] == 3'd0) && (mesh_output_credits[10] == 3'd4)) &&
        ((mesh_occupancy[11] == 5'd0) && !mesh_planned[11] && (mesh_route[11] == 3'd0) && (mesh_output_credits[11] == 3'd4)) &&
        ((mesh_occupancy[12] == 5'd0) && !mesh_planned[12] && (mesh_route[12] == 3'd0) && (mesh_output_credits[12] == 3'd4)) &&
        ((mesh_occupancy[13] == 5'd0) && !mesh_planned[13] && (mesh_route[13] == 3'd0) && (mesh_output_credits[13] == 3'd4)) &&
        ((mesh_occupancy[14] == 5'd0) && !mesh_planned[14] && (mesh_route[14] == 3'd0) && (mesh_output_credits[14] == 3'd4)) &&
        ((mesh_occupancy[15] == 5'd0) && !mesh_planned[15] && (mesh_route[15] == 3'd0) && (mesh_output_credits[15] == 3'd4)) &&
        ((mesh_occupancy[16] == 5'd0) && !mesh_planned[16] && (mesh_route[16] == 3'd0) && (mesh_output_credits[16] == 3'd4)) &&
        ((mesh_occupancy[17] == 5'd0) && !mesh_planned[17] && (mesh_route[17] == 3'd0) && (mesh_output_credits[17] == 3'd4)) &&
        ((mesh_occupancy[18] == 5'd0) && !mesh_planned[18] && (mesh_route[18] == 3'd0) && (mesh_output_credits[18] == 3'd4)) &&
        ((mesh_occupancy[19] == 5'd0) && !mesh_planned[19] && (mesh_route[19] == 3'd0) && (mesh_output_credits[19] == 3'd4)) &&
        ((mesh_occupancy[20] == 5'd0) && !mesh_planned[20] && (mesh_route[20] == 3'd0) && (mesh_output_credits[20] == 3'd4)) &&
        ((mesh_occupancy[21] == 5'd0) && !mesh_planned[21] && (mesh_route[21] == 3'd0) && (mesh_output_credits[21] == 3'd4)) &&
        ((mesh_occupancy[22] == 5'd0) && !mesh_planned[22] && (mesh_route[22] == 3'd0) && (mesh_output_credits[22] == 3'd4)) &&
        ((mesh_occupancy[23] == 5'd0) && !mesh_planned[23] && (mesh_route[23] == 3'd0) && (mesh_output_credits[23] == 3'd4)) &&
        ((mesh_occupancy[24] == 5'd0) && !mesh_planned[24] && (mesh_route[24] == 3'd0) && (mesh_output_credits[24] == 3'd4)) &&
        ((mesh_occupancy[25] == 5'd0) && !mesh_planned[25] && (mesh_route[25] == 3'd0) && (mesh_output_credits[25] == 3'd4)) &&
        ((mesh_occupancy[26] == 5'd0) && !mesh_planned[26] && (mesh_route[26] == 3'd0) && (mesh_output_credits[26] == 3'd4)) &&
        ((mesh_occupancy[27] == 5'd0) && !mesh_planned[27] && (mesh_route[27] == 3'd0) && (mesh_output_credits[27] == 3'd4)) &&
        ((mesh_occupancy[28] == 5'd0) && !mesh_planned[28] && (mesh_route[28] == 3'd0) && (mesh_output_credits[28] == 3'd4)) &&
        ((mesh_occupancy[29] == 5'd0) && !mesh_planned[29] && (mesh_route[29] == 3'd0) && (mesh_output_credits[29] == 3'd4)) &&
        ((mesh_occupancy[30] == 5'd0) && !mesh_planned[30] && (mesh_route[30] == 3'd0) && (mesh_output_credits[30] == 3'd4)) &&
        ((mesh_occupancy[31] == 5'd0) && !mesh_planned[31] && (mesh_route[31] == 3'd0) && (mesh_output_credits[31] == 3'd4)) &&
        ((mesh_occupancy[32] == 5'd0) && !mesh_planned[32] && (mesh_route[32] == 3'd0) && (mesh_output_credits[32] == 3'd4)) &&
        ((mesh_occupancy[33] == 5'd0) && !mesh_planned[33] && (mesh_route[33] == 3'd0) && (mesh_output_credits[33] == 3'd4)) &&
        ((mesh_occupancy[34] == 5'd0) && !mesh_planned[34] && (mesh_route[34] == 3'd0) && (mesh_output_credits[34] == 3'd4)) &&
        ((mesh_occupancy[35] == 5'd0) && !mesh_planned[35] && (mesh_route[35] == 3'd0) && (mesh_output_credits[35] == 3'd4)) &&
        ((mesh_occupancy[36] == 5'd0) && !mesh_planned[36] && (mesh_route[36] == 3'd0) && (mesh_output_credits[36] == 3'd4)) &&
        ((mesh_occupancy[37] == 5'd0) && !mesh_planned[37] && (mesh_route[37] == 3'd0) && (mesh_output_credits[37] == 3'd4)) &&
        ((mesh_occupancy[38] == 5'd0) && !mesh_planned[38] && (mesh_route[38] == 3'd0) && (mesh_output_credits[38] == 3'd4)) &&
        ((mesh_occupancy[39] == 5'd0) && !mesh_planned[39] && (mesh_route[39] == 3'd0) && (mesh_output_credits[39] == 3'd4)) &&
        ((mesh_occupancy[40] == 5'd0) && !mesh_planned[40] && (mesh_route[40] == 3'd0) && (mesh_output_credits[40] == 3'd4)) &&
        ((mesh_occupancy[41] == 5'd0) && !mesh_planned[41] && (mesh_route[41] == 3'd0) && (mesh_output_credits[41] == 3'd4)) &&
        ((mesh_occupancy[42] == 5'd0) && !mesh_planned[42] && (mesh_route[42] == 3'd0) && (mesh_output_credits[42] == 3'd4)) &&
        ((mesh_occupancy[43] == 5'd0) && !mesh_planned[43] && (mesh_route[43] == 3'd0) && (mesh_output_credits[43] == 3'd4)) &&
        ((mesh_occupancy[44] == 5'd0) && !mesh_planned[44] && (mesh_route[44] == 3'd0) && (mesh_output_credits[44] == 3'd4)) &&
        ((mesh_occupancy[45] == 5'd0) && !mesh_planned[45] && (mesh_route[45] == 3'd0) && (mesh_output_credits[45] == 3'd4)) &&
        ((mesh_occupancy[46] == 5'd0) && !mesh_planned[46] && (mesh_route[46] == 3'd0) && (mesh_output_credits[46] == 3'd4)) &&
        ((mesh_occupancy[47] == 5'd0) && !mesh_planned[47] && (mesh_route[47] == 3'd0) && (mesh_output_credits[47] == 3'd4)) &&
        ((mesh_occupancy[48] == 5'd0) && !mesh_planned[48] && (mesh_route[48] == 3'd0) && (mesh_output_credits[48] == 3'd4)) &&
        ((mesh_occupancy[49] == 5'd0) && !mesh_planned[49] && (mesh_route[49] == 3'd0) && (mesh_output_credits[49] == 3'd4)) &&
        ((mesh_occupancy[50] == 5'd0) && !mesh_planned[50] && (mesh_route[50] == 3'd0) && (mesh_output_credits[50] == 3'd4)) &&
        ((mesh_occupancy[51] == 5'd0) && !mesh_planned[51] && (mesh_route[51] == 3'd0) && (mesh_output_credits[51] == 3'd4)) &&
        ((mesh_occupancy[52] == 5'd0) && !mesh_planned[52] && (mesh_route[52] == 3'd0) && (mesh_output_credits[52] == 3'd4)) &&
        ((mesh_occupancy[53] == 5'd0) && !mesh_planned[53] && (mesh_route[53] == 3'd0) && (mesh_output_credits[53] == 3'd4)) &&
        ((mesh_occupancy[54] == 5'd0) && !mesh_planned[54] && (mesh_route[54] == 3'd0) && (mesh_output_credits[54] == 3'd4)) &&
        ((mesh_occupancy[55] == 5'd0) && !mesh_planned[55] && (mesh_route[55] == 3'd0) && (mesh_output_credits[55] == 3'd4)) &&
        ((mesh_occupancy[56] == 5'd0) && !mesh_planned[56] && (mesh_route[56] == 3'd0) && (mesh_output_credits[56] == 3'd4)) &&
        ((mesh_occupancy[57] == 5'd0) && !mesh_planned[57] && (mesh_route[57] == 3'd0) && (mesh_output_credits[57] == 3'd4)) &&
        ((mesh_occupancy[58] == 5'd0) && !mesh_planned[58] && (mesh_route[58] == 3'd0) && (mesh_output_credits[58] == 3'd4)) &&
        ((mesh_occupancy[59] == 5'd0) && !mesh_planned[59] && (mesh_route[59] == 3'd0) && (mesh_output_credits[59] == 3'd4)) &&
        ((mesh_occupancy[60] == 5'd0) && !mesh_planned[60] && (mesh_route[60] == 3'd0) && (mesh_output_credits[60] == 3'd4)) &&
        ((mesh_occupancy[61] == 5'd0) && !mesh_planned[61] && (mesh_route[61] == 3'd0) && (mesh_output_credits[61] == 3'd4)) &&
        ((mesh_occupancy[62] == 5'd0) && !mesh_planned[62] && (mesh_route[62] == 3'd0) && (mesh_output_credits[62] == 3'd4)) &&
        ((mesh_occupancy[63] == 5'd0) && !mesh_planned[63] && (mesh_route[63] == 3'd0) && (mesh_output_credits[63] == 3'd4)) &&
        ((mesh_occupancy[64] == 5'd0) && !mesh_planned[64] && (mesh_route[64] == 3'd0) && (mesh_output_credits[64] == 3'd4)) &&
        ((mesh_occupancy[65] == 5'd0) && !mesh_planned[65] && (mesh_route[65] == 3'd0) && (mesh_output_credits[65] == 3'd4)) &&
        ((mesh_occupancy[66] == 5'd0) && !mesh_planned[66] && (mesh_route[66] == 3'd0) && (mesh_output_credits[66] == 3'd4)) &&
        ((mesh_occupancy[67] == 5'd0) && !mesh_planned[67] && (mesh_route[67] == 3'd0) && (mesh_output_credits[67] == 3'd4)) &&
        ((mesh_occupancy[68] == 5'd0) && !mesh_planned[68] && (mesh_route[68] == 3'd0) && (mesh_output_credits[68] == 3'd4)) &&
        ((mesh_occupancy[69] == 5'd0) && !mesh_planned[69] && (mesh_route[69] == 3'd0) && (mesh_output_credits[69] == 3'd4)) &&
        ((mesh_occupancy[70] == 5'd0) && !mesh_planned[70] && (mesh_route[70] == 3'd0) && (mesh_output_credits[70] == 3'd4)) &&
        ((mesh_occupancy[71] == 5'd0) && !mesh_planned[71] && (mesh_route[71] == 3'd0) && (mesh_output_credits[71] == 3'd4)) &&
        ((mesh_occupancy[72] == 5'd0) && !mesh_planned[72] && (mesh_route[72] == 3'd0) && (mesh_output_credits[72] == 3'd4)) &&
        ((mesh_occupancy[73] == 5'd0) && !mesh_planned[73] && (mesh_route[73] == 3'd0) && (mesh_output_credits[73] == 3'd4)) &&
        ((mesh_occupancy[74] == 5'd0) && !mesh_planned[74] && (mesh_route[74] == 3'd0) && (mesh_output_credits[74] == 3'd4)) &&
        ((mesh_occupancy[75] == 5'd0) && !mesh_planned[75] && (mesh_route[75] == 3'd0) && (mesh_output_credits[75] == 3'd4)) &&
        ((mesh_occupancy[76] == 5'd0) && !mesh_planned[76] && (mesh_route[76] == 3'd0) && (mesh_output_credits[76] == 3'd4)) &&
        ((mesh_occupancy[77] == 5'd0) && !mesh_planned[77] && (mesh_route[77] == 3'd0) && (mesh_output_credits[77] == 3'd4)) &&
        ((mesh_occupancy[78] == 5'd0) && !mesh_planned[78] && (mesh_route[78] == 3'd0) && (mesh_output_credits[78] == 3'd4)) &&
        ((mesh_occupancy[79] == 5'd0) && !mesh_planned[79] && (mesh_route[79] == 3'd0) && (mesh_output_credits[79] == 3'd4)) &&
        ((mesh_occupancy[80] == 5'd0) && !mesh_planned[80] && (mesh_route[80] == 3'd0) && (mesh_output_credits[80] == 3'd4)) &&
        ((mesh_occupancy[81] == 5'd0) && !mesh_planned[81] && (mesh_route[81] == 3'd0) && (mesh_output_credits[81] == 3'd4)) &&
        ((mesh_occupancy[82] == 5'd0) && !mesh_planned[82] && (mesh_route[82] == 3'd0) && (mesh_output_credits[82] == 3'd4)) &&
        ((mesh_occupancy[83] == 5'd0) && !mesh_planned[83] && (mesh_route[83] == 3'd0) && (mesh_output_credits[83] == 3'd4)) &&
        ((mesh_occupancy[84] == 5'd0) && !mesh_planned[84] && (mesh_route[84] == 3'd0) && (mesh_output_credits[84] == 3'd4)) &&
        ((mesh_occupancy[85] == 5'd0) && !mesh_planned[85] && (mesh_route[85] == 3'd0) && (mesh_output_credits[85] == 3'd4)) &&
        ((mesh_occupancy[86] == 5'd0) && !mesh_planned[86] && (mesh_route[86] == 3'd0) && (mesh_output_credits[86] == 3'd4)) &&
        ((mesh_occupancy[87] == 5'd0) && !mesh_planned[87] && (mesh_route[87] == 3'd0) && (mesh_output_credits[87] == 3'd4)) &&
        ((mesh_occupancy[88] == 5'd0) && !mesh_planned[88] && (mesh_route[88] == 3'd0) && (mesh_output_credits[88] == 3'd4)) &&
        ((mesh_occupancy[89] == 5'd0) && !mesh_planned[89] && (mesh_route[89] == 3'd0) && (mesh_output_credits[89] == 3'd4)) &&
        ((mesh_occupancy[90] == 5'd0) && !mesh_planned[90] && (mesh_route[90] == 3'd0) && (mesh_output_credits[90] == 3'd4)) &&
        ((mesh_occupancy[91] == 5'd0) && !mesh_planned[91] && (mesh_route[91] == 3'd0) && (mesh_output_credits[91] == 3'd4)) &&
        ((mesh_occupancy[92] == 5'd0) && !mesh_planned[92] && (mesh_route[92] == 3'd0) && (mesh_output_credits[92] == 3'd4)) &&
        ((mesh_occupancy[93] == 5'd0) && !mesh_planned[93] && (mesh_route[93] == 3'd0) && (mesh_output_credits[93] == 3'd4)) &&
        ((mesh_occupancy[94] == 5'd0) && !mesh_planned[94] && (mesh_route[94] == 3'd0) && (mesh_output_credits[94] == 3'd4)) &&
        ((mesh_occupancy[95] == 5'd0) && !mesh_planned[95] && (mesh_route[95] == 3'd0) && (mesh_output_credits[95] == 3'd4)) &&
        ((mesh_occupancy[96] == 5'd0) && !mesh_planned[96] && (mesh_route[96] == 3'd0) && (mesh_output_credits[96] == 3'd4)) &&
        ((mesh_occupancy[97] == 5'd0) && !mesh_planned[97] && (mesh_route[97] == 3'd0) && (mesh_output_credits[97] == 3'd4)) &&
        ((mesh_occupancy[98] == 5'd0) && !mesh_planned[98] && (mesh_route[98] == 3'd0) && (mesh_output_credits[98] == 3'd4)) &&
        ((mesh_occupancy[99] == 5'd0) && !mesh_planned[99] && (mesh_route[99] == 3'd0) && (mesh_output_credits[99] == 3'd4)) &&
        ((mesh_occupancy[100] == 5'd0) && !mesh_planned[100] && (mesh_route[100] == 3'd0) && (mesh_output_credits[100] == 3'd4)) &&
        ((mesh_occupancy[101] == 5'd0) && !mesh_planned[101] && (mesh_route[101] == 3'd0) && (mesh_output_credits[101] == 3'd4)) &&
        ((mesh_occupancy[102] == 5'd0) && !mesh_planned[102] && (mesh_route[102] == 3'd0) && (mesh_output_credits[102] == 3'd4)) &&
        ((mesh_occupancy[103] == 5'd0) && !mesh_planned[103] && (mesh_route[103] == 3'd0) && (mesh_output_credits[103] == 3'd4)) &&
        ((mesh_occupancy[104] == 5'd0) && !mesh_planned[104] && (mesh_route[104] == 3'd0) && (mesh_output_credits[104] == 3'd4)) &&
        ((mesh_occupancy[105] == 5'd0) && !mesh_planned[105] && (mesh_route[105] == 3'd0) && (mesh_output_credits[105] == 3'd4)) &&
        ((mesh_occupancy[106] == 5'd0) && !mesh_planned[106] && (mesh_route[106] == 3'd0) && (mesh_output_credits[106] == 3'd4)) &&
        ((mesh_occupancy[107] == 5'd0) && !mesh_planned[107] && (mesh_route[107] == 3'd0) && (mesh_output_credits[107] == 3'd4)) &&
        ((mesh_occupancy[108] == 5'd0) && !mesh_planned[108] && (mesh_route[108] == 3'd0) && (mesh_output_credits[108] == 3'd4)) &&
        ((mesh_occupancy[109] == 5'd0) && !mesh_planned[109] && (mesh_route[109] == 3'd0) && (mesh_output_credits[109] == 3'd4)) &&
        ((mesh_occupancy[110] == 5'd0) && !mesh_planned[110] && (mesh_route[110] == 3'd0) && (mesh_output_credits[110] == 3'd4)) &&
        ((mesh_occupancy[111] == 5'd0) && !mesh_planned[111] && (mesh_route[111] == 3'd0) && (mesh_output_credits[111] == 3'd4)) &&
        ((mesh_occupancy[112] == 5'd0) && !mesh_planned[112] && (mesh_route[112] == 3'd0) && (mesh_output_credits[112] == 3'd4)) &&
        ((mesh_occupancy[113] == 5'd0) && !mesh_planned[113] && (mesh_route[113] == 3'd0) && (mesh_output_credits[113] == 3'd4)) &&
        ((mesh_occupancy[114] == 5'd0) && !mesh_planned[114] && (mesh_route[114] == 3'd0) && (mesh_output_credits[114] == 3'd4)) &&
        ((mesh_occupancy[115] == 5'd0) && !mesh_planned[115] && (mesh_route[115] == 3'd0) && (mesh_output_credits[115] == 3'd4)) &&
        ((mesh_occupancy[116] == 5'd0) && !mesh_planned[116] && (mesh_route[116] == 3'd0) && (mesh_output_credits[116] == 3'd4)) &&
        ((mesh_occupancy[117] == 5'd0) && !mesh_planned[117] && (mesh_route[117] == 3'd0) && (mesh_output_credits[117] == 3'd4)) &&
        ((mesh_occupancy[118] == 5'd0) && !mesh_planned[118] && (mesh_route[118] == 3'd0) && (mesh_output_credits[118] == 3'd4)) &&
        ((mesh_occupancy[119] == 5'd0) && !mesh_planned[119] && (mesh_route[119] == 3'd0) && (mesh_output_credits[119] == 3'd4)) &&
        ((mesh_occupancy[120] == 5'd0) && !mesh_planned[120] && (mesh_route[120] == 3'd0) && (mesh_output_credits[120] == 3'd4)) &&
        ((mesh_occupancy[121] == 5'd0) && !mesh_planned[121] && (mesh_route[121] == 3'd0) && (mesh_output_credits[121] == 3'd4)) &&
        ((mesh_occupancy[122] == 5'd0) && !mesh_planned[122] && (mesh_route[122] == 3'd0) && (mesh_output_credits[122] == 3'd4)) &&
        ((mesh_occupancy[123] == 5'd0) && !mesh_planned[123] && (mesh_route[123] == 3'd0) && (mesh_output_credits[123] == 3'd4)) &&
        ((mesh_occupancy[124] == 5'd0) && !mesh_planned[124] && (mesh_route[124] == 3'd0) && (mesh_output_credits[124] == 3'd4)) &&
        ((mesh_occupancy[125] == 5'd0) && !mesh_planned[125] && (mesh_route[125] == 3'd0) && (mesh_output_credits[125] == 3'd4)) &&
        ((mesh_occupancy[126] == 5'd0) && !mesh_planned[126] && (mesh_route[126] == 3'd0) && (mesh_output_credits[126] == 3'd4)) &&
        ((mesh_occupancy[127] == 5'd0) && !mesh_planned[127] && (mesh_route[127] == 3'd0) && (mesh_output_credits[127] == 3'd4)) &&
        ((mesh_occupancy[128] == 5'd0) && !mesh_planned[128] && (mesh_route[128] == 3'd0) && (mesh_output_credits[128] == 3'd4)) &&
        ((mesh_occupancy[129] == 5'd0) && !mesh_planned[129] && (mesh_route[129] == 3'd0) && (mesh_output_credits[129] == 3'd4)) &&
        ((mesh_occupancy[130] == 5'd0) && !mesh_planned[130] && (mesh_route[130] == 3'd0) && (mesh_output_credits[130] == 3'd4)) &&
        ((mesh_occupancy[131] == 5'd0) && !mesh_planned[131] && (mesh_route[131] == 3'd0) && (mesh_output_credits[131] == 3'd4)) &&
        ((mesh_occupancy[132] == 5'd0) && !mesh_planned[132] && (mesh_route[132] == 3'd0) && (mesh_output_credits[132] == 3'd4)) &&
        ((mesh_occupancy[133] == 5'd0) && !mesh_planned[133] && (mesh_route[133] == 3'd0) && (mesh_output_credits[133] == 3'd4)) &&
        ((mesh_occupancy[134] == 5'd0) && !mesh_planned[134] && (mesh_route[134] == 3'd0) && (mesh_output_credits[134] == 3'd4)))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_12
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_13
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_13
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic dlv,
    input wire logic [ 2 : 0 ] sink_occ,
    input wire logic [ 4 : 0 ] c_src [ 0 : 8 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_RESET_SOURCE_CREDIT_FULL: assert property (@(posedge clk) disable iff (!rst_ok)
    (rst_ok && !$past(rst_ok)) |-> ((((c_src[0] == 5'd16) &&
        (c_src[1] == 5'd16) &&
        (c_src[2] == 5'd16) &&
        (c_src[3] == 5'd16) &&
        (c_src[4] == 5'd16) &&
        (c_src[5] == 5'd16) &&
        (c_src[6] == 5'd16) &&
        (c_src[7] == 5'd16) &&
        (c_src[8] == 5'd16))) && !dlv && (sink_occ == 3'd0))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_13
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_14
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_14
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 7 : 0 ] mesh_x [ 0 : 26 ],
    input wire logic [ 7 : 0 ] mesh_y [ 0 : 26 ],
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

T_RESET_TILE_COORDS_BEFORE_TRAFFIC: assert property (@(posedge clk) disable iff (!rst_ok)
    ((!((mesh_occupancy[0] != 5'd0) || (mesh_occupancy[1] != 5'd0) || (mesh_occupancy[2] != 5'd0) || (mesh_occupancy[3] != 5'd0) || (mesh_occupancy[4] != 5'd0)) || ((mesh_x[0] == 8'd0) && (mesh_y[0] == 8'd0))) &&
        (!((mesh_occupancy[5] != 5'd0) || (mesh_occupancy[6] != 5'd0) || (mesh_occupancy[7] != 5'd0) || (mesh_occupancy[8] != 5'd0) || (mesh_occupancy[9] != 5'd0)) || ((mesh_x[1] == 8'd0) && (mesh_y[1] == 8'd0))) &&
        (!((mesh_occupancy[10] != 5'd0) || (mesh_occupancy[11] != 5'd0) || (mesh_occupancy[12] != 5'd0) || (mesh_occupancy[13] != 5'd0) || (mesh_occupancy[14] != 5'd0)) || ((mesh_x[2] == 8'd0) && (mesh_y[2] == 8'd0))) &&
        (!((mesh_occupancy[15] != 5'd0) || (mesh_occupancy[16] != 5'd0) || (mesh_occupancy[17] != 5'd0) || (mesh_occupancy[18] != 5'd0) || (mesh_occupancy[19] != 5'd0)) || ((mesh_x[3] == 8'd1) && (mesh_y[3] == 8'd0))) &&
        (!((mesh_occupancy[20] != 5'd0) || (mesh_occupancy[21] != 5'd0) || (mesh_occupancy[22] != 5'd0) || (mesh_occupancy[23] != 5'd0) || (mesh_occupancy[24] != 5'd0)) || ((mesh_x[4] == 8'd1) && (mesh_y[4] == 8'd0))) &&
        (!((mesh_occupancy[25] != 5'd0) || (mesh_occupancy[26] != 5'd0) || (mesh_occupancy[27] != 5'd0) || (mesh_occupancy[28] != 5'd0) || (mesh_occupancy[29] != 5'd0)) || ((mesh_x[5] == 8'd1) && (mesh_y[5] == 8'd0))) &&
        (!((mesh_occupancy[30] != 5'd0) || (mesh_occupancy[31] != 5'd0) || (mesh_occupancy[32] != 5'd0) || (mesh_occupancy[33] != 5'd0) || (mesh_occupancy[34] != 5'd0)) || ((mesh_x[6] == 8'd2) && (mesh_y[6] == 8'd0))) &&
        (!((mesh_occupancy[35] != 5'd0) || (mesh_occupancy[36] != 5'd0) || (mesh_occupancy[37] != 5'd0) || (mesh_occupancy[38] != 5'd0) || (mesh_occupancy[39] != 5'd0)) || ((mesh_x[7] == 8'd2) && (mesh_y[7] == 8'd0))) &&
        (!((mesh_occupancy[40] != 5'd0) || (mesh_occupancy[41] != 5'd0) || (mesh_occupancy[42] != 5'd0) || (mesh_occupancy[43] != 5'd0) || (mesh_occupancy[44] != 5'd0)) || ((mesh_x[8] == 8'd2) && (mesh_y[8] == 8'd0))) &&
        (!((mesh_occupancy[45] != 5'd0) || (mesh_occupancy[46] != 5'd0) || (mesh_occupancy[47] != 5'd0) || (mesh_occupancy[48] != 5'd0) || (mesh_occupancy[49] != 5'd0)) || ((mesh_x[9] == 8'd0) && (mesh_y[9] == 8'd1))) &&
        (!((mesh_occupancy[50] != 5'd0) || (mesh_occupancy[51] != 5'd0) || (mesh_occupancy[52] != 5'd0) || (mesh_occupancy[53] != 5'd0) || (mesh_occupancy[54] != 5'd0)) || ((mesh_x[10] == 8'd0) && (mesh_y[10] == 8'd1))) &&
        (!((mesh_occupancy[55] != 5'd0) || (mesh_occupancy[56] != 5'd0) || (mesh_occupancy[57] != 5'd0) || (mesh_occupancy[58] != 5'd0) || (mesh_occupancy[59] != 5'd0)) || ((mesh_x[11] == 8'd0) && (mesh_y[11] == 8'd1))) &&
        (!((mesh_occupancy[60] != 5'd0) || (mesh_occupancy[61] != 5'd0) || (mesh_occupancy[62] != 5'd0) || (mesh_occupancy[63] != 5'd0) || (mesh_occupancy[64] != 5'd0)) || ((mesh_x[12] == 8'd1) && (mesh_y[12] == 8'd1))) &&
        (!((mesh_occupancy[65] != 5'd0) || (mesh_occupancy[66] != 5'd0) || (mesh_occupancy[67] != 5'd0) || (mesh_occupancy[68] != 5'd0) || (mesh_occupancy[69] != 5'd0)) || ((mesh_x[13] == 8'd1) && (mesh_y[13] == 8'd1))) &&
        (!((mesh_occupancy[70] != 5'd0) || (mesh_occupancy[71] != 5'd0) || (mesh_occupancy[72] != 5'd0) || (mesh_occupancy[73] != 5'd0) || (mesh_occupancy[74] != 5'd0)) || ((mesh_x[14] == 8'd1) && (mesh_y[14] == 8'd1))) &&
        (!((mesh_occupancy[75] != 5'd0) || (mesh_occupancy[76] != 5'd0) || (mesh_occupancy[77] != 5'd0) || (mesh_occupancy[78] != 5'd0) || (mesh_occupancy[79] != 5'd0)) || ((mesh_x[15] == 8'd2) && (mesh_y[15] == 8'd1))) &&
        (!((mesh_occupancy[80] != 5'd0) || (mesh_occupancy[81] != 5'd0) || (mesh_occupancy[82] != 5'd0) || (mesh_occupancy[83] != 5'd0) || (mesh_occupancy[84] != 5'd0)) || ((mesh_x[16] == 8'd2) && (mesh_y[16] == 8'd1))) &&
        (!((mesh_occupancy[85] != 5'd0) || (mesh_occupancy[86] != 5'd0) || (mesh_occupancy[87] != 5'd0) || (mesh_occupancy[88] != 5'd0) || (mesh_occupancy[89] != 5'd0)) || ((mesh_x[17] == 8'd2) && (mesh_y[17] == 8'd1))) &&
        (!((mesh_occupancy[90] != 5'd0) || (mesh_occupancy[91] != 5'd0) || (mesh_occupancy[92] != 5'd0) || (mesh_occupancy[93] != 5'd0) || (mesh_occupancy[94] != 5'd0)) || ((mesh_x[18] == 8'd0) && (mesh_y[18] == 8'd2))) &&
        (!((mesh_occupancy[95] != 5'd0) || (mesh_occupancy[96] != 5'd0) || (mesh_occupancy[97] != 5'd0) || (mesh_occupancy[98] != 5'd0) || (mesh_occupancy[99] != 5'd0)) || ((mesh_x[19] == 8'd0) && (mesh_y[19] == 8'd2))) &&
        (!((mesh_occupancy[100] != 5'd0) || (mesh_occupancy[101] != 5'd0) || (mesh_occupancy[102] != 5'd0) || (mesh_occupancy[103] != 5'd0) || (mesh_occupancy[104] != 5'd0)) || ((mesh_x[20] == 8'd0) && (mesh_y[20] == 8'd2))) &&
        (!((mesh_occupancy[105] != 5'd0) || (mesh_occupancy[106] != 5'd0) || (mesh_occupancy[107] != 5'd0) || (mesh_occupancy[108] != 5'd0) || (mesh_occupancy[109] != 5'd0)) || ((mesh_x[21] == 8'd1) && (mesh_y[21] == 8'd2))) &&
        (!((mesh_occupancy[110] != 5'd0) || (mesh_occupancy[111] != 5'd0) || (mesh_occupancy[112] != 5'd0) || (mesh_occupancy[113] != 5'd0) || (mesh_occupancy[114] != 5'd0)) || ((mesh_x[22] == 8'd1) && (mesh_y[22] == 8'd2))) &&
        (!((mesh_occupancy[115] != 5'd0) || (mesh_occupancy[116] != 5'd0) || (mesh_occupancy[117] != 5'd0) || (mesh_occupancy[118] != 5'd0) || (mesh_occupancy[119] != 5'd0)) || ((mesh_x[23] == 8'd1) && (mesh_y[23] == 8'd2))) &&
        (!((mesh_occupancy[120] != 5'd0) || (mesh_occupancy[121] != 5'd0) || (mesh_occupancy[122] != 5'd0) || (mesh_occupancy[123] != 5'd0) || (mesh_occupancy[124] != 5'd0)) || ((mesh_x[24] == 8'd2) && (mesh_y[24] == 8'd2))) &&
        (!((mesh_occupancy[125] != 5'd0) || (mesh_occupancy[126] != 5'd0) || (mesh_occupancy[127] != 5'd0) || (mesh_occupancy[128] != 5'd0) || (mesh_occupancy[129] != 5'd0)) || ((mesh_x[25] == 8'd2) && (mesh_y[25] == 8'd2))) &&
        (!((mesh_occupancy[130] != 5'd0) || (mesh_occupancy[131] != 5'd0) || (mesh_occupancy[132] != 5'd0) || (mesh_occupancy[133] != 5'd0) || (mesh_occupancy[134] != 5'd0)) || ((mesh_x[26] == 8'd2) && (mesh_y[26] == 8'd2))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_14
`endif
