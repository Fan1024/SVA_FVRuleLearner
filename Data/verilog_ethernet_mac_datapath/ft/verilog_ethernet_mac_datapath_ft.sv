// ===========================================================================
// verilog_ethernet_mac_datapath_ft -- formal top for the 1G Ethernet MAC
// transmit/receive datapath of alexforencich/verilog-ethernet.
//
// TASK-AUTHORED.  Nothing in this file comes from upstream; the eighteen
// upstream modules under `rtl/verilog_ethernet/` and `rtl/axis/` are
// byte-identical and are only instantiated here.
//
// THE CHAIN, left to right.  Three separate stages of buffering, which is the
// point of the cut -- a frame is store-and-forwarded three times and is split
// into a header and a payload that travel through DIFFERENT fifos:
//
//   veth_frame_src            authored: one well-formed Ethernet frame at a
//        |                    time on an 8-bit AXI-Stream.  Every byte is a
//        |                    function of a 16-bit sequence number, so the
//        |                    checker can recompute the whole frame from the
//        |                    header that comes out the far end.
//        v
//   axis_gmii_tx  (u_gmii_src)      upstream.  Adds preamble/SFD, computes
//        |  gmii (phy_rx*)          the CRC-32 FCS.  This is the LINK.
//        v
//   +-- eth_mac_1g_fifo (u_mac) ------------------------------------------+
//   |  axis_gmii_rx -> [ BUFFER 1: rx axis_async_fifo, FRAME FIFO,        |
//   |                    store-and-forward, drops bad-FCS and             |
//   |                    drop-when-full frames ]                          |
//   +---------------------------------------------------------------------+
//        |  rx_axis (frame without preamble and without FCS)
//        v
//   eth_axis_rx  (u_eth_rx)     upstream.  SPLITS the frame: 14 header bytes
//        |                      become one {dest,src,type} handshake, the
//        |  hdr + payload       rest stays on the payload stream.
//        v
//   axis_pipeline_register (u_pipe)   upstream, 2 skid stages on the payload
//        |
//        v
//   eth_demux (u_demux)         upstream.  Two flows, selected by the LOW BIT
//        |         \            OF THE ETHERTYPE, which is frame data.
//        v          v
//   [ BUFFER 2, per flow and per KIND:
//       axis_fifo u_hdr_fifo[i]  DEPTH 4,  112-bit {dest,src,type}
//       axis_fifo u_pay_fifo[i]  DEPTH 32, 8-bit payload ]
//        |          |
//        v          v
//   eth_arb_mux (u_arb)         upstream, round-robin, grant LOCKED for a
//        |                      whole frame (ARB_BLOCK_ACK on payload tlast).
//        v
//   eth_axis_tx (u_eth_tx)      upstream.  REJOINS header and payload.
//        |
//        v
//   +-- eth_mac_1g_fifo (u_mac) ------------------------------------------+
//   |  [ BUFFER 3: tx axis_async_fifo, FRAME FIFO, store-and-forward ]     |
//   |    -> axis_gmii_tx  (preamble, FCS)                                  |
//   +---------------------------------------------------------------------+
//        |  gmii (phy_tx*)
//        v
//   axis_gmii_rx (u_gmii_mon)   upstream, used as a MONITOR: it re-receives
//        |                      the transmitted link, checks the FCS the
//        |                      transmit path computed, and strips the
//        v                      preamble again.
//   mon_* -- the far observation point.  `sva/targets_*.sv` parses these
//            bytes with its own counter and compares them with what the
//            sequence number in the header says they must be.
//
// Everything the environment chooses is a free top-level input.  The two
// LINK enables are free but BOUNDED: `veth_bounded_stall` cannot hold either
// gmii byte clock off for more than three consecutive cycles.  That is what
// makes the bounded-response, fairness and deadlock candidates mean something
// -- with an unbounded link stall every one of them is false, and with no
// stall at all the fifos never fill and the backpressure targets are vacuous.
//
// Everything the environment REMEMBERS lives in `env_src` or in a top-level
// register named `ftenv_*`; `taskdef.json:design_keep` keeps that state out of
// the reset cut and cuts the whole design.
// ===========================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

