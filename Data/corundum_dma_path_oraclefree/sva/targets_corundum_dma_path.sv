// ===========================================================================
// ORACLE-FREE candidate targets for Corundum's descriptor / DMA / completion
// datapath.
//
// Bound into `corundum_dma_path_ft`, so every reference below is a
// hierarchical name from that top.  Nothing here is an assumption.
//
// WHAT IS DIFFERENT FROM THE PARENT PACKAGE.  `tasks/corundum_dma_path`
// carries a reference model: shadow queues of dequeue requests and started
// fetches, a recomputed `host_word()`, tag-keyed outstanding sets for the two
// DMA channels and the four queue managers, per-ring post/take counters and
// eight saturating wait counters -- 25 modelled signals across 9 `always_ff`
// blocks.  Ten of its fifteen hard targets are stated against that model, so
// the modelling, which is the part we want to measure an agent doing, was
// already done by whoever wrote the package.
//
// This file re-states those obligations WITHOUT a model.  Every target below
// but two is a property of
//
//   * the design's OWN registers -- desc_fetch's descriptor table and its
//     three pointers, cpl_write's completion table, the four queue managers'
//     operation tables and `queue_ram` producer / consumer pointers;
//   * the design's OWN wires at a boundary handshake;
//   * SVA sampled-value functions and property operators -- `$past`,
//     `$stable`, `$countones`, `$onehot0`, `until_with`, and bounded
//     `##[1:N]` windows.
//
// There is no `always_ff`, no shadow queue, no expected-value register and no
// wait counter here except in the two targets marked ORACLE-DEPENDENT, where
// the obligation is a COUNT over the whole chain and no property of the
// design's own state expresses it.
//
// A bounded-response or deadlock obligation that the parent wrote as a bound
// on a saturating counter is written here as a bounded window, `a |-> ##[1:N]
// b`.  That is the same claim with the same N and it needs no checker state.
//
// Ring geometry the address targets assume, and where it comes from: the four
// descriptor rings are configured by `env_cfg_dq0/1` at 0x10000, 0x11000,
// 0x20000, 0x21000 with 4 entries of 16 bytes; the four completion rings by
// `env_cfg_cq0/1` at 0x40000, 0x41000, 0x80000, 0x81000 with 4 entries of 8
// bytes.  Those constants are the FORMAL TOP's, not the design's.
// ===========================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module corundum_dma_targets (input wire clk, input wire rst);

// ------------------------------------------------------------------ sizes
localparam PORTS            = 2;
localparam DESC_TABLE_SIZE  = 4;
localparam CPL_TABLE_SIZE   = 4;
localparam OP_TABLE_SIZE    = 4;
localparam RING_SIZE        = 4;
localparam SAT              = 10'd1023;

// Bounds for the bounded-response / deadlock windows.  Same numbers the
// parent package's saturating counters were compared against.
localparam int N_FETCH   = 255;   // request accepted -> status returned
localparam int N_DESC    = 255;   // fetch started    -> descriptor delivered
localparam int N_CPL     = 255;   // cpl request      -> status returned
localparam int N_STALL   = 255;   // work outstanding -> some boundary event
localparam int N_FULL    = 255;   // desc_fetch table full

// The most a descriptor ring's producer pointer can lead an entry the design
// is handing out: RING_SIZE entries posted and not yet taken, plus the
// operations already taken and not yet committed, plus the two pipeline
// stages between the `queue_ram` read and the response.  The claim being
// made is the LOWER bound -- an entry handed out is one the driver posted --
// and this upper bound is only there to catch the wrap that an over-dequeue
// would show as a near-2**16 difference.
localparam DQ_LAG_MAX = 16'd12;

// ================================================================== taps ==

// -- descriptor fetch request / status --------------------------------------
wire        df_req_sel   = corundum_dma_path_ft.df_req_sel;
wire        df_req_queue = corundum_dma_path_ft.df_req_queue;
wire [3:0]  df_req_tag   = corundum_dma_path_ft.df_req_tag;
wire        df_req_valid = corundum_dma_path_ft.df_req_valid;
wire        df_req_ready = corundum_dma_path_ft.df_req_ready;
wire        df_req_fire  = df_req_valid && df_req_ready;

wire        df_st_queue  = corundum_dma_path_ft.df_st_queue;
wire        df_st_cpl    = corundum_dma_path_ft.df_st_cpl;
wire [3:0]  df_st_tag    = corundum_dma_path_ft.df_st_tag;
wire        df_st_empty  = corundum_dma_path_ft.df_st_empty;
wire        df_st_error  = corundum_dma_path_ft.df_st_error;
wire        df_st_valid  = corundum_dma_path_ft.df_st_valid;
wire        df_st_ok     = df_st_valid && !df_st_empty && !df_st_error;

// -- descriptor stream ------------------------------------------------------
wire [63:0] desc_tdata  = corundum_dma_path_ft.desc_tdata;
wire [7:0]  desc_tkeep  = corundum_dma_path_ft.desc_tkeep;
wire        desc_tvalid = corundum_dma_path_ft.desc_tvalid;
wire        desc_tready = corundum_dma_path_ft.desc_tready;
wire        desc_tlast  = corundum_dma_path_ft.desc_tlast;
wire [3:0]  desc_tid    = corundum_dma_path_ft.desc_tid;
wire        desc_beat   = desc_tvalid && desc_tready;

