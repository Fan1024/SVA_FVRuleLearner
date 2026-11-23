// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_0
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_0
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 1 : 0 ] dq_req_valid,
    input wire logic [ 1 : 0 ] dq_req_ready,
    input wire logic [ 1 : 0 ] dq_req_queue,
    input wire logic [ 7 : 0 ] dq_req_tag,
    input wire logic [ 1 : 0 ] dq_resp_valid,
    input wire logic [ 1 : 0 ] dq_resp_ready,
    input wire logic [ 1 : 0 ] dq_resp_queue,
    input wire logic [ 7 : 0 ] dq_resp_tag
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

integer i ;

reg [ 4 : 0 ] dqq_mem [ 0 : 1 ] [ 0 : FIFO_N - 1 ] ;

reg [ FIFO_AW : 0 ] dqq_wr [ 0 : 1 ] ;

reg [ FIFO_AW : 0 ] dqq_rd [ 0 : 1 ] ;

wire  dq_fire0 = dq_req_valid [ 0 ] && dq_req_ready [ 0 ] ;

wire  dq_fire1 = dq_req_valid [ 1 ] && dq_req_ready [ 1 ] ;

wire  dq_rfire0 = dq_resp_valid [ 0 ] && dq_resp_ready [ 0 ] ;

wire  dq_rfire1 = dq_resp_valid [ 1 ] && dq_resp_ready [ 1 ] ;

always @ ( posedge clk ) begin if ( rst ) begin for ( i = 0 ; i < 2 ; i = i + 1 ) begin dqq_wr [ i ] <= 0 ; dqq_rd [ i ] <= 0 ; end end else begin if ( dq_fire0 ) begin dqq_mem [ 0 ] [ dqq_wr [ 0 ] [ FIFO_AW - 1 : 0 ] ] <= { dq_req_queue [ 0 ] , dq_req_tag [ 3 : 0 ] } ; dqq_wr [ 0 ] <= dqq_wr [ 0 ] + 1 'b 1 ; end if ( dq_rfire0 ) begin if ( dqq_wr [ 0 ] == dqq_rd [ 0 ] ) ; else begin dqq_rd [ 0 ] <= dqq_rd [ 0 ] + 1 'b 1 ; end end if ( dq_fire1 ) begin dqq_mem [ 1 ] [ dqq_wr [ 1 ] [ FIFO_AW - 1 : 0 ] ] <= { dq_req_queue [ 1 ] , dq_req_tag [ 7 : 4 ] } ; dqq_wr [ 1 ] <= dqq_wr [ 1 ] + 1 'b 1 ; end if ( dq_rfire1 ) begin if ( dqq_wr [ 1 ] == dqq_rd [ 1 ] ) ; else begin dqq_rd [ 1 ] <= dqq_rd [ 1 ] + 1 'b 1 ; end end end end

T_ORDER_DEQ_RESP_RX_RING_IN_REQUEST_ORDER: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && ((dq_resp_valid[1] && dq_resp_ready[1]) && (dqq_wr[1] != dqq_rd[1]) && (dqq_mem[1][dqq_rd[1][FIFO_AW-1:0]] != {dq_resp_queue[1], dq_resp_tag[7:4]})))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_0
`endif

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_1
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_1
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] dh_tag,
    input wire logic dh_valid,
    input wire logic dh_ready,
    input wire logic [ 3 : 0 ] dh_st_tag,
    input wire logic dh_st_valid
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

wire  dh_fire = dh_valid && dh_ready ;

reg [ 15 : 0 ] dh_out ;

always @ ( posedge clk ) begin if ( rst ) begin dh_out <= 16 'd 0 ; end else begin if ( dh_fire ) begin dh_out [ dh_tag ] <= 1 'b 1 ; end if ( dh_st_valid ) begin if ( ! ( dh_fire && dh_tag == dh_st_tag ) ) dh_out [ dh_st_tag ] <= 1 'b 0 ; end end end

T_UNIQ_DESC_DMA_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && ((dh_valid && dh_ready) && dh_out[dh_tag]))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_1
`endif

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_2
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_2
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] th_tag,
    input wire logic th_valid,
    input wire logic th_ready,
    input wire logic [ 3 : 0 ] th_st_tag,
    input wire logic th_st_valid
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

wire  th_fire = th_valid && th_ready ;

reg [ 15 : 0 ] th_out ;

always @ ( posedge clk ) begin if ( rst ) begin th_out <= 16 'd 0 ; end else begin if ( th_fire ) begin th_out [ th_tag ] <= 1 'b 1 ; end if ( th_st_valid ) begin if ( ! ( th_fire && th_tag == th_st_tag ) ) th_out [ th_st_tag ] <= 1 'b 0 ; end end end

