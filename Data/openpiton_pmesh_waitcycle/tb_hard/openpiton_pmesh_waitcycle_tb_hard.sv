// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_0
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_0
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] e_p [ 0 : 8 ],
    input wire logic [ 4 : 0 ] c_src [ 0 : 8 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_0
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_1
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_1
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_requests [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_1
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_2
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_2
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ],
    input wire logic [ 3 : 0 ] mesh_head [ 0 : 134 ],
    input wire logic [ 3 : 0 ] mesh_tail [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_2
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_3
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_3
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 2 : 0 ] mesh_output_credits [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_3
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_5
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_5
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 134 : 0 ] mesh_dequeue,
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_5
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_6
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_6
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] e_p [ 0 : 8 ],
    input wire logic [ 8 : 0 ] crd
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_6
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_7
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_7
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_input_grants [ 0 : 134 ],
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_7
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_8
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_8
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 2 : 0 ] e_w [ 0 : 8 ],
    input wire logic [ 2 : 0 ] e_n [ 0 : 8 ],
    input wire logic [ 7 : 0 ] mesh_link_valid
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_8
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_12
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_12
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ],
    input wire logic [ 134 : 0 ] mesh_planned,
    input wire logic [ 2 : 0 ] mesh_route [ 0 : 134 ],
    input wire logic [ 2 : 0 ] mesh_output_credits [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_12
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_13
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_13
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic dlv,
    input wire logic [ 2 : 0 ] sink_occ,
    input wire logic [ 4 : 0 ] c_src [ 0 : 8 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_13
`endif

`ifdef BLOCK_HARD_CASE_openpiton_pmesh_waitcycle_14
// BEGIN BLOCK_HARD_CASE openpiton_pmesh_waitcycle_14
`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input wire logic clk,
    input wire logic rst_ok,
    input wire logic [ 7 : 0 ] mesh_x [ 0 : 26 ],
    input wire logic [ 7 : 0 ] mesh_y [ 0 : 26 ],
    input wire logic [ 4 : 0 ] mesh_occupancy [ 0 : 134 ]
);

localparam logic signed [ 31 : 0 ] DRAIN_N = 32 'sh 8 ;

localparam logic signed [ 31 : 0 ] NOSPACE_N = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_pmesh_waitcycle_14
`endif
