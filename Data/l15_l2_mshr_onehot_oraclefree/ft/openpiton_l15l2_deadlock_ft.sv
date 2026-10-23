// ===========================================================================
// Formal testbench for the OpenPiton L1.5 <-> L2 request / response /
// invalidate triangle.
//
// The DUT is the real `l15` and the real `l2`, wired to each other exactly as
// `tile.v` wires them to the P-Mesh router, with three environment models:
//
//   * a bounded core request source on the transducer (PCX) port,
//   * a NOC2 demultiplexer that separates L2->L1.5 responses from L2->memory
//     requests (OpenPiton multiplexes both onto the same channel),
//   * a one-outstanding-per-slot memory responder that returns
//     LOAD/STORE_MEM_ACK on NOC3 at an adversarially chosen time, and a
//     packet-atomic NOC3 merge.
//
// Every environment model is a *legality* model: it restricts nothing the real
// P-Mesh would allow. The memory responder queues up to 8 requests, which is
// `L2_MSHR_ENTRIES, so it cannot be the binding constraint on how many L2 MSHR
// entries are simultaneously busy.
//
// Other configuration held at the ordinary single-chip defaults:
// config_csm_en = 0, dmbr_l15_stall = 0, config_system_tile_count = 1,
// chipid = coreid_x = coreid_y = 0, BIST idle.
// ===========================================================================