T_UNIQ_TXDATA_DMA_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && ((th_valid && th_ready) && th_out[th_tag]))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_2
`endif

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_3
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_3
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] ch_tag,
    input wire logic ch_valid,
    input wire logic ch_ready,
    input wire logic [ 3 : 0 ] ch_st_tag,
    input wire logic ch_st_valid
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

wire  ch_fire = ch_valid && ch_ready ;

reg [ 15 : 0 ] ch_out ;

always @ ( posedge clk ) begin if ( rst ) begin ch_out <= 16 'd 0 ; end else begin if ( ch_fire ) begin ch_out [ ch_tag ] <= 1 'b 1 ; end if ( ch_st_valid ) begin if ( ! ( ch_fire && ch_tag == ch_st_tag ) ) ch_out [ ch_st_tag ] <= 1 'b 0 ; end end end

T_UNIQ_CPL_DMA_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && ((ch_valid && ch_ready) && ch_out[ch_tag]))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_3
`endif

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_9
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_9
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] dh_tag,
    input wire logic dh_valid,
    input wire logic dh_ready,
    input wire logic [ 3 : 0 ] dh_st_tag,
    input wire logic dh_st_valid
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

wire  dh_fire = dh_valid && dh_ready ;

reg [ 15 : 0 ] dh_out ;

always @ ( posedge clk ) begin if ( rst ) begin dh_out <= 16 'd 0 ; end else begin if ( dh_fire ) begin dh_out [ dh_tag ] <= 1 'b 1 ; end if ( dh_st_valid ) begin if ( ! ( dh_fire && dh_tag == dh_st_tag ) ) dh_out [ dh_st_tag ] <= 1 'b 0 ; end end end

T_REQRSP_DESC_DMA_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && (dh_st_valid && !dh_out[dh_st_tag] && !((dh_valid && dh_ready) && (dh_tag == dh_st_tag))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_9
`endif

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_10
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_10
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] th_tag,
    input wire logic th_valid,
    input wire logic th_ready,
    input wire logic [ 3 : 0 ] th_st_tag,
    input wire logic th_st_valid
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

wire  th_fire = th_valid && th_ready ;

reg [ 15 : 0 ] th_out ;

always @ ( posedge clk ) begin if ( rst ) begin th_out <= 16 'd 0 ; end else begin if ( th_fire ) begin th_out [ th_tag ] <= 1 'b 1 ; end if ( th_st_valid ) begin if ( ! ( th_fire && th_tag == th_st_tag ) ) th_out [ th_st_tag ] <= 1 'b 0 ; end end end

T_REQRSP_TXDATA_DMA_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && (th_st_valid && !th_out[th_st_tag] && !((th_valid && th_ready) && (th_tag == th_st_tag))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_10
`endif

`ifdef BLOCK_HARD_CASE_corundum_tx_rx_datapath_11
// BEGIN BLOCK_HARD_CASE corundum_tx_rx_datapath_11
`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (
    input wire  clk,
    input wire  rst,
    input wire logic [ 3 : 0 ] ch_tag,
    input wire logic ch_valid,
    input wire logic ch_ready,
    input wire logic [ 3 : 0 ] ch_st_tag,
    input wire logic ch_st_valid
);

localparam  DF_TABLE_SIZE = 4 ;

localparam  TX_TABLE_SIZE = 4 ;

localparam  RX_TABLE_SIZE = 4 ;

localparam  CW_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  MAC_FIFO_BYTES = 128 ;

localparam  FIFO_N = 8 ;

localparam  FIFO_AW = 3 ;

localparam  CSAT = 12 'd 4095 ;

localparam  TSAT = 12 'd 4095 ;

localparam  N_BLOCK = 12 'd 200 ;

localparam  N_FETCH = 12 'd 400 ;

localparam  N_PKT = 12 'd 1500 ;

localparam  N_TXCPL = 12 'd 64 ;

localparam  N_PROGRESS = 12 'd 400 ;

localparam  N_DFFULL = 12 'd 400 ;

wire  ch_fire = ch_valid && ch_ready ;

reg [ 15 : 0 ] ch_out ;

always @ ( posedge clk ) begin if ( rst ) begin ch_out <= 16 'd 0 ; end else begin if ( ch_fire ) begin ch_out [ ch_tag ] <= 1 'b 1 ; end if ( ch_st_valid ) begin if ( ! ( ch_fire && ch_tag == ch_st_tag ) ) ch_out [ ch_st_tag ] <= 1 'b 0 ; end end end

T_REQRSP_CPL_DMA_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    !$past(!rst && (ch_st_valid && !ch_out[ch_st_tag] && !((ch_valid && ch_ready) && (ch_tag == ch_st_tag))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_tx_rx_datapath_11
`endif
