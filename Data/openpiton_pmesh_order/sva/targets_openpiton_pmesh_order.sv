// ---------------------------------------------------------------------------
// targets_openpiton_pmesh_order.sv
//
// Candidate TARGET assertions for the 3x3 OpenPiton P-Mesh convergence task.
//
// Everything below is an INDEPENDENT oracle: four shadow payload queues, a
// set of reference counters and a set of bounded wait counters, all held in
// this file and all driven only from the two observation points the task
// already defines -- the four endpoint injections and the one shared
// destination egress -- plus read-only taps into the fabric for the
// occupancy, arbitration and handshake families. No design expression is
// restated as its own specification, and no assumption is added anywhere.
//
// Every assertion is a SAFETY property. The three liveness-shaped families
// (arbitration fairness, bounded response, deadlock freedom) are encoded as
// saturating wait counters declared here and asserted against a bound.
//
// Reset. `reset_n && dut_ready` is the same gate the task's own checker uses:
// `dynamic_node_top` registers `reset_in` once, so the fabric leaves its
// internal reset one cycle after `reset_n` rises, and `dut_ready` is exactly
// that cycle of slack. Every oracle register here is reset by it and every
// assertion is disabled by it, so a mid-trace reset flushes the fabric and
// the oracle together.
// ---------------------------------------------------------------------------

`define TGT_FT openpiton_pmesh_order_scaled_ft
`define TGT_DN(y,x,n) `TGT_FT.dut.row[y].col[x].noc[n].u_router.dynamic_node_top

// One input port of one router: the flags every mesh-wide assertion reduces.
//   I     bit index                P   hierarchical path of the dynamic_input_top
//   DEPTH NIB element count        PW  pointer width
`define TGT_NIB_FLAGS(I, P, DEPTH, PW)                                        \
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
                                       P.thanks_w, P.thanks_p});

