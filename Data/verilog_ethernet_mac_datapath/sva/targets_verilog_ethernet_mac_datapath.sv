// ===========================================================================
// Candidate target assertions for the verilog-ethernet 1G MAC transmit /
// receive datapath.
//
// Bound into `verilog_ethernet_mac_datapath_ft`, so every reference below is a
// hierarchical name from that top.  Nothing here is an assumption.
//
// THE ORACLE IS A FUNCTION, NOT A COPY OF THE DESIGN.  Every byte the
// environment injects is a function of a 16-bit sequence number, and the
// sequence number travels inside the frame:
//
//     dest_mac = 48'hDADADADA_0000 | seq
//     src_mac  = 48'h5A5A5A5A_0000 | (plen << 8) | (~seq[7:0])
//     eth_type = 16'h0800 | flow
//     payload byte at frame index i (i >= 14) = seq[7:0] ^ (i-13) ^ 8'hA5
//
// So the checker can recompute the ENTIRE frame from the header it reads at
// the far end.  It never reads a fifo, a pointer or a state register of the
// design to decide what the answer should be.  Four consequences, and they are
// the four hardest candidates in this file:
//
//   1. `T_DATA_MON_PAYLOAD_BYTE` compares every transmitted payload byte with
//      a function of the DEST MAC of the same frame.  The dest MAC came
//      through the 112-bit header fifo of its flow; the payload byte came
//      through the 8-bit payload fifo of the same flow.  Those two fifos have
//      different depths, different units and no shared pointer.  Proving this
//      needs an invariant that ties the two fifo occupancies together across
//      `eth_demux`, `eth_arb_mux` and `eth_axis_tx`.
//   2. `T_DATA_MON_SEQ_COMPLEMENT` says the two halves of the header agree.
//      They are 5 bytes apart on the wire and travel together, so this is the
//      cheap version of the same obligation.
//   3. `T_ORDER_MON_FLOW*_SEQ_INCREASING` says per-flow order survives the
//      whole chain -- three store-and-forward buffers and a round-robin
//      arbiter.  Global order does NOT survive, and `C_ORDER_GLOBAL_INVERTED`
//      is the cover that shows it.
//   4. `T_UNIQ_MON_COUNT_LE_MAX_SEQ` says the number of frames delivered never
//      exceeds the number of distinct sequence numbers that can have been
//      delivered.  That is duplication, stated as a counting fact.
//
// The two counting families -- `n_*` frame counters and `w_*` saturating wait
// timers -- are this file's own registers.  The timers are how fairness,
// bounded response and deadlock are written as SAFETY properties.  There is no
// `s_eventually`, no `F` and no `G F` anywhere in this package.
//
// Every constant the checker uses (`0xDA`, `0x5A`, `0xA5`, 14 header bytes,
// the two ethertypes) is the FORMAL TOP's, declared in `veth_frame_src`.  None
// of them is the design's.
// ===========================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module veth_mac_targets (input wire clk, input wire rst);

// ------------------------------------------------------------------ sizes --
localparam [7:0]  HDR_BYTES   = 8'd14;   // Ethernet header, dest+src+type
localparam [7:0]  MAX_PLEN    = 8'd4;    // veth_frame_src: 1..4 payload bytes
localparam [7:0]  MAX_IDX     = HDR_BYTES + MAX_PLEN - 8'd1;   // 17
localparam [15:0] CNT_MAX     = 16'hFFFF;
localparam [11:0] TMR_MAX     = 12'hFFF;

localparam [15:0] HDR_FIFO_CAP = 16'd6;   // DEPTH 4 + RAM_PIPELINE(1) + output
localparam [15:0] PAY_FIFO_CAP = 16'd34;  // DEPTH 32 + RAM_PIPELINE(1) + output
localparam [15:0] MID_CAP      = 16'd24;  // frames between rx_axis and the wire

// Hand-chosen bounds.  These are ESTIMATES from counting handshakes along the
// chain, not measurements -- see PROVENANCE.md.  A gmii byte costs up to four
// cycles (`veth_bounded_stall` allows three consecutive stalls), a frame on
// the wire is 8 preamble + 15..18 data + 4 fcs + 12 ifg = 39..42 byte times,
// so one frame occupies the transmit link for at most ~170 cycles.
localparam [11:0] N_ARBWAIT  = 12'd600;   // header at a fifo head, not granted
localparam [11:0] N_MACTX    = 12'd400;   // eth_axis_tx offered, mac not ready
localparam [11:0] N_RXSTALL  = 12'd600;   // mac rx fifo offered, chain not ready
localparam [11:0] N_PROGRESS = 12'd400;   // no boundary event while work is in
localparam [11:0] N_E2E      = 12'd2000;  // rx_axis frame -> the same count out

// ================================================================== taps ===

