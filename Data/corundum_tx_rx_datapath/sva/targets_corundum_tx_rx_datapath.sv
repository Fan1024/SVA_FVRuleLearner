// ===========================================================================
// Candidate target assertions for Corundum's mqnic transmit AND receive
// datapath.
//
// Bound into `corundum_tx_rx_datapath_ft`, so every reference below is a
// hierarchical name from that top.  Nothing here is an assumption.
//
// THE ORACLES ARE INDEPENDENT of the design's own bookkeeping.  Six of them:
//
//   1. `host_word()` and `desc_word()`, RECOMPUTED here.  The checker never
//      reads a descriptor RAM, a packet RAM or a queue RAM.  Host memory is a
//      pure function of its own address --
//          host_word(a) = { a[31:0], ~a[31:0] }
//      -- so a 64-bit packet word carries its own address AND that address's
//      complement.  A packet word can therefore be checked at any of five
//      observation points with one register and no shadow copy of the packet,
//      which is what makes the far-end data candidates say something after
//      the bytes have crossed five separate buffers.
//   2. six shadow FIFOs, this file's own arrays and pointers: the dequeue
//      requests offered to each ring manager, the host addresses of started
//      descriptor fetches, the transmit and receive packet buffers a
//      descriptor named, and the packets in flight between the transmit
//      interface and the receive interface, per MAC port.
//   3. tag-keyed outstanding sets for the four DMA channels and the two
//      queue managers' operation tags -- set at the request, cleared at the
//      response.  That is what catches a reused tag or an unsolicited status.
//   4. a per-completion-ring slot counter.  The k-th completion of ring c
//      must be DMA-written to entry (k mod 4) of ring c; the checker counts
//      completions from the address it saw on the wire and predicts the next
//      address.  It never reads the queue manager's producer pointer.
//   5. frame counters at eleven boundaries -- transmit requests, descriptor
//      fetches, descriptor stream, transmit packet DMA, transmit interface,
//      each MAC port, receive interface, receive packet DMA, host words,
//      completion requests, completion host writes -- all this file's own
//      registers, all saturating.
//   6. eleven saturating wait timers.  Fairness, bounded response and
//      deadlock are bounds on those timers.  There is no `s_eventually`, no
//      `F` and no `G F` anywhere in this package -- every candidate is a
//      safety property.
//
// GEOMETRY THE CHECKER ASSUMES, and where it comes from.  These constants are
// the FORMAL TOP's, not the design's:
//   * transmit descriptor rings at 0x0001_0000 and 0x0001_1000, receive rings
//     at 0x0002_0000 / 0x0002_1000, completion rings at 0x0003_0000 /
//     0x0003_1000; 4 entries each, 16-byte descriptors, 32-byte completions;
//   * transmit packet buffers at 0x4xxx_xxxx, receive packet buffers at
//     0x8xxx_xxxx;
//   * a transmit descriptor asks for 8 or 16 payload bytes, alternating with
//     bit 4 of its own address; a receive descriptor offers 64 bytes.
// ===========================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module corundum_txrx_targets (input wire clk, input wire rst);

// ------------------------------------------------------------------ sizes
localparam DF_TABLE_SIZE = 4;    // desc_fetch in-flight fetches
localparam TX_TABLE_SIZE = 4;    // tx_engine  in-flight packets
localparam RX_TABLE_SIZE = 4;    // rx_engine  in-flight packets
localparam CW_TABLE_SIZE = 4;    // cpl_write  in-flight completions
localparam OP_TABLE_SIZE = 4;    // queue-manager operation table
localparam RING_SIZE     = 4;
localparam MAC_FIFO_BYTES = 128;

localparam FIFO_N  = 8;          // shadow queue depth
localparam FIFO_AW = 3;

localparam CSAT = 12'd4095;      // counter saturation
localparam TSAT = 12'd4095;      // timer saturation

// bounds for the saturating timers.  HAND-CHOSEN from counting handshakes
// along the chain, not measured -- see PROVENANCE.md, "What is expected to be
// wrong".
localparam N_BLOCK    = 12'd200;   // a request channel offered but not taken
localparam N_FETCH    = 12'd400;   // fetch accepted -> fetch status returned
localparam N_PKT      = 12'd1500;  // packet on the transmit interface -> its
                                   // bytes reach host memory
localparam N_TXCPL    = 12'd64;    // MAC frame end -> transmit completion taken
localparam N_PROGRESS = 12'd400;   // work outstanding -> some boundary event
localparam N_DFFULL   = 12'd400;   // desc_fetch table completely full

// ================================================================== taps ==

wire        configured = corundum_tx_rx_datapath_ft.all_configured;

// -- transmit request -------------------------------------------------------
wire        txreq_queue  = corundum_tx_rx_datapath_ft.tx_req_queue;
wire [2:0]  txreq_tag    = corundum_tx_rx_datapath_ft.tx_req_tag;
wire [4:0]  txreq_dest   = corundum_tx_rx_datapath_ft.tx_req_dest;
wire        txreq_valid  = corundum_tx_rx_datapath_ft.tx_req_valid;
wire        txreq_ready  = corundum_tx_rx_datapath_ft.tx_req_ready;
wire        txreq_fire   = txreq_valid && txreq_ready;
wire        txreq_st_valid = corundum_tx_rx_datapath_ft.tx_req_status_valid;

// -- descriptor requests into the shared arbiter ---------------------------
wire        tdr_valid = corundum_tx_rx_datapath_ft.tx_desc_req_valid;
wire        tdr_ready = corundum_tx_rx_datapath_ft.tx_desc_req_ready;
wire        rdr_valid = corundum_tx_rx_datapath_ft.rx_desc_req_valid;
wire        rdr_ready = corundum_tx_rx_datapath_ft.rx_desc_req_ready;

// -- desc_op_mux <-> desc_fetch --------------------------------------------
wire        df_req_sel   = corundum_tx_rx_datapath_ft.df_req_sel;
wire        df_req_queue = corundum_tx_rx_datapath_ft.df_req_queue;
wire [3:0]  df_req_tag   = corundum_tx_rx_datapath_ft.df_req_tag;
wire        df_req_valid = corundum_tx_rx_datapath_ft.df_req_valid;
wire        df_req_ready = corundum_tx_rx_datapath_ft.df_req_ready;
wire        df_req_fire  = df_req_valid && df_req_ready;

wire        df_st_empty  = corundum_tx_rx_datapath_ft.df_st_empty;
wire        df_st_error  = corundum_tx_rx_datapath_ft.df_st_error;
wire        df_st_valid  = corundum_tx_rx_datapath_ft.df_st_valid;
wire        df_st_ok     = df_st_valid && !df_st_empty && !df_st_error;

wire [127:0] df_desc_tdata  = corundum_tx_rx_datapath_ft.df_desc_tdata;
wire [15:0]  df_desc_tkeep  = corundum_tx_rx_datapath_ft.df_desc_tkeep;
wire         df_desc_tvalid = corundum_tx_rx_datapath_ft.df_desc_tvalid;
wire         df_desc_tready = corundum_tx_rx_datapath_ft.df_desc_tready;
wire         df_desc_tlast  = corundum_tx_rx_datapath_ft.df_desc_tlast;
wire [3:0]   df_desc_tid    = corundum_tx_rx_datapath_ft.df_desc_tid;
wire         df_desc_beat   = df_desc_tvalid && df_desc_tready;

