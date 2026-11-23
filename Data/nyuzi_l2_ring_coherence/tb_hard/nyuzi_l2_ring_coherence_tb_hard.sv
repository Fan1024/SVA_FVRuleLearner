// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_nyuzi_l2_ring_coherence_2
// BEGIN BLOCK_HARD_CASE nyuzi_l2_ring_coherence_2
`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input wire logic clk,
    input wire logic reset,
    input wire logic [ 1 : 0 ] [ 2 : 0 ] core_dequeue_sources
);

localparam logic [ 2 : 0 ] L2REQ_FLUSH = 3 'h 4 ;

localparam bit signed [ 31 : 0 ] BURST_BEATS = 32 'sh 4 ;

localparam bit signed [ 31 : 0 ] BEATW = 32 'sh 2 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_2
`endif

`ifdef BLOCK_HARD_CASE_nyuzi_l2_ring_coherence_3
// BEGIN BLOCK_HARD_CASE nyuzi_l2_ring_coherence_3
`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input wire logic clk,
    input wire logic reset,
    input wire logic [ 1 : 0 ] [ 3 : 0 ] core_dtag_updates
);

localparam logic [ 2 : 0 ] L2REQ_FLUSH = 3 'h 4 ;

localparam bit signed [ 31 : 0 ] BURST_BEATS = 32 'sh 4 ;

localparam bit signed [ 31 : 0 ] BEATW = 32 'sh 2 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_3
`endif

`ifdef BLOCK_HARD_CASE_nyuzi_l2_ring_coherence_8
// BEGIN BLOCK_HARD_CASE nyuzi_l2_ring_coherence_8
`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input wire logic clk,
    input wire logic reset,
    input wire logic [ 1 : 0 ] mem_w_beat,
    input wire logic dut_axi_wlast,
    input wire logic dut_axi_wvalid,
    input wire logic dut_axi_wready
);

localparam logic [ 2 : 0 ] L2REQ_FLUSH = 3 'h 4 ;

localparam bit signed [ 31 : 0 ] BURST_BEATS = 32 'sh 4 ;

localparam bit signed [ 31 : 0 ] BEATW = 32 'sh 2 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_8
`endif

`ifdef BLOCK_HARD_CASE_nyuzi_l2_ring_coherence_10
// BEGIN BLOCK_HARD_CASE nyuzi_l2_ring_coherence_10
`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input wire logic clk,
    input wire logic reset,
    input wire logic deq_fill,
    input wire logic [ 4 : 0 ] shq [ 0 : 7 ],
    input wire logic [ 2 : 0 ] sh_rd,
    input wire logic [ 3 : 0 ] sh_cnt,
    input wire logic fill_head_core,
    input wire logic [ 1 : 0 ] fill_head_id,
    input wire logic fill_head_cache_type,
    input wire logic [ 2 : 0 ] fill_head_packet_type
);

localparam logic [ 2 : 0 ] L2REQ_FLUSH = 3 'h 4 ;

localparam bit signed [ 31 : 0 ] BURST_BEATS = 32 'sh 4 ;

localparam bit signed [ 31 : 0 ] BEATW = 32 'sh 2 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_10
`endif

`ifdef BLOCK_HARD_CASE_nyuzi_l2_ring_coherence_11
// BEGIN BLOCK_HARD_CASE nyuzi_l2_ring_coherence_11
`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input wire logic clk,
    input wire logic reset,
    input wire logic [ 1 : 0 ] bo_ff,
    input wire logic [ 1 : 0 ] rd_cnt,
    input wire logic [ 31 : 0 ] raw_bus_state
);

localparam logic [ 2 : 0 ] L2REQ_FLUSH = 3 'h 4 ;

localparam bit signed [ 31 : 0 ] BURST_BEATS = 32 'sh 4 ;

localparam bit signed [ 31 : 0 ] BEATW = 32 'sh 2 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_11
`endif

`ifdef BLOCK_HARD_CASE_nyuzi_l2_ring_coherence_13
// BEGIN BLOCK_HARD_CASE nyuzi_l2_ring_coherence_13
`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input wire logic clk,
    input wire logic reset,
    input wire logic [ 1 : 0 ] previous_store_ack_hit,
    input wire logic [ 1 : 0 ] core_ddata_update
);

localparam logic [ 2 : 0 ] L2REQ_FLUSH = 3 'h 4 ;

localparam bit signed [ 31 : 0 ] BURST_BEATS = 32 'sh 4 ;

localparam bit signed [ 31 : 0 ] BEATW = 32 'sh 2 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_13
`endif
