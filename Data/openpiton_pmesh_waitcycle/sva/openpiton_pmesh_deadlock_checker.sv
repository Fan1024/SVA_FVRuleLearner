module openpiton_pmesh_deadlock_checker (
    input wire        clk,
    input wire        reset_n,
    input wire        sink_ready,
    input wire [8:0]  src_active,
    input wire [3:0]  input_occupied [0:8],
    input wire [15:0] route_req      [0:8],
    input wire [3:0]  no_credit      [0:8]
);
    // The sole congested destination buffer drains at least once in every
    // four-cycle window.
    A_FAIR_SINK: assume property (@(posedge clk) disable iff (!reset_n)
        1'b1 |-> ##[0:3] sink_ready);

    localparam integer X_TILES = 3;
    localparam integer NT = 9;
    localparam integer DIRS = 4;
    localparam integer NNODES = NT * DIRS;
    localparam integer NORTH = 0;
    localparam integer EAST = 1;
    localparam integer SOUTH = 2;
    localparam integer WEST = 3;

    reg [NNODES-1:0] wait_edge [0:NNODES-1];
    reg [NNODES-1:0] reach     [0:NNODES-1];
    reg [5:0] wait_edge_count;
    reg wait_cycle;
    reg wait_path2;
    reg horizontal_wait;
    reg vertical_wait;
    integer t;
    integer d;
    integer i;
    integer j;
    integer k;
    integer src;

    // A node is a real directional input FIFO. An edge records that its head
    // flit requests a neighboring output while that output has no credit.
    // Blocking assignments compute the exact transitive closure of this
    // cycle's live dependency graph.
    always @* begin
        for (i = 0; i < NNODES; i = i + 1) begin
            wait_edge[i] = {NNODES{1'b0}};
            reach[i] = {NNODES{1'b0}};
        end

        for (t = 0; t < NT; t = t + 1) begin
            for (d = 0; d < DIRS; d = d + 1) begin
                src = t * DIRS + d;
                if (input_occupied[t][d] &&
                    route_req[t][d * DIRS + NORTH] &&
                    no_credit[t][NORTH] && t >= X_TILES)
                    wait_edge[src][(t - X_TILES) * DIRS + SOUTH] = 1'b1;
                if (input_occupied[t][d] &&
                    route_req[t][d * DIRS + EAST] &&
                    no_credit[t][EAST] && (t % X_TILES) != X_TILES - 1)
                    wait_edge[src][(t + 1) * DIRS + WEST] = 1'b1;
                if (input_occupied[t][d] &&
                    route_req[t][d * DIRS + SOUTH] &&
                    no_credit[t][SOUTH] && t < NT - X_TILES)
                    wait_edge[src][(t + X_TILES) * DIRS + NORTH] = 1'b1;
                if (input_occupied[t][d] &&
                    route_req[t][d * DIRS + WEST] &&
                    no_credit[t][WEST] && (t % X_TILES) != 0)
                    wait_edge[src][(t - 1) * DIRS + EAST] = 1'b1;
            end
        end

        for (i = 0; i < NNODES; i = i + 1)
            reach[i] = wait_edge[i];
        for (k = 0; k < NNODES; k = k + 1)
            for (i = 0; i < NNODES; i = i + 1)
                if (reach[i][k])
                    reach[i] = reach[i] | reach[k];

        wait_edge_count = 6'd0;
        wait_cycle = 1'b0;
        wait_path2 = 1'b0;
        horizontal_wait = 1'b0;
        vertical_wait = 1'b0;
        for (i = 0; i < NNODES; i = i + 1) begin
            if (reach[i][i])
                wait_cycle = 1'b1;
            for (j = 0; j < NNODES; j = j + 1) begin
                if (wait_edge[i][j]) begin
                    wait_edge_count = wait_edge_count + 1'b1;
                    if ((i / DIRS) / X_TILES == (j / DIRS) / X_TILES)
                        horizontal_wait = 1'b1;
                    else
                        vertical_wait = 1'b1;
                    for (k = 0; k < NNODES; k = k + 1)
                        if (wait_edge[j][k])
                            wait_path2 = 1'b1;
                end
            end
        end
    end

    T_WAIT_GRAPH_ACYCLIC: assert property (@(posedge clk) disable iff (!reset_n)
        !wait_cycle);

    C_ALL_SOURCES_ACTIVE: cover property (@(posedge clk) disable iff (!reset_n)
        &src_active);
    C_WAIT_EDGE: cover property (@(posedge clk) disable iff (!reset_n)
        wait_edge_count >= 1);
    C_TWO_WAIT_EDGES: cover property (@(posedge clk) disable iff (!reset_n)
        wait_edge_count >= 2);
    C_TWO_HOP_WAIT: cover property (@(posedge clk) disable iff (!reset_n)
        wait_path2);
    C_XY_WAIT: cover property (@(posedge clk) disable iff (!reset_n)
        horizontal_wait && vertical_wait);
endmodule