// -- the environment's injection point --------------------------------------
wire        src_accept   = verilog_ethernet_mac_datapath_ft.src_frame_accepted;
wire [15:0] src_seq      = verilog_ethernet_mac_datapath_ft.src_seq;
wire [7:0]  src_plen     = verilog_ethernet_mac_datapath_ft.src_plen;
wire        src_flow     = verilog_ethernet_mac_datapath_ft.src_flow;
wire        src_busy     = verilog_ethernet_mac_datapath_ft.src_busy;
wire [15:0] ftenv_inj    = verilog_ethernet_mac_datapath_ft.ftenv_injected;

// -- the two gmii links -----------------------------------------------------
wire        phy_rx_dv    = verilog_ethernet_mac_datapath_ft.phy_rx_dv;
wire        phy_tx_en    = verilog_ethernet_mac_datapath_ft.phy_tx_en;
wire        phy_tx_er    = verilog_ethernet_mac_datapath_ft.phy_tx_er;
wire        rx_link_en   = verilog_ethernet_mac_datapath_ft.rx_link_en;
wire        tx_link_en   = verilog_ethernet_mac_datapath_ft.tx_link_en;

// -- the mac's rx axi-stream, after buffer 1 --------------------------------
wire [7:0]  mrx_tdata    = verilog_ethernet_mac_datapath_ft.mac_rx_tdata;
wire        mrx_tvalid   = verilog_ethernet_mac_datapath_ft.mac_rx_tvalid;
wire        mrx_tready   = verilog_ethernet_mac_datapath_ft.mac_rx_tready;
wire        mrx_tlast    = verilog_ethernet_mac_datapath_ft.mac_rx_tlast;
wire        mrx_tuser    = verilog_ethernet_mac_datapath_ft.mac_rx_tuser;
wire        mrx_beat     = mrx_tvalid && mrx_tready;

// -- the mac's frame accounting outputs -------------------------------------
wire        rx_good      = verilog_ethernet_mac_datapath_ft.rx_fifo_good_frame;
wire        rx_bad       = verilog_ethernet_mac_datapath_ft.rx_fifo_bad_frame;
wire        rx_ovf       = verilog_ethernet_mac_datapath_ft.rx_fifo_overflow;
wire        tx_good      = verilog_ethernet_mac_datapath_ft.tx_fifo_good_frame;
wire        tx_bad       = verilog_ethernet_mac_datapath_ft.tx_fifo_bad_frame;
wire        tx_ovf       = verilog_ethernet_mac_datapath_ft.tx_fifo_overflow;
wire        tx_underflow = verilog_ethernet_mac_datapath_ft.tx_error_underflow;
wire        rx_bad_fcs   = verilog_ethernet_mac_datapath_ft.rx_error_bad_fcs;

// -- eth_axis_rx: the header/payload split ----------------------------------
wire        erx_hv       = verilog_ethernet_mac_datapath_ft.erx_hdr_valid;
wire        erx_hr       = verilog_ethernet_mac_datapath_ft.erx_hdr_ready;
wire [47:0] erx_dest     = verilog_ethernet_mac_datapath_ft.erx_dest_mac;
wire [47:0] erx_src      = verilog_ethernet_mac_datapath_ft.erx_src_mac;
wire [15:0] erx_type     = verilog_ethernet_mac_datapath_ft.erx_type;
wire        erx_hdr_take = erx_hv && erx_hr;
wire        erx_pv       = verilog_ethernet_mac_datapath_ft.erx_pay_tvalid;
wire        erx_pr       = verilog_ethernet_mac_datapath_ft.erx_pay_tready;
wire        erx_pl       = verilog_ethernet_mac_datapath_ft.erx_pay_tlast;
wire        erx_pay_beat = erx_pv && erx_pr;

// -- eth_demux outputs, one pair per flow -----------------------------------
wire [1:0]  dm_hv        = verilog_ethernet_mac_datapath_ft.dm_hdr_valid;
wire [1:0]  dm_hr        = verilog_ethernet_mac_datapath_ft.dm_hdr_ready;
wire [1:0]  dm_pv        = verilog_ethernet_mac_datapath_ft.dm_pay_tvalid;
wire [1:0]  dm_pr        = verilog_ethernet_mac_datapath_ft.dm_pay_tready;
wire [1:0]  dm_pl        = verilog_ethernet_mac_datapath_ft.dm_pay_tlast;
wire [1:0]  dm_hdr_take  = dm_hv & dm_hr;
wire [1:0]  dm_pay_beat  = dm_pv & dm_pr;
wire [1:0]  dm_pay_done  = dm_pv & dm_pr & dm_pl;
wire        dmx_frame    = verilog_ethernet_mac_datapath_ft.u_demux.frame_reg;
wire        dmx_select   = verilog_ethernet_mac_datapath_ft.u_demux.select_reg;

