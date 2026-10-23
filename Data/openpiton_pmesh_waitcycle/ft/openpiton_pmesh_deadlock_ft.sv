`include "network_define.v"

module openpiton_packet_source #(
    parameter integer TAG = 0
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire        space,
    input  wire        start_req,
    input  wire [18:0] start_payload,
    output wire        send,
    output wire [63:0] flit,
    output wire        active
);
    reg active_f;
    reg launched_f;
    reg [2:0] body_left_f;
    reg [15:0] payload_f;

    wire launch = enable && space && !active_f && !launched_f && start_req;
    wire tail = active_f && body_left_f == 1;
    wire [63:0] header_flit =
        {14'd0, 8'd2, 8'd2, 4'd0, 8'd7, TAG[3:0], 1'b0,
         start_payload[16:0]};
    wire [63:0] body_flit =
        {40'd0, TAG[3:0], tail, body_left_f, payload_f};

    assign send = enable && space &&
                  (active_f || (!launched_f && start_req));
    assign flit = active_f ? body_flit : header_flit;
    assign active = active_f;

    always @(posedge clk) begin
        if (!reset_n) begin
            active_f <= 1'b0;
            launched_f <= 1'b0;
            body_left_f <= 3'd0;
            payload_f <= 16'd0;
        end else if (launch) begin
            active_f <= 1'b1;
            launched_f <= 1'b1;
            body_left_f <= 3'd7;
            payload_f <= start_payload[15:0];
        end else if (active_f && send) begin
            if (body_left_f == 1) begin
                active_f <= 1'b0;
                body_left_f <= 3'd0;
            end else begin
                body_left_f <= body_left_f - 1'b1;
            end
        end
    end
endmodule

// Nine finite eight-flit packets converge over a real 3x3 OpenPiton P-Mesh
// toward tile 8. The target observes the real network-input FIFOs, route
// requests, and downstream-credit state that define the live wait-for graph.
module openpiton_pmesh_deadlock_ft (
    input wire         clk,
    input wire         reset_n,
    input wire [8:0]   src_start,
    input wire [170:0] src_payload,
    input wire         sink_ready
);
    localparam integer X_TILES = 3;
    localparam integer Y_TILES = 3;
    localparam integer NT = 9;
    localparam integer NOCS = 3;
    localparam integer NOC_ID = 0;
    localparam integer DST = 8;

    wire [`DATA_WIDTH-1:0] pIn_data   [0:NT-1][0:NOCS-1];
    wire                   pIn_valid  [0:NT-1][0:NOCS-1];
    wire                   pIn_yummy  [0:NT-1][0:NOCS-1];
    wire [`DATA_WIDTH-1:0] pOut_data  [0:NT-1][0:NOCS-1];
    wire                   pOut_valid [0:NT-1][0:NOCS-1];
    wire                   pOut_yummy [0:NT-1][0:NOCS-1];
    wire                   pThanks    [0:NT-1][0:NOCS-1];

    reg dut_ready;
    always @(posedge clk) begin
        if (!reset_n)
            dut_ready <= 1'b0;
        else
            dut_ready <= 1'b1;
    end
    wire checker_reset_n = reset_n && dut_ready;

    reg [2:0] sink_occupancy;
    wire sink_dequeue = sink_ready && sink_occupancy != 0;
    always @(posedge clk) begin
        if (!reset_n)
            sink_occupancy <= 3'd0;
        else begin
            case ({pOut_valid[DST][NOC_ID], sink_dequeue})
                2'b10: sink_occupancy <= sink_occupancy + 1'b1;
                2'b01: sink_occupancy <= sink_occupancy - 1'b1;
                default: sink_occupancy <= sink_occupancy;
            endcase
        end
    end

    wire [8:0] src_space;
    wire [8:0] src_send;
    wire [8:0] src_active;
    wire [63:0] src_flit [0:NT-1];

    genvar source;
    generate
        for (source = 0; source < NT; source = source + 1) begin : g_source
            openpiton_packet_source #(.TAG(source)) u_source (
                .clk(clk),
                .reset_n(reset_n),
                .enable(dut_ready),
                .space(src_space[source]),
                .start_req(src_start[source]),
                .start_payload(src_payload[19*source +: 19]),
                .send(src_send[source]),
                .flit(src_flit[source]),
                .active(src_active[source])
            );
            space_avail_top #(.BUFFER_SIZE(16), .BUFFER_BITS(5)) u_credit (
                .valid(src_send[source]),
                .yummy(pThanks[source][NOC_ID]),
                .spc_avail(src_space[source]),
                .clk(clk),
                .reset(!reset_n)
            );
        end
    endgenerate

    genvar tile, noc;
    generate
        for (tile = 0; tile < NT; tile = tile + 1) begin : g_ep_tile
            for (noc = 0; noc < NOCS; noc = noc + 1) begin : g_ep_noc
                if (noc == NOC_ID) begin : g_active_noc
                    assign pIn_valid[tile][noc] = src_send[tile];
                    assign pIn_data[tile][noc] = src_flit[tile];
                    if (tile == DST)
                        assign pIn_yummy[tile][noc] = sink_dequeue;
                    else
                        assign pIn_yummy[tile][noc] = pOut_valid[tile][noc];
                end else begin : g_inactive_noc
                    assign pIn_valid[tile][noc] = 1'b0;
                    assign pIn_data[tile][noc] = {`DATA_WIDTH{1'b0}};
                    assign pIn_yummy[tile][noc] = pOut_valid[tile][noc];
                end
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

    // Direction order is north, east, south, west. route_req[T][4*I+O]
    // records the request from input direction I to output direction O.
    wire [3:0]  input_occupied [0:NT-1];
    wire [15:0] route_req      [0:NT-1];
    wire [3:0]  no_credit      [0:NT-1];

    genvar gx, gy;
    generate
        for (gy = 0; gy < Y_TILES; gy = gy + 1) begin : g_observe_y
            for (gx = 0; gx < X_TILES; gx = gx + 1) begin : g_observe_x
                localparam integer T = gy * X_TILES + gx;
                assign input_occupied[T][0] =
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.north_input.NIB.elements_in_array_f != 0;
                assign input_occupied[T][1] =
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.east_input.NIB.elements_in_array_f != 0;
                assign input_occupied[T][2] =
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.south_input.NIB.elements_in_array_f != 0;
                assign input_occupied[T][3] =
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.west_input.NIB.elements_in_array_f != 0;

                assign route_req[T][0 +: 4] = {
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_n_to_w,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_n_to_s,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_n_to_e,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_n_to_n
                };
                assign route_req[T][4 +: 4] = {
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_e_to_w,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_e_to_s,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_e_to_e,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_e_to_n
                };
                assign route_req[T][8 +: 4] = {
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_s_to_w,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_s_to_s,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_s_to_e,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_s_to_n
                };
                assign route_req[T][12 +: 4] = {
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_w_to_w,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_w_to_s,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_w_to_e,
                    dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.route_req_w_to_n
                };

                assign no_credit[T][0] =
                    !dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.north_output.space_avail_connection;
                assign no_credit[T][1] =
                    !dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.east_output.space_avail_connection;
                assign no_credit[T][2] =
                    !dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.south_output.space_avail_connection;
                assign no_credit[T][3] =
                    !dut.row[gy].col[gx].noc[NOC_ID].u_router.dynamic_node_top.west_output.space_avail_connection;
            end
        end
    endgenerate

    openpiton_pmesh_deadlock_checker u_checker (
        .clk(clk),
        .reset_n(checker_reset_n),
        .sink_ready(sink_ready),
        .src_active(src_active),
        .input_occupied(input_occupied),
        .route_req(route_req),
        .no_credit(no_credit)
    );

endmodule
