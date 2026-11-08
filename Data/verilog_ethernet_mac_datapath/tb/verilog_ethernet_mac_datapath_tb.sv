`timescale 1ns/1ps
`default_nettype none

module veth_mac_targets (input wire clk, input wire rst,
    input logic src_accept,
    input logic [15:0] src_seq,
    input logic [7:0] src_plen,
    input logic src_flow,
    input logic src_busy,
    input logic [15:0] ftenv_inj,
    input logic phy_rx_dv,
    input logic phy_tx_en,
    input logic phy_tx_er,
    input logic rx_link_en,
    input logic tx_link_en,
    input logic [7:0] mrx_tdata,
    input logic mrx_tvalid,
    input logic mrx_tready,
    input logic mrx_tlast,
    input logic mrx_tuser,
    input logic rx_good,
    input logic rx_bad,
    input logic rx_ovf,
    input logic tx_good,
    input logic tx_bad,
    input logic tx_ovf,
    input logic tx_underflow,
    input logic rx_bad_fcs,
    input logic erx_hv,
    input logic erx_hr,
    input logic [47:0] erx_dest,
    input logic [47:0] erx_src,
    input logic [15:0] erx_type,
    input logic erx_pv,
    input logic erx_pr,
    input logic erx_pl,
    input logic [1:0] dm_hv,
    input logic [1:0] dm_hr,
    input logic [1:0] dm_pv,
    input logic [1:0] dm_pr,
    input logic [1:0] dm_pl,
    input logic dmx_frame,
    input logic dmx_select,
    input logic [1:0] hf_v,
    input logic [1:0] hf_r,
    input logic [15:0] hf0_seq,
    input logic [15:0] hf1_seq,
    input logic [47:0] hf0_dest,
    input logic [15:0] hf0_type,
    input logic [15:0] hf1_type,
    input logic [2:0] hf0_depth,
    input logic [2:0] hf1_depth,
    input logic [1:0] pf_v,
    input logic [1:0] pf_r,
    input logic [1:0] pf_l,
    input logic [5:0] pf0_depth,
    input logic [5:0] pf1_depth,
    input logic arb_hv,
    input logic arb_hr,
    input logic [47:0] arb_dest,
    input logic [47:0] arb_src,
    input logic [15:0] arb_type,
    input logic [7:0] arb_ptdata,
    input logic arb_pv,
    input logic arb_pr,
    input logic arb_pl,
    input logic [1:0] arb_grant,
    input logic arb_gvalid,
    input logic arb_genc,
    input logic arb_frame,
    input logic [7:0] mtx_tdata,
    input logic mtx_tvalid,
    input logic mtx_tready,
    input logic mtx_tlast,
    input logic [7:0] mon_tdata,
    input logic mon_tvalid,
    input logic mon_tlast,
    input logic mon_tuser
);

localparam [7:0]  HDR_BYTES   = 8'd14;
localparam [7:0]  MAX_PLEN    = 8'd4;
localparam [7:0]  MAX_IDX     = HDR_BYTES + MAX_PLEN - 8'd1;
localparam [15:0] CNT_MAX     = 16'hFFFF;
localparam [11:0] TMR_MAX     = 12'hFFF;

localparam [15:0] HDR_FIFO_CAP = 16'd6;
localparam [15:0] PAY_FIFO_CAP = 16'd34;
localparam [15:0] MID_CAP      = 16'd24;

localparam [11:0] N_ARBWAIT  = 12'd600;
localparam [11:0] N_MACTX    = 12'd400;
localparam [11:0] N_RXSTALL  = 12'd600;
localparam [11:0] N_PROGRESS = 12'd400;
localparam [11:0] N_E2E      = 12'd2000;

wire        mrx_beat     = mrx_tvalid && mrx_tready;

wire        erx_hdr_take = erx_hv && erx_hr;

wire        erx_pay_beat = erx_pv && erx_pr;

wire [1:0]  dm_hdr_take  = dm_hv & dm_hr;
wire [1:0]  dm_pay_beat  = dm_pv & dm_pr;
wire [1:0]  dm_pay_done  = dm_pv & dm_pr & dm_pl;

wire [1:0]  hf_take      = hf_v & hf_r;

