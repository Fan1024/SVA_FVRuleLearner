// pmesh_top.v — OpenPiton P-Mesh NoC fabric.
//
// An X_TILES x Y_TILES mesh of OpenPiton NoC routers. Each tile carries the 3 P-Mesh
// virtual networks (NoC1/NoC2/NoC3) as 3 `dynamic_node_top_wrap` instances. The on-chip
// mesh (N/E/S/W) is wired between adjacent tiles; the processor-side (P) channels and the
// perimeter are this module's boundary.
//
// Cores + L1.5/L2 caches are not instantiated. This is the fabric alone; whatever
// instantiates it drives and observes the P channels.
//
// NoC flow-control = valid/yummy (yummy = downstream had space / consumed). network_define.v
// provides the static NoC widths (DATA_WIDTH=64, XY_WIDTH=8, CHIP_ID_WIDTH=14).
`include "network_define.v"

// Tile-count knobs: take the mesh dimensions from +define+PMESH_{X,Y}_TILES (reduced=2x2 default;
// the full launcher passes +define+PMESH_X_TILES=4 etc.). These feed the params below so the build
// define is NOT inert (a reviewer-flagged bug).
// NB: a PMESH_-prefixed name (NOT PITON_X_TILES) — OpenPiton's define.tmp.vh sets PITON_X_TILES=8 for
// the full chip, which would otherwise leak in via jg's cross-analyze macro persistence and force 8x8.
`ifndef PMESH_X_TILES
  `define PMESH_X_TILES 2
`endif
`ifndef PMESH_Y_TILES
  `define PMESH_Y_TILES 2
`endif

module pmesh_top #(
    parameter X_TILES = `PMESH_X_TILES,     // reduced=2x2 ; full launcher sets +define+PMESH_X_TILES=4
    parameter Y_TILES = `PMESH_Y_TILES,
    parameter NOCS    = 3,                  // NoC1/NoC2/NoC3
    parameter NT      = X_TILES * Y_TILES
) (
    input clk,
    input rst_n,
    // --- processor-side (P) channels: the coherence-endpoint boundary, one per tile per NoC ---
    // Inputs, driven by the instantiating module:
    input  [`DATA_WIDTH-1:0] pIn_data  [0:NT-1][0:NOCS-1],
    input                    pIn_valid [0:NT-1][0:NOCS-1],
    input                    pIn_yummy [0:NT-1][0:NOCS-1],   // endpoint consumed router's P output
    // Observed FV outputs:
    output [`DATA_WIDTH-1:0] pOut_data [0:NT-1][0:NOCS-1],
    output                   pOut_valid[0:NT-1][0:NOCS-1],
    output                   pOut_yummy[0:NT-1][0:NOCS-1],   // router consumed endpoint's P input
    output                   pThanks   [0:NT-1][0:NOCS-1]    // router->endpoint space_avail (credit)
);
    // ---- inter-tile mesh wires (per tile, per NoC, per direction) ----
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
          localparam integer TE = gy * X_TILES + ((gx + 1) % X_TILES);     // east neighbor
          localparam integer TS = ((gy + 1) % Y_TILES) * X_TILES + gx;     // south neighbor
          for (gn = 0; gn < NOCS; gn = gn + 1) begin : noc
            // East boundary: connect to east neighbor's West (mesh, no wrap on perimeter -> tie)
            wire is_e_edge = (gx == X_TILES-1);
            wire is_s_edge = (gy == Y_TILES-1);
            dynamic_node_top_wrap u_router (
              .clk        (clk),
              .reset_in   (~rst_n),
              // inputs from neighbors (perimeter edges have no neighbor -> 0 valid)
              .dataIn_N   (d_S[(gy==0)?T:((gy-1)*X_TILES+gx)][gn]),
              .dataIn_E   (is_e_edge ? {`DATA_WIDTH{1'b0}} : d_W[TE][gn]),
              .dataIn_S   (is_s_edge ? {`DATA_WIDTH{1'b0}} : d_N[TS][gn]),
              .dataIn_W   (d_E[(gx==0)?T:(gy*X_TILES+gx-1)][gn]),
              .dataIn_P   (pIn_data[T][gn]),
              .validIn_N  ((gy==0)        ? 1'b0 : v_S[(gy-1)*X_TILES+gx][gn]),
              .validIn_E  (is_e_edge      ? 1'b0 : v_W[TE][gn]),
              .validIn_S  (is_s_edge      ? 1'b0 : v_N[TS][gn]),
              .validIn_W  ((gx==0)        ? 1'b0 : v_E[gy*X_TILES+gx-1][gn]),
              .validIn_P  (pIn_valid[T][gn]),
              .yummyIn_N  ((gy==0)        ? 1'b1 : y_S[(gy-1)*X_TILES+gx][gn]),
              .yummyIn_E  (is_e_edge      ? 1'b1 : y_W[TE][gn]),
              .yummyIn_S  (is_s_edge      ? 1'b1 : y_N[TS][gn]),
              .yummyIn_W  ((gx==0)        ? 1'b1 : y_E[gy*X_TILES+gx-1][gn]),
              .yummyIn_P  (pIn_yummy[T][gn]),
              .myLocX     (gx[`XY_WIDTH-1:0]),
              .myLocY     (gy[`XY_WIDTH-1:0]),
              .myChipID   ({`CHIP_ID_WIDTH{1'b0}}),
              // outputs to neighbors
              .dataOut_N  (d_N[T][gn]), .dataOut_E (d_E[T][gn]),
              .dataOut_S  (d_S[T][gn]), .dataOut_W (d_W[T][gn]),
              .dataOut_P  (pOut_data[T][gn]),
              .validOut_N (v_N[T][gn]), .validOut_E(v_E[T][gn]),
              .validOut_S (v_S[T][gn]), .validOut_W(v_W[T][gn]),
              .validOut_P (pOut_valid[T][gn]),
              .yummyOut_N (y_N[T][gn]), .yummyOut_E(y_E[T][gn]),
              .yummyOut_S (y_S[T][gn]), .yummyOut_W(y_W[T][gn]),
              .yummyOut_P (pOut_yummy[T][gn]),
              .thanksIn_P (pThanks[T][gn])   // OUTPUT: space_avail/credit toward the P endpoint
            );
          end
        end
      end
    endgenerate
endmodule