// -- desc_fetch <-> descriptor queue managers -------------------------------
wire [1:0]  dq_req_valid = corundum_dma_path_ft.dq_req_valid;
wire [1:0]  dq_req_ready = corundum_dma_path_ft.dq_req_ready;
wire [1:0]  dq_req_queue = corundum_dma_path_ft.dq_req_queue;
wire [7:0]  dq_req_tag   = corundum_dma_path_ft.dq_req_tag;

wire [1:0]  dq_resp_valid = corundum_dma_path_ft.dq_resp_valid;
wire [1:0]  dq_resp_ready = corundum_dma_path_ft.dq_resp_ready;
wire [1:0]  dq_resp_queue = corundum_dma_path_ft.dq_resp_queue;
wire [7:0]  dq_resp_tag   = corundum_dma_path_ft.dq_resp_tag;
wire [31:0] dq_resp_ptr   = corundum_dma_path_ft.dq_resp_ptr;
wire [3:0]  dq_resp_optag = corundum_dma_path_ft.dq_resp_op_tag;
wire [1:0]  dq_resp_empty = corundum_dma_path_ft.dq_resp_empty;
wire [1:0]  dq_resp_error = corundum_dma_path_ft.dq_resp_error;

wire [3:0]  dq_commit_optag = corundum_dma_path_ft.dq_commit_op_tag;
wire [1:0]  dq_commit_valid = corundum_dma_path_ft.dq_commit_valid;
wire [1:0]  dq_commit_ready = corundum_dma_path_ft.dq_commit_ready;

// -- DMA read channel (descriptor fetch) ------------------------------------
wire [63:0] rd_addr   = corundum_dma_path_ft.rd_desc_dma_addr;
wire [5:0]  rd_ram    = corundum_dma_path_ft.rd_desc_ram_addr;
wire [7:0]  rd_len    = corundum_dma_path_ft.rd_desc_len;
wire [3:0]  rd_tag    = corundum_dma_path_ft.rd_desc_tag;
wire        rd_valid  = corundum_dma_path_ft.rd_desc_valid;
wire        rd_ready  = corundum_dma_path_ft.rd_desc_ready;
wire        rd_fire   = rd_valid && rd_ready;
wire [3:0]  rd_st_tag = corundum_dma_path_ft.rd_status_tag;
wire        rd_st_val = corundum_dma_path_ft.rd_status_valid;

// -- completion write request / status --------------------------------------
wire        cw_req_sel   = corundum_dma_path_ft.cw_req_sel;
wire        cw_req_queue = corundum_dma_path_ft.cw_req_queue;
wire [3:0]  cw_req_tag   = corundum_dma_path_ft.cw_req_tag;
wire [63:0] cw_req_data  = corundum_dma_path_ft.cw_req_data;
wire        cw_req_valid = corundum_dma_path_ft.cw_req_valid;
wire        cw_req_ready = corundum_dma_path_ft.cw_req_ready;
wire        cw_req_fire  = cw_req_valid && cw_req_ready;
wire [3:0]  cw_st_tag    = corundum_dma_path_ft.cw_st_tag;
wire        cw_st_valid  = corundum_dma_path_ft.cw_st_valid;

// -- cpl_write <-> completion queue managers --------------------------------
wire [1:0]  cq_req_valid  = corundum_dma_path_ft.cq_req_valid;
wire [1:0]  cq_req_ready  = corundum_dma_path_ft.cq_req_ready;
wire [1:0]  cq_resp_valid = corundum_dma_path_ft.cq_resp_valid;
wire [1:0]  cq_resp_ready = corundum_dma_path_ft.cq_resp_ready;
wire [1:0]  cq_resp_queue = corundum_dma_path_ft.cq_resp_queue;
wire [3:0]  cq_resp_optag = corundum_dma_path_ft.cq_resp_op_tag;
wire [1:0]  cq_resp_full  = corundum_dma_path_ft.cq_resp_full;
wire [1:0]  cq_resp_error = corundum_dma_path_ft.cq_resp_error;
wire [3:0]  cq_commit_optag = corundum_dma_path_ft.cq_commit_op_tag;
wire [1:0]  cq_commit_valid = corundum_dma_path_ft.cq_commit_valid;
wire [1:0]  cq_commit_ready = corundum_dma_path_ft.cq_commit_ready;

// -- DMA write channel (completion writeback) -------------------------------
wire [63:0] wr_addr   = corundum_dma_path_ft.wr_desc_dma_addr;
wire [5:0]  wr_ram    = corundum_dma_path_ft.wr_desc_ram_addr;
wire [7:0]  wr_len    = corundum_dma_path_ft.wr_desc_len;
wire [3:0]  wr_tag    = corundum_dma_path_ft.wr_desc_tag;
wire        wr_valid  = corundum_dma_path_ft.wr_desc_valid;
wire        wr_ready  = corundum_dma_path_ft.wr_desc_ready;
wire        wr_fire   = wr_valid && wr_ready;
wire [3:0]  wr_st_tag = corundum_dma_path_ft.wr_status_tag;
wire        wr_st_val = corundum_dma_path_ft.wr_status_valid;

