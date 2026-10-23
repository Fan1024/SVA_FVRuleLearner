// ===========================================================================
// corundum_dma_path_ft -- formal top for Corundum's descriptor / DMA /
// completion datapath.
//
// TASK-AUTHORED.  Nothing in this file comes from upstream Corundum; the six
// upstream modules under `rtl/corundum/` are byte-identical and are only
// instantiated here.
//
// The chain, left to right:
//
//   env request generator
//        |  s_axis_req (sel, queue, tag)
//        v
//   desc_fetch  ------ dequeue req/resp/commit ----->  queue_manager x2
//        |                                             (descriptor rings)
//        |  m_axis_dma_read_desc (host addr, ram addr, len, tag)
//        v
//   env descriptor host memory  --- RAM writes --->  desc_fetch's psdpram
//        |  status
//        v
//   desc_fetch's dma_client_axis_source -- m_axis_desc (AXI-Stream) -->
//        |
//        v
//   env descriptor engine  ---- s_axis_req (queue, tag, data) --->
//        |
//        v
//   cpl_write  ------- enqueue req/resp/commit ----->  cpl_queue_manager x2
//        |                                             (completion rings)
//        |  m_axis_dma_write_desc
//        v
//   env completion host memory  --- RAM reads --->  cpl_write's data table
//        |  status
//        v
//   host completion word (the far observation point)
//
// Everything the environment chooses is a free top-level input.  Everything
// the environment REMEMBERS lives in a submodule instance named `env_*` or in
// a top-level register named `ftenv_*`; `taskdef.json:design_keep` keeps that
// state out of the reset cut and cuts the whole design.
//
// The two responders are BOUNDED: each takes at most 3 extra cycles (a free
// two-bit delay latched at accept) before it returns status, and the
// descriptor sink cannot stall for more than three consecutive cycles.  That
// is what makes the bounded-response, fairness and deadlock targets mean
// something -- an unbounded responder makes every one of them false.
// ===========================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module corundum_dma_path_ft (
    input  wire       clk,
    input  wire       rst,

    // ---- bounded descriptor-fetch request generation ----------------------
    input  wire       env_req_go,        // offer a new fetch request
    input  wire       env_req_sel,       // which descriptor queue manager
    input  wire       env_req_queue,     // which ring inside it
    input  wire [3:0] env_req_tag,       // the caller's tag, carried end to end

    // ---- descriptor consumer ---------------------------------------------
    input  wire       env_desc_bp,       // stall the descriptor stream
    input  wire       env_cpl_sel,       // which completion queue manager

    // ---- bounded host-memory responders ----------------------------------
    input  wire [1:0] env_rd_delay,      // descriptor read turnaround, 0..3
    input  wire [1:0] env_wr_delay,      // completion write turnaround, 0..3

    // ---- driver: descriptor ring producer pointers ------------------------
    input  wire       env_dq0_adv_go,
    input  wire       env_dq0_adv_queue,
    input  wire       env_dq1_adv_go,
    input  wire       env_dq1_adv_queue,

    // ---- driver: completion ring consumer pointers ------------------------
    input  wire       env_cq0_adv_go,
    input  wire       env_cq0_adv_queue,
    input  wire       env_cq1_adv_go,
    input  wire       env_cq1_adv_queue
);

// ---------------------------------------------------------------- geometry
localparam PORTS                 = 2;
localparam SELECT_WIDTH          = 1;   // $clog2(PORTS)
localparam SEG_COUNT             = 1;
localparam SEG_DATA_WIDTH        = 64;
localparam SEG_ADDR_WIDTH        = 3;
localparam SEG_BE_WIDTH          = 8;
localparam RAM_ADDR_WIDTH        = 6;   // SEG_ADDR + clog2(SEG_COUNT) + clog2(SEG_BE)
localparam RAM_PIPELINE          = 2;

localparam DMA_ADDR_WIDTH        = 64;
localparam DMA_LEN_WIDTH         = 8;
localparam DMA_TAG_WIDTH         = 4;

localparam REQ_TAG_WIDTH         = 4;
localparam QUEUE_REQ_TAG_WIDTH   = 4;
localparam QUEUE_OP_TAG_WIDTH    = 2;
localparam QUEUE_INDEX_WIDTH     = 1;
localparam CPL_QUEUE_INDEX_WIDTH = 1;
localparam QUEUE_PTR_WIDTH       = 16;
localparam LOG_QUEUE_SIZE_WIDTH  = 4;   // $clog2(QUEUE_PTR_WIDTH)
localparam LOG_BLOCK_SIZE_WIDTH  = 1;

localparam DESC_SIZE             = 8;
localparam CPL_SIZE              = 8;
localparam AXIS_DATA_WIDTH       = DESC_SIZE*8;
localparam AXIS_KEEP_WIDTH       = DESC_SIZE;

localparam DESC_TABLE_SIZE       = 4;   // desc_fetch in-flight fetches
localparam CPL_TABLE_SIZE        = 4;   // cpl_write in-flight completions
localparam OP_TABLE_SIZE         = 4;   // queue-manager in-flight operations

localparam PIPELINE              = 2;
localparam AXIL_DATA_WIDTH       = 32;
localparam AXIL_STRB_WIDTH       = 4;
localparam QM_AXIL_ADDR_WIDTH    = QUEUE_INDEX_WIDTH + 5;
localparam CQM_AXIL_ADDR_WIDTH   = CPL_QUEUE_INDEX_WIDTH + 4;
localparam EVENT_WIDTH           = 16;

localparam NQ                    = 2;   // rings per manager (2**QUEUE_INDEX_WIDTH)
localparam LOG_RING_SIZE         = 2;   // rings hold 4 entries
localparam RING_SIZE             = 4;
localparam LOG_DESC_BLOCK        = 1;   // descriptors come in blocks of 2

// ================================================================= wires ==

// ---- desc_fetch external request -----------------------------------------
wire [SELECT_WIDTH-1:0]        df_req_sel;
wire [QUEUE_INDEX_WIDTH-1:0]   df_req_queue;
wire [REQ_TAG_WIDTH-1:0]       df_req_tag;
wire                           df_req_valid;
wire                           df_req_ready;

// ---- desc_fetch request status -------------------------------------------
wire [QUEUE_INDEX_WIDTH-1:0]     df_st_queue;
wire [QUEUE_PTR_WIDTH-1:0]       df_st_ptr;
wire [CPL_QUEUE_INDEX_WIDTH-1:0] df_st_cpl;
wire [REQ_TAG_WIDTH-1:0]         df_st_tag;
wire                             df_st_empty;
wire                             df_st_error;
wire                             df_st_valid;

// ---- descriptor stream ----------------------------------------------------
wire [AXIS_DATA_WIDTH-1:0]     desc_tdata;
wire [AXIS_KEEP_WIDTH-1:0]     desc_tkeep;
wire                           desc_tvalid;
wire                           desc_tready;
wire                           desc_tlast;
wire [REQ_TAG_WIDTH-1:0]       desc_tid;
wire                           desc_tuser;

// ---- desc_fetch <-> descriptor queue managers -----------------------------
wire [PORTS*QUEUE_INDEX_WIDTH-1:0]     dq_req_queue;
wire [PORTS*QUEUE_REQ_TAG_WIDTH-1:0]   dq_req_tag;
wire [PORTS-1:0]                       dq_req_valid;
wire [PORTS-1:0]                       dq_req_ready;

wire [PORTS*QUEUE_INDEX_WIDTH-1:0]      dq_resp_queue;
wire [PORTS*QUEUE_PTR_WIDTH-1:0]        dq_resp_ptr;
wire [PORTS*DMA_ADDR_WIDTH-1:0]         dq_resp_addr;
wire [PORTS*LOG_BLOCK_SIZE_WIDTH-1:0]   dq_resp_block_size;
wire [PORTS*CPL_QUEUE_INDEX_WIDTH-1:0]  dq_resp_cpl;
wire [PORTS*QUEUE_REQ_TAG_WIDTH-1:0]    dq_resp_tag;
wire [PORTS*QUEUE_OP_TAG_WIDTH-1:0]     dq_resp_op_tag;
wire [PORTS-1:0]                        dq_resp_empty;
wire [PORTS-1:0]                        dq_resp_error;
wire [PORTS-1:0]                        dq_resp_valid;
wire [PORTS-1:0]                        dq_resp_ready;

wire [PORTS*QUEUE_OP_TAG_WIDTH-1:0]     dq_commit_op_tag;
wire [PORTS-1:0]                        dq_commit_valid;
wire [PORTS-1:0]                        dq_commit_ready;

wire [PORTS-1:0]                        dq_resp_phase;

// ---- desc_fetch <-> descriptor host memory --------------------------------
wire [DMA_ADDR_WIDTH-1:0]      rd_desc_dma_addr;
wire [RAM_ADDR_WIDTH-1:0]      rd_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]       rd_desc_len;
wire [DMA_TAG_WIDTH-1:0]       rd_desc_tag;
wire                           rd_desc_valid;
wire                           rd_desc_ready;
wire [DMA_TAG_WIDTH-1:0]       rd_status_tag;
wire [3:0]                     rd_status_error;
wire                           rd_status_valid;

