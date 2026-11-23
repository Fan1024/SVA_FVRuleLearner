// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_0
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_0
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic s_lst,
    input wire logic mid_val,
    input wire logic mid_rdy,
    input wire logic mid_lst
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

reg qa_lst [ 0 : DEPTH - 1 ] ;

reg [ 5 : 0 ] qa_wr , qa_rd ;

reg mid_fcs ;

reg [ 1 : 0 ] mid_idx ;

always @ ( posedge clock ) begin if ( reset ) begin qa_wr <= 6 'd 0 ; qa_rd <= 6 'd 0 ; mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin if ( s_fire ) begin qa_lst [ qa_wr ] <= s_lst ; qa_wr <= qa_wr + 6 'd 1 ; end if ( ( mid_val && mid_rdy ) ) begin if ( ! mid_fcs ) begin qa_rd <= qa_rd + 6 'd 1 ; if ( qa_lst [ qa_rd ] ) begin mid_fcs <= 1 'b 1 ; mid_idx <= 2 'd 0 ; end end else if ( mid_idx == 2 'd 3 ) begin mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin mid_idx <= mid_idx + 2 'd 1 ; end end end end

T_ORDER_MID_LAST_ONLY_ON_FOURTH_FCS_BYTE: assert property (@(posedge clock) disable iff (reset) (mid_val && mid_rdy) |-> (mid_lst == (mid_fcs && (mid_idx == 2'd3))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_0
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_1
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_1
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 7 : 0 ] mid_dat,
    input wire logic mid_val,
    input wire logic mid_rdy,
    input wire logic [ 7 : 0 ] chk_d0,
    input wire logic [ 7 : 0 ] chk_d1,
    input wire logic [ 7 : 0 ] chk_d2,
    input wire logic [ 7 : 0 ] chk_d3
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  mid_fire = mid_val && mid_rdy ;

reg [ 2 : 0 ] mid_hist ;

always @ ( posedge clock ) begin if ( reset ) begin mid_hist <= 3 'd 0 ; end else begin if ( mid_fire ) begin if ( mid_hist != 3 'd 4 ) mid_hist <= mid_hist + 3 'd 1 ; end end end

T_DATA_CHECK_DELAY_LINE_HOLDS_LAST_FOUR_BYTES: assert property (@(posedge clock) disable iff (reset)
    (mid_hist == 3'd4) |-> ((chk_d0 == $past(mid_dat, 1, mid_val && mid_rdy)) && (chk_d1 == $past(mid_dat, 2, mid_val && mid_rdy)) && (chk_d2 == $past(mid_dat, 3, mid_val && mid_rdy)) && (chk_d3 == $past(mid_dat, 4, mid_val && mid_rdy)))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_1
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_3
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_3
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic s_lst,
    input wire logic mid_val,
    input wire logic mid_rdy
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

reg qa_lst [ 0 : DEPTH - 1 ] ;

reg [ 5 : 0 ] qa_wr , qa_rd ;

reg [ 6 : 0 ] qa_occ ;

reg mid_fcs ;

reg [ 1 : 0 ] mid_idx ;

always @ ( posedge clock ) begin if ( reset ) begin qa_wr <= 6 'd 0 ; qa_rd <= 6 'd 0 ; qa_occ <= 7 'd 0 ; mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin if ( s_fire ) begin qa_lst [ qa_wr ] <= s_lst ; qa_wr <= qa_wr + 6 'd 1 ; end if ( ( mid_val && mid_rdy ) ) begin if ( ! mid_fcs ) begin qa_rd <= qa_rd + 6 'd 1 ; if ( qa_lst [ qa_rd ] ) begin mid_fcs <= 1 'b 1 ; mid_idx <= 2 'd 0 ; end end else if ( mid_idx == 2 'd 3 ) begin mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin mid_idx <= mid_idx + 2 'd 1 ; end end qa_occ <= qa_occ + { 6 'd 0 , s_fire } - { 6 'd 0 , ( ( mid_val && mid_rdy ) && ! mid_fcs ) } ; end end

T_UNIQ_MID_PAYLOAD_WAS_PUSHED: assert property (@(posedge clock) disable iff (reset) ((mid_val && mid_rdy) && !mid_fcs) |-> (qa_occ != 7'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_3
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_4
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_4
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic s_lst,
    input wire logic mid_val,
    input wire logic mid_rdy,
    input wire logic o_val,
    input wire logic o_rdy
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

wire  mid_fire = mid_val && mid_rdy ;

reg qa_lst [ 0 : DEPTH - 1 ] ;

reg [ 5 : 0 ] qa_wr , qa_rd ;

reg [ 6 : 0 ] qb_occ ;

reg mid_fcs ;

reg [ 1 : 0 ] mid_idx ;

wire  mid_payload = mid_fire && ! mid_fcs ;

always @ ( posedge clock ) begin if ( reset ) begin qa_wr <= 6 'd 0 ; qa_rd <= 6 'd 0 ; qb_occ <= 7 'd 0 ; mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin if ( s_fire ) begin qa_lst [ qa_wr ] <= s_lst ; qa_wr <= qa_wr + 6 'd 1 ; end if ( mid_fire ) begin if ( ! mid_fcs ) begin qa_rd <= qa_rd + 6 'd 1 ; if ( qa_lst [ qa_rd ] ) begin mid_fcs <= 1 'b 1 ; mid_idx <= 2 'd 0 ; end end else if ( mid_idx == 2 'd 3 ) begin mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin mid_idx <= mid_idx + 2 'd 1 ; end end qb_occ <= qb_occ + { 6 'd 0 , mid_payload } - { 6 'd 0 , ( o_val && o_rdy ) } ; end end

T_UNIQ_OUT_BYTE_WAS_RELEASED: assert property (@(posedge clock) disable iff (reset) (o_val && o_rdy) |-> (qb_occ != 7'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_4
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_5
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_5
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic s_lst,
    input wire logic mid_val,
    input wire logic mid_rdy
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

reg qa_lst [ 0 : DEPTH - 1 ] ;

reg [ 5 : 0 ] qa_wr , qa_rd ;

reg [ 3 : 0 ] fr_occ ;

reg mid_fcs ;

reg [ 1 : 0 ] mid_idx ;

always @ ( posedge clock ) begin if ( reset ) begin qa_wr <= 6 'd 0 ; qa_rd <= 6 'd 0 ; fr_occ <= 4 'd 0 ; mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin if ( s_fire ) begin qa_lst [ qa_wr ] <= s_lst ; qa_wr <= qa_wr + 6 'd 1 ; end fr_occ <= fr_occ + { 3 'd 0 , ( s_fire && s_lst ) } - { 3 'd 0 , ( ( ( mid_val && mid_rdy ) && mid_fcs ) && ( mid_idx == 2 'd 3 ) ) } ; if ( ( mid_val && mid_rdy ) ) begin if ( ! mid_fcs ) begin qa_rd <= qa_rd + 6 'd 1 ; if ( qa_lst [ qa_rd ] ) begin mid_fcs <= 1 'b 1 ; mid_idx <= 2 'd 0 ; end end else if ( mid_idx == 2 'd 3 ) begin mid_fcs <= 1 'b 0 ; mid_idx <= 2 'd 0 ; end else begin mid_idx <= mid_idx + 2 'd 1 ; end end end end

T_UNIQ_MID_FCS_BELONGS_TO_A_FRAME: assert property (@(posedge clock) disable iff (reset) ((mid_val && mid_rdy) && mid_fcs) |-> (fr_occ != 4'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_5
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_17
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_17
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic mid_val,
    input wire logic [ 1 : 0 ] ins_state,
    input wire logic [ 31 : 0 ] ins_crc,
    input wire logic ins_tval,
    input wire logic ins_busy
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_INSERT_IDLE: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((ins_state == INS_IDLE) && (ins_crc == 32'hFFFFFFFF) && !mid_val && !ins_tval && !ins_busy)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_17
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_18
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_18
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic o_val,
    input wire logic bad_fcs,
    input wire logic [ 1 : 0 ] chk_state,
    input wire logic [ 31 : 0 ] chk_crc,
    input wire logic chk_tval
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_CHECK_IDLE: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((chk_state == INS_IDLE) && (chk_crc == 32'hFFFFFFFF) && !o_val && !chk_tval && !bad_fcs)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_18
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_19
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_19
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic chk_v0,
    input wire logic chk_v1,
    input wire logic chk_v2,
    input wire logic chk_v3
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_CHECK_DELAY_LINE_INVALID: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> (!chk_v0 && !chk_v1 && !chk_v2 && !chk_v3)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_19
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_20
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_20
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_rdy
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_SOURCE_PORT_NOT_READY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> !s_rdy
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_20
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_fcs_roundtrip_22
// BEGIN BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_22
`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic [ 1 : 0 ] ins_state
);

localparam integer DEPTH = 64 ;

localparam integer FRAMES = 8 ;

localparam [ 1 : 0 ] INS_IDLE = 2 'd 0 ;

localparam [ 1 : 0 ] INS_PAYLOAD = 2 'd 1 ;

localparam [ 1 : 0 ] INS_PAD = 2 'd 2 ;

localparam [ 1 : 0 ] INS_FCS = 2 'd 3 ;

localparam [ 7 : 0 ] N_MID_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 12 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_LIFECYCLE_NO_INPUT_ACCEPTED_DURING_FCS: assert property (@(posedge clock) disable iff (reset) (s_val && s_rdy) |-> (ins_state != INS_FCS));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_fcs_roundtrip_22
`endif
