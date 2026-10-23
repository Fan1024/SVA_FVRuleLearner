// ---------------------------------------------------------------------------
// targets_openpiton_pmesh_waitcycle.sv
//
// Candidate TARGET assertions for the 3x3 OpenPiton P-Mesh wait-cycle task.
//
// Everything below is an INDEPENDENT oracle held in this file:
//
//   * nine shadow flit queues, one per source, written at the nine endpoint
//     injections and read at the one shared destination egress;
//   * an egress packet framer -- this file's own count of delivered flits
//     against the header's own length field. The framer is what makes the
//     flow tag readable at all: a header carries its tag at [21:18] and a
//     body flit at [23:20], so "which packet, which flit" has to be this
//     file's arithmetic before the tag can even be located;
//   * reference counters for injection, delivery, credit return and the
//     modelled sink buffer;
//   * saturating wait counters, which is how a fairness / bounded-response /
//     deadlock obligation is written as a SAFETY property.
//
// NOTHING here reads the package checker's wait graph. `wait_edge`, `reach`
// and `wait_cycle` are that checker's Floyd-Warshall closure of the same
// design state, and restating them would prove nothing. The deadlock family
// below argues acyclicity from the OTHER side: dimension-ordered routing in
// this workload emits no north request, no west request, no U-turn request
// and no request that would leave the mesh, so the wait-for relation has no
// backward edge to close a cycle with.
//
// No assumption is added anywhere. The package's single `A_FAIR_SINK`
// assumption lives in `sva/openpiton_pmesh_deadlock_checker.sv`.
//
// Workload, from the formal top: nine one-shot eight-flit packets, one per
// tile, all addressed to (2,2) = tile 8. Tile index = y*3+x, and XY routing
// makes every route monotone east-then-south, so exactly seventeen network
// input buffers can ever hold a flit:
//
//   the nine processor inputs, the west inputs of tiles 1,2,4,5,7,8, and the
//   north inputs of tiles 5 and 8.
//
// Flit layout (from the packet source in the formal top):
//   header  [63:50]=0 [49:42]=dstX=2 [41:34]=dstY=2 [33:30]=final=0
//           [29:22]=length=7 [21:18]=tag [17]=0 [16:0]=payload
//   body    [63:24]=0 [23:20]=tag [19]=tail [18:16]=body_left [15:0]=payload
//
// Reset. `reset_n && dut_ready` is the gate the task's own checker uses:
// `dynamic_node_top` registers `reset_in` once, so the fabric leaves its
// internal reset one cycle after `reset_n` rises and `dut_ready` is exactly
// that cycle of slack. Every oracle register here is reset by it and every
// assertion is disabled by it.
// ---------------------------------------------------------------------------

`define TWC_FT openpiton_pmesh_deadlock_ft
`define TWC_DN(y,x,n) `TWC_FT.dut.row[y].col[x].noc[n].u_router.dynamic_node_top

// One input port of one router: the flags every mesh-wide assertion reduces.
//   I     bit index                P   hierarchical path of the dynamic_input_top
//   DEPTH NIB element count        PW  pointer width
`define TWC_NIB_FLAGS(I, P, DEPTH, PW)                                        \
  assign nib_ne[I]        = (P.NIB.elements_in_array_f != 0);                 \
  assign nib_over[I]      = (P.NIB.elements_in_array_f > DEPTH);              \
  assign nib_ptr_bad[I]   = (P.NIB.elements_in_array_f[PW-1:0]                \
                             != (P.NIB.tail_ptr_f - P.NIB.head_ptr_f));       \
  assign nib_enq_full[I]  = (P.NIB.valid_in                                   \
                             && (P.NIB.elements_in_array_f == DEPTH));        \
  assign nib_deq_empty[I] = (P.NIB.thanks_in                                  \
                             && (P.NIB.elements_in_array_f == 0));            \
  assign rq_multi[I]      = !$onehot0({P.route_req_n_out, P.route_req_e_out,  \
                                       P.route_req_s_out, P.route_req_w_out,  \
                                       P.route_req_p_out});                   \
  assign th_multi[I]      = !$onehot0({P.thanks_n, P.thanks_e, P.thanks_s,    \
                                       P.thanks_w, P.thanks_p});              \
  assign grant_empty[I]   = ((P.thanks_n | P.thanks_e | P.thanks_s            \
                              | P.thanks_w | P.thanks_p)                      \
                             && (P.NIB.elements_in_array_f == 0));            \
  assign rq_back[I]       = (P.route_req_n_out | P.route_req_w_out);          \
  assign rq_offmesh[I]    = (P.route_req_e_out && (gx == 2))                  \
                          | (P.route_req_s_out && (gy == 2));