// -- cpl_write's DMA RAM read port, and the far observation point -----------
// `cw_rd_addr` is the completion-RAM word the host-write responder is reading;
// it is a WIRE, not a checker register, and it names the completion slot
// whose payload is on its way out of the chip.
wire [2:0]  cw_rd_addr   = corundum_dma_path_ft.cw_ram_rd_addr;
wire        cw_rd_rvalid = corundum_dma_path_ft.cw_ram_rd_resp_valid;
wire        host_valid   = corundum_dma_path_ft.host_cpl_valid;
wire [63:0] host_addr    = corundum_dma_path_ft.host_cpl_addr;
wire [63:0] host_data    = corundum_dma_path_ft.host_cpl_data;

// -- the driver -------------------------------------------------------------
wire [1:0]  dq_adv     = corundum_dma_path_ft.dq_adv_fire;
wire [1:0]  dq_adv_q   = corundum_dma_path_ft.dq_adv_fire_queue;
wire [1:0]  cq_adv     = corundum_dma_path_ft.cq_adv_fire;
wire [1:0]  cq_adv_q   = corundum_dma_path_ft.cq_adv_fire_queue;
wire        configured = corundum_dma_path_ft.all_configured;

// ================================================ the design's own state ==
//
// Everything below this line is a register the RTL already keeps.  No target
// in this file needs one the design does not have.

// -- desc_fetch's descriptor table ------------------------------------------
wire [3:0]  df_tbl_active  = corundum_dma_path_ft.u_df.desc_table_active;
wire [3:0]  df_tbl_fetched = corundum_dma_path_ft.u_df.desc_table_desc_fetched;
wire [3:0]  df_tbl_rddone  = corundum_dma_path_ft.u_df.desc_table_desc_read_done;
wire [2:0]  df_start_ptr   = corundum_dma_path_ft.u_df.desc_table_start_ptr_reg;
wire [2:0]  df_read_ptr    = corundum_dma_path_ft.u_df.desc_table_desc_read_ptr_reg;
wire [2:0]  df_fin_ptr     = corundum_dma_path_ft.u_df.desc_table_finish_ptr_reg;
wire [2:0]  df_active_cnt  = corundum_dma_path_ft.u_df.active_count_reg;

// -- cpl_write's completion table -------------------------------------------
wire [3:0]  cw_tbl_active  = corundum_dma_path_ft.u_cw.desc_table_active;
wire [3:0]  cw_tbl_invalid = corundum_dma_path_ft.u_cw.desc_table_invalid;
wire [3:0]  cw_tbl_wrdone  = corundum_dma_path_ft.u_cw.desc_table_cpl_write_done;
wire [2:0]  cw_start_ptr   = corundum_dma_path_ft.u_cw.desc_table_start_ptr_reg;
wire [2:0]  cw_fin_ptr     = corundum_dma_path_ft.u_cw.desc_table_finish_ptr_reg;

wire [3:0]  cw_tag0 = corundum_dma_path_ft.u_cw.desc_table_tag[0];
wire [3:0]  cw_tag1 = corundum_dma_path_ft.u_cw.desc_table_tag[1];
wire [3:0]  cw_tag2 = corundum_dma_path_ft.u_cw.desc_table_tag[2];
wire [3:0]  cw_tag3 = corundum_dma_path_ft.u_cw.desc_table_tag[3];

wire [63:0] cw_dat0 = corundum_dma_path_ft.u_cw.desc_table_data[0];
wire [63:0] cw_dat1 = corundum_dma_path_ft.u_cw.desc_table_data[1];
wire [63:0] cw_dat2 = corundum_dma_path_ft.u_cw.desc_table_data[2];
wire [63:0] cw_dat3 = corundum_dma_path_ft.u_cw.desc_table_data[3];

wire        cw_ph0  = corundum_dma_path_ft.u_cw.desc_table_phase[0];
wire        cw_ph1  = corundum_dma_path_ft.u_cw.desc_table_phase[1];
wire        cw_ph2  = corundum_dma_path_ft.u_cw.desc_table_phase[2];
wire        cw_ph3  = corundum_dma_path_ft.u_cw.desc_table_phase[3];

// Modular differences, taken at THEIR OWN width.  Written inline in a
// comparison against an integer these would be widened to 32 bits first and a
// legal wrap would read as a huge positive number.
wire [2:0]  df_span      = df_start_ptr - df_fin_ptr;
wire [2:0]  df_read_span = df_start_ptr - df_read_ptr;
wire [2:0]  cw_span      = cw_start_ptr - cw_fin_ptr;

// -- the four queue managers' operation tables ------------------------------
wire [3:0]  qm0_op_active  = corundum_dma_path_ft.g_dqm[0].u_qm.op_table_active;
wire [3:0]  qm1_op_active  = corundum_dma_path_ft.g_dqm[1].u_qm.op_table_active;
wire [3:0]  cqm0_op_active = corundum_dma_path_ft.g_cqm[0].u_cqm.op_table_active;
wire [3:0]  cqm1_op_active = corundum_dma_path_ft.g_cqm[1].u_cqm.op_table_active;

