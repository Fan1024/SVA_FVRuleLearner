// ===========================================================================
// Candidate target assertions for the PULP buffered 4x4 stream crossbar block.
//
//     4 inputs -> cc_stream_fifo(4) -> cc_stream_xbar(4x4, round robin,
//     LockIn, AxiVldRdy, output spill register) -> cc_stream_fifo(4) -> 4 outs
//
// Bound into `testbench`, so every reference below is an absolute hierarchical
// name from the formal top. Nothing here is an assumption, and every property
// here is a concurrent `assert property` -- the package's own target
// (T_BUFFERED_XBAR_ORDER) is a labelled IMMEDIATE assertion inside `ft/tb.sv`
// and is deliberately left in that form.
//
// THE ORACLES ARE INDEPENDENT of the design's bookkeeping AND of the formal
// top's own sixteen (source, destination) reference rings.  Where the shipped
// target checks ONE relation -- input push against output pop, per pair --
// this file cuts the path into its three real buffers and shadows each one
// separately, so a failure says WHICH stage lost or reordered a beat:
//
//   A  a 4-entry SHADOW of every input `cc_stream_fifo`, pushed at
//      (in_valid & input_ready) with the payload the top built, popped when
//      the crossbar accepts the head.  Its head is compared against
//      `buffered_payload`, its occupancy against `input_usage`.
//
//   B  a SHADOW of every output SPILL REGISTER, pushed when this file's own
//      decode says input i was accepted for output o -- that is
//      buffered_valid[i] & buffered_ready[i] & (dest of i == o), computed
//      here and NOT read from `idx_o`, `gnt_o` or `rr_q`.  Its head is
//      compared against the crossbar's `idx_o` and data at `switched_valid`.
//      This is what makes "the crossbar labels the beat with the input it
//      really came from" a checkable claim rather than a definition.
//
//   C  a 4-entry SHADOW of every output `cc_stream_fifo`, pushed at the
//      crossbar's output handshake, popped at the top's output handshake.
//
//   D  PER-PAIR IN-FLIGHT counters, one per (input, output), compared against
//      the formal top's own `ref_count` -- two rings built at the same two
//      boundaries out of different code -- and a whole-block accounting
//      identity against the three stage occupancies.
//
//   E  SATURATING WAIT counters per (input, output) and per output.  That is
//      how a fairness, a bounded-response or a deadlock obligation is written
//      as a safety property; there is no `s_eventually` in this file and there
//      must not be, because the reset cut makes liveness vacuous.  `out_ready`
//      is a free input of this package and no assumption may be added, so a
//      fairness bound here is counted in TRANSFERS on the contended output,
//      and a cycle bound is cleared whenever that output's sink stops taking
//      beats.
//
// Payload bit positions, from the two packed structs in `ft/tb.sv`:
//     in_payload_t  = {dest[1:0], data[7:0]}   -> [9:8] dest, [7:0] data
//     out_payload_t = {source[1:0], data[7:0]} -> [9:8] source, [7:0] data
// ===========================================================================