// -- descriptor streams out of the arbiter, per flow -----------------------
wire [127:0] txd_tdata  = corundum_tx_rx_datapath_ft.tx_desc_tdata;
wire         txd_tvalid = corundum_tx_rx_datapath_ft.tx_desc_tvalid;
wire         txd_tready = corundum_tx_rx_datapath_ft.tx_desc_tready;
wire         txd_beat   = txd_tvalid && txd_tready;

wire [127:0] rxd_tdata  = corundum_tx_rx_datapath_ft.rx_desc_tdata;
wire         rxd_tvalid = corundum_tx_rx_datapath_ft.rx_desc_tvalid;
wire         rxd_tready = corundum_tx_rx_datapath_ft.rx_desc_tready;
wire         rxd_beat   = rxd_tvalid && rxd_tready;

// -- desc_fetch <-> the two descriptor ring managers -----------------------
wire [1:0]  dq_req_valid  = corundum_tx_rx_datapath_ft.dq_req_valid;
wire [1:0]  dq_req_ready  = corundum_tx_rx_datapath_ft.dq_req_ready;
wire [1:0]  dq_req_queue  = corundum_tx_rx_datapath_ft.dq_req_queue;
wire [7:0]  dq_req_tag    = corundum_tx_rx_datapath_ft.dq_req_tag;

wire [1:0]  dq_resp_valid = corundum_tx_rx_datapath_ft.dq_resp_valid;
wire [1:0]  dq_resp_ready = corundum_tx_rx_datapath_ft.dq_resp_ready;
wire [1:0]  dq_resp_queue = corundum_tx_rx_datapath_ft.dq_resp_queue;
wire [7:0]  dq_resp_tag   = corundum_tx_rx_datapath_ft.dq_resp_tag;
wire [3:0]  dq_resp_optag = corundum_tx_rx_datapath_ft.dq_resp_op_tag;
wire [1:0]  dq_resp_empty = corundum_tx_rx_datapath_ft.dq_resp_empty;
wire [1:0]  dq_resp_error = corundum_tx_rx_datapath_ft.dq_resp_error;

wire [3:0]  dq_commit_optag = corundum_tx_rx_datapath_ft.dq_commit_op_tag;
wire [1:0]  dq_commit_valid = corundum_tx_rx_datapath_ft.dq_commit_valid;
wire [1:0]  dq_commit_ready = corundum_tx_rx_datapath_ft.dq_commit_ready;

// -- DMA channel A: descriptor fetch ---------------------------------------
wire [63:0] dh_addr  = corundum_tx_rx_datapath_ft.dh_desc_dma_addr;
wire [15:0] dh_len   = corundum_tx_rx_datapath_ft.dh_desc_len;
wire [3:0]  dh_tag   = corundum_tx_rx_datapath_ft.dh_desc_tag;
wire        dh_valid = corundum_tx_rx_datapath_ft.dh_desc_valid;
wire        dh_ready = corundum_tx_rx_datapath_ft.dh_desc_ready;
wire        dh_fire  = dh_valid && dh_ready;
wire [3:0]  dh_st_tag   = corundum_tx_rx_datapath_ft.dh_status_tag;
wire        dh_st_valid = corundum_tx_rx_datapath_ft.dh_status_valid;

// -- DMA channel B: transmit packet read -----------------------------------
wire [63:0] th_addr  = corundum_tx_rx_datapath_ft.th_desc_dma_addr;
wire [15:0] th_len   = corundum_tx_rx_datapath_ft.th_desc_len;
wire [3:0]  th_tag   = corundum_tx_rx_datapath_ft.th_desc_tag;
wire        th_valid = corundum_tx_rx_datapath_ft.th_desc_valid;
wire        th_ready = corundum_tx_rx_datapath_ft.th_desc_ready;
wire        th_fire  = th_valid && th_ready;
wire [3:0]  th_st_tag   = corundum_tx_rx_datapath_ft.th_status_tag;
wire        th_st_valid = corundum_tx_rx_datapath_ft.th_status_valid;

// -- DMA channel C: receive packet write -----------------------------------
wire [63:0] rh_addr  = corundum_tx_rx_datapath_ft.rh_desc_dma_addr;
wire [15:0] rh_len   = corundum_tx_rx_datapath_ft.rh_desc_len;
wire [3:0]  rh_tag   = corundum_tx_rx_datapath_ft.rh_desc_tag;
wire        rh_valid = corundum_tx_rx_datapath_ft.rh_desc_valid;
wire        rh_ready = corundum_tx_rx_datapath_ft.rh_desc_ready;
wire        rh_fire  = rh_valid && rh_ready;
wire [3:0]  rh_st_tag   = corundum_tx_rx_datapath_ft.rh_status_tag;
wire        rh_st_valid = corundum_tx_rx_datapath_ft.rh_status_valid;

wire        rxhw_valid = corundum_tx_rx_datapath_ft.rx_host_wr_valid;
wire [63:0] rxhw_addr  = corundum_tx_rx_datapath_ft.rx_host_wr_addr;
wire [63:0] rxhw_data  = corundum_tx_rx_datapath_ft.rx_host_wr_data;

// -- DMA channel D: completion writeback -----------------------------------
wire [63:0] ch_addr  = corundum_tx_rx_datapath_ft.ch_desc_dma_addr;
wire [15:0] ch_len   = corundum_tx_rx_datapath_ft.ch_desc_len;
wire [3:0]  ch_tag   = corundum_tx_rx_datapath_ft.ch_desc_tag;
wire        ch_valid = corundum_tx_rx_datapath_ft.ch_desc_valid;
wire        ch_ready = corundum_tx_rx_datapath_ft.ch_desc_ready;
wire        ch_fire  = ch_valid && ch_ready;
wire [3:0]  ch_st_tag   = corundum_tx_rx_datapath_ft.ch_status_tag;
wire        ch_st_valid = corundum_tx_rx_datapath_ft.ch_status_valid;

wire         cplhw_valid = corundum_tx_rx_datapath_ft.cpl_host_wr_valid;
wire [63:0]  cplhw_addr  = corundum_tx_rx_datapath_ft.cpl_host_wr_addr;
wire [255:0] cplhw_data  = corundum_tx_rx_datapath_ft.cpl_host_wr_data;

// -- packet streams ---------------------------------------------------------
wire [63:0] iftx_tdata  = corundum_tx_rx_datapath_ft.if_tx_tdata;
wire [7:0]  iftx_tkeep  = corundum_tx_rx_datapath_ft.if_tx_tkeep;
wire        iftx_tvalid = corundum_tx_rx_datapath_ft.if_tx_tvalid;
wire        iftx_tready = corundum_tx_rx_datapath_ft.if_tx_tready;
wire        iftx_tlast  = corundum_tx_rx_datapath_ft.if_tx_tlast;
wire [4:0]  iftx_tdest  = corundum_tx_rx_datapath_ft.if_tx_tdest;
wire [3:0]  iftx_tuser  = corundum_tx_rx_datapath_ft.if_tx_tuser;
wire        iftx_beat   = iftx_tvalid && iftx_tready;
wire        iftx_port   = iftx_tdest[4];

wire [63:0] mactx_tdata  = corundum_tx_rx_datapath_ft.mac_tx_tdata;
wire [1:0]  mactx_tvalid = corundum_tx_rx_datapath_ft.mac_tx_tvalid;
wire [1:0]  mactx_tready = corundum_tx_rx_datapath_ft.mac_tx_tready;
wire [1:0]  mactx_tlast  = corundum_tx_rx_datapath_ft.mac_tx_tlast;
wire [7:0]  mactx_tuser  = corundum_tx_rx_datapath_ft.mac_tx_tuser;