wire [SEG_COUNT*SEG_BE_WIDTH-1:0]   df_ram_wr_be;
wire [SEG_COUNT*SEG_ADDR_WIDTH-1:0] df_ram_wr_addr;
wire [SEG_COUNT*SEG_DATA_WIDTH-1:0] df_ram_wr_data;
wire [SEG_COUNT-1:0]                df_ram_wr_valid;
wire [SEG_COUNT-1:0]                df_ram_wr_ready;
wire [SEG_COUNT-1:0]                df_ram_wr_done;

// ---- cpl_write external request -------------------------------------------
wire [SELECT_WIDTH-1:0]          cw_req_sel;
wire [CPL_QUEUE_INDEX_WIDTH-1:0] cw_req_queue;
wire [REQ_TAG_WIDTH-1:0]         cw_req_tag;
wire [CPL_SIZE*8-1:0]            cw_req_data;
wire                             cw_req_valid;
wire                             cw_req_ready;

wire [REQ_TAG_WIDTH-1:0]         cw_st_tag;
wire                             cw_st_full;
wire                             cw_st_error;
wire                             cw_st_valid;

// ---- cpl_write <-> completion queue managers ------------------------------
wire [PORTS*CPL_QUEUE_INDEX_WIDTH-1:0] cq_req_queue;
wire [PORTS*QUEUE_REQ_TAG_WIDTH-1:0]   cq_req_tag;
wire [PORTS-1:0]                       cq_req_valid;
wire [PORTS-1:0]                       cq_req_ready;

wire [PORTS-1:0]                        cq_resp_phase;
wire [PORTS*DMA_ADDR_WIDTH-1:0]         cq_resp_addr;
wire [PORTS*QUEUE_REQ_TAG_WIDTH-1:0]    cq_resp_tag;
wire [PORTS*QUEUE_OP_TAG_WIDTH-1:0]     cq_resp_op_tag;
wire [PORTS-1:0]                        cq_resp_full;
wire [PORTS-1:0]                        cq_resp_error;
wire [PORTS-1:0]                        cq_resp_valid;
wire [PORTS-1:0]                        cq_resp_ready;
wire [PORTS*CPL_QUEUE_INDEX_WIDTH-1:0]  cq_resp_queue;
wire [PORTS*QUEUE_PTR_WIDTH-1:0]        cq_resp_ptr;

wire [PORTS*QUEUE_OP_TAG_WIDTH-1:0]     cq_commit_op_tag;
wire [PORTS-1:0]                        cq_commit_valid;
wire [PORTS-1:0]                        cq_commit_ready;

// ---- cpl_write <-> completion host memory ---------------------------------
wire [DMA_ADDR_WIDTH-1:0]      wr_desc_dma_addr;
wire [RAM_ADDR_WIDTH-1:0]      wr_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]       wr_desc_len;
wire [DMA_TAG_WIDTH-1:0]       wr_desc_tag;
wire                           wr_desc_valid;
wire                           wr_desc_ready;
wire [DMA_TAG_WIDTH-1:0]       wr_status_tag;
wire [3:0]                     wr_status_error;
wire                           wr_status_valid;

wire [SEG_COUNT*SEG_ADDR_WIDTH-1:0] cw_ram_rd_addr;
wire [SEG_COUNT-1:0]                cw_ram_rd_valid;
wire [SEG_COUNT-1:0]                cw_ram_rd_ready;
wire [SEG_COUNT*SEG_DATA_WIDTH-1:0] cw_ram_rd_data;
wire [SEG_COUNT-1:0]                cw_ram_rd_resp_valid;
wire [SEG_COUNT-1:0]                cw_ram_rd_resp_ready;

// ---- the far observation point: the completion word reaching host memory ---
wire                           host_cpl_valid;
wire [DMA_ADDR_WIDTH-1:0]      host_cpl_addr;
wire [SEG_DATA_WIDTH-1:0]      host_cpl_data;

// ---- AXI-Lite to the four queue managers ----------------------------------
wire [PORTS*QM_AXIL_ADDR_WIDTH-1:0]  dqa_awaddr;
wire [PORTS*3-1:0]                   dqa_awprot;
wire [PORTS-1:0]                     dqa_awvalid;
wire [PORTS-1:0]                     dqa_awready;
wire [PORTS*AXIL_DATA_WIDTH-1:0]     dqa_wdata;
wire [PORTS*AXIL_STRB_WIDTH-1:0]     dqa_wstrb;
wire [PORTS-1:0]                     dqa_wvalid;
wire [PORTS-1:0]                     dqa_wready;
wire [PORTS*2-1:0]                   dqa_bresp;
wire [PORTS-1:0]                     dqa_bvalid;
wire [PORTS-1:0]                     dqa_bready;

wire [PORTS*CQM_AXIL_ADDR_WIDTH-1:0] cqa_awaddr;
wire [PORTS*3-1:0]                   cqa_awprot;
wire [PORTS-1:0]                     cqa_awvalid;
wire [PORTS-1:0]                     cqa_awready;
wire [PORTS*AXIL_DATA_WIDTH-1:0]     cqa_wdata;
wire [PORTS*AXIL_STRB_WIDTH-1:0]     cqa_wstrb;
wire [PORTS-1:0]                     cqa_wvalid;
wire [PORTS-1:0]                     cqa_wready;
wire [PORTS*2-1:0]                   cqa_bresp;
wire [PORTS-1:0]                     cqa_bvalid;
wire [PORTS-1:0]                     cqa_bready;

wire [1:0]                     dq_init_done;
wire [1:0]                     cq_init_done;
wire [1:0]                     dq_adv_fire;
wire [1:0]                     dq_adv_fire_queue;
wire [1:0]                     cq_adv_fire;
wire [1:0]                     cq_adv_fire_queue;
wire [NQ-1:0]                  dq0_adv_allowed, dq1_adv_allowed;
wire [NQ-1:0]                  cq0_adv_allowed, cq1_adv_allowed;

wire all_configured = &dq_init_done & &cq_init_done;

// ============================================== bounded request generation ==
// One request offered at a time, payload held stable until it is accepted, and
// nothing offered before all four rings are configured.
reg                          ftenv_req_valid_reg;
reg [SELECT_WIDTH-1:0]       ftenv_req_sel_reg;
reg [QUEUE_INDEX_WIDTH-1:0]  ftenv_req_queue_reg;
reg [REQ_TAG_WIDTH-1:0]      ftenv_req_tag_reg;

