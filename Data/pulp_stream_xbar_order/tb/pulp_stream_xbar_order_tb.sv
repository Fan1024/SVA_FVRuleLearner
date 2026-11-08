`timescale 1ns/1ps
`default_nettype none

module pulp_xbar_targets (input wire clk, input wire rst,
    input logic [3:0] iv,
    input logic [3:0] ird,
    input logic [3:0] bv,
    input logic [3:0] brd,
    input logic [3:0] sv,
    input logic [3:0] srd,
    input logic [3:0] ov,
    input logic [3:0] ordy,
    input logic [9:0] spay [0:3],
    input logic [9:0] bpay [0:3],
    input logic [1:0] bdest [0:3],
    input logic [1:0] ssrc [0:3],
    input logic [7:0] sdat [0:3],
    input logic [9:0] opay [0:3],
    input logic [2:0] iusage [0:3],
    input logic [2:0] ousage [0:3],
    input logic [3:0] agnt [0:3],
    input logic [1:0] arrq [0:3],
    input logic alock [0:3],
    input logic spa [0:3],
    input logic spb [0:3],
    input logic av [0:3],
    input logic ar [0:3],
    input logic [4:0] dut_ref_count [0:3][0:3]
);

  genvar go, gj;
  generate
    for (go = 0; go < 4; go = go + 1) begin : g_port

    end
  endgenerate

  wire [3:0] ipush = iv & ird;
  wire [3:0] xacc  = bv & brd;
  wire [3:0] xpop  = sv & srd;
  wire [3:0] opop  = ov & ordy;

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

  reg [9:0] in_q [0:3][0:3];   reg [1:0] in_wp [0:3];  reg [1:0] in_rp [0:3];
  reg [2:0] in_cnt [0:3];

  reg [9:0] sp_q [0:3][0:3];   reg [1:0] sp_wp [0:3];  reg [1:0] sp_rp [0:3];
  reg [2:0] sp_cnt [0:3];

  reg [9:0] of_q [0:3][0:3];   reg [1:0] of_wp [0:3];  reg [1:0] of_rp [0:3];
  reg [2:0] of_cnt [0:3];

  reg [4:0] n_pair [0:3][0:3];

  reg [2:0] wg   [0:3][0:3];
  reg [5:0] wr   [0:3][0:3];
  reg [3:0] w_prog;
  reg [3:0] w_spill [0:3];
  reg [3:0] w_drain [0:3];

  reg [3:0] held    [0:3];
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

      if (sv[a]) begin
        ok_sp_live = ok_sp_live && (sp_cnt[a] != 3'd0);
        ok_sp_src  = ok_sp_src  && (sp_q[a][sp_rp[a]][9:8] == ssrc[a]);
        ok_sp_dat  = ok_sp_dat  && (sp_q[a][sp_rp[a]][7:0] == sdat[a]);
      end
      ok_sp_occ      = ok_sp_occ &&
                       (sp_cnt[a] == ({2'd0, spa[a]} + {2'd0, spb[a]}));
      ok_spill_bound = ok_spill_bound && (sp_cnt[a] <= 3'd2);
      ok_sp_push     = ok_sp_push && ((av[a] && ar[a]) == (|acc_for[a]));

      if (ov[a]) begin
        ok_of_live = ok_of_live && (of_cnt[a] != 3'd0);
        ok_of_src  = ok_of_src  && (of_q[a][of_rp[a]][9:8] == opay[a][9:8]);
        ok_of_dat  = ok_of_dat  && (of_q[a][of_rp[a]][7:0] == opay[a][7:0]);
      end
      ok_of_usage = ok_of_usage && (of_cnt[a] == ousage[a]);

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
                        (n_pair[a][b] == dut_ref_count[a][b]);
        ok_pair_bound = ok_pair_bound && (n_pair[a][b] <= 5'd10);
        ok_ref_bound  = ok_ref_bound && (dut_ref_count[a][b] <= 5'd10);
        ok_wait_tight = ok_wait_tight && (wg[a][b] <= 3'd3);
        ok_wait_loose = ok_wait_loose && (wg[a][b] <= 3'd7);
        ok_wait_cycles= ok_wait_cycles && (wr[a][b] <= 6'd24);
        sum_pair      = sum_pair + {5'd0, n_pair[a][b]};
      end
    end
  end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