// -- the four descriptor rings and the four completion rings, as the design
//    keeps them.  `queue_ram` layout, from queue_manager.v:
//      [15:0] producer ptr, [31:16] consumer ptr, [55] enable,
//      [63:56] op index, [127:76] base address >> 12.
wire [127:0] qm0_q0  = corundum_dma_path_ft.g_dqm[0].u_qm.queue_ram[0];
wire [127:0] qm0_q1  = corundum_dma_path_ft.g_dqm[0].u_qm.queue_ram[1];
wire [127:0] qm1_q0  = corundum_dma_path_ft.g_dqm[1].u_qm.queue_ram[0];
wire [127:0] qm1_q1  = corundum_dma_path_ft.g_dqm[1].u_qm.queue_ram[1];
wire [127:0] cqm0_q0 = corundum_dma_path_ft.g_cqm[0].u_cqm.queue_ram[0];
wire [127:0] cqm0_q1 = corundum_dma_path_ft.g_cqm[0].u_cqm.queue_ram[1];
wire [127:0] cqm1_q0 = corundum_dma_path_ft.g_cqm[1].u_cqm.queue_ram[0];
wire [127:0] cqm1_q1 = corundum_dma_path_ft.g_cqm[1].u_cqm.queue_ram[1];

// Completion-ring occupancy, by the design's OWN pointers: the design moves
// the producer pointer when it finalises a completion, the driver moves the
// consumer pointer when software retires one.
wire [15:0] cq_occ0 = cqm0_q0[15:0] - cqm0_q0[31:16];
wire [15:0] cq_occ1 = cqm0_q1[15:0] - cqm0_q1[31:16];
wire [15:0] cq_occ2 = cqm1_q0[15:0] - cqm1_q0[31:16];
wire [15:0] cq_occ3 = cqm1_q1[15:0] - cqm1_q1[31:16];

// Descriptor-ring accounting, by the design's OWN pointers: the driver moves
// the producer pointer when software posts, and the entry the design hands
// out on a dequeue response is the `ptr` field of that response.
wire [15:0] dq0_resp_ptr = dq_resp_ptr[15:0];
wire [15:0] dq1_resp_ptr = dq_resp_ptr[31:16];
wire [15:0] qm0_prod_sel = dq_resp_queue[0] ? qm0_q1[15:0] : qm0_q0[15:0];
wire [15:0] qm1_prod_sel = dq_resp_queue[1] ? qm1_q1[15:0] : qm1_q0[15:0];
wire [15:0] dq0_lag      = qm0_prod_sel - dq0_resp_ptr;
wire [15:0] dq1_lag      = qm1_prod_sel - dq1_resp_ptr;

// ============================================== boundary events, no state ==
wire [1:0] dq_req_fire    = dq_req_valid & dq_req_ready;
wire [1:0] dq_resp_fire   = dq_resp_valid & dq_resp_ready;
wire [1:0] dq_take        = dq_resp_fire & ~dq_resp_empty & ~dq_resp_error;
wire [1:0] dq_commit_fire = dq_commit_valid & dq_commit_ready;

wire [1:0] cq_resp_fire   = cq_resp_valid & cq_resp_ready;
wire [1:0] cq_take        = cq_resp_fire & ~cq_resp_full & ~cq_resp_error;
wire [1:0] cq_commit_fire = cq_commit_valid & cq_commit_ready;

wire [1:0] wr_slot = wr_ram[4:3];   // ram_addr = slot << 3, CPL_SIZE = 8

