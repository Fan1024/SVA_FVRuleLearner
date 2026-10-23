// ===========================================================================
// Candidate target assertions for Corundum's descriptor / DMA / completion
// datapath.
//
// Bound into `corundum_dma_path_ft`, so every reference below is a
// hierarchical name from that top.  Nothing here is an assumption.
//
// THE ORACLES ARE INDEPENDENT of the design's own bookkeeping.  Five of them:
//
//   1. a per-port shadow queue of dequeue requests, this file's own pointers
//      and payload copy, checked against the response the queue manager
//      presents;
//   2. a shadow queue of started fetches -- one entry per successful dequeue
//      response, one entry per DMA read descriptor -- popped at the last beat
//      of a descriptor, which is how the descriptor stream is checked against
//      the fetch that produced it;
//   3. `host_word()`, RECOMPUTED here from the address seen on the DMA read
//      descriptor wire.  The checker never reads the design's descriptor RAM;
//      it recomputes what the environment must have put there and compares it
//      with what came out of the AXI-Stream three modules later;
//   4. tag-keyed outstanding sets for the two DMA channels and for the two
//      queue managers' operation tags, set at the request and cleared at the
//      response -- the pattern that catches a reused tag or an unsolicited
//      completion;
//   5. saturating wait counters, which is how a fairness / bounded-response /
//      deadlock obligation is written as a SAFETY property.  There is no
//      `s_eventually` in this file.
//
// Ring geometry the checker assumes, and where it comes from: the four
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
localparam FIFO_N           = 8;   // shadow queue depth
localparam SAT              = 10'd1023;

// bounds for the saturating counters
localparam N_BLOCK   = 10'd96;    // a channel offered but not taken
localparam N_FETCH   = 10'd255;   // request accepted -> status returned
localparam N_DESC    = 10'd255;   // fetch started    -> descriptor delivered
localparam N_CPL     = 10'd255;   // cpl request      -> status returned
localparam N_STALL   = 10'd255;   // work outstanding -> some boundary event
localparam N_FULL    = 10'd255;   // desc_fetch table full

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

// -- the far observation point ----------------------------------------------
wire        host_valid = corundum_dma_path_ft.host_cpl_valid;
wire [63:0] host_addr  = corundum_dma_path_ft.host_cpl_addr;
wire [63:0] host_data  = corundum_dma_path_ft.host_cpl_data;

// -- the driver -------------------------------------------------------------
wire [1:0]  dq_adv     = corundum_dma_path_ft.dq_adv_fire;
wire [1:0]  dq_adv_q   = corundum_dma_path_ft.dq_adv_fire_queue;
wire [1:0]  cq_adv     = corundum_dma_path_ft.cq_adv_fire;
wire [1:0]  cq_adv_q   = corundum_dma_path_ft.cq_adv_fire_queue;
wire        configured = corundum_dma_path_ft.all_configured;

// -- design internals the bound and lifecycle targets name ------------------
wire [3:0]  df_tbl_active = corundum_dma_path_ft.u_df.desc_table_active;
wire [2:0]  df_start_ptr  = corundum_dma_path_ft.u_df.desc_table_start_ptr_reg;
wire [2:0]  df_read_ptr   = corundum_dma_path_ft.u_df.desc_table_desc_read_ptr_reg;
wire [2:0]  df_fin_ptr    = corundum_dma_path_ft.u_df.desc_table_finish_ptr_reg;
wire [2:0]  df_active_cnt = corundum_dma_path_ft.u_df.active_count_reg;

wire [3:0]  cw_tbl_active = corundum_dma_path_ft.u_cw.desc_table_active;
wire [2:0]  cw_start_ptr  = corundum_dma_path_ft.u_cw.desc_table_start_ptr_reg;
wire [2:0]  cw_fin_ptr    = corundum_dma_path_ft.u_cw.desc_table_finish_ptr_reg;

// Modular differences, taken at THEIR OWN width.  Written inline in a
// comparison against an integer these would be widened to 32 bits first and a
// legal wrap would read as a huge positive number.
wire [2:0]  df_span      = df_start_ptr - df_fin_ptr;
wire [2:0]  df_read_span = df_start_ptr - df_read_ptr;
wire [2:0]  cw_span      = cw_start_ptr - cw_fin_ptr;