`include "define.tmp.h"
`include "l15.tmp.h"
`include "l2.tmp.h"

// ---------------------------------------------------------------------------
// One core-side requester.  Holds `val` and the payload stable until the L1.5
// acknowledges, which is the CCX/PCX contract.
// ---------------------------------------------------------------------------
module l15l2_core_source (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire        start,
    input  wire [15:0] seed,
    input  wire        granted,
    output wire        pending,
    output wire [39:0] address,
    output wire [4:0]  rqtype,
    output wire [2:0]  size,
    output wire        nc,
    output wire [1:0]  rplway
);
    reg        pending_f;
    reg [15:0] payload_f;

    wire launch = enable && !pending_f && start;

    assign pending = pending_f;

    // Address type field [39:32] held at 0 so no diagnostic / config-register
    // / HMC special access is ever decoded; traffic is ordinary cacheable
    // load / store / ifill.  Low 4 bits held at 0 (16 B aligned).  The
    // remaining 8 bits sweep a 4 KB window, which spans several L1.5 sets,
    // several L2 sets and provokes way conflicts at both levels.
    assign address = {8'h00, 20'h0, payload_f[11:4], 4'h0};
    assign rqtype  = (payload_f[13:12] == 2'b00) ? `PCX_REQTYPE_LOAD  :
                     (payload_f[13:12] == 2'b01) ? `PCX_REQTYPE_STORE :
                     (payload_f[13:12] == 2'b10) ? `PCX_REQTYPE_IFILL :
                                                   `PCX_REQTYPE_LOAD;
    assign size    = 3'b011;
    assign nc      = 1'b0;
    assign rplway  = payload_f[15:14];

    always @(posedge clk) begin
        if (!reset_n) begin
            pending_f <= 1'b0;
            payload_f <= 16'd0;
        end else if (launch) begin
            pending_f <= 1'b1;
            payload_f <= seed;
        end else if (pending_f && granted) begin
            pending_f <= 1'b0;
        end
    end
endmodule

// ---------------------------------------------------------------------------
// Memory responder, up to NOUT requests outstanding.
//
// Accepts a complete LOAD_MEM / STORE_MEM packet off NOC2, then at an
// adversarially chosen later cycle emits the matching *_MEM_ACK on NOC3.
// The ack echoes the request's header flit with MSG_TYPE and MSG_LENGTH
// rewritten; every other field, MSG_MSHRID included, is returned unchanged,
// so the responder invents nothing the requester did not send.
// ---------------------------------------------------------------------------
module l15l2_mem_responder (
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
    output wire        sending
);
    localparam RX_HDR  = 2'd0;
    localparam RX_BODY = 2'd1;

    localparam NOUT = 8;   // = `L2_MSHR_ENTRIES
    reg [63:0] hdr_q [0:NOUT-1];
    reg [3:0]  q_wr_f;
    reg [3:0]  q_rd_f;
    wire [3:0] q_cnt   = q_wr_f - q_rd_f;
    wire       q_full  = (q_cnt >= NOUT);
    wire       q_empty = (q_cnt == 4'd0);
    wire [63:0] q_head = hdr_q[q_rd_f[2:0]];

    reg [1:0]  rx_state_f;
    reg [7:0]  rx_left_f;

    localparam TX_IDLE = 2'd0;
    localparam TX_HDR  = 2'd1;
    localparam TX_BODY = 2'd2;

    reg [1:0] tx_state_f;
    reg [7:0] tx_left_f;

    wire hdr_is_load = (q_head[`MSG_TYPE] == `MSG_TYPE_LOAD_MEM);

    // Accept mid-packet always; accept a NEW packet whenever the queue has
    // room, independently of whether a response is being sent.
    assign req_rdy = (rx_state_f == RX_BODY) || (!q_full);

    wire rx_fire = req_val && req_rdy;

    assign holding = !q_empty;
    assign sending = (tx_state_f != TX_IDLE);

    reg [63:0] rsp_hdr;
    always @* begin
        rsp_hdr = q_head;
        rsp_hdr[`MSG_TYPE]   = hdr_is_load ? `MSG_TYPE_LOAD_MEM_ACK
                                           : `MSG_TYPE_STORE_MEM_ACK;
        rsp_hdr[`MSG_LENGTH] = hdr_is_load ? 8'd8 : 8'd0;
    end

    assign rsp_val  = (tx_state_f != TX_IDLE);
    assign rsp_data = (tx_state_f == TX_HDR) ? rsp_hdr : 64'd0;

    wire tx_fire = rsp_val && rsp_rdy;

    integer qi;
    always @(posedge clk) begin
        if (!reset_n) begin
            rx_state_f <= RX_HDR;
            rx_left_f  <= 8'd0;
            q_wr_f     <= 4'd0;
            q_rd_f     <= 4'd0;
            tx_state_f <= TX_IDLE;
            tx_left_f  <= 8'd0;
            for (qi = 0; qi < NOUT; qi = qi + 1) hdr_q[qi] <= 64'd0;
        end else begin
            if (rx_fire) begin
                if (rx_state_f == RX_HDR) begin
                    hdr_q[q_wr_f[2:0]] <= req_data;
                    if (req_data[`MSG_LENGTH] == 8'd0) begin
                        q_wr_f     <= q_wr_f + 4'd1;
                        rx_state_f <= RX_HDR;
                    end else begin
                        rx_left_f  <= req_data[`MSG_LENGTH];
                        rx_state_f <= RX_BODY;
                    end
                end else begin
                    if (rx_left_f == 8'd1) begin
                        q_wr_f     <= q_wr_f + 4'd1;
                        rx_state_f <= RX_HDR;
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
                        q_rd_f     <= q_rd_f + 4'd1;
                    end else begin
                        tx_state_f <= TX_BODY;
                    end
                end else begin
                    if (tx_left_f == 8'd1) begin
                        tx_state_f <= TX_IDLE;
                        q_rd_f     <= q_rd_f + 4'd1;
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
module openpiton_l15l2_deadlock_ft (
    input wire        clk,
    input wire        reset_n,
    input wire [1:0]  core_start,
    input wire [31:0] core_seed,
    input wire        cpx_ack,
    input wire        mem_send
);
    // -----------------------------------------------------------------------
    // Post-reset qualification for the checker only.  The DUT itself sees the
    // real reset; this bit exists so the target is not evaluated in the very
    // first cycle out of reset.
    // -----------------------------------------------------------------------
    reg dut_ready;
    always @(posedge clk) begin
        if (!reset_n) dut_ready <= 1'b0;
        else          dut_ready <= 1'b1;
    end
    wire checker_reset_n = reset_n && dut_ready;

    // -----------------------------------------------------------------------
    // Core-side sources: one per L1.5 thread.
    // -----------------------------------------------------------------------
    wire [1:0]  src_pending;
    wire [39:0] src_address [0:1];
    wire [4:0]  src_rqtype  [0:1];
    wire [2:0]  src_size    [0:1];
    wire [1:0]  src_nc;
    wire [1:0]  src_rplway  [0:1];

    wire        l15_transducer_ack;
    wire        l15_transducer_header_ack;

    // Fixed-priority arbitration between the two threads for the single PCX
    // port.  Thread 0 wins; the L1.5 acks whichever it is presented with.
    wire        sel_t1   = !src_pending[0] && src_pending[1];
    wire        pcx_val  = src_pending[0] || src_pending[1];
    wire [39:0] pcx_addr = sel_t1 ? src_address[1] : src_address[0];
    wire [4:0]  pcx_type = sel_t1 ? src_rqtype[1]  : src_rqtype[0];
    wire [2:0]  pcx_size = sel_t1 ? src_size[1]    : src_size[0];
    wire        pcx_nc   = sel_t1 ? src_nc[1]      : src_nc[0];
    wire [1:0]  pcx_rply = sel_t1 ? src_rplway[1]  : src_rplway[0];
    wire        pcx_tid  = sel_t1 ? 1'b1 : 1'b0;

    genvar t;
    generate
        for (t = 0; t < 2; t = t + 1) begin : g_src
            wire granted = pcx_val && l15_transducer_ack &&
                           (sel_t1 ? (t == 1) : (t == 0));
            l15l2_core_source u_src (
                .clk(clk),
                .reset_n(reset_n),
                .enable(dut_ready),
                .start(core_start[t]),
                .seed(core_seed[16*t +: 16]),
                .granted(granted),
                .pending(src_pending[t]),
                .address(src_address[t]),
                .rqtype(src_rqtype[t]),
                .size(src_size[t]),
                .nc(src_nc[t]),
                .rplway(src_rplway[t])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // NOC wires
    // -----------------------------------------------------------------------
    wire        l15_noc1_val;
    wire [63:0] l15_noc1_data;
    wire        l15_noc1_rdy;

    wire        l15_noc2_val;
    wire [63:0] l15_noc2_data;
    wire        l15_noc2_rdy;

    wire        l15_noc3_val;
    wire [63:0] l15_noc3_data;
    wire        l15_noc3_rdy;

    wire        l2_noc2_val;
    wire [63:0] l2_noc2_data;
    wire        l2_noc2_rdy;

    wire        l2_noc3_val;
    wire [63:0] l2_noc3_data;
    wire        l2_noc3_rdy;

    // -----------------------------------------------------------------------
    // The L1.5
    // -----------------------------------------------------------------------
    wire [63:0] l15_t_data_0, l15_t_data_1, l15_t_data_2, l15_t_data_3;

    l15 u_l15 (
        .clk(clk),
        .rst_n(reset_n),

        .transducer_l15_rqtype(pcx_type),
        .transducer_l15_amo_op({`L15_AMO_OP_WIDTH{1'b0}}),
        .transducer_l15_nc(pcx_nc),
        .transducer_l15_size(pcx_size),
        .transducer_l15_threadid(pcx_tid),
        .transducer_l15_prefetch(1'b0),
        .transducer_l15_invalidate_cacheline(1'b0),
        .transducer_l15_blockstore(1'b0),
        .transducer_l15_blockinitstore(1'b0),
        .transducer_l15_l1rplway(pcx_rply),
        .transducer_l15_val(pcx_val),
        .transducer_l15_address(pcx_addr),
        .transducer_l15_data(64'd0),
        .transducer_l15_data_next_entry(64'd0),
        .transducer_l15_csm_data({`TLB_CSM_WIDTH{1'b0}}),

        .l15_transducer_ack(l15_transducer_ack),
        .l15_transducer_header_ack(l15_transducer_header_ack),

        .l15_transducer_val(),
        .l15_transducer_returntype(),
        .l15_transducer_l2miss(),
        .l15_transducer_error(),
        .l15_transducer_noncacheable(),
        .l15_transducer_atomic(),
        .l15_transducer_threadid(),
        .l15_transducer_prefetch(),
        .l15_transducer_f4b(),
        .l15_transducer_data_0(l15_t_data_0),
        .l15_transducer_data_1(l15_t_data_1),
        .l15_transducer_data_2(l15_t_data_2),
        .l15_transducer_data_3(l15_t_data_3),
        .l15_transducer_inval_icache_all_way(),
        .l15_transducer_inval_dcache_all_way(),
        .l15_transducer_inval_address_15_4(),
        .l15_transducer_cross_invalidate(),
        .l15_transducer_cross_invalidate_way(),
        .l15_transducer_inval_dcache_inval(),
        .l15_transducer_inval_icache_inval(),
        .l15_transducer_inval_way(),
        .l15_transducer_blockinitstore(),

        .transducer_l15_req_ack(cpx_ack),

        .noc1_out_rdy(l15_noc1_rdy),
        .noc2_in_val(l15_noc2_val),
        .noc2_in_data(l15_noc2_data),
        .noc3_out_rdy(l15_noc3_rdy),
        .dmbr_l15_stall(1'b0),
        .chipid({`NOC_CHIPID_WIDTH{1'b0}}),
        .coreid_x({`NOC_X_WIDTH{1'b0}}),
        .coreid_y({`NOC_Y_WIDTH{1'b0}}),

        .config_l15_read_res_data_s3(64'd0),
        .config_csm_en(1'b0),
        .config_system_tile_count(32'd1),
        .config_home_alloc_method({`HOME_ALLOC_METHOD_WIDTH{1'b0}}),
        .config_hmt_base({`L15_HMT_BASE_ADDR_WIDTH{1'b0}}),

        .noc1_out_val(l15_noc1_val),
        .noc1_out_data(l15_noc1_data),
        .noc2_in_rdy(l15_noc2_rdy),
        .noc3_out_val(l15_noc3_val),
        .noc3_out_data(l15_noc3_data),
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

    // -----------------------------------------------------------------------
    // The L2
    // -----------------------------------------------------------------------
    l2 u_l2 (
        .clk(clk),
        .rst_n(reset_n),

        .chipid({`NOC_CHIPID_WIDTH{1'b0}}),
        .coreid_x({`NOC_X_WIDTH{1'b0}}),
        .coreid_y({`NOC_Y_WIDTH{1'b0}}),

        .noc1_valid_in(l15_noc1_val),
        .noc1_data_in(l15_noc1_data),
        .noc1_ready_in(l15_noc1_rdy),

        .noc3_valid_in(l2_noc3_val),
        .noc3_data_in(l2_noc3_data),
        .noc3_ready_in(l2_noc3_rdy),

        .noc2_valid_out(l2_noc2_val),
        .noc2_data_out(l2_noc2_data),
        .noc2_ready_out(l2_noc2_rdy),

        .srams_rtap_data(),
        .rtap_srams_bist_command({`BIST_OP_WIDTH{1'b0}}),
        .rtap_srams_bist_data({`SRAM_WRAPPER_BUS_WIDTH{1'b0}})
    );

    // -----------------------------------------------------------------------
    // NOC2 demultiplexer.  OpenPiton multiplexes L2->L1.5 responses and
    // L2->memory requests onto NOC2, so the destination is decided from the
    // packet's own header flit and held for the whole packet.
    // -----------------------------------------------------------------------
    reg       n2_in_body_f;
    reg [7:0] n2_left_f;
    reg       n2_to_mem_f;

    wire n2_hdr_is_mem =
        (l2_noc2_data[`MSG_TYPE] == `MSG_TYPE_LOAD_MEM) ||
        (l2_noc2_data[`MSG_TYPE] == `MSG_TYPE_STORE_MEM);

    wire n2_to_mem = n2_in_body_f ? n2_to_mem_f : n2_hdr_is_mem;

    wire        mem_req_val;
    wire        mem_req_rdy;

    assign l15_noc2_val  = l2_noc2_val && !n2_to_mem;
    assign l15_noc2_data = l2_noc2_data;
    assign mem_req_val   = l2_noc2_val &&  n2_to_mem;
    assign l2_noc2_rdy   = n2_to_mem ? mem_req_rdy : l15_noc2_rdy;

    wire n2_fire = l2_noc2_val && l2_noc2_rdy;

    always @(posedge clk) begin
        if (!reset_n) begin
            n2_in_body_f <= 1'b0;
            n2_left_f    <= 8'd0;
            n2_to_mem_f  <= 1'b0;
        end else if (n2_fire) begin
            if (!n2_in_body_f) begin
                n2_to_mem_f <= n2_hdr_is_mem;
                if (l2_noc2_data[`MSG_LENGTH] != 8'd0) begin
                    n2_in_body_f <= 1'b1;
                    n2_left_f    <= l2_noc2_data[`MSG_LENGTH];
                end
            end else begin
                if (n2_left_f == 8'd1) n2_in_body_f <= 1'b0;
                else                   n2_left_f    <= n2_left_f - 8'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Memory responder
    // -----------------------------------------------------------------------
    wire        mem_rsp_val;
    wire [63:0] mem_rsp_data;
    wire        mem_rsp_rdy;
    wire        mem_holding;
    wire        mem_sending;

    l15l2_mem_responder u_mem (
        .clk(clk),
        .reset_n(reset_n),
        .free_send(mem_send),
        .req_val(mem_req_val),
        .req_data(l2_noc2_data),
        .req_rdy(mem_req_rdy),
        .rsp_val(mem_rsp_val),
        .rsp_data(mem_rsp_data),
        .rsp_rdy(mem_rsp_rdy),
        .holding(mem_holding),
        .sending(mem_sending)
    );

    // -----------------------------------------------------------------------
    // NOC3 merge -- packet-atomic, memory first when both are idle.
    // -----------------------------------------------------------------------
    reg       n3_busy_f;
    reg       n3_owner_f;    // 0 = L1.5, 1 = memory
    reg [7:0] n3_left_f;

    wire n3_pick_mem = n3_busy_f ? n3_owner_f
                                 : (mem_rsp_val ? 1'b1 : 1'b0);

    assign l2_noc3_val  = n3_pick_mem ? mem_rsp_val : l15_noc3_val;
    assign l2_noc3_data = n3_pick_mem ? mem_rsp_data : l15_noc3_data;
    assign mem_rsp_rdy  =  n3_pick_mem && l2_noc3_rdy;
    assign l15_noc3_rdy = !n3_pick_mem && l2_noc3_rdy;

    wire n3_fire = l2_noc3_val && l2_noc3_rdy;

    always @(posedge clk) begin
        if (!reset_n) begin
            n3_busy_f  <= 1'b0;
            n3_owner_f <= 1'b0;
            n3_left_f  <= 8'd0;
        end else if (n3_fire) begin
            if (!n3_busy_f) begin
                if (l2_noc3_data[`MSG_LENGTH] != 8'd0) begin
                    n3_busy_f  <= 1'b1;
                    n3_owner_f <= n3_pick_mem;
                    n3_left_f  <= l2_noc3_data[`MSG_LENGTH];
                end
            end else begin
                if (n3_left_f == 8'd1) n3_busy_f <= 1'b0;
                else                   n3_left_f <= n3_left_f - 8'd1;
            end
        end
    end

    // =======================================================================
    // OBSERVATION -- everything below is combinational over DUT state.
    // =======================================================================

    // ---- L1.5 trackers: 6 = 3 classes x 2 threads -------------------------
    // Index: 0 = t0.LD, 1 = t0.ST, 2 = t0.IFILL, 3 = t1.LD, 4 = t1.ST,
    //        5 = t1.IFILL
    wire [5:0] l15_mshr_val = {
        u_l15.mshr.ifill_val[1], u_l15.mshr.st_val[1], u_l15.mshr.ld_val[1],
        u_l15.mshr.ifill_val[0], u_l15.mshr.st_val[0], u_l15.mshr.ld_val[0]
    };

    // ---- L2 trackers: 8 MSHR entries --------------------------------------
    wire [7:0] l2_mshr_busy;
    wire [7:0] l2_mshr_wait;
    wire [7:0] l2_mshr_pend;
    genvar m;
    generate
        for (m = 0; m < 8; m = m + 1) begin : g_l2_mshr
            assign l2_mshr_busy[m] =
                (u_l2.mshr_wrap.state_mem_f[m] != `L2_MSHR_STATE_INVAL);
            assign l2_mshr_wait[m] =
                (u_l2.mshr_wrap.state_mem_f[m] == `L2_MSHR_STATE_WAIT);
            assign l2_mshr_pend[m] =
                (u_l2.mshr_wrap.state_mem_f[m] == `L2_MSHR_STATE_PENDING);
        end
    endgenerate

    // ---- channel blockage --------------------------------------------------
    wire noc1_blocked = l15_noc1_val && !l15_noc1_rdy;
    wire noc2_l15_blocked = l2_noc2_val && !n2_to_mem && !l15_noc2_rdy;
    wire noc3_blocked = l2_noc3_val && !l2_noc3_rdy;

    // ---- L2 MSHR pool occupancy -------------------------------------------
    wire [3:0] l2_empty_slots = u_l2.mshr_empty_slots;

    // ---- the conserved quantity --------------------------------------------
    // `L2_MSHR_CMP_ADDR == `L2_TAG_INDEX, 3 bits at this build, per entry.
    // Flattened so the checker port stays a plain vector.
    wire [23:0] l2_mshr_cmp_addr_flat;
    wire [15:0] l2_mshr_state_flat;
    generate
        for (m = 0; m < 8; m = m + 1) begin : g_l2_cons
            assign l2_mshr_cmp_addr_flat[3*m +: 3] =
                u_l2.mshr_wrap.data_mem_f[m][`L2_MSHR_CMP_ADDR];
            assign l2_mshr_state_flat[2*m +: 2] =
                u_l2.mshr_wrap.state_mem_f[m];
        end
    endgenerate

    openpiton_l15l2_deadlock_checker u_checker (
        .clk(clk),
        .reset_n(checker_reset_n),
        .l15_mshr_val(l15_mshr_val),
        .l2_mshr_busy(l2_mshr_busy),
        .l2_mshr_wait(l2_mshr_wait),
        .l2_mshr_pend(l2_mshr_pend),
        .l2_empty_slots(l2_empty_slots),
        .noc1_blocked(noc1_blocked),
        .noc2_l15_blocked(noc2_l15_blocked),
        .noc3_blocked(noc3_blocked),
        .mem_holding(mem_holding),
        .core_active(src_pending),
        .cpx_ack(cpx_ack),
        .mem_send(mem_send),
        .l2_mshr_cmp_addr_flat(l2_mshr_cmp_addr_flat),
        .l2_mshr_state_flat(l2_mshr_state_flat)
    );
endmodule