wire [63:0] ifrx_tdata  = corundum_tx_rx_datapath_ft.if_rx_tdata;
wire        ifrx_tvalid = corundum_tx_rx_datapath_ft.if_rx_tvalid;
wire        ifrx_tready = corundum_tx_rx_datapath_ft.if_rx_tready;
wire        ifrx_tlast  = corundum_tx_rx_datapath_ft.if_rx_tlast;
wire        ifrx_tid    = corundum_tx_rx_datapath_ft.if_rx_tid;
wire        ifrx_beat   = ifrx_tvalid && ifrx_tready;

wire [15:0] txfifo_depth0 = corundum_tx_rx_datapath_ft.tx_fifo_status_depth[7:0];
wire [15:0] txfifo_depth1 = corundum_tx_rx_datapath_ft.tx_fifo_status_depth[15:8];
wire [15:0] rxfifo_depth0 = corundum_tx_rx_datapath_ft.rx_fifo_status_depth[7:0];
wire [15:0] rxfifo_depth1 = corundum_tx_rx_datapath_ft.rx_fifo_status_depth[15:8];

// -- transmit completion (the MAC's return path) ---------------------------
wire [2:0]  txcpl_tag   = corundum_tx_rx_datapath_ft.tx_cpl_tag;
wire        txcpl_valid = corundum_tx_rx_datapath_ft.tx_cpl_valid;
wire        txcpl_ready = corundum_tx_rx_datapath_ft.tx_cpl_ready;
wire [1:0]  maccpl_valid = corundum_tx_rx_datapath_ft.mac_cpl_valid;
wire [1:0]  maccpl_ready = corundum_tx_rx_datapath_ft.mac_cpl_ready;

// -- completion requests ----------------------------------------------------
wire        tcr_valid = corundum_tx_rx_datapath_ft.tx_cpl_req_valid;
wire        tcr_ready = corundum_tx_rx_datapath_ft.tx_cpl_req_ready;
wire        rcr_valid = corundum_tx_rx_datapath_ft.rx_cpl_req_valid;
wire        rcr_ready = corundum_tx_rx_datapath_ft.rx_cpl_req_ready;

wire        cw_req_queue = corundum_tx_rx_datapath_ft.cw_req_queue;
wire [3:0]  cw_req_tag   = corundum_tx_rx_datapath_ft.cw_req_tag;
wire        cw_req_valid = corundum_tx_rx_datapath_ft.cw_req_valid;
wire        cw_req_ready = corundum_tx_rx_datapath_ft.cw_req_ready;
wire        cw_req_fire  = cw_req_valid && cw_req_ready;

// -- cpl_write <-> the completion ring manager -----------------------------
wire        cq_req_valid  = corundum_tx_rx_datapath_ft.cq_enq_req_valid;
wire        cq_req_ready  = corundum_tx_rx_datapath_ft.cq_enq_req_ready;
wire        cq_resp_valid = corundum_tx_rx_datapath_ft.cq_enq_resp_valid;
wire        cq_resp_ready = corundum_tx_rx_datapath_ft.cq_enq_resp_ready;
wire        cq_resp_queue = corundum_tx_rx_datapath_ft.cq_enq_resp_queue;
wire [1:0]  cq_resp_optag = corundum_tx_rx_datapath_ft.cq_enq_resp_op_tag;
wire        cq_resp_full  = corundum_tx_rx_datapath_ft.cq_enq_resp_full;
wire        cq_resp_error = corundum_tx_rx_datapath_ft.cq_enq_resp_error;
wire [1:0]  cq_commit_optag = corundum_tx_rx_datapath_ft.cq_enq_commit_op_tag;
wire        cq_commit_valid = corundum_tx_rx_datapath_ft.cq_enq_commit_valid;
wire        cq_commit_ready = corundum_tx_rx_datapath_ft.cq_enq_commit_ready;

// -- a few design-internal taps, for the occupancy and reset candidates -----
wire [2:0]  df_active_count = corundum_tx_rx_datapath_ft.desc_fetch_inst.active_count_reg;
wire [2:0]  df_start_ptr    = corundum_tx_rx_datapath_ft.desc_fetch_inst.desc_table_start_ptr_reg;
wire [2:0]  df_finish_ptr   = corundum_tx_rx_datapath_ft.desc_fetch_inst.desc_table_finish_ptr_reg;
wire [3:0]  df_table_active = corundum_tx_rx_datapath_ft.desc_fetch_inst.desc_table_active;
wire [3:0]  txe_table_active =
    corundum_tx_rx_datapath_ft.interface_tx_inst.tx_engine_inst.desc_table_active;
wire [3:0]  rxe_table_active =
    corundum_tx_rx_datapath_ft.interface_rx_inst.rx_engine_inst.desc_table_active;
wire [3:0]  cw_table_active = corundum_tx_rx_datapath_ft.cpl_write_inst.desc_table_active;
wire [3:0]  txqm_op_active  = corundum_tx_rx_datapath_ft.tx_qm_inst.op_table_active;
wire [3:0]  cqm_op_active   = corundum_tx_rx_datapath_ft.cq_manager_inst.op_table_active;

// ============================================================== functions ==
// Host memory is a pure function of its own address.  RECOMPUTED here; the
// checker never reads a RAM.

function automatic [63:0] host_word(input [63:0] a);
    host_word = {a[31:0], ~a[31:0]};
endfunction

// The transmit packet buffer a transmit descriptor at host address `a` names.
function automatic [31:0] tx_pbuf(input [63:0] a);
    tx_pbuf = 32'h4000_0000 | ({16'd0, a[15:0]} << 8);
endfunction

// The receive packet buffer a receive descriptor at host address `a` names.
function automatic [31:0] rx_pbuf(input [63:0] a);
    rx_pbuf = 32'h8000_0000 | ({16'd0, a[15:0]} << 8);
endfunction

