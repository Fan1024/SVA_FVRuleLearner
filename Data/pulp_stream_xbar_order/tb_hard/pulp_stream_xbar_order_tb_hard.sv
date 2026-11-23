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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE pulp_stream_xbar_order_35
`endif
