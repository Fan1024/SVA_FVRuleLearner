// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_0
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_0
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic s_lst,
    input wire logic [ 3 : 0 ] pk_kep,
    input wire logic pk_val,
    input wire logic pk_rdy,
    input wire logic pk_lst
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

reg qa_lst [ 0 : DEPTH - 1 ] ;

reg [ 5 : 0 ] qa_wr , qa_rd ;

reg [ 6 : 0 ] qa_occ ;

always @ ( posedge clock ) begin if ( reset ) begin qa_wr <= 6 'd 0 ; qa_rd <= 6 'd 0 ; qa_occ <= 7 'd 0 ; end else begin if ( s_fire ) begin qa_lst [ qa_wr ] <= s_lst ; qa_wr <= qa_wr + 6 'd 1 ; end if ( ( pk_val && pk_rdy ) ) qa_rd <= qa_rd + { 3 'd 0 , $unsigned ( 3 ' ( { 2 'd 0 , pk_kep [ 0 ] } + { 2 'd 0 , pk_kep [ 1 ] } + { 2 'd 0 , pk_kep [ 2 ] } + { 2 'd 0 , pk_kep [ 3 ] } ) ) } ; qa_occ <= qa_occ + { 6 'd 0 , s_fire } - ( ( pk_val && pk_rdy ) ? { 4 'd 0 , $unsigned ( 3 ' ( { 2 'd 0 , pk_kep [ 0 ] } + { 2 'd 0 , pk_kep [ 1 ] } + { 2 'd 0 , pk_kep [ 2 ] } + { 2 'd 0 , pk_kep [ 3 ] } ) ) } : 7 'd 0 ) ; end end

T_ORDER_PACKED_LAST_MARKS_FRAME_END: assert property (@(posedge clock) disable iff (reset) !(!((!((pk_val && pk_rdy) && (qa_occ >= {4'd0, $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]}))}) && (3'd0 < $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})))) || (qa_lst[$unsigned(6'(qa_rd + 6'd0))] == ((3'd0 == ($unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})) - 3'd1)) ? pk_lst : 1'b0))) &&
        (!((pk_val && pk_rdy) && (qa_occ >= {4'd0, $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]}))}) && (3'd1 < $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})))) || (qa_lst[$unsigned(6'(qa_rd + 6'd1))] == ((3'd1 == ($unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})) - 3'd1)) ? pk_lst : 1'b0))) &&
        (!((pk_val && pk_rdy) && (qa_occ >= {4'd0, $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]}))}) && (3'd2 < $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})))) || (qa_lst[$unsigned(6'(qa_rd + 6'd2))] == ((3'd2 == ($unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})) - 3'd1)) ? pk_lst : 1'b0))) &&
        (!((pk_val && pk_rdy) && (qa_occ >= {4'd0, $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]}))}) && (3'd3 < $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})))) || (qa_lst[$unsigned(6'(qa_rd + 6'd3))] == ((3'd3 == ($unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]})) - 3'd1)) ? pk_lst : 1'b0))))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_0
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_2
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_2
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] pk_kep,
    input wire logic pk_val,
    input wire logic pk_rdy,
    input wire logic pk_lst
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_DATA_PACKED_FULL_WORD_UNLESS_LAST: assert property (@(posedge clock) disable iff (reset) ((pk_val && pk_rdy) && !pk_lst) |-> (pk_kep == 4'hf));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_2
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_3
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_3
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic [ 3 : 0 ] pk_kep,
    input wire logic pk_val,
    input wire logic pk_rdy
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

reg [ 6 : 0 ] qa_occ ;

always @ ( posedge clock ) begin if ( reset ) begin qa_occ <= 7 'd 0 ; end else begin qa_occ <= qa_occ + { 6 'd 0 , s_fire } - ( ( pk_val && pk_rdy ) ? { 4 'd 0 , $unsigned ( 3 ' ( { 2 'd 0 , pk_kep [ 0 ] } + { 2 'd 0 , pk_kep [ 1 ] } + { 2 'd 0 , pk_kep [ 2 ] } + { 2 'd 0 , pk_kep [ 3 ] } ) ) } : 7 'd 0 ) ; end end

T_UNIQ_PACKED_WORD_WAS_PUSHED: assert property (@(posedge clock) disable iff (reset) !((pk_val && pk_rdy) && (qa_occ < {4'd0, $unsigned(3'({2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]}))})));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_3
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_4
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_4
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] bf_kep,
    input wire logic bf_val,
    input wire logic bf_rdy,
    input wire logic o_val,
    input wire logic o_rdy
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  bf_fire = bf_val && bf_rdy ;