wire [3:0]  qm0_op_active = corundum_dma_path_ft.g_dqm[0].u_qm.op_table_active;
wire [3:0]  qm1_op_active = corundum_dma_path_ft.g_dqm[1].u_qm.op_table_active;
wire [3:0]  cqm0_op_active = corundum_dma_path_ft.g_cqm[0].u_cqm.op_table_active;
wire [3:0]  cqm1_op_active = corundum_dma_path_ft.g_cqm[1].u_cqm.op_table_active;

wire [127:0] qm0_q0 = corundum_dma_path_ft.g_dqm[0].u_qm.queue_ram[0];
wire [127:0] qm0_q1 = corundum_dma_path_ft.g_dqm[0].u_qm.queue_ram[1];
wire [127:0] cqm0_q0 = corundum_dma_path_ft.g_cqm[0].u_cqm.queue_ram[0];
wire [127:0] cqm0_q1 = corundum_dma_path_ft.g_cqm[0].u_cqm.queue_ram[1];

// ===================================================================== ==
// The host-memory word.  RECOMPUTED, not read: `corundum_host_rd` writes
// this function of the byte address into the descriptor RAM, and the checker
// asserts that the same function of the address it saw on the DMA read
// descriptor wire comes back out of the AXI-Stream.
// ===================================================================== ==
function automatic [63:0] host_word(input [31:0] a);
    host_word = {a, ~a};
endfunction

// ===================================================================== ==
// ORACLE 1 -- per-port shadow queue of dequeue requests.
// Pushed when the queue manager takes a request, popped when it answers.
// Four entries: the manager admits one request into its pipeline at a time.
// ===================================================================== ==
reg [3:0] dqq_tag  [0:PORTS*4-1];
reg       dqq_q    [0:PORTS*4-1];
reg [2:0] dqq_wr   [0:PORTS-1];
reg [2:0] dqq_rd   [0:PORTS-1];

wire [1:0] dq_req_fire  = dq_req_valid & dq_req_ready;
wire [1:0] dq_resp_fire = dq_resp_valid & dq_resp_ready;

wire dqq0_empty = (dqq_wr[0] == dqq_rd[0]);
wire dqq1_empty = (dqq_wr[1] == dqq_rd[1]);
wire [3:0] dqq0_head_tag = dqq_tag[0*4 + dqq_rd[0][1:0]];
wire [3:0] dqq1_head_tag = dqq_tag[1*4 + dqq_rd[1][1:0]];
wire       dqq0_head_q   = dqq_q  [0*4 + dqq_rd[0][1:0]];
wire       dqq1_head_q   = dqq_q  [1*4 + dqq_rd[1][1:0]];

integer i;
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < PORTS; i = i + 1) begin
            dqq_wr[i] <= 3'd0;
            dqq_rd[i] <= 3'd0;
        end
    end else begin
        if (dq_req_fire[0]) begin
            dqq_tag[0*4 + dqq_wr[0][1:0]] <= dq_req_tag[3:0];
            dqq_q  [0*4 + dqq_wr[0][1:0]] <= dq_req_queue[0];
            dqq_wr[0] <= dqq_wr[0] + 3'd1;
        end
        if (dq_req_fire[1]) begin
            dqq_tag[1*4 + dqq_wr[1][1:0]] <= dq_req_tag[7:4];
            dqq_q  [1*4 + dqq_wr[1][1:0]] <= dq_req_queue[1];
            dqq_wr[1] <= dqq_wr[1] + 3'd1;
        end
        if (dq_resp_fire[0] && !dqq0_empty) dqq_rd[0] <= dqq_rd[0] + 3'd1;
        if (dq_resp_fire[1] && !dqq1_empty) dqq_rd[1] <= dqq_rd[1] + 3'd1;
    end
end

// ===================================================================== ==
// ORACLE 2 -- the started-fetch queues.
//
// `sq` holds one caller tag per dequeue response that actually took a
// descriptor; `fq` holds one {host address, length} per DMA read descriptor
// desc_fetch issued.  Both are popped at the last beat of a descriptor, which
// is the point where the AXI-Stream can be compared with the fetch it came
// from.  Neither reads a design register.
// ===================================================================== ==
reg [3:0]  sq_tag  [0:FIFO_N-1];
reg [3:0]  sq_wr, sq_rd;
reg [31:0] fq_addr [0:FIFO_N-1];
reg [7:0]  fq_len  [0:FIFO_N-1];
reg [3:0]  fq_wr, fq_rd;
reg [1:0]  beat_idx;