wire [1:0]  pf_beat      = pf_v & pf_r;
wire [1:0]  pf_done      = pf_v & pf_r & pf_l;

wire        arb_hdr_take = arb_hv && arb_hr;

wire        arb_pay_beat = arb_pv && arb_pr;

wire        mtx_beat     = mtx_tvalid && mtx_tready;

reg [7:0]  mon_idx  = 8'd0;
reg [47:0] mon_dest = 48'd0;
reg [47:0] mon_src  = 48'd0;
reg [15:0] mon_type = 16'd0;

always @(posedge clk) begin
    if (rst) begin
        mon_idx  <= 8'd0;
        mon_dest <= 48'd0;
        mon_src  <= 48'd0;
        mon_type <= 16'd0;
    end else if (mon_tvalid) begin
        if (mon_idx <= 8'd5)
            mon_dest <= {mon_dest[39:0], mon_tdata};
        else if (mon_idx <= 8'd11)
            mon_src  <= {mon_src[39:0], mon_tdata};
        else if (mon_idx <= 8'd13)
            mon_type <= {mon_type[7:0], mon_tdata};
        mon_idx <= mon_tlast ? 8'd0 : mon_idx + 8'd1;
    end
end

wire        mon_in_payload = mon_tvalid && (mon_idx >= HDR_BYTES);
wire [15:0] mon_seq   = mon_dest[15:0];
wire [7:0]  mon_seqlo = mon_dest[7:0];
wire [7:0]  mon_plen  = mon_src[15:8];
wire        mon_flow  = mon_type[0];
wire        mon_done  = mon_tvalid && mon_tlast && (mon_idx >= HDR_BYTES);

wire [7:0]  mon_expect = mon_seqlo ^ (mon_idx - (HDR_BYTES - 8'd1)) ^ 8'hA5;

reg [15:0] mon_last_seq [0:1];
reg [1:0]  mon_seen   = 2'b00;
reg [15:0] mon_seq_max = 16'd0;

always @(posedge clk) begin
    if (rst) begin
        mon_last_seq[0] <= 16'd0;
        mon_last_seq[1] <= 16'd0;
        mon_seen        <= 2'b00;
        mon_seq_max     <= 16'd0;
    end else if (mon_done) begin
        mon_last_seq[mon_flow] <= mon_seq;
        mon_seen[mon_flow]     <= 1'b1;
        if (mon_seq > mon_seq_max) mon_seq_max <= mon_seq;
    end
end

reg [15:0] erx_last_seq = 16'd0;
reg        erx_seen     = 1'b0;
reg [15:0] hf_last_seq [0:1];
reg [1:0]  hf_seen      = 2'b00;

always @(posedge clk) begin
    if (rst) begin
        erx_last_seq <= 16'd0;
        erx_seen     <= 1'b0;
        hf_last_seq[0] <= 16'd0;
        hf_last_seq[1] <= 16'd0;
        hf_seen        <= 2'b00;
    end else begin
        if (erx_hdr_take) begin
            erx_last_seq <= erx_dest[15:0];
            erx_seen     <= 1'b1;
        end
        if (hf_take[0]) begin
            hf_last_seq[0] <= hf0_seq;
            hf_seen[0]     <= 1'b1;
        end
        if (hf_take[1]) begin
            hf_last_seq[1] <= hf1_seq;
            hf_seen[1]     <= 1'b1;
        end
    end
end

reg [15:0] n_src       = 16'd0;
reg [15:0] n_rx_good   = 16'd0;
reg [15:0] n_rx_bad    = 16'd0;
reg [15:0] n_rx_ovf    = 16'd0;
reg [15:0] n_rxaxis    = 16'd0;
reg [15:0] n_mon       = 16'd0;

reg [15:0] n_hdr_in  [0:1];
reg [15:0] n_hdr_out [0:1];
reg [15:0] n_pay_in  [0:1];
reg [15:0] n_pay_out [0:1];
reg [15:0] n_pb_in   [0:1];
reg [15:0] n_pb_out  [0:1];

integer f;

always @(posedge clk) begin
    if (rst) begin
        n_src <= 16'd0;  n_rx_good <= 16'd0;  n_rx_bad <= 16'd0;
        n_rx_ovf <= 16'd0;  n_rxaxis <= 16'd0;  n_mon <= 16'd0;
        for (f = 0; f < 2; f = f + 1) begin
            n_hdr_in[f]  <= 16'd0;  n_hdr_out[f] <= 16'd0;
            n_pay_in[f]  <= 16'd0;  n_pay_out[f] <= 16'd0;
            n_pb_in[f]   <= 16'd0;  n_pb_out[f]  <= 16'd0;
        end
    end else begin
        if (src_accept && n_src != CNT_MAX)                 n_src     <= n_src + 16'd1;
        if (rx_good   && n_rx_good != CNT_MAX)              n_rx_good <= n_rx_good + 16'd1;
        if (rx_bad    && n_rx_bad != CNT_MAX)               n_rx_bad  <= n_rx_bad + 16'd1;
        if (rx_ovf    && n_rx_ovf != CNT_MAX)               n_rx_ovf  <= n_rx_ovf + 16'd1;
        if (mrx_beat && mrx_tlast && n_rxaxis != CNT_MAX)   n_rxaxis  <= n_rxaxis + 16'd1;
        if (mon_done && n_mon != CNT_MAX)                   n_mon     <= n_mon + 16'd1;

        for (f = 0; f < 2; f = f + 1) begin
            if (dm_hdr_take[f] && n_hdr_in[f]  != CNT_MAX) n_hdr_in[f]  <= n_hdr_in[f]  + 16'd1;
            if (hf_take[f]     && n_hdr_out[f] != CNT_MAX) n_hdr_out[f] <= n_hdr_out[f] + 16'd1;
            if (dm_pay_done[f] && n_pay_in[f]  != CNT_MAX) n_pay_in[f]  <= n_pay_in[f]  + 16'd1;
            if (pf_done[f]     && n_pay_out[f] != CNT_MAX) n_pay_out[f] <= n_pay_out[f] + 16'd1;
            if (dm_pay_beat[f] && n_pb_in[f]   != CNT_MAX) n_pb_in[f]   <= n_pb_in[f]   + 16'd1;
            if (pf_beat[f]     && n_pb_out[f]  != CNT_MAX) n_pb_out[f]  <= n_pb_out[f]  + 16'd1;
        end
    end
end

wire progress =
      mrx_beat || erx_hdr_take || erx_pay_beat || (|dm_pay_beat)
   || (|hf_take) || (|pf_beat) || arb_hdr_take || arb_pay_beat
   || mtx_beat || mon_tvalid || phy_tx_en || phy_rx_dv;

wire work_outstanding = (n_rxaxis != n_mon);

reg [11:0] w_hf_wait [0:1];
reg [11:0] w_mactx   = 12'd0;
reg [11:0] w_rxstall = 12'd0;
reg [11:0] w_prog    = 12'd0;
reg [11:0] w_e2e     = 12'd0;

always @(posedge clk) begin
    if (rst) begin
        w_hf_wait[0] <= 12'd0;
        w_hf_wait[1] <= 12'd0;
        w_mactx   <= 12'd0;
        w_rxstall <= 12'd0;
        w_prog    <= 12'd0;
        w_e2e     <= 12'd0;
    end else begin
        for (f = 0; f < 2; f = f + 1) begin
            if (hf_v[f] && !hf_r[f]) begin
                if (w_hf_wait[f] != TMR_MAX) w_hf_wait[f] <= w_hf_wait[f] + 12'd1;
            end else begin
                w_hf_wait[f] <= 12'd0;
            end
        end

        if (mtx_tvalid && !mtx_tready) begin
            if (w_mactx != TMR_MAX) w_mactx <= w_mactx + 12'd1;
        end else begin
            w_mactx <= 12'd0;
        end

        if (mrx_tvalid && !mrx_tready) begin
            if (w_rxstall != TMR_MAX) w_rxstall <= w_rxstall + 12'd1;
        end else begin
            w_rxstall <= 12'd0;
        end

        if (work_outstanding && !progress) begin
            if (w_prog != TMR_MAX) w_prog <= w_prog + 12'd1;
        end else begin
            w_prog <= 12'd0;
        end

        if (work_outstanding && !mon_done) begin
            if (w_e2e != TMR_MAX) w_e2e <= w_e2e + 12'd1;
        end else begin
            w_e2e <= 12'd0;
        end
    end
end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