// ---------------------------------------------------------------------------
// The frame generator.  ONE frame at a time, offered when `go` is high.
//
// Frame layout (14-byte Ethernet header + 1..4 payload bytes), every byte a
// function of the 16-bit sequence number `seq`, the payload length `plen` and
// the flow bit:
//
//   byte  0..3   8'hDA                       dest_mac[47:16] = 32'hDADADADA
//   byte  4..5   seq[15:8], seq[7:0]         dest_mac[15:0]  = seq
//   byte  6..9   8'h5A                       src_mac[47:16]  = 32'h5A5A5A5A
//   byte 10      plen                        src_mac[15:8]   = payload length
//   byte 11      ~seq[7:0]                   src_mac[7:0]    = ~seq[7:0]
//   byte 12..13  8'h08, {7'b0, flow}         eth_type = 16'h0800 | flow
//   byte 14+j    seq[7:0] ^ (j+1) ^ 8'hA5    payload
//
// The redundancy is deliberate.  `seq` is carried in the dest MAC, its
// complement in the src MAC and its low byte in every payload byte, so a
// header that overtakes its own payload -- the failure mode a split
// header/payload fifo pair actually has -- is visible at the far end without
// any shadow queue at all.
// ---------------------------------------------------------------------------
module veth_frame_src (
    input  wire        clk,
    input  wire        rst,

    input  wire        go,            // free: offer the next frame
    input  wire        sel_flow,      // free: which ethertype, hence which flow
    input  wire [1:0]  sel_len,       // free: payload length - 1

    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire        m_axis_tuser,

    output wire [15:0] seq_cur,       // sequence number of the frame in flight
    output wire [7:0]  plen_cur,
    output wire        flow_cur,
    output wire [7:0]  idx_cur,
    output wire        busy,
    output wire        frame_accepted // pulse: the link took the last byte
);

localparam [7:0] HDR_BYTES = 8'd14;

