`include "network_define.v"

// Four independent single-flit streams converge through a real 3x3
// OpenPiton P-Mesh. There are no task assumptions or helper facts.
//
// Tile index = y*3+x, destination = tile 8 (2,2):
//   flow 0: tile 0 (0,0) -> E,E,S,S
//   flow 1: tile 1 (1,0) -> E,S,S
//   flow 2: tile 2 (2,0) -> S,S
//   flow 3: tile 5 (2,1) -> S
//
// The streams first couple at tile 2's south output, then couple again with
// flow 3 at tile 5's south output before sharing tile 8's processor egress.
module openpiton_pmesh_order_scaled_ft (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        src0_req,
    input  wire        src1_req,
    input  wire        src2_req,
    input  wire        src3_req,
    input  wire [19:0] src0_payload,
    input  wire [19:0] src1_payload,
    input  wire [19:0] src2_payload,
    input  wire [19:0] src3_payload
);
    localparam integer X_TILES = 3;
    localparam integer Y_TILES = 3;
    localparam integer NT      = X_TILES * Y_TILES;
    localparam integer NOCS    = 3;
    localparam integer NOC_ID  = 0;
    localparam integer SRC0    = 0;
    localparam integer SRC1    = 1;
    localparam integer SRC2    = 2;
    localparam integer SRC3    = 5;
    localparam integer DST     = 8;

    wire [`DATA_WIDTH-1:0] pIn_data   [0:NT-1][0:NOCS-1];
    wire                   pIn_valid  [0:NT-1][0:NOCS-1];
    wire                   pIn_yummy  [0:NT-1][0:NOCS-1];
    wire [`DATA_WIDTH-1:0] pOut_data  [0:NT-1][0:NOCS-1];
    wire                   pOut_valid [0:NT-1][0:NOCS-1];
    wire                   pOut_yummy [0:NT-1][0:NOCS-1];
    wire                   pThanks    [0:NT-1][0:NOCS-1];

    wire src0_space;
    wire src1_space;
    wire src2_space;
    wire src3_space;
    wire src0_send;
    wire src1_send;
    wire src2_send;
    wire src3_send;

    // dynamic_node_top registers reset_in once. Keep endpoints and the
    // independent oracle idle until the real router reset pipeline clears.
    reg dut_ready;
    always @(posedge clk) begin
        if (!reset_n)
            dut_ready <= 1'b0;
        else
            dut_ready <= 1'b1;
    end

    wire checker_reset_n;
    assign checker_reset_n = reset_n && dut_ready;
    assign src0_send = src0_req && src0_space && dut_ready;
    assign src1_send = src1_req && src1_space && dut_ready;
    assign src2_send = src2_req && src2_space && dut_ready;
    assign src3_send = src3_req && src3_space && dut_ready;

    space_avail_top #(.BUFFER_SIZE(16), .BUFFER_BITS(5)) u_src0_credit (
        .valid(src0_send), .yummy(pThanks[SRC0][NOC_ID]),
        .spc_avail(src0_space), .clk(clk), .reset(!reset_n)
    );
    space_avail_top #(.BUFFER_SIZE(16), .BUFFER_BITS(5)) u_src1_credit (
        .valid(src1_send), .yummy(pThanks[SRC1][NOC_ID]),
        .spc_avail(src1_space), .clk(clk), .reset(!reset_n)
    );
    space_avail_top #(.BUFFER_SIZE(16), .BUFFER_BITS(5)) u_src2_credit (
        .valid(src2_send), .yummy(pThanks[SRC2][NOC_ID]),
        .spc_avail(src2_space), .clk(clk), .reset(!reset_n)
    );
    space_avail_top #(.BUFFER_SIZE(16), .BUFFER_BITS(5)) u_src3_credit (
        .valid(src3_send), .yummy(pThanks[SRC3][NOC_ID]),
        .spc_avail(src3_space), .clk(clk), .reset(!reset_n)
    );

    // OpenPiton one-flit header: chip, dst_x, dst_y, final, length,
    // task-owned two-bit source tag, then unconstrained payload.
    wire [`DATA_WIDTH-1:0] src0_flit;
    wire [`DATA_WIDTH-1:0] src1_flit;
    wire [`DATA_WIDTH-1:0] src2_flit;
    wire [`DATA_WIDTH-1:0] src3_flit;
    assign src0_flit = {14'd0, 8'd2, 8'd2, 4'd0, 8'd0, 2'd0,
                        src0_payload};
    assign src1_flit = {14'd0, 8'd2, 8'd2, 4'd0, 8'd0, 2'd1,
                        src1_payload};
    assign src2_flit = {14'd0, 8'd2, 8'd2, 4'd0, 8'd0, 2'd2,
                        src2_payload};
    assign src3_flit = {14'd0, 8'd2, 8'd2, 4'd0, 8'd0, 2'd3,
                        src3_payload};

    genvar t, n;
    generate
        for (t = 0; t < NT; t = t + 1) begin : g_ep_tile
            for (n = 0; n < NOCS; n = n + 1) begin : g_ep_noc
                if ((t == SRC0) && (n == NOC_ID)) begin : g_src0
                    assign pIn_valid[t][n] = src0_send;
                    assign pIn_data[t][n]  = src0_flit;
                end else if ((t == SRC1) && (n == NOC_ID)) begin : g_src1
                    assign pIn_valid[t][n] = src1_send;
                    assign pIn_data[t][n]  = src1_flit;
                end else if ((t == SRC2) && (n == NOC_ID)) begin : g_src2
                    assign pIn_valid[t][n] = src2_send;
                    assign pIn_data[t][n]  = src2_flit;
                end else if ((t == SRC3) && (n == NOC_ID)) begin : g_src3
                    assign pIn_valid[t][n] = src3_send;
                    assign pIn_data[t][n]  = src3_flit;
                end else begin : g_inactive
                    assign pIn_valid[t][n] = 1'b0;
                    assign pIn_data[t][n]  = {`DATA_WIDTH{1'b0}};
                end
                assign pIn_yummy[t][n] = pOut_valid[t][n];
            end
        end
    endgenerate

    pmesh_top #(
        .X_TILES(X_TILES),
        .Y_TILES(Y_TILES),
        .NOCS(NOCS),
        .NT(NT)
    ) dut (
        .clk(clk),
        .rst_n(reset_n),
        .pIn_data(pIn_data),
        .pIn_valid(pIn_valid),
        .pIn_yummy(pIn_yummy),
        .pOut_data(pOut_data),
        .pOut_valid(pOut_valid),
        .pOut_yummy(pOut_yummy),
        .pThanks(pThanks)
    );

    wire dst_fire;
    assign dst_fire = pOut_valid[DST][NOC_ID] &&
                      pIn_yummy[DST][NOC_ID];

    // Reachability-only taps into the two intended shared south outputs.
    wire upstream_contention;
    wire downstream_contention;
    assign upstream_contention =
        dut.row[0].col[2].noc[NOC_ID].u_router.dynamic_node_top.route_req_w_to_s &&
        dut.row[0].col[2].noc[NOC_ID].u_router.dynamic_node_top.route_req_p_to_s;
    assign downstream_contention =
        dut.row[1].col[2].noc[NOC_ID].u_router.dynamic_node_top.route_req_n_to_s &&
        dut.row[1].col[2].noc[NOC_ID].u_router.dynamic_node_top.route_req_p_to_s;

    openpiton_pmesh_order_scaled_checker #(
        .REF_DEPTH(128)
    ) u_checker (
        .clk(clk),
        .reset_n(checker_reset_n),
        .inject0(src0_send),
        .inject0_flit(src0_flit),
        .inject1(src1_send),
        .inject1_flit(src1_flit),
        .inject2(src2_send),
        .inject2_flit(src2_flit),
        .inject3(src3_send),
        .inject3_flit(src3_flit),
        .dst_fire(dst_fire),
        .dst_flit(pOut_data[DST][NOC_ID]),
        .upstream_contention(upstream_contention),
        .downstream_contention(downstream_contention)
    );
endmodule
