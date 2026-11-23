// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_0
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_0
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] iv,
    input wire logic [ 3 : 0 ] ird,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 9 : 0 ] spay [ 0 : 3 ],
    input wire logic [ 9 : 0 ] bpay [ 0 : 3 ]
);

wire [ 3 : 0 ] ipush = iv & ird ;

wire [ 3 : 0 ] xacc = bv & brd ;

reg [ 9 : 0 ] in_q [ 0 : 3 ] [ 0 : 3 ] ;

reg [ 1 : 0 ] in_wp [ 0 : 3 ] ;

reg [ 1 : 0 ] in_rp [ 0 : 3 ] ;

integer i , o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin in_wp [ o ] <= 2 'd 0 ; in_rp [ o ] <= 2 'd 0 ; end end else begin for ( i = 0 ; i < 4 ; i = i + 1 ) begin if ( ipush [ i ] ) begin in_q [ i ] [ in_wp [ i ] ] <= spay [ i ] ; in_wp [ i ] <= in_wp [ i ] + 2 'd 1 ; end if ( xacc [ i ] ) in_rp [ i ] <= in_rp [ i ] + 2 'd 1 ; end end end

T_ORDER_INPUT_BUFFER_HEAD_IS_SHADOW_HEAD: assert property (@(posedge clk) disable iff (rst) (((!bv[0] || (in_q[0][in_rp[0]] == bpay[0])) &&
        (!bv[1] || (in_q[1][in_rp[1]] == bpay[1])) &&
        (!bv[2] || (in_q[2][in_rp[2]] == bpay[2])) &&
        (!bv[3] || (in_q[3][in_rp[3]] == bpay[3])))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_0
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_1
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_1
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] srd,
    input wire logic [ 9 : 0 ] bpay [ 0 : 3 ],
    input wire logic [ 1 : 0 ] bdest [ 0 : 3 ],
    input wire logic [ 1 : 0 ] ssrc [ 0 : 3 ]
);

genvar go , gj ;

wire [ 3 : 0 ] xacc = bv & brd ;

wire [ 3 : 0 ] xpop = sv & srd ;

wire [ 3 : 0 ] acc_for [ 0 : 3 ] ;

generate for ( go = 0 ; go < 4 ; go = go + 1 ) begin : g_accfor for ( gj = 0 ; gj < 4 ; gj = gj + 1 ) begin : g_accfor_in assign acc_for [ go ] [ gj ] = xacc [ gj ] && ( bdest [ gj ] == go [ 1 : 0 ] ) ; end end endgenerate

wire [ 1 : 0 ] src_of [ 0 : 3 ] ;

generate for ( go = 0 ; go < 4 ; go = go + 1 ) begin : g_srcof assign src_of [ go ] = acc_for [ go ] [ 1 ] ? 2 'd 1 : acc_for [ go ] [ 2 ] ? 2 'd 2 : acc_for [ go ] [ 3 ] ? 2 'd 3 : 2 'd 0 ; end endgenerate

reg [ 9 : 0 ] sp_q [ 0 : 3 ] [ 0 : 3 ] ;

reg [ 1 : 0 ] sp_wp [ 0 : 3 ] ;

