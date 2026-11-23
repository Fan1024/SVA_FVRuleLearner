// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_verilog_ethernet_mac_datapath_4
// BEGIN BLOCK_HARD_CASE verilog_ethernet_mac_datapath_4
`timescale 1ns/1ps
`default_nettype none

module veth_mac_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 1 : 0 ] pf_v,
    input wire logic [ 1 : 0 ] pf_r,
    input wire logic [ 1 : 0 ] pf_l,
    input wire logic [ 1 : 0 ] arb_grant,
    input wire logic arb_gvalid
);

localparam [ 7 : 0 ] HDR_BYTES = 8 'd 14 ;

localparam [ 7 : 0 ] MAX_PLEN = 8 'd 4 ;

localparam [ 7 : 0 ] MAX_IDX = HDR_BYTES + MAX_PLEN - 8 'd 1 ;

localparam [ 15 : 0 ] CNT_MAX = 16 'h FFFF ;

localparam [ 11 : 0 ] TMR_MAX = 12 'h FFF ;

localparam [ 15 : 0 ] HDR_FIFO_CAP = 16 'd 6 ;

localparam [ 15 : 0 ] PAY_FIFO_CAP = 16 'd 34 ;

localparam [ 15 : 0 ] MID_CAP = 16 'd 24 ;

localparam [ 11 : 0 ] N_ARBWAIT = 12 'd 600 ;

localparam [ 11 : 0 ] N_MACTX = 12 'd 400 ;

localparam [ 11 : 0 ] N_RXSTALL = 12 'd 600 ;

localparam [ 11 : 0 ] N_PROGRESS = 12 'd 400 ;

localparam [ 11 : 0 ] N_E2E = 12 'd 2000 ;

T_ALLOC_ARB_GRANT_HELD_UNTIL_ACK: assert property (@(posedge clk) disable iff (rst)
    (arb_gvalid && !(|(arb_grant & $unsigned(2'(pf_v & pf_r & pf_l))))) |=> (arb_gvalid && $stable(arb_grant)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_mac_datapath_4
`endif

`ifdef BLOCK_HARD_CASE_verilog_ethernet_mac_datapath_12
// BEGIN BLOCK_HARD_CASE verilog_ethernet_mac_datapath_12
`timescale 1ns/1ps
`default_nettype none

module veth_mac_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 1 : 0 ] hf_v,
    input wire logic [ 1 : 0 ] hf_r,
    input wire logic [ 15 : 0 ] hf0_type,
    input wire logic [ 15 : 0 ] hf1_type
);

localparam [ 7 : 0 ] HDR_BYTES = 8 'd 14 ;

localparam [ 7 : 0 ] MAX_PLEN = 8 'd 4 ;

localparam [ 7 : 0 ] MAX_IDX = HDR_BYTES + MAX_PLEN - 8 'd 1 ;

localparam [ 15 : 0 ] CNT_MAX = 16 'h FFFF ;

localparam [ 11 : 0 ] TMR_MAX = 12 'h FFF ;

localparam [ 15 : 0 ] HDR_FIFO_CAP = 16 'd 6 ;

localparam [ 15 : 0 ] PAY_FIFO_CAP = 16 'd 34 ;

localparam [ 15 : 0 ] MID_CAP = 16 'd 24 ;

localparam [ 11 : 0 ] N_ARBWAIT = 12 'd 600 ;

localparam [ 11 : 0 ] N_MACTX = 12 'd 400 ;

localparam [ 11 : 0 ] N_RXSTALL = 12 'd 600 ;

localparam [ 11 : 0 ] N_PROGRESS = 12 'd 400 ;

localparam [ 11 : 0 ] N_E2E = 12 'd 2000 ;

T_LIFECYCLE_HDRFIFO_FLOW_MATCHES_TYPE: assert property (@(posedge clk) disable iff (rst)
    (!(hf_v[0] & hf_r[0]) || hf0_type[0] == 1'b0) && (!(hf_v[1] & hf_r[1]) || hf1_type[0] == 1'b1));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE verilog_ethernet_mac_datapath_12
`endif