wire sq_empty = (sq_wr == sq_rd);
wire fq_empty = (fq_wr == fq_rd);
wire [3:0]  sq_head_tag  = sq_tag [sq_rd[2:0]];
wire [31:0] fq_head_addr = fq_addr[fq_rd[2:0]];
wire [7:0]  fq_head_len  = fq_len [fq_rd[2:0]];
wire [3:0]  sq_occ = sq_wr - sq_rd;
wire [3:0]  fq_occ = fq_wr - fq_rd;

wire [63:0] desc_expect = host_word(fq_head_addr + {26'd0, beat_idx, 3'd0});

always @(posedge clk) begin
    if (rst) begin
        sq_wr <= 4'd0; sq_rd <= 4'd0;
        fq_wr <= 4'd0; fq_rd <= 4'd0;
        beat_idx <= 2'd0;
    end else begin
        if (df_st_ok) begin
            sq_tag[sq_wr[2:0]] <= df_st_tag;
            sq_wr <= sq_wr + 4'd1;
        end
        if (rd_fire) begin
            fq_addr[fq_wr[2:0]] <= rd_addr[31:0];
            fq_len [fq_wr[2:0]] <= rd_len;
            fq_wr <= fq_wr + 4'd1;
        end
        if (desc_beat && desc_tlast) begin
            if (!sq_empty) sq_rd <= sq_rd + 4'd1;
            if (!fq_empty) fq_rd <= fq_rd + 4'd1;
            beat_idx <= 2'd0;
        end else if (desc_beat) begin
            beat_idx <= beat_idx + 2'd1;
        end
    end
end

// ===================================================================== ==
// ORACLE 3 -- tag-keyed outstanding sets for the two DMA channels.
// ===================================================================== ==
reg [15:0] rd_out;
reg [15:0] wr_out;

always @(posedge clk) begin
    if (rst) begin
        rd_out <= 16'd0;
        wr_out <= 16'd0;
    end else begin
        if (rd_fire)   rd_out[rd_tag]    <= 1'b1;
        if (rd_st_val) rd_out[rd_st_tag] <= 1'b0;
        if (wr_fire)   wr_out[wr_tag]    <= 1'b1;
        if (wr_st_val) wr_out[wr_st_tag] <= 1'b0;
    end
end

// ===================================================================== ==
// ORACLE 4 -- operation-tag sets for the four queue managers, plus the
// completion slot table.
// ===================================================================== ==
reg [3:0] dq_ops [0:PORTS-1];
reg [3:0] cq_ops [0:PORTS-1];

wire [1:0] dq_take = dq_resp_fire & ~dq_resp_empty & ~dq_resp_error;
wire [1:0] cq_take = (cq_resp_valid & cq_resp_ready) & ~cq_resp_full & ~cq_resp_error;
wire [1:0] dq_commit_fire = dq_commit_valid & dq_commit_ready;
wire [1:0] cq_commit_fire = cq_commit_valid & cq_commit_ready;

always @(posedge clk) begin
    if (rst) begin
        dq_ops[0] <= 4'd0; dq_ops[1] <= 4'd0;
        cq_ops[0] <= 4'd0; cq_ops[1] <= 4'd0;
    end else begin
        if (dq_take[0])        dq_ops[0][dq_resp_optag[1:0]]   <= 1'b1;
        if (dq_commit_fire[0]) dq_ops[0][dq_commit_optag[1:0]] <= 1'b0;
        if (dq_take[1])        dq_ops[1][dq_resp_optag[3:2]]   <= 1'b1;
        if (dq_commit_fire[1]) dq_ops[1][dq_commit_optag[3:2]] <= 1'b0;
        if (cq_take[0])        cq_ops[0][cq_resp_optag[1:0]]   <= 1'b1;
        if (cq_commit_fire[0]) cq_ops[0][cq_commit_optag[1:0]] <= 1'b0;
        if (cq_take[1])        cq_ops[1][cq_resp_optag[3:2]]   <= 1'b1;
        if (cq_commit_fire[1]) cq_ops[1][cq_commit_optag[3:2]] <= 1'b0;
    end