// One output port of one router.
`define TGT_OUT_FLAGS(I, P)                                                   \
  assign arb_bad[I]     = (P.control.planned_f == 1'b0)                       \
                          && (P.control.current_route_f != 3'd0);             \
  assign arb_enc_bad[I] = (P.control.current_route_f > 3'd4);                 \
  assign arb_idle[I]    = (P.control.planned_f == 1'b0)                       \
                          && (P.control.current_route_f == 3'd0);             \
  assign sp_bad[I]      = (P.space.count_f > 3'd4);                           \
  assign sp_full[I]     = (P.space.count_f == 3'd4);

module targets_openpiton_pmesh_order (input wire clk, input wire reset_n);

    // ---------------------------------------------------------- parameters
    localparam integer QD    = 128;      // shadow queue depth, per flow
    localparam integer NFLOW = 4;

    // the 42 header bits every injected flit carries: chip 0, dst (2,2),
    // final route 0, length 0.  Only [21:20] (the flow tag) and [19:0] (the
    // payload) differ between flits.
    localparam [41:0] HDR_CONST = {14'd0, 8'd2, 8'd2, 4'd0, 8'd0};

    // bounds for the counter-encoded liveness families
    localparam integer FAIR_N     = 64;   // arbiter grant wait
    localparam integer GRANT_N    = 8;    // destination grant wait
    localparam integer DRAIN_N    = 8;    // destination egress drain
    localparam integer CREDIT_N   = 128;  // source credit return
    localparam integer HEADHOLD_N = 128;  // any path buffer head held
    localparam integer PROGRESS_N = 100;  // global no-delivery while in flight

    // ------------------------------------------------- reset for the oracle
    wire rst_ok;
    assign rst_ok = reset_n && `TGT_FT.dut_ready;

    reg armed;
    always @(posedge clk) begin
        if (!rst_ok) armed <= 1'b0;
        else         armed <= 1'b1;
    end
    wire first_cycle;
    assign first_cycle = rst_ok && !armed;

    // ------------------------------------------------ boundary observations
    wire [3:0]  inj;
    assign inj = {`TGT_FT.src3_send, `TGT_FT.src2_send,
                  `TGT_FT.src1_send, `TGT_FT.src0_send};

    wire [19:0] inj_pl [0:3];
    assign inj_pl[0] = `TGT_FT.src0_payload;
    assign inj_pl[1] = `TGT_FT.src1_payload;
    assign inj_pl[2] = `TGT_FT.src2_payload;
    assign inj_pl[3] = `TGT_FT.src3_payload;

    wire        dlv;
    wire [63:0] dlv_flit;
    wire [1:0]  dlv_flow;
    assign dlv      = `TGT_FT.dst_fire;
    assign dlv_flit = `TGT_FT.pOut_data[8][0];
    assign dlv_flow = dlv_flit[21:20];

    wire [3:0] pop;
    assign pop[0] = dlv && (dlv_flow == 2'd0);
    assign pop[1] = dlv && (dlv_flow == 2'd1);
    assign pop[2] = dlv && (dlv_flow == 2'd2);
    assign pop[3] = dlv && (dlv_flow == 2'd3);

    // credit returned to each source endpoint
    wire [3:0] crd;
    assign crd[0] = `TGT_FT.pThanks[0][0];
    assign crd[1] = `TGT_FT.pThanks[1][0];
    assign crd[2] = `TGT_FT.pThanks[2][0];
    assign crd[3] = `TGT_FT.pThanks[5][0];

    // ------------------------------------- the eight buffers that hold flits
    // Tile index = y*3+x.  Sources 0,1,2,5; destination 8.  XY routing puts
    // every flit in exactly one of these eight NIBs between injection and
    // egress; nothing else in the fabric can hold one.
    wire [4:0] e_t0_p, e_t1_p, e_t2_p, e_t5_p;   // 16-deep endpoint buffers
    wire [2:0] e_t1_w, e_t2_w, e_t5_n, e_t8_n;   // 4-deep mesh buffers
    assign e_t0_p = `TGT_DN(0,0,0).proc_input.NIB.elements_in_array_f;
    assign e_t1_p = `TGT_DN(0,1,0).proc_input.NIB.elements_in_array_f;
    assign e_t2_p = `TGT_DN(0,2,0).proc_input.NIB.elements_in_array_f;
    assign e_t5_p = `TGT_DN(1,2,0).proc_input.NIB.elements_in_array_f;
    assign e_t1_w = `TGT_DN(0,1,0).west_input.NIB.elements_in_array_f;
    assign e_t2_w = `TGT_DN(0,2,0).west_input.NIB.elements_in_array_f;
    assign e_t5_n = `TGT_DN(1,2,0).north_input.NIB.elements_in_array_f;
    assign e_t8_n = `TGT_DN(2,2,0).north_input.NIB.elements_in_array_f;

    wire [7:0] buffered_total;
    assign buffered_total = {3'd0, e_t0_p} + {3'd0, e_t1_p} + {3'd0, e_t2_p}
                          + {3'd0, e_t5_p} + {5'd0, e_t1_w} + {5'd0, e_t2_w}
                          + {5'd0, e_t5_n} + {5'd0, e_t8_n};

    // head-of-queue flit of each path buffer, and whether it is present
    wire [63:0] h_t0_p, h_t1_p, h_t2_p, h_t5_p, h_t1_w, h_t2_w, h_t5_n, h_t8_n;
    assign h_t0_p = `TGT_DN(0,0,0).proc_input.data_out;
    assign h_t1_p = `TGT_DN(0,1,0).proc_input.data_out;
    assign h_t2_p = `TGT_DN(0,2,0).proc_input.data_out;
    assign h_t5_p = `TGT_DN(1,2,0).proc_input.data_out;
    assign h_t1_w = `TGT_DN(0,1,0).west_input.data_out;
    assign h_t2_w = `TGT_DN(0,2,0).west_input.data_out;
    assign h_t5_n = `TGT_DN(1,2,0).north_input.data_out;
    assign h_t8_n = `TGT_DN(2,2,0).north_input.data_out;

    wire [1:0] h_t8_n_flow;
    assign h_t8_n_flow = h_t8_n[21:20];

    // --------------------------------------- taps at the two contended nodes
    // tile 2 (2,0) south output: flows 0/1 arrive from the west, flow 2 from
    // the endpoint.  tile 5 (2,1) south output: flows 0/1/2 from the north,
    // flow 3 from the endpoint.  tile 8 (2,2) proc output: the egress.
    wire rq_t2_w2s, rq_t2_p2s, th_t2_s2w, th_t2_s2p;
    wire rq_t5_n2s, rq_t5_p2s, th_t5_s2n, th_t5_s2p;
    wire rq_t8_n2p, th_t8_p2n;
    assign rq_t2_w2s = `TGT_DN(0,2,0).route_req_w_to_s;
    assign rq_t2_p2s = `TGT_DN(0,2,0).route_req_p_to_s;
    assign th_t2_s2w = `TGT_DN(0,2,0).thanks_s_to_w;
    assign th_t2_s2p = `TGT_DN(0,2,0).thanks_s_to_p;
    assign rq_t5_n2s = `TGT_DN(1,2,0).route_req_n_to_s;
    assign rq_t5_p2s = `TGT_DN(1,2,0).route_req_p_to_s;
    assign th_t5_s2n = `TGT_DN(1,2,0).thanks_s_to_n;
    assign th_t5_s2p = `TGT_DN(1,2,0).thanks_s_to_p;
    assign rq_t8_n2p = `TGT_DN(2,2,0).route_req_n_to_p;
    assign th_t8_p2n = `TGT_DN(2,2,0).thanks_p_to_n;

    // the four loaded links, sender valid against receiver occupancy
    wire lv_t0e, lv_t1e, lv_t2s, lv_t5s;
    assign lv_t0e = `TGT_DN(0,0,0).validOut_E;
    assign lv_t1e = `TGT_DN(0,1,0).validOut_E;
    assign lv_t2s = `TGT_DN(0,2,0).validOut_S;
    assign lv_t5s = `TGT_DN(1,2,0).validOut_S;

    // source endpoint credit counters (BUFFER_SIZE 16)
    wire [4:0] c_src0, c_src1, c_src2, c_src3;
    assign c_src0 = `TGT_FT.u_src0_credit.count_f;
    assign c_src1 = `TGT_FT.u_src1_credit.count_f;
    assign c_src2 = `TGT_FT.u_src2_credit.count_f;
    assign c_src3 = `TGT_FT.u_src3_credit.count_f;

    // ------------------------------------------------ mesh-wide flag vectors
    // 27 routers x 5 input ports, and 27 routers x 5 output ports.
    wire [134:0] nib_ne, nib_over, nib_ptr_bad, nib_enq_full, nib_deq_empty;
    wire [134:0] rq_multi, th_multi, offpath_ne;
    wire [134:0] arb_bad, arb_enc_bad, arb_idle, sp_bad, sp_full;
    wire [26:0]  pv_bad, loc_bad;

    genvar gy, gx, gn;
    generate
      for (gy = 0; gy < 3; gy = gy + 1) begin : g_row
        for (gx = 0; gx < 3; gx = gx + 1) begin : g_col
          for (gn = 0; gn < 3; gn = gn + 1) begin : g_noc
            localparam integer R = (gy*3 + gx)*3 + gn;   // router ordinal
            localparam integer B = R * 5;                // first flag bit

            `TGT_NIB_FLAGS(B+0, `TGT_DN(gy,gx,gn).north_input, 4,  2)
            `TGT_NIB_FLAGS(B+1, `TGT_DN(gy,gx,gn).east_input,  4,  2)
            `TGT_NIB_FLAGS(B+2, `TGT_DN(gy,gx,gn).south_input, 4,  2)
            `TGT_NIB_FLAGS(B+3, `TGT_DN(gy,gx,gn).west_input,  4,  2)
            `TGT_NIB_FLAGS(B+4, `TGT_DN(gy,gx,gn).proc_input, 16,  4)

            `TGT_OUT_FLAGS(B+0, `TGT_DN(gy,gx,gn).north_output)
            `TGT_OUT_FLAGS(B+1, `TGT_DN(gy,gx,gn).east_output)
            `TGT_OUT_FLAGS(B+2, `TGT_DN(gy,gx,gn).south_output)
            `TGT_OUT_FLAGS(B+3, `TGT_DN(gy,gx,gn).west_output)
            `TGT_OUT_FLAGS(B+4, `TGT_DN(gy,gx,gn).proc_output)

            // the eight buffers a flit may legally occupy
            localparam integer ON_N = ((gn == 0) && (gx == 2)
                                       && ((gy == 1) || (gy == 2))) ? 1 : 0;
            localparam integer ON_W = ((gn == 0) && (gy == 0)
                                       && ((gx == 1) || (gx == 2))) ? 1 : 0;
            localparam integer ON_P = ((gn == 0)
                                       && (((gy == 0) && (gx <= 2))
                                        || ((gy == 1) && (gx == 2)))) ? 1 : 0;
            assign offpath_ne[B+0] = ON_N ? 1'b0 : nib_ne[B+0];
            assign offpath_ne[B+1] = nib_ne[B+1];
            assign offpath_ne[B+2] = nib_ne[B+2];
            assign offpath_ne[B+3] = ON_W ? 1'b0 : nib_ne[B+3];
            assign offpath_ne[B+4] = ON_P ? 1'b0 : nib_ne[B+4];


            // no egress anywhere but the one destination endpoint
            assign pv_bad[R] = ((gy == 2) && (gx == 2) && (gn == 0))
                               ? 1'b0 : `TGT_FT.pOut_valid[gy*3 + gx][gn];

            // a router must have latched its own coordinates before any flit
            // in it is routed
            assign loc_bad[R] = (nib_ne[B+0] | nib_ne[B+1] | nib_ne[B+2]
                                 | nib_ne[B+3] | nib_ne[B+4])
                                && ((`TGT_DN(gy,gx,gn).myLocX_f != gx)
                                 || (`TGT_DN(gy,gx,gn).myLocY_f != gy));
          end
        end
      end
    endgenerate

    // ================================================================ ORACLE
    // Four shadow payload queues, one per flow, written at injection and read
    // at the shared egress.  This is the reference model: nothing in the
    // design carries a flow tag, a sequence number or a queue.
    reg [19:0] q_mem [0:NFLOW-1][0:QD-1];
    reg [6:0]  q_wr  [0:NFLOW-1];
    reg [6:0]  q_rd  [0:NFLOW-1];
    reg [7:0]  q_cnt [0:NFLOW-1];

    reg [15:0] inj_cnt [0:NFLOW-1];   // saturating reference counters
    reg [15:0] dlv_cnt [0:NFLOW-1];
    reg [15:0] crd_cnt [0:NFLOW-1];
    reg [9:0]  in_flight;             // injected minus delivered, all flows

    // registered copies of the four endpoint buffer occupancies, so the
    // credit account can be stated without $past
    reg [4:0] e_t0_p_d, e_t1_p_d, e_t2_p_d, e_t5_p_d;

    // saturating wait counters -- the bounded-safety encoding of fairness,
    // bounded response and deadlock freedom
    reg [9:0] w_t2s_w, w_t2s_p, w_t5s_n, w_t5s_p;
    reg [9:0] w_grant, w_drain, w_credit0, w_progress;
    reg [9:0] w_head [0:7];

    wire [7:0] head_pending;
    assign head_pending[0] = (e_t0_p != 0)
                             && !`TGT_DN(0,0,0).proc_input.thanks_all_temp;
    assign head_pending[1] = (e_t1_p != 0)
                             && !`TGT_DN(0,1,0).proc_input.thanks_all_temp;
    assign head_pending[2] = (e_t2_p != 0)
                             && !`TGT_DN(0,2,0).proc_input.thanks_all_temp;
    assign head_pending[3] = (e_t5_p != 0)
                             && !`TGT_DN(1,2,0).proc_input.thanks_all_temp;
    assign head_pending[4] = (e_t1_w != 0)
                             && !`TGT_DN(0,1,0).west_input.thanks_all_temp;
    assign head_pending[5] = (e_t2_w != 0)
                             && !`TGT_DN(0,2,0).west_input.thanks_all_temp;
    assign head_pending[6] = (e_t5_n != 0)
                             && !`TGT_DN(1,2,0).north_input.thanks_all_temp;
    assign head_pending[7] = (e_t8_n != 0)
                             && !`TGT_DN(2,2,0).north_input.thanks_all_temp;

    integer f, b;
    always @(posedge clk) begin
        if (!rst_ok) begin
            for (f = 0; f < NFLOW; f = f + 1) begin
                q_wr[f]    <= 7'd0;
                q_rd[f]    <= 7'd0;
                q_cnt[f]   <= 8'd0;
                inj_cnt[f] <= 16'd0;
                dlv_cnt[f] <= 16'd0;
                crd_cnt[f] <= 16'd0;
            end
            in_flight  <= 10'd0;
            e_t0_p_d   <= 5'd0;
            e_t1_p_d   <= 5'd0;
            e_t2_p_d   <= 5'd0;
            e_t5_p_d   <= 5'd0;
            w_t2s_w    <= 10'd0;
            w_t2s_p    <= 10'd0;
            w_t5s_n    <= 10'd0;
            w_t5s_p    <= 10'd0;
            w_grant    <= 10'd0;
            w_drain    <= 10'd0;
            w_credit0  <= 10'd0;
            w_progress <= 10'd0;
            for (b = 0; b < 8; b = b + 1) w_head[b] <= 10'd0;
        end else begin
            for (f = 0; f < NFLOW; f = f + 1) begin
                if (inj[f]) begin
                    q_mem[f][q_wr[f]] <= inj_pl[f];
                    q_wr[f] <= (q_wr[f] == QD-1) ? 7'd0 : q_wr[f] + 7'd1;
                    if (inj_cnt[f] != 16'hFFFF)
                        inj_cnt[f] <= inj_cnt[f] + 16'd1;
                end
                if (pop[f]) begin
                    q_rd[f] <= (q_rd[f] == QD-1) ? 7'd0 : q_rd[f] + 7'd1;
                    if (dlv_cnt[f] != 16'hFFFF)
                        dlv_cnt[f] <= dlv_cnt[f] + 16'd1;
                end
                case ({inj[f], pop[f]})
                    2'b10:   q_cnt[f] <= q_cnt[f] + 8'd1;
                    2'b01:   q_cnt[f] <= q_cnt[f] - 8'd1;
                    default: begin end
                endcase
                if (crd[f] && (crd_cnt[f] != 16'hFFFF))
                    crd_cnt[f] <= crd_cnt[f] + 16'd1;
            end

            in_flight <= in_flight + {9'd0, inj[0]} + {9'd0, inj[1]}
                                   + {9'd0, inj[2]} + {9'd0, inj[3]}
                                   - {9'd0, dlv};

            e_t0_p_d <= e_t0_p;
            e_t1_p_d <= e_t1_p;
            e_t2_p_d <= e_t2_p;
            e_t5_p_d <= e_t5_p;

            w_t2s_w <= (!(rq_t2_w2s && !th_t2_s2w)) ? 10'd0
                       : (w_t2s_w == 10'h3FF) ? w_t2s_w : w_t2s_w + 10'd1;
            w_t2s_p <= (!(rq_t2_p2s && !th_t2_s2p)) ? 10'd0
                       : (w_t2s_p == 10'h3FF) ? w_t2s_p : w_t2s_p + 10'd1;
            w_t5s_n <= (!(rq_t5_n2s && !th_t5_s2n)) ? 10'd0
                       : (w_t5s_n == 10'h3FF) ? w_t5s_n : w_t5s_n + 10'd1;
            w_t5s_p <= (!(rq_t5_p2s && !th_t5_s2p)) ? 10'd0
                       : (w_t5s_p == 10'h3FF) ? w_t5s_p : w_t5s_p + 10'd1;
            w_grant <= (!(rq_t8_n2p && !th_t8_p2n)) ? 10'd0
                       : (w_grant == 10'h3FF) ? w_grant : w_grant + 10'd1;
            w_drain <= (!((e_t8_n != 0) && !dlv)) ? 10'd0
                       : (w_drain == 10'h3FF) ? w_drain : w_drain + 10'd1;
            w_credit0 <= (!((e_t0_p != 0) && !crd[0])) ? 10'd0
                       : (w_credit0 == 10'h3FF) ? w_credit0 : w_credit0 + 10'd1;
            w_progress <= (!((in_flight != 0) && !dlv)) ? 10'd0
                       : (w_progress == 10'h3FF) ? w_progress
                                                 : w_progress + 10'd1;

            for (b = 0; b < 8; b = b + 1)
                w_head[b] <= (!head_pending[b]) ? 10'd0
                             : (w_head[b] == 10'h3FF) ? w_head[b]
                                                      : w_head[b] + 10'd1;
        end
    end

    // convenience: the payload the oracle expects next for each flow
    wire [19:0] expect_pl [0:NFLOW-1];
    assign expect_pl[0] = q_mem[0][q_rd[0]];
    assign expect_pl[1] = q_mem[1][q_rd[1]];
    assign expect_pl[2] = q_mem[2][q_rd[2]];
    assign expect_pl[3] = q_mem[3][q_rd[3]];

    wire [19:0] expect_sel;
    wire [7:0]  count_sel;
    assign expect_sel = expect_pl[dlv_flow];
    assign count_sel  = q_cnt[dlv_flow];

    wire [19:0] expect_t8n;
    wire [7:0]  count_t8n;
    assign expect_t8n = expect_pl[h_t8_n_flow];
    assign count_t8n  = q_cnt[h_t8_n_flow];

    wire path_head_hdr_ok;
    assign path_head_hdr_ok =
        ((e_t0_p == 0) || (h_t0_p[63:22] == HDR_CONST)) &&
        ((e_t1_p == 0) || (h_t1_p[63:22] == HDR_CONST)) &&
        ((e_t2_p == 0) || (h_t2_p[63:22] == HDR_CONST)) &&
        ((e_t5_p == 0) || (h_t5_p[63:22] == HDR_CONST)) &&
        ((e_t1_w == 0) || (h_t1_w[63:22] == HDR_CONST)) &&
        ((e_t2_w == 0) || (h_t2_w[63:22] == HDR_CONST)) &&
        ((e_t5_n == 0) || (h_t5_n[63:22] == HDR_CONST)) &&
        ((e_t8_n == 0) || (h_t8_n[63:22] == HDR_CONST));

    // =============================================================== TARGETS
    // 1 -- end-to-end ordering
    // ------------------------------------------------------------------

    T_ORDERING_FLOW0_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        pop[0] |-> ((q_cnt[0] != 0) && (dlv_flit[19:0] == expect_pl[0])));

    T_ORDERING_FLOW1_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        pop[1] |-> ((q_cnt[1] != 0) && (dlv_flit[19:0] == expect_pl[1])));

    T_ORDERING_FLOW2_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        pop[2] |-> ((q_cnt[2] != 0) && (dlv_flit[19:0] == expect_pl[2])));

    T_ORDERING_FLOW3_FIFO: assert property (@(posedge clk) disable iff (!rst_ok)
        pop[3] |-> ((q_cnt[3] != 0) && (dlv_flit[19:0] == expect_pl[3])));

    // the oldest undelivered flit of a flow is already the head of the last
    // buffer before the egress -- ordering observed one hop upstream
    T_ORDERING_LASTHOP_HEAD: assert property (@(posedge clk) disable iff (!rst_ok)
        (e_t8_n != 0) |-> ((count_t8n != 0)
                           && (h_t8_n[19:0] == expect_t8n)));

    // ------------------------------------------------------------------
    // 2 -- data integrity
    // ------------------------------------------------------------------

    T_INTEGRITY_EGRESS_HEADER: assert property (@(posedge clk) disable iff (!rst_ok)
        dlv |-> (dlv_flit[63:22] == HDR_CONST));

    T_INTEGRITY_EGRESS_FULL_FLIT: assert property (@(posedge clk) disable iff (!rst_ok)
        dlv |-> ((count_sel != 0)
                 && (dlv_flit == {HDR_CONST, dlv_flow, expect_sel})));

    T_INTEGRITY_PATH_HEAD_HEADER: assert property (@(posedge clk) disable iff (!rst_ok)
        path_head_hdr_ok);

    // ------------------------------------------------------------------
    // 3 -- uniqueness / no duplication
    // ------------------------------------------------------------------

    T_UNIQUE_PERFLOW_DELIVERY_LE_INJECTION: assert property (@(posedge clk) disable iff (!rst_ok)
        (dlv_cnt[0] <= inj_cnt[0]) && (dlv_cnt[1] <= inj_cnt[1]) &&
        (dlv_cnt[2] <= inj_cnt[2]) && (dlv_cnt[3] <= inj_cnt[3]));

    T_UNIQUE_NO_POP_OF_EMPTY_QUEUE: assert property (@(posedge clk) disable iff (!rst_ok)
        dlv |-> ((count_sel != 0) && (in_flight != 0)));

    // ------------------------------------------------------------------
    // 4 -- no loss / conservation
    // ------------------------------------------------------------------

    // injected minus delivered equals what the eight path buffers hold: no
    // flit is lost, invented or parked anywhere else in the fabric
    T_CONSERVE_INFLIGHT_EQUALS_BUFFERED: assert property (@(posedge clk) disable iff (!rst_ok)
        in_flight == {2'd0, buffered_total});

    T_CONSERVE_SRC0_CREDIT_ACCOUNT: assert property (@(posedge clk) disable iff (!rst_ok)
        c_src0 == (5'd16 - e_t0_p_d));

    T_CONSERVE_ALL_SRC_CREDIT_ACCOUNT: assert property (@(posedge clk) disable iff (!rst_ok)
        (c_src1 == (5'd16 - e_t1_p_d)) && (c_src2 == (5'd16 - e_t2_p_d)) &&
        (c_src3 == (5'd16 - e_t5_p_d)));

    T_CONSERVE_NO_STRAY_EGRESS: assert property (@(posedge clk) disable iff (!rst_ok)
        pv_bad == 27'd0);

    T_CONSERVE_NO_TRAFFIC_OFF_PATH: assert property (@(posedge clk) disable iff (!rst_ok)
        offpath_ne == 135'd0);

    // ------------------------------------------------------------------
    // 5 -- mutual exclusion / one-hot
    // ------------------------------------------------------------------

    T_MUTEX_ROUTE_REQ_ONEHOT_DST: assert property (@(posedge clk) disable iff (!rst_ok)
        $onehot0({`TGT_DN(2,2,0).route_req_n_to_n, `TGT_DN(2,2,0).route_req_n_to_e,
                  `TGT_DN(2,2,0).route_req_n_to_s, `TGT_DN(2,2,0).route_req_n_to_w,
                  `TGT_DN(2,2,0).route_req_n_to_p}));

    T_MUTEX_ROUTE_REQ_ONEHOT_MESH: assert property (@(posedge clk) disable iff (!rst_ok)
        rq_multi == 135'd0);

    // two output ports must never consume the same buffer entry in one cycle
    T_MUTEX_THANKS_ONEHOT_DST: assert property (@(posedge clk) disable iff (!rst_ok)
        $onehot0({`TGT_DN(2,2,0).thanks_n_to_n, `TGT_DN(2,2,0).thanks_e_to_n,
                  `TGT_DN(2,2,0).thanks_s_to_n, `TGT_DN(2,2,0).thanks_w_to_n,
                  `TGT_DN(2,2,0).thanks_p_to_n}));

    T_MUTEX_THANKS_ONEHOT_MESH: assert property (@(posedge clk) disable iff (!rst_ok)
        th_multi == 135'd0);

    // ------------------------------------------------------------------
    // 6 -- occupancy and bounds
    // ------------------------------------------------------------------

    T_BOUND_SOURCE_NIB_DEPTH: assert property (@(posedge clk) disable iff (!rst_ok)
        (e_t0_p <= 5'd16) && (e_t1_p <= 5'd16) &&
        (e_t2_p <= 5'd16) && (e_t5_p <= 5'd16));

    T_BOUND_PATH_NIB_DEPTH: assert property (@(posedge clk) disable iff (!rst_ok)
        (e_t1_w <= 3'd4) && (e_t2_w <= 3'd4) &&
        (e_t5_n <= 3'd4) && (e_t8_n <= 3'd4));

    T_BOUND_MESH_NIB_DEPTH: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_over == 135'd0);

    T_BOUND_NIB_POINTER_CONSISTENT: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_ptr_bad == 135'd0);

    T_BOUND_CREDIT_COUNTERS: assert property (@(posedge clk) disable iff (!rst_ok)
        (c_src0 <= 5'd16) && (c_src1 <= 5'd16) && (c_src2 <= 5'd16) &&
        (c_src3 <= 5'd16) && (sp_bad == 135'd0));

    T_BOUND_ROUTE_ENCODING: assert property (@(posedge clk) disable iff (!rst_ok)
        arb_enc_bad == 135'd0);

    T_BOUND_INFLIGHT_PER_FLOW: assert property (@(posedge clk) disable iff (!rst_ok)
        (q_cnt[0] <= 8'd48) && (q_cnt[1] <= 8'd48) &&
        (q_cnt[2] <= 8'd48) && (q_cnt[3] <= 8'd48));

    T_BOUND_INFLIGHT_TOTAL: assert property (@(posedge clk) disable iff (!rst_ok)
        in_flight <= 10'd96);

    // ------------------------------------------------------------------
    // 7 -- allocator discipline (the NIB slot is the allocated resource)
    // ------------------------------------------------------------------

    T_ALLOC_NO_ENQUEUE_WHEN_FULL: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_enq_full == 135'd0);

    T_ALLOC_NO_DEQUEUE_WHEN_EMPTY: assert property (@(posedge clk) disable iff (!rst_ok)
        nib_deq_empty == 135'd0);

    T_ALLOC_NO_INJECT_INTO_FULL_SOURCE: assert property (@(posedge clk) disable iff (!rst_ok)
        ((!inj[0]) || (e_t0_p < 5'd16)) && ((!inj[1]) || (e_t1_p < 5'd16)) &&
        ((!inj[2]) || (e_t2_p < 5'd16)) && ((!inj[3]) || (e_t5_p < 5'd16)));

    // ------------------------------------------------------------------
    // 8 -- request-response correspondence
    // ------------------------------------------------------------------

    T_REQRSP_NO_UNSOLICITED_FLOW: assert property (@(posedge clk) disable iff (!rst_ok)
        ((!pop[0]) || (inj_cnt[0] != 0)) && ((!pop[1]) || (inj_cnt[1] != 0)) &&
        ((!pop[2]) || (inj_cnt[2] != 0)) && ((!pop[3]) || (inj_cnt[3] != 0)));

    T_REQRSP_CREDIT_LE_INJECTION: assert property (@(posedge clk) disable iff (!rst_ok)
        (crd_cnt[0] <= inj_cnt[0]) && (crd_cnt[1] <= inj_cnt[1]) &&
        (crd_cnt[2] <= inj_cnt[2]) && (crd_cnt[3] <= inj_cnt[3]));

    T_REQRSP_CREDIT_ONLY_ON_DEQUEUE: assert property (@(posedge clk) disable iff (!rst_ok)
        ((!crd[0]) || (e_t0_p != 0)) && ((!crd[1]) || (e_t1_p != 0)) &&
        ((!crd[2]) || (e_t2_p != 0)) && ((!crd[3]) || (e_t5_p != 0)));

    // ------------------------------------------------------------------
    // 9 -- protocol conformance
    // ------------------------------------------------------------------

    // an output port only ever consumes an input that asked for it
    T_PROTO_NO_MISROUTED_GRANT: assert property (@(posedge clk) disable iff (!rst_ok)
        ((!th_t2_s2w) || rq_t2_w2s) && ((!th_t2_s2p) || rq_t2_p2s) &&
        ((!th_t5_s2n) || rq_t5_n2s) && ((!th_t5_s2p) || rq_t5_p2s) &&
        ((!th_t8_p2n) || rq_t8_n2p));

    // an unplanned output arbiter has released its crossbar select
    T_PROTO_IDLE_ARBITER_ROUTE_A: assert property (@(posedge clk) disable iff (!rst_ok)
        arb_bad == 135'd0);

    // credit-based flow control: a sender never drives valid at a buffer with
    // no free slot
    T_PROTO_NO_SEND_WITHOUT_SPACE: assert property (@(posedge clk) disable iff (!rst_ok)
        ((!lv_t0e) || (e_t1_w <= 3'd3)) && ((!lv_t1e) || (e_t2_w <= 3'd3)) &&
        ((!lv_t2s) || (e_t5_n <= 3'd3)) && ((!lv_t5s) || (e_t8_n <= 3'd3)));

    T_PROTO_EGRESS_HAS_SOURCE_DATA: assert property (@(posedge clk) disable iff (!rst_ok)
        dlv |-> ((e_t8_n != 0) && th_t8_p2n && (dlv_flit == h_t8_n)));

    // ------------------------------------------------------------------
    // 10 -- arbitration fairness (bounded wait, not liveness)
    // ------------------------------------------------------------------

    T_FAIR_T2_SOUTH_WEST_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t2s_w <= FAIR_N);

    T_FAIR_T2_SOUTH_PROC_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t2s_p <= FAIR_N);

    T_FAIR_T5_SOUTH_NORTH_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_n <= FAIR_N);

    T_FAIR_T5_SOUTH_PROC_INPUT: assert property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_p <= FAIR_N);

    // ------------------------------------------------------------------
    // 11 -- bounded response
    // ------------------------------------------------------------------

    T_RESPONSE_DST_GRANT_LATENCY: assert property (@(posedge clk) disable iff (!rst_ok)
        w_grant <= GRANT_N);

    T_RESPONSE_EGRESS_DRAIN: assert property (@(posedge clk) disable iff (!rst_ok)
        w_drain <= DRAIN_N);

    T_RESPONSE_SOURCE_CREDIT_RETURN: assert property (@(posedge clk) disable iff (!rst_ok)
        w_credit0 <= CREDIT_N);

    // ------------------------------------------------------------------
    // 12 -- deadlock freedom (bounded global progress)
    // ------------------------------------------------------------------

    T_DEADLOCK_GLOBAL_PROGRESS: assert property (@(posedge clk) disable iff (!rst_ok)
        w_progress <= PROGRESS_N);

    T_DEADLOCK_NO_STALLED_BUFFER: assert property (@(posedge clk) disable iff (!rst_ok)
        (w_head[0] <= HEADHOLD_N) && (w_head[1] <= HEADHOLD_N) &&
        (w_head[2] <= HEADHOLD_N) && (w_head[3] <= HEADHOLD_N) &&
        (w_head[4] <= HEADHOLD_N) && (w_head[5] <= HEADHOLD_N) &&
        (w_head[6] <= HEADHOLD_N) && (w_head[7] <= HEADHOLD_N));

    // ------------------------------------------------------------------
    // 13 -- reset / initialisation
    // ------------------------------------------------------------------

    T_RESET_MESH_EMPTY_AND_IDLE: assert property (@(posedge clk) disable iff (!rst_ok)
        first_cycle |-> ((nib_ne == 135'd0) && (&arb_idle) && (&sp_full)));

    T_RESET_SOURCE_CREDIT_FULL: assert property (@(posedge clk) disable iff (!rst_ok)
        first_cycle |-> ((c_src0 == 5'd16) && (c_src1 == 5'd16) &&
                         (c_src2 == 5'd16) && (c_src3 == 5'd16)));

    T_RESET_NO_TRAFFIC_AT_STARTUP: assert property (@(posedge clk) disable iff (!rst_ok)
        first_cycle |-> (!dlv && (in_flight == 10'd0)));

    T_RESET_TILE_COORDS_BEFORE_TRAFFIC: assert property (@(posedge clk) disable iff (!rst_ok)
        loc_bad == 27'd0);

    // ================================================================ COVERS

    C_TGT_ORDER_TWO_FLOW_INTERLEAVE: cover property (@(posedge clk) disable iff (!rst_ok)
        pop[0] ##[1:20] pop[1] ##[1:20] pop[0]);

    C_TGT_ORDER_BACKLOG_THEN_DELIVER: cover property (@(posedge clk) disable iff (!rst_ok)
        (q_cnt[0] >= 8'd4) ##[1:40] pop[0]);

    C_TGT_INTEGRITY_NONZERO_PAYLOAD: cover property (@(posedge clk) disable iff (!rst_ok)
        dlv && (dlv_flit[19:0] != 20'd0));

    C_TGT_UNIQUE_REPEATED_DELIVERY: cover property (@(posedge clk) disable iff (!rst_ok)
        (dlv_cnt[0] >= 16'd3) && (inj_cnt[0] >= 16'd5));

    C_TGT_CONSERVE_DEEP_INFLIGHT: cover property (@(posedge clk) disable iff (!rst_ok)
        in_flight >= 10'd12);

    C_TGT_CONSERVE_ALL_BUFFERS_BUSY: cover property (@(posedge clk) disable iff (!rst_ok)
        (e_t0_p != 0) && (e_t1_p != 0) && (e_t2_p != 0) && (e_t5_p != 0) &&
        (e_t1_w != 0) && (e_t2_w != 0) && (e_t5_n != 0) && (e_t8_n != 0));

    C_TGT_MUTEX_UPSTREAM_CONTEND: cover property (@(posedge clk) disable iff (!rst_ok)
        rq_t2_w2s && rq_t2_p2s);

    C_TGT_MUTEX_FOUR_WAY_CONTEND: cover property (@(posedge clk) disable iff (!rst_ok)
        rq_t2_w2s && rq_t2_p2s && rq_t5_n2s && rq_t5_p2s && rq_t8_n2p);

    C_TGT_BOUND_SOURCE_NIB_LOADED: cover property (@(posedge clk) disable iff (!rst_ok)
        e_t0_p >= 5'd8);

    C_TGT_BOUND_PATH_NIB_FULL: cover property (@(posedge clk) disable iff (!rst_ok)
        e_t8_n == 3'd4);

    C_TGT_ALLOC_FULL_THEN_DRAINED: cover property (@(posedge clk) disable iff (!rst_ok)
        (e_t2_w == 3'd4) ##[1:40] (e_t2_w == 3'd0));

    C_TGT_REQRSP_CREDIT_RETURNED: cover property (@(posedge clk) disable iff (!rst_ok)
        crd[0] && crd[1] && crd[2] && crd[3]);

    C_TGT_PROTO_LINK_BACKPRESSURED: cover property (@(posedge clk) disable iff (!rst_ok)
        (e_t8_n == 3'd4) && rq_t5_n2s && !th_t5_s2n);

    C_TGT_FAIR_WEST_INPUT_WAITS: cover property (@(posedge clk) disable iff (!rst_ok)
        w_t2s_w >= 10'd4);

    C_TGT_FAIR_PROC_INPUT_WAITS: cover property (@(posedge clk) disable iff (!rst_ok)
        w_t5s_p >= 10'd3);

    C_TGT_RESPONSE_GRANT_AFTER_WAIT: cover property (@(posedge clk) disable iff (!rst_ok)
        (w_grant >= 10'd1) ##1 dlv);

    C_TGT_DEADLOCK_PROGRESS_GAP: cover property (@(posedge clk) disable iff (!rst_ok)
        w_progress >= 10'd8);

    C_TGT_RESET_FIRST_CYCLE: cover property (@(posedge clk)
        first_cycle);

endmodule

bind openpiton_pmesh_order_scaled_ft targets_openpiton_pmesh_order
     u_targets_openpiton_pmesh_order (.clk(clk), .reset_n(reset_n));

`undef TGT_OUT_FLAGS
`undef TGT_NIB_FLAGS
`undef TGT_DN
`undef TGT_FT
