// ===========================================================================
// Candidate target assertions for verilog_axis_arb_mux_order.
//
// Bound into `testbench`, so every reference below is a hierarchical name from
// the formal top.  Nothing here is an assumption.
//
// The oracle is INDEPENDENT of `ft/tb.sv`'s own end-to-end reference rings.
// It cuts the path at the mux boundary instead and keeps TWO shadows:
//
//   * STAGE 1 -- one 16-entry shadow queue per source, pushed at the source
//     port (`in_valid & input_ready`, with the `tlast` the source actually
//     presented) and popped at the ARBITRATED MUX OUTPUT
//     (`mux_valid && mux_ready`), keyed on the source the mux's own `tid`
//     names.  This queue is what the four input FIFOs plus the arbiter have
//     to agree with.
//   * STAGE 2 -- one 64-entry shadow queue of the merged stream, pushed at the
//     mux output and popped at the final egress (`output_valid && out_ready`).
//     This queue is what the 16-deep output FIFO has to agree with.
//
//   * frame trackers at both boundaries, built from this file's own count of
//     `tlast`, so "a frame is in progress and it belongs to source S" is this
//     file's arithmetic and not the design's `grant`.
//   * saturating wait counters, which is how a fairness / bounded-response /
//     deadlock obligation is written as a safety property under FRA.
//
// Composition, from `ft/tb.sv`: four 8-deep `axis_fifo`s -> a locked
// round-robin `axis_arb_mux` (UPDATE_TID, so `m_axis_tid[2:1]` is the granted
// source and `[0]` is the sources' own tied-off id) -> a 16-deep `axis_fifo`.
// Every source emits fixed 4-beat frames.
// ===========================================================================

