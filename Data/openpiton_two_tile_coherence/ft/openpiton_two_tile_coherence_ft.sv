// ===========================================================================
// Formal testbench: TWO OpenPiton cache tiles over a real P-Mesh.
//
// Each tile is the real `l15` plus the real `l2` slice, attached to its node's
// three routers exactly as `piton/design/chip/tile/rtl/tile.v` attaches them --
// `valrdy_to_credit` on the way in, `credit_to_valrdy` on the way out, one
// router per NoC per node:
//
//     NoC1  L1.5 -> router P in ...... router P out -> L2   (requests)
//     NoC2  L2   -> router P in ...... router P out -> L1.5 (responses, FWDs)
//     NoC3  L1.5 -> router P in ...... router P out -> L2   (FWDACKs, WBs)
//
// The mesh is 2x1: node (0,0) is tile 0, node (1,0) is tile 1. Address bit 6
// picks the home L2 (`HOME_ID_ADDR_POS_LOW is [11:6] and `config_system_tile_count
// = 2, so `l15_home_encoder` reduces it to addr[6]), which is what makes this a
// TWO-AGENT system: either L1.5 can miss to either L2 slice, and one L2 slice can
// hold a directory entry naming both L1.5s. That is the state
// `tasks/l15_l2_mshr_onehot` cannot reach -- its formal top has one L1.5, so no
// second agent exists to hold a conflicting permission.
//
// The memory controller hangs off the WEST link of node (0,0), which is where
// OpenPiton puts it: the L2 addresses `MSG_TYPE_LOAD_MEM` / `STORE_MEM` to chip
// id {1'b1, ...}, every router reads that as off-chip and routes toward
// (`OFF_CHIP_NODE_X, `OFF_CHIP_NODE_Y) = (0,0), and there `NOC_FBITS_MEM`
// (3'b010 == `FINAL_WEST) sends it out the west link.
//
// Environment models, all of them LEGALITY models -- they forbid nothing a real
// P-Mesh chip would allow:
//   * four bounded core request sources (two threads x two tiles) on the PCX
//     ports, holding val and payload stable until the L1.5 acks;
//   * one memory responder on the off-chip link, up to 16 requests outstanding
//     (= 2 x `L2_MSHR_ENTRIES, so it cannot be the binding constraint on how
//     many L2 MSHR entries are busy), answering at an adversarially chosen time
//     and addressing its ack back to whichever L2 sent the request, read off
//     that request's own third flit;
//   * free inputs `cpx_ack` and `mem_send`, fair by two assumptions declared in
//     the checker.
//
// Configuration held at the ordinary two-tile single-chip defaults:
// config_csm_en = 0 (no coherence-domain remap; the home is a pure function of
// the address), dmbr_l15_stall = 0, config_system_tile_count = 2,
// config_home_alloc_method = `HOME_ALLOC_LOW_ORDER_BITS, chipid = 0,
// coreid_x = tile index, coreid_y = 0, BIST idle.
// ===========================================================================

`include "define.tmp.h"
`include "l15.tmp.h"
`include "l2.tmp.h"
`include "network_define.v"

// ---------------------------------------------------------------------------
// One core-side requester. Holds `val` and the payload stable until the L1.5
// acknowledges, which is the CCX/PCX contract.
//
// The address window is deliberately narrow and SHARED between the two tiles:
//
//     address = { 30'd0, key[3:0], 6'd0 }
//
//   * bits [5:0] zero -- 64 B aligned, so each touched line is one 16 B L1.5
//     subline sitting alone in its 64 B L2 line and a subline vector is never
//     more than one bit. Nothing here depends on that; it keeps the shadow
//     directory keyed on one line identifier instead of two.
//   * bit [6] is the home selector AND the low bit of `L2_TAG_INDEX ([8:6]).
//   * bits [8:6] are the L2 set index, bit [9] a tag bit, so the sixteen keys
//     land four to an L1.5 set (index is addr[7:4]) -- exactly the L1.5's four
//     ways, so replacement pressure and writebacks are reachable without being
//     forced.
//
// Both tiles draw from the same sixteen keys, so both can be asking the same
// home L2 for the same line at once. That is the point of the task.
// ---------------------------------------------------------------------------
module tt_core_source (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire        start,
    input  wire [7:0]  seed,
    input  wire        granted,
    output wire        pending,
    output wire [39:0] address,
    output wire [4:0]  rqtype,
    output wire [2:0]  size,
    output wire        nc,
    output wire [1:0]  rplway
);
    reg       pending_f;
    reg [7:0] payload_f;

    wire launch = enable && !pending_f && start;

    assign pending = pending_f;

    assign address = {30'd0, payload_f[3:0], 6'd0};
    assign rqtype  = payload_f[4] ? `PCX_REQTYPE_STORE : `PCX_REQTYPE_LOAD;
    assign size    = 3'b011;
    assign nc      = 1'b0;
    assign rplway  = payload_f[7:6];

    always @(posedge clk) begin
        if (!reset_n) begin
            pending_f <= 1'b0;
            payload_f <= 8'd0;
        end else if (launch) begin
            pending_f <= 1'b1;
            payload_f <= seed;
        end else if (pending_f && granted) begin
            pending_f <= 1'b0;
        end
    end