// -- buffer 2: the header fifos and the payload fifos -----------------------
wire [1:0]  hf_v         = verilog_ethernet_mac_datapath_ft.hf_out_valid;
wire [1:0]  hf_r         = verilog_ethernet_mac_datapath_ft.hf_out_ready;
wire [1:0]  hf_take      = hf_v & hf_r;
wire [15:0] hf0_seq      = verilog_ethernet_mac_datapath_ft.hf_dest_mac[0 +: 16];
wire [15:0] hf1_seq      = verilog_ethernet_mac_datapath_ft.hf_dest_mac[48 +: 16];
wire [47:0] hf0_dest     = verilog_ethernet_mac_datapath_ft.hf_dest_mac[0 +: 48];
wire [15:0] hf0_type     = verilog_ethernet_mac_datapath_ft.hf_type[0 +: 16];
wire [15:0] hf1_type     = verilog_ethernet_mac_datapath_ft.hf_type[16 +: 16];
wire [2:0]  hf0_depth    = verilog_ethernet_mac_datapath_ft.hf_depth[0 +: 3];
wire [2:0]  hf1_depth    = verilog_ethernet_mac_datapath_ft.hf_depth[3 +: 3];

wire [1:0]  pf_v         = verilog_ethernet_mac_datapath_ft.pf_tvalid;
wire [1:0]  pf_r         = verilog_ethernet_mac_datapath_ft.pf_tready;
wire [1:0]  pf_l         = verilog_ethernet_mac_datapath_ft.pf_tlast;
wire [1:0]  pf_beat      = pf_v & pf_r;
wire [1:0]  pf_done      = pf_v & pf_r & pf_l;
wire [5:0]  pf0_depth    = verilog_ethernet_mac_datapath_ft.pf_depth[0 +: 6];
wire [5:0]  pf1_depth    = verilog_ethernet_mac_datapath_ft.pf_depth[6 +: 6];

// -- eth_arb_mux ------------------------------------------------------------
wire        arb_hv       = verilog_ethernet_mac_datapath_ft.arb_hdr_valid;
wire        arb_hr       = verilog_ethernet_mac_datapath_ft.arb_hdr_ready;
wire [47:0] arb_dest     = verilog_ethernet_mac_datapath_ft.arb_dest_mac;
wire [47:0] arb_src      = verilog_ethernet_mac_datapath_ft.arb_src_mac;
wire [15:0] arb_type     = verilog_ethernet_mac_datapath_ft.arb_type;
wire        arb_hdr_take = arb_hv && arb_hr;
wire [7:0]  arb_ptdata   = verilog_ethernet_mac_datapath_ft.arb_pay_tdata;
wire        arb_pv       = verilog_ethernet_mac_datapath_ft.arb_pay_tvalid;
wire        arb_pr       = verilog_ethernet_mac_datapath_ft.arb_pay_tready;
wire        arb_pl       = verilog_ethernet_mac_datapath_ft.arb_pay_tlast;
wire        arb_pay_beat = arb_pv && arb_pr;
wire [1:0]  arb_grant    = verilog_ethernet_mac_datapath_ft.u_arb.grant;
wire        arb_gvalid   = verilog_ethernet_mac_datapath_ft.u_arb.grant_valid;
wire        arb_genc     = verilog_ethernet_mac_datapath_ft.u_arb.grant_encoded;
wire        arb_frame    = verilog_ethernet_mac_datapath_ft.u_arb.frame_reg;

// -- eth_axis_tx into the mac, before buffer 3 ------------------------------
wire [7:0]  mtx_tdata    = verilog_ethernet_mac_datapath_ft.mac_tx_tdata;
wire        mtx_tvalid   = verilog_ethernet_mac_datapath_ft.mac_tx_tvalid;
wire        mtx_tready   = verilog_ethernet_mac_datapath_ft.mac_tx_tready;
wire        mtx_tlast    = verilog_ethernet_mac_datapath_ft.mac_tx_tlast;
wire        mtx_beat     = mtx_tvalid && mtx_tready;

// -- the monitor receiver on the transmitted link: the far observation point -
wire [7:0]  mon_tdata    = verilog_ethernet_mac_datapath_ft.mon_tdata;
wire        mon_tvalid   = verilog_ethernet_mac_datapath_ft.mon_tvalid;
wire        mon_tlast    = verilog_ethernet_mac_datapath_ft.mon_tlast;
wire        mon_tuser    = verilog_ethernet_mac_datapath_ft.mon_tuser;

// ============================== the oracle: a frame parser and a function ===
// The checker re-parses the transmitted link for itself.  It reuses NOTHING
// from `eth_axis_rx`: its own byte counter, its own header registers.
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

// Complete for the frame in progress from index 14 onwards.
wire        mon_in_payload = mon_tvalid && (mon_idx >= HDR_BYTES);
wire [15:0] mon_seq   = mon_dest[15:0];
wire [7:0]  mon_seqlo = mon_dest[7:0];
wire [7:0]  mon_plen  = mon_src[15:8];
wire        mon_flow  = mon_type[0];
wire        mon_done  = mon_tvalid && mon_tlast && (mon_idx >= HDR_BYTES);