function [7:0] veth_byte;
    input [15:0] seq;
    input [7:0]  plen;
    input        flow;
    input [7:0]  idx;
    begin
        case (idx)
            8'd0, 8'd1, 8'd2, 8'd3: veth_byte = 8'hDA;
            8'd4:                   veth_byte = seq[15:8];
            8'd5:                   veth_byte = seq[7:0];
            8'd6, 8'd7, 8'd8, 8'd9: veth_byte = 8'h5A;
            8'd10:                  veth_byte = plen;
            8'd11:                  veth_byte = ~seq[7:0];
            8'd12:                  veth_byte = 8'h08;
            8'd13:                  veth_byte = {7'b0, flow};
            default:                veth_byte = seq[7:0]
                                                ^ (idx - (HDR_BYTES - 8'd1))
                                                ^ 8'hA5;
        endcase
    end
endfunction

reg        busy_reg  = 1'b0;
reg [7:0]  idx_reg   = 8'd0;
reg [15:0] seq_reg   = 16'd0;
reg [7:0]  plen_reg  = 8'd1;
reg        flow_reg  = 1'b0;

wire last = busy_reg && (idx_reg == (HDR_BYTES - 8'd1) + plen_reg);

assign m_axis_tdata  = veth_byte(seq_reg, plen_reg, flow_reg, idx_reg);
assign m_axis_tvalid = busy_reg;
assign m_axis_tlast  = last;
assign m_axis_tuser  = 1'b0;

assign seq_cur        = seq_reg;
assign plen_cur       = plen_reg;
assign flow_cur       = flow_reg;
assign idx_cur        = idx_reg;
assign busy           = busy_reg;
assign frame_accepted = busy_reg && m_axis_tready && last;

always @(posedge clk) begin
    if (rst) begin
        busy_reg <= 1'b0;
        idx_reg  <= 8'd0;
        seq_reg  <= 16'd0;
        plen_reg <= 8'd1;
        flow_reg <= 1'b0;
    end else if (!busy_reg) begin
        if (go) begin
            busy_reg <= 1'b1;
            idx_reg  <= 8'd0;
            plen_reg <= {6'd0, sel_len} + 8'd1;
            flow_reg <= sel_flow;
        end
    end else if (m_axis_tready) begin
        if (last) begin
            busy_reg <= 1'b0;
            seq_reg  <= seq_reg + 16'd1;
        end else begin
            idx_reg <= idx_reg + 8'd1;
        end
    end
end

endmodule

// ---------------------------------------------------------------------------
// A gmii byte-clock enable that the environment controls but cannot hold off
// forever: `en` is low only while `req` is high AND fewer than MAX consecutive
// stalls have been taken, so `en` is never low for more than MAX cycles in a
// row.  This is the whole of the fairness / bounded-response environment.
// ---------------------------------------------------------------------------
module veth_bounded_stall #(
    parameter [2:0] MAX = 3'd3
) (
    input  wire clk,
    input  wire rst,
    input  wire req,
    output wire en
);

reg [2:0] cnt_reg = 3'd0;

assign en = !(req && (cnt_reg != MAX));

always @(posedge clk) begin
    if (rst) begin
        cnt_reg <= 3'd0;
    end else if (!en) begin
        cnt_reg <= cnt_reg + 3'd1;
    end else begin
        cnt_reg <= 3'd0;
    end
end

endmodule

// ===========================================================================
module verilog_ethernet_mac_datapath_ft (
    input  wire       clk,
    input  wire       rst,

    // ---- what the environment injects ------------------------------------
    input  wire       env_go,          // offer the next frame
    input  wire       env_flow,        // its ethertype low bit, hence its flow
    input  wire [1:0] env_len,         // its payload length - 1  (1..4 bytes)

    // ---- the two link stalls, bounded to 3 consecutive cycles -------------
    input  wire       env_rx_link_stall,
    input  wire       env_tx_link_stall
);

// --------------------------------------------------------------- geometry --
localparam AXIS_DATA_WIDTH   = 8;
localparam MAC_RX_FIFO_DEPTH = 32;   // bytes; a frame is 15..18 bytes
localparam MAC_TX_FIFO_DEPTH = 32;
localparam HDR_FIFO_DEPTH    = 4;    // headers per flow
localparam PAY_FIFO_DEPTH    = 32;   // payload bytes per flow
localparam FLOWS             = 2;

// ------------------------------------------------------------ reset tree ---
// The two gmii domains take their reset through the upstream synchroniser,
// which is what every verilog-ethernet wrapper does.  Same clock here, so
// this is two cycles of extra reset and no cdc.
wire rx_rst;
wire tx_rst;
wire logic_rst = rst;

sync_reset #(.N(2)) u_rx_rst (.clk(clk), .rst(rst), .out(rx_rst));
sync_reset #(.N(2)) u_tx_rst (.clk(clk), .rst(rst), .out(tx_rst));

// ------------------------------------------------- bounded link enables ----
wire rx_link_en;
wire tx_link_en;

veth_bounded_stall #(.MAX(3'd3)) u_rx_stall (
    .clk(clk), .rst(rst), .req(env_rx_link_stall), .en(rx_link_en));
veth_bounded_stall #(.MAX(3'd3)) u_tx_stall (
    .clk(clk), .rst(rst), .req(env_tx_link_stall), .en(tx_link_en));

// ===================================================== stage 0: the source ==
wire [7:0]  src_tdata;
wire        src_tvalid;
wire        src_tready;
wire        src_tlast;
wire        src_tuser;

wire [15:0] src_seq;
wire [7:0]  src_plen;
wire        src_flow;
wire [7:0]  src_idx;
wire        src_busy;
wire        src_frame_accepted;

veth_frame_src env_src (
    .clk(clk),
    .rst(rst),
    .go(env_go),
    .sel_flow(env_flow),
    .sel_len(env_len),
    .m_axis_tdata(src_tdata),
    .m_axis_tvalid(src_tvalid),
    .m_axis_tready(src_tready),
    .m_axis_tlast(src_tlast),
    .m_axis_tuser(src_tuser),
    .seq_cur(src_seq),
    .plen_cur(src_plen),
    .flow_cur(src_flow),
    .idx_cur(src_idx),
    .busy(src_busy),
    .frame_accepted(src_frame_accepted)
);

// --- the receive link.  Upstream transmit logic used as a frame source, so
// --- the FCS the receiver checks is a real CRC-32 and not a guess.
wire [7:0] phy_rxd;
wire       phy_rx_dv;
wire       phy_rx_er;

axis_gmii_tx #(
    .DATA_WIDTH(8),
    .ENABLE_PADDING(0),          // no 64-byte pad: keeps a frame 23..26 link
    .MIN_FRAME_LENGTH(64),       // bytes instead of 72, which is 50 cycles of
    .PTP_TS_ENABLE(0)            // cover depth saved on every frame
)
u_gmii_src (
    .clk(clk),
    .rst(rx_rst),
    .s_axis_tdata(src_tdata),
    .s_axis_tvalid(src_tvalid),
    .s_axis_tready(src_tready),
    .s_axis_tlast(src_tlast),
    .s_axis_tuser(src_tuser),
    .gmii_txd(phy_rxd),
    .gmii_tx_en(phy_rx_dv),
    .gmii_tx_er(phy_rx_er),
    .ptp_ts(96'd0),
    .m_axis_ptp_ts(),
    .m_axis_ptp_ts_tag(),
    .m_axis_ptp_ts_valid(),
    .clk_enable(rx_link_en),
    .mii_select(1'b0),
    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .start_packet(),
    .error_underflow()
);

// ============================== stage 1: the MAC, and buffers 1 and 3 =======
wire [7:0] mac_rx_tdata;
wire       mac_rx_tvalid;
wire       mac_rx_tready;
wire       mac_rx_tlast;
wire       mac_rx_tuser;

wire [7:0] mac_tx_tdata;
wire       mac_tx_tvalid;
wire       mac_tx_tready;
wire       mac_tx_tlast;
wire       mac_tx_tuser;

wire [7:0] phy_txd;
wire       phy_tx_en;
wire       phy_tx_er;

wire       tx_error_underflow;
wire       tx_fifo_overflow;
wire       tx_fifo_bad_frame;
wire       tx_fifo_good_frame;
wire       rx_error_bad_frame;
wire       rx_error_bad_fcs;
wire       rx_fifo_overflow;
wire       rx_fifo_bad_frame;
wire       rx_fifo_good_frame;

eth_mac_1g_fifo #(
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .AXIS_KEEP_ENABLE(0),
    .AXIS_KEEP_WIDTH(1),
    .ENABLE_PADDING(0),
    .MIN_FRAME_LENGTH(64),
    .TX_FIFO_DEPTH(MAC_TX_FIFO_DEPTH),
    .TX_FIFO_RAM_PIPELINE(1),
    .TX_FRAME_FIFO(1),
    .RX_FIFO_DEPTH(MAC_RX_FIFO_DEPTH),
    .RX_FIFO_RAM_PIPELINE(1),
    .RX_FRAME_FIFO(1)
)
u_mac (
    .rx_clk(clk),
    .rx_rst(rx_rst),
    .tx_clk(clk),
    .tx_rst(tx_rst),
    .logic_clk(clk),
    .logic_rst(logic_rst),

    .tx_axis_tdata(mac_tx_tdata),
    .tx_axis_tkeep(1'b1),
    .tx_axis_tvalid(mac_tx_tvalid),
    .tx_axis_tready(mac_tx_tready),
    .tx_axis_tlast(mac_tx_tlast),
    .tx_axis_tuser(mac_tx_tuser),

    .rx_axis_tdata(mac_rx_tdata),
    .rx_axis_tkeep(),
    .rx_axis_tvalid(mac_rx_tvalid),
    .rx_axis_tready(mac_rx_tready),
    .rx_axis_tlast(mac_rx_tlast),
    .rx_axis_tuser(mac_rx_tuser),

    .gmii_rxd(phy_rxd),
    .gmii_rx_dv(phy_rx_dv),
    .gmii_rx_er(phy_rx_er),
    .gmii_txd(phy_txd),
    .gmii_tx_en(phy_tx_en),
    .gmii_tx_er(phy_tx_er),

    .rx_clk_enable(rx_link_en),
    .tx_clk_enable(tx_link_en),
    .rx_mii_select(1'b0),
    .tx_mii_select(1'b0),

    .tx_error_underflow(tx_error_underflow),
    .tx_fifo_overflow(tx_fifo_overflow),
    .tx_fifo_bad_frame(tx_fifo_bad_frame),
    .tx_fifo_good_frame(tx_fifo_good_frame),
    .rx_error_bad_frame(rx_error_bad_frame),
    .rx_error_bad_fcs(rx_error_bad_fcs),
    .rx_fifo_overflow(rx_fifo_overflow),
    .rx_fifo_bad_frame(rx_fifo_bad_frame),
    .rx_fifo_good_frame(rx_fifo_good_frame),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

// ============================ stage 2: header/payload split =================
wire        erx_hdr_valid;
wire        erx_hdr_ready;
wire [47:0] erx_dest_mac;
wire [47:0] erx_src_mac;
wire [15:0] erx_type;

wire [7:0]  erx_pay_tdata;
wire        erx_pay_tvalid;
wire        erx_pay_tready;
wire        erx_pay_tlast;
wire        erx_pay_tuser;

wire        erx_busy;
wire        erx_hdr_early_term;

eth_axis_rx #(
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1)
)
u_eth_rx (
    .clk(clk),
    .rst(logic_rst),
    .s_axis_tdata(mac_rx_tdata),
    .s_axis_tkeep(1'b1),
    .s_axis_tvalid(mac_rx_tvalid),
    .s_axis_tready(mac_rx_tready),
    .s_axis_tlast(mac_rx_tlast),
    .s_axis_tuser(mac_rx_tuser),
    .m_eth_hdr_valid(erx_hdr_valid),
    .m_eth_hdr_ready(erx_hdr_ready),
    .m_eth_dest_mac(erx_dest_mac),
    .m_eth_src_mac(erx_src_mac),
    .m_eth_type(erx_type),
    .m_eth_payload_axis_tdata(erx_pay_tdata),
    .m_eth_payload_axis_tkeep(),
    .m_eth_payload_axis_tvalid(erx_pay_tvalid),
    .m_eth_payload_axis_tready(erx_pay_tready),
    .m_eth_payload_axis_tlast(erx_pay_tlast),
    .m_eth_payload_axis_tuser(erx_pay_tuser),
    .busy(erx_busy),
    .error_header_early_termination(erx_hdr_early_term)
);

// --- two skid stages on the payload only.  The header reaches the demux a
// --- couple of cycles before its own payload, which is exactly the skew the
// --- split-fifo targets are about.
wire [7:0] pipe_tdata;
wire       pipe_tvalid;
wire       pipe_tready;
wire       pipe_tlast;
wire       pipe_tuser;

axis_pipeline_register #(
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1),
    .LAST_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .REG_TYPE(2),
    .LENGTH(2)
)
u_pipe (
    .clk(clk),
    .rst(logic_rst),
    .s_axis_tdata(erx_pay_tdata),
    .s_axis_tkeep(1'b1),
    .s_axis_tvalid(erx_pay_tvalid),
    .s_axis_tready(erx_pay_tready),
    .s_axis_tlast(erx_pay_tlast),
    .s_axis_tid(8'd0),
    .s_axis_tdest(8'd0),
    .s_axis_tuser(erx_pay_tuser),
    .m_axis_tdata(pipe_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(pipe_tvalid),
    .m_axis_tready(pipe_tready),
    .m_axis_tlast(pipe_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(pipe_tuser)
);

// ============================ stage 3: two flows, buffer 2 =================
wire [FLOWS-1:0]    dm_hdr_valid;
wire [FLOWS-1:0]    dm_hdr_ready;
wire [FLOWS*48-1:0] dm_dest_mac;
wire [FLOWS*48-1:0] dm_src_mac;
wire [FLOWS*16-1:0] dm_type;
wire [FLOWS*8-1:0]  dm_pay_tdata;
wire [FLOWS-1:0]    dm_pay_tvalid;
wire [FLOWS-1:0]    dm_pay_tready;
wire [FLOWS-1:0]    dm_pay_tlast;
wire [FLOWS-1:0]    dm_pay_tuser;

// The routing decision is FRAME DATA: the low bit of the ethertype the
// receiver parsed out of the wire.  eth_demux latches it when it takes the
// header, and holds it for the whole frame.
wire dm_select = erx_type[0];

eth_demux #(
    .M_COUNT(FLOWS),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1),
    .ID_ENABLE(0),
    .ID_WIDTH(8),
    .DEST_ENABLE(0),
    .DEST_WIDTH(8),
    .USER_ENABLE(1),
    .USER_WIDTH(1)
)
u_demux (
    .clk(clk),
    .rst(logic_rst),
    .s_eth_hdr_valid(erx_hdr_valid),
    .s_eth_hdr_ready(erx_hdr_ready),
    .s_eth_dest_mac(erx_dest_mac),
    .s_eth_src_mac(erx_src_mac),
    .s_eth_type(erx_type),
    .s_eth_payload_axis_tdata(pipe_tdata),
    .s_eth_payload_axis_tkeep(1'b1),
    .s_eth_payload_axis_tvalid(pipe_tvalid),
    .s_eth_payload_axis_tready(pipe_tready),
    .s_eth_payload_axis_tlast(pipe_tlast),
    .s_eth_payload_axis_tid(8'd0),
    .s_eth_payload_axis_tdest(8'd0),
    .s_eth_payload_axis_tuser(pipe_tuser),
    .m_eth_hdr_valid(dm_hdr_valid),
    .m_eth_hdr_ready(dm_hdr_ready),
    .m_eth_dest_mac(dm_dest_mac),
    .m_eth_src_mac(dm_src_mac),
    .m_eth_type(dm_type),
    .m_eth_payload_axis_tdata(dm_pay_tdata),
    .m_eth_payload_axis_tkeep(),
    .m_eth_payload_axis_tvalid(dm_pay_tvalid),
    .m_eth_payload_axis_tready(dm_pay_tready),
    .m_eth_payload_axis_tlast(dm_pay_tlast),
    .m_eth_payload_axis_tid(),
    .m_eth_payload_axis_tdest(),
    .m_eth_payload_axis_tuser(dm_pay_tuser),
    .enable(1'b1),
    .drop(1'b0),
    .select(dm_select)
);

// --- buffer 2: per flow, a 4-deep HEADER fifo and a 32-deep PAYLOAD fifo.
// --- Different depths, different units, no shared pointer: keeping them in
// --- step is the design's obligation and nothing enforces it locally.
wire [FLOWS-1:0]     hf_out_valid;
wire [FLOWS-1:0]     hf_out_ready;
wire [FLOWS*112-1:0] hf_out_data;
wire [FLOWS*48-1:0]  hf_dest_mac;
wire [FLOWS*48-1:0]  hf_src_mac;
wire [FLOWS*16-1:0]  hf_type;
wire [FLOWS*3-1:0]   hf_depth;

wire [FLOWS*8-1:0]   pf_tdata;
wire [FLOWS-1:0]     pf_tvalid;
wire [FLOWS-1:0]     pf_tready;
wire [FLOWS-1:0]     pf_tlast;
wire [FLOWS-1:0]     pf_tuser;
wire [FLOWS*6-1:0]   pf_depth;

genvar gi;
generate
for (gi = 0; gi < FLOWS; gi = gi + 1) begin : flow

    // ---- the header fifo.  112 bits wide, one word per frame, no tlast.
    axis_fifo #(
        .DEPTH(HDR_FIFO_DEPTH),
        .DATA_WIDTH(112),
        .KEEP_ENABLE(0),
        .KEEP_WIDTH(1),
        .LAST_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .RAM_PIPELINE(1),
        .OUTPUT_FIFO_ENABLE(0),
        .FRAME_FIFO(0),
        .DROP_OVERSIZE_FRAME(0),
        .DROP_BAD_FRAME(0),
        .DROP_WHEN_FULL(0),
        .MARK_WHEN_FULL(0),
        .PAUSE_ENABLE(0),
        .FRAME_PAUSE(0)
    )
    u_hdr_fifo (
        .clk(clk),
        .rst(logic_rst),
        .s_axis_tdata({dm_dest_mac[gi*48 +: 48],
                       dm_src_mac[gi*48 +: 48],
                       dm_type[gi*16 +: 16]}),
        .s_axis_tkeep(1'b0),
        .s_axis_tvalid(dm_hdr_valid[gi]),
        .s_axis_tready(dm_hdr_ready[gi]),
        .s_axis_tlast(1'b1),
        .s_axis_tid(8'd0),
        .s_axis_tdest(8'd0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(hf_out_data[gi*112 +: 112]),
        .m_axis_tkeep(),
        .m_axis_tvalid(hf_out_valid[gi]),
        .m_axis_tready(hf_out_ready[gi]),
        .m_axis_tlast(),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(),
        .pause_req(1'b0),
        .pause_ack(),
        .status_depth(hf_depth[gi*3 +: 3]),
        .status_depth_commit(),
        .status_overflow(),
        .status_bad_frame(),
        .status_good_frame()
    );

    assign hf_dest_mac[gi*48 +: 48] = hf_out_data[gi*112 + 64 +: 48];
    assign hf_src_mac [gi*48 +: 48] = hf_out_data[gi*112 + 16 +: 48];
    assign hf_type    [gi*16 +: 16] = hf_out_data[gi*112 +  0 +: 16];

    // ---- the payload fifo.  8 bits wide, one word per BYTE, tlast carried.
    axis_fifo #(
        .DEPTH(PAY_FIFO_DEPTH),
        .DATA_WIDTH(8),
        .KEEP_ENABLE(0),
        .KEEP_WIDTH(1),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .RAM_PIPELINE(1),
        .OUTPUT_FIFO_ENABLE(0),
        .FRAME_FIFO(0),
        .DROP_OVERSIZE_FRAME(0),
        .DROP_BAD_FRAME(0),
        .DROP_WHEN_FULL(0),
        .MARK_WHEN_FULL(0),
        .PAUSE_ENABLE(0),
        .FRAME_PAUSE(0)
    )
    u_pay_fifo (
        .clk(clk),
        .rst(logic_rst),
        .s_axis_tdata(dm_pay_tdata[gi*8 +: 8]),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(dm_pay_tvalid[gi]),
        .s_axis_tready(dm_pay_tready[gi]),
        .s_axis_tlast(dm_pay_tlast[gi]),
        .s_axis_tid(8'd0),
        .s_axis_tdest(8'd0),
        .s_axis_tuser(dm_pay_tuser[gi]),
        .m_axis_tdata(pf_tdata[gi*8 +: 8]),
        .m_axis_tkeep(),
        .m_axis_tvalid(pf_tvalid[gi]),
        .m_axis_tready(pf_tready[gi]),
        .m_axis_tlast(pf_tlast[gi]),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(pf_tuser[gi]),
        .pause_req(1'b0),
        .pause_ack(),
        .status_depth(pf_depth[gi*6 +: 6]),
        .status_depth_commit(),
        .status_overflow(),
        .status_bad_frame(),
        .status_good_frame()
    );

end
endgenerate

// ============================ stage 4: the arbiter =========================
wire        arb_hdr_valid;
wire        arb_hdr_ready;
wire [47:0] arb_dest_mac;
wire [47:0] arb_src_mac;
wire [15:0] arb_type;
wire [7:0]  arb_pay_tdata;
wire        arb_pay_tvalid;
wire        arb_pay_tready;
wire        arb_pay_tlast;
wire        arb_pay_tuser;

eth_arb_mux #(
    .S_COUNT(FLOWS),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1),
    .ID_ENABLE(0),
    .ID_WIDTH(8),
    .DEST_ENABLE(0),
    .DEST_WIDTH(8),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .ARB_TYPE_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIORITY(1)
)
u_arb (
    .clk(clk),
    .rst(logic_rst),
    .s_eth_hdr_valid(hf_out_valid),
    .s_eth_hdr_ready(hf_out_ready),
    .s_eth_dest_mac(hf_dest_mac),
    .s_eth_src_mac(hf_src_mac),
    .s_eth_type(hf_type),
    .s_eth_payload_axis_tdata(pf_tdata),
    .s_eth_payload_axis_tkeep(2'b11),
    .s_eth_payload_axis_tvalid(pf_tvalid),
    .s_eth_payload_axis_tready(pf_tready),
    .s_eth_payload_axis_tlast(pf_tlast),
    .s_eth_payload_axis_tid(16'd0),
    .s_eth_payload_axis_tdest(16'd0),
    .s_eth_payload_axis_tuser(pf_tuser),
    .m_eth_hdr_valid(arb_hdr_valid),
    .m_eth_hdr_ready(arb_hdr_ready),
    .m_eth_dest_mac(arb_dest_mac),
    .m_eth_src_mac(arb_src_mac),
    .m_eth_type(arb_type),
    .m_eth_payload_axis_tdata(arb_pay_tdata),
    .m_eth_payload_axis_tkeep(),
    .m_eth_payload_axis_tvalid(arb_pay_tvalid),
    .m_eth_payload_axis_tready(arb_pay_tready),
    .m_eth_payload_axis_tlast(arb_pay_tlast),
    .m_eth_payload_axis_tid(),
    .m_eth_payload_axis_tdest(),
    .m_eth_payload_axis_tuser(arb_pay_tuser)
);

// ============================ stage 5: rejoin ==============================
wire etx_busy;

eth_axis_tx #(
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1)
)
u_eth_tx (
    .clk(clk),
    .rst(logic_rst),
    .s_eth_hdr_valid(arb_hdr_valid),
    .s_eth_hdr_ready(arb_hdr_ready),
    .s_eth_dest_mac(arb_dest_mac),
    .s_eth_src_mac(arb_src_mac),
    .s_eth_type(arb_type),
    .s_eth_payload_axis_tdata(arb_pay_tdata),
    .s_eth_payload_axis_tkeep(1'b1),
    .s_eth_payload_axis_tvalid(arb_pay_tvalid),
    .s_eth_payload_axis_tready(arb_pay_tready),
    .s_eth_payload_axis_tlast(arb_pay_tlast),
    .s_eth_payload_axis_tuser(arb_pay_tuser),
    .m_axis_tdata(mac_tx_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(mac_tx_tvalid),
    .m_axis_tready(mac_tx_tready),
    .m_axis_tlast(mac_tx_tlast),
    .m_axis_tuser(mac_tx_tuser),
    .busy(etx_busy)
);

// ============================ stage 6: the monitor =========================
// A THIRD upstream receiver, on the transmitted link.  It re-checks the FCS
// the transmit path computed and strips the preamble, so the checker sees the
// same 14-byte header and payload it started with -- but only if every stage
// in between kept them together.
wire [7:0] mon_tdata;
wire       mon_tvalid;
wire       mon_tlast;
wire       mon_tuser;
wire       mon_start_packet;
wire       mon_error_bad_frame;
wire       mon_error_bad_fcs;

axis_gmii_rx #(
    .DATA_WIDTH(8),
    .PTP_TS_ENABLE(0)
)
u_gmii_mon (
    .clk(clk),
    .rst(tx_rst),
    .gmii_rxd(phy_txd),
    .gmii_rx_dv(phy_tx_en),
    .gmii_rx_er(phy_tx_er),
    .m_axis_tdata(mon_tdata),
    .m_axis_tvalid(mon_tvalid),
    .m_axis_tlast(mon_tlast),
    .m_axis_tuser(mon_tuser),
    .ptp_ts(96'd0),
    .clk_enable(tx_link_en),
    .mii_select(1'b0),
    .cfg_rx_enable(1'b1),
    .start_packet(mon_start_packet),
    .error_bad_frame(mon_error_bad_frame),
    .error_bad_fcs(mon_error_bad_fcs)
);

// ================= environment bookkeeping, kept out of the reset cut ======
// Only what the ENVIRONMENT needs to remember; every oracle lives in
// `sva/targets_verilog_ethernet_mac_datapath.sv`.
reg [15:0] ftenv_injected = 16'd0;   // frames handed to the receive link

always @(posedge clk) begin
    if (rst) begin
        ftenv_injected <= 16'd0;
    end else if (src_frame_accepted) begin
        ftenv_injected <= ftenv_injected + 16'd1;
    end
end

endmodule

`resetall
