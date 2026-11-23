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

T_MUTEX_L1_ONE_DEQUEUE_SOURCE: assert property (@(posedge clk)
        disable iff (reset)
    (($onehot0(core_dequeue_sources[0])) &&
        ($onehot0(core_dequeue_sources[1])))
);
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

T_MUTEX_DTAG_UPDATE_ONEHOT: assert property (@(posedge clk)
        disable iff (reset)
    (($onehot0(core_dtag_updates[0])) &&
        ($onehot0(core_dtag_updates[1])))
);
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

T_PROTO_AXI_WLAST_ON_LAST_BEAT: assert property (@(posedge clk)
        disable iff (reset)
        ((dut_axi_wvalid && dut_axi_wready) && dut_axi_wlast) |-> mem_w_beat == BEATW'(BURST_BEATS - 1));
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

T_ORDER_FILL_QUEUE_FIFO_ORDER: assert property (@(posedge clk)
        disable iff (reset)
    (deq_fill && sh_cnt != 4'd0) |-> shq[sh_rd] == {fill_head_core, fill_head_id, ((fill_head_cache_type == 1'b0) ? 2'd1 : (((fill_head_packet_type == 3'd0) || (fill_head_packet_type == 3'd1)) ? 2'd0 : 2'd2))}
);
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

T_ORDER_AXI_READ_BEATS_IN_SEQUENCE: assert property (@(posedge clk)
        disable iff (reset)
    (raw_bus_state == 32'd4) |-> (bo_ff == rd_cnt)
);
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

T_COH_STORE_ACK_UPDATES_SNOOP_HITTER: assert property (@(posedge clk)
        disable iff (reset)
    ((!previous_store_ack_hit[0] || core_ddata_update[0]) &&
        (!previous_store_ack_hit[1] || core_ddata_update[1]))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nyuzi_l2_ring_coherence_13
`endif