reg [ 1 : 0 ] sp_rp [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin sp_wp [ o ] <= 2 'd 0 ; sp_rp [ o ] <= 2 'd 0 ; end end else begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin if ( | acc_for [ o ] ) begin sp_q [ o ] [ sp_wp [ o ] ] <= { src_of [ o ] , bpay [ src_of [ o ] ] [ 7 : 0 ] } ; sp_wp [ o ] <= sp_wp [ o ] + 2 'd 1 ; end if ( xpop [ o ] ) sp_rp [ o ] <= sp_rp [ o ] + 2 'd 1 ; end end end

T_ORDER_CROSSBAR_SOURCE_IS_SHADOW_SOURCE: assert property (@(posedge clk) disable iff (rst) (((!sv[0] || (sp_q[0][sp_rp[0]][9:8] == ssrc[0])) &&
        (!sv[1] || (sp_q[1][sp_rp[1]][9:8] == ssrc[1])) &&
        (!sv[2] || (sp_q[2][sp_rp[2]][9:8] == ssrc[2])) &&
        (!sv[3] || (sp_q[3][sp_rp[3]][9:8] == ssrc[3])))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_1
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_2
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_2
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] srd,
    input wire logic [ 3 : 0 ] ov,
    input wire logic [ 3 : 0 ] ordy,
    input wire logic [ 1 : 0 ] ssrc [ 0 : 3 ],
    input wire logic [ 7 : 0 ] sdat [ 0 : 3 ],
    input wire logic [ 9 : 0 ] opay [ 0 : 3 ]
);

wire [ 3 : 0 ] xpop = sv & srd ;

wire [ 3 : 0 ] opop = ov & ordy ;

reg [ 9 : 0 ] of_q [ 0 : 3 ] [ 0 : 3 ] ;

reg [ 1 : 0 ] of_wp [ 0 : 3 ] ;

reg [ 1 : 0 ] of_rp [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin of_wp [ o ] <= 2 'd 0 ; of_rp [ o ] <= 2 'd 0 ; end end else begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin if ( xpop [ o ] ) begin of_q [ o ] [ of_wp [ o ] ] <= { ssrc [ o ] , sdat [ o ] } ; of_wp [ o ] <= of_wp [ o ] + 2 'd 1 ; end if ( opop [ o ] ) of_rp [ o ] <= of_rp [ o ] + 2 'd 1 ; end end end

T_ORDER_OUTPUT_BUFFER_SOURCE_IS_SHADOW_SOURCE: assert property (@(posedge clk) disable iff (rst) (((!ov[0] || (of_q[0][of_rp[0]][9:8] == opay[0][9:8])) &&
        (!ov[1] || (of_q[1][of_rp[1]][9:8] == opay[1][9:8])) &&
        (!ov[2] || (of_q[2][of_rp[2]][9:8] == opay[2][9:8])) &&
        (!ov[3] || (of_q[3][of_rp[3]][9:8] == opay[3][9:8])))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_2
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_3
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_3
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] ov
);

reg [ 2 : 0 ] in_cnt [ 0 : 3 ] ;

reg [ 2 : 0 ] sp_cnt [ 0 : 3 ] ;

reg [ 2 : 0 ] of_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin in_cnt [ o ] <= 3 'd 0 ; sp_cnt [ o ] <= 3 'd 0 ; of_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_ORDER_NO_HEAD_WITHOUT_A_SHADOW_ENTRY: assert property (@(posedge clk) disable iff (rst) ((((!bv[0] || (in_cnt[0] != 3'd0)) &&
        (!bv[1] || (in_cnt[1] != 3'd0)) &&
        (!bv[2] || (in_cnt[2] != 3'd0)) &&
        (!bv[3] || (in_cnt[3] != 3'd0)))) && (((!sv[0] || (sp_cnt[0] != 3'd0)) &&
        (!sv[1] || (sp_cnt[1] != 3'd0)) &&
        (!sv[2] || (sp_cnt[2] != 3'd0)) &&
        (!sv[3] || (sp_cnt[3] != 3'd0)))) && (((!ov[0] || (of_cnt[0] != 3'd0)) &&
        (!ov[1] || (of_cnt[1] != 3'd0)) &&
        (!ov[2] || (of_cnt[2] != 3'd0)) &&
        (!ov[3] || (of_cnt[3] != 3'd0))))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_3
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_4
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_4
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] srd,
    input wire logic [ 9 : 0 ] bpay [ 0 : 3 ],
    input wire logic [ 1 : 0 ] bdest [ 0 : 3 ],
    input wire logic [ 7 : 0 ] sdat [ 0 : 3 ]
);

genvar go , gj ;

wire [ 3 : 0 ] xacc = bv & brd ;

wire [ 3 : 0 ] xpop = sv & srd ;

wire [ 3 : 0 ] acc_for [ 0 : 3 ] ;

generate for ( go = 0 ; go < 4 ; go = go + 1 ) begin : g_accfor for ( gj = 0 ; gj < 4 ; gj = gj + 1 ) begin : g_accfor_in assign acc_for [ go ] [ gj ] = xacc [ gj ] && ( bdest [ gj ] == go [ 1 : 0 ] ) ; end end endgenerate

wire [ 1 : 0 ] src_of [ 0 : 3 ] ;

generate for ( go = 0 ; go < 4 ; go = go + 1 ) begin : g_srcof assign src_of [ go ] = acc_for [ go ] [ 1 ] ? 2 'd 1 : acc_for [ go ] [ 2 ] ? 2 'd 2 : acc_for [ go ] [ 3 ] ? 2 'd 3 : 2 'd 0 ; end endgenerate

reg [ 9 : 0 ] sp_q [ 0 : 3 ] [ 0 : 3 ] ;

reg [ 1 : 0 ] sp_wp [ 0 : 3 ] ;

reg [ 1 : 0 ] sp_rp [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin sp_wp [ o ] <= 2 'd 0 ; sp_rp [ o ] <= 2 'd 0 ; end end else begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin if ( | acc_for [ o ] ) begin sp_q [ o ] [ sp_wp [ o ] ] <= { src_of [ o ] , bpay [ src_of [ o ] ] [ 7 : 0 ] } ; sp_wp [ o ] <= sp_wp [ o ] + 2 'd 1 ; end if ( xpop [ o ] ) sp_rp [ o ] <= sp_rp [ o ] + 2 'd 1 ; end end end

T_DATA_CROSSBAR_WORD_IS_SHADOW_WORD: assert property (@(posedge clk) disable iff (rst) (((!sv[0] || (sp_q[0][sp_rp[0]][7:0] == sdat[0])) &&
        (!sv[1] || (sp_q[1][sp_rp[1]][7:0] == sdat[1])) &&
        (!sv[2] || (sp_q[2][sp_rp[2]][7:0] == sdat[2])) &&
        (!sv[3] || (sp_q[3][sp_rp[3]][7:0] == sdat[3])))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_4
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_5
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_5
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] srd,
    input wire logic [ 3 : 0 ] ov,
    input wire logic [ 3 : 0 ] ordy,
    input wire logic [ 1 : 0 ] ssrc [ 0 : 3 ],
    input wire logic [ 7 : 0 ] sdat [ 0 : 3 ],
    input wire logic [ 9 : 0 ] opay [ 0 : 3 ]
);

wire [ 3 : 0 ] xpop = sv & srd ;

wire [ 3 : 0 ] opop = ov & ordy ;

reg [ 9 : 0 ] of_q [ 0 : 3 ] [ 0 : 3 ] ;

reg [ 1 : 0 ] of_wp [ 0 : 3 ] ;

reg [ 1 : 0 ] of_rp [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin of_wp [ o ] <= 2 'd 0 ; of_rp [ o ] <= 2 'd 0 ; end end else begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin if ( xpop [ o ] ) begin of_q [ o ] [ of_wp [ o ] ] <= { ssrc [ o ] , sdat [ o ] } ; of_wp [ o ] <= of_wp [ o ] + 2 'd 1 ; end if ( opop [ o ] ) of_rp [ o ] <= of_rp [ o ] + 2 'd 1 ; end end end

T_DATA_OUTPUT_BUFFER_WORD_IS_SHADOW_WORD: assert property (@(posedge clk) disable iff (rst) (((!ov[0] || (of_q[0][of_rp[0]][7:0] == opay[0][7:0])) &&
        (!ov[1] || (of_q[1][of_rp[1]][7:0] == opay[1][7:0])) &&
        (!ov[2] || (of_q[2][of_rp[2]][7:0] == opay[2][7:0])) &&
        (!ov[3] || (of_q[3][of_rp[3]][7:0] == opay[3][7:0])))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_5
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_9
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_9
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 1 : 0 ] bdest [ 0 : 3 ]
);



T_UNIQ_INPUT_ACCEPTED_FOR_ONE_OUTPUT: assert property (@(posedge clk) disable iff (rst) ((($onehot0({((bv[0] & brd[0]) && (bdest[0] == 2'd3)), ((bv[0] & brd[0]) && (bdest[0] == 2'd2)), ((bv[0] & brd[0]) && (bdest[0] == 2'd1)), ((bv[0] & brd[0]) && (bdest[0] == 2'd0))})) &&
        ($onehot0({((bv[1] & brd[1]) && (bdest[1] == 2'd3)), ((bv[1] & brd[1]) && (bdest[1] == 2'd2)), ((bv[1] & brd[1]) && (bdest[1] == 2'd1)), ((bv[1] & brd[1]) && (bdest[1] == 2'd0))})) &&
        ($onehot0({((bv[2] & brd[2]) && (bdest[2] == 2'd3)), ((bv[2] & brd[2]) && (bdest[2] == 2'd2)), ((bv[2] & brd[2]) && (bdest[2] == 2'd1)), ((bv[2] & brd[2]) && (bdest[2] == 2'd0))})) &&
        ($onehot0({((bv[3] & brd[3]) && (bdest[3] == 2'd3)), ((bv[3] & brd[3]) && (bdest[3] == 2'd2)), ((bv[3] & brd[3]) && (bdest[3] == 2'd1)), ((bv[3] & brd[3]) && (bdest[3] == 2'd0))})))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_9
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_10
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_10
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] srd,
    input wire logic [ 3 : 0 ] ov,
    input wire logic [ 3 : 0 ] ordy
);

reg [ 2 : 0 ] in_cnt [ 0 : 3 ] ;

reg [ 2 : 0 ] sp_cnt [ 0 : 3 ] ;

reg [ 2 : 0 ] of_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin in_cnt [ o ] <= 3 'd 0 ; sp_cnt [ o ] <= 3 'd 0 ; of_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_UNIQ_NO_POP_WITHOUT_AN_ENTRY: assert property (@(posedge clk) disable iff (rst) ((((!(bv[0] & brd[0]) || in_cnt[0] != 3'd0) && (!(sv[0] & srd[0]) || sp_cnt[0] != 3'd0) && (!(ov[0] & ordy[0]) || of_cnt[0] != 3'd0)) &&
        ((!(bv[1] & brd[1]) || in_cnt[1] != 3'd0) && (!(sv[1] & srd[1]) || sp_cnt[1] != 3'd0) && (!(ov[1] & ordy[1]) || of_cnt[1] != 3'd0)) &&
        ((!(bv[2] & brd[2]) || in_cnt[2] != 3'd0) && (!(sv[2] & srd[2]) || sp_cnt[2] != 3'd0) && (!(ov[2] & ordy[2]) || of_cnt[2] != 3'd0)) &&
        ((!(bv[3] & brd[3]) || in_cnt[3] != 3'd0) && (!(sv[3] & srd[3]) || sp_cnt[3] != 3'd0) && (!(ov[3] & ordy[3]) || of_cnt[3] != 3'd0)))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_10
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_11
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_11
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 2 : 0 ] iusage [ 0 : 3 ]
);

reg [ 2 : 0 ] in_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin in_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_LOSS_INPUT_USAGE_MATCHES_SHADOW: assert property (@(posedge clk) disable iff (rst) (((in_cnt[0] == iusage[0]) &&
        (in_cnt[1] == iusage[1]) &&
        (in_cnt[2] == iusage[2]) &&
        (in_cnt[3] == iusage[3]))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_11
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_12
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_12
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 2 : 0 ] ousage [ 0 : 3 ]
);

reg [ 2 : 0 ] of_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin of_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_LOSS_OUTPUT_USAGE_MATCHES_SHADOW: assert property (@(posedge clk) disable iff (rst) (((of_cnt[0] == ousage[0]) &&
        (of_cnt[1] == ousage[1]) &&
        (of_cnt[2] == ousage[2]) &&
        (of_cnt[3] == ousage[3]))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_12
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_13
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_13
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic spa [ 0 : 3 ],
    input wire logic spb [ 0 : 3 ]
);

reg [ 2 : 0 ] sp_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin sp_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_LOSS_SPILL_OCCUPANCY_MATCHES_SHADOW: assert property (@(posedge clk) disable iff (rst) (((sp_cnt[0] == ({2'd0, spa[0]} + {2'd0, spb[0]})) &&
        (sp_cnt[1] == ({2'd0, spa[1]} + {2'd0, spb[1]})) &&
        (sp_cnt[2] == ({2'd0, spa[2]} + {2'd0, spb[2]})) &&
        (sp_cnt[3] == ({2'd0, spa[3]} + {2'd0, spb[3]})))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_13
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_14
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_14
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 1 : 0 ] bdest [ 0 : 3 ],
    input wire logic av [ 0 : 3 ],
    input wire logic ar [ 0 : 3 ]
);

wire [ 3 : 0 ] xacc = bv & brd ;

T_LOSS_SPILL_PUSH_MATCHES_ACCEPTED_INPUT: assert property (@(posedge clk) disable iff (rst)
    (((av[0] && ar[0]) == (|{(xacc[3] && (bdest[3] == 2'd0)), (xacc[2] && (bdest[2] == 2'd0)), (xacc[1] && (bdest[1] == 2'd0)), (xacc[0] && (bdest[0] == 2'd0))})) &&
        ((av[1] && ar[1]) == (|{(xacc[3] && (bdest[3] == 2'd1)), (xacc[2] && (bdest[2] == 2'd1)), (xacc[1] && (bdest[1] == 2'd1)), (xacc[0] && (bdest[0] == 2'd1))})) &&
        ((av[2] && ar[2]) == (|{(xacc[3] && (bdest[3] == 2'd2)), (xacc[2] && (bdest[2] == 2'd2)), (xacc[1] && (bdest[1] == 2'd2)), (xacc[0] && (bdest[0] == 2'd2))})) &&
        ((av[3] && ar[3]) == (|{(xacc[3] && (bdest[3] == 2'd3)), (xacc[2] && (bdest[2] == 2'd3)), (xacc[1] && (bdest[1] == 2'd3)), (xacc[0] && (bdest[0] == 2'd3))})))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_14
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_15
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_15
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 4 : 0 ] dut_ref_count [ 0 : 3 ] [ 0 : 3 ]
);

reg [ 4 : 0 ] n_pair [ 0 : 3 ] [ 0 : 3 ] ;

integer i , o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin for ( i = 0 ; i < 4 ; i = i + 1 ) begin n_pair [ i ] [ o ] <= 5 'd 0 ; end end end else ; end

T_LOSS_PAIR_COUNTS_MATCH_REFERENCE_RINGS: assert property (@(posedge clk) disable iff (rst) (((n_pair[0][0] == dut_ref_count[0][0]) &&
        (n_pair[0][1] == dut_ref_count[0][1]) &&
        (n_pair[0][2] == dut_ref_count[0][2]) &&
        (n_pair[0][3] == dut_ref_count[0][3]) &&
        (n_pair[1][0] == dut_ref_count[1][0]) &&
        (n_pair[1][1] == dut_ref_count[1][1]) &&
        (n_pair[1][2] == dut_ref_count[1][2]) &&
        (n_pair[1][3] == dut_ref_count[1][3]) &&
        (n_pair[2][0] == dut_ref_count[2][0]) &&
        (n_pair[2][1] == dut_ref_count[2][1]) &&
        (n_pair[2][2] == dut_ref_count[2][2]) &&
        (n_pair[2][3] == dut_ref_count[2][3]) &&
        (n_pair[3][0] == dut_ref_count[3][0]) &&
        (n_pair[3][1] == dut_ref_count[3][1]) &&
        (n_pair[3][2] == dut_ref_count[3][2]) &&
        (n_pair[3][3] == dut_ref_count[3][3]))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_15
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_16
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_16
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 1 : 0 ] bdest [ 0 : 3 ]
);



T_MUTEX_ONE_INPUT_PER_OUTPUT: assert property (@(posedge clk) disable iff (rst) ((($onehot0(({((bv[3] & brd[3]) && (bdest[3] == 2'd0)), ((bv[2] & brd[2]) && (bdest[2] == 2'd0)), ((bv[1] & brd[1]) && (bdest[1] == 2'd0)), ((bv[0] & brd[0]) && (bdest[0] == 2'd0))}))) &&
        ($onehot0(({((bv[3] & brd[3]) && (bdest[3] == 2'd1)), ((bv[2] & brd[2]) && (bdest[2] == 2'd1)), ((bv[1] & brd[1]) && (bdest[1] == 2'd1)), ((bv[0] & brd[0]) && (bdest[0] == 2'd1))}))) &&
        ($onehot0(({((bv[3] & brd[3]) && (bdest[3] == 2'd2)), ((bv[2] & brd[2]) && (bdest[2] == 2'd2)), ((bv[1] & brd[1]) && (bdest[1] == 2'd2)), ((bv[0] & brd[0]) && (bdest[0] == 2'd2))}))) &&
        ($onehot0(({((bv[3] & brd[3]) && (bdest[3] == 2'd3)), ((bv[2] & brd[2]) && (bdest[2] == 2'd3)), ((bv[1] & brd[1]) && (bdest[1] == 2'd3)), ((bv[0] & brd[0]) && (bdest[0] == 2'd3))}))))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_16
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_17
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_17
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] agnt [ 0 : 3 ]
);



T_MUTEX_ARBITER_GRANT_ONEHOT: assert property (@(posedge clk) disable iff (rst) ((($onehot0(agnt[0])) &&
        ($onehot0(agnt[1])) &&
        ($onehot0(agnt[2])) &&
        ($onehot0(agnt[3])))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_17
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_18
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_18
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 2 : 0 ] iusage [ 0 : 3 ],
    input wire logic [ 2 : 0 ] ousage [ 0 : 3 ]
);



T_BOUND_BUFFER_USAGE: assert property (@(posedge clk) disable iff (rst) ((((iusage[0] <= 3'd4) && (ousage[0] <= 3'd4)) &&
        ((iusage[1] <= 3'd4) && (ousage[1] <= 3'd4)) &&
        ((iusage[2] <= 3'd4) && (ousage[2] <= 3'd4)) &&
        ((iusage[3] <= 3'd4) && (ousage[3] <= 3'd4)))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_18
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_19
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_19
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst
);

reg [ 2 : 0 ] sp_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin sp_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_BOUND_SPILL_OCCUPANCY: assert property (@(posedge clk) disable iff (rst) (((sp_cnt[0] <= 3'd2) &&
        (sp_cnt[1] <= 3'd2) &&
        (sp_cnt[2] <= 3'd2) &&
        (sp_cnt[3] <= 3'd2))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_19
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_25
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_25
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] iv,
    input wire logic [ 3 : 0 ] ird,
    input wire logic [ 3 : 0 ] sv,
    input wire logic [ 3 : 0 ] srd
);

reg [ 2 : 0 ] in_cnt [ 0 : 3 ] ;

reg [ 2 : 0 ] of_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin in_cnt [ o ] <= 3 'd 0 ; of_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_PROTO_NO_PUSH_INTO_A_FULL_BUFFER: assert property (@(posedge clk) disable iff (rst) ((((iv[0] & ird[0]) |-> in_cnt[0] <= 3'd3) and ((iv[1] & ird[1]) |-> in_cnt[1] <= 3'd3) and ((iv[2] & ird[2]) |-> in_cnt[2] <= 3'd3) and ((iv[3] & ird[3]) |-> in_cnt[3] <= 3'd3)) and (((sv[0] & srd[0]) |-> of_cnt[0] <= 3'd3) and ((sv[1] & srd[1]) |-> of_cnt[1] <= 3'd3) and ((sv[2] & srd[2]) |-> of_cnt[2] <= 3'd3) and ((sv[3] & srd[3]) |-> of_cnt[3] <= 3'd3))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_25
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_26
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_26
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] brd,
    input wire logic [ 1 : 0 ] bdest [ 0 : 3 ]
);

reg [ 2 : 0 ] sp_cnt [ 0 : 3 ] ;

integer o ;

always @ ( posedge clk ) begin if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin sp_cnt [ o ] <= 3 'd 0 ; end end else ; end

T_PROTO_NO_PUSH_INTO_A_FULL_SPILL: assert property (@(posedge clk) disable iff (rst) (((|({((bv[3] & brd[3]) && (bdest[3] == 2'd0)), ((bv[2] & brd[2]) && (bdest[2] == 2'd0)), ((bv[1] & brd[1]) && (bdest[1] == 2'd0)), ((bv[0] & brd[0]) && (bdest[0] == 2'd0))})) |-> sp_cnt[0] <= 3'd1) and ((|({((bv[3] & brd[3]) && (bdest[3] == 2'd1)), ((bv[2] & brd[2]) && (bdest[2] == 2'd1)), ((bv[1] & brd[1]) && (bdest[1] == 2'd1)), ((bv[0] & brd[0]) && (bdest[0] == 2'd1))})) |-> sp_cnt[1] <= 3'd1) and ((|({((bv[3] & brd[3]) && (bdest[3] == 2'd2)), ((bv[2] & brd[2]) && (bdest[2] == 2'd2)), ((bv[1] & brd[1]) && (bdest[1] == 2'd2)), ((bv[0] & brd[0]) && (bdest[0] == 2'd2))})) |-> sp_cnt[2] <= 3'd1) and ((|({((bv[3] & brd[3]) && (bdest[3] == 2'd3)), ((bv[2] & brd[2]) && (bdest[2] == 2'd3)), ((bv[1] & brd[1]) && (bdest[1] == 2'd3)), ((bv[0] & brd[0]) && (bdest[0] == 2'd3))})) |-> sp_cnt[3] <= 3'd1)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_26
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_32
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_32
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 2 : 0 ] iusage [ 0 : 3 ],
    input wire logic [ 2 : 0 ] ousage [ 0 : 3 ]
);

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_BUFFERS_EMPTY: assert property (@(posedge clk) (rst_q && !rst) |-> ((iusage[0] == 3'd0) && (iusage[1] == 3'd0) && (iusage[2] == 3'd0) && (iusage[3] == 3'd0) && (ousage[0] == 3'd0) && (ousage[1] == 3'd0) && (ousage[2] == 3'd0) && (ousage[3] == 3'd0)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_32
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_33
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_33
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] sv,
    input wire logic spa [ 0 : 3 ],
    input wire logic spb [ 0 : 3 ]
);

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_SPILLS_EMPTY: assert property (@(posedge clk) (rst_q && !rst) |-> (!spa[0] && !spb[0] && !spa[1] && !spb[1] && !spa[2] && !spb[2] && !spa[3] && !spb[3] && (sv == 4'd0)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_33
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_34
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_34
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 1 : 0 ] arrq [ 0 : 3 ],
    input wire logic alock [ 0 : 3 ]
);

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_ARBITERS_IDLE: assert property (@(posedge clk) (rst_q && !rst) |-> ((arrq[0] == 2'd0) && (arrq[1] == 2'd0) && (arrq[2] == 2'd0) && (arrq[3] == 2'd0) && !alock[0] && !alock[1] && !alock[2] && !alock[3]));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_34
`endif

`ifdef BLOCK_HARD_CASE_pulp_stream_xbar_order_35
// BEGIN BLOCK_HARD_CASE pulp_stream_xbar_order_35
`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] bv,
    input wire logic [ 3 : 0 ] ov
);

reg [ 4 : 0 ] n_pair [ 0 : 3 ] [ 0 : 3 ] ;

reg rst_q ;

integer i , o ;

always @ ( posedge clk ) begin rst_q <= rst ; if ( rst ) begin for ( o = 0 ; o < 4 ; o = o + 1 ) begin for ( i = 0 ; i < 4 ; i = i + 1 ) begin n_pair [ i ] [ o ] <= 5 'd 0 ; end end end else ; end

T_RESET_NOTHING_IN_FLIGHT: assert property (@(posedge clk) (rst_q && !rst) |-> ((bv == 4'd0) && (ov == 4'd0) && ($unsigned(10'({5'd0, n_pair[0][0]} + {5'd0, n_pair[0][1]} + {5'd0, n_pair[0][2]} + {5'd0, n_pair[0][3]} + {5'd0, n_pair[1][0]} + {5'd0, n_pair[1][1]} + {5'd0, n_pair[1][2]} + {5'd0, n_pair[1][3]} + {5'd0, n_pair[2][0]} + {5'd0, n_pair[2][1]} + {5'd0, n_pair[2][2]} + {5'd0, n_pair[2][3]} + {5'd0, n_pair[3][0]} + {5'd0, n_pair[3][1]} + {5'd0, n_pair[3][2]} + {5'd0, n_pair[3][3]})) == 10'd0)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_35
`endif
