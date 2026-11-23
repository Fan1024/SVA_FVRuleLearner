// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_corundum_dma_path_0
// BEGIN BLOCK_HARD_CASE corundum_dma_path_0
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 1 : 0 ] dq_req_valid,
    input wire [ 1 : 0 ] dq_req_ready,
    input wire [ 7 : 0 ] dq_req_tag,
    input wire [ 1 : 0 ] dq_resp_valid,
    input wire [ 1 : 0 ] dq_resp_ready,
    input wire [ 7 : 0 ] dq_resp_tag
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

reg [ 3 : 0 ] dqq_tag [ 0 : PORTS * 4 - 1 ] ;

reg [ 2 : 0 ] dqq_wr [ 0 : PORTS - 1 ] ;

reg [ 2 : 0 ] dqq_rd [ 0 : PORTS - 1 ] ;

wire [ 1 : 0 ] dq_req_fire = dq_req_valid & dq_req_ready ;

wire [ 1 : 0 ] dq_resp_fire = dq_resp_valid & dq_resp_ready ;

wire  dqq1_empty = ( dqq_wr [ 1 ] == dqq_rd [ 1 ] ) ;

integer i ;

always @ ( posedge clk ) begin if ( rst ) begin for ( i = 0 ; i < PORTS ; i = i + 1 ) begin dqq_wr [ i ] <= 3 'd 0 ; dqq_rd [ i ] <= 3 'd 0 ; end end else begin if ( dq_req_fire [ 0 ] ) begin dqq_tag [ 0 * 4 + dqq_wr [ 0 ] [ 1 : 0 ] ] <= dq_req_tag [ 3 : 0 ] ; dqq_wr [ 0 ] <= dqq_wr [ 0 ] + 3 'd 1 ; end if ( dq_req_fire [ 1 ] ) begin dqq_tag [ 1 * 4 + dqq_wr [ 1 ] [ 1 : 0 ] ] <= dq_req_tag [ 7 : 4 ] ; dqq_wr [ 1 ] <= dqq_wr [ 1 ] + 3 'd 1 ; end if ( dq_resp_fire [ 0 ] && ! ( ( dqq_wr [ 0 ] == dqq_rd [ 0 ] ) ) ) dqq_rd [ 0 ] <= dqq_rd [ 0 ] + 3 'd 1 ; if ( dq_resp_fire [ 1 ] && ! dqq1_empty ) dqq_rd [ 1 ] <= dqq_rd [ 1 ] + 3 'd 1 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_0
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_1
// BEGIN BLOCK_HARD_CASE corundum_dma_path_1
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 1 : 0 ] dq_req_valid,
    input wire [ 1 : 0 ] dq_req_ready,
    input wire [ 7 : 0 ] dq_req_tag,
    input wire [ 1 : 0 ] dq_resp_valid,
    input wire [ 1 : 0 ] dq_resp_ready,
    input wire [ 7 : 0 ] dq_resp_tag
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

reg [ 3 : 0 ] dqq_tag [ 0 : PORTS * 4 - 1 ] ;

reg [ 2 : 0 ] dqq_wr [ 0 : PORTS - 1 ] ;

reg [ 2 : 0 ] dqq_rd [ 0 : PORTS - 1 ] ;

wire [ 1 : 0 ] dq_req_fire = dq_req_valid & dq_req_ready ;

wire [ 1 : 0 ] dq_resp_fire = dq_resp_valid & dq_resp_ready ;

wire  dqq0_empty = ( dqq_wr [ 0 ] == dqq_rd [ 0 ] ) ;

integer i ;

always @ ( posedge clk ) begin if ( rst ) begin for ( i = 0 ; i < PORTS ; i = i + 1 ) begin dqq_wr [ i ] <= 3 'd 0 ; dqq_rd [ i ] <= 3 'd 0 ; end end else begin if ( dq_req_fire [ 0 ] ) begin dqq_tag [ 0 * 4 + dqq_wr [ 0 ] [ 1 : 0 ] ] <= dq_req_tag [ 3 : 0 ] ; dqq_wr [ 0 ] <= dqq_wr [ 0 ] + 3 'd 1 ; end if ( dq_req_fire [ 1 ] ) begin dqq_tag [ 1 * 4 + dqq_wr [ 1 ] [ 1 : 0 ] ] <= dq_req_tag [ 7 : 4 ] ; dqq_wr [ 1 ] <= dqq_wr [ 1 ] + 3 'd 1 ; end if ( dq_resp_fire [ 0 ] && ! dqq0_empty ) dqq_rd [ 0 ] <= dqq_rd [ 0 ] + 3 'd 1 ; if ( dq_resp_fire [ 1 ] && ! ( ( dqq_wr [ 1 ] == dqq_rd [ 1 ] ) ) ) dqq_rd [ 1 ] <= dqq_rd [ 1 ] + 3 'd 1 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_1
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_2
// BEGIN BLOCK_HARD_CASE corundum_dma_path_2
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 63 : 0 ] rd_addr,
    input wire  rd_valid
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_2
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_3
// BEGIN BLOCK_HARD_CASE corundum_dma_path_3
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 3 : 0 ] rd_tag,
    input wire  rd_valid,
    input wire  rd_ready,
    input wire [ 3 : 0 ] rd_st_tag,
    input wire  rd_st_val
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

