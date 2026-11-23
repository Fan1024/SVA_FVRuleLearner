// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_nvdla_bdma_data_order_0
// BEGIN BLOCK_HARD_CASE nvdla_bdma_data_order_0
`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic rreq_valid,
    input wire logic rreq_ready,
    input wire logic [ 78 : 0 ] rreq_pd
);

localparam [ 7 : 0 ] N_REQ_OWED = 8 'd 8 ;

localparam [ 7 : 0 ] N_BEAT_OWED = 8 'd 64 ;

localparam [ 7 : 0 ] N_HELD = 8 'd 64 ;

localparam [ 7 : 0 ] N_WCMD_OWED = 8 'd 64 ;

localparam [ 9 : 0 ] N_WDAT_OWED = 10 'd 512 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 64 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

T_DATA_READ_REQUEST_SIZE_IS_ONE_LINE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (rreq_valid && rreq_ready) |-> (rreq_pd[78:64] == 15'd15));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_bdma_data_order_0
`endif

`ifdef BLOCK_HARD_CASE_nvdla_bdma_data_order_1
// BEGIN BLOCK_HARD_CASE nvdla_bdma_data_order_1
`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 12 : 0 ] ld_line_size,
    input wire logic [ 31 : 0 ] ld_line_strd,
    input wire logic [ 31 : 0 ] ld_surf_strd,
    input wire logic [ 23 : 0 ] ld_line_rpt,
    input wire logic [ 23 : 0 ] ld_surf_rpt,
    input wire logic ld_src_type,
    input wire logic [ 2 : 0 ] pkg_cmds_seen
);

localparam [ 7 : 0 ] N_REQ_OWED = 8 'd 8 ;

localparam [ 7 : 0 ] N_BEAT_OWED = 8 'd 64 ;

localparam [ 7 : 0 ] N_HELD = 8 'd 64 ;

localparam [ 7 : 0 ] N_WCMD_OWED = 8 'd 64 ;

localparam [ 9 : 0 ] N_WDAT_OWED = 10 'd 512 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 64 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

T_DATA_LOAD_HOLDS_THE_FROZEN_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((pkg_cmds_seen != 3'd0)) |-> ((ld_line_size == 13'd15) && (ld_src_type == 1'b1) &&
                    (ld_line_strd == 32'd1024) && (ld_surf_strd == 32'd2048) &&
                    (ld_line_rpt == 24'd1) && (ld_surf_rpt == 24'd0)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_bdma_data_order_1
`endif

`ifdef BLOCK_HARD_CASE_nvdla_bdma_data_order_2
// BEGIN BLOCK_HARD_CASE nvdla_bdma_data_order_2
`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 63 : 0 ] ld_line_addr,
    input wire logic [ 63 : 0 ] ld_surf_addr,
    input wire logic [ 2 : 0 ] pkg_cmds_seen
);

localparam [ 7 : 0 ] N_REQ_OWED = 8 'd 8 ;

localparam [ 7 : 0 ] N_BEAT_OWED = 8 'd 64 ;

localparam [ 7 : 0 ] N_HELD = 8 'd 64 ;

localparam [ 7 : 0 ] N_WCMD_OWED = 8 'd 64 ;

localparam [ 9 : 0 ] N_WDAT_OWED = 10 'd 512 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 64 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

T_DATA_LOAD_ADDRESS_STAYS_LINE_ALIGNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((pkg_cmds_seen != 3'd0)) |-> ((ld_line_addr[9:0] == 10'd0) && (ld_surf_addr[10:0] == 11'd0)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_bdma_data_order_2
`endif

`ifdef BLOCK_HARD_CASE_nvdla_bdma_data_order_22
// BEGIN BLOCK_HARD_CASE nvdla_bdma_data_order_22
`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic rreq_valid,
    input wire logic rreq_ready,
    input wire logic [ 78 : 0 ] rreq_pd
);

localparam [ 7 : 0 ] N_REQ_OWED = 8 'd 8 ;

localparam [ 7 : 0 ] N_BEAT_OWED = 8 'd 64 ;

localparam [ 7 : 0 ] N_HELD = 8 'd 64 ;

localparam [ 7 : 0 ] N_WCMD_OWED = 8 'd 64 ;

localparam [ 9 : 0 ] N_WDAT_OWED = 10 'd 512 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 64 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

T_PROTO_READ_REQUEST_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
    $past(reset_n && (rreq_valid && !rreq_ready)) |-> $stable(rreq_pd)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_bdma_data_order_22
`endif

`ifdef BLOCK_HARD_CASE_nvdla_bdma_data_order_24
// BEGIN BLOCK_HARD_CASE nvdla_bdma_data_order_24
`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic wreq_valid,
    input wire logic wreq_ready,
    input wire logic [ 514 : 0 ] wreq_pd
);

localparam [ 7 : 0 ] N_REQ_OWED = 8 'd 8 ;

localparam [ 7 : 0 ] N_BEAT_OWED = 8 'd 64 ;

localparam [ 7 : 0 ] N_HELD = 8 'd 64 ;

localparam [ 7 : 0 ] N_WCMD_OWED = 8 'd 64 ;

localparam [ 9 : 0 ] N_WDAT_OWED = 10 'd 512 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 64 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

T_PROTO_WRITE_REQUEST_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
    $past(reset_n && (wreq_valid && !wreq_ready)) |-> $stable(wreq_pd)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_bdma_data_order_24
`endif

`ifdef BLOCK_HARD_CASE_nvdla_bdma_data_order_30
// BEGIN BLOCK_HARD_CASE nvdla_bdma_data_order_30
`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic ld_cv_req_vld,
    input wire logic [ 2 : 0 ] pkg_cmds_seen
);

localparam [ 7 : 0 ] N_REQ_OWED = 8 'd 8 ;

localparam [ 7 : 0 ] N_BEAT_OWED = 8 'd 64 ;

localparam [ 7 : 0 ] N_HELD = 8 'd 64 ;

localparam [ 7 : 0 ] N_WCMD_OWED = 8 'd 64 ;

localparam [ 9 : 0 ] N_WDAT_OWED = 10 'd 512 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 64 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

T_LIFECYCLE_CVIF_READ_NEVER_REQUESTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((pkg_cmds_seen != 3'd0)) |-> !ld_cv_req_vld);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_bdma_data_order_30
`endif