end

// the completion payload, remembered by the slot cpl_write hands the DMA
// engine.  The slot allocator is the checker's own modulo-4 counter.
reg [63:0] cs_data [0:CPL_TABLE_SIZE-1];
reg [3:0]  cs_tag  [0:CPL_TABLE_SIZE-1];
reg [CPL_TABLE_SIZE-1:0] cs_live;
reg [1:0]  cs_idx;
reg [1:0]  hw_slot;

always @(posedge clk) begin
    if (rst) begin
        cs_live <= {CPL_TABLE_SIZE{1'b0}};
        cs_idx  <= 2'd0;
        hw_slot <= 2'd0;
    end else begin
        if (wr_st_val) cs_live[wr_st_tag[1:0]] <= 1'b0;
        if (cw_req_fire) begin
            cs_data[cs_idx] <= cw_req_data;
            cs_tag [cs_idx] <= cw_req_tag;
            cs_live[cs_idx] <= 1'b1;
            cs_idx <= cs_idx + 2'd1;
        end
        if (wr_fire) hw_slot <= wr_ram[4:3];
    end
end

// ===================================================================== ==
// ORACLE 5 -- ring accounting, kept by the checker itself.
//
// `dring_post` counts the producer-pointer bumps the driver issued into each
// descriptor ring; `dring_take` counts the descriptors the design handed out
// of it.  `cring_make` counts the completions the design started into each
// completion ring; `cring_eat` counts the consumer-pointer bumps the driver
// issued.  Index is {port, ring}.
// ===================================================================== ==
reg [7:0] dring_post [0:PORTS*2-1];
reg [7:0] dring_take [0:PORTS*2-1];
reg [7:0] cring_make [0:PORTS*2-1];
reg [7:0] cring_eat  [0:PORTS*2-1];

wire [7:0] dring_bal0 = dring_post[0] - dring_take[0];
wire [7:0] dring_bal1 = dring_post[1] - dring_take[1];
wire [7:0] dring_bal2 = dring_post[2] - dring_take[2];
wire [7:0] dring_bal3 = dring_post[3] - dring_take[3];
wire [7:0] cring_occ0 = cring_make[0] - cring_eat[0];
wire [7:0] cring_occ1 = cring_make[1] - cring_eat[1];
wire [7:0] cring_occ2 = cring_make[2] - cring_eat[2];
wire [7:0] cring_occ3 = cring_make[3] - cring_eat[3];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < PORTS*2; i = i + 1) begin
            dring_post[i] <= 8'd0;
            dring_take[i] <= 8'd0;
            cring_make[i] <= 8'd0;
            cring_eat [i] <= 8'd0;
        end
    end else begin
        if (dq_adv[0]) dring_post[{1'b0, dq_adv_q[0]}] <= dring_post[{1'b0, dq_adv_q[0]}] + 8'd1;
        if (dq_adv[1]) dring_post[{1'b1, dq_adv_q[1]}] <= dring_post[{1'b1, dq_adv_q[1]}] + 8'd1;
        if (dq_take[0]) dring_take[{1'b0, dq_resp_queue[0]}] <= dring_take[{1'b0, dq_resp_queue[0]}] + 8'd1;
        if (dq_take[1]) dring_take[{1'b1, dq_resp_queue[1]}] <= dring_take[{1'b1, dq_resp_queue[1]}] + 8'd1;
        if (cq_take[0]) cring_make[{1'b0, cq_resp_queue[0]}] <= cring_make[{1'b0, cq_resp_queue[0]}] + 8'd1;
        if (cq_take[1]) cring_make[{1'b1, cq_resp_queue[1]}] <= cring_make[{1'b1, cq_resp_queue[1]}] + 8'd1;
        if (cq_adv[0]) cring_eat[{1'b0, cq_adv_q[0]}] <= cring_eat[{1'b0, cq_adv_q[0]}] + 8'd1;
        if (cq_adv[1]) cring_eat[{1'b1, cq_adv_q[1]}] <= cring_eat[{1'b1, cq_adv_q[1]}] + 8'd1;
    end
end

// end-to-end counters
reg [9:0] n_req, n_status, n_fetched, n_delivered, n_cplreq, n_cplst, n_hostwr;

always @(posedge clk) begin
    if (rst) begin
        n_req <= 10'd0; n_status <= 10'd0; n_fetched <= 10'd0;
        n_delivered <= 10'd0; n_cplreq <= 10'd0; n_cplst <= 10'd0;
        n_hostwr <= 10'd0;
    end else begin
        if (df_req_fire && n_req     != SAT) n_req     <= n_req + 10'd1;
        if (df_st_valid && n_status  != SAT) n_status  <= n_status + 10'd1;
        if (df_st_ok    && n_fetched != SAT) n_fetched <= n_fetched + 10'd1;
        if (desc_beat && desc_tlast && n_delivered != SAT) n_delivered <= n_delivered + 10'd1;
        if (cw_req_fire && n_cplreq  != SAT) n_cplreq  <= n_cplreq + 10'd1;
        if (cw_st_valid && n_cplst   != SAT) n_cplst   <= n_cplst + 10'd1;
        if (host_valid  && n_hostwr  != SAT) n_hostwr  <= n_hostwr + 10'd1;
    end
end

wire [9:0] req_out = n_req - n_status;
wire [9:0] cpl_out = n_cplreq - n_cplst;

// per-tag population of live completion-write requests
reg [2:0] cw_tagcnt [0:15];
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 16; i = i + 1) cw_tagcnt[i] <= 3'd0;
    end else begin
        // Same tag in and out on one cycle is a net zero; different tags are
        // two updates to two different entries and BOTH have to happen.
        if (!(cw_req_fire && cw_st_valid && cw_req_tag == cw_st_tag)) begin
            if (cw_req_fire) cw_tagcnt[cw_req_tag] <= cw_tagcnt[cw_req_tag] + 3'd1;
            if (cw_st_valid) cw_tagcnt[cw_st_tag]  <= cw_tagcnt[cw_st_tag]  - 3'd1;
        end
    end
