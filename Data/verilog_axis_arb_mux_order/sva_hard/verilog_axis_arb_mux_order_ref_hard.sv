// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_1
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_1
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic out_val,
    input wire logic out_rdy
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

reg [ 6 : 0 ] s2_occ ;

always @ ( posedge clock ) begin if ( reset ) begin s2_occ <= 7 'd 0 ; end else ; end

T_UNIQ_OUT_BEAT_WAS_MERGED: assert property (@(posedge clock) disable iff (reset) (out_val && out_rdy) |-> (s2_occ != 7'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_1
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_3
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_3
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] f_wr [ 0 : 3 ],
    input wire logic [ 3 : 0 ] f_rd [ 0 : 3 ],
    input wire logic [ 3 : 0 ] f_depth [ 0 : 3 ]
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_CONSERV_INPUT_STATUS_DEPTH_TRACKS_PTRS: assert property (@(posedge clock) disable iff (reset)
    !$past(reset) |-> !(!((f_depth[0] == $past($unsigned(4'(f_wr[0] - f_rd[0])))) &&
        (f_depth[1] == $past($unsigned(4'(f_wr[1] - f_rd[1])))) &&
        (f_depth[2] == $past($unsigned(4'(f_wr[2] - f_rd[2])))) &&
        (f_depth[3] == $past($unsigned(4'(f_wr[3] - f_rd[3]))))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_3
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_4
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_4
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 4 : 0 ] out_depth,
    input wire logic [ 4 : 0 ] o_wr,
    input wire logic [ 4 : 0 ] o_rd
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_CONSERV_OUTPUT_STATUS_DEPTH_TRACKS_PTRS: assert property (@(posedge clock) disable iff (reset)
    !$past(reset) |-> (out_depth == $past($unsigned(5'(o_wr - o_rd))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_4
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_8
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_8
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic mux_val,
    input wire logic mux_rdy,
    input wire logic mux_lst,
    input wire logic [ 2 : 0 ] mux_tid
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

reg mux_fr_active ;

reg [ 1 : 0 ] mux_fr_src ;

always @ ( posedge clock ) begin if ( reset ) begin mux_fr_active <= 1 'b 0 ; mux_fr_src <= 2 'd 0 ; end else begin if ( ( mux_val && mux_rdy ) ) begin if ( ! mux_fr_active ) begin mux_fr_src <= $unsigned ( 2 ' ( mux_tid [ 2 : 1 ] ) ) ; mux_fr_active <= ! mux_lst ; end else if ( mux_lst ) begin mux_fr_active <= 1 'b 0 ; end else ; end end end

T_MUTEX_MUX_FRAME_HAS_ONE_OWNER: assert property (@(posedge clock) disable iff (reset) ((mux_val && mux_rdy) && mux_fr_active) |-> ((mux_tid[2:1]) == mux_fr_src));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_8
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_9
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_9
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] f_wr [ 0 : 3 ],
    input wire logic [ 3 : 0 ] f_rd [ 0 : 3 ]
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_BOUND_INPUT_FIFO_FILL_LE_DEPTH: assert property (@(posedge clock) disable iff (reset) !(!(((f_wr[0] - f_rd[0]) <= 4'd8) &&
        ((f_wr[1] - f_rd[1]) <= 4'd8) &&
        ((f_wr[2] - f_rd[2]) <= 4'd8) &&
        ((f_wr[3] - f_rd[3]) <= 4'd8))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_9
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_11
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_11
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] f_ofw [ 0 : 3 ],
    input wire logic [ 3 : 0 ] f_ofr [ 0 : 3 ]
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_BOUND_INPUT_SKID_FIFO_NEVER_FULL: assert property (@(posedge clock) disable iff (reset) !(!(((f_ofw[0] - f_ofr[0]) <= 4'd7) &&
        ((f_ofw[1] - f_ofr[1]) <= 4'd7) &&
        ((f_ofw[2] - f_ofr[2]) <= 4'd7) &&
        ((f_ofw[3] - f_ofr[3]) <= 4'd7))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_11
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_17
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_17
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] fv_valid,
    input wire logic [ 3 : 0 ] fv_ready,
    input wire logic [ 31 : 0 ] fv_data,
    input wire logic [ 3 : 0 ] fv_last
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_PROTO_INPUT_FIFO_EGRESS_STABLE: assert property (@(posedge clock) disable iff (reset)
    !(!((!($past(fv_valid[0]) && !$past(fv_ready[0])) || (fv_valid[0] && (fv_data[0 +: 8] == $past(fv_data[0 +: 8])) && (fv_last[0] == $past(fv_last[0])))) &&
        (!($past(fv_valid[1]) && !$past(fv_ready[1])) || (fv_valid[1] && (fv_data[8 +: 8] == $past(fv_data[8 +: 8])) && (fv_last[1] == $past(fv_last[1])))) &&
        (!($past(fv_valid[2]) && !$past(fv_ready[2])) || (fv_valid[2] && (fv_data[16 +: 8] == $past(fv_data[16 +: 8])) && (fv_last[2] == $past(fv_last[2])))) &&
        (!($past(fv_valid[3]) && !$past(fv_ready[3])) || (fv_valid[3] && (fv_data[24 +: 8] == $past(fv_data[24 +: 8])) && (fv_last[3] == $past(fv_last[3]))))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_17
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_18
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_18
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] in_ready,
    input wire logic [ 3 : 0 ] f_wr [ 0 : 3 ],
    input wire logic [ 3 : 0 ] f_rd [ 0 : 3 ]
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_PROTO_SOURCE_PORT_READY_ONLY_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) !(!((in_ready[0] || ((f_wr[0] - f_rd[0]) == 4'd8)) &&
        (in_ready[1] || ((f_wr[1] - f_rd[1]) == 4'd8)) &&
        (in_ready[2] || ((f_wr[2] - f_rd[2]) == 4'd8)) &&
        (in_ready[3] || ((f_wr[3] - f_rd[3]) == 4'd8)))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_18
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_21
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_21
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] f_wr [ 0 : 3 ],
    input wire logic [ 3 : 0 ] f_rd [ 0 : 3 ]
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_INPUT_FIFOS_EMPTY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((f_wr[0] == f_rd[0]) && (f_wr[1] == f_rd[1]) && (f_wr[2] == f_rd[2]) && (f_wr[3] == f_rd[3]))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_21
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_22
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_22
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] grant,
    input wire logic grant_val
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_ARBITER_IDLE: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((grant == 4'd0) && !grant_val)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_22
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_23
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_23
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic mux_val,
    input wire logic [ 3 : 0 ] hold_val,
    input wire logic temp_val
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_MUX_HOLDS_NOTHING: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((hold_val == 4'd0) && !mux_val && !temp_val)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_23
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_arb_mux_order_24
// BEGIN BLOCK_HARD_CASE verilog_axis_arb_mux_order_24
`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (
    input wire  clock,
    input wire  reset,
    input wire logic out_val,
    input wire logic [ 4 : 0 ] o_wr,
    input wire logic [ 4 : 0 ] o_rd,
    input wire logic [ 1 : 0 ] o_pipe,
    input wire logic [ 3 : 0 ] o_ofw,
    input wire logic [ 3 : 0 ] o_ofr
);

localparam integer SRC = 4 ;

localparam integer S1_DEPTH = 16 ;

localparam integer S2_DEPTH = 64 ;

localparam [ 7 : 0 ] N_FAIR_LOOSE = 8 'd 24 ;

localparam [ 7 : 0 ] N_FAIR_TIGHT = 8 'd 16 ;

localparam [ 7 : 0 ] N_MUX_STALL = 8 'd 24 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_OUTPUT_FIFO_EMPTY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> ((o_wr == o_rd) && (o_ofw == o_ofr) && !out_val && (o_pipe == 2'd0))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_24
`endif
