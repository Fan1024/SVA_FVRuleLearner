`timescale 1ns/1ps
`default_nettype none

module axis_arb_targets (input wire clock, input wire reset,
    input logic [3:0] in_valid,
    input logic [31:0] in_data,
    input logic [3:0] in_ready,
    input logic [3:0] in_last,
    input logic [3:0] in_push,
    input logic [3:0] fv_valid,
    input logic [3:0] fv_ready,
    input logic [31:0] fv_data,
    input logic [3:0] fv_last,
    input logic mux_val,
    input logic mux_rdy,
    input logic [7:0] mux_dat,
    input logic mux_lst,
    input logic [2:0] mux_tid,
    input logic out_val,
    input logic out_rdy,
    input logic [7:0] out_dat,
    input logic out_lst,
    input logic [2:0] out_tid,
    input logic [4:0] out_depth,
    input logic [3:0] grant,
    input logic grant_val,
    input logic [1:0] grant_enc,
    input logic [3:0] hold_val,
    input logic [31:0] hold_dat,
    input logic [3:0] hold_lst,
    input logic temp_val,
    input logic [2:0] temp_tid,
    input logic [4:0] o_wr,
    input logic [4:0] o_rd,
    input logic [1:0] o_pipe,
    input logic [3:0] o_ofw,
    input logic [3:0] o_ofr,
    input logic o_oval,
    input logic [3:0] f_wr [0:3],
    input logic [3:0] f_rd [0:3],
    input logic [1:0] f_pipe [0:3],
    input logic [3:0] f_ofw [0:3],
    input logic [3:0] f_ofr [0:3],
    input logic f_oval [0:3],
    input logic [3:0] f_depth [0:3]
);

    localparam integer SRC       = 4;
    localparam integer S1_DEPTH  = 16;
    localparam integer S2_DEPTH  = 64;

    localparam [7:0] N_FAIR_LOOSE = 8'd24;
    localparam [7:0] N_FAIR_TIGHT = 8'd16;
    localparam [7:0] N_MUX_STALL  = 8'd24;
    localparam [7:0] N_OUT_STALL  = 8'd16;
    localparam [7:0] N_NO_MOVE    = 8'd24;
    localparam [7:0] CTR_MAX      = 8'd255;

    wire        mux_fire = mux_val && mux_rdy;
    wire [1:0]  mux_src  = mux_tid[2:1];

    wire        out_fire = out_val && out_rdy;
    wire [1:0]  out_src  = out_tid[2:1];

    wire [1:0]  temp_src = temp_tid[2:1];

    genvar g;
    generate
        for (g = 0; g < SRC; g = g + 1) begin : g_fifo

        end
    endgenerate

    reg [7:0]  s1_dat [0:SRC-1][0:S1_DEPTH-1];
    reg        s1_lst [0:SRC-1][0:S1_DEPTH-1];
    reg [3:0]  s1_wr  [0:SRC-1];
    reg [3:0]  s1_rd  [0:SRC-1];
    reg [4:0]  s1_occ [0:SRC-1];

    reg [7:0]  s2_dat [0:S2_DEPTH-1];
    reg        s2_lst [0:S2_DEPTH-1];
    reg [2:0]  s2_tid [0:S2_DEPTH-1];
    reg [5:0]  s2_wr;
    reg [5:0]  s2_rd;
    reg [6:0]  s2_occ;

    reg [15:0] in_cnt  [0:SRC-1];
    reg [15:0] out_cnt [0:SRC-1];

    reg        mux_fr_active;
    reg [1:0]  mux_fr_src;
    reg [2:0]  mux_fr_pos;
    reg        out_fr_active;
    reg [1:0]  out_fr_src;
    reg [2:0]  out_fr_pos;

    reg [7:0]  fair_ctr [0:SRC-1];
    reg [7:0]  mux_stall_ctr;
    reg [7:0]  out_stall_ctr;
    reg [7:0]  no_move_ctr;
    reg [7:0]  all_full_ctr;

    reg [3:0]  f_fill_q [0:SRC-1];
    reg [4:0]  o_fill_q;
    reg        after_reset;
    reg        seen_all_sources;
    reg [3:0]  seen_src;

    wire [1:0] mux_pend [0:SRC-1];
    generate
        for (g = 0; g < SRC; g = g + 1) begin : g_pend
            assign mux_pend[g] = {1'b0, (mux_val  && (mux_src  == g[1:0]))} +
                                 {1'b0, (temp_val && (temp_src == g[1:0]))};
        end
    endgenerate

    reg        hold_bad;
    reg        fifo_head_bad;
    reg        acct_bad;
    reg        occ_bad;
    reg        fill_bad;
    reg        skid_bad;
    reg        stable_bad;
    reg        cnt_bad;
    reg        depth_bad;
    reg        ready_bad;
    reg        all_full;
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

                if (!fv_valid[u] || (mux_fire && (mux_src == u[1:0])))
                    fair_ctr[u] <= 8'd0;
                else if (mux_fire && (fair_ctr[u] != CTR_MAX))
                    fair_ctr[u] <= fair_ctr[u] + 8'd1;
            end

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

            if (!(grant_val && (s1_occ[grant_enc] != 5'd0)) || !mux_rdy
                    || mux_fire)
                mux_stall_ctr <= 8'd0;
            else if (mux_stall_ctr != CTR_MAX)
                mux_stall_ctr <= mux_stall_ctr + 8'd1;

            if ((s2_occ == 7'd0) || !out_rdy || out_fire)
                out_stall_ctr <= 8'd0;
            else if (out_stall_ctr != CTR_MAX)
                out_stall_ctr <= out_stall_ctr + 8'd1;

            if (!((s2_occ != 7'd0) ||
                  (grant_val && (s1_occ[grant_enc] != 5'd0)))
                    || !out_rdy || (|in_push) || mux_fire || out_fire)
                no_move_ctr <= 8'd0;
            else if (no_move_ctr != CTR_MAX)
                no_move_ctr <= no_move_ctr + 8'd1;

            if (!all_full || !out_rdy || mux_fire)
                all_full_ctr <= 8'd0;
            else if (all_full_ctr != CTR_MAX)
                all_full_ctr <= all_full_ctr + 8'd1;
        end
    end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