end

// ===================================================================== ==
// ORACLE 6 -- saturating wait counters.  A fairness, bounded-response or
// deadlock obligation is a bound on one of these; there is no liveness
// operator anywhere in this file.
// ===================================================================== ==
reg [9:0] ctr_dq0_blocked, ctr_dq1_blocked, ctr_desc_blocked;
reg [9:0] age_fetch, age_desc, age_cpl, ctr_stall, ctr_full;

wire any_event = df_req_fire || df_st_valid || rd_fire || rd_st_val
                 || desc_beat || cw_req_fire || cw_st_valid
                 || wr_fire || wr_st_val || host_valid
                 || (|dq_resp_fire) || (|(cq_resp_valid & cq_resp_ready));
wire any_work  = (req_out != 10'd0) || (cpl_out != 10'd0)
                 || (rd_out != 16'd0) || (wr_out != 16'd0) || !sq_empty;

always @(posedge clk) begin
    if (rst) begin
        ctr_dq0_blocked <= 10'd0; ctr_dq1_blocked <= 10'd0;
        ctr_desc_blocked <= 10'd0;
        age_fetch <= 10'd0; age_desc <= 10'd0; age_cpl <= 10'd0;
        ctr_stall <= 10'd0; ctr_full <= 10'd0;
    end else begin
        if (dq_resp_valid[0] && !dq_resp_ready[0])
            ctr_dq0_blocked <= (ctr_dq0_blocked == SAT) ? SAT : ctr_dq0_blocked + 10'd1;
        else ctr_dq0_blocked <= 10'd0;

        if (dq_resp_valid[1] && !dq_resp_ready[1])
            ctr_dq1_blocked <= (ctr_dq1_blocked == SAT) ? SAT : ctr_dq1_blocked + 10'd1;
        else ctr_dq1_blocked <= 10'd0;

        if (desc_tvalid && !desc_tready)
            ctr_desc_blocked <= (ctr_desc_blocked == SAT) ? SAT : ctr_desc_blocked + 10'd1;
        else ctr_desc_blocked <= 10'd0;

        if (df_st_valid || req_out == 10'd0) age_fetch <= 10'd0;
        else age_fetch <= (age_fetch == SAT) ? SAT : age_fetch + 10'd1;

        if ((desc_beat && desc_tlast) || sq_empty) age_desc <= 10'd0;
        else age_desc <= (age_desc == SAT) ? SAT : age_desc + 10'd1;

        if (cw_st_valid || cpl_out == 10'd0) age_cpl <= 10'd0;
        else age_cpl <= (age_cpl == SAT) ? SAT : age_cpl + 10'd1;

        if (any_event || !any_work) ctr_stall <= 10'd0;
        else ctr_stall <= (ctr_stall == SAT) ? SAT : ctr_stall + 10'd1;

        if (df_tbl_active == 4'hF)
            ctr_full <= (ctr_full == SAT) ? SAT : ctr_full + 10'd1;
        else ctr_full <= 10'd0;
    end
end

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

// ========================================================================
//                              T A R G E T S
// ========================================================================

// ---------------------------------------------- 1. end-to-end ordering ----
T_ORDER_DEQ_RESP_P0_TAG: assert property (@(posedge clk) disable iff (rst)
    dq_resp_valid[0] |-> (!dqq0_empty && dq_resp_tag[3:0] == dqq0_head_tag));

T_ORDER_DEQ_RESP_P1_TAG: assert property (@(posedge clk) disable iff (rst)
    dq_resp_valid[1] |-> (!dqq1_empty && dq_resp_tag[7:4] == dqq1_head_tag));


T_ORDER_DESC_TID_IS_OLDEST_FETCH: assert property (@(posedge clk) disable iff (rst)
    desc_tvalid |-> (!sq_empty && desc_tid == sq_head_tag));

T_ORDER_DESC_TID_STABLE_WITHIN_DESCRIPTOR: assert property (@(posedge clk) disable iff (rst)
    (desc_beat && !desc_tlast) |=> (desc_tvalid |-> desc_tid == $past(desc_tid)));

// --------------------------------------------------- 2. data integrity ----
T_DATA_DESC_WORD_MATCHES_HOST: assert property (@(posedge clk) disable iff (rst)
    desc_tvalid |-> (!fq_empty && desc_tdata == desc_expect));

T_DATA_DESC_TKEEP_FULL: assert property (@(posedge clk) disable iff (rst)
    desc_tvalid |-> desc_tkeep == 8'hFF);

T_DATA_DESC_DMA_ADDR_IN_RING: assert property (@(posedge clk) disable iff (rst)
    rd_valid |-> (desc_page_ok && desc_off_ok));

T_DATA_CPL_DMA_ADDR_IN_RING: assert property (@(posedge clk) disable iff (rst)
    wr_valid |-> (cpl_page_ok && cpl_off_ok));

T_DATA_CPL_PAYLOAD_TO_HOST: assert property (@(posedge clk) disable iff (rst)
    host_valid |-> host_data[62:0] == cs_data[hw_slot][62:0]);

// ------------------------------------------ 3. uniqueness / no duplicate --
T_UNIQ_DMA_READ_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    rd_fire |-> !rd_out[rd_tag]);

T_UNIQ_DMA_WRITE_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    wr_fire |-> !wr_out[wr_tag]);

T_UNIQ_DEQ_OP_TAG_NOT_REUSED_P0: assert property (@(posedge clk) disable iff (rst)
    dq_take[0] |-> !dq_ops[0][dq_resp_optag[1:0]]);

T_UNIQ_ENQ_OP_TAG_NOT_REUSED_P0: assert property (@(posedge clk) disable iff (rst)
    cq_take[0] |-> !cq_ops[0][cq_resp_optag[1:0]]);

// -------------------------------------------- 4. no loss / conservation ---
T_CONSERV_DEQ_NOT_MORE_THAN_POSTED: assert property (@(posedge clk) disable iff (rst)
    (dring_bal0 < 8'd128) && (dring_bal1 < 8'd128)
    && (dring_bal2 < 8'd128) && (dring_bal3 < 8'd128));

T_CONSERV_DESC_BEATS_MATCH_LEN: assert property (@(posedge clk) disable iff (rst)
    (desc_beat && desc_tlast) |->
        (!fq_empty && ({6'd0, beat_idx} + 8'd1) == (fq_head_len >> 3)));

T_CONSERV_DESC_DELIVERED_LE_FETCHED: assert property (@(posedge clk) disable iff (rst)
    n_delivered <= n_fetched);

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
T_BOUND_DESC_OUTSTANDING_LE_TABLE: assert property (@(posedge clk) disable iff (rst)
    req_out <= DESC_TABLE_SIZE);

T_BOUND_DMA_READ_OUTSTANDING_LE_TABLE: assert property (@(posedge clk) disable iff (rst)
    $countones(rd_out) <= DESC_TABLE_SIZE);

T_BOUND_DMA_WRITE_OUTSTANDING_LE_TABLE: assert property (@(posedge clk) disable iff (rst)
    $countones(wr_out) <= CPL_TABLE_SIZE);

T_BOUND_CPL_RING_OCCUPANCY: assert property (@(posedge clk) disable iff (rst)
    (cring_occ0 <= RING_SIZE) && (cring_occ1 <= RING_SIZE)
    && (cring_occ2 <= RING_SIZE) && (cring_occ3 <= RING_SIZE));

T_BOUND_DF_TABLE_PTR_SPAN: assert property (@(posedge clk) disable iff (rst)
    df_span <= DESC_TABLE_SIZE);



// ------------------------------------------------ 7. allocator discipline -
T_ALLOC_DEQ_COMMIT_NAMES_LIVE_OP_P0: assert property (@(posedge clk) disable iff (rst)
    dq_commit_fire[0] |-> dq_ops[0][dq_commit_optag[1:0]]);

T_ALLOC_ENQ_COMMIT_NAMES_LIVE_OP_P0: assert property (@(posedge clk) disable iff (rst)
    cq_commit_fire[0] |-> cq_ops[0][cq_commit_optag[1:0]]);

T_ALLOC_QM0_OPSET_SUBSET_OF_DESIGN: assert property (@(posedge clk) disable iff (rst)
    (dq_ops[0] & ~qm0_op_active) == 4'd0);

T_ALLOC_CPL_DMA_WRITE_SLOT_LIVE: assert property (@(posedge clk) disable iff (rst)
    wr_fire |-> cs_live[wr_ram[4:3]]);

// -------------------------------------- 8. request-response correspondence-
T_REQRSP_DMA_READ_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    rd_st_val |-> rd_out[rd_st_tag]);

T_REQRSP_DMA_WRITE_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    wr_st_val |-> wr_out[wr_st_tag]);

T_REQRSP_DESC_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    df_st_valid |-> req_out != 10'd0);

T_REQRSP_CPL_STATUS_TAG_LIVE: assert property (@(posedge clk) disable iff (rst)
    cw_st_valid |-> cw_tagcnt[cw_st_tag] != 3'd0);

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

// ------------------------------------------------ 10. arbitration fairness-
T_FAIR_DEQ_RESP_P0_ADMITTED_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    ctr_dq0_blocked <= N_BLOCK);

T_FAIR_DEQ_RESP_P1_ADMITTED_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    ctr_dq1_blocked <= N_BLOCK);

// ---------------------------------------------------- 11. bounded response-
T_BOUNDRSP_FETCH_STATUS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    age_fetch <= N_FETCH);