endmodule

// ---------------------------------------------------------------------------
// Memory responder on the off-chip link, up to NOUT requests outstanding.
//
// Accepts a complete LOAD_MEM / STORE_MEM packet, then at an adversarially
// chosen later cycle emits the matching *_MEM_ACK. The ack echoes the request's
// header flit with MSG_TYPE, MSG_LENGTH and the four destination fields
// rewritten; every other field, MSG_MSHRID included, is returned unchanged, so
// the responder invents nothing the requester did not send.
//
// The destination comes from the request's own THIRD flit. `l2_encoder` builds a
// 192-bit header as {src..., addr..., dst...}, so flit 2 carries
// `MSG_SRC_CHIPID_ / `MSG_SRC_X_ / `MSG_SRC_Y_ at exactly the bit positions
// `MSG_DST_CHIPID / `MSG_DST_X / `MSG_DST_Y occupy in flit 0. Returning
// {flit2[63:34], `NOC_FBITS_L2} is therefore "send it back where it came from"
// and nothing more; with two L2 slices on the mesh there is no other way to
// answer the right one.
// ---------------------------------------------------------------------------
module tt_mem_responder #(
    parameter integer NOUT = 16,
    parameter integer PTRW = 5          // log2(NOUT)+1
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        free_send,

    input  wire        req_val,
    input  wire [63:0] req_data,
    output wire        req_rdy,

    output wire        rsp_val,
    output wire [63:0] rsp_data,
    input  wire        rsp_rdy,

    output wire        holding,
    output wire        sending,
    output wire [PTRW-1:0] occupancy
);
    localparam RX_HDR  = 2'd0;
    localparam RX_BODY = 2'd1;

    reg [63:0] hdr_q [0:NOUT-1];
    reg [63:0] src_q [0:NOUT-1];
    reg [PTRW-1:0] q_wr_f;
    reg [PTRW-1:0] q_rd_f;
    wire [PTRW-1:0] q_cnt   = q_wr_f - q_rd_f;
    wire            q_full  = (q_cnt >= NOUT[PTRW-1:0]);
    wire            q_empty = (q_cnt == {PTRW{1'b0}});
    wire [63:0] q_head     = hdr_q[q_rd_f[PTRW-2:0]];
    wire [63:0] q_head_src = src_q[q_rd_f[PTRW-2:0]];

    reg [1:0] rx_state_f;
    reg [7:0] rx_left_f;
    reg [7:0] rx_idx_f;          // flit index inside the packet being received

    localparam TX_IDLE = 2'd0;
    localparam TX_HDR  = 2'd1;
    localparam TX_BODY = 2'd2;

    reg [1:0] tx_state_f;
    reg [7:0] tx_left_f;

    wire hdr_is_load = (q_head[`MSG_TYPE] == `MSG_TYPE_LOAD_MEM);

    assign req_rdy = (rx_state_f == RX_BODY) || (!q_full);

    wire rx_fire = req_val && req_rdy;

    assign holding   = !q_empty;
    assign sending   = (tx_state_f != TX_IDLE);
    assign occupancy = q_cnt;

    reg [63:0] rsp_hdr;
    always @* begin
        rsp_hdr = q_head;
        rsp_hdr[`MSG_TYPE]        = hdr_is_load ? `MSG_TYPE_LOAD_MEM_ACK
                                                : `MSG_TYPE_STORE_MEM_ACK;
        rsp_hdr[`MSG_LENGTH]      = hdr_is_load ? 8'd8 : 8'd0;
        rsp_hdr[`MSG_DST_CHIPID]  = q_head_src[`MSG_SRC_CHIPID_];
        rsp_hdr[`MSG_DST_X]       = q_head_src[`MSG_SRC_X_];
        rsp_hdr[`MSG_DST_Y]       = q_head_src[`MSG_SRC_Y_];
        rsp_hdr[`MSG_DST_FBITS]   = `NOC_FBITS_L2;
    end

    assign rsp_val  = (tx_state_f != TX_IDLE);
    assign rsp_data = (tx_state_f == TX_HDR) ? rsp_hdr : 64'd0;

    wire tx_fire = rsp_val && rsp_rdy;

    integer qi;
    always @(posedge clk) begin
        if (!reset_n) begin
            rx_state_f <= RX_HDR;
            rx_left_f  <= 8'd0;
            rx_idx_f   <= 8'd0;
            q_wr_f     <= {PTRW{1'b0}};
            q_rd_f     <= {PTRW{1'b0}};
            tx_state_f <= TX_IDLE;
            tx_left_f  <= 8'd0;
            for (qi = 0; qi < NOUT; qi = qi + 1) begin
                hdr_q[qi] <= 64'd0;
                src_q[qi] <= 64'd0;
            end
        end else begin
            if (rx_fire) begin
                if (rx_state_f == RX_HDR) begin
                    hdr_q[q_wr_f[PTRW-2:0]] <= req_data;
                    src_q[q_wr_f[PTRW-2:0]] <= 64'd0;
                    rx_idx_f <= 8'd1;
                    if (req_data[`MSG_LENGTH] == 8'd0) begin
                        q_wr_f     <= q_wr_f + {{(PTRW-1){1'b0}}, 1'b1};
                        rx_state_f <= RX_HDR;
                        rx_idx_f   <= 8'd0;
                    end else begin
                        rx_left_f  <= req_data[`MSG_LENGTH];
                        rx_state_f <= RX_BODY;
                    end
                end else begin
                    if (rx_idx_f == 8'd2) src_q[q_wr_f[PTRW-2:0]] <= req_data;
                    rx_idx_f <= rx_idx_f + 8'd1;
                    if (rx_left_f == 8'd1) begin
                        q_wr_f     <= q_wr_f + {{(PTRW-1){1'b0}}, 1'b1};
                        rx_state_f <= RX_HDR;
                        rx_idx_f   <= 8'd0;
                    end else begin
                        rx_left_f <= rx_left_f - 8'd1;
                    end
                end
            end

            if (tx_state_f == TX_IDLE) begin
                if (!q_empty && free_send) begin
                    tx_state_f <= TX_HDR;
                    tx_left_f  <= hdr_is_load ? 8'd8 : 8'd0;
                end
            end else if (tx_fire) begin
                if (tx_state_f == TX_HDR) begin
                    if (tx_left_f == 8'd0) begin
                        tx_state_f <= TX_IDLE;
                        q_rd_f     <= q_rd_f + {{(PTRW-1){1'b0}}, 1'b1};
                    end else begin
                        tx_state_f <= TX_BODY;
                    end
                end else begin
                    if (tx_left_f == 8'd1) begin
                        tx_state_f <= TX_IDLE;
                        q_rd_f     <= q_rd_f + {{(PTRW-1){1'b0}}, 1'b1};
                    end else begin
                        tx_left_f <= tx_left_f - 8'd1;
                    end
                end
            end
        end
    end
endmodule

// ===========================================================================
// The formal top.
// ===========================================================================
module openpiton_two_tile_coherence_ft (
    input wire        clk,
    input wire        reset_n,
    input wire [3:0]  core_start,   // {tile1.t1, tile1.t0, tile0.t1, tile0.t0}
    input wire [31:0] core_seed,    // 8 bits per source, same order
    input wire [1:0]  cpx_ack,      // one per tile: the core drains CPX
    input wire        mem_send      // the memory controller answers
);
    localparam integer NTILE = 2;
    localparam integer X_TILES = 2;
    localparam integer Y_TILES = 1;
    localparam integer NOCS   = 3;
    localparam integer NT     = X_TILES * Y_TILES;

    // -----------------------------------------------------------------------
    // Post-reset qualification. `dynamic_node_top` registers reset_in once, so
    // the routers are still in reset for a cycle after reset_n rises. The DUT
    // sees the real reset; this bit only keeps the endpoints and the oracle
    // quiet until the fabric's own reset pipeline has cleared.
    // -----------------------------------------------------------------------
    reg [1:0] ready_sr;
    always @(posedge clk) begin
        if (!reset_n) ready_sr <= 2'b00;
        else          ready_sr <= {ready_sr[0], 1'b1};
    end
    wire dut_ready       = ready_sr[1];
    wire checker_reset_n = reset_n && dut_ready;

    // -----------------------------------------------------------------------
    // Mesh boundary
    // -----------------------------------------------------------------------
    wire [`DATA_WIDTH-1:0] pIn_data   [0:NT-1][0:NOCS-1];
    wire                   pIn_valid  [0:NT-1][0:NOCS-1];
    wire                   pIn_yummy  [0:NT-1][0:NOCS-1];
    wire [`DATA_WIDTH-1:0] pOut_data  [0:NT-1][0:NOCS-1];
    wire                   pOut_valid [0:NT-1][0:NOCS-1];
    wire                   pOut_yummy [0:NT-1][0:NOCS-1];
    wire                   pThanks    [0:NT-1][0:NOCS-1];

    wire [`DATA_WIDTH-1:0] wIn_data   [0:Y_TILES-1][0:NOCS-1];
    wire                   wIn_valid  [0:Y_TILES-1][0:NOCS-1];
    wire                   wIn_yummy  [0:Y_TILES-1][0:NOCS-1];
    wire [`DATA_WIDTH-1:0] wOut_data  [0:Y_TILES-1][0:NOCS-1];
    wire                   wOut_valid [0:Y_TILES-1][0:NOCS-1];
    wire                   wOut_yummy [0:Y_TILES-1][0:NOCS-1];

    coherence_mesh #(
        .X_TILES(X_TILES), .Y_TILES(Y_TILES), .NOCS(NOCS), .NT(NT)
    ) u_mesh (
        .clk(clk), .rst_n(reset_n),
        .pIn_data(pIn_data),   .pIn_valid(pIn_valid),   .pIn_yummy(pIn_yummy),
        .pOut_data(pOut_data), .pOut_valid(pOut_valid), .pOut_yummy(pOut_yummy),
        .pThanks(pThanks),
        .wIn_data(wIn_data),   .wIn_valid(wIn_valid),   .wIn_yummy(wIn_yummy),
        .wOut_data(wOut_data), .wOut_valid(wOut_valid), .wOut_yummy(wOut_yummy)
    );

    // -----------------------------------------------------------------------
    // Per-tile endpoint wires. `prod_*` is endpoint -> router (val/rdy, before
    // the credit transducer), `cons_*` is router -> endpoint (val/rdy, after
    // it). NoC index 0/1/2 = NoC1/NoC2/NoC3.
    // -----------------------------------------------------------------------
    wire [63:0] prod_data [0:NT-1][0:NOCS-1];
    wire        prod_val  [0:NT-1][0:NOCS-1];
    wire        prod_rdy  [0:NT-1][0:NOCS-1];
    wire [63:0] cons_data [0:NT-1][0:NOCS-1];
    wire        cons_val  [0:NT-1][0:NOCS-1];
    wire        cons_rdy  [0:NT-1][0:NOCS-1];

    genvar gt, gn;
    generate
        for (gt = 0; gt < NT; gt = gt + 1) begin : g_xduce_tile
            for (gn = 0; gn < NOCS; gn = gn + 1) begin : g_xduce_noc
                // 16 = the P input buffer of `dynamic_node_top` (it takes a
                // `dynamic_input_top_16` on P and a `dynamic_input_top_4` on
                // N/E/S/W), which is the depth tile.v hands valrdy_to_credit.
                valrdy_to_credit #(16, 5) u_v2c (
                    .clk(clk), .reset(!reset_n),
                    .data_in(prod_data[gt][gn]),
                    .valid_in(prod_val[gt][gn]),
                    .ready_in(prod_rdy[gt][gn]),
                    .data_out(pIn_data[gt][gn]),
                    .valid_out(pIn_valid[gt][gn]),
                    .yummy_out(pOut_yummy[gt][gn])
                );
                credit_to_valrdy u_c2v (
                    .clk(clk), .reset(!reset_n),
                    .data_in(pOut_data[gt][gn]),
                    .valid_in(pOut_valid[gt][gn]),
                    .yummy_in(pIn_yummy[gt][gn]),
                    .data_out(cons_data[gt][gn]),
                    .valid_out(cons_val[gt][gn]),
                    .ready_out(cons_rdy[gt][gn])
                );
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Core sources and the PCX arbitration, two threads per tile.
    // -----------------------------------------------------------------------
    wire [3:0]  src_pending;
    wire [39:0] src_address [0:3];
    wire [4:0]  src_rqtype  [0:3];
    wire [2:0]  src_size    [0:3];
    wire [3:0]  src_nc;
    wire [1:0]  src_rplway  [0:3];

    wire [1:0]  l15_transducer_ack;
    wire [1:0]  l15_transducer_header_ack;

    wire [1:0]  sel_t1;
    wire [1:0]  pcx_val;
    wire [39:0] pcx_addr [0:1];
    wire [4:0]  pcx_type [0:1];
    wire [2:0]  pcx_size [0:1];
    wire [1:0]  pcx_nc;
    wire [1:0]  pcx_rply [0:1];
    wire [1:0]  pcx_tid;

    genvar t, th;
    generate
        for (t = 0; t < NTILE; t = t + 1) begin : g_pcx
            // Fixed-priority arbitration between the two threads of this tile
            // for its single PCX port. Thread 0 wins.
            assign sel_t1[t]   = !src_pending[2*t] && src_pending[2*t+1];
            assign pcx_val[t]  = src_pending[2*t] || src_pending[2*t+1];
            assign pcx_addr[t] = sel_t1[t] ? src_address[2*t+1] : src_address[2*t];
            assign pcx_type[t] = sel_t1[t] ? src_rqtype[2*t+1]  : src_rqtype[2*t];
            assign pcx_size[t] = sel_t1[t] ? src_size[2*t+1]    : src_size[2*t];
            assign pcx_nc[t]   = sel_t1[t] ? src_nc[2*t+1]      : src_nc[2*t];
            assign pcx_rply[t] = sel_t1[t] ? src_rplway[2*t+1]  : src_rplway[2*t];
            assign pcx_tid[t]  = sel_t1[t] ? 1'b1 : 1'b0;

            for (th = 0; th < 2; th = th + 1) begin : g_src
                wire granted = pcx_val[t] && l15_transducer_ack[t] &&
                               (sel_t1[t] ? (th == 1) : (th == 0));
                tt_core_source u_src (
                    .clk(clk),
                    .reset_n(reset_n),
                    .enable(dut_ready),
                    .start(core_start[2*t+th]),
                    .seed(core_seed[8*(2*t+th) +: 8]),
                    .granted(granted),
                    .pending(src_pending[2*t+th]),
                    .address(src_address[2*t+th]),
                    .rqtype(src_rqtype[2*t+th]),
                    .size(src_size[2*t+th]),
                    .nc(src_nc[2*t+th]),
                    .rplway(src_rplway[2*t+th])
                );
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // The two tiles.
    // -----------------------------------------------------------------------
    wire [63:0] l15_t_data_0 [0:1];
    wire [63:0] l15_t_data_1 [0:1];
    wire [63:0] l15_t_data_2 [0:1];
    wire [63:0] l15_t_data_3 [0:1];

    generate
        for (t = 0; t < NTILE; t = t + 1) begin : g_tile
            l15 u_l15 (
                .clk(clk),
                .rst_n(reset_n),

                .transducer_l15_rqtype(pcx_type[t]),
                .transducer_l15_amo_op({`L15_AMO_OP_WIDTH{1'b0}}),
                .transducer_l15_nc(pcx_nc[t]),
                .transducer_l15_size(pcx_size[t]),
                .transducer_l15_threadid(pcx_tid[t]),
                .transducer_l15_prefetch(1'b0),
                .transducer_l15_invalidate_cacheline(1'b0),
                .transducer_l15_blockstore(1'b0),
                .transducer_l15_blockinitstore(1'b0),
                .transducer_l15_l1rplway(pcx_rply[t]),
                .transducer_l15_val(pcx_val[t]),
                .transducer_l15_address(pcx_addr[t]),
                .transducer_l15_data(64'd0),
                .transducer_l15_data_next_entry(64'd0),
                .transducer_l15_csm_data({`TLB_CSM_WIDTH{1'b0}}),

                .l15_transducer_ack(l15_transducer_ack[t]),
                .l15_transducer_header_ack(l15_transducer_header_ack[t]),

                .l15_transducer_val(),
                .l15_transducer_returntype(),
                .l15_transducer_l2miss(),
                .l15_transducer_error(),
                .l15_transducer_noncacheable(),
                .l15_transducer_atomic(),
                .l15_transducer_threadid(),
                .l15_transducer_prefetch(),
                .l15_transducer_f4b(),
                .l15_transducer_data_0(l15_t_data_0[t]),
                .l15_transducer_data_1(l15_t_data_1[t]),
                .l15_transducer_data_2(l15_t_data_2[t]),
                .l15_transducer_data_3(l15_t_data_3[t]),
                .l15_transducer_inval_icache_all_way(),
                .l15_transducer_inval_dcache_all_way(),
                .l15_transducer_inval_address_15_4(),
                .l15_transducer_cross_invalidate(),
                .l15_transducer_cross_invalidate_way(),
                .l15_transducer_inval_dcache_inval(),
                .l15_transducer_inval_icache_inval(),
                .l15_transducer_inval_way(),
                .l15_transducer_blockinitstore(),

                .transducer_l15_req_ack(cpx_ack[t]),

                .noc1_out_rdy(prod_rdy[t][0]),
                .noc2_in_val(cons_val[t][1]),
                .noc2_in_data(cons_data[t][1]),
                .noc3_out_rdy(prod_rdy[t][2]),
                .dmbr_l15_stall(1'b0),
                .chipid({`NOC_CHIPID_WIDTH{1'b0}}),
                .coreid_x(t[`NOC_X_WIDTH-1:0]),
                .coreid_y({`NOC_Y_WIDTH{1'b0}}),

                .config_l15_read_res_data_s3(64'd0),
                .config_csm_en(1'b0),
                .config_system_tile_count(32'd2),
                .config_home_alloc_method(`HOME_ALLOC_LOW_ORDER_BITS),
                .config_hmt_base({`L15_HMT_BASE_ADDR_WIDTH{1'b0}}),

                .noc1_out_val(prod_val[t][0]),
                .noc1_out_data(prod_data[t][0]),
                .noc2_in_rdy(cons_rdy[t][1]),
                .noc3_out_val(prod_val[t][2]),
                .noc3_out_data(prod_data[t][2]),
                .l15_dmbr_l1missIn(),
                .l15_dmbr_l1missTag(),
                .l15_dmbr_l2responseIn(),
                .l15_dmbr_l2missIn(),
                .l15_dmbr_l2missTag(),

                .l15_config_req_val_s2(),
                .l15_config_req_rw_s2(),
                .l15_config_write_req_data_s2(),
                .l15_config_req_address_s2(),

                .srams_rtap_data(),
                .rtap_srams_bist_command({`BIST_OP_WIDTH{1'b0}}),
                .rtap_srams_bist_data({`SRAM_WRAPPER_BUS_WIDTH{1'b0}})
            );

            l2 u_l2 (
                .clk(clk),
                .rst_n(reset_n),

                .chipid({`NOC_CHIPID_WIDTH{1'b0}}),
                .coreid_x(t[`NOC_X_WIDTH-1:0]),
                .coreid_y({`NOC_Y_WIDTH{1'b0}}),

                .noc1_valid_in(cons_val[t][0]),
                .noc1_data_in(cons_data[t][0]),
                .noc1_ready_in(cons_rdy[t][0]),

                .noc3_valid_in(cons_val[t][2]),
                .noc3_data_in(cons_data[t][2]),
                .noc3_ready_in(cons_rdy[t][2]),

                .noc2_valid_out(prod_val[t][1]),
                .noc2_data_out(prod_data[t][1]),
                .noc2_ready_out(prod_rdy[t][1]),

                .srams_rtap_data(),
                .rtap_srams_bist_command({`BIST_OP_WIDTH{1'b0}}),
                .rtap_srams_bist_data({`SRAM_WRAPPER_BUS_WIDTH{1'b0}})
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // The off-chip link at the west of node (0,0): the memory controller.
    //
    // NoC2 leaves the chip there (LOAD_MEM / STORE_MEM), NoC3 comes back in
    // (*_MEM_ACK). NoC1 never leaves the chip and NoC3 never does; those two
    // west outputs are drained (yummy tied high) and their west inputs idle.
    // -----------------------------------------------------------------------
    wire [63:0] mem_req_data;
    wire        mem_req_val;
    wire        mem_req_rdy;
    wire [63:0] mem_rsp_data;
    wire        mem_rsp_val;
    wire        mem_rsp_rdy;
    wire        mem_holding;
    wire        mem_sending;
    wire [4:0]  mem_occupancy;

    credit_to_valrdy u_mem_in (
        .clk(clk), .reset(!reset_n),
        .data_in(wOut_data[0][1]),
        .valid_in(wOut_valid[0][1]),
        .yummy_in(wOut_yummy[0][1]),
        .data_out(mem_req_data),
        .valid_out(mem_req_val),
        .ready_out(mem_req_rdy)
    );

    // 4 = the N/E/S/W input buffer of `dynamic_node_top`
    // (`dynamic_input_top_4`), which is what the west link feeds.
    valrdy_to_credit #(4, 3) u_mem_out (
        .clk(clk), .reset(!reset_n),
        .data_in(mem_rsp_data),
        .valid_in(mem_rsp_val),
        .ready_in(mem_rsp_rdy),
        .data_out(wIn_data[0][2]),
        .valid_out(wIn_valid[0][2]),
        .yummy_out(wIn_yummy[0][2])
    );

    assign wIn_data[0][0]   = 64'd0;
    assign wIn_valid[0][0]  = 1'b0;
    assign wIn_data[0][1]   = 64'd0;
    assign wIn_valid[0][1]  = 1'b0;
    assign wOut_yummy[0][0] = 1'b1;
    assign wOut_yummy[0][2] = 1'b1;

    tt_mem_responder #(.NOUT(16), .PTRW(5)) u_mem (
        .clk(clk),
        .reset_n(reset_n),
        .free_send(mem_send),
        .req_val(mem_req_val),
        .req_data(mem_req_data),
        .req_rdy(mem_req_rdy),
        .rsp_val(mem_rsp_val),
        .rsp_data(mem_rsp_data),
        .rsp_rdy(mem_rsp_rdy),
        .holding(mem_holding),
        .sending(mem_sending),
        .occupancy(mem_occupancy)
    );

    // =======================================================================
    // OBSERVATION. Everything below is combinational over DUT / environment
    // state; it names the wires the oracle watches and flattens the per-tile
    // arrays so the checker's ports stay plain vectors.
    // =======================================================================

    // ---- the L1.5 boundary of each tile -----------------------------------
    // NoC1 out (requests), NoC2 in (responses and FWDs), NoC3 out (FWDACKs,
    // writebacks). These are the L1.5's own pins, before/after the credit
    // transducer, which is where a coherence agent's traffic is observable.
    wire [1:0]   l15_n1_val;
    wire [1:0]   l15_n1_rdy;
    wire [127:0] l15_n1_data;
    wire [1:0]   l15_n2_val;
    wire [1:0]   l15_n2_rdy;
    wire [127:0] l15_n2_data;
    wire [1:0]   l15_n3_val;
    wire [1:0]   l15_n3_rdy;
    wire [127:0] l15_n3_data;

    // ---- the L2 boundary of each tile -------------------------------------
    wire [1:0]   l2_n1_val;
    wire [1:0]   l2_n1_rdy;
    wire [127:0] l2_n1_data;
    wire [1:0]   l2_n2_val;
    wire [1:0]   l2_n2_rdy;
    wire [127:0] l2_n2_data;
    wire [1:0]   l2_n3_val;
    wire [1:0]   l2_n3_rdy;
    wire [127:0] l2_n3_data;

    generate
        for (t = 0; t < NTILE; t = t + 1) begin : g_obs
            assign l15_n1_val[t]           = prod_val[t][0];
            assign l15_n1_rdy[t]           = prod_rdy[t][0];
            assign l15_n1_data[64*t +: 64] = prod_data[t][0];
            assign l15_n2_val[t]           = cons_val[t][1];
            assign l15_n2_rdy[t]           = cons_rdy[t][1];
            assign l15_n2_data[64*t +: 64] = cons_data[t][1];
            assign l15_n3_val[t]           = prod_val[t][2];
            assign l15_n3_rdy[t]           = prod_rdy[t][2];
            assign l15_n3_data[64*t +: 64] = prod_data[t][2];

            assign l2_n1_val[t]            = cons_val[t][0];
            assign l2_n1_rdy[t]            = cons_rdy[t][0];
            assign l2_n1_data[64*t +: 64]  = cons_data[t][0];
            assign l2_n2_val[t]            = prod_val[t][1];
            assign l2_n2_rdy[t]            = prod_rdy[t][1];
            assign l2_n2_data[64*t +: 64]  = prod_data[t][1];
            assign l2_n3_val[t]            = cons_val[t][2];
            assign l2_n3_rdy[t]            = cons_rdy[t][2];
            assign l2_n3_data[64*t +: 64]  = cons_data[t][2];
        end
    endgenerate

    // ---- L2 MSHR pools, both slices ---------------------------------------
    wire [15:0] l2_mshr_busy;      // {tile1[7:0], tile0[7:0]}
    wire [15:0] l2_mshr_wait;
    wire [15:0] l2_mshr_pend;
    wire [7:0]  l2_empty_slots;    // {tile1[3:0], tile0[3:0]}
    wire [47:0] l2_mshr_cmp_addr_flat;   // 3 bits x 8 entries x 2 tiles
    wire [31:0] l2_mshr_state_flat;      // 2 bits x 8 entries x 2 tiles

    genvar m;
    generate
        for (t = 0; t < NTILE; t = t + 1) begin : g_l2pool
            assign l2_empty_slots[4*t +: 4] = g_tile[t].u_l2.mshr_empty_slots;
            for (m = 0; m < 8; m = m + 1) begin : g_l2e
                assign l2_mshr_busy[8*t + m] =
                    (g_tile[t].u_l2.mshr_wrap.state_mem_f[m] != `L2_MSHR_STATE_INVAL);
                assign l2_mshr_wait[8*t + m] =
                    (g_tile[t].u_l2.mshr_wrap.state_mem_f[m] == `L2_MSHR_STATE_WAIT);
                assign l2_mshr_pend[8*t + m] =
                    (g_tile[t].u_l2.mshr_wrap.state_mem_f[m] == `L2_MSHR_STATE_PENDING);
                assign l2_mshr_state_flat[16*t + 2*m +: 2] =
                    g_tile[t].u_l2.mshr_wrap.state_mem_f[m];
                assign l2_mshr_cmp_addr_flat[24*t + 3*m +: 3] =
                    g_tile[t].u_l2.mshr_wrap.data_mem_f[m][`L2_MSHR_CMP_ADDR];
            end
        end
    endgenerate

    // ---- L1.5 miss trackers, 3 classes x 2 threads x 2 tiles --------------
    wire [11:0] l15_mshr_val;
    generate
        for (t = 0; t < NTILE; t = t + 1) begin : g_l15pool
            assign l15_mshr_val[6*t +: 6] = {
                g_tile[t].u_l15.mshr.ifill_val[1],
                g_tile[t].u_l15.mshr.st_val[1],
                g_tile[t].u_l15.mshr.ld_val[1],
                g_tile[t].u_l15.mshr.ifill_val[0],
                g_tile[t].u_l15.mshr.st_val[0],
                g_tile[t].u_l15.mshr.ld_val[0]
            };
        end
    endgenerate

    // ---- channel blockage, per tile ---------------------------------------
    wire [1:0] noc1_blocked;
    wire [1:0] noc2_blocked;
    wire [1:0] noc3_blocked;
    generate
        for (t = 0; t < NTILE; t = t + 1) begin : g_blk
            assign noc1_blocked[t] = l15_n1_val[t] && !l15_n1_rdy[t];
            assign noc2_blocked[t] = l2_n2_val[t]  && !l2_n2_rdy[t];
            assign noc3_blocked[t] = l15_n3_val[t] && !l15_n3_rdy[t];
        end
    endgenerate

    wire mem_req_blocked = mem_req_val && !mem_req_rdy;
    wire mem_rsp_blocked = mem_rsp_val && !mem_rsp_rdy;

    openpiton_two_tile_coherence_checker u_checker (
        .clk(clk),
        .reset_n(checker_reset_n),

        .l15_n1_val(l15_n1_val),   .l15_n1_rdy(l15_n1_rdy),   .l15_n1_data(l15_n1_data),
        .l15_n2_val(l15_n2_val),   .l15_n2_rdy(l15_n2_rdy),   .l15_n2_data(l15_n2_data),
        .l15_n3_val(l15_n3_val),   .l15_n3_rdy(l15_n3_rdy),   .l15_n3_data(l15_n3_data),

        .l2_mshr_busy(l2_mshr_busy),
        .l2_mshr_wait(l2_mshr_wait),
        .l2_mshr_pend(l2_mshr_pend),
        .l2_empty_slots(l2_empty_slots),
        .l15_mshr_val(l15_mshr_val),

        .noc1_blocked(noc1_blocked),
        .noc2_blocked(noc2_blocked),
        .noc3_blocked(noc3_blocked),
        .mem_req_blocked(mem_req_blocked),
        .mem_rsp_blocked(mem_rsp_blocked),

        .mem_holding(mem_holding),
        .mem_occupancy(mem_occupancy),
        .core_active(src_pending),
        .cpx_ack(cpx_ack),
        .mem_send(mem_send)
    );
endmodule