wire [ 2 : 0 ] bf_n = { 2 'd 0 , bf_kep [ 0 ] } + { 2 'd 0 , bf_kep [ 1 ] } + { 2 'd 0 , bf_kep [ 2 ] } + { 2 'd 0 , bf_kep [ 3 ] } ;

reg [ 6 : 0 ] qb_occ ;

always @ ( posedge clock ) begin if ( reset ) begin qb_occ <= 7 'd 0 ; end else begin qb_occ <= qb_occ + ( bf_fire ? { 4 'd 0 , bf_n } : 7 'd 0 ) - { 6 'd 0 , ( o_val && o_rdy ) } ; end end

T_UNIQ_OUT_BYTE_WAS_BUFFERED: assert property (@(posedge clock) disable iff (reset) (o_val && o_rdy) |-> (qb_occ != 7'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_4
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_5
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_5
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_val,
    input wire logic s_rdy,
    input wire logic [ 3 : 0 ] pk_kep,
    input wire logic pk_val,
    input wire logic pk_rdy,
    input wire logic [ 1 : 0 ] up_seg,
    input wire logic up_skid,
    input wire logic up_oval,
    input wire logic [ 3 : 0 ] up_okeep
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  s_fire = s_val && s_rdy ;

wire  pk_fire = pk_val && pk_rdy ;

wire [ 2 : 0 ] pk_n = { 2 'd 0 , pk_kep [ 0 ] } + { 2 'd 0 , pk_kep [ 1 ] } + { 2 'd 0 , pk_kep [ 2 ] } + { 2 'd 0 , pk_kep [ 3 ] } ;

reg [ 6 : 0 ] qa_occ ;

always @ ( posedge clock ) begin if ( reset ) begin qa_occ <= 7 'd 0 ; end else begin qa_occ <= qa_occ + { 6 'd 0 , s_fire } - ( pk_fire ? { 4 'd 0 , pk_n } : 7 'd 0 ) ; end end

T_CONSERV_QA_OCC_MATCHES_UPSIZE_STATE: assert property (@(posedge clock) disable iff (reset) (qa_occ == {3'd0, $unsigned(4'((up_oval ? {1'b0, $unsigned(3'({2'd0, up_okeep[0]} + {2'd0, up_okeep[1]}
                    + {2'd0, up_okeep[2]} + {2'd0, up_okeep[3]}))} : {2'd0, up_seg})
                       + {3'd0, up_skid}))}));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_5
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_6
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_6
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic pk_val,
    input wire logic pk_rdy,
    input wire logic bf_val,
    input wire logic bf_rdy,
    input wire logic pp_v0,
    input wire logic pp_v1,
    input wire logic pp_v2,
    input wire logic pp_v3,
    input wire logic [ 5 : 0 ] pp_ofw,
    input wire logic [ 5 : 0 ] pp_ofr,
    input wire logic pp_oval
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  pk_fire = pk_val && pk_rdy ;

wire  bf_fire = bf_val && bf_rdy ;

reg [ 6 : 0 ] qw_occ ;

always @ ( posedge clock ) begin if ( reset ) begin qw_occ <= 7 'd 0 ; end else begin qw_occ <= qw_occ + { 6 'd 0 , pk_fire } - { 6 'd 0 , bf_fire } ; end end

T_CONSERV_QW_OCC_MATCHES_PIPELINE_STATE: assert property (@(posedge clock) disable iff (reset) (qw_occ == ({4'd0, $unsigned(3'({2'd0, pp_v0} + {2'd0, pp_v1}
                     + {2'd0, pp_v2} + {2'd0, pp_v3}))} + {1'd0, pp_ofw - pp_ofr} + {6'd0, pp_oval})));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_6
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_7
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_7
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic [ 3 : 0 ] bf_kep,
    input wire logic bf_val,
    input wire logic bf_rdy,
    input wire logic o_val,
    input wire logic o_rdy,
    input wire logic dn_skid,
    input wire logic [ 3 : 0 ] dn_skeep,
    input wire logic dn_oval
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

wire  bf_fire = bf_val && bf_rdy ;

wire  o_fire = o_val && o_rdy ;

wire [ 2 : 0 ] bf_n = { 2 'd 0 , bf_kep [ 0 ] } + { 2 'd 0 , bf_kep [ 1 ] } + { 2 'd 0 , bf_kep [ 2 ] } + { 2 'd 0 , bf_kep [ 3 ] } ;

reg [ 6 : 0 ] qb_occ ;

always @ ( posedge clock ) begin if ( reset ) begin qb_occ <= 7 'd 0 ; end else begin qb_occ <= qb_occ + ( bf_fire ? { 4 'd 0 , bf_n } : 7 'd 0 ) - { 6 'd 0 , o_fire } ; end end

T_CONSERV_QB_OCC_MATCHES_DOWNSIZE_STATE: assert property (@(posedge clock) disable iff (reset) (qb_occ == {3'd0, $unsigned(4'((dn_skid ? {1'b0, $unsigned(3'({2'd0, dn_skeep[0]} + {2'd0, dn_skeep[1]}
                    + {2'd0, dn_skeep[2]} + {2'd0, dn_skeep[3]}))} : 4'd0) + {3'd0, dn_oval}))}));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_7
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_20
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_20
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic pk_val,
    input wire logic [ 1 : 0 ] up_seg,
    input wire logic up_skid
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_UPSIZE_IDLE: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> (!pk_val && !up_skid && (up_seg == 2'd0))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_20
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_21
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_21
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic pp_v0,
    input wire logic pp_v1,
    input wire logic pp_v2,
    input wire logic pp_v3,
    input wire logic [ 5 : 0 ] pp_ofw,
    input wire logic [ 5 : 0 ] pp_ofr,
    input wire logic pp_oval
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_PIPELINE_EMPTY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> (($unsigned(3'({2'd0, pp_v0} + {2'd0, pp_v1}
                     + {2'd0, pp_v2} + {2'd0, pp_v3})) == 3'd0) && (pp_ofw == pp_ofr) && !pp_oval)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_21
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_22
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_22
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic o_val,
    input wire logic dn_skid
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_DOWNSIZE_IDLE: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> (!o_val && !dn_skid)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_22
`endif

`ifdef BLOCK_HARD_CASE_verilog_axis_width_roundtrip_23
// BEGIN BLOCK_HARD_CASE verilog_axis_width_roundtrip_23
`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (
    input wire  clock,
    input wire  reset,
    input wire logic s_rdy
);

localparam integer DEPTH = 64 ;

localparam [ 7 : 0 ] N_OUT_STALL = 8 'd 8 ;

localparam [ 7 : 0 ] N_BUF_STALL = 8 'd 16 ;

localparam [ 7 : 0 ] N_NO_MOVE = 8 'd 24 ;

localparam [ 7 : 0 ] N_INPUT_BLOCK = 8 'd 128 ;

localparam [ 7 : 0 ] CTR_MAX = 8 'd 255 ;

T_RESET_INPUT_PORT_READY: assert property (@(posedge clock) disable iff (reset)
    $past(reset) |-> s_rdy
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_axis_width_roundtrip_23
`endif