T_BOUNDRSP_DESC_DELIVERED_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    age_desc <= N_DESC);

T_BOUNDRSP_CPL_STATUS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    age_cpl <= N_CPL);

// ---------------------------------------------------- 12. deadlock freedom-
T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    ctr_stall <= N_STALL);

T_DEADLOCK_DF_TABLE_DRAINS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    ctr_full <= N_FULL);

// ------------------------------------------------ 13. reset/initialisation-
T_RESET_DF_TABLE_IDLE: assert property (@(posedge clk)
    (!rst && $past(rst)) |-> (df_tbl_active == 4'd0 && df_start_ptr == 3'd0
                              && df_fin_ptr == 3'd0 && df_active_cnt == 3'd0));

T_RESET_QM_OP_TABLES_IDLE: assert property (@(posedge clk)
    (!rst && $past(rst)) |-> (qm0_op_active == 4'd0 && qm1_op_active == 4'd0
                              && cqm0_op_active == 4'd0 && cqm1_op_active == 4'd0));

// ------------------------------------------ 14. lifecycle / access control-
T_LIFECYCLE_DQ0_BASE_STABLE_WHILE_ENABLED: assert property (@(posedge clk) disable iff (rst)
    (qm0_q0[55] && $past(qm0_q0[55])) |-> $stable(qm0_q0[127:76]));