reg [ 15 : 0 ] rd_out ;

always @ ( posedge clk ) begin if ( rst ) begin rd_out <= 16 'd 0 ; end else begin if ( ( rd_valid && rd_ready ) ) rd_out [ rd_tag ] <= 1 'b 1 ; if ( rd_st_val ) rd_out [ rd_st_tag ] <= 1 'b 0 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_3
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_4
// BEGIN BLOCK_HARD_CASE corundum_dma_path_4
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 3 : 0 ] wr_tag,
    input wire  wr_valid,
    input wire  wr_ready,
    input wire [ 3 : 0 ] wr_st_tag,
    input wire  wr_st_val
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

reg [ 15 : 0 ] wr_out ;

always @ ( posedge clk ) begin if ( rst ) begin wr_out <= 16 'd 0 ; end else begin if ( ( wr_valid && wr_ready ) ) wr_out [ wr_tag ] <= 1 'b 1 ; if ( wr_st_val ) wr_out [ wr_st_tag ] <= 1 'b 0 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_4
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_9
// BEGIN BLOCK_HARD_CASE corundum_dma_path_9
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire  df_req_valid,
    input wire  df_req_ready,
    input wire  df_st_valid
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

wire  df_req_fire = df_req_valid && df_req_ready ;

reg [ 9 : 0 ] n_req , n_status ;

always @ ( posedge clk ) begin if ( rst ) begin n_req <= 10 'd 0 ; n_status <= 10 'd 0 ; end else begin if ( df_req_fire && n_req != SAT ) n_req <= n_req + 10 'd 1 ; if ( df_st_valid && n_status != SAT ) n_status <= n_status + 10 'd 1 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_9
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_12
// BEGIN BLOCK_HARD_CASE corundum_dma_path_12
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 2 : 0 ] df_start_ptr,
    input wire [ 2 : 0 ] df_fin_ptr
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_12
`endif

`ifdef BLOCK_HARD_CASE_corundum_dma_path_13
// BEGIN BLOCK_HARD_CASE corundum_dma_path_13
`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire  clk,
    input wire  rst,
    input wire [ 1 : 0 ] dq_resp_valid,
    input wire [ 1 : 0 ] dq_resp_ready,
    input wire [ 3 : 0 ] dq_resp_optag,
    input wire [ 1 : 0 ] dq_resp_empty,
    input wire [ 1 : 0 ] dq_resp_error,
    input wire [ 3 : 0 ] dq_commit_optag,
    input wire [ 1 : 0 ] dq_commit_valid,
    input wire [ 1 : 0 ] dq_commit_ready
);

localparam  PORTS = 2 ;

localparam  DESC_TABLE_SIZE = 4 ;

localparam  CPL_TABLE_SIZE = 4 ;

localparam  OP_TABLE_SIZE = 4 ;

localparam  RING_SIZE = 4 ;

localparam  FIFO_N = 8 ;

localparam  SAT = 10 'd 1023 ;

localparam  N_BLOCK = 10 'd 96 ;

localparam  N_FETCH = 10 'd 255 ;

localparam  N_DESC = 10 'd 255 ;

localparam  N_CPL = 10 'd 255 ;

localparam  N_STALL = 10 'd 255 ;

localparam  N_FULL = 10 'd 255 ;

wire [ 1 : 0 ] dq_resp_fire = dq_resp_valid & dq_resp_ready ;

reg [ 3 : 0 ] dq_ops [ 0 : PORTS - 1 ] ;

wire [ 1 : 0 ] dq_take = dq_resp_fire & ~ dq_resp_empty & ~ dq_resp_error ;

wire [ 1 : 0 ] dq_commit_fire = dq_commit_valid & dq_commit_ready ;

always @ ( posedge clk ) begin if ( rst ) begin dq_ops [ 0 ] <= 4 'd 0 ; dq_ops [ 1 ] <= 4 'd 0 ; end else begin if ( dq_take [ 0 ] ) dq_ops [ 0 ] [ dq_resp_optag [ 1 : 0 ] ] <= 1 'b 1 ; if ( dq_commit_fire [ 0 ] ) dq_ops [ 0 ] [ dq_commit_optag [ 1 : 0 ] ] <= 1 'b 0 ; if ( dq_take [ 1 ] ) dq_ops [ 1 ] [ dq_resp_optag [ 3 : 2 ] ] <= 1 'b 1 ; if ( dq_commit_fire [ 1 ] ) dq_ops [ 1 ] [ dq_commit_optag [ 3 : 2 ] ] <= 1 'b 0 ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE corundum_dma_path_13
`endif