// The whole 16-byte descriptor at host address `a`.
function automatic [127:0] desc_word(input [63:0] a);
    reg [31:0] len;
    reg [63:0] pbuf;
    begin
        if (a[17]) begin
            len  = 32'd64;
            pbuf = {32'h0000_0000, rx_pbuf(a)};
        end else begin
            len  = a[4] ? 32'd16 : 32'd8;
            pbuf = {32'h0000_0000, tx_pbuf(a)};
        end
        desc_word = {pbuf, len, 32'h0000_0000};
    end
endfunction

function automatic [11:0] sat_inc(input [11:0] v);
    sat_inc = (v == CSAT) ? CSAT : v + 12'd1;
endfunction

// ================================================================ oracle ===

integer i;

// -- 1. dequeue request shadow queues, one per ring manager ----------------
reg [4:0]        dqq_mem   [0:1][0:FIFO_N-1];   // {queue, tag}
reg [FIFO_AW:0]  dqq_wr    [0:1];
reg [FIFO_AW:0]  dqq_rd    [0:1];
reg              dqq_bad   [0:1];               // a pop with nothing pushed

// -- 2. started descriptor fetches: the host address of each --------------
reg [63:0]       dfq_mem [0:FIFO_N-1];
reg [FIFO_AW:0]  dfq_wr;
reg [FIFO_AW:0]  dfq_rd;
reg              dfq_bad;

// -- 3. transmit packet buffers a descriptor named ------------------------
reg [31:0]       tbq_addr [0:FIFO_N-1];
reg [15:0]       tbq_len  [0:FIFO_N-1];
reg [FIFO_AW:0]  tbq_wr;
reg [FIFO_AW:0]  tbq_rd;
reg              tbq_bad;

// -- 4. receive packet buffers a descriptor named -------------------------
reg [31:0]       rbq_addr [0:FIFO_N-1];
reg [FIFO_AW:0]  rbq_wr;
reg [FIFO_AW:0]  rbq_rd;
reg              rbq_bad;

// -- 5. packets in flight from the transmit interface to the receive
//       interface, per MAC port -------------------------------------------
reg [31:0]       tpq_mem [0:1][0:FIFO_N-1];
reg [FIFO_AW:0]  tpq_wr  [0:1];
reg [FIFO_AW:0]  tpq_rd  [0:1];
reg              tpq_bad [0:1];

// -- 6. packets in flight from the receive interface to host memory -------
reg [31:0]       rpq_mem [0:FIFO_N-1];
reg [FIFO_AW:0]  rpq_wr;
reg [FIFO_AW:0]  rpq_rd;
reg              rpq_bad;

// -- outstanding tag sets -------------------------------------------------
reg [15:0] dh_out;      // descriptor-fetch DMA read tags
reg [15:0] th_out;      // transmit packet DMA read tags
reg [15:0] rh_out;      // receive packet DMA write tags
reg [15:0] ch_out;      // completion DMA write tags
reg [3:0]  dqop_out [0:1];   // ring-manager operation tags
reg [3:0]  cqop_out;         // completion-manager operation tags

reg dh_reuse, th_reuse, rh_reuse, ch_reuse;
reg dh_unsol, th_unsol, rh_unsol, ch_unsol;
reg dqop_reuse, cqop_reuse;
reg dq_commit_stale, cq_commit_stale;

// -- packet-word tracking -------------------------------------------------
reg        iftx_in_frame;
reg [31:0] iftx_prev_addr;
reg        iftx_word_bad;      // a transmit beat that is not a host word
reg        iftx_step_bad;      // a transmit beat 8 bytes out of step

reg [1:0]  mac_odd;            // which half of a 64-bit word comes next
reg [31:0] mac_prev [0:1];
reg [1:0]  mac_pair_bad;

reg        ifrx_in_frame;
reg        ifrx_word_bad;
reg [1:0]  ifrx_order_bad;

reg        rxhw_first;
reg [31:0] rxhw_prev_addr;
reg        rxhw_word_bad;
reg        rxhw_step_bad;
reg        rxhw_region_bad;
reg        rxhw_order_bad;

// -- descriptor / DMA correspondence flags --------------------------------
reg        desc_data_bad;      // the streamed descriptor is not desc_word()
reg        desc_order_bad;     // the streamed descriptor is not the oldest fetch
reg        txdma_addr_bad;     // the packet read is not the buffer the descriptor named
reg        txdma_len_bad;
reg        rxdma_addr_bad;
reg [1:0]  dq_order_bad;       // a dequeue response out of request order

// -- completion accounting -------------------------------------------------
reg [11:0] cq_slot   [0:1];    // completions written to each ring so far
reg        cpl_slot_bad;
reg        cpl_len_bad;
reg        cpl_queue_bad;

// -- boundary counters ------------------------------------------------------
reg [11:0] n_txreq, n_txreq_st;
reg [11:0] n_dfreq, n_dfst_ok;
reg [11:0] n_desc_stream;
reg [11:0] n_thdma;
reg [11:0] n_iftx_pkt;
reg [11:0] n_ifrx_pkt;
reg [11:0] n_rh_dma;
reg [11:0] n_rxhw_word;
reg [11:0] n_rxhw_pkt;
reg [11:0] n_cw_req;
reg [11:0] n_ch_dma;
reg [11:0] n_cplhw;

// -- saturating wait timers -------------------------------------------------
reg [11:0] t_txreq_block;
reg [11:0] t_tdr_block;
reg [11:0] t_rdr_block;
reg [11:0] t_tcr_block;
reg [11:0] t_rcr_block;
reg [11:0] t_fetch;
reg [11:0] t_pkt;
reg [11:0] t_txcpl0, t_txcpl1;
reg [11:0] t_progress;
reg [11:0] t_dffull;

// convenience
wire        dq_fire0 = dq_req_valid[0] && dq_req_ready[0];
wire        dq_fire1 = dq_req_valid[1] && dq_req_ready[1];
wire        dq_rfire0 = dq_resp_valid[0] && dq_resp_ready[0];
wire        dq_rfire1 = dq_resp_valid[1] && dq_resp_ready[1];
wire        dq_rok0  = dq_rfire0 && !dq_resp_empty[0] && !dq_resp_error[0];
wire        dq_rok1  = dq_rfire1 && !dq_resp_empty[1] && !dq_resp_error[1];
wire        cq_rfire = cq_resp_valid && cq_resp_ready;
wire        cq_rok   = cq_rfire && !cq_resp_full && !cq_resp_error;

wire        iftx_first = iftx_beat && !iftx_in_frame;
wire        ifrx_first = ifrx_beat && !ifrx_in_frame;

wire [FIFO_AW:0] tpq_occ0 = tpq_wr[0] - tpq_rd[0];
wire [FIFO_AW:0] tpq_occ1 = tpq_wr[1] - tpq_rd[1];
wire [FIFO_AW:0] rpq_occ  = rpq_wr - rpq_rd;
wire [FIFO_AW:0] dfq_occ  = dfq_wr - dfq_rd;

wire any_work = (n_txreq != n_txreq_st) || (n_iftx_pkt != n_rxhw_pkt)
                || (n_cw_req != n_cplhw);
wire any_event = txreq_fire || txreq_st_valid || df_req_fire || df_st_valid
                 || df_desc_beat || dh_fire || dh_st_valid || th_fire
                 || th_st_valid || iftx_beat || ifrx_beat || rh_fire
                 || rh_st_valid || rxhw_valid || cw_req_fire || ch_fire
                 || ch_st_valid || cplhw_valid || txcpl_valid;

integer j;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 2; i = i + 1) begin
            dqq_wr[i] <= 0; dqq_rd[i] <= 0; dqq_bad[i] <= 1'b0;
            tpq_wr[i] <= 0; tpq_rd[i] <= 0; tpq_bad[i] <= 1'b0;
            dqop_out[i] <= 4'd0;
            mac_prev[i] <= 32'd0;
            cq_slot[i]  <= 12'd0;
        end
        dfq_wr <= 0; dfq_rd <= 0; dfq_bad <= 1'b0;
        tbq_wr <= 0; tbq_rd <= 0; tbq_bad <= 1'b0;
        rbq_wr <= 0; rbq_rd <= 0; rbq_bad <= 1'b0;
        rpq_wr <= 0; rpq_rd <= 0; rpq_bad <= 1'b0;

        dh_out <= 16'd0; th_out <= 16'd0; rh_out <= 16'd0; ch_out <= 16'd0;
        cqop_out <= 4'd0;
        dh_reuse <= 1'b0; th_reuse <= 1'b0; rh_reuse <= 1'b0; ch_reuse <= 1'b0;
        dh_unsol <= 1'b0; th_unsol <= 1'b0; rh_unsol <= 1'b0; ch_unsol <= 1'b0;
        dqop_reuse <= 1'b0; cqop_reuse <= 1'b0;
        dq_commit_stale <= 1'b0; cq_commit_stale <= 1'b0;

        iftx_in_frame <= 1'b0; iftx_prev_addr <= 32'd0;
        iftx_word_bad <= 1'b0; iftx_step_bad <= 1'b0;
        mac_odd <= 2'b00; mac_pair_bad <= 2'b00;
        ifrx_in_frame <= 1'b0; ifrx_word_bad <= 1'b0; ifrx_order_bad <= 2'b00;
        rxhw_first <= 1'b1; rxhw_prev_addr <= 32'd0;
        rxhw_word_bad <= 1'b0; rxhw_step_bad <= 1'b0;
        rxhw_region_bad <= 1'b0; rxhw_order_bad <= 1'b0;

        desc_data_bad <= 1'b0; desc_order_bad <= 1'b0;
        txdma_addr_bad <= 1'b0; txdma_len_bad <= 1'b0; rxdma_addr_bad <= 1'b0;
        dq_order_bad <= 2'b00;
        cpl_slot_bad <= 1'b0; cpl_len_bad <= 1'b0; cpl_queue_bad <= 1'b0;

        n_txreq <= 0; n_txreq_st <= 0; n_dfreq <= 0; n_dfst_ok <= 0;
        n_desc_stream <= 0; n_thdma <= 0; n_iftx_pkt <= 0; n_ifrx_pkt <= 0;
        n_rh_dma <= 0; n_rxhw_word <= 0; n_rxhw_pkt <= 0;
        n_cw_req <= 0; n_ch_dma <= 0; n_cplhw <= 0;

        t_txreq_block <= 0; t_tdr_block <= 0; t_rdr_block <= 0;
        t_tcr_block <= 0; t_rcr_block <= 0;
        t_fetch <= 0; t_pkt <= 0; t_txcpl0 <= 0; t_txcpl1 <= 0;
        t_progress <= 0; t_dffull <= 0;
    end else begin
        // ---------------------------------------------- dequeue shadow ----
        if (dq_fire0) begin
            dqq_mem[0][dqq_wr[0][FIFO_AW-1:0]] <= {dq_req_queue[0], dq_req_tag[3:0]};
            dqq_wr[0] <= dqq_wr[0] + 1'b1;
        end
        if (dq_rfire0) begin
            if (dqq_wr[0] == dqq_rd[0]) dqq_bad[0] <= 1'b1;
            else begin
                dqq_rd[0] <= dqq_rd[0] + 1'b1;
                if (dqq_mem[0][dqq_rd[0][FIFO_AW-1:0]]
                    != {dq_resp_queue[0], dq_resp_tag[3:0]}) dq_order_bad[0] <= 1'b1;
            end
        end
        if (dq_fire1) begin
            dqq_mem[1][dqq_wr[1][FIFO_AW-1:0]] <= {dq_req_queue[1], dq_req_tag[7:4]};
            dqq_wr[1] <= dqq_wr[1] + 1'b1;
        end
        if (dq_rfire1) begin
            if (dqq_wr[1] == dqq_rd[1]) dqq_bad[1] <= 1'b1;
            else begin
                dqq_rd[1] <= dqq_rd[1] + 1'b1;
                if (dqq_mem[1][dqq_rd[1][FIFO_AW-1:0]]
                    != {dq_resp_queue[1], dq_resp_tag[7:4]}) dq_order_bad[1] <= 1'b1;
            end
        end

        // ------------------------------------- started descriptor fetches --
        if (dh_fire) begin
            dfq_mem[dfq_wr[FIFO_AW-1:0]] <= dh_addr;
            dfq_wr <= dfq_wr + 1'b1;
        end
        if (df_desc_beat && df_desc_tlast) begin
            if (dfq_wr == dfq_rd) dfq_bad <= 1'b1;
            else begin
                dfq_rd <= dfq_rd + 1'b1;
                if (df_desc_tdata != desc_word(dfq_mem[dfq_rd[FIFO_AW-1:0]]))
                    desc_data_bad <= 1'b1;
                if (df_desc_tdata[127:64] !=
                    {32'h0000_0000, dfq_mem[dfq_rd[FIFO_AW-1:0]][17]
                                    ? rx_pbuf(dfq_mem[dfq_rd[FIFO_AW-1:0]])
                                    : tx_pbuf(dfq_mem[dfq_rd[FIFO_AW-1:0]])})
                    desc_order_bad <= 1'b1;
            end
        end

        // ------------------- the transmit buffer a descriptor named --------
        if (txd_beat) begin
            tbq_addr[tbq_wr[FIFO_AW-1:0]] <= txd_tdata[95:64];
            tbq_len [tbq_wr[FIFO_AW-1:0]] <= txd_tdata[47:32];
            tbq_wr <= tbq_wr + 1'b1;
        end
        if (th_fire) begin
            if (tbq_wr == tbq_rd) tbq_bad <= 1'b1;
            else begin
                tbq_rd <= tbq_rd + 1'b1;
                if (th_addr[31:0] != tbq_addr[tbq_rd[FIFO_AW-1:0]])
                    txdma_addr_bad <= 1'b1;
                if (th_len != tbq_len[tbq_rd[FIFO_AW-1:0]])
                    txdma_len_bad <= 1'b1;
            end
        end

        // -------------------- the receive buffer a descriptor named --------
        if (rxd_beat) begin
            rbq_addr[rbq_wr[FIFO_AW-1:0]] <= rxd_tdata[95:64];
            rbq_wr <= rbq_wr + 1'b1;
        end
        if (rh_fire) begin
            if (rbq_wr == rbq_rd) rbq_bad <= 1'b1;
            else begin
                rbq_rd <= rbq_rd + 1'b1;
                if (rh_addr[31:0] != rbq_addr[rbq_rd[FIFO_AW-1:0]])
                    rxdma_addr_bad <= 1'b1;
            end
        end

        // ------------------------------------------- transmit interface ----
        if (iftx_beat) begin
            iftx_in_frame  <= !iftx_tlast;
            iftx_prev_addr <= iftx_tdata[63:32];
            if (iftx_tdata[63:32] != ~iftx_tdata[31:0]) iftx_word_bad <= 1'b1;
            if (iftx_in_frame
                && iftx_tdata[63:32] != iftx_prev_addr + 32'd8)
                iftx_step_bad <= 1'b1;
            if (iftx_tlast) n_iftx_pkt <= sat_inc(n_iftx_pkt);
            if (!iftx_in_frame) begin
                tpq_mem[iftx_port][tpq_wr[iftx_port][FIFO_AW-1:0]]
                    <= iftx_tdata[63:32];
                tpq_wr[iftx_port] <= tpq_wr[iftx_port] + 1'b1;
            end
        end

        // ------------------------------------------------- the MAC links ---
        for (j = 0; j < 2; j = j + 1) begin
            if (mactx_tvalid[j] && mactx_tready[j]) begin
                mac_prev[j] <= mactx_tdata[j*32 +: 32];
                if (mac_odd[j] && mactx_tdata[j*32 +: 32] != ~mac_prev[j])
                    mac_pair_bad[j] <= 1'b1;
                mac_odd[j] <= mactx_tlast[j] ? 1'b0 : ~mac_odd[j];
            end
        end

        // -------------------------------------------- receive interface ----
        if (ifrx_beat) begin
            ifrx_in_frame <= !ifrx_tlast;
            if (ifrx_tdata[63:32] != ~ifrx_tdata[31:0]) ifrx_word_bad <= 1'b1;
            if (ifrx_tlast) n_ifrx_pkt <= sat_inc(n_ifrx_pkt);
            if (!ifrx_in_frame) begin
                // pop the transmit-side shadow for this MAC port
                if (tpq_wr[ifrx_tid] == tpq_rd[ifrx_tid]) tpq_bad[ifrx_tid] <= 1'b1;
                else begin
                    tpq_rd[ifrx_tid] <= tpq_rd[ifrx_tid] + 1'b1;
                    if (tpq_mem[ifrx_tid][tpq_rd[ifrx_tid][FIFO_AW-1:0]]
                        != ifrx_tdata[63:32]) ifrx_order_bad[ifrx_tid] <= 1'b1;
                end
                // and push for the host side
                rpq_mem[rpq_wr[FIFO_AW-1:0]] <= ifrx_tdata[63:32];
                rpq_wr <= rpq_wr + 1'b1;
            end
        end

        // --------------------------------------- the far end of the packet -
        if (rxhw_valid) begin
            n_rxhw_word <= sat_inc(n_rxhw_word);
            rxhw_first <= 1'b0;
            rxhw_prev_addr <= rxhw_data[63:32];
            if (rxhw_data[63:32] != ~rxhw_data[31:0]) rxhw_word_bad <= 1'b1;
            if (rxhw_data[63:62] != 2'b01) rxhw_region_bad <= 1'b1;
            if (rxhw_addr[63:32] != 32'd0 || rxhw_addr[31:30] != 2'b10)
                rxhw_region_bad <= 1'b1;
            if (!rxhw_first && rxhw_data[63:32] != rxhw_prev_addr + 32'd8)
                rxhw_step_bad <= 1'b1;
            if (rxhw_first) begin
                n_rxhw_pkt <= sat_inc(n_rxhw_pkt);
                if (rpq_wr == rpq_rd) rpq_bad <= 1'b1;
                else begin
                    rpq_rd <= rpq_rd + 1'b1;
                    if (rpq_mem[rpq_rd[FIFO_AW-1:0]] != rxhw_data[63:32])
                        rxhw_order_bad <= 1'b1;
                end
            end
        end
        // a new receive DMA burst re-arms the first-word marker.  Placed
        // AFTER the publish block so a burst start always wins.
        if (rh_fire) begin
            rxhw_first <= 1'b1;
            n_rh_dma <= sat_inc(n_rh_dma);
        end

        // ------------------------------------------------- DMA tag sets ----
        if (dh_fire) begin
            if (dh_out[dh_tag]) dh_reuse <= 1'b1;
            dh_out[dh_tag] <= 1'b1;
        end
        if (dh_st_valid) begin
            if (!dh_out[dh_st_tag] && !(dh_fire && dh_tag == dh_st_tag))
                dh_unsol <= 1'b1;
            if (!(dh_fire && dh_tag == dh_st_tag)) dh_out[dh_st_tag] <= 1'b0;
        end
        if (th_fire) begin
            if (th_out[th_tag]) th_reuse <= 1'b1;
            th_out[th_tag] <= 1'b1;
            n_thdma <= sat_inc(n_thdma);
        end
        if (th_st_valid) begin
            if (!th_out[th_st_tag] && !(th_fire && th_tag == th_st_tag))
                th_unsol <= 1'b1;
            if (!(th_fire && th_tag == th_st_tag)) th_out[th_st_tag] <= 1'b0;
        end
        if (rh_fire) begin
            if (rh_out[rh_tag]) rh_reuse <= 1'b1;
            rh_out[rh_tag] <= 1'b1;
        end
        if (rh_st_valid) begin
            if (!rh_out[rh_st_tag] && !(rh_fire && rh_tag == rh_st_tag))
                rh_unsol <= 1'b1;
            if (!(rh_fire && rh_tag == rh_st_tag)) rh_out[rh_st_tag] <= 1'b0;
        end
        if (ch_fire) begin
            if (ch_out[ch_tag]) ch_reuse <= 1'b1;
            ch_out[ch_tag] <= 1'b1;
            n_ch_dma <= sat_inc(n_ch_dma);
            // the k-th completion of ring c lands in entry (k mod 4)
            if (ch_addr[63:32] != 32'd0 || ch_addr[31:13] != 19'd24
                || ch_addr[11:7] != 5'd0 || ch_addr[4:0] != 5'd0
                || ch_addr[6:5] != cq_slot[ch_addr[12]][1:0])
                cpl_slot_bad <= 1'b1;
            cq_slot[ch_addr[12]] <= cq_slot[ch_addr[12]] + 12'd1;
        end
        if (ch_st_valid) begin
            if (!ch_out[ch_st_tag] && !(ch_fire && ch_tag == ch_st_tag))
                ch_unsol <= 1'b1;
            if (!(ch_fire && ch_tag == ch_st_tag)) ch_out[ch_st_tag] <= 1'b0;
        end

        // ------------------------------------ ring-manager operation tags --
        if (dq_rok0) begin
            if (dqop_out[0][dq_resp_optag[1:0]]) dqop_reuse <= 1'b1;
            dqop_out[0][dq_resp_optag[1:0]] <= 1'b1;
        end
        if (dq_commit_valid[0] && dq_commit_ready[0]) begin
            if (!dqop_out[0][dq_commit_optag[1:0]]) dq_commit_stale <= 1'b1;
            dqop_out[0][dq_commit_optag[1:0]] <= 1'b0;
        end
        if (dq_rok1) begin
            if (dqop_out[1][dq_resp_optag[3:2]]) dqop_reuse <= 1'b1;
            dqop_out[1][dq_resp_optag[3:2]] <= 1'b1;
        end
        if (dq_commit_valid[1] && dq_commit_ready[1]) begin
            if (!dqop_out[1][dq_commit_optag[3:2]]) dq_commit_stale <= 1'b1;
            dqop_out[1][dq_commit_optag[3:2]] <= 1'b0;
        end
        if (cq_rok) begin
            if (cqop_out[cq_resp_optag]) cqop_reuse <= 1'b1;
            cqop_out[cq_resp_optag] <= 1'b1;
        end
        if (cq_commit_valid && cq_commit_ready) begin
            if (!cqop_out[cq_commit_optag]) cq_commit_stale <= 1'b1;
            cqop_out[cq_commit_optag] <= 1'b0;
        end

        // ---------------------------------- the far end of the descriptor --
        if (cplhw_valid) begin
            n_cplhw <= sat_inc(n_cplhw);
            if (cplhw_data[47:32] != 16'd8 && cplhw_data[47:32] != 16'd16)
                cpl_len_bad <= 1'b1;
            if (cplhw_data[15:1] != 15'd0) cpl_queue_bad <= 1'b1;
        end

        // ------------------------------------------ boundary counters ------
        if (txreq_fire)     n_txreq       <= sat_inc(n_txreq);
        if (txreq_st_valid) n_txreq_st    <= sat_inc(n_txreq_st);
        if (df_req_fire)    n_dfreq       <= sat_inc(n_dfreq);
        if (df_st_ok)       n_dfst_ok     <= sat_inc(n_dfst_ok);
        if (df_desc_beat && df_desc_tlast) n_desc_stream <= sat_inc(n_desc_stream);
        if (cw_req_fire)    n_cw_req      <= sat_inc(n_cw_req);

        // ------------------------------------------------------- timers ----
        t_txreq_block <= (txreq_valid && !txreq_ready)
                         ? ((t_txreq_block == TSAT) ? TSAT : t_txreq_block + 1) : 0;
        t_tdr_block   <= (tdr_valid && !tdr_ready)
                         ? ((t_tdr_block == TSAT) ? TSAT : t_tdr_block + 1) : 0;
        t_rdr_block   <= (rdr_valid && !rdr_ready)
                         ? ((t_rdr_block == TSAT) ? TSAT : t_rdr_block + 1) : 0;
        t_tcr_block   <= (tcr_valid && !tcr_ready)
                         ? ((t_tcr_block == TSAT) ? TSAT : t_tcr_block + 1) : 0;
        t_rcr_block   <= (rcr_valid && !rcr_ready)
                         ? ((t_rcr_block == TSAT) ? TSAT : t_rcr_block + 1) : 0;

        if (df_st_valid || (n_dfreq == n_dfst_ok)) t_fetch <= 0;
        else t_fetch <= (t_fetch == TSAT) ? TSAT : t_fetch + 1;

        if (rxhw_valid || (n_iftx_pkt == n_rxhw_pkt)) t_pkt <= 0;
        else t_pkt <= (t_pkt == TSAT) ? TSAT : t_pkt + 1;

        t_txcpl0 <= (maccpl_valid[0] && !maccpl_ready[0])
                    ? ((t_txcpl0 == TSAT) ? TSAT : t_txcpl0 + 1) : 0;
        t_txcpl1 <= (maccpl_valid[1] && !maccpl_ready[1])
                    ? ((t_txcpl1 == TSAT) ? TSAT : t_txcpl1 + 1) : 0;

        if (any_event || !any_work) t_progress <= 0;
        else t_progress <= (t_progress == TSAT) ? TSAT : t_progress + 1;

        t_dffull <= (df_active_count == DF_TABLE_SIZE)
                    ? ((t_dffull == TSAT) ? TSAT : t_dffull + 1) : 0;
    end
end

// ================================================== candidate targets =====
// Every one is a SAFETY property.  Labels here, `taskdef.json:target_labels`
// and `lists/targets.txt` are identical and in the same order.

// ---- 1. end-to-end ordering ----------------------------------------------

T_ORDER_DEQ_RESP_TX_RING_IN_REQUEST_ORDER: assert property (@(posedge clk) disable iff (rst)
    !dq_order_bad[0]);

T_ORDER_DEQ_RESP_RX_RING_IN_REQUEST_ORDER: assert property (@(posedge clk) disable iff (rst)
    !dq_order_bad[1]);

T_ORDER_DESC_STREAM_IS_OLDEST_FETCH: assert property (@(posedge clk) disable iff (rst)
    !desc_order_bad);

T_ORDER_PKT_PORT0_FIFO: assert property (@(posedge clk) disable iff (rst)
    !ifrx_order_bad[0]);

T_ORDER_RXHOST_MATCHES_RXSTREAM: assert property (@(posedge clk) disable iff (rst)
    !rxhw_order_bad);

// ---- 2. data integrity ----------------------------------------------------

T_DATA_DESC_MATCHES_HOST: assert property (@(posedge clk) disable iff (rst)
    !desc_data_bad);

T_DATA_TXDMA_ADDR_MATCHES_DESC: assert property (@(posedge clk) disable iff (rst)
    !txdma_addr_bad);

T_DATA_RXDMA_ADDR_MATCHES_DESC: assert property (@(posedge clk) disable iff (rst)
    !rxdma_addr_bad);

T_DATA_IFTX_WORD_SELF_CONSISTENT: assert property (@(posedge clk) disable iff (rst)
    !iftx_word_bad);

T_DATA_IFTX_WORD_ADDR_STEPS_8: assert property (@(posedge clk) disable iff (rst)
    !iftx_step_bad);

T_DATA_MAC0_HALFWORD_PAIR: assert property (@(posedge clk) disable iff (rst)
    !mac_pair_bad[0]);

T_DATA_IFRX_WORD_SELF_CONSISTENT: assert property (@(posedge clk) disable iff (rst)
    !ifrx_word_bad);

T_DATA_RXHOST_WORD_SELF_CONSISTENT: assert property (@(posedge clk) disable iff (rst)
    !rxhw_word_bad);

T_DATA_RXHOST_WORD_ADDR_STEPS_8: assert property (@(posedge clk) disable iff (rst)
    !rxhw_step_bad);

T_DATA_CPL_ADDR_IS_NEXT_RING_SLOT: assert property (@(posedge clk) disable iff (rst)
    !cpl_slot_bad);

T_DATA_CPL_LEN_IS_A_PACKET_LEN: assert property (@(posedge clk) disable iff (rst)
    !cpl_len_bad);

// ---- 3. uniqueness / no duplication ---------------------------------------

T_UNIQ_DESC_DMA_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    !dh_reuse);

T_UNIQ_TXDATA_DMA_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    !th_reuse);

T_UNIQ_CPL_DMA_TAG_NOT_REUSED: assert property (@(posedge clk) disable iff (rst)
    !ch_reuse);

// ---- 4. no loss / conservation --------------------------------------------

T_CONSERV_DESC_STREAM_LE_FETCH_OK: assert property (@(posedge clk) disable iff (rst)
    n_desc_stream <= n_dfst_ok);

T_CONSERV_IFRX_LE_IFTX: assert property (@(posedge clk) disable iff (rst)
    n_ifrx_pkt <= n_iftx_pkt);

T_CONSERV_RXHOST_PKT_LE_IFRX: assert property (@(posedge clk) disable iff (rst)
    n_rxhw_pkt <= n_ifrx_pkt);

T_CONSERV_CPL_HOST_LE_CPL_DMA: assert property (@(posedge clk) disable iff (rst)
    n_cplhw <= n_ch_dma);

// ---- 5. mutual exclusion / one-hot ----------------------------------------

T_MUTEX_DEQ_REQ_ONEHOT: assert property (@(posedge clk) disable iff (rst)
    $onehot0(dq_req_valid));

T_MUTEX_DESC_STREAM_ONE_FLOW: assert property (@(posedge clk) disable iff (rst)
    !(txd_tvalid && rxd_tvalid));

// ---- 6. occupancy and bounds ----------------------------------------------

T_BOUND_TXFIFO0_DEPTH: assert property (@(posedge clk) disable iff (rst)
    txfifo_depth0 <= MAC_FIFO_BYTES);

T_BOUND_RXFIFO_DEPTH: assert property (@(posedge clk) disable iff (rst)
    rxfifo_depth0 <= MAC_FIFO_BYTES && rxfifo_depth1 <= MAC_FIFO_BYTES);

T_BOUND_DESC_FETCH_INFLIGHT: assert property (@(posedge clk) disable iff (rst)
    dfq_occ <= DF_TABLE_SIZE);

T_BOUND_DF_TABLE_PTR_SPAN: assert property (@(posedge clk) disable iff (rst)
    $unsigned(df_start_ptr - df_finish_ptr) <= DF_TABLE_SIZE);

T_BOUND_SHADOW_QUEUES_NEVER_UNDERFLOW: assert property (@(posedge clk) disable iff (rst)
    !rpq_bad && !dfq_bad && !tbq_bad && !rbq_bad);

// ---- 7. allocator discipline ----------------------------------------------

T_ALLOC_DEQ_COMMIT_NAMES_LIVE_OP: assert property (@(posedge clk) disable iff (rst)
    !dq_commit_stale);

T_ALLOC_ENQ_COMMIT_NAMES_LIVE_OP: assert property (@(posedge clk) disable iff (rst)
    !cq_commit_stale);

T_ALLOC_TXQM_OPSET_SUBSET_OF_DESIGN: assert property (@(posedge clk) disable iff (rst)
    (dqop_out[0] & ~txqm_op_active) == 4'd0);

T_ALLOC_TXCPL_TAG_MARKED: assert property (@(posedge clk) disable iff (rst)
    txcpl_valid |-> txcpl_tag[2] == 1'b1);

// ---- 8. request-response correspondence -----------------------------------

T_REQRSP_DESC_DMA_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    !dh_unsol);

T_REQRSP_TXDATA_DMA_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    !th_unsol);

T_REQRSP_CPL_DMA_STATUS_SOLICITED: assert property (@(posedge clk) disable iff (rst)
    !ch_unsol);

// ---- 9. protocol conformance ----------------------------------------------

T_PROTO_IFTX_TVALID_STABLE: assert property (@(posedge clk) disable iff (rst)
    (iftx_tvalid && !iftx_tready) |=> iftx_tvalid);

T_PROTO_IFTX_PAYLOAD_STABLE: assert property (@(posedge clk) disable iff (rst)
    (iftx_tvalid && !iftx_tready)
    |=> $stable(iftx_tdata) && $stable(iftx_tkeep) && $stable(iftx_tlast)
        && $stable(iftx_tdest) && $stable(iftx_tuser));

T_PROTO_DESC_STREAM_STABLE: assert property (@(posedge clk) disable iff (rst)
    (df_desc_tvalid && !df_desc_tready)
    |=> df_desc_tvalid && $stable(df_desc_tdata) && $stable(df_desc_tid));

T_PROTO_MAC_TUSER_GOOD_FRAME: assert property (@(posedge clk) disable iff (rst)
    (!mactx_tvalid[0] || mactx_tuser[0] == 1'b0)
    && (!mactx_tvalid[1] || mactx_tuser[4] == 1'b0));

// ---- 10. arbitration fairness ---------------------------------------------

T_FAIR_TX_DESC_REQ_ADMITTED_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    t_tdr_block < N_BLOCK);

T_FAIR_RX_DESC_REQ_ADMITTED_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    t_rdr_block < N_BLOCK);

// ---- 11. bounded response -------------------------------------------------

T_BOUNDRSP_FETCH_STATUS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    t_fetch < N_FETCH);

T_BOUNDRSP_PKT_TO_HOST_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    t_pkt < N_PKT);

// ---- 12. deadlock freedom -------------------------------------------------

T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    t_progress < N_PROGRESS);

T_DEADLOCK_DF_TABLE_DRAINS_WITHIN_N: assert property (@(posedge clk) disable iff (rst)
    t_dffull < N_DFFULL);

// ---- 13. reset / initialisation -------------------------------------------

T_RESET_DF_TABLE_IDLE: assert property (@(posedge clk)
    $fell(rst) |-> df_table_active == 4'd0 && df_active_count == 3'd0
                   && df_start_ptr == 3'd0 && df_finish_ptr == 3'd0);

// ---- 14. lifecycle / access control ---------------------------------------

T_LIFECYCLE_NO_DEQ_ERROR_AFTER_CONFIG: assert property (@(posedge clk) disable iff (rst)
    configured |-> !(dq_resp_valid[0] && dq_resp_error[0])
                   && !(dq_resp_valid[1] && dq_resp_error[1]));

T_LIFECYCLE_NO_ENQ_ERROR_AFTER_CONFIG: assert property (@(posedge clk) disable iff (rst)
    configured |-> !(cq_resp_valid && cq_resp_error));

// ==================================================== covers ==============
// One per category used, plus a graduated ladder along the chain so a
// `COVER_DEPTH` run that cannot reach the far end still reports where it
// stopped.

C_CONFIGURED: cover property (@(posedge clk) disable iff (rst)
    configured);

C_TXREQ_ACCEPTED: cover property (@(posedge clk) disable iff (rst)
    txreq_fire);

C_DESC_FETCH_STARTED: cover property (@(posedge clk) disable iff (rst)
    dh_fire);

C_DESC_STREAM_TX: cover property (@(posedge clk) disable iff (rst)
    txd_beat);

C_DESC_STREAM_RX: cover property (@(posedge clk) disable iff (rst)
    rxd_beat);

C_TXDATA_DMA_READ: cover property (@(posedge clk) disable iff (rst)
    th_fire);

C_IFTX_FIRST_BEAT: cover property (@(posedge clk) disable iff (rst)
    iftx_first);

C_IFTX_TWO_BEAT_PACKET: cover property (@(posedge clk) disable iff (rst)
    iftx_beat && iftx_in_frame && iftx_tlast);

C_MAC0_FRAME: cover property (@(posedge clk) disable iff (rst)
    mactx_tvalid[0] && mactx_tready[0] && mactx_tlast[0]);

C_MAC1_FRAME: cover property (@(posedge clk) disable iff (rst)
    mactx_tvalid[1] && mactx_tready[1] && mactx_tlast[1]);

C_BOTH_MAC_PORTS_USED: cover property (@(posedge clk) disable iff (rst)
    tpq_wr[0] != 0 && tpq_wr[1] != 0);

C_IFRX_FIRST_BEAT: cover property (@(posedge clk) disable iff (rst)
    ifrx_first);

C_RXDATA_DMA_WRITE: cover property (@(posedge clk) disable iff (rst)
    rh_fire);

C_RXHOST_WORD: cover property (@(posedge clk) disable iff (rst)
    rxhw_valid);

C_RXHOST_PACKET_DELIVERED: cover property (@(posedge clk) disable iff (rst)
    rxhw_valid && rxhw_first);

C_RXHOST_TWO_PACKETS: cover property (@(posedge clk) disable iff (rst)
    n_rxhw_pkt >= 12'd2);

C_CPL_REQUEST: cover property (@(posedge clk) disable iff (rst)
    cw_req_fire);

C_CPL_DMA_WRITE: cover property (@(posedge clk) disable iff (rst)
    ch_fire);

C_CPL_HOST_WRITE: cover property (@(posedge clk) disable iff (rst)
    cplhw_valid);

C_CPL_BOTH_RINGS: cover property (@(posedge clk) disable iff (rst)
    cq_slot[0] != 0 && cq_slot[1] != 0);

C_TXCPL_RETURNED: cover property (@(posedge clk) disable iff (rst)
    txcpl_valid && txcpl_ready);

C_TWO_FETCHES_IN_FLIGHT: cover property (@(posedge clk) disable iff (rst)
    dfq_occ >= 2);

C_DESC_ARB_CONTENTION: cover property (@(posedge clk) disable iff (rst)
    tdr_valid && rdr_valid);

C_CPL_ARB_CONTENTION: cover property (@(posedge clk) disable iff (rst)
    tcr_valid && rcr_valid);

C_TX_DESC_REQ_BLOCKED: cover property (@(posedge clk) disable iff (rst)
    t_tdr_block >= 12'd4);

C_TXFIFO_HALF_FULL: cover property (@(posedge clk) disable iff (rst)
    txfifo_depth0 >= 12'd32);

C_RXFIFO_HALF_FULL: cover property (@(posedge clk) disable iff (rst)
    rxfifo_depth0 >= 12'd32);

C_RING_OP_TAG_LIVE: cover property (@(posedge clk) disable iff (rst)
    dqop_out[0] != 4'd0);

C_CQ_OP_TAG_LIVE: cover property (@(posedge clk) disable iff (rst)
    cqop_out != 4'd0);

C_DF_TABLE_FULL: cover property (@(posedge clk) disable iff (rst)
    df_active_count == DF_TABLE_SIZE);

endmodule

bind corundum_tx_rx_datapath_ft corundum_txrx_targets corundum_txrx_targets (
    .clk(clk), .rst(rst));

`resetall
