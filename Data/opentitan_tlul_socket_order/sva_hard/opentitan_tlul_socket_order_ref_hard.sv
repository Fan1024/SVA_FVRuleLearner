// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_opentitan_tlul_socket_order_6
// BEGIN BLOCK_HARD_CASE opentitan_tlul_socket_order_6
`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] d_dv,
    input wire logic [ 3 : 0 ] d_dr
);

localparam int unsigned RD = 32 ;

wire [ 3 : 0 ] d_dv , d_dr ;

reg [ 3 : 0 ] dcnt [ 0 : 3 ] ;

integer k ;

always @ ( posedge clk ) begin if ( rst ) begin for ( k = 0 ; k < 4 ; k = k + 1 ) dcnt [ k ] <= 4 'd 0 ; end else ; end

T_REQRSP_DEVICE_ANSWERS_ONLY_WHAT_IT_OWES: assert property (@(posedge clk) disable iff (rst) (|$unsigned(4'(d_dv & d_dr))) |-> (dcnt[$unsigned(2'((d_dv[1] & d_dr[1])  ? 2'd1 : (d_dv[2] & d_dr[2])  ? 2'd2 :
                    (d_dv[3] & d_dr[3])  ? 2'd3 : 2'd0))] != 4'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_tlul_socket_order_6
`endif

`ifdef BLOCK_HARD_CASE_opentitan_tlul_socket_order_12
// BEGIN BLOCK_HARD_CASE opentitan_tlul_socket_order_12
`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] d_av,
    input wire logic [ 3 : 0 ] d_ar
);

localparam int unsigned RD = 32 ;

wire [ 3 : 0 ] d_av , d_ar ;

reg [ 3 : 0 ] dcnt [ 0 : 3 ] ;

integer k ;

always @ ( posedge clk ) begin if ( rst ) begin for ( k = 0 ; k < 4 ; k = k + 1 ) dcnt [ k ] <= 4 'd 0 ; end else ; end

T_PROTO_RESPONDER_NEVER_OVERFILLED: assert property (@(posedge clk) disable iff (rst) (((d_av[0] & d_ar[0]) |-> dcnt[0] <= 4'd3) and ((d_av[1] & d_ar[1]) |-> dcnt[1] <= 4'd3) and ((d_av[2] & d_ar[2]) |-> dcnt[2] <= 4'd3) and ((d_av[3] & d_ar[3]) |-> dcnt[3] <= 4'd3)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_tlul_socket_order_12
`endif

`ifdef BLOCK_HARD_CASE_opentitan_tlul_socket_order_13
// BEGIN BLOCK_HARD_CASE opentitan_tlul_socket_order_13
`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 8 : 0 ] nout,
    input wire logic hold,
    input wire logic [ 2 : 0 ] hq,
    input wire logic [ 2 : 0 ] hp
);

localparam int unsigned RD = 32 ;

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_SOCKET_IDLE: assert property (@(posedge clk) (rst_q && !rst) |-> (nout == 9'd0 && !hold && hq == 3'd0 && hp == 3'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_tlul_socket_order_13
`endif

`ifdef BLOCK_HARD_CASE_opentitan_tlul_socket_order_14
// BEGIN BLOCK_HARD_CASE opentitan_tlul_socket_order_14
`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 2 : 0 ] dq_req [ 0 : 3 ],
    input wire logic [ 2 : 0 ] dq_rsp [ 0 : 3 ]
);

localparam int unsigned RD = 32 ;

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_DEVICE_FIFOS_EMPTY: assert property (@(posedge clk) (rst_q && !rst) |-> (dq_req[0] == 3'd0 && dq_req[1] == 3'd0 && dq_req[2] == 3'd0 && dq_req[3] == 3'd0 && dq_rsp[0] == 3'd0 && dq_rsp[1] == 3'd0 && dq_rsp[2] == 3'd0 && dq_rsp[3] == 3'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_tlul_socket_order_14
`endif

`ifdef BLOCK_HARD_CASE_opentitan_tlul_socket_order_15
// BEGIN BLOCK_HARD_CASE opentitan_tlul_socket_order_15
`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] d_dv,
    input wire logic [ 2 : 0 ] d_cnt [ 0 : 3 ]
);

localparam int unsigned RD = 32 ;

wire [ 3 : 0 ] d_dv ;

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_RESPONDERS_EMPTY: assert property (@(posedge clk) (rst_q && !rst) |-> (d_cnt[0] == 3'd0 && d_cnt[1] == 3'd0 && d_cnt[2] == 3'd0 && d_cnt[3] == 3'd0 && !(|d_dv)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_tlul_socket_order_15
`endif

`ifdef BLOCK_HARD_CASE_opentitan_tlul_socket_order_16
// BEGIN BLOCK_HARD_CASE opentitan_tlul_socket_order_16
`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (
    input wire  clk,
    input wire  rst,
    input wire logic h_dv,
    input wire logic [ 6 : 0 ] dut_ref_count
);

localparam int unsigned RD = 32 ;

reg rst_q ;

always @ ( posedge clk ) begin rst_q <= rst ; end

T_RESET_NO_RESPONSE_OFFERED: assert property (@(posedge clk) (rst_q && !rst) |-> (!h_dv && dut_ref_count == 7'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_tlul_socket_order_16
`endif
