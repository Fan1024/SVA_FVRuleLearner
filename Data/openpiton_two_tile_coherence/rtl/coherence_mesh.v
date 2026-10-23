// coherence_mesh.v -- AUTHORED for tasks/openpiton_two_tile_coherence.
//
// An X_TILES x Y_TILES mesh of OpenPiton NoC routers, three per node (NoC1,
// NoC2, NoC3), built from the byte-identical upstream `dynamic_node_top_wrap`.
// Derived from tasks/openpiton_pmesh_order/rtl/pmesh_top.v, which is the same
// fabric with a different boundary; two things differ and both are forced by
// what this task has to carry.
//
//  1. THE WEST PERIMETER OF COLUMN 0 IS A PORT, not a tie-off. OpenPiton's L2
//     addresses a memory request to chip id {1'b1, ...}, which every router
//     reads as off-chip and routes toward (`OFF_CHIP_NODE_X, `OFF_CHIP_NODE_Y)
//     = (0,0); at that node `NOC_FBITS_MEM == 3'b010 == `FINAL_WEST sends it out
//     the west link. That link is where a memory controller hangs on a real
//     chip, so the memory responder has to be reachable there. pmesh_top ties
//     west valid to 0 and west yummy to 1, which would silently swallow every
//     memory request and never answer one.
//
//  2. The north and (non-exported) west edges take constant 0 data rather than
//     the node's own output. pmesh_top feeds a perimeter node's own south/east
//     output back into its north/west input with validIn tied low; that is
//     harmless but it is a structural loop, and there is no reason to carry one.
//
// Everything else -- the neighbour wiring, the credit (valid/yummy) protocol,
// one router per NoC per node -- is pmesh_top's.
`include "network_define.v"

module coherence_mesh #(
    parameter X_TILES = 2,
    parameter Y_TILES = 1,
    parameter NOCS    = 3,
    parameter NT      = X_TILES * Y_TILES
) (
    input  wire clk,
    input  wire rst_n,

    // ---- processor-side (P) channels: one per node per NoC ----------------
    input  wire [`DATA_WIDTH-1:0] pIn_data   [0:NT-1][0:NOCS-1],
    input  wire                   pIn_valid  [0:NT-1][0:NOCS-1],
    input  wire                   pIn_yummy  [0:NT-1][0:NOCS-1],
    output wire [`DATA_WIDTH-1:0] pOut_data  [0:NT-1][0:NOCS-1],
    output wire                   pOut_valid [0:NT-1][0:NOCS-1],
    output wire                   pOut_yummy [0:NT-1][0:NOCS-1],
    output wire                   pThanks    [0:NT-1][0:NOCS-1],

    // ---- west perimeter of column 0: the off-chip link --------------------
    // wIn_*  : into the mesh   (memory -> chip)
    // wOut_* : out of the mesh (chip -> memory)
    input  wire [`DATA_WIDTH-1:0] wIn_data   [0:Y_TILES-1][0:NOCS-1],
    input  wire                   wIn_valid  [0:Y_TILES-1][0:NOCS-1],
    output wire                   wIn_yummy  [0:Y_TILES-1][0:NOCS-1],
    output wire [`DATA_WIDTH-1:0] wOut_data  [0:Y_TILES-1][0:NOCS-1],
    output wire                   wOut_valid [0:Y_TILES-1][0:NOCS-1],
    input  wire                   wOut_yummy [0:Y_TILES-1][0:NOCS-1]
);
    // ---- inter-node mesh wires (per node, per NoC, per direction) ----
    wire [`DATA_WIDTH-1:0] d_N [0:NT-1][0:NOCS-1], d_E [0:NT-1][0:NOCS-1],
                           d_S [0:NT-1][0:NOCS-1], d_W [0:NT-1][0:NOCS-1];
    wire                   v_N [0:NT-1][0:NOCS-1], v_E [0:NT-1][0:NOCS-1],
                           v_S [0:NT-1][0:NOCS-1], v_W [0:NT-1][0:NOCS-1];
    wire                   y_N [0:NT-1][0:NOCS-1], y_E [0:NT-1][0:NOCS-1],
                           y_S [0:NT-1][0:NOCS-1], y_W [0:NT-1][0:NOCS-1];

    genvar gx, gy, gn;
    generate
      for (gy = 0; gy < Y_TILES; gy = gy + 1) begin : row
        for (gx = 0; gx < X_TILES; gx = gx + 1) begin : col
          localparam integer T  = gy * X_TILES + gx;
          localparam integer TE = gy * X_TILES + gx + 1;
          localparam integer TS = (gy + 1) * X_TILES + gx;
          localparam integer TW = gy * X_TILES + gx - 1;
          localparam integer TN = (gy - 1) * X_TILES + gx;
          for (gn = 0; gn < NOCS; gn = gn + 1) begin : noc
            localparam integer IS_E_EDGE = (gx == X_TILES-1);
            localparam integer IS_S_EDGE = (gy == Y_TILES-1);
            localparam integer IS_N_EDGE = (gy == 0);
            localparam integer IS_W_EDGE = (gx == 0);

            dynamic_node_top_wrap u_router (
              .clk        (clk),
              .reset_in   (~rst_n),
              .dataIn_N   (IS_N_EDGE ? {`DATA_WIDTH{1'b0}} : d_S[TN][gn]),
              .dataIn_E   (IS_E_EDGE ? {`DATA_WIDTH{1'b0}} : d_W[TE][gn]),
              .dataIn_S   (IS_S_EDGE ? {`DATA_WIDTH{1'b0}} : d_N[TS][gn]),
              .dataIn_W   (IS_W_EDGE ? wIn_data[gy][gn]    : d_E[TW][gn]),
              .dataIn_P   (pIn_data[T][gn]),
              .validIn_N  (IS_N_EDGE ? 1'b0 : v_S[TN][gn]),
              .validIn_E  (IS_E_EDGE ? 1'b0 : v_W[TE][gn]),
              .validIn_S  (IS_S_EDGE ? 1'b0 : v_N[TS][gn]),
              .validIn_W  (IS_W_EDGE ? wIn_valid[gy][gn] : v_E[TW][gn]),
              .validIn_P  (pIn_valid[T][gn]),
              .yummyIn_N  (IS_N_EDGE ? 1'b1 : y_S[TN][gn]),
              .yummyIn_E  (IS_E_EDGE ? 1'b1 : y_W[TE][gn]),
              .yummyIn_S  (IS_S_EDGE ? 1'b1 : y_N[TS][gn]),
              .yummyIn_W  (IS_W_EDGE ? wOut_yummy[gy][gn] : y_E[TW][gn]),
              .yummyIn_P  (pIn_yummy[T][gn]),
              .myLocX     (gx[`XY_WIDTH-1:0]),
              .myLocY     (gy[`XY_WIDTH-1:0]),
              .myChipID   ({`CHIP_ID_WIDTH{1'b0}}),
              .dataOut_N  (d_N[T][gn]), .dataOut_E (d_E[T][gn]),
              .dataOut_S  (d_S[T][gn]), .dataOut_W (d_W[T][gn]),
              .dataOut_P  (pOut_data[T][gn]),
              .validOut_N (v_N[T][gn]), .validOut_E(v_E[T][gn]),
              .validOut_S (v_S[T][gn]), .validOut_W(v_W[T][gn]),
              .validOut_P (pOut_valid[T][gn]),
              .yummyOut_N (y_N[T][gn]), .yummyOut_E(y_E[T][gn]),
              .yummyOut_S (y_S[T][gn]), .yummyOut_W(y_W[T][gn]),
              .yummyOut_P (pOut_yummy[T][gn]),
              .thanksIn_P (pThanks[T][gn])
            );

            if (gx == 0) begin : g_west_port
              assign wOut_data[gy][gn]  = d_W[T][gn];
              assign wOut_valid[gy][gn] = v_W[T][gn];
              assign wIn_yummy[gy][gn]  = y_W[T][gn];
            end
          end
        end
      end
    endgenerate
endmodule