// Work outstanding ANYWHERE in the chain, read off the design's own tables.
// Nothing here is a checker counter: every term is a register the RTL keeps.
wire any_work = (df_tbl_active != 4'd0) || (df_active_cnt != 3'd0)
             || (cw_tbl_active != 4'd0)
             || (qm0_op_active != 4'd0) || (qm1_op_active != 4'd0)
             || (cqm0_op_active != 4'd0) || (cqm1_op_active != 4'd0);

// An event on any boundary of the chain.
wire any_event = df_req_fire || df_st_valid || rd_fire || rd_st_val
              || desc_beat || cw_req_fire || cw_st_valid
              || wr_fire || wr_st_val || host_valid
              || (|dq_resp_fire) || (|cq_resp_fire)
              || (|dq_commit_fire) || (|cq_commit_fire);

// ===================================================================== ==
// Ring-address predicates.  The four descriptor rings hold 4 blocks of 16
// bytes at 0x10000/0x11000/0x20000/0x21000; the four completion rings hold 4
// entries of 8 bytes at 0x40000/0x41000/0x80000/0x81000.  Those are the
// FORMAL TOP's constants, so this is a check on the whole address path --
// base register, pointer mask, block-size shift.
// ===================================================================== ==
wire desc_page_ok = (rd_addr[63:12] == 52'h00010) || (rd_addr[63:12] == 52'h00011)
                 || (rd_addr[63:12] == 52'h00020) || (rd_addr[63:12] == 52'h00021);
wire desc_off_ok  = (rd_addr[11:6] == 6'd0) && (rd_addr[3:0] == 4'd0);

wire cpl_page_ok  = (wr_addr[63:12] == 52'h00040) || (wr_addr[63:12] == 52'h00041)
                 || (wr_addr[63:12] == 52'h00080) || (wr_addr[63:12] == 52'h00081);
wire cpl_off_ok   = (wr_addr[11:5] == 7'd0) && (wr_addr[2:0] == 3'd0);

// ===================================================================== ==
// ORACLE-DEPENDENT, and the only modelled state in this file.
//
// Four saturating event counters.  Two targets below are CONSERVATION claims
// -- "delivered never exceeds fetched", "host writes never exceed requests"
// -- and a conservation claim is a statement about two counts.  The design
// keeps neither count: its tables are windows, not totals.  There is no
// property of the design's own registers that says this, so these two keep a
// model, and they are marked at their assertion.
//
// Nothing else in this file reads these.  No shadow queue, no expected value,
// no per-tag outstanding set, no wait counter.
// ===================================================================== ==
reg [9:0] n_fetched, n_delivered, n_cplreq, n_hostwr;

always @(posedge clk) begin
    if (rst) begin
        n_fetched <= 10'd0; n_delivered <= 10'd0;
        n_cplreq  <= 10'd0; n_hostwr    <= 10'd0;
    end else begin
        if (df_st_ok    && n_fetched   != SAT) n_fetched   <= n_fetched + 10'd1;
        if (desc_beat && desc_tlast && n_delivered != SAT)
                                               n_delivered <= n_delivered + 10'd1;
        if (cw_req_fire && n_cplreq    != SAT) n_cplreq    <= n_cplreq + 10'd1;
        if (host_valid  && n_hostwr    != SAT) n_hostwr    <= n_hostwr + 10'd1;
    end
end

// ===================================================================== ==
// Properties parameterised by a tag.  A property declaration with a formal
// argument is not modelling: it holds no state, and the four instances below
// each expand to the same SVA the four-line version would.
// ===================================================================== ==

// A DMA read tag is not reissued until the status that retires it.
property p_rd_no_reuse(logic [1:0] k);
    (rd_fire && rd_tag[1:0] == k) |=>
        (!(rd_fire && rd_tag[1:0] == k))
        until_with (rd_st_val && rd_st_tag[1:0] == k);
endproperty

// A DMA write tag is not reissued until the status that retires it.
property p_wr_no_reuse(logic [1:0] k);
    (wr_fire && wr_tag[1:0] == k) |=>
        (!(wr_fire && wr_tag[1:0] == k))
        until_with (wr_st_val && wr_st_tag[1:0] == k);
endproperty

// Two statuses for the same DMA read tag with no request between them would
// be an unsolicited completion.
property p_rd_status_solicited(logic [1:0] k);
    (rd_st_val && rd_st_tag[1:0] == k) |=>
        (!(rd_st_val && rd_st_tag[1:0] == k))
        until_with (rd_fire && rd_tag[1:0] == k);
endproperty

property p_wr_status_solicited(logic [1:0] k);
    (wr_st_val && wr_st_tag[1:0] == k) |=>
        (!(wr_st_val && wr_st_tag[1:0] == k))
        until_with (wr_fire && wr_tag[1:0] == k);
endproperty

// Descriptor queue manager 0 does not hand out an operation tag again until
// the commit that retires it.
property p_dq0_op_no_reuse(logic [1:0] k);
    (dq_take[0] && dq_resp_optag[1:0] == k) |=>
        (!(dq_take[0] && dq_resp_optag[1:0] == k))
        until_with (dq_commit_fire[0] && dq_commit_optag[1:0] == k);
endproperty

// Completion queue manager 0, likewise.
property p_cq0_op_no_reuse(logic [1:0] k);
    (cq_take[0] && cq_resp_optag[1:0] == k) |=>
        (!(cq_take[0] && cq_resp_optag[1:0] == k))
        until_with (cq_commit_fire[0] && cq_commit_optag[1:0] == k);
endproperty

// ========================================================================
//                              T A R G E T S
// ========================================================================

// ---------------------------------------------- 1. end-to-end ordering ----
T_ORDER_DESC_TID_STABLE_WITHIN_DESCRIPTOR: assert property (@(posedge clk) disable iff (rst)
    (desc_beat && !desc_tlast) |=> (desc_tvalid |-> desc_tid == $past(desc_tid)));

// --------------------------------------------------- 2. data integrity ----
T_DATA_DESC_TKEEP_FULL: assert property (@(posedge clk) disable iff (rst)
    desc_tvalid |-> desc_tkeep == 8'hFF);

T_DATA_DESC_DMA_ADDR_IN_RING: assert property (@(posedge clk) disable iff (rst)
    rd_valid |-> (desc_page_ok && desc_off_ok));

T_DATA_CPL_DMA_ADDR_IN_RING: assert property (@(posedge clk) disable iff (rst)
    wr_valid |-> (cpl_page_ok && cpl_off_ok));

// RE-STATED WITHOUT THE MODEL.  The parent compared the word reaching host
// memory with a copy the checker made of what the engine handed cpl_write.
// This compares it with CPL_WRITE'S OWN completion-table entry for the slot
// the host-write responder is reading -- `desc_table_data` and
// `desc_table_phase`, both design registers -- so the RAM read port, the
// two-stage read pipeline, the phase bit that upstream splices into bit 63
// and the slot addressing are all still on the hook, and no checker register
// remembers anything.  `$past(cw_rd_addr)` names the slot because the
// responder holds its RAM address for the whole read.
T_DATA_CPL_PAYLOAD_TO_HOST: assert property (@(posedge clk) disable iff (rst)
    host_valid |-> ((($past(cw_rd_addr[1:0]) == 2'd0) && host_data == {cw_ph0, cw_dat0[62:0]})
                 || (($past(cw_rd_addr[1:0]) == 2'd1) && host_data == {cw_ph1, cw_dat1[62:0]})
                 || (($past(cw_rd_addr[1:0]) == 2'd2) && host_data == {cw_ph2, cw_dat2[62:0]})
                 || (($past(cw_rd_addr[1:0]) == 2'd3) && host_data == {cw_ph3, cw_dat3[62:0]})));

// The other half of the same claim, and cheap: what cpl_write stores in the
// slot it allocates is what the engine handed it.
T_DATA_CPL_REQUEST_LANDS_IN_SLOT: assert property (@(posedge clk) disable iff (rst)
    cw_req_fire |=> ((($past(cw_start_ptr[1:0]) == 2'd0) && cw_dat0 == $past(cw_req_data))
                  || (($past(cw_start_ptr[1:0]) == 2'd1) && cw_dat1 == $past(cw_req_data))
                  || (($past(cw_start_ptr[1:0]) == 2'd2) && cw_dat2 == $past(cw_req_data))
                  || (($past(cw_start_ptr[1:0]) == 2'd3) && cw_dat3 == $past(cw_req_data))));

// ------------------------------------------ 3. uniqueness / no duplicate --
// RE-STATED WITHOUT THE MODEL.  The parent kept a tag-keyed outstanding set
// in a checker register and asserted the tag was clear at the request.  The
// same obligation, with no register: between two issues of a tag there is the
// status that retired it.
T_UNIQ_DMA_READ_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    p_rd_no_reuse(2'd0) and p_rd_no_reuse(2'd1)
    and p_rd_no_reuse(2'd2) and p_rd_no_reuse(2'd3));

T_UNIQ_DMA_WRITE_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    p_wr_no_reuse(2'd0) and p_wr_no_reuse(2'd1)
    and p_wr_no_reuse(2'd2) and p_wr_no_reuse(2'd3));

T_UNIQ_DEQ_OP_TAG_NOT_REUSED_P0: assert property (@(posedge clk) disable iff (rst)
    p_dq0_op_no_reuse(2'd0) and p_dq0_op_no_reuse(2'd1)
    and p_dq0_op_no_reuse(2'd2) and p_dq0_op_no_reuse(2'd3));

T_UNIQ_ENQ_OP_TAG_NOT_REUSED_P0: assert property (@(posedge clk) disable iff (rst)
    p_cq0_op_no_reuse(2'd0) and p_cq0_op_no_reuse(2'd1)
    and p_cq0_op_no_reuse(2'd2) and p_cq0_op_no_reuse(2'd3));

// -------------------------------------------- 4. no loss / conservation ---
// RE-STATED WITHOUT THE MODEL.  The parent counted the driver's producer-
// pointer bumps and the design's takes in checker registers.  The design
// keeps the producer pointer itself, in `queue_ram`, and the entry it is
// handing out is the `ptr` field of the response: an entry handed out is
// always one the driver has posted, so the producer pointer LEADS it.  A
// ring that gave out more than was posted shows here as a lag of zero or as
// the near-2**16 wrap.
T_CONSERV_DEQ_NOT_MORE_THAN_POSTED: assert property (@(posedge clk) disable iff (rst)
    (dq_take[0] |-> (dq0_lag >= 16'd1 && dq0_lag <= DQ_LAG_MAX))
    and (dq_take[1] |-> (dq1_lag >= 16'd1 && dq1_lag <= DQ_LAG_MAX)));

// ORACLE-DEPENDENT: a conservation claim between two totals, and the design
// keeps neither total -- its descriptor table is a window of four, not a
// count of everything that has passed.  Two saturating counters, no more.
T_CONSERV_DESC_DELIVERED_LE_FETCHED: assert property (@(posedge clk) disable iff (rst)
    n_delivered <= n_fetched);

// ORACLE-DEPENDENT: same reason, at the far end of the chain.
T_CONSERV_CPL_HOST_WRITES_LE_REQUESTS: assert property (@(posedge clk) disable iff (rst)
    n_hostwr <= n_cplreq);

T_CONSERV_DF_ACTIVE_GE_TABLE_POP: assert property (@(posedge clk) disable iff (rst)
    df_active_cnt >= $countones(df_tbl_active));

// ----------------------------------------- 5. mutual exclusion / one-hot --
T_MUTEX_DEQ_REQ_ONEHOT: assert property (@(posedge clk) disable iff (rst)
    $onehot0(dq_req_valid));

T_MUTEX_DEQ_RESP_ACCEPT_ONEHOT: assert property (@(posedge clk) disable iff (rst)
    $onehot0(dq_resp_ready));

T_MUTEX_ENQ_REQ_ONEHOT: assert property (@(posedge clk) disable iff (rst)
    $onehot0(cq_req_valid));

// ------------------------------------------------ 6. occupancy / bounds ---
// RE-STATED WITHOUT THE MODEL.  The parent bounded requests-minus-statuses
// counted in checker registers.  desc_fetch keeps that number itself, in
// `active_count_reg`, and gates its request port on it.  The bound catches
// both directions: an overshoot, and the underflow that a decrement with
// nothing outstanding would wrap into 5, 6 or 7.
T_BOUND_DESC_OUTSTANDING_LE_TABLE: assert property (@(posedge clk) disable iff (rst)
    df_active_cnt <= DESC_TABLE_SIZE);

// RE-STATED WITHOUT THE MODEL.  The parent counted completion starts and
// driver retirements in checker registers.  The completion queue manager
// keeps both numbers itself: the producer pointer it advances at a commit and
// the consumer pointer the driver writes over AXI-Lite.
T_BOUND_CPL_RING_OCCUPANCY: assert property (@(posedge clk) disable iff (rst)
    (cq_occ0 <= RING_SIZE) && (cq_occ1 <= RING_SIZE)
    && (cq_occ2 <= RING_SIZE) && (cq_occ3 <= RING_SIZE));

T_BOUND_DF_TABLE_PTR_SPAN: assert property (@(posedge clk) disable iff (rst)
    df_span <= DESC_TABLE_SIZE);

T_BOUND_CW_TABLE_PTR_SPAN: assert property (@(posedge clk) disable iff (rst)
    cw_span <= CPL_TABLE_SIZE);

// ------------------------------------------------ 7. allocator discipline -
// RE-STATED WITHOUT THE MODEL.  The parent asked whether the commit named an
// operation the CHECKER had recorded.  This asks the queue manager's own
// operation table, which is the register that decides whether the tag is
// live: an operation is retired only after the commit that names it, so a
// commit naming a dead tag is the allocator breaking.
T_ALLOC_DEQ_COMMIT_NAMES_LIVE_OP_P0: assert property (@(posedge clk) disable iff (rst)
    dq_commit_fire[0] |-> qm0_op_active[dq_commit_optag[1:0]]);

T_ALLOC_ENQ_COMMIT_NAMES_LIVE_OP_P0: assert property (@(posedge clk) disable iff (rst)
    cq_commit_fire[0] |-> cqm0_op_active[cq_commit_optag[1:0]]);

// RE-STATED WITHOUT THE MODEL.  The parent allocated completion slots in a
// checker-side modulo-4 counter and asked whether the DMA write named a live
// one.  cpl_write's own table decides that: the slot on the DMA write
// descriptor must be allocated, not invalidated, and not already written
// back, and the DMA tag must be the same slot.
T_ALLOC_CPL_DMA_WRITE_SLOT_LIVE: assert property (@(posedge clk) disable iff (rst)
    wr_valid |-> (wr_tag[1:0] == wr_slot && cw_tbl_active[wr_slot]
                  && !cw_tbl_invalid[wr_slot] && !cw_tbl_wrdone[wr_slot]));

// -------------------------------------- 8. request-response correspondence-
T_REQRSP_DMA_READ_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    p_rd_status_solicited(2'd0) and p_rd_status_solicited(2'd1)
    and p_rd_status_solicited(2'd2) and p_rd_status_solicited(2'd3));

T_REQRSP_DMA_WRITE_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    p_wr_status_solicited(2'd0) and p_wr_status_solicited(2'd1)
    and p_wr_status_solicited(2'd2) and p_wr_status_solicited(2'd3));

// RE-STATED WITHOUT THE MODEL: desc_fetch's own outstanding count stands in
// for the checker's requests-minus-statuses.  Sampled one cycle back, because
// the status register and the decrement that retires the request are loaded
// on the same edge, so the count a status belongs to is the previous one.
T_REQRSP_DESC_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    df_st_valid |-> $past(df_active_cnt) != 3'd0);

// RE-STATED WITHOUT THE MODEL.  The parent kept a per-tag population count of
// live completion-write requests.  cpl_write keeps the caller tag of every
// live request in its own table, so a status must carry the tag of a slot
// that is allocated right now.
T_REQRSP_CPL_STATUS_TAG_LIVE: assert property (@(posedge clk) disable iff (rst)
    cw_st_valid |-> ((cw_tbl_active[0] && cw_st_tag == cw_tag0)
                  || (cw_tbl_active[1] && cw_st_tag == cw_tag1)
                  || (cw_tbl_active[2] && cw_st_tag == cw_tag2)
                  || (cw_tbl_active[3] && cw_st_tag == cw_tag3)));

// ------------------------------------------------ 9. protocol conformance -
T_PROTO_DESC_TVALID_STABLE: assert property (@(posedge clk) disable iff (rst)
    (desc_tvalid && !desc_tready) |=> desc_tvalid);

T_PROTO_DESC_PAYLOAD_STABLE: assert property (@(posedge clk) disable iff (rst)
    (desc_tvalid && !desc_tready) |=>
        $stable({desc_tdata, desc_tkeep, desc_tlast, desc_tid}));

T_PROTO_DMA_READ_DESC_STABLE: assert property (@(posedge clk) disable iff (rst)
    (rd_valid && !rd_ready) |=> (rd_valid && $stable({rd_addr, rd_ram, rd_len, rd_tag})));

T_PROTO_DMA_WRITE_DESC_STABLE: assert property (@(posedge clk) disable iff (rst)
    (wr_valid && !wr_ready) |=> (wr_valid && $stable({wr_addr, wr_ram, wr_len, wr_tag})));

T_PROTO_DEQ_RESP_P0_STABLE: assert property (@(posedge clk) disable iff (rst)
    (dq_resp_valid[0] && !dq_resp_ready[0]) |=>
        (dq_resp_valid[0] && $stable({dq_resp_tag[3:0], dq_resp_queue[0],
                                      dq_resp_optag[1:0], dq_resp_empty[0],
                                      dq_resp_error[0]})));

// ---------------------------------------------------- 10. bounded response-
// RE-STATED WITHOUT THE MODEL.  The parent aged each obligation in a
// saturating checker counter and bounded the counter.  A bounded window says
// the same thing with the same N and keeps no state.
T_BOUNDRSP_FETCH_STATUS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    df_req_fire |-> ##[1:N_FETCH] df_st_valid);

T_BOUNDRSP_DESC_DELIVERED_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    df_st_ok |-> ##[1:N_DESC] (desc_beat && desc_tlast));

T_BOUNDRSP_CPL_STATUS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    cw_req_fire |-> ##[1:N_CPL] cw_st_valid);

// ---------------------------------------------------- 11. deadlock freedom-
// RE-STATED WITHOUT THE MODEL.  `any_work` is read off the design's own
// tables and counters -- desc_fetch's table and active count, cpl_write's
// table, the four operation tables -- not off a checker's outstanding sets.
T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    any_work |-> ##[0:N_STALL] any_event);

T_DEADLOCK_DF_TABLE_DRAINS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    (df_tbl_active == 4'hF) |-> ##[1:N_FULL] (df_tbl_active != 4'hF));

// ------------------------------------------------ 12. reset/initialisation-
T_RESET_DF_TABLE_IDLE: assert property (@(posedge clk)
    (!rst && $past(rst)) |-> (df_tbl_active == 4'd0 && df_start_ptr == 3'd0
                              && df_fin_ptr == 3'd0 && df_active_cnt == 3'd0));

T_RESET_QM_OP_TABLES_IDLE: assert property (@(posedge clk)
    (!rst && $past(rst)) |-> (qm0_op_active == 4'd0 && qm1_op_active == 4'd0
                              && cqm0_op_active == 4'd0 && cqm1_op_active == 4'd0));

// ------------------------------------------ 13. lifecycle / access control-
T_LIFECYCLE_DQ0_BASE_STABLE_WHILE_ENABLED: assert property (@(posedge clk) disable iff (rst)
    (qm0_q0[55] && $past(qm0_q0[55])) |-> $stable(qm0_q0[127:76]));

T_LIFECYCLE_RINGS_STAY_ENABLED: assert property (@(posedge clk) disable iff (rst)
    configured |-> (qm0_q0[55] && qm0_q1[55] && cqm0_q0[55] && cqm0_q1[55]));

// ========================================================================
//                               C O V E R S
// ========================================================================

C_ORDER_TWO_FETCHES_IN_FLIGHT: cover property (@(posedge clk) disable iff (rst)
    df_active_cnt >= 3'd2);
C_ORDER_BOTH_MANAGERS_BUSY: cover property (@(posedge clk) disable iff (rst)
    (qm0_op_active != 4'd0) && (qm1_op_active != 4'd0));

C_DATA_DESC_DELIVERED: cover property (@(posedge clk) disable iff (rst)
    desc_beat && desc_tlast);
C_DATA_HOST_COMPLETION_WRITTEN: cover property (@(posedge clk) disable iff (rst)
    host_valid);

C_UNIQ_TWO_QM0_OPS_LIVE: cover property (@(posedge clk) disable iff (rst)
    $countones(qm0_op_active) >= 2);
C_UNIQ_TWO_CW_SLOTS_LIVE: cover property (@(posedge clk) disable iff (rst)
    $countones(cw_tbl_active) >= 2);

C_CONSERV_FOUR_DELIVERED: cover property (@(posedge clk) disable iff (rst)
    n_delivered >= 10'd4);

C_MUTEX_PORT1_DEQ_REQ: cover property (@(posedge clk) disable iff (rst)
    dq_req_valid[1]);
C_MUTEX_PORT1_ENQ_REQ: cover property (@(posedge clk) disable iff (rst)
    cq_req_valid[1]);

C_BOUND_DF_TABLE_FULL: cover property (@(posedge clk) disable iff (rst)
    df_tbl_active == 4'hF);
C_BOUND_CPL_RING_FULL: cover property (@(posedge clk) disable iff (rst)
    cq_occ0 == RING_SIZE);
C_BOUND_CPL_RING_REPORTED_FULL: cover property (@(posedge clk) disable iff (rst)
    |(cq_resp_valid & cq_resp_full));

C_ALLOC_DEQ_COMMIT: cover property (@(posedge clk) disable iff (rst)
    |dq_commit_fire);
C_ALLOC_ENQ_COMMIT: cover property (@(posedge clk) disable iff (rst)
    |cq_commit_fire);

C_REQRSP_EMPTY_RING_STATUS: cover property (@(posedge clk) disable iff (rst)
    df_st_valid && df_st_empty);
C_REQRSP_CPL_STATUS: cover property (@(posedge clk) disable iff (rst)
    cw_st_valid);

C_PROTO_DESC_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst)
    desc_tvalid && !desc_tready);
C_PROTO_DMA_READ_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst)
    rd_valid && !rd_ready);

C_DEADLOCK_WORK_OUTSTANDING_QUIET: cover property (@(posedge clk) disable iff (rst)
    any_work && !any_event);

C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
    !rst && $past(rst));

C_LIFECYCLE_CONFIGURED: cover property (@(posedge clk) disable iff (rst)
    configured);

endmodule

bind corundum_dma_path_ft corundum_dma_targets corundum_dma_targets (
    .clk(clk), .rst(rst));

`resetall
