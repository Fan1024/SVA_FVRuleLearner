// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_wb2axip_axi3_reorder_0
// BEGIN BLOCK_HARD_CASE wb2axip_axi3_reorder_0
`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (
    input wire  clock,
    input wire  reset,
    input wire logic w_val,
    input wire logic w_rdy,
    input wire logic m_val,
    input wire logic m_rdy,
    input wire logic [ 15 : 0 ] sr_valid
);

localparam integer AR = 32 ;

localparam integer AWQ = 16 ;

localparam integer NSREG = 16 ;

localparam [ 7 : 0 ] N_HEAD_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_AW_LOAD = 8 'd 8 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_AW_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  push_w = w_val && w_rdy ;

wire  pop_w = m_val && m_rdy ;

reg [ 5 : 0 ] ar_occ ;

always @ ( posedge clock ) begin if ( reset ) begin ar_occ <= 6 'd 0 ; end else begin ar_occ <= ar_occ + { 5 'd 0 , push_w } - { 5 'd 0 , pop_w } ; end end

T_CONSERV_INFLIGHT_EQ_SR_FILL_PLUS_OUTREG: assert property (@(posedge clock) disable iff (reset) (ar_occ == ($unsigned(6'($countones(sr_valid))) + {5'd0, m_val})));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE wb2axip_axi3_reorder_0
`endif

`ifdef BLOCK_HARD_CASE_wb2axip_axi3_reorder_4
// BEGIN BLOCK_HARD_CASE wb2axip_axi3_reorder_4
`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (
    input wire  clock,
    input wire  reset,
    input wire logic m_val,
    input wire logic m_rdy,
    input wire logic [ 1 : 0 ] m_id,
    input wire logic m_lst
);

localparam integer AR = 32 ;

localparam integer AWQ = 16 ;

localparam integer NSREG = 16 ;

localparam [ 7 : 0 ] N_HEAD_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_AW_LOAD = 8 'd 8 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_AW_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

reg out_pkt_active ;

reg [ 1 : 0 ] out_pkt_id ;

always @ ( posedge clock ) begin if ( reset ) begin out_pkt_active <= 1 'b 0 ; out_pkt_id <= 2 'd 0 ; end else begin if ( ( m_val && m_rdy ) ) begin if ( ! out_pkt_active ) begin out_pkt_id <= m_id ; out_pkt_active <= ! m_lst ; end else if ( m_lst ) begin out_pkt_active <= 1 'b 0 ; end else ; end end end

T_MUTEX_OUT_PACKET_NOT_INTERLEAVED: assert property (@(posedge clock) disable iff (reset) ((m_val && m_rdy) && out_pkt_active) |-> (m_id == out_pkt_id));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE wb2axip_axi3_reorder_4
`endif

`ifdef BLOCK_HARD_CASE_wb2axip_axi3_reorder_7
// BEGIN BLOCK_HARD_CASE wb2axip_axi3_reorder_7
`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (
    input wire  clock,
    input wire  reset,
    input wire logic w_val,
    input wire logic w_rdy,
    input wire logic m_val,
    input wire logic m_rdy
);

localparam integer AR = 32 ;

localparam integer AWQ = 16 ;

localparam integer NSREG = 16 ;

localparam [ 7 : 0 ] N_HEAD_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_AW_LOAD = 8 'd 8 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_AW_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  pop_w = m_val && m_rdy ;

reg [ 5 : 0 ] ar_occ ;

always @ ( posedge clock ) begin if ( reset ) begin ar_occ <= 6 'd 0 ; end else begin ar_occ <= ar_occ + { 5 'd 0 , ( w_val && w_rdy ) } - { 5 'd 0 , pop_w } ; end end

T_ALLOC_NO_W_ACCEPT_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) (ar_occ >= 6'd17) |-> !(w_val && w_rdy));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE wb2axip_axi3_reorder_7
`endif

`ifdef BLOCK_HARD_CASE_wb2axip_axi3_reorder_14
// BEGIN BLOCK_HARD_CASE wb2axip_axi3_reorder_14
`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (
    input wire  clock,
    input wire  reset,
    input wire logic m_val,
    input wire logic [ 15 : 0 ] sr_valid
);

localparam integer AR = 32 ;

localparam integer AWQ = 16 ;

localparam integer NSREG = 16 ;

localparam [ 7 : 0 ] N_HEAD_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_AW_LOAD = 8 'd 8 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_AW_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_SHIFT_REGISTER_EMPTY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((sr_valid == 16'd0) && !m_val)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE wb2axip_axi3_reorder_14
`endif

`ifdef BLOCK_HARD_CASE_wb2axip_axi3_reorder_15
// BEGIN BLOCK_HARD_CASE wb2axip_axi3_reorder_15
`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (
    input wire  clock,
    input wire  reset,
    input wire logic cid_valid,
    input wire logic [ 3 : 0 ] awf_fill,
    input wire logic [ 3 : 0 ] awf_wr,
    input wire logic [ 3 : 0 ] awf_rd
);

localparam integer AR = 32 ;

localparam integer AWQ = 16 ;

localparam integer NSREG = 16 ;

localparam [ 7 : 0 ] N_HEAD_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_AW_LOAD = 8 'd 8 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_AW_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_AW_TRACKING_EMPTY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((awf_fill == 4'd0) && (awf_wr == awf_rd) && !cid_valid)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE wb2axip_axi3_reorder_15
`endif

`ifdef BLOCK_HARD_CASE_wb2axip_axi3_reorder_16
// BEGIN BLOCK_HARD_CASE wb2axip_axi3_reorder_16
`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (
    input wire  clock,
    input wire  reset,
    input wire logic aw_rdy,
    input wire logic w_rdy
);

localparam integer AR = 32 ;

localparam integer AWQ = 16 ;

localparam integer NSREG = 16 ;

localparam [ 7 : 0 ] N_HEAD_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_AW_LOAD = 8 'd 8 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 16 ;

localparam [ 7 : 0 ] N_AW_BLOCK = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_BOTH_SLAVE_PORTS_READY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> (aw_rdy && w_rdy)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE wb2axip_axi3_reorder_16
`endif