// THE reference: what byte must be at frame index `mon_idx` of a frame whose
// dest mac low byte is `mon_seqlo`.  Identical to `veth_frame_src.veth_byte`
// for the payload range, recomputed here and not read from anywhere.
wire [7:0]  mon_expect = mon_seqlo ^ (mon_idx - (HDR_BYTES - 8'd1)) ^ 8'hA5;

// -- per-flow delivery history ----------------------------------------------
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

// -- the same trick one stage earlier, at eth_axis_rx and at the header fifos
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

// ============================ counting oracles =============================
reg [15:0] n_src       = 16'd0;   // frames handed to the receive link
reg [15:0] n_rx_good   = 16'd0;   // frames the rx frame-fifo committed
reg [15:0] n_rx_bad    = 16'd0;   // frames it dropped for a bad fcs
reg [15:0] n_rx_ovf    = 16'd0;   // frames it dropped because it was full
reg [15:0] n_rxaxis    = 16'd0;   // frames that left the rx fifo
reg [15:0] n_mon       = 16'd0;   // frames the far end delivered

reg [15:0] n_hdr_in  [0:1];       // headers pushed into each header fifo
reg [15:0] n_hdr_out [0:1];       // headers pulled out of it
reg [15:0] n_pay_in  [0:1];       // payload FRAMES pushed into each payload fifo
reg [15:0] n_pay_out [0:1];       // payload frames pulled out of it
reg [15:0] n_pb_in   [0:1];       // payload BYTES pushed in
reg [15:0] n_pb_out  [0:1];       // payload bytes pulled out

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

// ============================ saturating wait timers ========================
// Liveness, written as bounded safety.  Each timer counts CONSECUTIVE cycles
// of a blocked condition and is cleared the moment the condition clears; the
// candidate is an upper bound on the timer.
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

// ===========================================================================
// CANDIDATE TARGETS
// ===========================================================================

// -------------------------------------------------- 1. end-to-end ordering --

// ORACLE: `veth_frame_src` increments `seq` by one per frame and never
// reissues one, `eth_demux` sends a frame to exactly one flow and both fifos
// on that flow are in-order, so the sequence numbers arriving at the far end
// on one flow must be strictly increasing.  Frames LOST in the mac rx fifo
// only remove entries from that sequence, which cannot break monotonicity.
T_ORDER_MON_FLOW0_SEQ_INCREASING: assert property (@(posedge clk) disable iff (rst)
    (mon_done && mon_flow == 1'b0 && mon_seen[0]) |-> mon_seq > mon_last_seq[0]);

T_ORDER_MON_FLOW1_SEQ_INCREASING: assert property (@(posedge clk) disable iff (rst)
    (mon_done && mon_flow == 1'b1 && mon_seen[1]) |-> mon_seq > mon_last_seq[1]);

// ORACLE: nothing between the receive link and `eth_axis_rx` reorders -- the
// rx frame fifo is a single queue -- so GLOBAL order is still intact here.
// It stops being intact after the arbiter, which is what
// `C_ORDER_GLOBAL_INVERTED` shows.
T_ORDER_ERX_HDR_SEQ_INCREASING: assert property (@(posedge clk) disable iff (rst)
    (erx_hdr_take && erx_seen) |-> erx_dest[15:0] > erx_last_seq);

// ORACLE: one header fifo per flow, written by the demux in arrival order and
// read by the arbiter, is a queue: what comes out of it is in the order it
// went in.
T_ORDER_HDRFIFO0_SEQ_INCREASING: assert property (@(posedge clk) disable iff (rst)
    (hf_take[0] && hf_seen[0]) |-> hf0_seq > hf_last_seq[0]);

// ---------------------------------------------------------- 2. data integrity

// ORACLE: the payload byte at frame index i is `seq[7:0] ^ (i-13) ^ 8'hA5` by
// construction in `veth_frame_src`, and `seq[7:0]` is the low byte of the dest
// mac of the SAME frame.  The dest mac travelled through the 112-bit header
// fifo; the payload byte travelled through the 8-bit payload fifo.  This is
// the end-to-end obligation of the whole cut.
T_DATA_MON_PAYLOAD_BYTE: assert property (@(posedge clk) disable iff (rst)
    mon_in_payload |-> mon_tdata == mon_expect);

// ORACLE: the top four bytes of the dest mac are a constant of the generator.
// A header that has been corrupted, truncated or mixed with another frame's
// shows up here.
T_DATA_MON_DEST_PREFIX: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> mon_dest[47:16] == 32'hDADADADA);

T_DATA_MON_SRC_PREFIX: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> mon_src[47:16] == 32'h5A5A5A5A);

// ORACLE: the generator writes `seq[7:0]` at wire byte 5 and `~seq[7:0]` at
// wire byte 11.  Six bytes apart, so a header assembled out of two different
// frames breaks this even when both frames are individually well formed.
T_DATA_MON_SEQ_COMPLEMENT: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> mon_src[7:0] == ~mon_dest[7:0]);

// ORACLE: the ethertype is 16'h0800 or 16'h0801 and nothing else.
T_DATA_MON_TYPE_PREFIX: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> mon_type[15:1] == 15'h0400);

// ORACLE: the generator writes the payload length into src_mac[15:8], so the
// frame carries its own length.  The transmitted frame must be exactly that
// long -- 14 header bytes plus `plen`.
T_DATA_MON_LENGTH_MATCHES_HEADER: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> mon_idx == (HDR_BYTES - 8'd1) + mon_plen);

// ORACLE: `axis_gmii_tx` inside the mac recomputes the FCS over whatever it is
// given, and the monitor `axis_gmii_rx` checks it.  tuser at tlast means the
// received frame failed its own fcs or saw gmii_tx_er, either of which means
// the transmit path emitted a frame no receiver would keep.
T_DATA_MON_FCS_GOOD: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> !mon_tuser);

// ORACLE: the same header well-formedness, one stage after the mac rx fifo.
// If it fails here and not at the monitor, the fault is in the receive half.
T_DATA_ERX_HDR_WELL_FORMED: assert property (@(posedge clk) disable iff (rst)
    erx_hdr_take |-> (erx_dest[47:16] == 32'hDADADADA
                   && erx_src[47:16]  == 32'h5A5A5A5A
                   && erx_src[7:0]    == ~erx_dest[7:0]));

// ------------------------------------------------ 3. uniqueness / no duplicate

// ORACLE: sequence numbers are handed out 0,1,2,... one per frame, so after
// `k` distinct sequence numbers have been delivered the largest of them is at
// least `k-1`.  Delivering a frame twice makes the count exceed the largest
// sequence number plus one.  This is duplication stated as arithmetic.
T_UNIQ_MON_COUNT_LE_MAX_SEQ: assert property (@(posedge clk) disable iff (rst)
    n_mon <= mon_seq_max + 16'd1);

// ORACLE: a fifo cannot emit more items than it was given.
T_UNIQ_HDRFIFO0_OUT_LE_IN: assert property (@(posedge clk) disable iff (rst)
    n_hdr_out[0] <= n_hdr_in[0]);

T_UNIQ_PAYFIFO0_OUT_LE_IN: assert property (@(posedge clk) disable iff (rst)
    n_pb_out[0] <= n_pb_in[0]);

// ORACLE: nothing between the rx fifo output and the wire creates a frame.
T_UNIQ_MON_FRAMES_LE_RXAXIS: assert property (@(posedge clk) disable iff (rst)
    n_mon <= n_rxaxis);

// --------------------------------------------------- 4. no loss / conservation

// ORACLE: the only source of frames is `veth_frame_src`.
T_CONSERV_MON_LE_INJECTED: assert property (@(posedge clk) disable iff (rst)
    n_mon <= n_src);

// ORACLE: the rx frame fifo delivers only frames it committed.
T_CONSERV_RXAXIS_LE_RXGOOD: assert property (@(posedge clk) disable iff (rst)
    n_rxaxis <= n_rx_good);

// ORACLE: every frame the rx fifo saw -- kept, dropped for a bad fcs, or
// dropped because it was full -- was a frame the environment injected.  This
// is the accounting identity of the receive half, stated as the inequality it
// is safe to state (the three status pulses are three cycles behind the
// injection that caused them).
T_CONSERV_RX_FRAME_ACCOUNT: assert property (@(posedge clk) disable iff (rst)
    n_rx_good + n_rx_bad + n_rx_ovf <= n_src);

// ORACLE: past the rx fifo NOTHING drops a frame -- `eth_demux.drop` is tied
// low, both mid-chain fifos have DROP_* clear, and the transmit frame fifo
// only drops oversize (>32 byte) or tuser-marked frames, neither of which this
// environment can produce.  So the frames between the two counting points are
// exactly the ones still inside the chain, and the chain's capacity bounds
// them.  EXPECTED TO BE THE SHAKIEST OF THE FOUR: `MID_CAP` is a capacity
// estimate, not a measurement.  Stated additively so no unsigned subtraction
// can wrap if the delivered count ever runs ahead.
T_CONSERV_MID_INFLIGHT_BOUNDED: assert property (@(posedge clk) disable iff (rst)
    {1'b0, n_rxaxis} <= {1'b0, n_mon} + {1'b0, MID_CAP});

// ORACLE: `eth_demux` routes ONE frame at a time -- `frame_ctl` gates the
// payload ready and is only set when it takes that frame's header -- so the
// header count and the payload-frame count for a flow can differ by at most
// the one frame in progress.  The skew has BOTH signs: the header normally
// leads, but if the header fifo is full the header sits in the demux output
// register while that frame's payload finishes, and the payload leads by one.
// If they ever separate by more than one, the split fifo pair has lost
// lockstep, which is the failure this whole cut is built to expose.
T_CONSERV_HDRPAY_LOCKSTEP_IN_FLOW0: assert property (@(posedge clk) disable iff (rst)
    ((n_hdr_in[0] >= n_pay_in[0]) ? (n_hdr_in[0] - n_pay_in[0])
                                  : (n_pay_in[0] - n_hdr_in[0])) <= 16'd1);

// ORACLE: the same obligation on the way OUT of the two fifos.  Again both
// signs: `eth_arb_mux` drives the payload ready off `grant_valid` alone, so a
// one-byte payload can move on the grant cycle, one cycle before
// `s_eth_hdr_ready` consumes the header -- but the arbiter holds the grant
// until that payload's tlast, so only one frame is ever in this state.
T_CONSERV_HDRPAY_LOCKSTEP_OUT_FLOW0: assert property (@(posedge clk) disable iff (rst)
    ((n_hdr_out[0] >= n_pay_out[0]) ? (n_hdr_out[0] - n_pay_out[0])
                                    : (n_pay_out[0] - n_hdr_out[0])) <= 16'd1);

// ---------------------------------------------- 5. mutual exclusion / one-hot

// ORACLE: `eth_demux` drives its payload valid as `(...) << select_ctl`, so at
// most one output can be valid; two would mean one frame reaching two flows.
T_MUTEX_DEMUX_PAYLOAD_ONEHOT0: assert property (@(posedge clk) disable iff (rst)
    $onehot0(dm_pv));

// ORACLE: the arbiter grants one port at a time; two grants would splice two
// flows' payloads into one frame.
T_MUTEX_ARB_GRANT_ONEHOT0: assert property (@(posedge clk) disable iff (rst)
    $onehot0(arb_grant));

// ------------------------------------------------------ 6. occupancy and bounds

// ORACLE: the fifos report their own occupancy and it cannot exceed the depth
// they were built with.
T_BOUND_HDRFIFO0_DEPTH: assert property (@(posedge clk) disable iff (rst)
    hf0_depth <= 3'd4);

T_BOUND_PAYFIFO0_DEPTH: assert property (@(posedge clk) disable iff (rst)
    pf0_depth <= 6'd32);

// ORACLE: the checker's own in-minus-out, which does not read the fifo's
// pointers at all, is bounded by the same capacity plus the two output
// pipeline stages RAM_PIPELINE(1) buys.
T_BOUND_HDRFIFO0_INFLIGHT: assert property (@(posedge clk) disable iff (rst)
    {1'b0, n_hdr_in[0]} <= {1'b0, n_hdr_out[0]} + {1'b0, HDR_FIFO_CAP});

T_BOUND_PAYFIFO0_INFLIGHT: assert property (@(posedge clk) disable iff (rst)
    {1'b0, n_pb_in[0]} <= {1'b0, n_pb_out[0]} + {1'b0, PAY_FIFO_CAP});

// ORACLE: the generator's longest frame is 14 header bytes plus 4 payload
// bytes, so the frame index at the far end never passes 17.
T_BOUND_MON_FRAME_LEN: assert property (@(posedge clk) disable iff (rst)
    mon_tvalid |-> mon_idx <= MAX_IDX);

// ORACLE: and its shortest is 15 bytes, so a frame never ends inside the
// header.  A shorter one means the transmit path truncated a frame.
T_BOUND_MON_FRAME_MIN_LEN: assert property (@(posedge clk) disable iff (rst)
    (mon_tvalid && mon_tlast) |-> mon_idx >= HDR_BYTES);

// ------------------------------------------------------ 7. allocator discipline

// ORACLE: `request = s_eth_hdr_valid & ~grant` and ARB_BLOCK_ACK holds the
// grant until the payload tlast, so a grant is either backed by a header
// waiting at that fifo's head or by a frame already in progress.
T_ALLOC_ARB_GRANT_BACKED: assert property (@(posedge clk) disable iff (rst)
    arb_gvalid |-> (hf_v[arb_genc] || arb_frame));

// ORACLE: `eth_arb_mux` instantiates `arbiter` with ARB_BLOCK_ACK, and its
// acknowledge is the payload tlast on the FIFO side -- so until the granted
// flow's payload fifo has handed over the last byte of the frame the grant may
// not move.  If it did, two flows' payloads would interleave inside one
// transmitted frame.  Note the ack is the FIFO-side tlast, one cycle ahead of
// the arb mux's own registered output tlast.
T_ALLOC_ARB_GRANT_HELD_UNTIL_ACK: assert property (@(posedge clk) disable iff (rst)
    (arb_gvalid && !(|(arb_grant & pf_done))) |=> (arb_gvalid && $stable(arb_grant)));

// ------------------------------------------- 8. request-response correspondence

// ORACLE: a frame can only be delivered after it has been injected, and the
// environment's injected count is the number of sequence numbers it has ever
// handed to the link.  A delivered sequence number at or above that count is
// a frame nobody sent.
T_REQRSP_MON_SEQ_WAS_INJECTED: assert property (@(posedge clk) disable iff (rst)
    mon_done |-> mon_seq < ftenv_inj);

// -------------------------------------------------------- 9. protocol conformance

// ORACLE: AXI-Stream. A valid beat may not be withdrawn or altered before it
// is accepted.
T_PROTO_MACTX_BEAT_STABLE: assert property (@(posedge clk) disable iff (rst)
    (mtx_tvalid && !mtx_tready) |=> (mtx_tvalid && $stable(mtx_tdata) && $stable(mtx_tlast)));

T_PROTO_ARB_PAYLOAD_STABLE: assert property (@(posedge clk) disable iff (rst)
    (arb_pv && !arb_pr) |=> (arb_pv && $stable(arb_ptdata) && $stable(arb_pl)));

// ORACLE: the same rule on the header handshake, which is where a header could
// be replaced by the next frame's while the demux is still deciding.
T_PROTO_ERX_HDR_STABLE: assert property (@(posedge clk) disable iff (rst)
    (erx_hv && !erx_hr) |=> (erx_hv && $stable(erx_dest) && $stable(erx_src) && $stable(erx_type)));

T_PROTO_HDRFIFO0_OUT_STABLE: assert property (@(posedge clk) disable iff (rst)
    (hf_v[0] && !hf_r[0]) |=> (hf_v[0] && $stable(hf0_dest)));

// ------------------------------------------------------- 10. arbitration fairness

// ORACLE: `eth_arb_mux` is instantiated with ARB_TYPE_ROUND_ROBIN(1), so a
// header sitting at the head of one flow's fifo waits for at most the frame
// the other flow is transmitting.  `veth_bounded_stall` caps a gmii byte at
// four cycles, so that frame lasts at most about 170 cycles.  BOUND IS AN
// ESTIMATE.
T_FAIR_HDRFIFO0_WAIT_BOUNDED: assert property (@(posedge clk) disable iff (rst)
    w_hf_wait[0] <= N_ARBWAIT);

T_FAIR_HDRFIFO1_WAIT_BOUNDED: assert property (@(posedge clk) disable iff (rst)
    w_hf_wait[1] <= N_ARBWAIT);

// ---------------------------------------------------------- 11. bounded response

// ORACLE: the transmit frame fifo drains onto a link that cannot be stalled
// for more than three consecutive cycles, so it cannot refuse `eth_axis_tx`
// forever.  BOUND IS AN ESTIMATE.
T_BOUNDRSP_MACTX_STALL_BOUNDED: assert property (@(posedge clk) disable iff (rst)
    w_mactx <= N_MACTX);

// ORACLE: the same on the receive side -- the chain must keep taking bytes out
// of the rx fifo.  BOUND IS AN ESTIMATE.
T_BOUNDRSP_RXFIFO_STALL_BOUNDED: assert property (@(posedge clk) disable iff (rst)
    w_rxstall <= N_RXSTALL);

// ORACLE: a frame that has left the rx fifo cannot be dropped by anything
// downstream, so while the delivered count trails the received count some
// frame must still be completing.  BOUND IS AN ESTIMATE.
T_BOUNDRSP_E2E_LATENCY_BOUNDED: assert property (@(posedge clk) disable iff (rst)
    w_e2e <= N_E2E);

// ------------------------------------------------------------ 12. deadlock freedom

// ORACLE: while a frame is between the two counting points, SOMETHING must
// move -- a handshake anywhere in the chain, a byte on either link.  A long
// quiet stretch with work outstanding is a cyclic wait among the buffers.
// BOUND IS AN ESTIMATE: the longest legitimately quiet stretch is the transmit
// interframe gap, twelve byte times, at most four cycles each.
T_DEADLOCK_NO_GLOBAL_STALL: assert property (@(posedge clk) disable iff (rst)
    w_prog <= N_PROGRESS);

// ORACLE: the one place a cyclic wait could actually form is the pair of
// mid-chain fifos, because the arbiter holds a grant on one flow while the
// demux is filling the other.  If both header fifos are full and neither is
// being read, nothing can ever drain.
T_DEADLOCK_NOT_BOTH_HDR_FIFOS_STUCK_FULL: assert property (@(posedge clk) disable iff (rst)
    (hf0_depth == 3'd4 && hf1_depth == 3'd4) |-> (hf_v[0] || hf_v[1]));

// ------------------------------------------------------ 13. reset / initialisation

T_RESET_ARB_NO_GRANT_AT_START: assert property (@(posedge clk)
    (!rst && $past(rst)) |-> !arb_gvalid);

T_RESET_HDRFIFOS_EMPTY_AT_START: assert property (@(posedge clk)
    (!rst && $past(rst)) |-> (hf0_depth == 3'd0 && hf1_depth == 3'd0));

// --------------------------------------------------- 14. lifecycle / routing state

// ORACLE: `eth_demux` latches `select` when it takes a header and holds it for
// the whole frame, so every payload byte of one frame leaves on the output the
// ethertype of THAT frame chose.  A select that moved mid-frame would split a
// frame across both flows.
T_LIFECYCLE_DEMUX_ROUTES_WHOLE_FRAME: assert property (@(posedge clk) disable iff (rst)
    (dmx_frame && |dm_pv) |-> dm_pv == (2'b01 << dmx_select));

// ORACLE: `dm_select` is the low bit of the ethertype the receiver parsed off
// the wire, so a header sitting in flow i's fifo must carry ethertype low bit
// i.  This spans the demux AND the fifo: it fails if the demux routed on stale
// data, or if a header landed in the wrong queue, or if the 112-bit word came
// back out of the queue paired with the wrong frame.
T_LIFECYCLE_HDRFIFO_FLOW_MATCHES_TYPE: assert property (@(posedge clk) disable iff (rst)
    (!hf_take[0] || hf0_type[0] == 1'b0) && (!hf_take[1] || hf1_type[0] == 1'b1));

// ===========================================================================
// COVERS.  Not targets -- these are what COVER_DEPTH counts to show the
// candidates above are not vacuous.  At least one per category used.
// ===========================================================================

C_INJECT_ONE_FRAME: cover property (@(posedge clk) disable iff (rst)
    src_accept);
C_INJECT_TWO_FRAMES: cover property (@(posedge clk) disable iff (rst)
    n_src >= 16'd2);

C_RX_ONE_FRAME_COMMITTED: cover property (@(posedge clk) disable iff (rst)
    rx_good);
C_RX_AXIS_FRAME_OUT: cover property (@(posedge clk) disable iff (rst)
    mrx_beat && mrx_tlast);

C_ERX_HEADER_PARSED: cover property (@(posedge clk) disable iff (rst)
    erx_hdr_take);
C_ERX_HEADER_IS_FLOW1: cover property (@(posedge clk) disable iff (rst)
    erx_hdr_take && erx_type[0]);

C_DEMUX_ROUTED_FLOW0: cover property (@(posedge clk) disable iff (rst)
    dm_hdr_take[0]);
C_DEMUX_ROUTED_FLOW1: cover property (@(posedge clk) disable iff (rst)
    dm_hdr_take[1]);

C_BOTH_FLOWS_HAVE_A_HEADER: cover property (@(posedge clk) disable iff (rst)
    hf_v[0] && hf_v[1]);
C_HDRFIFO0_TWO_DEEP: cover property (@(posedge clk) disable iff (rst)
    hf0_depth >= 3'd2);
C_PAYFIFO0_EIGHT_DEEP: cover property (@(posedge clk) disable iff (rst)
    pf0_depth >= 6'd8);

C_ARB_GRANTED_FLOW0: cover property (@(posedge clk) disable iff (rst)
    arb_hdr_take && arb_genc == 1'b0);
C_ARB_GRANTED_FLOW1: cover property (@(posedge clk) disable iff (rst)
    arb_hdr_take && arb_genc == 1'b1);
C_ARB_CONTENDED: cover property (@(posedge clk) disable iff (rst)
    hf_v[0] && hf_v[1] && arb_gvalid);

C_MACTX_FRAME_OFFERED: cover property (@(posedge clk) disable iff (rst)
    mtx_beat && mtx_tlast);
C_MACTX_BACKPRESSURED: cover property (@(posedge clk) disable iff (rst)
    mtx_tvalid && !mtx_tready);
C_RXAXIS_BACKPRESSURED: cover property (@(posedge clk) disable iff (rst)
    mrx_tvalid && !mrx_tready);

C_LINK_STALLED: cover property (@(posedge clk) disable iff (rst)
    !tx_link_en);

C_DELIVER_ONE_FRAME: cover property (@(posedge clk) disable iff (rst)
    mon_done);
C_DELIVER_TWO_FRAMES: cover property (@(posedge clk) disable iff (rst)
    n_mon >= 16'd2);
C_DELIVER_BOTH_FLOWS: cover property (@(posedge clk) disable iff (rst)
    mon_seen == 2'b11);
C_DELIVER_MAX_PAYLOAD: cover property (@(posedge clk) disable iff (rst)
    mon_done && mon_plen == MAX_PLEN);

// The arbiter reordering two flows against injection order: the reason global
// order is NOT a candidate and per-flow order is.
C_ORDER_GLOBAL_INVERTED: cover property (@(posedge clk) disable iff (rst)
    mon_done && mon_seen[0] && mon_seen[1]
             && mon_seq < mon_last_seq[mon_flow ? 1'b0 : 1'b1]);

C_RX_FRAME_DROPPED_FULL: cover property (@(posedge clk) disable iff (rst)
    rx_ovf);
C_TX_FIFO_COMMITTED: cover property (@(posedge clk) disable iff (rst)
    tx_good);

C_ARBWAIT_SIXTEEN: cover property (@(posedge clk) disable iff (rst)
    w_hf_wait[0] >= 12'd16 || w_hf_wait[1] >= 12'd16);
C_E2E_TIMER_SIXTY_FOUR: cover property (@(posedge clk) disable iff (rst)
    w_e2e >= 12'd64);
C_PROGRESS_TIMER_SIXTEEN: cover property (@(posedge clk) disable iff (rst)
    w_prog >= 12'd16);

C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
    !rst && $past(rst));

endmodule

bind verilog_ethernet_mac_datapath_ft veth_mac_targets veth_mac_targets (
    .clk(clk), .rst(rst));

`resetall
