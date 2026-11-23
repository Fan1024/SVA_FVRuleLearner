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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_arb_mux_order_24
`endif