`default_nettype none

module pulp_xbar_targets (input wire clk, input wire rst);

  // ----------------------------------------------------------- the boundaries
  wire [3:0] iv   = testbench.in_valid;
  wire [3:0] ird  = testbench.input_ready;
  wire [3:0] bv   = testbench.buffered_valid;
  wire [3:0] brd  = testbench.buffered_ready;
  wire [3:0] sv   = testbench.switched_valid;
  wire [3:0] srd  = testbench.switched_ready;
  wire [3:0] ov   = testbench.output_valid;
  wire [3:0] ordy = testbench.out_ready;

  wire [9:0] spay   [0:3];   // what the top presents at an input
  wire [9:0] bpay   [0:3];   // the head of an input buffer
  wire [1:0] bdest  [0:3];
  wire [1:0] ssrc   [0:3];   // the crossbar's own idx_o, after the spill
  wire [7:0] sdat   [0:3];
  wire [9:0] opay   [0:3];   // the head of an output buffer
  wire [2:0] iusage [0:3];
  wire [2:0] ousage [0:3];
  wire [3:0] agnt   [0:3];   // each output arbiter's grant vector
  wire [1:0] arrq   [0:3];
  wire       alock  [0:3];
  wire       spa    [0:3];
  wire       spb    [0:3];
  wire       av     [0:3];   // spill register valid_i  (arb_valid)
  wire       ar     [0:3];   // spill register ready_o  (arb_ready)

  genvar go, gj;
  generate
    for (go = 0; go < 4; go = go + 1) begin : g_port
      assign spay[go]   = testbench.source_payload[go];
      assign bpay[go]   = testbench.buffered_payload[go];
      assign bdest[go]  = testbench.buffered_payload[go][9:8];
      assign ssrc[go]   = testbench.switched_source[go];
      assign sdat[go]   = testbench.switched_payload[go][7:0];
      assign opay[go]   = testbench.output_fifo_out[go];
      assign iusage[go] = testbench.input_usage[go];
      assign ousage[go] = testbench.output_usage[go];
      assign agnt[go]   = testbench.xbar.gen_outs[go].i_rr_arb_tree.gnt_o;
      assign arrq[go]   = testbench.xbar.gen_outs[go].i_rr_arb_tree.gen_arbiter.rr_q;
      assign alock[go]  =
        testbench.xbar.gen_outs[go].i_rr_arb_tree.gen_arbiter.gen_int_rr.gen_lock.lock_q;
      assign spa[go]    =
        testbench.xbar.gen_outs[go].i_spill_register.spill_register_flushable_i.gen_spill_reg.a_full_q;
      assign spb[go]    =
        testbench.xbar.gen_outs[go].i_spill_register.spill_register_flushable_i.gen_spill_reg.b_full_q;
      assign av[go]     = testbench.xbar.gen_outs[go].arb_valid;
      assign ar[go]     = testbench.xbar.gen_outs[go].arb_ready;
    end
  endgenerate

  // ------------------------------------------------------------------- events
  wire [3:0] ipush = iv & ird;    // a beat enters an input buffer
  wire [3:0] xacc  = bv & brd;    // the crossbar takes an input buffer's head
  wire [3:0] xpop  = sv & srd;    // a beat leaves the crossbar's spill register
  wire [3:0] opop  = ov & ordy;   // a beat leaves an output buffer

  // this file's own decode of which input the crossbar took for which output
  wire [3:0] acc_for [0:3];
  generate
    for (go = 0; go < 4; go = go + 1) begin : g_accfor
      for (gj = 0; gj < 4; gj = gj + 1) begin : g_accfor_in
        assign acc_for[go][gj] = xacc[gj] && (bdest[gj] == go[1:0]);
      end
    end
  endgenerate

  wire [1:0] src_of [0:3];
  generate
    for (go = 0; go < 4; go = go + 1) begin : g_srcof
      assign src_of[go] = acc_for[go][1] ? 2'd1 :
                          acc_for[go][2] ? 2'd2 :
                          acc_for[go][3] ? 2'd3 : 2'd0;
    end
  endgenerate

  // ============================================================== THE ORACLES
  reg [9:0] in_q [0:3][0:3];   reg [1:0] in_wp [0:3];  reg [1:0] in_rp [0:3];
  reg [2:0] in_cnt [0:3];

  reg [9:0] sp_q [0:3][0:3];   reg [1:0] sp_wp [0:3];  reg [1:0] sp_rp [0:3];
  reg [2:0] sp_cnt [0:3];

  reg [9:0] of_q [0:3][0:3];   reg [1:0] of_wp [0:3];  reg [1:0] of_rp [0:3];
  reg [2:0] of_cnt [0:3];

  reg [4:0] n_pair [0:3][0:3];   // in flight per (input, output)

  reg [2:0] wg   [0:3][0:3];     // transfers on o taken by somebody else
  reg [5:0] wr   [0:3][0:3];     // cycles waiting while o's sink is taking
  reg [3:0] w_prog;              // block-wide stall while every sink is taking
  reg [3:0] w_spill [0:3];       // spill holds a beat and the output will not
  reg [3:0] w_drain [0:3];       // output buffer holds a beat and will not pop

  reg [3:0] held    [0:3];       // asking o continuously since the last accept
  reg [1:0] prev_src[0:3];
  reg [3:0] seen_o;

  reg rst_q;
  wire first = rst_q && !rst;

  integer i, o;

  always @(posedge clk) begin
    rst_q <= rst;
    if (rst) begin
      w_prog <= 4'd0;
      seen_o <= 4'd0;
      for (o = 0; o < 4; o = o + 1) begin
        in_wp[o] <= 2'd0; in_rp[o] <= 2'd0; in_cnt[o] <= 3'd0;
        sp_wp[o] <= 2'd0; sp_rp[o] <= 2'd0; sp_cnt[o] <= 3'd0;
        of_wp[o] <= 2'd0; of_rp[o] <= 2'd0; of_cnt[o] <= 3'd0;
        w_spill[o] <= 4'd0; w_drain[o] <= 4'd0;
        held[o] <= 4'd0; prev_src[o] <= 2'd0;
        for (i = 0; i < 4; i = i + 1) begin
          n_pair[i][o] <= 5'd0;
          wg[i][o] <= 3'd0;
          wr[i][o] <= 6'd0;
        end
      end
    end else begin
      // ---- A: the input buffers
      for (i = 0; i < 4; i = i + 1) begin
        if (ipush[i]) begin
          in_q[i][in_wp[i]] <= spay[i];
          in_wp[i] <= in_wp[i] + 2'd1;
        end
        if (xacc[i]) in_rp[i] <= in_rp[i] + 2'd1;
        case ({ipush[i], xacc[i]})
          2'b10: in_cnt[i] <= in_cnt[i] + 3'd1;
          2'b01: in_cnt[i] <= in_cnt[i] - 3'd1;
          default: in_cnt[i] <= in_cnt[i];
        endcase
      end

      // ---- B: the output spill registers
      for (o = 0; o < 4; o = o + 1) begin
        if (|acc_for[o]) begin
          sp_q[o][sp_wp[o]] <= {src_of[o], bpay[src_of[o]][7:0]};
          sp_wp[o] <= sp_wp[o] + 2'd1;
        end
        if (xpop[o]) sp_rp[o] <= sp_rp[o] + 2'd1;
        case ({(|acc_for[o]), xpop[o]})
          2'b10: sp_cnt[o] <= sp_cnt[o] + 3'd1;
          2'b01: sp_cnt[o] <= sp_cnt[o] - 3'd1;
          default: sp_cnt[o] <= sp_cnt[o];
        endcase
      end

      // ---- C: the output buffers
      for (o = 0; o < 4; o = o + 1) begin
        if (xpop[o]) begin
          of_q[o][of_wp[o]] <= {ssrc[o], sdat[o]};
          of_wp[o] <= of_wp[o] + 2'd1;
        end
        if (opop[o]) of_rp[o] <= of_rp[o] + 2'd1;
        case ({xpop[o], opop[o]})
          2'b10: of_cnt[o] <= of_cnt[o] + 3'd1;
          2'b01: of_cnt[o] <= of_cnt[o] - 3'd1;
          default: of_cnt[o] <= of_cnt[o];
        endcase
      end

      // ---- D: per-pair in flight
      for (i = 0; i < 4; i = i + 1) begin
        for (o = 0; o < 4; o = o + 1) begin
          case ({(ipush[i] && spay[i][9:8] == o[1:0]),
                 (opop[o] && opay[o][9:8] == i[1:0])})
            2'b10: n_pair[i][o] <= n_pair[i][o] + 5'd1;
            2'b01: n_pair[i][o] <= n_pair[i][o] - 5'd1;
            default: n_pair[i][o] <= n_pair[i][o];
          endcase
        end
      end

      // ---- E: waits
      for (i = 0; i < 4; i = i + 1) begin
        for (o = 0; o < 4; o = o + 1) begin
          if (!(bv[i] && bdest[i] == o[1:0]) || acc_for[o][i]) begin
            wg[i][o] <= 3'd0;
            wr[i][o] <= 6'd0;
          end else begin
            if (|acc_for[o])
              wg[i][o] <= (wg[i][o] == 3'd7) ? wg[i][o] : wg[i][o] + 3'd1;
            if (!ordy[o]) wr[i][o] <= 6'd0;
            else          wr[i][o] <= (wr[i][o] == 6'h3f) ? wr[i][o]
                                                         : wr[i][o] + 6'd1;
          end
        end
      end

      if (!(|bv) || (ordy != 4'hf) || (|xacc) || (|opop)) w_prog <= 4'd0;
      else if (w_prog != 4'hf)                            w_prog <= w_prog + 4'd1;

      for (o = 0; o < 4; o = o + 1) begin
        if (sp_cnt[o] == 3'd0 || !ordy[o] || xpop[o]) w_spill[o] <= 4'd0;
        else if (w_spill[o] != 4'hf) w_spill[o] <= w_spill[o] + 4'd1;

        if (of_cnt[o] == 3'd0 || !ordy[o] || opop[o]) w_drain[o] <= 4'd0;
        else if (w_drain[o] != 4'hf) w_drain[o] <= w_drain[o] + 4'd1;
      end

      // ---- who has been asking an output continuously since its last accept
      for (o = 0; o < 4; o = o + 1) begin
        if (|acc_for[o]) begin
          prev_src[o] <= src_of[o];
          seen_o[o]   <= 1'b1;
          held[o]     <= {(bv[3] && bdest[3] == o[1:0]),
                          (bv[2] && bdest[2] == o[1:0]),
                          (bv[1] && bdest[1] == o[1:0]),
                          (bv[0] && bdest[0] == o[1:0])} & ~acc_for[o];
        end else begin
          held[o] <= held[o] & {(bv[3] && bdest[3] == o[1:0]),
                                (bv[2] && bdest[2] == o[1:0]),
                                (bv[1] && bdest[1] == o[1:0]),
                                (bv[0] && bdest[0] == o[1:0])};
        end
      end
    end
  end

  // ------------------------------------------- combinational reductions, so
  // every assertion below stays one line and one claim
  logic ok_in_head, ok_in_usage, ok_in_live;
  logic ok_sp_src, ok_sp_dat, ok_sp_occ, ok_sp_live, ok_sp_push;
  logic ok_of_src, ok_of_dat, ok_of_usage, ok_of_live;
  logic ok_pair_ref, ok_pair_bound, ok_ref_bound;
  logic ok_acc_onehot, ok_gnt_onehot, ok_acc_one_output, ok_no_over_pop;
  logic ok_usage_bound, ok_spill_bound;
  logic ok_wait_tight, ok_wait_loose, ok_wait_cycles;
  logic ok_norepeat, ok_drain, ok_spill_drain;
  logic [9:0] sum_pair, sum_stage;
  integer a, b;

  always_comb begin
    ok_in_head = 1'b1; ok_in_usage = 1'b1; ok_in_live = 1'b1;
    ok_sp_src = 1'b1; ok_sp_dat = 1'b1; ok_sp_occ = 1'b1; ok_sp_live = 1'b1;
    ok_sp_push = 1'b1;
    ok_of_src = 1'b1; ok_of_dat = 1'b1; ok_of_usage = 1'b1; ok_of_live = 1'b1;
    ok_pair_ref = 1'b1; ok_pair_bound = 1'b1; ok_ref_bound = 1'b1;
    ok_acc_onehot = 1'b1; ok_gnt_onehot = 1'b1; ok_acc_one_output = 1'b1;
    ok_no_over_pop = 1'b1;
    ok_usage_bound = 1'b1; ok_spill_bound = 1'b1;
    ok_wait_tight = 1'b1; ok_wait_loose = 1'b1; ok_wait_cycles = 1'b1;
    ok_norepeat = 1'b1; ok_drain = 1'b1; ok_spill_drain = 1'b1;
    sum_pair = 10'd0; sum_stage = 10'd0;

    for (a = 0; a < 4; a = a + 1) begin
      // A -- the input buffers
      if (bv[a]) begin
        ok_in_live = ok_in_live && (in_cnt[a] != 3'd0);
        ok_in_head = ok_in_head && (in_q[a][in_rp[a]] == bpay[a]);
      end
      ok_in_usage    = ok_in_usage && (in_cnt[a] == iusage[a]);
      ok_usage_bound = ok_usage_bound && (iusage[a] <= 3'd4) &&
                                         (ousage[a] <= 3'd4);
      ok_no_over_pop = ok_no_over_pop &&
                       (!xacc[a] || in_cnt[a] != 3'd0) &&
                       (!xpop[a] || sp_cnt[a] != 3'd0) &&
                       (!opop[a] || of_cnt[a] != 3'd0);

      // B -- the spill registers
      if (sv[a]) begin
        ok_sp_live = ok_sp_live && (sp_cnt[a] != 3'd0);
        ok_sp_src  = ok_sp_src  && (sp_q[a][sp_rp[a]][9:8] == ssrc[a]);
        ok_sp_dat  = ok_sp_dat  && (sp_q[a][sp_rp[a]][7:0] == sdat[a]);
      end
      ok_sp_occ      = ok_sp_occ &&
                       (sp_cnt[a] == ({2'd0, spa[a]} + {2'd0, spb[a]}));
      ok_spill_bound = ok_spill_bound && (sp_cnt[a] <= 3'd2);
      ok_sp_push     = ok_sp_push && ((av[a] && ar[a]) == (|acc_for[a]));

      // C -- the output buffers
      if (ov[a]) begin
        ok_of_live = ok_of_live && (of_cnt[a] != 3'd0);
        ok_of_src  = ok_of_src  && (of_q[a][of_rp[a]][9:8] == opay[a][9:8]);
        ok_of_dat  = ok_of_dat  && (of_q[a][of_rp[a]][7:0] == opay[a][7:0]);
      end
      ok_of_usage = ok_of_usage && (of_cnt[a] == ousage[a]);

      // one input per output, one output per input, one grant per arbiter
      ok_acc_onehot = ok_acc_onehot && $onehot0(acc_for[a]);
      ok_gnt_onehot = ok_gnt_onehot && $onehot0(agnt[a]);
      ok_acc_one_output = ok_acc_one_output &&
        $onehot0({acc_for[3][a], acc_for[2][a], acc_for[1][a], acc_for[0][a]});

      ok_norepeat = ok_norepeat &&
        (!((|acc_for[a]) && seen_o[a] && (src_of[a] == prev_src[a])) ||
         ((held[a] & ~acc_for[a]) == 4'd0));

      ok_spill_drain = ok_spill_drain && (w_spill[a] <= 4'd8);
      ok_drain       = ok_drain && (w_drain[a] == 4'd0);

      sum_stage = sum_stage + {7'd0, in_cnt[a]} + {7'd0, sp_cnt[a]} +
                              {7'd0, of_cnt[a]};

      for (b = 0; b < 4; b = b + 1) begin
        ok_pair_ref   = ok_pair_ref &&
                        (n_pair[a][b] == testbench.ref_count[a][b]);
        ok_pair_bound = ok_pair_bound && (n_pair[a][b] <= 5'd10);
        ok_ref_bound  = ok_ref_bound && (testbench.ref_count[a][b] <= 5'd10);
        ok_wait_tight = ok_wait_tight && (wg[a][b] <= 3'd3);
        ok_wait_loose = ok_wait_loose && (wg[a][b] <= 3'd7);
        ok_wait_cycles= ok_wait_cycles && (wr[a][b] <= 6'd24);
        sum_pair      = sum_pair + {5'd0, n_pair[a][b]};
      end
    end
  end

  // =======================================================================
  // 1 -- END-TO-END ORDERING
  // =======================================================================
  // Each input buffer presents the beats this file pushed into it, in order.
  T_ORDER_INPUT_BUFFER_HEAD_IS_SHADOW_HEAD: assert property (@(posedge clk) disable iff (rst) ok_in_head);

  // The source index the crossbar reports for an output is the input this file
  // watched it accept for that output, in the order it accepted them.
  T_ORDER_CROSSBAR_SOURCE_IS_SHADOW_SOURCE: assert property (@(posedge clk) disable iff (rst) ok_sp_src);

  // Each output buffer presents the beats the crossbar handed it, in order.
  T_ORDER_OUTPUT_BUFFER_SOURCE_IS_SHADOW_SOURCE: assert property (@(posedge clk) disable iff (rst) ok_of_src);

  // No stage ever offers a beat this file has not put into that stage.
  T_ORDER_NO_HEAD_WITHOUT_A_SHADOW_ENTRY: assert property (@(posedge clk) disable iff (rst) (ok_in_live && ok_sp_live && ok_of_live));

  // =======================================================================
  // 2 -- DATA INTEGRITY
  // =======================================================================
  T_DATA_CROSSBAR_WORD_IS_SHADOW_WORD: assert property (@(posedge clk) disable iff (rst) ok_sp_dat);

  T_DATA_OUTPUT_BUFFER_WORD_IS_SHADOW_WORD: assert property (@(posedge clk) disable iff (rst) ok_of_dat);

  T_DATA_INPUT_BUFFER_STABLE_WHILE_STALLED: assert property (@(posedge clk) disable iff (rst) (((bv[0] && !brd[0]) |=> $stable(bpay[0])) and ((bv[1] && !brd[1]) |=> $stable(bpay[1])) and ((bv[2] && !brd[2]) |=> $stable(bpay[2])) and ((bv[3] && !brd[3]) |=> $stable(bpay[3]))));

  T_DATA_CROSSBAR_OUTPUT_STABLE_WHILE_STALLED: assert property (@(posedge clk) disable iff (rst) (((sv[0] && !srd[0]) |=> ($stable(ssrc[0]) && $stable(sdat[0]))) and ((sv[1] && !srd[1]) |=> ($stable(ssrc[1]) && $stable(sdat[1]))) and ((sv[2] && !srd[2]) |=> ($stable(ssrc[2]) && $stable(sdat[2]))) and ((sv[3] && !srd[3]) |=> ($stable(ssrc[3]) && $stable(sdat[3])))));

  T_DATA_OUTPUT_STABLE_WHILE_STALLED: assert property (@(posedge clk) disable iff (rst) (((ov[0] && !ordy[0]) |=> $stable(opay[0])) and ((ov[1] && !ordy[1]) |=> $stable(opay[1])) and ((ov[2] && !ordy[2]) |=> $stable(opay[2])) and ((ov[3] && !ordy[3]) |=> $stable(opay[3]))));

  // =======================================================================
  // 3 -- UNIQUENESS / NO DUPLICATION
  // =======================================================================
  // A beat leaves its input buffer towards exactly one output.
  T_UNIQ_INPUT_ACCEPTED_FOR_ONE_OUTPUT: assert property (@(posedge clk) disable iff (rst) ok_acc_one_output);

  // No stage ever pops a beat it does not hold.
  T_UNIQ_NO_POP_WITHOUT_AN_ENTRY: assert property (@(posedge clk) disable iff (rst) ok_no_over_pop);

  // =======================================================================
  // 4 -- NO LOSS / CONSERVATION
  // =======================================================================
  T_LOSS_INPUT_USAGE_MATCHES_SHADOW: assert property (@(posedge clk) disable iff (rst) ok_in_usage);

  T_LOSS_OUTPUT_USAGE_MATCHES_SHADOW: assert property (@(posedge clk) disable iff (rst) ok_of_usage);

  T_LOSS_SPILL_OCCUPANCY_MATCHES_SHADOW: assert property (@(posedge clk) disable iff (rst) ok_sp_occ);

  // The crossbar pushes its spill register exactly when this file's own decode
  // says it took a beat for that output -- no phantom beat from a locked-in
  // arbitration decision.
  T_LOSS_SPILL_PUSH_MATCHES_ACCEPTED_INPUT: assert property (@(posedge clk) disable iff (rst) ok_sp_push);

  // Two rings built at the same two boundaries out of different code agree.
  T_LOSS_PAIR_COUNTS_MATCH_REFERENCE_RINGS: assert property (@(posedge clk) disable iff (rst) ok_pair_ref);

  // and everything in flight is sitting in one of the three buffer stages.
  T_LOSS_WHOLE_BLOCK_ACCOUNTING: assert property (@(posedge clk) disable iff (rst) (sum_pair == sum_stage));

  // =======================================================================
  // 5 -- MUTUAL EXCLUSION / ONE-HOT
  // =======================================================================
  T_MUTEX_ONE_INPUT_PER_OUTPUT: assert property (@(posedge clk) disable iff (rst) ok_acc_onehot);

  T_MUTEX_ARBITER_GRANT_ONEHOT: assert property (@(posedge clk) disable iff (rst) ok_gnt_onehot);

  // =======================================================================
  // 6 -- OCCUPANCY AND BOUNDS
  // =======================================================================
  T_BOUND_BUFFER_USAGE: assert property (@(posedge clk) disable iff (rst) ok_usage_bound);

  T_BOUND_SPILL_OCCUPANCY: assert property (@(posedge clk) disable iff (rst) ok_spill_bound);

  T_BOUND_PAIR_IN_FLIGHT: assert property (@(posedge clk) disable iff (rst) ok_pair_bound);

  T_BOUND_REFERENCE_RING_OCCUPANCY: assert property (@(posedge clk) disable iff (rst) ok_ref_bound);

  T_BOUND_SHADOW_POINTERS_TRACK_COUNTS: assert property (@(posedge clk) disable iff (rst) ((in_cnt[0] <= 3'd4) && (in_cnt[1] <= 3'd4) && (in_cnt[2] <= 3'd4) && (in_cnt[3] <= 3'd4) && (of_cnt[0] <= 3'd4) && (of_cnt[1] <= 3'd4) && (of_cnt[2] <= 3'd4) && (of_cnt[3] <= 3'd4)));

  // =======================================================================
  // 9 -- PROTOCOL CONFORMANCE
  // =======================================================================
  T_PROTO_BUFFERED_VALID_HELD_UNTIL_READY: assert property (@(posedge clk) disable iff (rst) (((bv[0] && !brd[0]) |=> bv[0]) and ((bv[1] && !brd[1]) |=> bv[1]) and ((bv[2] && !brd[2]) |=> bv[2]) and ((bv[3] && !brd[3]) |=> bv[3])));

  T_PROTO_BUFFERED_DEST_STABLE_WHILE_STALLED: assert property (@(posedge clk) disable iff (rst) (((bv[0] && !brd[0]) |=> $stable(bdest[0])) and ((bv[1] && !brd[1]) |=> $stable(bdest[1])) and ((bv[2] && !brd[2]) |=> $stable(bdest[2])) and ((bv[3] && !brd[3]) |=> $stable(bdest[3]))));

  T_PROTO_SWITCHED_VALID_HELD_UNTIL_READY: assert property (@(posedge clk) disable iff (rst) (((sv[0] && !srd[0]) |=> sv[0]) and ((sv[1] && !srd[1]) |=> sv[1]) and ((sv[2] && !srd[2]) |=> sv[2]) and ((sv[3] && !srd[3]) |=> sv[3])));

  T_PROTO_OUTPUT_VALID_HELD_UNTIL_READY: assert property (@(posedge clk) disable iff (rst) (((ov[0] && !ordy[0]) |=> ov[0]) and ((ov[1] && !ordy[1]) |=> ov[1]) and ((ov[2] && !ordy[2]) |=> ov[2]) and ((ov[3] && !ordy[3]) |=> ov[3])));

  T_PROTO_NO_PUSH_INTO_A_FULL_BUFFER: assert property (@(posedge clk) disable iff (rst) (((ipush[0] |-> in_cnt[0] <= 3'd3) and (ipush[1] |-> in_cnt[1] <= 3'd3) and (ipush[2] |-> in_cnt[2] <= 3'd3) and (ipush[3] |-> in_cnt[3] <= 3'd3)) and ((xpop[0] |-> of_cnt[0] <= 3'd3) and (xpop[1] |-> of_cnt[1] <= 3'd3) and (xpop[2] |-> of_cnt[2] <= 3'd3) and (xpop[3] |-> of_cnt[3] <= 3'd3))));

  T_PROTO_NO_PUSH_INTO_A_FULL_SPILL: assert property (@(posedge clk) disable iff (rst) (((|acc_for[0]) |-> sp_cnt[0] <= 3'd1) and ((|acc_for[1]) |-> sp_cnt[1] <= 3'd1) and ((|acc_for[2]) |-> sp_cnt[2] <= 3'd1) and ((|acc_for[3]) |-> sp_cnt[3] <= 3'd1)));

  // =======================================================================
  // 10 -- ARBITRATION FAIRNESS (counted in transfers on the contended output,
  //       because `out_ready` is a free input)
  // =======================================================================
  T_FAIR_WAIT_BOUNDED_BY_THREE_TRANSFERS: assert property (@(posedge clk) disable iff (rst) ok_wait_tight);

  T_FAIR_WAIT_BOUNDED_BY_SEVEN_TRANSFERS: assert property (@(posedge clk) disable iff (rst) ok_wait_loose);

  T_FAIR_NO_REPEAT_ACCEPT_WHILE_OTHERS_WAIT: assert property (@(posedge clk) disable iff (rst) ok_norepeat);

  // =======================================================================
  // 11 -- BOUNDED RESPONSE (cycle counters, cleared whenever that output's
  //       sink stops taking beats)
  // =======================================================================
  T_BOUNDRSP_HEAD_ACCEPTED_WHILE_SINK_TAKES: assert property (@(posedge clk) disable iff (rst) ok_wait_cycles);

  T_BOUNDRSP_OUTPUT_BUFFER_NEVER_WITHHOLDS: assert property (@(posedge clk) disable iff (rst) ok_drain);

  // =======================================================================
  // 12 -- DEADLOCK FREEDOM (global and per-output progress counters)
  // =======================================================================
  T_DEADLOCK_BLOCK_MAKES_PROGRESS: assert property (@(posedge clk) disable iff (rst) (w_prog <= 4'd8));

  T_DEADLOCK_SPILL_ALWAYS_DRAINS: assert property (@(posedge clk) disable iff (rst) ok_spill_drain);

  // =======================================================================
  // 13 -- RESET / INITIALISATION
  // =======================================================================
  T_RESET_BUFFERS_EMPTY: assert property (@(posedge clk) first |-> ((iusage[0] == 3'd0) && (iusage[1] == 3'd0) && (iusage[2] == 3'd0) && (iusage[3] == 3'd0) && (ousage[0] == 3'd0) && (ousage[1] == 3'd0) && (ousage[2] == 3'd0) && (ousage[3] == 3'd0)));

  T_RESET_SPILLS_EMPTY: assert property (@(posedge clk) first |-> (!spa[0] && !spb[0] && !spa[1] && !spb[1] && !spa[2] && !spb[2] && !spa[3] && !spb[3] && (sv == 4'd0)));

  T_RESET_ARBITERS_IDLE: assert property (@(posedge clk) first |-> ((arrq[0] == 2'd0) && (arrq[1] == 2'd0) && (arrq[2] == 2'd0) && (arrq[3] == 2'd0) && !alock[0] && !alock[1] && !alock[2] && !alock[3]));

  T_RESET_NOTHING_IN_FLIGHT: assert property (@(posedge clk) first |-> ((bv == 4'd0) && (ov == 4'd0) && (sum_pair == 10'd0)));

  // =======================================================================
  // covers -- one per category used
  // =======================================================================
  C_ORDER_ALL_FOUR_OUTPUTS_DELIVER: cover property (@(posedge clk) disable iff (rst) (opop == 4'hf));

  C_ORDER_SAME_OUTPUT_TWO_SOURCES: cover property (@(posedge clk) disable iff (rst) (opop[0] && opay[0][9:8] == 2'd0) ##[1:20] (opop[0] && opay[0][9:8] == 2'd2));

  C_DATA_NONZERO_WORD_DELIVERED: cover property (@(posedge clk) disable iff (rst) (|opop && opay[0][7:0] != 8'd0));

  C_UNIQ_TWO_OUTPUTS_TAKE_AT_ONCE: cover property (@(posedge clk) disable iff (rst) ($countones(xacc) >= 2));

  C_LOSS_EVERY_STAGE_OCCUPIED: cover property (@(posedge clk) disable iff (rst) ((in_cnt[0] != 3'd0) && (sp_cnt[0] != 3'd0) && (of_cnt[0] != 3'd0)));

  C_MUTEX_FOUR_INPUTS_ASK_ONE_OUTPUT: cover property (@(posedge clk) disable iff (rst) (bv == 4'hf && bdest[0] == 2'd0 && bdest[1] == 2'd0 && bdest[2] == 2'd0 && bdest[3] == 2'd0));

  C_BOUND_INPUT_BUFFER_FULL: cover property (@(posedge clk) disable iff (rst) (iusage[0] == 3'd4));

  C_BOUND_OUTPUT_BUFFER_FULL: cover property (@(posedge clk) disable iff (rst) (ousage[0] == 3'd4));

  C_BOUND_SPILL_FULL: cover property (@(posedge clk) disable iff (rst) (sp_cnt[0] == 3'd2));

  C_PROTO_CROSSBAR_OUTPUT_STALLED: cover property (@(posedge clk) disable iff (rst) (|(sv & ~srd)));

  C_PROTO_INPUT_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst) (|(iv & ~ird)));

  C_FAIR_LONG_WAIT: cover property (@(posedge clk) disable iff (rst) (wg[3][0] >= 3'd2));

  C_FAIR_ROTATION: cover property (@(posedge clk) disable iff (rst) (acc_for[0][0]) ##[1:20] (acc_for[0][1]) ##[1:20] (acc_for[0][2]));

  C_BOUNDRSP_HEAD_WAITED: cover property (@(posedge clk) disable iff (rst) (wr[2][1] >= 6'd6));

  C_DEADLOCK_PROGRESS_GAP: cover property (@(posedge clk) disable iff (rst) (w_prog >= 4'd2));

  C_RESET_FIRST_CYCLE: cover property (@(posedge clk) first);

endmodule

bind testbench pulp_xbar_targets u_pulp_xbar_targets (.clk(clock), .rst(reset));

`default_nettype wire
