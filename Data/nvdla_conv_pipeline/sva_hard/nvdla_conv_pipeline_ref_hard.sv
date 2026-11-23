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

T_ORDER_CBUF_DAT_RD_VALID_TRACKS_ISSUE: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd8)) |-> (buf_dat_rd_valid == $past(buf_dat_rd_en, 6))
);
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

T_ORDER_CBUF_WT_RD_VALID_TRACKS_ISSUE: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd8)) |-> (buf_wt_rd_valid == $past(buf_wt_rd_en, 6))
);
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

T_CONSERV_SDP_BEATS_EQ_CREDITS: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd4)) |-> (sdp_credits == $past(sdp_beats))
);
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

T_REQRSP_CDMA_CSB_RESP_SOLICITED: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd4)) |-> (csb_resp_valid[0] == $past((csb_req_pvld[0] && (!csb_req_pd_flat[54] || csb_req_pd_flat[55])), 2))
);
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

T_REQRSP_CSC_CSB_RESP_SOLICITED: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd4)) |-> (csb_resp_valid[1] == $past((csb_req_pvld[1] && (!csb_req_pd_flat[117] || csb_req_pd_flat[118])), 2))
);
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

T_REQRSP_CACC_CSB_RESP_SOLICITED: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd4)) |-> (csb_resp_valid[4] == $past((csb_req_pvld[4] && (!csb_req_pd_flat[306] || csb_req_pd_flat[307])), 2))
);
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

T_REQRSP_ACCU_CREDIT_MATCHES_SDP_BEAT: assert property (@(posedge clk)
      disable iff (!reset_n)
    ((age >= 8'd4)) |-> (accu2sc_credit_vld == $past((sdp_valid && sdp_ready)))
);
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

T_REQRSP_CBUF_DAT_RD_VALID_HAS_ISSUE: assert property (@(posedge clk)
      disable iff (!reset_n)
    (((age >= 8'd8)) && buf_dat_rd_valid) |-> (dat_inflight != 4'd0)
);
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

T_PROTO_MEM_DAT_REQ_ADDR_ALIGNED: assert property (@(posedge clk)
      disable iff (!reset_n)
    (((age >= 8'd16)) && mem_req_valid[0]) |-> ($unsigned(5'(mem_req_pd_flat[4:0])) == 5'd0)
);
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

T_BOUNDRSP_CBUF_DAT_RD_ANSWERED_IN_6: assert property (@(posedge clk)
      disable iff (!reset_n)
    (((age >= 8'd8)) && buf_dat_rd_en) |-> ##6 buf_dat_rd_valid
);
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

T_BOUNDRSP_MAC_A_OUTPUT_IN_4: assert property (@(posedge clk)
      disable iff (!reset_n)
    (((age >= 8'd8)) && sc2mac_dat_pvld[0]) |-> ##4 mac2accu_pvld[0]
);
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

T_LIFECYCLE_MAC_A_PD_HELD_UNLESS_VALID: assert property (@(posedge clk)
      disable iff (!reset_n)
    (((age >= 8'd8)) && !mac2accu_pvld[0]) |-> (mac_pd[0] == $past(mac_pd[0]))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_conv_pipeline_16
`endif
