// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_0
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_0
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire  buf_dat_rd_en,
    input wire  buf_dat_rd_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_0
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_1
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_1
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire  buf_wt_rd_en,
    input wire  buf_wt_rd_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_1
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_2
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_2
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire  sdp_valid,
    input wire  sdp_ready,
    input wire  accu2sc_credit_vld
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

wire  sdp_fire = sdp_valid && sdp_ready ;

reg [ 15 : 0 ] sdp_beats , sdp_credits ;

always @ ( posedge clk ) begin if ( ! reset_n ) begin sdp_beats <= 16 'd 0 ; sdp_credits <= 16 'd 0 ; end else begin if ( sdp_fire && ( sdp_beats != 16 'h ffff ) ) sdp_beats <= sdp_beats + 16 'd 1 ; if ( accu2sc_credit_vld && ( sdp_credits != 16 'h ffff ) ) sdp_credits <= sdp_credits + 16 'd 1 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_2
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_3
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_3
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire [ 4 : 0 ] csb_req_pvld,
    input wire [ 314 : 0 ] csb_req_pd_flat,
    input wire [ 4 : 0 ] csb_resp_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_3
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_4
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_4
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire [ 4 : 0 ] csb_req_pvld,
    input wire [ 314 : 0 ] csb_req_pd_flat,
    input wire [ 4 : 0 ] csb_resp_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_4
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_5
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_5
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire [ 4 : 0 ] csb_req_pvld,
    input wire [ 314 : 0 ] csb_req_pd_flat,
    input wire [ 4 : 0 ] csb_resp_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_5
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_6
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_6
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire  sdp_valid,
    input wire  sdp_ready,
    input wire  accu2sc_credit_vld
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_6
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_7
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_7
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire  buf_dat_rd_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

reg [ 3 : 0 ] dat_inflight ;

always @ ( posedge clk ) begin if ( ! reset_n ) begin dat_inflight <= 4 'd 0 ; end else ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_7
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_9
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_9
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire [ 3 : 0 ] mem_req_valid,
    input wire [ 315 : 0 ] mem_req_pd_flat
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_9
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_11
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_11
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire  buf_dat_rd_en,
    input wire  buf_dat_rd_valid
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_11
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_12
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_12
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire [ 1 : 0 ] sc2mac_dat_pvld,
    input wire [ 1 : 0 ] mac2accu_pvld
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_12
`endif

`ifdef BLOCK_HARD_CASE_nvdla_conv_pipeline_16
// BEGIN BLOCK_HARD_CASE nvdla_conv_pipeline_16
`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
    input wire  clk,
    input wire  reset_n,
    input wire [ 1 : 0 ] mac2accu_pvld,
    input wire [ 17 : 0 ] mac2accu_pd_flat
);

reg [ 7 : 0 ] age ;

always @ ( posedge clk ) begin if ( ! reset_n ) age <= 8 'd 0 ; else if ( age != 8 'h ff ) age <= age + 8 'd 1 ; end

wire [ 8 : 0 ] mac_pd [ 0 : 1 ] ;

assign mac_pd [ 0 ] = mac2accu_pd_flat [ 8 : 0 ] ;

assign mac_pd [ 1 ] = mac2accu_pd_flat [ 17 : 9 ] ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_16
`endif