T_LIFECYCLE_RINGS_STAY_ENABLED: assert property (@(posedge clk) disable iff (rst)
    configured |-> (qm0_q0[55] && qm0_q1[55] && cqm0_q0[55] && cqm0_q1[55]));

// ========================================================================
//                               C O V E R S
// ========================================================================

C_ORDER_TWO_FETCHES_IN_FLIGHT: cover property (@(posedge clk) disable iff (rst)
    req_out >= 10'd2);
C_ORDER_BOTH_PORTS_OUTSTANDING: cover property (@(posedge clk) disable iff (rst)
    !dqq0_empty && !dqq1_empty);

C_DATA_DESC_DELIVERED: cover property (@(posedge clk) disable iff (rst)
    desc_beat && desc_tlast);
C_DATA_DESC_SECOND_BEAT: cover property (@(posedge clk) disable iff (rst)
    desc_beat && beat_idx == 2'd1);
C_DATA_HOST_COMPLETION_WRITTEN: cover property (@(posedge clk) disable iff (rst)
    host_valid);

C_UNIQ_TWO_DMA_READS_OUTSTANDING: cover property (@(posedge clk) disable iff (rst)
    $countones(rd_out) >= 2);
C_UNIQ_TWO_DMA_WRITES_OUTSTANDING: cover property (@(posedge clk) disable iff (rst)
    $countones(wr_out) >= 2);

C_CONSERV_DESC_RING_FULL: cover property (@(posedge clk) disable iff (rst)
    dring_bal0 == 8'd4);
C_CONSERV_FOUR_DELIVERED: cover property (@(posedge clk) disable iff (rst)
    n_delivered >= 10'd4);

C_MUTEX_PORT1_DEQ_REQ: cover property (@(posedge clk) disable iff (rst)
    dq_req_valid[1]);
C_MUTEX_PORT1_ENQ_REQ: cover property (@(posedge clk) disable iff (rst)
    cq_req_valid[1]);

C_BOUND_DF_TABLE_FULL: cover property (@(posedge clk) disable iff (rst)
    df_tbl_active == 4'hF);
C_BOUND_CPL_RING_FULL: cover property (@(posedge clk) disable iff (rst)
    cring_occ0 == RING_SIZE);
C_BOUND_CPL_RING_REPORTED_FULL: cover property (@(posedge clk) disable iff (rst)
    |(cq_resp_valid & cq_resp_full));

C_ALLOC_TWO_QM0_OPS_LIVE: cover property (@(posedge clk) disable iff (rst)
    $countones(dq_ops[0]) >= 2);
C_ALLOC_DEQ_COMMIT: cover property (@(posedge clk) disable iff (rst)
    |dq_commit_fire);

C_REQRSP_EMPTY_RING_STATUS: cover property (@(posedge clk) disable iff (rst)
    df_st_valid && df_st_empty);
C_REQRSP_CPL_STATUS: cover property (@(posedge clk) disable iff (rst)
    cw_st_valid);

C_PROTO_DESC_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst)
    desc_tvalid && !desc_tready);
C_PROTO_DMA_READ_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst)
    rd_valid && !rd_ready);

C_FAIR_DQ1_BLOCKED_FOUR: cover property (@(posedge clk) disable iff (rst)
    ctr_dq1_blocked >= 10'd4);
C_BOUNDRSP_FETCH_AGE_TWENTY: cover property (@(posedge clk) disable iff (rst)
    age_fetch >= 10'd20);
C_DEADLOCK_STALL_EIGHT: cover property (@(posedge clk) disable iff (rst)
    ctr_stall >= 10'd8);

C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
    !rst && $past(rst));

C_LIFECYCLE_CONFIGURED: cover property (@(posedge clk) disable iff (rst)
    configured);

endmodule

bind corundum_dma_path_ft corundum_dma_targets corundum_dma_targets (
    .clk(clk), .rst(rst));

`resetall