always @(posedge clk) begin
    if (rst) begin
        ftenv_req_valid_reg <= 1'b0;
        ftenv_req_sel_reg   <= {SELECT_WIDTH{1'b0}};
        ftenv_req_queue_reg <= {QUEUE_INDEX_WIDTH{1'b0}};
        ftenv_req_tag_reg   <= {REQ_TAG_WIDTH{1'b0}};
    end else if (ftenv_req_valid_reg) begin
        if (df_req_ready) ftenv_req_valid_reg <= 1'b0;
    end else if (env_req_go && all_configured) begin
        ftenv_req_valid_reg <= 1'b1;
        ftenv_req_sel_reg   <= env_req_sel;
        ftenv_req_queue_reg <= env_req_queue;
        ftenv_req_tag_reg   <= env_req_tag;
    end
end

assign df_req_sel   = ftenv_req_sel_reg;
assign df_req_queue = ftenv_req_queue_reg;
assign df_req_tag   = ftenv_req_tag_reg;
assign df_req_valid = ftenv_req_valid_reg;

// ======================================================== ring accounting ==
// What the environment has produced into each descriptor ring and consumed out
// of each completion ring.  These are the numbers that keep the driver honest;
// they are kept out of the reset cut, because an arbitrary start would let the
// environment over-fill or over-drain a ring and falsify an occupancy target
// for a reason no design-side helper could repair.
reg [7:0] ftenv_dq_prod [0:PORTS*NQ-1];   // producer-pointer bumps issued
reg [7:0] ftenv_dq_used [0:PORTS*NQ-1];   // dequeue responses that took an entry
reg [7:0] ftenv_cq_made [0:PORTS*NQ-1];   // enqueue commits observed
reg [7:0] ftenv_cq_eaten[0:PORTS*NQ-1];   // consumer-pointer bumps issued

// op tag -> ring, so a completion commit can be attributed to the right ring
reg [CPL_QUEUE_INDEX_WIDTH-1:0] ftenv_cq_opq [0:PORTS*OP_TABLE_SIZE-1];

integer gi;
initial begin
    for (gi = 0; gi < PORTS*NQ; gi = gi + 1) begin
        ftenv_dq_prod[gi]  = 8'd0;
        ftenv_dq_used[gi]  = 8'd0;
        ftenv_cq_made[gi]  = 8'd0;
        ftenv_cq_eaten[gi] = 8'd0;
    end
    for (gi = 0; gi < PORTS*OP_TABLE_SIZE; gi = gi + 1)
        ftenv_cq_opq[gi] = {CPL_QUEUE_INDEX_WIDTH{1'b0}};
end

wire [PORTS-1:0] dq_take;   // this port took a descriptor out of its ring
wire [PORTS-1:0] cq_made;   // this port finalised a completion into its ring

genvar p;
generate
    for (p = 0; p < PORTS; p = p + 1) begin : g_port
        assign dq_take[p] = dq_resp_valid[p] && dq_resp_ready[p]
                            && !dq_resp_empty[p] && !dq_resp_error[p];
        assign cq_made[p] = cq_commit_valid[p] && cq_commit_ready[p];
    end
endgenerate

wire [PORTS-1:0] cq_started;
generate
    for (p = 0; p < PORTS; p = p + 1) begin : g_cqstart
        assign cq_started[p] = cq_resp_valid[p] && cq_resp_ready[p]
                               && !cq_resp_full[p] && !cq_resp_error[p];
    end
endgenerate

integer pi;
always @(posedge clk) begin
    if (rst) begin
        for (pi = 0; pi < PORTS*NQ; pi = pi + 1) begin
            ftenv_dq_prod[pi]  <= 8'd0;
            ftenv_dq_used[pi]  <= 8'd0;
            ftenv_cq_made[pi]  <= 8'd0;
            ftenv_cq_eaten[pi] <= 8'd0;
        end
    end else begin
        // descriptor rings: the driver's producer-pointer bumps
        if (dq_adv_fire[0])
            ftenv_dq_prod[0*NQ + dq_adv_fire_queue[0]] <=
                ftenv_dq_prod[0*NQ + dq_adv_fire_queue[0]] + 8'd1;
        if (dq_adv_fire[1])
            ftenv_dq_prod[1*NQ + dq_adv_fire_queue[1]] <=
                ftenv_dq_prod[1*NQ + dq_adv_fire_queue[1]] + 8'd1;
        if (dq_take[0])
            ftenv_dq_used[0*NQ + dq_resp_queue[0*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]] <=
                ftenv_dq_used[0*NQ + dq_resp_queue[0*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]] + 8'd1;
        if (dq_take[1])
            ftenv_dq_used[1*NQ + dq_resp_queue[1*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]] <=
                ftenv_dq_used[1*NQ + dq_resp_queue[1*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]] + 8'd1;

        // completion rings: commits in, driver's consumer-pointer bumps out
        if (cq_made[0])
            ftenv_cq_made[0*NQ + ftenv_cq_opq[0*OP_TABLE_SIZE +
                                 cq_commit_op_tag[0*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]]] <=
                ftenv_cq_made[0*NQ + ftenv_cq_opq[0*OP_TABLE_SIZE +
                                 cq_commit_op_tag[0*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]]] + 8'd1;
        if (cq_made[1])
            ftenv_cq_made[1*NQ + ftenv_cq_opq[1*OP_TABLE_SIZE +
                                 cq_commit_op_tag[1*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]]] <=
                ftenv_cq_made[1*NQ + ftenv_cq_opq[1*OP_TABLE_SIZE +
                                 cq_commit_op_tag[1*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]]] + 8'd1;
        if (cq_adv_fire[0])
            ftenv_cq_eaten[0*NQ + cq_adv_fire_queue[0]] <=
                ftenv_cq_eaten[0*NQ + cq_adv_fire_queue[0]] + 8'd1;
        if (cq_adv_fire[1])
            ftenv_cq_eaten[1*NQ + cq_adv_fire_queue[1]] <=
                ftenv_cq_eaten[1*NQ + cq_adv_fire_queue[1]] + 8'd1;
    end
end

integer oi;
always @(posedge clk) begin
    if (rst) begin
        for (oi = 0; oi < PORTS*OP_TABLE_SIZE; oi = oi + 1)
            ftenv_cq_opq[oi] <= {CPL_QUEUE_INDEX_WIDTH{1'b0}};
    end
    if (cq_started[0])
        ftenv_cq_opq[0*OP_TABLE_SIZE +
                     cq_resp_op_tag[0*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]] <=
            cq_resp_queue[0*CPL_QUEUE_INDEX_WIDTH +: CPL_QUEUE_INDEX_WIDTH];
    if (cq_started[1])
        ftenv_cq_opq[1*OP_TABLE_SIZE +
                     cq_resp_op_tag[1*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]] <=
            cq_resp_queue[1*CPL_QUEUE_INDEX_WIDTH +: CPL_QUEUE_INDEX_WIDTH];
end

// A descriptor ring may be filled up to RING_SIZE outstanding entries; a
// completion ring may be drained only as far as it has been filled.
assign dq0_adv_allowed[0] = (ftenv_dq_prod[0] - ftenv_dq_used[0]) < RING_SIZE;
assign dq0_adv_allowed[1] = (ftenv_dq_prod[1] - ftenv_dq_used[1]) < RING_SIZE;
assign dq1_adv_allowed[0] = (ftenv_dq_prod[2] - ftenv_dq_used[2]) < RING_SIZE;
assign dq1_adv_allowed[1] = (ftenv_dq_prod[3] - ftenv_dq_used[3]) < RING_SIZE;

assign cq0_adv_allowed[0] = ftenv_cq_eaten[0] != ftenv_cq_made[0];
assign cq0_adv_allowed[1] = ftenv_cq_eaten[1] != ftenv_cq_made[1];
assign cq1_adv_allowed[0] = ftenv_cq_eaten[2] != ftenv_cq_made[2];
assign cq1_adv_allowed[1] = ftenv_cq_eaten[3] != ftenv_cq_made[3];

// ================================================================ the DUT ==

desc_fetch #(
    .PORTS(PORTS),
    .SELECT_WIDTH(SELECT_WIDTH),
    .SEG_COUNT(SEG_COUNT),
    .SEG_DATA_WIDTH(SEG_DATA_WIDTH),
    .SEG_ADDR_WIDTH(SEG_ADDR_WIDTH),
    .SEG_BE_WIDTH(SEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .REQ_TAG_WIDTH(REQ_TAG_WIDTH),
    .QUEUE_REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .QUEUE_OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CPL_QUEUE_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .DESC_TABLE_SIZE(DESC_TABLE_SIZE),
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH)
)
u_df (
    .clk(clk),
    .rst(rst),

    .s_axis_req_sel(df_req_sel),
    .s_axis_req_queue(df_req_queue),
    .s_axis_req_tag(df_req_tag),
    .s_axis_req_valid(df_req_valid),
    .s_axis_req_ready(df_req_ready),

    .m_axis_req_status_queue(df_st_queue),
    .m_axis_req_status_ptr(df_st_ptr),
    .m_axis_req_status_cpl(df_st_cpl),
    .m_axis_req_status_tag(df_st_tag),
    .m_axis_req_status_empty(df_st_empty),
    .m_axis_req_status_error(df_st_error),
    .m_axis_req_status_valid(df_st_valid),

    .m_axis_desc_tdata(desc_tdata),
    .m_axis_desc_tkeep(desc_tkeep),
    .m_axis_desc_tvalid(desc_tvalid),
    .m_axis_desc_tready(desc_tready),
    .m_axis_desc_tlast(desc_tlast),
    .m_axis_desc_tid(desc_tid),
    .m_axis_desc_tuser(desc_tuser),

    .m_axis_desc_dequeue_req_queue(dq_req_queue),
    .m_axis_desc_dequeue_req_tag(dq_req_tag),
    .m_axis_desc_dequeue_req_valid(dq_req_valid),
    .m_axis_desc_dequeue_req_ready(dq_req_ready),

    .s_axis_desc_dequeue_resp_queue(dq_resp_queue),
    .s_axis_desc_dequeue_resp_ptr(dq_resp_ptr),
    .s_axis_desc_dequeue_resp_addr(dq_resp_addr),
    .s_axis_desc_dequeue_resp_block_size(dq_resp_block_size),
    .s_axis_desc_dequeue_resp_cpl(dq_resp_cpl),
    .s_axis_desc_dequeue_resp_tag(dq_resp_tag),
    .s_axis_desc_dequeue_resp_op_tag(dq_resp_op_tag),
    .s_axis_desc_dequeue_resp_empty(dq_resp_empty),
    .s_axis_desc_dequeue_resp_error(dq_resp_error),
    .s_axis_desc_dequeue_resp_valid(dq_resp_valid),
    .s_axis_desc_dequeue_resp_ready(dq_resp_ready),

    .m_axis_desc_dequeue_commit_op_tag(dq_commit_op_tag),
    .m_axis_desc_dequeue_commit_valid(dq_commit_valid),
    .m_axis_desc_dequeue_commit_ready(dq_commit_ready),

    .m_axis_dma_read_desc_dma_addr(rd_desc_dma_addr),
    .m_axis_dma_read_desc_ram_addr(rd_desc_ram_addr),
    .m_axis_dma_read_desc_len(rd_desc_len),
    .m_axis_dma_read_desc_tag(rd_desc_tag),
    .m_axis_dma_read_desc_valid(rd_desc_valid),
    .m_axis_dma_read_desc_ready(rd_desc_ready),

    .s_axis_dma_read_desc_status_tag(rd_status_tag),
    .s_axis_dma_read_desc_status_error(rd_status_error),
    .s_axis_dma_read_desc_status_valid(rd_status_valid),

    .dma_ram_wr_cmd_be(df_ram_wr_be),
    .dma_ram_wr_cmd_addr(df_ram_wr_addr),
    .dma_ram_wr_cmd_data(df_ram_wr_data),
    .dma_ram_wr_cmd_valid(df_ram_wr_valid),
    .dma_ram_wr_cmd_ready(df_ram_wr_ready),
    .dma_ram_wr_done(df_ram_wr_done),

    .enable(all_configured)
);

generate
    for (p = 0; p < PORTS; p = p + 1) begin : g_dqm
        queue_manager #(
            .ADDR_WIDTH(DMA_ADDR_WIDTH),
            .REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
            .OP_TABLE_SIZE(OP_TABLE_SIZE),
            .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
            .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
            .CPL_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
            .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
            .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
            .DESC_SIZE(DESC_SIZE),
            .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
            .PIPELINE(PIPELINE),
            .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
            .AXIL_ADDR_WIDTH(QM_AXIL_ADDR_WIDTH),
            .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH)
        )
        u_qm (
            .clk(clk),
            .rst(rst),

            .s_axis_dequeue_req_queue(dq_req_queue[p*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]),
            .s_axis_dequeue_req_tag(dq_req_tag[p*QUEUE_REQ_TAG_WIDTH +: QUEUE_REQ_TAG_WIDTH]),
            .s_axis_dequeue_req_valid(dq_req_valid[p]),
            .s_axis_dequeue_req_ready(dq_req_ready[p]),

            .m_axis_dequeue_resp_queue(dq_resp_queue[p*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]),
            .m_axis_dequeue_resp_ptr(dq_resp_ptr[p*QUEUE_PTR_WIDTH +: QUEUE_PTR_WIDTH]),
            .m_axis_dequeue_resp_phase(dq_resp_phase[p]),
            .m_axis_dequeue_resp_addr(dq_resp_addr[p*DMA_ADDR_WIDTH +: DMA_ADDR_WIDTH]),
            .m_axis_dequeue_resp_block_size(dq_resp_block_size[p*LOG_BLOCK_SIZE_WIDTH +: LOG_BLOCK_SIZE_WIDTH]),
            .m_axis_dequeue_resp_cpl(dq_resp_cpl[p*CPL_QUEUE_INDEX_WIDTH +: CPL_QUEUE_INDEX_WIDTH]),
            .m_axis_dequeue_resp_tag(dq_resp_tag[p*QUEUE_REQ_TAG_WIDTH +: QUEUE_REQ_TAG_WIDTH]),
            .m_axis_dequeue_resp_op_tag(dq_resp_op_tag[p*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
            .m_axis_dequeue_resp_empty(dq_resp_empty[p]),
            .m_axis_dequeue_resp_error(dq_resp_error[p]),
            .m_axis_dequeue_resp_valid(dq_resp_valid[p]),
            .m_axis_dequeue_resp_ready(dq_resp_ready[p]),

            .s_axis_dequeue_commit_op_tag(dq_commit_op_tag[p*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
            .s_axis_dequeue_commit_valid(dq_commit_valid[p]),
            .s_axis_dequeue_commit_ready(dq_commit_ready[p]),

            .m_axis_doorbell_queue(),
            .m_axis_doorbell_valid(),

            .s_axil_awaddr(dqa_awaddr[p*QM_AXIL_ADDR_WIDTH +: QM_AXIL_ADDR_WIDTH]),
            .s_axil_awprot(dqa_awprot[p*3 +: 3]),
            .s_axil_awvalid(dqa_awvalid[p]),
            .s_axil_awready(dqa_awready[p]),
            .s_axil_wdata(dqa_wdata[p*AXIL_DATA_WIDTH +: AXIL_DATA_WIDTH]),
            .s_axil_wstrb(dqa_wstrb[p*AXIL_STRB_WIDTH +: AXIL_STRB_WIDTH]),
            .s_axil_wvalid(dqa_wvalid[p]),
            .s_axil_wready(dqa_wready[p]),
            .s_axil_bresp(dqa_bresp[p*2 +: 2]),
            .s_axil_bvalid(dqa_bvalid[p]),
            .s_axil_bready(dqa_bready[p]),
            .s_axil_araddr({QM_AXIL_ADDR_WIDTH{1'b0}}),
            .s_axil_arprot(3'd0),
            .s_axil_arvalid(1'b0),
            .s_axil_arready(),
            .s_axil_rdata(),
            .s_axil_rresp(),
            .s_axil_rvalid(),
            .s_axil_rready(1'b1),

            .enable(1'b1)
        );
    end
endgenerate

cpl_write #(
    .PORTS(PORTS),
    .SELECT_WIDTH(SELECT_WIDTH),
    .SEG_COUNT(SEG_COUNT),
    .SEG_DATA_WIDTH(SEG_DATA_WIDTH),
    .SEG_ADDR_WIDTH(SEG_ADDR_WIDTH),
    .SEG_BE_WIDTH(SEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .REQ_TAG_WIDTH(REQ_TAG_WIDTH),
    .QUEUE_REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .QUEUE_OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
    .CPL_SIZE(CPL_SIZE),
    .DESC_TABLE_SIZE(CPL_TABLE_SIZE)
)
u_cw (
    .clk(clk),
    .rst(rst),

    .s_axis_req_sel(cw_req_sel),
    .s_axis_req_queue(cw_req_queue),
    .s_axis_req_tag(cw_req_tag),
    .s_axis_req_data(cw_req_data),
    .s_axis_req_valid(cw_req_valid),
    .s_axis_req_ready(cw_req_ready),

    .m_axis_req_status_tag(cw_st_tag),
    .m_axis_req_status_full(cw_st_full),
    .m_axis_req_status_error(cw_st_error),
    .m_axis_req_status_valid(cw_st_valid),

    .m_axis_cpl_enqueue_req_queue(cq_req_queue),
    .m_axis_cpl_enqueue_req_tag(cq_req_tag),
    .m_axis_cpl_enqueue_req_valid(cq_req_valid),
    .m_axis_cpl_enqueue_req_ready(cq_req_ready),

    .s_axis_cpl_enqueue_resp_phase(cq_resp_phase),
    .s_axis_cpl_enqueue_resp_addr(cq_resp_addr),
    .s_axis_cpl_enqueue_resp_tag(cq_resp_tag),
    .s_axis_cpl_enqueue_resp_op_tag(cq_resp_op_tag),
    .s_axis_cpl_enqueue_resp_full(cq_resp_full),
    .s_axis_cpl_enqueue_resp_error(cq_resp_error),
    .s_axis_cpl_enqueue_resp_valid(cq_resp_valid),
    .s_axis_cpl_enqueue_resp_ready(cq_resp_ready),

    .m_axis_cpl_enqueue_commit_op_tag(cq_commit_op_tag),
    .m_axis_cpl_enqueue_commit_valid(cq_commit_valid),
    .m_axis_cpl_enqueue_commit_ready(cq_commit_ready),

    .m_axis_dma_write_desc_dma_addr(wr_desc_dma_addr),
    .m_axis_dma_write_desc_ram_addr(wr_desc_ram_addr),
    .m_axis_dma_write_desc_len(wr_desc_len),
    .m_axis_dma_write_desc_tag(wr_desc_tag),
    .m_axis_dma_write_desc_valid(wr_desc_valid),
    .m_axis_dma_write_desc_ready(wr_desc_ready),

    .s_axis_dma_write_desc_status_tag(wr_status_tag),
    .s_axis_dma_write_desc_status_error(wr_status_error),
    .s_axis_dma_write_desc_status_valid(wr_status_valid),

    .dma_ram_rd_cmd_addr(cw_ram_rd_addr),
    .dma_ram_rd_cmd_valid(cw_ram_rd_valid),
    .dma_ram_rd_cmd_ready(cw_ram_rd_ready),
    .dma_ram_rd_resp_data(cw_ram_rd_data),
    .dma_ram_rd_resp_valid(cw_ram_rd_resp_valid),
    .dma_ram_rd_resp_ready(cw_ram_rd_resp_ready),

    .enable(all_configured)
);

generate
    for (p = 0; p < PORTS; p = p + 1) begin : g_cqm
        cpl_queue_manager #(
            .ADDR_WIDTH(DMA_ADDR_WIDTH),
            .REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
            .OP_TABLE_SIZE(OP_TABLE_SIZE),
            .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
            .QUEUE_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
            .EVENT_WIDTH(EVENT_WIDTH),
            .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
            .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
            .CPL_SIZE(CPL_SIZE),
            .PIPELINE(PIPELINE),
            .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
            .AXIL_ADDR_WIDTH(CQM_AXIL_ADDR_WIDTH),
            .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH)
        )
        u_cqm (
            .clk(clk),
            .rst(rst),

            .s_axis_enqueue_req_queue(cq_req_queue[p*CPL_QUEUE_INDEX_WIDTH +: CPL_QUEUE_INDEX_WIDTH]),
            .s_axis_enqueue_req_tag(cq_req_tag[p*QUEUE_REQ_TAG_WIDTH +: QUEUE_REQ_TAG_WIDTH]),
            .s_axis_enqueue_req_valid(cq_req_valid[p]),
            .s_axis_enqueue_req_ready(cq_req_ready[p]),

            .m_axis_enqueue_resp_queue(cq_resp_queue[p*CPL_QUEUE_INDEX_WIDTH +: CPL_QUEUE_INDEX_WIDTH]),
            .m_axis_enqueue_resp_ptr(cq_resp_ptr[p*QUEUE_PTR_WIDTH +: QUEUE_PTR_WIDTH]),
            .m_axis_enqueue_resp_phase(cq_resp_phase[p]),
            .m_axis_enqueue_resp_addr(cq_resp_addr[p*DMA_ADDR_WIDTH +: DMA_ADDR_WIDTH]),
            .m_axis_enqueue_resp_event(),
            .m_axis_enqueue_resp_tag(cq_resp_tag[p*QUEUE_REQ_TAG_WIDTH +: QUEUE_REQ_TAG_WIDTH]),
            .m_axis_enqueue_resp_op_tag(cq_resp_op_tag[p*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
            .m_axis_enqueue_resp_full(cq_resp_full[p]),
            .m_axis_enqueue_resp_error(cq_resp_error[p]),
            .m_axis_enqueue_resp_valid(cq_resp_valid[p]),
            .m_axis_enqueue_resp_ready(cq_resp_ready[p]),

            .s_axis_enqueue_commit_op_tag(cq_commit_op_tag[p*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
            .s_axis_enqueue_commit_valid(cq_commit_valid[p]),
            .s_axis_enqueue_commit_ready(cq_commit_ready[p]),

            .m_axis_event(),
            .m_axis_event_source(),
            .m_axis_event_valid(),
            .m_axis_event_ready(1'b1),

            .s_axil_awaddr(cqa_awaddr[p*CQM_AXIL_ADDR_WIDTH +: CQM_AXIL_ADDR_WIDTH]),
            .s_axil_awprot(cqa_awprot[p*3 +: 3]),
            .s_axil_awvalid(cqa_awvalid[p]),
            .s_axil_awready(cqa_awready[p]),
            .s_axil_wdata(cqa_wdata[p*AXIL_DATA_WIDTH +: AXIL_DATA_WIDTH]),
            .s_axil_wstrb(cqa_wstrb[p*AXIL_STRB_WIDTH +: AXIL_STRB_WIDTH]),
            .s_axil_wvalid(cqa_wvalid[p]),
            .s_axil_wready(cqa_wready[p]),
            .s_axil_bresp(cqa_bresp[p*2 +: 2]),
            .s_axil_bvalid(cqa_bvalid[p]),
            .s_axil_bready(cqa_bready[p]),
            .s_axil_araddr({CQM_AXIL_ADDR_WIDTH{1'b0}}),
            .s_axil_arprot(3'd0),
            .s_axil_arvalid(1'b0),
            .s_axil_arready(),
            .s_axil_rdata(),
            .s_axil_rresp(),
            .s_axil_rvalid(),
            .s_axil_rready(1'b1),

            .enable(1'b1)
        );
    end
endgenerate

// ======================================================== the environment ==

corundum_axil_qcfg #(
    .CPL(0), .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .AXIL_ADDR_WIDTH(QM_AXIL_ADDR_WIDTH),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE), .LOG_BLOCK_SIZE(LOG_DESC_BLOCK),
    .BASE_HI20(20'h00010), .BASE_UPPER(32'h0000_0000), .LINK_INDEX(24'd0)
)
env_cfg_dq0 (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(dqa_awaddr[0*QM_AXIL_ADDR_WIDTH +: QM_AXIL_ADDR_WIDTH]), .m_axil_awprot(dqa_awprot[0*3 +: 3]),
    .m_axil_awvalid(dqa_awvalid[0]), .m_axil_awready(dqa_awready[0]),
    .m_axil_wdata(dqa_wdata[0*AXIL_DATA_WIDTH +: AXIL_DATA_WIDTH]),
    .m_axil_wstrb(dqa_wstrb[0*AXIL_STRB_WIDTH +: AXIL_STRB_WIDTH]),
    .m_axil_wvalid(dqa_wvalid[0]), .m_axil_wready(dqa_wready[0]),
    .m_axil_bresp(dqa_bresp[0*2 +: 2]), .m_axil_bvalid(dqa_bvalid[0]),
    .m_axil_bready(dqa_bready[0]),
    .adv_go(env_dq0_adv_go), .adv_queue(env_dq0_adv_queue),
    .adv_allowed(dq0_adv_allowed),
    .init_done(dq_init_done[0]),
    .adv_fire(dq_adv_fire[0]), .adv_fire_queue(dq_adv_fire_queue[0])
);

corundum_axil_qcfg #(
    .CPL(0), .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .AXIL_ADDR_WIDTH(QM_AXIL_ADDR_WIDTH),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE), .LOG_BLOCK_SIZE(LOG_DESC_BLOCK),
    .BASE_HI20(20'h00020), .BASE_UPPER(32'h0000_0000), .LINK_INDEX(24'd1)
)
env_cfg_dq1 (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(dqa_awaddr[1*QM_AXIL_ADDR_WIDTH +: QM_AXIL_ADDR_WIDTH]), .m_axil_awprot(dqa_awprot[1*3 +: 3]),
    .m_axil_awvalid(dqa_awvalid[1]), .m_axil_awready(dqa_awready[1]),
    .m_axil_wdata(dqa_wdata[1*AXIL_DATA_WIDTH +: AXIL_DATA_WIDTH]),
    .m_axil_wstrb(dqa_wstrb[1*AXIL_STRB_WIDTH +: AXIL_STRB_WIDTH]),
    .m_axil_wvalid(dqa_wvalid[1]), .m_axil_wready(dqa_wready[1]),
    .m_axil_bresp(dqa_bresp[1*2 +: 2]), .m_axil_bvalid(dqa_bvalid[1]),
    .m_axil_bready(dqa_bready[1]),
    .adv_go(env_dq1_adv_go), .adv_queue(env_dq1_adv_queue),
    .adv_allowed(dq1_adv_allowed),
    .init_done(dq_init_done[1]),
    .adv_fire(dq_adv_fire[1]), .adv_fire_queue(dq_adv_fire_queue[1])
);

corundum_axil_qcfg #(
    .CPL(1), .QUEUE_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
    .AXIL_ADDR_WIDTH(CQM_AXIL_ADDR_WIDTH),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE), .LOG_BLOCK_SIZE(0),
    .BASE_HI20(20'h00040), .BASE_UPPER(32'h0000_0000), .LINK_INDEX(24'd0)
)
env_cfg_cq0 (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(cqa_awaddr[0*CQM_AXIL_ADDR_WIDTH +: CQM_AXIL_ADDR_WIDTH]), .m_axil_awprot(cqa_awprot[0*3 +: 3]),
    .m_axil_awvalid(cqa_awvalid[0]), .m_axil_awready(cqa_awready[0]),
    .m_axil_wdata(cqa_wdata[0*AXIL_DATA_WIDTH +: AXIL_DATA_WIDTH]),
    .m_axil_wstrb(cqa_wstrb[0*AXIL_STRB_WIDTH +: AXIL_STRB_WIDTH]),
    .m_axil_wvalid(cqa_wvalid[0]), .m_axil_wready(cqa_wready[0]),
    .m_axil_bresp(cqa_bresp[0*2 +: 2]), .m_axil_bvalid(cqa_bvalid[0]),
    .m_axil_bready(cqa_bready[0]),
    .adv_go(env_cq0_adv_go), .adv_queue(env_cq0_adv_queue),
    .adv_allowed(cq0_adv_allowed),
    .init_done(cq_init_done[0]),
    .adv_fire(cq_adv_fire[0]), .adv_fire_queue(cq_adv_fire_queue[0])
);

corundum_axil_qcfg #(
    .CPL(1), .QUEUE_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
    .AXIL_ADDR_WIDTH(CQM_AXIL_ADDR_WIDTH),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE), .LOG_BLOCK_SIZE(0),
    .BASE_HI20(20'h00080), .BASE_UPPER(32'h0000_0000), .LINK_INDEX(24'd1)
)
env_cfg_cq1 (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(cqa_awaddr[1*CQM_AXIL_ADDR_WIDTH +: CQM_AXIL_ADDR_WIDTH]), .m_axil_awprot(cqa_awprot[1*3 +: 3]),
    .m_axil_awvalid(cqa_awvalid[1]), .m_axil_awready(cqa_awready[1]),
    .m_axil_wdata(cqa_wdata[1*AXIL_DATA_WIDTH +: AXIL_DATA_WIDTH]),
    .m_axil_wstrb(cqa_wstrb[1*AXIL_STRB_WIDTH +: AXIL_STRB_WIDTH]),
    .m_axil_wvalid(cqa_wvalid[1]), .m_axil_wready(cqa_wready[1]),
    .m_axil_bresp(cqa_bresp[1*2 +: 2]), .m_axil_bvalid(cqa_bvalid[1]),
    .m_axil_bready(cqa_bready[1]),
    .adv_go(env_cq1_adv_go), .adv_queue(env_cq1_adv_queue),
    .adv_allowed(cq1_adv_allowed),
    .init_done(cq_init_done[1]),
    .adv_fire(cq_adv_fire[1]), .adv_fire_queue(cq_adv_fire_queue[1])
);

corundum_host_rd #(
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .SEG_ADDR_WIDTH(SEG_ADDR_WIDTH),
    .SEG_DATA_WIDTH(SEG_DATA_WIDTH),
    .SEG_BE_WIDTH(SEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH)
)
env_host_rd (
    .clk(clk), .rst(rst),
    .s_desc_dma_addr(rd_desc_dma_addr),
    .s_desc_ram_addr(rd_desc_ram_addr),
    .s_desc_len(rd_desc_len),
    .s_desc_tag(rd_desc_tag),
    .s_desc_valid(rd_desc_valid),
    .s_desc_ready(rd_desc_ready),
    .m_status_tag(rd_status_tag),
    .m_status_error(rd_status_error),
    .m_status_valid(rd_status_valid),
    .ram_wr_cmd_be(df_ram_wr_be),
    .ram_wr_cmd_addr(df_ram_wr_addr),
    .ram_wr_cmd_data(df_ram_wr_data),
    .ram_wr_cmd_valid(df_ram_wr_valid),
    .ram_wr_cmd_ready(df_ram_wr_ready),
    .ram_wr_done(df_ram_wr_done),
    .env_delay(env_rd_delay)
);

corundum_desc_engine #(
    .REQ_TAG_WIDTH(REQ_TAG_WIDTH),
    .CPL_QUEUE_INDEX_WIDTH(CPL_QUEUE_INDEX_WIDTH),
    .SELECT_WIDTH(SELECT_WIDTH),
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .CPL_SIZE(CPL_SIZE)
)
env_engine (
    .clk(clk), .rst(rst),
    .st_cpl(df_st_cpl),
    .st_empty(df_st_empty),
    .st_error(df_st_error),
    .st_valid(df_st_valid),
    .env_cpl_sel(env_cpl_sel),
    .s_desc_tdata(desc_tdata),
    .s_desc_tvalid(desc_tvalid),
    .s_desc_tready(desc_tready),
    .s_desc_tlast(desc_tlast),
    .s_desc_tid(desc_tid),
    .env_bp(env_desc_bp),
    .m_req_sel(cw_req_sel),
    .m_req_queue(cw_req_queue),
    .m_req_tag(cw_req_tag),
    .m_req_data(cw_req_data),
    .m_req_valid(cw_req_valid),
    .m_req_ready(cw_req_ready)
);

corundum_host_wr #(
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .SEG_ADDR_WIDTH(SEG_ADDR_WIDTH),
    .SEG_DATA_WIDTH(SEG_DATA_WIDTH),
    .SEG_BE_WIDTH(SEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH)
)
env_host_wr (
    .clk(clk), .rst(rst),
    .s_desc_dma_addr(wr_desc_dma_addr),
    .s_desc_ram_addr(wr_desc_ram_addr),
    .s_desc_len(wr_desc_len),
    .s_desc_tag(wr_desc_tag),
    .s_desc_valid(wr_desc_valid),
    .s_desc_ready(wr_desc_ready),
    .m_status_tag(wr_status_tag),
    .m_status_error(wr_status_error),
    .m_status_valid(wr_status_valid),
    .ram_rd_cmd_addr(cw_ram_rd_addr),
    .ram_rd_cmd_valid(cw_ram_rd_valid),
    .ram_rd_cmd_ready(cw_ram_rd_ready),
    .ram_rd_resp_data(cw_ram_rd_data),
    .ram_rd_resp_valid(cw_ram_rd_resp_valid),
    .ram_rd_resp_ready(cw_ram_rd_resp_ready),
    .env_delay(env_wr_delay),
    .host_wr_valid(host_cpl_valid),
    .host_wr_addr(host_cpl_addr),
    .host_wr_data(host_cpl_data)
);

endmodule


// ===========================================================================
// corundum_axil_qcfg -- the driver.
//
// Eight AXI-Lite writes per ring bring it up: disable, base low, base high,
// size, linked queue index, producer pointer, consumer pointer, enable.  After
// that it sits in RUN and, whenever the environment asks and the ring
// accounting allows, bumps one pointer by one: the PRODUCER pointer on a
// descriptor ring (software posting a descriptor) or the CONSUMER pointer on a
// completion ring (software retiring a completion).
//
// The shadow pointer is this module's own; it never reads one back.
// ===========================================================================
module corundum_axil_qcfg #(
    parameter CPL               = 0,
    parameter QUEUE_INDEX_WIDTH = 1,
    parameter AXIL_ADDR_WIDTH   = 6,
    parameter LOG_QUEUE_SIZE    = 2,
    parameter LOG_BLOCK_SIZE    = 1,
    parameter [19:0] BASE_HI20  = 20'h00010,
    parameter [31:0] BASE_UPPER = 32'h0000_0000,
    parameter [23:0] LINK_INDEX = 24'd0
)(
    input  wire                            clk,
    input  wire                            rst,

    output wire [AXIL_ADDR_WIDTH-1:0]      m_axil_awaddr,
    output wire [2:0]                      m_axil_awprot,
    output wire                            m_axil_awvalid,
    input  wire                            m_axil_awready,
    output wire [31:0]                     m_axil_wdata,
    output wire [3:0]                      m_axil_wstrb,
    output wire                            m_axil_wvalid,
    input  wire                            m_axil_wready,
    input  wire [1:0]                      m_axil_bresp,
    input  wire                            m_axil_bvalid,
    output wire                            m_axil_bready,

    input  wire                            adv_go,
    input  wire [QUEUE_INDEX_WIDTH-1:0]    adv_queue,
    input  wire [(2**QUEUE_INDEX_WIDTH)-1:0] adv_allowed,

    output wire                            init_done,
    output wire                            adv_fire,
    output wire [QUEUE_INDEX_WIDTH-1:0]    adv_fire_queue
);

localparam NQ     = 2**QUEUE_INDEX_WIDTH;
localparam QSHIFT = CPL ? 4 : 5;

reg  [2:0]                     step_reg;
reg  [QUEUE_INDEX_WIDTH-1:0]   q_reg;
reg                            done_reg;
reg                            busy_reg;
reg                            aw_done_reg;
reg                            w_done_reg;
reg                            run_reg;
reg  [AXIL_ADDR_WIDTH-1:0]     awaddr_reg;
reg  [31:0]                    wdata_reg;
reg  [15:0]                    ptr_reg [0:NQ-1];

integer ii;
initial begin
    for (ii = 0; ii < NQ; ii = ii + 1) ptr_reg[ii] = 16'd0;
end

wire launch_run = done_reg && !busy_reg && adv_go && adv_allowed[adv_queue];

assign m_axil_awvalid   = busy_reg && !aw_done_reg;
assign m_axil_wvalid    = busy_reg && !w_done_reg;
assign m_axil_awaddr    = awaddr_reg;
assign m_axil_wdata     = wdata_reg;
assign m_axil_wstrb     = 4'hF;
assign m_axil_awprot    = 3'd0;
assign m_axil_bready    = 1'b1;
assign init_done        = done_reg;
assign adv_fire         = launch_run;
assign adv_fire_queue   = adv_queue;

function [31:0] step_data;
    input [2:0] s;
    input [QUEUE_INDEX_WIDTH-1:0] q;
    reg [19:0] base;
    begin
        base = BASE_HI20 + {{(20-QUEUE_INDEX_WIDTH){1'b0}}, q};
        case (s)
            3'd0:    step_data = 32'h4000_0100;                        // enable = 0
            3'd1:    step_data = {base, 12'h000};                      // base[31:12]
            3'd2:    step_data = BASE_UPPER;                           // base[63:32]
            3'd3:    step_data = 32'h8002_0000
                                 | (CPL ? 32'd0 : (LOG_BLOCK_SIZE << 8))
                                 | LOG_QUEUE_SIZE;                     // set size
            3'd4:    step_data = {8'hC0, LINK_INDEX
                                       + {{(24-QUEUE_INDEX_WIDTH){1'b0}}, q}}; // CQN / EQN
            3'd5:    step_data = 32'h8080_0000;                        // producer ptr = 0
            3'd6:    step_data = 32'h8090_0000;                        // consumer ptr = 0
            default: step_data = 32'h4000_0101;                        // enable = 1
        endcase
    end
endfunction

function [AXIL_ADDR_WIDTH-1:0] step_addr;
    input [2:0] s;
    input [QUEUE_INDEX_WIDTH-1:0] q;
    reg [2:0] r;
    reg [15:0] wide;
    begin
        case (s)
            3'd1:    r = 3'd0;
            3'd2:    r = 3'd1;
            default: r = 3'd2;
        endcase
        wide = {{(16-QUEUE_INDEX_WIDTH){1'b0}}, q};
        step_addr = (wide << QSHIFT) | {13'd0, r} << 2;
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        step_reg    <= 3'd0;
        q_reg       <= {QUEUE_INDEX_WIDTH{1'b0}};
        done_reg    <= 1'b0;
        busy_reg    <= 1'b0;
        aw_done_reg <= 1'b0;
        w_done_reg  <= 1'b0;
        run_reg     <= 1'b0;
        awaddr_reg  <= {AXIL_ADDR_WIDTH{1'b0}};
        wdata_reg   <= 32'd0;
        for (ii = 0; ii < NQ; ii = ii + 1) ptr_reg[ii] <= 16'd0;
    end else if (!busy_reg) begin
        if (!done_reg) begin
            busy_reg    <= 1'b1;
            aw_done_reg <= 1'b0;
            w_done_reg  <= 1'b0;
            run_reg     <= 1'b0;
            awaddr_reg  <= step_addr(step_reg, q_reg);
            wdata_reg   <= step_data(step_reg, q_reg);
        end else if (launch_run) begin
            busy_reg    <= 1'b1;
            aw_done_reg <= 1'b0;
            w_done_reg  <= 1'b0;
            run_reg     <= 1'b1;
            awaddr_reg  <= step_addr(3'd5, adv_queue);
            wdata_reg   <= (CPL ? 32'h8090_0000 : 32'h8080_0000)
                           | {16'd0, (ptr_reg[adv_queue] + 16'd1)};
            ptr_reg[adv_queue] <= ptr_reg[adv_queue] + 16'd1;
        end
    end else begin
        if (m_axil_awvalid && m_axil_awready) aw_done_reg <= 1'b1;
        if (m_axil_wvalid  && m_axil_wready ) w_done_reg  <= 1'b1;
        if (m_axil_bvalid) begin
            busy_reg <= 1'b0;
            if (!run_reg) begin
                if (step_reg == 3'd7) begin
                    step_reg <= 3'd0;
                    if (q_reg == NQ-1) done_reg <= 1'b1;
                    else               q_reg    <= q_reg + 1'b1;
                end else begin
                    step_reg <= step_reg + 3'd1;
                end
            end
        end
    end
end

endmodule


// ===========================================================================
// corundum_host_rd -- the descriptor side of host memory.
//
// A DMA read descriptor names a host address, a RAM address, a length and a
// tag.  This model writes `len` bytes of a PURE FUNCTION of the host address
// into the design's descriptor RAM, waits a bounded number of cycles, then
// returns status.  `host_word` is what makes the end-to-end data check
// possible: the checker recomputes the same function from the address it saw
// on the wire and never reads the RAM.
// ===========================================================================
module corundum_host_rd #(
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_LEN_WIDTH  = 8,
    parameter DMA_TAG_WIDTH  = 4,
    parameter SEG_ADDR_WIDTH = 3,
    parameter SEG_DATA_WIDTH = 64,
    parameter SEG_BE_WIDTH   = 8,
    parameter RAM_ADDR_WIDTH = 6
)(
    input  wire                       clk,
    input  wire                       rst,

    input  wire [DMA_ADDR_WIDTH-1:0]  s_desc_dma_addr,
    input  wire [RAM_ADDR_WIDTH-1:0]  s_desc_ram_addr,
    input  wire [DMA_LEN_WIDTH-1:0]   s_desc_len,
    input  wire [DMA_TAG_WIDTH-1:0]   s_desc_tag,
    input  wire                       s_desc_valid,
    output wire                       s_desc_ready,

    output wire [DMA_TAG_WIDTH-1:0]   m_status_tag,
    output wire [3:0]                 m_status_error,
    output wire                       m_status_valid,

    output wire [SEG_BE_WIDTH-1:0]    ram_wr_cmd_be,
    output wire [SEG_ADDR_WIDTH-1:0]  ram_wr_cmd_addr,
    output wire [SEG_DATA_WIDTH-1:0]  ram_wr_cmd_data,
    output wire                       ram_wr_cmd_valid,
    input  wire                       ram_wr_cmd_ready,
    input  wire                       ram_wr_done,

    input  wire [1:0]                 env_delay
);

localparam ST_IDLE = 2'd0, ST_WRITE = 2'd1, ST_WAIT = 2'd2, ST_STATUS = 2'd3;

reg [1:0]                     st_reg;
reg [DMA_ADDR_WIDTH-1:0]      addr_reg;
reg [SEG_ADDR_WIDTH-1:0]      wa_reg;
reg [4:0]                     left_reg;
reg [DMA_TAG_WIDTH-1:0]       tag_reg;
reg [1:0]                     delay_reg;

function [63:0] host_word;
    input [DMA_ADDR_WIDTH-1:0] a;
    begin
        host_word = {a[31:0], ~a[31:0]};
    end
endfunction

assign s_desc_ready     = (st_reg == ST_IDLE);
assign ram_wr_cmd_valid = (st_reg == ST_WRITE);
assign ram_wr_cmd_be    = {SEG_BE_WIDTH{1'b1}};
assign ram_wr_cmd_addr  = wa_reg;
assign ram_wr_cmd_data  = host_word(addr_reg);
assign m_status_valid   = (st_reg == ST_STATUS);
assign m_status_tag     = tag_reg;
assign m_status_error   = 4'd0;

wire [4:0] words_in = (s_desc_len[DMA_LEN_WIDTH-1:3] == 5'd0)
                      ? 5'd1 : s_desc_len[7:3];

always @(posedge clk) begin
    if (rst) begin
        st_reg    <= ST_IDLE;
        addr_reg  <= {DMA_ADDR_WIDTH{1'b0}};
        wa_reg    <= {SEG_ADDR_WIDTH{1'b0}};
        left_reg  <= 5'd0;
        tag_reg   <= {DMA_TAG_WIDTH{1'b0}};
        delay_reg <= 2'd0;
    end else begin
        case (st_reg)
            ST_IDLE: begin
                if (s_desc_valid) begin
                    addr_reg  <= s_desc_dma_addr;
                    wa_reg    <= s_desc_ram_addr[RAM_ADDR_WIDTH-1:3];
                    left_reg  <= words_in;
                    tag_reg   <= s_desc_tag;
                    delay_reg <= env_delay;
                    st_reg    <= ST_WRITE;
                end
            end
            ST_WRITE: begin
                if (ram_wr_cmd_ready) begin
                    addr_reg <= addr_reg + 64'd8;
                    wa_reg   <= wa_reg + 1'b1;
                    left_reg <= left_reg - 5'd1;
                    if (left_reg <= 5'd1) st_reg <= ST_WAIT;
                end
            end
            ST_WAIT: begin
                if (delay_reg == 2'd0) st_reg <= ST_STATUS;
                else                   delay_reg <= delay_reg - 2'd1;
            end
            default: begin
                st_reg <= ST_IDLE;
            end
        endcase
    end
end

endmodule


// ===========================================================================
// corundum_desc_engine -- what a real mqnic TX engine reduces to here.
//
// It remembers which completion ring each successful fetch was told to write
// to (that is the `cpl` field of the fetch's own request status), consumes the
// descriptor stream, and on the last beat of a descriptor turns it into one
// completion write request carrying the descriptor's own tag and last word.
//
// The descriptor sink stalls only when the environment asks AND it has not
// already stalled three cycles running, so nothing downstream can be starved
// for ever by the environment alone.
// ===========================================================================
module corundum_desc_engine #(
    parameter REQ_TAG_WIDTH         = 4,
    parameter CPL_QUEUE_INDEX_WIDTH = 1,
    parameter SELECT_WIDTH          = 1,
    parameter AXIS_DATA_WIDTH       = 64,
    parameter CPL_SIZE              = 8
)(
    input  wire                             clk,
    input  wire                             rst,

    input  wire [CPL_QUEUE_INDEX_WIDTH-1:0] st_cpl,
    input  wire                             st_empty,
    input  wire                             st_error,
    input  wire                             st_valid,
    input  wire [SELECT_WIDTH-1:0]          env_cpl_sel,

    input  wire [AXIS_DATA_WIDTH-1:0]       s_desc_tdata,
    input  wire                             s_desc_tvalid,
    output wire                             s_desc_tready,
    input  wire                             s_desc_tlast,
    input  wire [REQ_TAG_WIDTH-1:0]         s_desc_tid,
    input  wire                             env_bp,

    output wire [SELECT_WIDTH-1:0]          m_req_sel,
    output wire [CPL_QUEUE_INDEX_WIDTH-1:0] m_req_queue,
    output wire [REQ_TAG_WIDTH-1:0]         m_req_tag,
    output wire [CPL_SIZE*8-1:0]            m_req_data,
    output wire                             m_req_valid,
    input  wire                             m_req_ready
);

localparam FIFO_AW = 3;
localparam FIFO_N  = 8;

reg [CPL_QUEUE_INDEX_WIDTH-1:0] fifo_cpl [0:FIFO_N-1];
reg [SELECT_WIDTH-1:0]          fifo_sel [0:FIFO_N-1];
reg [FIFO_AW:0]                 wr_ptr_reg;
reg [FIFO_AW:0]                 rd_ptr_reg;

reg                             req_valid_reg;
reg [SELECT_WIDTH-1:0]          req_sel_reg;
reg [CPL_QUEUE_INDEX_WIDTH-1:0] req_queue_reg;
reg [REQ_TAG_WIDTH-1:0]         req_tag_reg;
reg [CPL_SIZE*8-1:0]            req_data_reg;

reg [1:0]                       bp_cnt_reg;

integer ii;
initial begin
    for (ii = 0; ii < FIFO_N; ii = ii + 1) begin
        fifo_cpl[ii] = {CPL_QUEUE_INDEX_WIDTH{1'b0}};
        fifo_sel[ii] = {SELECT_WIDTH{1'b0}};
    end
end

wire fifo_empty = (wr_ptr_reg == rd_ptr_reg);
wire fifo_full  = (wr_ptr_reg[FIFO_AW-1:0] == rd_ptr_reg[FIFO_AW-1:0])
                  && (wr_ptr_reg[FIFO_AW] != rd_ptr_reg[FIFO_AW]);

wire push = st_valid && !st_empty && !st_error && !fifo_full;
wire allow_stall = (bp_cnt_reg != 2'd3);

assign s_desc_tready = !req_valid_reg && !(env_bp && allow_stall);

wire beat = s_desc_tvalid && s_desc_tready;
wire pop  = beat && s_desc_tlast && !fifo_empty;

assign m_req_sel   = req_sel_reg;
assign m_req_queue = req_queue_reg;
assign m_req_tag   = req_tag_reg;
assign m_req_data  = req_data_reg;
assign m_req_valid = req_valid_reg;

always @(posedge clk) begin
    if (rst) begin
        wr_ptr_reg    <= {(FIFO_AW+1){1'b0}};
        rd_ptr_reg    <= {(FIFO_AW+1){1'b0}};
        req_valid_reg <= 1'b0;
        req_sel_reg   <= {SELECT_WIDTH{1'b0}};
        req_queue_reg <= {CPL_QUEUE_INDEX_WIDTH{1'b0}};
        req_tag_reg   <= {REQ_TAG_WIDTH{1'b0}};
        req_data_reg  <= {(CPL_SIZE*8){1'b0}};
        bp_cnt_reg    <= 2'd0;
    end else begin
        if (push) begin
            fifo_cpl[wr_ptr_reg[FIFO_AW-1:0]] <= st_cpl;
            fifo_sel[wr_ptr_reg[FIFO_AW-1:0]] <= env_cpl_sel;
            wr_ptr_reg <= wr_ptr_reg + 1'b1;
        end

        if (pop) rd_ptr_reg <= rd_ptr_reg + 1'b1;

        if (beat && s_desc_tlast) begin
            req_valid_reg <= 1'b1;
            req_sel_reg   <= fifo_sel[rd_ptr_reg[FIFO_AW-1:0]];
            req_queue_reg <= fifo_cpl[rd_ptr_reg[FIFO_AW-1:0]];
            req_tag_reg   <= s_desc_tid;
            req_data_reg  <= s_desc_tdata;
        end else if (req_valid_reg && m_req_ready) begin
            req_valid_reg <= 1'b0;
        end

        if (s_desc_tvalid && !s_desc_tready) begin
            if (bp_cnt_reg != 2'd3) bp_cnt_reg <= bp_cnt_reg + 2'd1;
        end else begin
            bp_cnt_reg <= 2'd0;
        end
    end
end

endmodule


// ===========================================================================
// corundum_host_wr -- the completion side of host memory.
//
// Reads the completion word out of cpl_write's own data table over the DMA RAM
// read port, publishes it as the host write (`host_wr_*`, the far observation
// point of the whole chain), waits a bounded number of cycles and returns
// status.
// ===========================================================================
module corundum_host_wr #(
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_LEN_WIDTH  = 8,
    parameter DMA_TAG_WIDTH  = 4,
    parameter SEG_ADDR_WIDTH = 3,
    parameter SEG_DATA_WIDTH = 64,
    parameter SEG_BE_WIDTH   = 8,
    parameter RAM_ADDR_WIDTH = 6
)(
    input  wire                       clk,
    input  wire                       rst,

    input  wire [DMA_ADDR_WIDTH-1:0]  s_desc_dma_addr,
    input  wire [RAM_ADDR_WIDTH-1:0]  s_desc_ram_addr,
    input  wire [DMA_LEN_WIDTH-1:0]   s_desc_len,
    input  wire [DMA_TAG_WIDTH-1:0]   s_desc_tag,
    input  wire                       s_desc_valid,
    output wire                       s_desc_ready,

    output wire [DMA_TAG_WIDTH-1:0]   m_status_tag,
    output wire [3:0]                 m_status_error,
    output wire                       m_status_valid,

    output wire [SEG_ADDR_WIDTH-1:0]  ram_rd_cmd_addr,
    output wire                       ram_rd_cmd_valid,
    input  wire                       ram_rd_cmd_ready,
    input  wire [SEG_DATA_WIDTH-1:0]  ram_rd_resp_data,
    input  wire                       ram_rd_resp_valid,
    output wire                       ram_rd_resp_ready,

    input  wire [1:0]                 env_delay,

    output wire                       host_wr_valid,
    output wire [DMA_ADDR_WIDTH-1:0]  host_wr_addr,
    output wire [SEG_DATA_WIDTH-1:0]  host_wr_data
);

localparam ST_IDLE = 3'd0, ST_CMD = 3'd1, ST_RESP = 3'd2,
           ST_WAIT = 3'd3, ST_STATUS = 3'd4;

reg [2:0]                    st_reg;
reg [DMA_ADDR_WIDTH-1:0]     addr_reg;
reg [SEG_ADDR_WIDTH-1:0]     ra_reg;
reg [4:0]                    left_reg;
reg [DMA_TAG_WIDTH-1:0]      tag_reg;
reg [1:0]                    delay_reg;

reg                          hw_valid_reg;
reg [DMA_ADDR_WIDTH-1:0]     hw_addr_reg;
reg [SEG_DATA_WIDTH-1:0]     hw_data_reg;

assign s_desc_ready      = (st_reg == ST_IDLE);
assign ram_rd_cmd_valid  = (st_reg == ST_CMD);
assign ram_rd_cmd_addr   = ra_reg;
assign ram_rd_resp_ready = (st_reg == ST_RESP);
assign m_status_valid    = (st_reg == ST_STATUS);
assign m_status_tag      = tag_reg;
assign m_status_error    = 4'd0;

assign host_wr_valid     = hw_valid_reg;
assign host_wr_addr      = hw_addr_reg;
assign host_wr_data      = hw_data_reg;

wire [4:0] words_in = (s_desc_len[DMA_LEN_WIDTH-1:3] == 5'd0)
                      ? 5'd1 : s_desc_len[7:3];

always @(posedge clk) begin
    if (rst) begin
        st_reg       <= ST_IDLE;
        addr_reg     <= {DMA_ADDR_WIDTH{1'b0}};
        ra_reg       <= {SEG_ADDR_WIDTH{1'b0}};
        left_reg     <= 5'd0;
        tag_reg      <= {DMA_TAG_WIDTH{1'b0}};
        delay_reg    <= 2'd0;
        hw_valid_reg <= 1'b0;
        hw_addr_reg  <= {DMA_ADDR_WIDTH{1'b0}};
        hw_data_reg  <= {SEG_DATA_WIDTH{1'b0}};
    end else begin
        hw_valid_reg <= 1'b0;
        case (st_reg)
            ST_IDLE: begin
                if (s_desc_valid) begin
                    addr_reg  <= s_desc_dma_addr;
                    ra_reg    <= s_desc_ram_addr[RAM_ADDR_WIDTH-1:3];
                    left_reg  <= words_in;
                    tag_reg   <= s_desc_tag;
                    delay_reg <= env_delay;
                    st_reg    <= ST_CMD;
                end
            end
            ST_CMD: begin
                if (ram_rd_cmd_ready) st_reg <= ST_RESP;
            end
            ST_RESP: begin
                if (ram_rd_resp_valid) begin
                    hw_valid_reg <= 1'b1;
                    hw_addr_reg  <= addr_reg;
                    hw_data_reg  <= ram_rd_resp_data;
                    addr_reg     <= addr_reg + 64'd8;
                    ra_reg       <= ra_reg + 1'b1;
                    left_reg     <= left_reg - 5'd1;
                    if (left_reg <= 5'd1) st_reg <= ST_WAIT;
                    else                  st_reg <= ST_CMD;
                end
            end
            ST_WAIT: begin
                if (delay_reg == 2'd0) st_reg <= ST_STATUS;
                else                   delay_reg <= delay_reg - 2'd1;
            end
            default: begin
                st_reg <= ST_IDLE;
            end
        endcase
    end
end

endmodule

`resetall