`default_nettype none

module axis_arb_targets (input wire clock, input wire reset);

    localparam integer SRC       = 4;
    localparam integer S1_DEPTH  = 16;   // per-source, stage 1
    localparam integer S2_DEPTH  = 64;   // merged, stage 2

    // Bounds for the saturating counters.  Round-robin with a grant held to
    // `tlast` serves a waiting source after at most one rotation: three other
    // 4-beat frames plus the frame in progress is 16 beats, so 24 is the
    // loose form and 16 the tight one.
    localparam [7:0] N_FAIR_LOOSE = 8'd24;
    localparam [7:0] N_FAIR_TIGHT = 8'd16;
    localparam [7:0] N_MUX_STALL  = 8'd24;
    localparam [7:0] N_OUT_STALL  = 8'd16;
    localparam [7:0] N_NO_MOVE    = 8'd24;
    localparam [7:0] CTR_MAX      = 8'd255;

    // ------------------------------------------------------------- aliases
    // source ports
    wire [3:0]  in_valid = testbench.in_valid;
    wire [31:0] in_data  = testbench.in_data;
    wire [3:0]  in_ready = testbench.input_ready;
    wire [3:0]  in_last  = testbench.input_last;
    wire [3:0]  in_push  = testbench.push;

    // input FIFO egress == mux ingress
    wire [3:0]  fv_valid = testbench.input_fifo_valid;
    wire [3:0]  fv_ready = testbench.input_fifo_ready;
    wire [31:0] fv_data  = testbench.input_fifo_data;
    wire [3:0]  fv_last  = testbench.input_fifo_last;

    // arbitrated mux egress
    wire        mux_val  = testbench.mux_valid;
    wire        mux_rdy  = testbench.mux_ready;
    wire [7:0]  mux_dat  = testbench.mux_data;
    wire        mux_lst  = testbench.mux_last;
    wire [2:0]  mux_tid  = testbench.mux_id;
    wire        mux_fire = mux_val && mux_rdy;
    wire [1:0]  mux_src  = mux_tid[2:1];

    // final egress
    wire        out_val  = testbench.output_valid;
    wire        out_rdy  = testbench.out_ready;
    wire [7:0]  out_dat  = testbench.output_data;
    wire        out_lst  = testbench.output_last;
    wire [2:0]  out_tid  = testbench.output_id;
    wire [4:0]  out_depth= testbench.output_depth;
    wire        out_fire = out_val && out_rdy;
    wire [1:0]  out_src  = out_tid[2:1];

    // arbiter state
    wire [3:0]  grant     = testbench.frame_mux.arb_inst.grant_reg;
    wire        grant_val = testbench.frame_mux.arb_inst.grant_valid_reg;
    wire [1:0]  grant_enc = testbench.frame_mux.arb_inst.grant_encoded_reg;

    // the mux's per-source input registers and its skid pair
    wire [3:0]  hold_val = testbench.frame_mux.s_axis_tvalid_reg;
    wire [31:0] hold_dat = testbench.frame_mux.s_axis_tdata_reg;
    wire [3:0]  hold_lst = testbench.frame_mux.s_axis_tlast_reg;
    wire        temp_val = testbench.frame_mux.temp_m_axis_tvalid_reg;
    wire [2:0]  temp_tid = testbench.frame_mux.temp_m_axis_tid_reg;
    wire [1:0]  temp_src = temp_tid[2:1];

    // input FIFO internals, one set per source
    wire [3:0] f_wr   [0:SRC-1];
    wire [3:0] f_rd   [0:SRC-1];
    wire [1:0] f_pipe [0:SRC-1];
    wire [3:0] f_ofw  [0:SRC-1];
    wire [3:0] f_ofr  [0:SRC-1];
    wire       f_oval [0:SRC-1];
    wire [3:0] f_depth[0:SRC-1];

    genvar g;
    generate
        for (g = 0; g < SRC; g = g + 1) begin : g_fifo
            assign f_wr[g]    = testbench.G_INPUT_FIFO[g].input_fifo.wr_ptr_reg;
            assign f_rd[g]    = testbench.G_INPUT_FIFO[g].input_fifo.rd_ptr_reg;
            assign f_pipe[g]  = testbench.G_INPUT_FIFO[g].input_fifo.m_axis_tvalid_pipe_reg;
            assign f_ofw[g]   = testbench.G_INPUT_FIFO[g].input_fifo.output_fifo.out_fifo_wr_ptr_reg;
            assign f_ofr[g]   = testbench.G_INPUT_FIFO[g].input_fifo.output_fifo.out_fifo_rd_ptr_reg;
            assign f_oval[g]  = testbench.G_INPUT_FIFO[g].input_fifo.output_fifo.m_axis_tvalid_reg;
            assign f_depth[g] = testbench.input_depth[g];
        end
    endgenerate

    // output FIFO internals
    wire [4:0] o_wr   = testbench.output_fifo.wr_ptr_reg;
    wire [4:0] o_rd   = testbench.output_fifo.rd_ptr_reg;
    wire [1:0] o_pipe = testbench.output_fifo.m_axis_tvalid_pipe_reg;
    wire [3:0] o_ofw  = testbench.output_fifo.output_fifo.out_fifo_wr_ptr_reg;
    wire [3:0] o_ofr  = testbench.output_fifo.output_fifo.out_fifo_rd_ptr_reg;
    wire       o_oval = testbench.output_fifo.output_fifo.m_axis_tvalid_reg;

    // =====================================================================
    // ORACLE 1 -- per-source shadow queue, source port -> mux egress
    // =====================================================================
    reg [7:0]  s1_dat [0:SRC-1][0:S1_DEPTH-1];
    reg        s1_lst [0:SRC-1][0:S1_DEPTH-1];
    reg [3:0]  s1_wr  [0:SRC-1];
    reg [3:0]  s1_rd  [0:SRC-1];
    reg [4:0]  s1_occ [0:SRC-1];

    // =====================================================================
    // ORACLE 2 -- merged shadow queue, mux egress -> final egress
    // =====================================================================
    reg [7:0]  s2_dat [0:S2_DEPTH-1];
    reg        s2_lst [0:S2_DEPTH-1];
    reg [2:0]  s2_tid [0:S2_DEPTH-1];
    reg [5:0]  s2_wr;
    reg [5:0]  s2_rd;
    reg [6:0]  s2_occ;

    // per-source cumulative census, saturating
    reg [15:0] in_cnt  [0:SRC-1];
    reg [15:0] out_cnt [0:SRC-1];

    // frame trackers -- this file's own count of tlast at each boundary
    reg        mux_fr_active;
    reg [1:0]  mux_fr_src;
    reg [2:0]  mux_fr_pos;
    reg        out_fr_active;
    reg [1:0]  out_fr_src;
    reg [2:0]  out_fr_pos;

    // saturating wait counters
    reg [7:0]  fair_ctr [0:SRC-1];
    reg [7:0]  mux_stall_ctr;
    reg [7:0]  out_stall_ctr;
    reg [7:0]  no_move_ctr;
    reg [7:0]  all_full_ctr;

    reg [3:0]  f_fill_q [0:SRC-1];   // last cycle's input FIFO pointer difference
    reg [4:0]  o_fill_q;              // last cycle's output FIFO pointer difference
    reg        after_reset;
    reg        seen_all_sources;
    reg [3:0]  seen_src;

    // ------------------------------------------------------- derived views
    // beats of source c already past the mux's arbitration but not yet past
    // the mux egress: the skid output register (oldest) and its temp slot.
    wire [1:0] mux_pend [0:SRC-1];
    generate
        for (g = 0; g < SRC; g = g + 1) begin : g_pend
            assign mux_pend[g] = {1'b0, (mux_val  && (mux_src  == g[1:0]))} +
                                 {1'b0, (temp_val && (temp_src == g[1:0]))};
        end
    endgenerate

    reg        hold_bad;      // the mux's per-source register disagrees
    reg        fifo_head_bad; // the FIFO's presented beat disagrees
    reg        acct_bad;      // stage-1 occupancy disagrees with FIFO state
    reg        occ_bad;       // some stage-1 queue is over its expected bound
    reg        fill_bad;      // some input FIFO is over 8 entries
    reg        skid_bad;      // some skid FIFO is at 8 entries
    reg        stable_bad;    // an input FIFO withdrew a beat
    reg        cnt_bad;       // more beats out of a source than into it
    reg        depth_bad;     // status_depth does not track the pointers
    reg        ready_bad;     // a source port refused a beat with room to spare
    reg        all_full;      // every input FIFO is at its eight entries
    reg [3:0]  nxt;
    reg [3:0]  nx2;
    reg [6:0]  acct;
    integer    c;

    always @* begin
        hold_bad      = 1'b0;
        fifo_head_bad = 1'b0;
        acct_bad      = 1'b0;
        occ_bad       = 1'b0;
        fill_bad      = 1'b0;
        skid_bad      = 1'b0;
        cnt_bad       = 1'b0;
        depth_bad     = 1'b0;
        ready_bad     = 1'b0;
        all_full      = 1'b1;
        for (c = 0; c < SRC; c = c + 1) begin
            nxt = s1_rd[c] + {2'd0, mux_pend[c]};
            nx2 = nxt + {3'd0, hold_val[c]};
            if (hold_val[c] && (s1_occ[c] > {3'd0, mux_pend[c]}))
                if ((hold_dat[8*c +: 8] != s1_dat[c][nxt]) ||
                    (hold_lst[c] != s1_lst[c][nxt]))
                    hold_bad = 1'b1;
            if (fv_valid[c] &&
                (s1_occ[c] > ({3'd0, mux_pend[c]} + {4'd0, hold_val[c]})))
                if ((fv_data[8*c +: 8] != s1_dat[c][nx2]) ||
                    (fv_last[c] != s1_lst[c][nx2]))
                    fifo_head_bad = 1'b1;
            acct = {3'd0, f_wr[c] - f_rd[c]}
                 + {6'd0, f_pipe[c][0]} + {6'd0, f_pipe[c][1]}
                 + {3'd0, f_ofw[c] - f_ofr[c]}
                 + {6'd0, f_oval[c]} + {6'd0, hold_val[c]}
                 + {5'd0, mux_pend[c]};
            if ({2'd0, s1_occ[c]} != acct)
                acct_bad = 1'b1;
            if (s1_occ[c] > 5'd9)
                occ_bad = 1'b1;
            if ((f_wr[c] - f_rd[c]) > 4'd8)
                fill_bad = 1'b1;
            if ((f_ofw[c] - f_ofr[c]) > 4'd7)
                skid_bad = 1'b1;
            if (out_cnt[c] > in_cnt[c])
                cnt_bad = 1'b1;
            if (f_depth[c] != f_fill_q[c])
                depth_bad = 1'b1;
            if (!in_ready[c] && ((f_wr[c] - f_rd[c]) != 4'd8))
                ready_bad = 1'b1;
            if ((f_wr[c] - f_rd[c]) != 4'd8)
                all_full = 1'b0;
        end
    end

    // a source that presented a beat to the mux last cycle and was not taken
    reg [3:0] fv_valid_q;
    reg [31:0] fv_data_q;
    reg [3:0] fv_last_q;
    reg [3:0] fv_ready_q;
    integer q;
    always @(posedge clock) begin
        for (q = 0; q < SRC; q = q + 1)
            f_fill_q[q] <= f_wr[q] - f_rd[q];
        o_fill_q   <= o_wr - o_rd;
        fv_valid_q <= fv_valid;
        fv_data_q  <= fv_data;
        fv_last_q  <= fv_last;
        fv_ready_q <= fv_ready;
        after_reset <= reset;
    end

    always @* begin
        stable_bad = 1'b0;
        for (c = 0; c < SRC; c = c + 1)
            if (fv_valid_q[c] && !fv_ready_q[c])
                if (!fv_valid[c] || (fv_data[8*c +: 8] != fv_data_q[8*c +: 8])
                                 || (fv_last[c] != fv_last_q[c]))
                    stable_bad = 1'b1;
    end

    // ------------------------------------------------------- oracle update
    integer u;
    always @(posedge clock) begin
        if (reset) begin
            s2_wr <= 6'd0; s2_rd <= 6'd0; s2_occ <= 7'd0;
            mux_fr_active <= 1'b0; mux_fr_src <= 2'd0; mux_fr_pos <= 3'd0;
            out_fr_active <= 1'b0; out_fr_src <= 2'd0; out_fr_pos <= 3'd0;
            mux_stall_ctr <= 8'd0;
            out_stall_ctr <= 8'd0;
            no_move_ctr   <= 8'd0;
            all_full_ctr  <= 8'd0;
            seen_src      <= 4'd0;
            seen_all_sources <= 1'b0;
            for (u = 0; u < SRC; u = u + 1) begin
                s1_wr[u]    <= 4'd0;
                s1_rd[u]    <= 4'd0;
                s1_occ[u]   <= 5'd0;
                in_cnt[u]   <= 16'd0;
                out_cnt[u]  <= 16'd0;
                fair_ctr[u] <= 8'd0;
            end
        end else begin
            // stage 1: push at the source port, pop at the mux egress
            for (u = 0; u < SRC; u = u + 1) begin
                if (in_push[u]) begin
                    s1_dat[u][s1_wr[u]] <= in_data[8*u +: 8];
                    s1_lst[u][s1_wr[u]] <= in_last[u];
                    s1_wr[u]  <= s1_wr[u] + 4'd1;
                    if (in_cnt[u] != 16'hffff)
                        in_cnt[u] <= in_cnt[u] + 16'd1;
                end
                if (mux_fire && (mux_src == u[1:0]))
                    s1_rd[u] <= s1_rd[u] + 4'd1;
                case ({in_push[u], mux_fire && (mux_src == u[1:0])})
                    2'b10: s1_occ[u] <= s1_occ[u] + 5'd1;
                    2'b01: s1_occ[u] <= s1_occ[u] - 5'd1;
                    default: s1_occ[u] <= s1_occ[u];
                endcase
                if (out_fire && (out_src == u[1:0]) && (out_cnt[u] != 16'hffff))
                    out_cnt[u] <= out_cnt[u] + 16'd1;

                // fairness: other-source beats taken while u is asking
                if (!fv_valid[u] || (mux_fire && (mux_src == u[1:0])))
                    fair_ctr[u] <= 8'd0;
                else if (mux_fire && (fair_ctr[u] != CTR_MAX))
                    fair_ctr[u] <= fair_ctr[u] + 8'd1;
            end

            // stage 2: push at the mux egress, pop at the final egress
            if (mux_fire) begin
                s2_dat[s2_wr] <= mux_dat;
                s2_lst[s2_wr] <= mux_lst;
                s2_tid[s2_wr] <= mux_tid;
                s2_wr <= s2_wr + 6'd1;
            end
            if (out_fire)
                s2_rd <= s2_rd + 6'd1;
            case ({mux_fire, out_fire})
                2'b10: s2_occ <= s2_occ + 7'd1;
                2'b01: s2_occ <= s2_occ - 7'd1;
                default: s2_occ <= s2_occ;
            endcase

            // frame trackers
            if (mux_fire) begin
                if (!mux_fr_active) begin
                    mux_fr_src    <= mux_src;
                    mux_fr_active <= !mux_lst;
                    mux_fr_pos    <= mux_lst ? 3'd0 : 3'd1;
                end else if (mux_lst) begin
                    mux_fr_active <= 1'b0;
                    mux_fr_pos    <= 3'd0;
                end else begin
                    mux_fr_pos    <= mux_fr_pos + 3'd1;
                end
            end
            if (out_fire) begin
                seen_src[out_src] <= 1'b1;
                if (&(seen_src | (4'd1 << out_src)))
                    seen_all_sources <= 1'b1;
                if (!out_fr_active) begin
                    out_fr_src    <= out_src;
                    out_fr_active <= !out_lst;
                    out_fr_pos    <= out_lst ? 3'd0 : 3'd1;
                end else if (out_lst) begin
                    out_fr_active <= 1'b0;
                    out_fr_pos    <= 3'd0;
                end else begin
                    out_fr_pos    <= out_fr_pos + 3'd1;
                end
            end

            // bounded response: the granted source has a beat in its shadow,
            // the merge point can take one, and nothing crosses.
            if (!(grant_val && (s1_occ[grant_enc] != 5'd0)) || !mux_rdy
                    || mux_fire)
                mux_stall_ctr <= 8'd0;
            else if (mux_stall_ctr != CTR_MAX)
                mux_stall_ctr <= mux_stall_ctr + 8'd1;

            // bounded response: the merged shadow is not empty, the consumer
            // is ready, and nothing leaves.
            if ((s2_occ == 7'd0) || !out_rdy || out_fire)
                out_stall_ctr <= 8'd0;
            else if (out_stall_ctr != CTR_MAX)
                out_stall_ctr <= out_stall_ctr + 8'd1;

            // deadlock: work is pending somewhere the design can act on, the
            // consumer is ready, and no beat moves at ANY of the three
            // boundaries.
            if (!((s2_occ != 7'd0) ||
                  (grant_val && (s1_occ[grant_enc] != 5'd0)))
                    || !out_rdy || (|in_push) || mux_fire || out_fire)
                no_move_ctr <= 8'd0;
            else if (no_move_ctr != CTR_MAX)
                no_move_ctr <= no_move_ctr + 8'd1;

            // deadlock: every source is blocked at its port and the consumer
            // is ready, so the granted source is holding data it can merge.
            if (!all_full || !out_rdy || mux_fire)
                all_full_ctr <= 8'd0;
            else if (all_full_ctr != CTR_MAX)
                all_full_ctr <= all_full_ctr + 8'd1;
        end
    end

    // =====================================================================
    // 1 -- END-TO-END ORDERING
    // =====================================================================
    T_ORDER_MUX_BEAT_IS_SOURCE_HEAD: assert property (@(posedge clock) disable iff (reset) (mux_fire && (s1_occ[mux_src] != 5'd0)) |-> (mux_dat == s1_dat[mux_src][s1_rd[mux_src]]));

    T_ORDER_MUX_LAST_IS_SOURCE_HEAD: assert property (@(posedge clock) disable iff (reset) (mux_fire && (s1_occ[mux_src] != 5'd0)) |-> (mux_lst == s1_lst[mux_src][s1_rd[mux_src]]));

    T_ORDER_OUT_BEAT_IS_MERGE_HEAD: assert property (@(posedge clock) disable iff (reset) (out_fire && (s2_occ != 7'd0)) |-> (out_dat == s2_dat[s2_rd]));

    T_ORDER_OUT_ID_IS_MERGE_HEAD_ID: assert property (@(posedge clock) disable iff (reset) (out_fire && (s2_occ != 7'd0)) |-> (out_tid == s2_tid[s2_rd]));

    T_ORDER_OUT_FRAME_ENDS_ON_FOURTH_BEAT: assert property (@(posedge clock) disable iff (reset) (out_fire && out_lst) |-> (out_fr_pos == 3'd3));

    // =====================================================================
    // 2 -- DATA INTEGRITY
    // =====================================================================
    T_DATA_OUT_LAST_IS_MERGE_HEAD_LAST: assert property (@(posedge clock) disable iff (reset) (out_fire && (s2_occ != 7'd0)) |-> (out_lst == s2_lst[s2_rd]));

    T_DATA_MUX_HOLD_REG_IS_SOURCE_HEAD: assert property (@(posedge clock) disable iff (reset) !hold_bad);

    T_DATA_INPUT_FIFO_HEAD_IS_SOURCE_HEAD: assert property (@(posedge clock) disable iff (reset) !fifo_head_bad);

    T_DATA_OUT_ID_CARRIES_SOURCE_TIED_BIT: assert property (@(posedge clock) disable iff (reset) out_val |-> (out_tid[0] == 1'b0));

    // =====================================================================
    // 3 -- UNIQUENESS / NO DUPLICATION
    // =====================================================================
    T_UNIQ_MUX_BEAT_WAS_PUSHED: assert property (@(posedge clock) disable iff (reset) mux_fire |-> (s1_occ[mux_src] != 5'd0));

    T_UNIQ_OUT_BEAT_WAS_MERGED: assert property (@(posedge clock) disable iff (reset) out_fire |-> (s2_occ != 7'd0));

    T_UNIQ_NO_SOURCE_DELIVERED_TWICE: assert property (@(posedge clock) disable iff (reset) !cnt_bad);

    // =====================================================================
    // 4 -- NO LOSS / CONSERVATION
    // =====================================================================
    T_CONSERV_STAGE1_OCC_MATCHES_FIFO_STATE: assert property (@(posedge clock) disable iff (reset) !acct_bad);

    T_CONSERV_STAGE2_OCC_MATCHES_OUTPUT_FIFO_STATE: assert property (@(posedge clock) disable iff (reset) (s2_occ == ({2'd0, o_wr - o_rd} + {6'd0, o_pipe[0]} + {6'd0, o_pipe[1]} + {3'd0, o_ofw - o_ofr} + {6'd0, o_oval})));

    T_CONSERV_INPUT_STATUS_DEPTH_TRACKS_PTRS: assert property (@(posedge clock) disable iff (reset) !after_reset |-> !depth_bad);

    T_CONSERV_OUTPUT_STATUS_DEPTH_TRACKS_PTRS: assert property (@(posedge clock) disable iff (reset) !after_reset |-> (out_depth == o_fill_q));

    // =====================================================================
    // 5 -- MUTUAL EXCLUSION / ONE-HOT
    // =====================================================================
    T_MUTEX_ARB_GRANT_ONEHOT0: assert property (@(posedge clock) disable iff (reset) $onehot0(grant));

    T_MUTEX_ARB_GRANT_VALID_IFF_GRANTED: assert property (@(posedge clock) disable iff (reset) (grant_val == (grant != 4'd0)));

    T_MUTEX_ARB_GRANT_MATCHES_ENCODING: assert property (@(posedge clock) disable iff (reset) grant_val |-> (grant == (4'd1 << grant_enc)));

    T_MUTEX_MUX_FRAME_HAS_ONE_OWNER: assert property (@(posedge clock) disable iff (reset) (mux_fire && mux_fr_active) |-> (mux_src == mux_fr_src));

    T_MUTEX_OUT_FRAME_HAS_ONE_OWNER: assert property (@(posedge clock) disable iff (reset) (out_fire && out_fr_active) |-> (out_src == out_fr_src));

    // =====================================================================
    // 6 -- OCCUPANCY AND BOUNDS
    // =====================================================================
    T_BOUND_STAGE1_OCC_LE_NINE: assert property (@(posedge clock) disable iff (reset) !occ_bad);

    T_BOUND_STAGE2_OCC_LE_THIRTYTWO: assert property (@(posedge clock) disable iff (reset) (s2_occ <= 7'd32));

    T_BOUND_INPUT_FIFO_FILL_LE_DEPTH: assert property (@(posedge clock) disable iff (reset) !fill_bad);

    T_BOUND_OUTPUT_FIFO_FILL_LE_DEPTH: assert property (@(posedge clock) disable iff (reset) ((o_wr - o_rd) <= 5'd16));

    T_BOUND_INPUT_SKID_FIFO_NEVER_FULL: assert property (@(posedge clock) disable iff (reset) !skid_bad);

    T_BOUND_OUTPUT_SKID_FIFO_NEVER_FULL: assert property (@(posedge clock) disable iff (reset) ((o_ofw - o_ofr) <= 4'd7));

    // =====================================================================
    // 9 -- PROTOCOL CONFORMANCE
    // =====================================================================
    T_PROTO_MUX_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (mux_val && !mux_rdy) |=> mux_val);

    T_PROTO_MUX_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (mux_val && !mux_rdy) |=> ($stable(mux_dat) && $stable(mux_lst) && $stable(mux_tid)));

    T_PROTO_OUT_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (out_val && !out_rdy) |=> out_val);

    T_PROTO_OUT_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (out_val && !out_rdy) |=> ($stable(out_dat) && $stable(out_lst) && $stable(out_tid)));

    T_PROTO_INPUT_FIFO_EGRESS_STABLE: assert property (@(posedge clock) disable iff (reset) !stable_bad);

    T_PROTO_SOURCE_PORT_READY_ONLY_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) !ready_bad);

    // =====================================================================
    // 10 -- ARBITRATION FAIRNESS (bounded-safety form)
    // =====================================================================
    T_FAIR_SOURCE_SERVED_WITHIN_LOOSE_N: assert property (@(posedge clock) disable iff (reset) ((fair_ctr[0] <= N_FAIR_LOOSE) && (fair_ctr[1] <= N_FAIR_LOOSE) && (fair_ctr[2] <= N_FAIR_LOOSE) && (fair_ctr[3] <= N_FAIR_LOOSE)));

    T_FAIR_SOURCE_SERVED_WITHIN_TIGHT_N: assert property (@(posedge clock) disable iff (reset) ((fair_ctr[0] <= N_FAIR_TIGHT) && (fair_ctr[1] <= N_FAIR_TIGHT) && (fair_ctr[2] <= N_FAIR_TIGHT) && (fair_ctr[3] <= N_FAIR_TIGHT)));

    // =====================================================================
    // 11 -- BOUNDED RESPONSE (bounded-safety form)
    // =====================================================================
    T_BOUNDRSP_GRANTED_SOURCE_MERGED_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (mux_stall_ctr <= N_MUX_STALL));

    T_BOUNDRSP_MERGED_BEAT_DELIVERED_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (out_stall_ctr <= N_OUT_STALL));

    // =====================================================================
    // 12 -- DEADLOCK FREEDOM (bounded-safety form)
    // =====================================================================
    T_DEADLOCK_SOME_BOUNDARY_MOVES_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (no_move_ctr <= N_NO_MOVE));

    T_DEADLOCK_ALL_INPUTS_FULL_DRAINS_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (all_full_ctr <= N_NO_MOVE));

    // =====================================================================
    // 13 -- RESET / INITIALISATION
    // =====================================================================
    T_RESET_INPUT_FIFOS_EMPTY: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((f_wr[0] == f_rd[0]) && (f_wr[1] == f_rd[1]) && (f_wr[2] == f_rd[2]) && (f_wr[3] == f_rd[3])));

    T_RESET_ARBITER_IDLE: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((grant == 4'd0) && !grant_val));

    T_RESET_MUX_HOLDS_NOTHING: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((hold_val == 4'd0) && !mux_val && !temp_val));

    T_RESET_OUTPUT_FIFO_EMPTY: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((o_wr == o_rd) && (o_ofw == o_ofr) && !out_val && (o_pipe == 2'd0)));

    // =====================================================================
    // COVERS -- one or more per category used above
    // =====================================================================
    C_ORDER_MUX_FRAME_IN_PROGRESS: cover property (@(posedge clock) disable iff (reset) (mux_fire && mux_fr_active));
    C_ORDER_OUT_FRAME_COMPLETES: cover property (@(posedge clock) disable iff (reset) (out_fire && out_lst && (out_fr_pos == 3'd3)));

    C_DATA_MUX_HOLD_REG_BUSY: cover property (@(posedge clock) disable iff (reset) (hold_val == 4'hf));
    C_DATA_SKID_TEMP_IN_USE: cover property (@(posedge clock) disable iff (reset) temp_val);

    C_UNIQ_ALL_SOURCES_DELIVERED: cover property (@(posedge clock) disable iff (reset) seen_all_sources);

    C_CONSERV_STAGE1_DEEP: cover property (@(posedge clock) disable iff (reset) (s1_occ[0] >= 5'd6));
    C_CONSERV_STAGE2_DEEP: cover property (@(posedge clock) disable iff (reset) (s2_occ >= 7'd8));

    C_MUTEX_FOUR_WAY_CONTENTION: cover property (@(posedge clock) disable iff (reset) ((fv_valid == 4'hf) && mux_fire));
    C_MUTEX_GRANT_ROTATES: cover property (@(posedge clock) disable iff (reset) (grant_val && (grant_enc == 2'd3)));

    C_OCC_INPUT_FIFO_FULL: cover property (@(posedge clock) disable iff (reset) ((f_wr[0] - f_rd[0]) == 4'd8));
    C_OCC_OUTPUT_FIFO_HALF: cover property (@(posedge clock) disable iff (reset) ((o_wr - o_rd) >= 5'd8));

    C_PROTO_MUX_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (mux_val && !mux_rdy));
    C_PROTO_OUT_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (out_val && !out_rdy));
    C_PROTO_INPUT_FIFO_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) ((fv_valid & ~fv_ready) != 4'd0));

    C_FAIR_SOURCE_WAITED_EIGHT: cover property (@(posedge clock) disable iff (reset) (fair_ctr[0] >= 8'd8));
    C_FAIR_SOURCE_WAITED_TWELVE: cover property (@(posedge clock) disable iff (reset) (fair_ctr[3] >= 8'd12));

    C_BOUNDRSP_MUX_STALLED_FOUR: cover property (@(posedge clock) disable iff (reset) (mux_stall_ctr >= 8'd4));
    C_BOUNDRSP_OUT_STALLED_FOUR: cover property (@(posedge clock) disable iff (reset) (out_stall_ctr >= 8'd4));

    C_DEADLOCK_NOTHING_MOVED_FOUR: cover property (@(posedge clock) disable iff (reset) (no_move_ctr >= 8'd4));
    C_DEADLOCK_ALL_INPUTS_FULL: cover property (@(posedge clock) disable iff (reset) all_full);

    C_RESET_FIRST_CYCLE_AFTER_RESET: cover property (@(posedge clock) disable iff (reset) after_reset);

endmodule

`default_nettype wire

bind testbench axis_arb_targets axis_arb_targets (
    .clock(clock), .reset(reset));