// One output port of one router.
`define TWC_OUT_FLAGS(I, P)                                                   \
  assign arb_enc_bad[I] = (P.control.current_route_f > 3'd4);                 \
  assign arb_idle[I]    = (P.control.planned_f == 1'b0)                       \
                          && (P.control.current_route_f == 3'd0);             \
  assign sp_bad[I]      = (P.space.count_f > 3'd4);                           \
  assign sp_full[I]     = (P.space.count_f == 3'd4);

module targets_openpiton_pmesh_waitcycle (input wire clk, input wire reset_n);

    // ---------------------------------------------------------- parameters
    localparam integer NFLOW = 9;
    localparam integer QD    = 16;    // shadow queue depth, per flow
    localparam integer NBUF  = 17;    // buffers a flit may legally occupy

    // The 42 header bits every injected header flit carries: chip 0,
    // dst (2,2), final route 0, length 7.
    localparam [41:0] HDR_CONST = {14'd0, 8'd2, 8'd2, 4'd0, 8'd7};

    // Bounds for the counter-encoded liveness families. Every one of these is
    // an ESTIMATE: nine eight-flit packets converging on one four-credit
    // egress buffer whose sink accepts at least once in every four-cycle
    // window, so the whole workload is 72 flits behind a drain of one per
    // four cycles.
    localparam integer FAIR_N       = 512;  // arbiter grant wait at a shared output
    localparam integer GRANT_N      = 384;  // destination-egress grant wait
    localparam integer DRAIN_N      = 8;    // egress buffer non-empty, no dequeue
    localparam integer CREDIT_N     = 512;  // source credit return
    localparam integer OPEN_N       = 128;  // header delivered -> tail delivered
    localparam integer PROGRESS_N   = 128;  // in flight, nothing delivered
    localparam integer MESHHOLD_N   = 512;  // a mesh buffer head held
    localparam integer ENDHOLD_N    = 768;  // an endpoint buffer head held
    localparam integer NOSPACE_N    = 32;   // an output without downstream credit

    // ------------------------------------------------- reset for the oracle
    wire rst_ok;
    assign rst_ok = reset_n && `TWC_FT.dut_ready;

    reg armed;
    always @(posedge clk) begin
        if (!rst_ok) armed <= 1'b0;
        else         armed <= 1'b1;
    end
    wire first_cycle;
    assign first_cycle = rst_ok && !armed;

    // ------------------------------------------------ boundary observations
    wire [8:0] inj;
    assign inj = `TWC_FT.src_send;

    wire [23:0] inj_key [0:NFLOW-1];
    wire [4:0]  c_src   [0:NFLOW-1];
    wire        crd     [0:NFLOW-1];
    genvar gs;
    generate
        for (gs = 0; gs < NFLOW; gs = gs + 1) begin : g_src_tap
            assign inj_key[gs] = `TWC_FT.src_flit[gs][23:0];
            assign c_src[gs]   = `TWC_FT.g_source[gs].u_credit.count_f;
            assign crd[gs]     = `TWC_FT.pThanks[gs][0];
        end
    endgenerate

    wire        dlv;
    wire [63:0] dlv_flit;
    assign dlv      = `TWC_FT.pOut_valid[8][0];
    assign dlv_flit = `TWC_FT.pOut_data[8][0];

    wire       deq;
    wire [2:0] sink_occ;
    assign deq      = `TWC_FT.sink_dequeue;
    assign sink_occ = `TWC_FT.sink_occupancy;

    // ------------------------- the seventeen buffers that can hold a flit
    wire [4:0] e_p [0:8];      // 16-deep endpoint buffers, one per tile
    wire [2:0] e_w [0:8];      // 4-deep west inputs (only 1,2,4,5,7,8 used)
    wire [2:0] e_n [0:8];      // 4-deep north inputs (only 5 and 8 used)
    wire [63:0] h_p [0:8];
    wire [63:0] h_w [0:8];
    wire [63:0] h_n [0:8];
    wire        hp_p [0:8];    // head present and not being dequeued
    wire        hp_w [0:8];
    wire        hp_n [0:8];
    wire [3:0]  tg_w [0:8];    // the head flit's flow tag, header or body
    wire [3:0]  tg_n [0:8];

    genvar gby, gbx;
    generate
        for (gby = 0; gby < 3; gby = gby + 1) begin : g_by
            for (gbx = 0; gbx < 3; gbx = gbx + 1) begin : g_bx
                localparam integer T = gby*3 + gbx;
                assign e_p[T]  = `TWC_DN(gby,gbx,0).proc_input.NIB.elements_in_array_f;
                assign e_w[T]  = `TWC_DN(gby,gbx,0).west_input.NIB.elements_in_array_f;
                assign e_n[T]  = `TWC_DN(gby,gbx,0).north_input.NIB.elements_in_array_f;
                assign h_p[T]  = `TWC_DN(gby,gbx,0).proc_input.data_out;
                assign h_w[T]  = `TWC_DN(gby,gbx,0).west_input.data_out;
                assign h_n[T]  = `TWC_DN(gby,gbx,0).north_input.data_out;
                assign hp_p[T] = (e_p[T] != 0)
                                 && !`TWC_DN(gby,gbx,0).proc_input.thanks_all_temp;
                assign hp_w[T] = (e_w[T] != 0)
                                 && !`TWC_DN(gby,gbx,0).west_input.thanks_all_temp;
                assign hp_n[T] = (e_n[T] != 0)
                                 && !`TWC_DN(gby,gbx,0).north_input.thanks_all_temp;
                // a header carries its tag at [21:18], a body flit at [23:20]
                assign tg_w[T] = (h_w[T][63:22] == HDR_CONST) ? h_w[T][21:18]
                                                              : h_w[T][23:20];
                assign tg_n[T] = (h_n[T][63:22] == HDR_CONST) ? h_n[T][21:18]
                                                              : h_n[T][23:20];
            end
        end
    endgenerate

    wire [9:0] buffered_total;
    assign buffered_total =
          {5'd0, e_p[0]} + {5'd0, e_p[1]} + {5'd0, e_p[2]}
        + {5'd0, e_p[3]} + {5'd0, e_p[4]} + {5'd0, e_p[5]}
        + {5'd0, e_p[6]} + {5'd0, e_p[7]} + {5'd0, e_p[8]}
        + {7'd0, e_w[1]} + {7'd0, e_w[2]} + {7'd0, e_w[4]}
        + {7'd0, e_w[5]} + {7'd0, e_w[7]} + {7'd0, e_w[8]}
        + {7'd0, e_n[5]} + {7'd0, e_n[8]};

    // -------------------------------------- taps at the two contended nodes
    // tile 5 (2,1) south output: flows 0/1/2 from the north, 3/4 from the
    // west, 5 from the endpoint. tile 8 (2,2) proc output: flows 0..5 from
    // the north, 6/7 from the west, 8 from the endpoint.
    wire rq_t5s_n, rq_t5s_w, rq_t5s_p, th_t5s_n, th_t5s_w, th_t5s_p;
    wire rq_t8p_n, rq_t8p_w, rq_t8p_p, th_t8p_n, th_t8p_w, th_t8p_p;
    wire rq_t2s_w, rq_t2s_p, th_t2s_w, th_t2s_p;
    assign rq_t5s_n = `TWC_DN(1,2,0).route_req_n_to_s;
    assign rq_t5s_w = `TWC_DN(1,2,0).route_req_w_to_s;
    assign rq_t5s_p = `TWC_DN(1,2,0).route_req_p_to_s;
    assign th_t5s_n = `TWC_DN(1,2,0).thanks_s_to_n;
    assign th_t5s_w = `TWC_DN(1,2,0).thanks_s_to_w;
    assign th_t5s_p = `TWC_DN(1,2,0).thanks_s_to_p;
    assign rq_t8p_n = `TWC_DN(2,2,0).route_req_n_to_p;
    assign rq_t8p_w = `TWC_DN(2,2,0).route_req_w_to_p;
    assign rq_t8p_p = `TWC_DN(2,2,0).route_req_p_to_p;
    assign th_t8p_n = `TWC_DN(2,2,0).thanks_p_to_n;
    assign th_t8p_w = `TWC_DN(2,2,0).thanks_p_to_w;
    assign th_t8p_p = `TWC_DN(2,2,0).thanks_p_to_p;
    assign rq_t2s_w = `TWC_DN(0,2,0).route_req_w_to_s;
    assign rq_t2s_p = `TWC_DN(0,2,0).route_req_p_to_s;
    assign th_t2s_w = `TWC_DN(0,2,0).thanks_s_to_w;
    assign th_t2s_p = `TWC_DN(0,2,0).thanks_s_to_p;

    // the destination processor output: lock, crossbar select, credit
    wire       dst_planned;
    wire [2:0] dst_route;
    wire       dst_space;
    assign dst_planned = `TWC_DN(2,2,0).proc_output.control.planned_f;
    assign dst_route   = `TWC_DN(2,2,0).proc_output.control.current_route_f;
    assign dst_space   = `TWC_DN(2,2,0).proc_output.space_avail_connection;

    // the eight loaded links, sender valid against receiver occupancy
    wire link_overfill;
    assign link_overfill =
          (`TWC_FT.dut.v_E[0][0] && (e_w[1] > 3'd3))
        | (`TWC_FT.dut.v_E[1][0] && (e_w[2] > 3'd3))
        | (`TWC_FT.dut.v_E[3][0] && (e_w[4] > 3'd3))
        | (`TWC_FT.dut.v_E[4][0] && (e_w[5] > 3'd3))
        | (`TWC_FT.dut.v_E[6][0] && (e_w[7] > 3'd3))
        | (`TWC_FT.dut.v_E[7][0] && (e_w[8] > 3'd3))
        | (`TWC_FT.dut.v_S[2][0] && (e_n[5] > 3'd3))
        | (`TWC_FT.dut.v_S[5][0] && (e_n[8] > 3'd3));

    // ------------------------------------------------ mesh-wide flag vectors
    // 27 routers x 5 input ports, and 27 routers x 5 output ports.
    wire [134:0] nib_ne, nib_over, nib_ptr_bad, nib_enq_full, nib_deq_empty;
    wire [134:0] rq_multi, th_multi, grant_empty, rq_back, rq_offmesh;
    wire [134:0] offpath_ne;
    wire [134:0] arb_enc_bad, arb_idle, sp_bad, sp_full;
    wire [26:0]  pv_bad, loc_bad, uturn;

    genvar gy, gx, gn;
    generate
      for (gy = 0; gy < 3; gy = gy + 1) begin : g_row
        for (gx = 0; gx < 3; gx = gx + 1) begin : g_col
          for (gn = 0; gn < 3; gn = gn + 1) begin : g_noc
            localparam integer R = (gy*3 + gx)*3 + gn;   // router ordinal
            localparam integer B = R * 5;                // first flag bit

            `TWC_NIB_FLAGS(B+0, `TWC_DN(gy,gx,gn).north_input, 4,  2)
            `TWC_NIB_FLAGS(B+1, `TWC_DN(gy,gx,gn).east_input,  4,  2)
            `TWC_NIB_FLAGS(B+2, `TWC_DN(gy,gx,gn).south_input, 4,  2)
            `TWC_NIB_FLAGS(B+3, `TWC_DN(gy,gx,gn).west_input,  4,  2)
            `TWC_NIB_FLAGS(B+4, `TWC_DN(gy,gx,gn).proc_input, 16,  4)

            `TWC_OUT_FLAGS(B+0, `TWC_DN(gy,gx,gn).north_output)
            `TWC_OUT_FLAGS(B+1, `TWC_DN(gy,gx,gn).east_output)
            `TWC_OUT_FLAGS(B+2, `TWC_DN(gy,gx,gn).south_output)
            `TWC_OUT_FLAGS(B+3, `TWC_DN(gy,gx,gn).west_output)
            `TWC_OUT_FLAGS(B+4, `TWC_DN(gy,gx,gn).proc_output)

            // the seventeen buffers a flit may legally occupy
            localparam integer ON_N = ((gn == 0) && (gx == 2)
                                       && (gy >= 1)) ? 1 : 0;
            localparam integer ON_W = ((gn == 0) && (gx >= 1)) ? 1 : 0;
            localparam integer ON_P = (gn == 0) ? 1 : 0;
            assign offpath_ne[B+0] = ON_N ? 1'b0 : nib_ne[B+0];
            assign offpath_ne[B+1] = nib_ne[B+1];
            assign offpath_ne[B+2] = nib_ne[B+2];
            assign offpath_ne[B+3] = ON_W ? 1'b0 : nib_ne[B+3];
            assign offpath_ne[B+4] = ON_P ? 1'b0 : nib_ne[B+4];

            // no egress anywhere but the one destination endpoint
            assign pv_bad[R] = ((gy == 2) && (gx == 2) && (gn == 0))
                               ? 1'b0 : `TWC_FT.pOut_valid[gy*3 + gx][gn];

            // a router must have latched its own coordinates before any flit
            // in it is routed
            assign loc_bad[R] = (nib_ne[B+0] | nib_ne[B+1] | nib_ne[B+2]
                                 | nib_ne[B+3] | nib_ne[B+4])
                                && ((`TWC_DN(gy,gx,gn).myLocX_f != gx)
                                 || (`TWC_DN(gy,gx,gn).myLocY_f != gy));

            // a mesh input never asks for the output it arrived on. The
            // processor port is excluded: flow 8 is injected at the
            // destination tile and legitimately routes proc-to-proc.
            assign uturn[R] = `TWC_DN(gy,gx,gn).route_req_n_to_n
                            | `TWC_DN(gy,gx,gn).route_req_e_to_e
                            | `TWC_DN(gy,gx,gn).route_req_s_to_s
                            | `TWC_DN(gy,gx,gn).route_req_w_to_w;
          end
        end
      end
    endgenerate

    // ================================================================ ORACLE
    // Nine shadow flit queues, one per source, written at injection and read
    // at the shared egress. Only the 24 flit bits that differ between flits
    // are shadowed; the 40 or 42 constant bits above them are checked by the
    // framer assertions instead.
    reg [23:0] q_mem [0:NFLOW-1][0:QD-1];
    reg [3:0]  q_wr  [0:NFLOW-1];
    reg [3:0]  q_rd  [0:NFLOW-1];
    reg [7:0]  q_cnt [0:NFLOW-1];

    reg [7:0]  inj_cnt [0:NFLOW-1];
    reg [7:0]  dlv_cnt [0:NFLOW-1];
    reg [7:0]  crd_cnt [0:NFLOW-1];
    reg [9:0]  in_flight;
    reg [9:0]  egr_cnt;
    reg [9:0]  deq_cnt;

    // registered copies of the nine endpoint occupancies, so the credit
    // account can be stated without $past
    reg [4:0] e_p_d [0:NFLOW-1];

    // the egress packet framer
    reg        eg_open;
    reg [3:0]  eg_flow;
    reg [3:0]  eg_pos;      // flits of the open packet already delivered
    reg [2:0]  eg_route;    // the crossbar select the header was granted on

    wire [3:0] eg_expect_left;
    assign eg_expect_left = 4'd8 - eg_pos;

    // which flow the delivered flit belongs to, and whether that is legal
    wire [3:0] dlv_flow_raw;
    wire [3:0] dlv_flow;
    assign dlv_flow_raw = eg_open ? eg_flow : dlv_flit[21:18];
    assign dlv_flow     = (dlv_flow_raw > 4'd8) ? 4'd0 : dlv_flow_raw;

    wire [8:0] pop;
    genvar gp;
    generate
        for (gp = 0; gp < NFLOW; gp = gp + 1) begin : g_pop
            assign pop[gp] = dlv && (dlv_flow_raw == gp);
        end
    endgenerate

    // saturating wait counters -- the bounded-safety encoding of fairness,
    // bounded response and deadlock freedom
    reg [11:0] w_t5s_n, w_t5s_w, w_t5s_p;
    reg [11:0] w_t8p_n, w_t8p_w;
    reg [11:0] w_grant, w_drain, w_open, w_progress, w_nospace;
    reg [11:0] w_credit [0:NFLOW-1];
    reg [11:0] w_endhead [0:8];       // the nine endpoint buffers
    reg [11:0] w_meshhead [0:7];      // the eight mesh buffers

    wire [7:0] mesh_pending;
    assign mesh_pending[0] = hp_w[1];
    assign mesh_pending[1] = hp_w[2];
    assign mesh_pending[2] = hp_w[4];
    assign mesh_pending[3] = hp_w[5];
    assign mesh_pending[4] = hp_w[7];
    assign mesh_pending[5] = hp_w[8];
    assign mesh_pending[6] = hp_n[5];
    assign mesh_pending[7] = hp_n[8];

    wire dst_req_pending;
    assign dst_req_pending = (rq_t8p_n && !th_t8p_n)
                          || (rq_t8p_w && !th_t8p_w)
                          || (rq_t8p_p && !th_t8p_p);

    wire [3:0] inj_now;
    assign inj_now = {3'd0, inj[0]} + {3'd0, inj[1]} + {3'd0, inj[2]}
                   + {3'd0, inj[3]} + {3'd0, inj[4]} + {3'd0, inj[5]}
                   + {3'd0, inj[6]} + {3'd0, inj[7]} + {3'd0, inj[8]};

    integer f, b;
    always @(posedge clk) begin
        if (!rst_ok) begin
            for (f = 0; f < NFLOW; f = f + 1) begin
                q_wr[f]      <= 4'd0;
                q_rd[f]      <= 4'd0;
                q_cnt[f]     <= 8'd0;
                inj_cnt[f]   <= 8'd0;
                dlv_cnt[f]   <= 8'd0;
                crd_cnt[f]   <= 8'd0;
                e_p_d[f]     <= 5'd0;
                w_credit[f]  <= 12'd0;
                w_endhead[f] <= 12'd0;
            end
            for (b = 0; b < 8; b = b + 1) w_meshhead[b] <= 12'd0;
            in_flight  <= 10'd0;
            egr_cnt    <= 10'd0;
            deq_cnt    <= 10'd0;
            eg_open    <= 1'b0;
            eg_flow    <= 4'd0;
            eg_pos     <= 4'd0;
            eg_route   <= 3'd0;
            w_t5s_n    <= 12'd0;
            w_t5s_w    <= 12'd0;
            w_t5s_p    <= 12'd0;
            w_t8p_n    <= 12'd0;
            w_t8p_w    <= 12'd0;
            w_grant    <= 12'd0;
            w_drain    <= 12'd0;
            w_open     <= 12'd0;
            w_progress <= 12'd0;
            w_nospace  <= 12'd0;
        end else begin
            for (f = 0; f < NFLOW; f = f + 1) begin
                if (inj[f]) begin
                    q_mem[f][q_wr[f]] <= inj_key[f];
                    q_wr[f] <= (q_wr[f] == QD-1) ? 4'd0 : q_wr[f] + 4'd1;
                    if (inj_cnt[f] != 8'hFF) inj_cnt[f] <= inj_cnt[f] + 8'd1;
                end
                if (pop[f]) begin
                    q_rd[f] <= (q_rd[f] == QD-1) ? 4'd0 : q_rd[f] + 4'd1;
                    if (dlv_cnt[f] != 8'hFF) dlv_cnt[f] <= dlv_cnt[f] + 8'd1;
                end
                case ({inj[f], pop[f]})
                    2'b10:   q_cnt[f] <= q_cnt[f] + 8'd1;
                    2'b01:   q_cnt[f] <= q_cnt[f] - 8'd1;
                    default: begin end
                endcase
                if (crd[f] && (crd_cnt[f] != 8'hFF))
                    crd_cnt[f] <= crd_cnt[f] + 8'd1;

                e_p_d[f] <= e_p[f];

                w_credit[f] <= (!((e_p[f] != 0) && !crd[f])) ? 12'd0
                               : (w_credit[f] == 12'hFFF) ? w_credit[f]
                                                          : w_credit[f] + 12'd1;
                w_endhead[f] <= (!hp_p[f]) ? 12'd0
                                : (w_endhead[f] == 12'hFFF) ? w_endhead[f]
                                                            : w_endhead[f] + 12'd1;
            end

            for (b = 0; b < 8; b = b + 1)
                w_meshhead[b] <= (!mesh_pending[b]) ? 12'd0
                                 : (w_meshhead[b] == 12'hFFF) ? w_meshhead[b]
                                                              : w_meshhead[b] + 12'd1;

            in_flight <= in_flight + {6'd0, inj_now} - {9'd0, dlv};
            if (dlv && (egr_cnt != 10'h3FF)) egr_cnt <= egr_cnt + 10'd1;
            if (deq && (deq_cnt != 10'h3FF)) deq_cnt <= deq_cnt + 10'd1;

            // packet framing at the egress
            if (dlv) begin
                if (!eg_open) begin
                    eg_open  <= 1'b1;
                    eg_flow  <= dlv_flit[21:18];
                    eg_pos   <= 4'd1;
                    eg_route <= dst_route;
                end else if (eg_pos == 4'd7) begin
                    eg_open <= 1'b0;
                    eg_pos  <= 4'd0;
                end else begin
                    eg_pos <= eg_pos + 4'd1;
                end
            end

            w_t5s_n <= (!(rq_t5s_n && !th_t5s_n)) ? 12'd0
                       : (w_t5s_n == 12'hFFF) ? w_t5s_n : w_t5s_n + 12'd1;
            w_t5s_w <= (!(rq_t5s_w && !th_t5s_w)) ? 12'd0
                       : (w_t5s_w == 12'hFFF) ? w_t5s_w : w_t5s_w + 12'd1;
            w_t5s_p <= (!(rq_t5s_p && !th_t5s_p)) ? 12'd0
                       : (w_t5s_p == 12'hFFF) ? w_t5s_p : w_t5s_p + 12'd1;
            w_t8p_n <= (!(rq_t8p_n && !th_t8p_n)) ? 12'd0
                       : (w_t8p_n == 12'hFFF) ? w_t8p_n : w_t8p_n + 12'd1;
            w_t8p_w <= (!(rq_t8p_w && !th_t8p_w)) ? 12'd0
                       : (w_t8p_w == 12'hFFF) ? w_t8p_w : w_t8p_w + 12'd1;

            w_grant <= (!dst_req_pending) ? 12'd0
                       : (w_grant == 12'hFFF) ? w_grant : w_grant + 12'd1;
            w_drain <= (!((sink_occ != 0) && !deq)) ? 12'd0
                       : (w_drain == 12'hFFF) ? w_drain : w_drain + 12'd1;
            w_open <= (!(eg_open && !dlv)) ? 12'd0
                       : (w_open == 12'hFFF) ? w_open : w_open + 12'd1;
            w_progress <= (!((in_flight != 0) && !dlv)) ? 12'd0
                       : (w_progress == 12'hFFF) ? w_progress
                                                 : w_progress + 12'd1;
            w_nospace <= (dst_space) ? 12'd0
                       : (w_nospace == 12'hFFF) ? w_nospace : w_nospace + 12'd1;
        end
    end

    // convenience: the flit key the oracle expects next for each flow
    wire [23:0] expect_key [0:NFLOW-1];
    genvar ge;
    generate
        for (ge = 0; ge < NFLOW; ge = ge + 1) begin : g_expect
            assign expect_key[ge] = q_mem[ge][q_rd[ge]];
        end
    endgenerate

    wire all_flows_fifo_ok;
    assign all_flows_fifo_ok =
        ((!pop[0]) || ((q_cnt[0] != 0) && (dlv_flit[23:0] == expect_key[0]))) &&
        ((!pop[1]) || ((q_cnt[1] != 0) && (dlv_flit[23:0] == expect_key[1]))) &&
        ((!pop[2]) || ((q_cnt[2] != 0) && (dlv_flit[23:0] == expect_key[2]))) &&
        ((!pop[3]) || ((q_cnt[3] != 0) && (dlv_flit[23:0] == expect_key[3]))) &&
        ((!pop[4]) || ((q_cnt[4] != 0) && (dlv_flit[23:0] == expect_key[4]))) &&
        ((!pop[5]) || ((q_cnt[5] != 0) && (dlv_flit[23:0] == expect_key[5]))) &&
        ((!pop[6]) || ((q_cnt[6] != 0) && (dlv_flit[23:0] == expect_key[6]))) &&
        ((!pop[7]) || ((q_cnt[7] != 0) && (dlv_flit[23:0] == expect_key[7]))) &&
        ((!pop[8]) || ((q_cnt[8] != 0) && (dlv_flit[23:0] == expect_key[8])));

    wire delivery_le_injection_ok;
    assign delivery_le_injection_ok =
        (dlv_cnt[0] <= inj_cnt[0]) && (dlv_cnt[1] <= inj_cnt[1]) &&
        (dlv_cnt[2] <= inj_cnt[2]) && (dlv_cnt[3] <= inj_cnt[3]) &&
        (dlv_cnt[4] <= inj_cnt[4]) && (dlv_cnt[5] <= inj_cnt[5]) &&
        (dlv_cnt[6] <= inj_cnt[6]) && (dlv_cnt[7] <= inj_cnt[7]) &&
        (dlv_cnt[8] <= inj_cnt[8]);

    wire credit_le_injection_ok;
    assign credit_le_injection_ok =
        (crd_cnt[0] <= inj_cnt[0]) && (crd_cnt[1] <= inj_cnt[1]) &&
        (crd_cnt[2] <= inj_cnt[2]) && (crd_cnt[3] <= inj_cnt[3]) &&
        (crd_cnt[4] <= inj_cnt[4]) && (crd_cnt[5] <= inj_cnt[5]) &&
        (crd_cnt[6] <= inj_cnt[6]) && (crd_cnt[7] <= inj_cnt[7]) &&
        (crd_cnt[8] <= inj_cnt[8]);

    wire credit_only_on_dequeue_ok;
    assign credit_only_on_dequeue_ok =
        ((!crd[0]) || (e_p[0] != 0)) && ((!crd[1]) || (e_p[1] != 0)) &&
        ((!crd[2]) || (e_p[2] != 0)) && ((!crd[3]) || (e_p[3] != 0)) &&
        ((!crd[4]) || (e_p[4] != 0)) && ((!crd[5]) || (e_p[5] != 0)) &&
        ((!crd[6]) || (e_p[6] != 0)) && ((!crd[7]) || (e_p[7] != 0)) &&
        ((!crd[8]) || (e_p[8] != 0));

    wire source_credit_account_ok;
    assign source_credit_account_ok =
        (c_src[0] == (5'd16 - e_p_d[0])) && (c_src[1] == (5'd16 - e_p_d[1])) &&
        (c_src[2] == (5'd16 - e_p_d[2])) && (c_src[3] == (5'd16 - e_p_d[3])) &&
        (c_src[4] == (5'd16 - e_p_d[4])) && (c_src[5] == (5'd16 - e_p_d[5])) &&
        (c_src[6] == (5'd16 - e_p_d[6])) && (c_src[7] == (5'd16 - e_p_d[7])) &&
        (c_src[8] == (5'd16 - e_p_d[8]));

    wire source_credit_full_ok;
    assign source_credit_full_ok =
        (c_src[0] == 5'd16) && (c_src[1] == 5'd16) && (c_src[2] == 5'd16) &&
        (c_src[3] == 5'd16) && (c_src[4] == 5'd16) && (c_src[5] == 5'd16) &&
        (c_src[6] == 5'd16) && (c_src[7] == 5'd16) && (c_src[8] == 5'd16);

    wire credit_return_bounded_ok;
    assign credit_return_bounded_ok =
        (w_credit[0] <= CREDIT_N) && (w_credit[1] <= CREDIT_N) &&
        (w_credit[2] <= CREDIT_N) && (w_credit[3] <= CREDIT_N) &&
        (w_credit[4] <= CREDIT_N) && (w_credit[5] <= CREDIT_N) &&
        (w_credit[6] <= CREDIT_N) && (w_credit[7] <= CREDIT_N) &&
        (w_credit[8] <= CREDIT_N);

    wire endpoint_head_bounded_ok;
    assign endpoint_head_bounded_ok =
        (w_endhead[0] <= ENDHOLD_N) && (w_endhead[1] <= ENDHOLD_N) &&
        (w_endhead[2] <= ENDHOLD_N) && (w_endhead[3] <= ENDHOLD_N) &&
        (w_endhead[4] <= ENDHOLD_N) && (w_endhead[5] <= ENDHOLD_N) &&
        (w_endhead[6] <= ENDHOLD_N) && (w_endhead[7] <= ENDHOLD_N) &&
        (w_endhead[8] <= ENDHOLD_N);

    wire mesh_head_bounded_ok;
    assign mesh_head_bounded_ok =
        (w_meshhead[0] <= MESHHOLD_N) && (w_meshhead[1] <= MESHHOLD_N) &&
        (w_meshhead[2] <= MESHHOLD_N) && (w_meshhead[3] <= MESHHOLD_N) &&
        (w_meshhead[4] <= MESHHOLD_N) && (w_meshhead[5] <= MESHHOLD_N) &&
        (w_meshhead[6] <= MESHHOLD_N) && (w_meshhead[7] <= MESHHOLD_N);

    // every on-path buffer's head flit is either a well-formed header or a
    // well-formed body flit of this workload's one packet shape
    wire path_head_shape_ok;
    assign path_head_shape_ok =
        ((e_p[0] == 0) || (h_p[0][63:22] == HDR_CONST) || (h_p[0][63:24] == 40'd0)) &&
        ((e_p[1] == 0) || (h_p[1][63:22] == HDR_CONST) || (h_p[1][63:24] == 40'd0)) &&
        ((e_p[2] == 0) || (h_p[2][63:22] == HDR_CONST) || (h_p[2][63:24] == 40'd0)) &&
        ((e_p[3] == 0) || (h_p[3][63:22] == HDR_CONST) || (h_p[3][63:24] == 40'd0)) &&
        ((e_p[4] == 0) || (h_p[4][63:22] == HDR_CONST) || (h_p[4][63:24] == 40'd0)) &&
        ((e_p[5] == 0) || (h_p[5][63:22] == HDR_CONST) || (h_p[5][63:24] == 40'd0)) &&
        ((e_p[6] == 0) || (h_p[6][63:22] == HDR_CONST) || (h_p[6][63:24] == 40'd0)) &&
        ((e_p[7] == 0) || (h_p[7][63:22] == HDR_CONST) || (h_p[7][63:24] == 40'd0)) &&
        ((e_p[8] == 0) || (h_p[8][63:22] == HDR_CONST) || (h_p[8][63:24] == 40'd0)) &&
        ((e_w[1] == 0) || (h_w[1][63:22] == HDR_CONST) || (h_w[1][63:24] == 40'd0)) &&
        ((e_w[2] == 0) || (h_w[2][63:22] == HDR_CONST) || (h_w[2][63:24] == 40'd0)) &&
        ((e_w[4] == 0) || (h_w[4][63:22] == HDR_CONST) || (h_w[4][63:24] == 40'd0)) &&
        ((e_w[5] == 0) || (h_w[5][63:22] == HDR_CONST) || (h_w[5][63:24] == 40'd0)) &&
        ((e_w[7] == 0) || (h_w[7][63:22] == HDR_CONST) || (h_w[7][63:24] == 40'd0)) &&
        ((e_w[8] == 0) || (h_w[8][63:22] == HDR_CONST) || (h_w[8][63:24] == 40'd0)) &&
        ((e_n[5] == 0) || (h_n[5][63:22] == HDR_CONST) || (h_n[5][63:24] == 40'd0)) &&
        ((e_n[8] == 0) || (h_n[8][63:22] == HDR_CONST) || (h_n[8][63:24] == 40'd0));

    // the only flows that can reach each mesh buffer, from the XY routes
    wire path_head_tag_ok;
    assign path_head_tag_ok =
        ((e_w[1] == 0) || (tg_w[1] == 4'd0)) &&
        ((e_w[2] == 0) || (tg_w[2] <= 4'd1)) &&
        ((e_w[4] == 0) || (tg_w[4] == 4'd3)) &&
        ((e_w[5] == 0) || (tg_w[5] == 4'd3) || (tg_w[5] == 4'd4)) &&
        ((e_w[7] == 0) || (tg_w[7] == 4'd6)) &&
        ((e_w[8] == 0) || (tg_w[8] == 4'd6) || (tg_w[8] == 4'd7)) &&
        ((e_n[5] == 0) || (tg_n[5] <= 4'd2)) &&
        ((e_n[8] == 0) || (tg_n[8] <= 4'd5));

    // =============================================================== TARGETS
    // ------------------------------------------------------------------
    // 1 -- end-to-end ordering
    // ------------------------------------------------------------------

    T_ORDER_FLOW0_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        pop[0] |-> ((q_cnt[0] != 0) && (dlv_flit[23:0] == expect_key[0])));

    T_ORDER_FLOW2_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        pop[2] |-> ((q_cnt[2] != 0) && (dlv_flit[23:0] == expect_key[2])));

    T_ORDER_ALL_FLOWS_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        all_flows_fifo_ok);

    // wormhole: once a packet is open at the shared egress no other flow's
    // flit may pass until its tail has
    T_ORDER_EGRESS_NO_INTERLEAVE: assert property (@(posedge clk) disable iff (!rst_ok)
        (dlv && eg_open) |-> (dlv_flit[23:20] == eg_flow));

    // ------------------------------------------------------------------
    // 2 -- data integrity
    // ------------------------------------------------------------------

    T_DATA_EGRESS_HEADER_FIELDS: assert property (@(posedge clk) disable iff (!rst_ok)
        (dlv && !eg_open) |-> ((dlv_flit[63:22] == HDR_CONST)
                               && (dlv_flit[17] == 1'b0)
                               && (dlv_flit[21:18] <= 4'd8)));

    T_DATA_EGRESS_BODY_INDEX: assert property (@(posedge clk) disable iff (!rst_ok)
        (dlv && eg_open) |-> ((dlv_flit[63:24] == 40'd0)
                              && ({1'b0, dlv_flit[18:16]} == eg_expect_left)
                              && (dlv_flit[19] == (eg_pos == 4'd7))));

    T_DATA_PATH_HEAD_SHAPE: assert property (@(posedge clk) disable iff (!rst_ok)
        path_head_shape_ok);

    // the XY routes decide which flow can be sitting in which mesh buffer
    T_DATA_PATH_HEAD_TAG_LEGAL: assert property (@(posedge clk) disable iff (!rst_ok)
        path_head_tag_ok);

    // ------------------------------------------------------------------
    // 3 -- uniqueness / no duplication
    // ------------------------------------------------------------------

    T_UNIQ_DELIVERY_LE_INJECTION: assert property (@(posedge clk) disable iff (!rst_ok)
        delivery_le_injection_ok);

    T_UNIQ_NO_DELIVERY_WITHOUT_QUEUED: assert property (@(posedge clk) disable iff (!rst_ok)
        dlv |-> ((q_cnt[dlv_flow] != 0) && (in_flight != 0)
                 && (dlv_flow_raw <= 4'd8)));

    // ------------------------------------------------------------------
    // 4 -- no loss / conservation
    // ------------------------------------------------------------------

    T_CONSERVE_INFLIGHT_EQUALS_BUFFERED: assert property (@(posedge clk) disable iff (!rst_ok)
        in_flight == buffered_total);

    T_CONSERVE_NO_TRAFFIC_OFF_PATH: assert property (@(posedge clk) disable iff (!rst_ok)
        offpath_ne == 135'd0);

    T_CONSERVE_NO_STRAY_EGRESS: assert property (@(posedge clk) disable iff (!rst_ok)
        pv_bad == 27'd0);

    T_CONSERVE_SINK_ACCOUNT: assert property (@(posedge clk) disable iff (!rst_ok)
        {7'd0, sink_occ} == (egr_cnt - deq_cnt));

    T_CONSERVE_SOURCE_CREDIT_ACCOUNT: assert property (@(posedge clk) disable iff (!rst_ok)
        source_credit_account_ok);

    // ------------------------------------------------------------------
    // 5 -- mutual exclusion / one-hot
    // ------------------------------------------------------------------

    T_MUTEX_ROUTE_REQ_ONEHOT_MESH: assert property (@(posedge clk) disable iff (!rst_ok)
        rq_multi == 135'd0);

    // two output ports must never consume the same buffer entry in one cycle
    T_MUTEX_THANKS_ONEHOT_MESH: assert property (@(posedge clk) disable iff (!rst_ok)
        th_multi == 135'd0);

    // ------------------------------------------------------------------
    // 6 -- occupancy and bounds
    // ------------------------------------------------------------------

    T_BOUND_MESH_NIB_DEPTH: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_over == 135'd0);

    T_BOUND_NIB_POINTER_CONSISTENT: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_ptr_bad == 135'd0);

    T_BOUND_OUTPUT_CREDIT_RANGE: assert property (@(posedge clk) disable iff (!rst_ok)
        sp_bad == 135'd0);

    T_BOUND_SINK_OCCUPANCY: assert property (@(posedge clk) disable iff (!rst_ok)
        sink_occ <= 3'd4);

    T_BOUND_INFLIGHT_TOTAL: assert property (@(posedge clk) disable iff (!rst_ok)
        in_flight <= 10'd200);

    // ------------------------------------------------------------------
    // 7 -- allocator discipline (the NIB slot is the allocated resource)
    // ------------------------------------------------------------------

    T_ALLOC_NO_ENQUEUE_WHEN_FULL: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_enq_full == 135'd0);

    T_ALLOC_NO_DEQUEUE_WHEN_EMPTY: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_deq_empty == 135'd0);

    // ------------------------------------------------------------------
    // 8 -- request-response correspondence
    // ------------------------------------------------------------------

    T_REQRSP_CREDIT_LE_INJECTION: assert property (@(posedge clk) disable iff (!rst_ok)
        credit_le_injection_ok);

    T_REQRSP_CREDIT_ONLY_ON_DEQUEUE: assert property (@(posedge clk) disable iff (!rst_ok)
        credit_only_on_dequeue_ok);

    // ------------------------------------------------------------------
    // 9 -- protocol conformance
    // ------------------------------------------------------------------

    T_PROTO_NO_GRANT_OF_EMPTY_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        grant_empty == 135'd0);

    // credit-based flow control: a sender never drives valid at a buffer with
    // no free slot
    T_PROTO_NO_SEND_WITHOUT_SPACE: assert property (@(posedge clk) disable iff (!rst_ok)
        !link_overfill);

    T_PROTO_EGRESS_MATCHES_GRANTED_HEAD: assert property (@(posedge clk) disable iff (!rst_ok)
        dlv |-> ((th_t8p_n && (dlv_flit == h_n[8]) && (e_n[8] != 0)) ||
                 (th_t8p_w && (dlv_flit == h_w[8]) && (e_w[8] != 0)) ||
                 (th_t8p_p && (dlv_flit == h_p[8]) && (e_p[8] != 0))));

    // ------------------------------------------------------------------
    // 10 -- arbitration fairness (bounded wait, not liveness)
    // ------------------------------------------------------------------

    T_FAIR_T5_SOUTH_NORTH_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_n <= FAIR_N);

    T_FAIR_T5_SOUTH_WEST_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_w <= FAIR_N);

    T_FAIR_T5_SOUTH_PROC_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_p <= FAIR_N);

    T_FAIR_DST_EGRESS_NORTH_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t8p_n <= FAIR_N);

    T_FAIR_DST_EGRESS_WEST_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t8p_w <= FAIR_N);

    // ------------------------------------------------------------------
    // 11 -- bounded response
    // ------------------------------------------------------------------

    T_RESPONSE_DST_GRANT_LATENCY: assert property (@(posedge clk) disable iff (!rst_ok)
        w_grant <= GRANT_N);

    T_RESPONSE_EGRESS_DRAIN: assert property (@(posedge clk) disable iff (!rst_ok)
        w_drain <= DRAIN_N);

    T_RESPONSE_SOURCE_CREDIT_RETURN: assert property (@(posedge clk) disable iff (!rst_ok)
        credit_return_bounded_ok);

    T_RESPONSE_HEADER_TO_TAIL: assert property (@(posedge clk) disable iff (!rst_ok)
        w_open <= OPEN_N);

    // ------------------------------------------------------------------
    // 12 -- deadlock freedom (bounded progress, and the routing argument)
    // ------------------------------------------------------------------

    T_DEADLOCK_GLOBAL_PROGRESS: assert property (@(posedge clk) disable iff (!rst_ok)
        w_progress <= PROGRESS_N);

    T_DEADLOCK_NO_STALLED_MESH_BUFFER: assert property (@(posedge clk) disable iff (!rst_ok)
        mesh_head_bounded_ok);

    T_DEADLOCK_NO_STALLED_ENDPOINT_BUFFER: assert property (@(posedge clk) disable iff (!rst_ok)
        endpoint_head_bounded_ok);

    T_DEADLOCK_NO_CREDIT_STARVATION: assert property (@(posedge clk) disable iff (!rst_ok)
        w_nospace <= NOSPACE_N);

    // The reason the wait-for graph cannot close, argued from the routing
    // and not from the checker's own closure: every route in this workload
    // is monotone east-then-south, so no input port ever asks for a north or
    // a west output, no input asks for the output it arrived on, and no
    // request would carry a flit off the mesh edge. A cyclic wait needs a
    // backward edge, and there is none to have.
    T_DEADLOCK_NO_BACKWARD_ROUTE_REQUEST: assert property (@(posedge clk) disable iff (!rst_ok)
        rq_back == 135'd0);

    T_DEADLOCK_NO_UTURN_ROUTE_REQUEST: assert property (@(posedge clk) disable iff (!rst_ok)
        uturn == 27'd0);

    T_DEADLOCK_NO_ROUTE_REQUEST_OFF_MESH: assert property (@(posedge clk) disable iff (!rst_ok)
        rq_offmesh == 135'd0);

    // ------------------------------------------------------------------
    // 13 -- reset / initialisation
    // ------------------------------------------------------------------

    T_RESET_MESH_EMPTY_AND_IDLE: assert property (@(posedge clk) disable iff (!rst_ok)
        first_cycle |-> ((nib_ne == 135'd0) && (&arb_idle) && (&sp_full)));

    T_RESET_SOURCE_CREDIT_FULL: assert property (@(posedge clk) disable iff (!rst_ok)
        first_cycle |-> (source_credit_full_ok && !dlv && (sink_occ == 3'd0)));

    T_RESET_TILE_COORDS_BEFORE_TRAFFIC: assert property (@(posedge clk) disable iff (!rst_ok)
        loc_bad == 27'd0);

    // ------------------------------------------------------------------
    // 14 -- lifecycle: the destination output port's wormhole lock
    // ------------------------------------------------------------------

    // while this file's framer says a packet is open, the shared egress is
    // still locked, and its crossbar select is the one XY routing demands for
    // the open flow: flows 0..5 arrive from the north (ROUTE_C = 2), flows
    // 6 and 7 from the west (ROUTE_B = 1), flow 8 from the endpoint
    // (ROUTE_X = 4)
    T_LIFECYCLE_EGRESS_LOCK_HELD: assert property (@(posedge clk) disable iff (!rst_ok)
        eg_open |-> (dst_planned && (dst_route == eg_route)));

    T_LIFECYCLE_EGRESS_ROUTE_MATCHES_FLOW: assert property (@(posedge clk) disable iff (!rst_ok)
        eg_open |-> ((eg_flow <= 4'd5) ? (dst_route == 3'd2)
                     : ((eg_flow <= 4'd7) ? (dst_route == 3'd1)
                                          : (dst_route == 3'd4))));

    // ================================================================ COVERS

    C_TGT_ORDER_THREE_FLOW_INTERLEAVE: cover property (@(posedge clk) disable iff (!rst_ok)
        pop[0] ##[1:60] pop[4] ##[1:60] pop[8]);

    C_TGT_ORDER_FULL_PACKET: cover property (@(posedge clk) disable iff (!rst_ok)
        (dlv && !eg_open) ##[1:60] (dlv && eg_open && (eg_pos == 4'd7)));

    C_TGT_DATA_NONZERO_PAYLOAD: cover property (@(posedge clk) disable iff (!rst_ok)
        dlv && (dlv_flit[15:0] != 16'd0));

    C_TGT_UNIQ_TWO_FLOWS_DELIVERED: cover property (@(posedge clk) disable iff (!rst_ok)
        (dlv_cnt[0] != 0) && (dlv_cnt[8] != 0));

    C_TGT_CONSERVE_DEEP_INFLIGHT: cover property (@(posedge clk) disable iff (!rst_ok)
        in_flight >= 10'd16);

    C_TGT_CONSERVE_ALL_MESH_BUFFERS_BUSY: cover property (@(posedge clk) disable iff (!rst_ok)
        (e_w[1] != 0) && (e_w[2] != 0) && (e_w[4] != 0) && (e_w[5] != 0) &&
        (e_w[7] != 0) && (e_w[8] != 0) && (e_n[5] != 0) && (e_n[8] != 0));

    C_TGT_MUTEX_T5_THREE_WAY_CONTEND: cover property (@(posedge clk) disable iff (!rst_ok)
        rq_t5s_n && rq_t5s_w && rq_t5s_p);

    C_TGT_MUTEX_DST_THREE_WAY_CONTEND: cover property (@(posedge clk) disable iff (!rst_ok)
        rq_t8p_n && rq_t8p_w && rq_t8p_p);

    C_TGT_BOUND_ENDPOINT_NIB_LOADED: cover property (@(posedge clk) disable iff (!rst_ok)
        e_p[0] >= 5'd5);

    C_TGT_BOUND_MESH_NIB_FULL: cover property (@(posedge clk) disable iff (!rst_ok)
        e_n[8] == 3'd4);

    C_TGT_ALLOC_FULL_THEN_DRAINED: cover property (@(posedge clk) disable iff (!rst_ok)
        (e_n[8] == 3'd4) ##[1:60] (e_n[8] == 3'd0));

    C_TGT_REQRSP_CREDIT_RETURNED: cover property (@(posedge clk) disable iff (!rst_ok)
        crd[0] && crd[8]);

    C_TGT_PROTO_LINK_BACKPRESSURED: cover property (@(posedge clk) disable iff (!rst_ok)
        (e_n[8] == 3'd4) && rq_t5s_n && !th_t5s_n);

    C_TGT_FAIR_T5_NORTH_WAITS: cover property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_n >= 12'd8);

    C_TGT_FAIR_T2_SOUTH_CONTEND: cover property (@(posedge clk) disable iff (!rst_ok)
        rq_t2s_w && rq_t2s_p && !(th_t2s_w && th_t2s_p));

    C_TGT_RESPONSE_GRANT_AFTER_WAIT: cover property (@(posedge clk) disable iff (!rst_ok)
        (w_grant >= 12'd8) ##[1:16] dlv);

    C_TGT_RESPONSE_SINK_FULL: cover property (@(posedge clk) disable iff (!rst_ok)
        sink_occ == 3'd4);

    C_TGT_DEADLOCK_PROGRESS_GAP: cover property (@(posedge clk) disable iff (!rst_ok)
        w_progress >= 12'd8);

    C_TGT_DEADLOCK_LOCK_AND_BLOCK: cover property (@(posedge clk) disable iff (!rst_ok)
        dst_planned && !dst_space);

    C_TGT_DEADLOCK_MESH_HEAD_HELD: cover property (@(posedge clk) disable iff (!rst_ok)
        w_meshhead[7] >= 12'd8);

    C_TGT_RESET_FIRST_CYCLE: cover property (@(posedge clk)
        first_cycle);

    C_TGT_LIFECYCLE_EGRESS_OPEN: cover property (@(posedge clk) disable iff (!rst_ok)
        eg_open && (eg_pos == 4'd4));

endmodule

bind openpiton_pmesh_deadlock_ft targets_openpiton_pmesh_waitcycle
     u_targets_openpiton_pmesh_waitcycle (.clk(clk), .reset_n(reset_n));

`undef TWC_OUT_FLAGS
`undef TWC_NIB_FLAGS
`undef TWC_DN
`undef TWC_FT
