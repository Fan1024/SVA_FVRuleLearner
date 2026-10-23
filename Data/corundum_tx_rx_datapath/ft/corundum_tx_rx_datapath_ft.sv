// ===========================================================================
// corundum_tx_rx_datapath_ft -- formal top for Corundum's mqnic TRANSMIT AND
// RECEIVE datapath, taken together.
//
// TASK-AUTHORED.  Nothing in this file comes from upstream Corundum; the 28
// upstream modules under `rtl/corundum/` are byte-identical and are only
// instantiated here.
//
// THE CHAIN, and where the queues sit.  Every `====` box is upstream RTL;
// every `env_*` is authored environment.
//
//   env_txreq  (one transmit request at a time: ring, tag, MAC port)
//        |  s_axis_tx_req
//        v
//   ==== mqnic_interface_tx ==========================================
//   |  tx_engine  -- desc req -->                                    |
//   |  QUEUE 1: tx_desc_fifo (axis_fifo, 64 B, 128-bit descriptors)  |
//   |  QUEUE 2: dma_psdpram_tx (256 B transmit packet RAM)           |
//   |  dma_client_axis_source  -> mqnic_egress ->                    |
//   |  QUEUE 3: tx_csum_cmd_fifo (axis_fifo, 32)                     |
//   |  QUEUE 4: tx_checksum's data_fifo (64 B) + csum_fifo (64)      |
//   ==================================================================
//        |  descriptor request                     |  transmit packet stream
//        v                                         v   64-bit, tid=ring,
//   ==== desc_op_mux ==== (2 flows: TX and RX)     |   tdest[4]=MAC port
//        |  one shared descriptor fetcher          |
//        v                                         v
//   ==== desc_fetch =============                ==== tx_fifo (PORTS=2) ====
//   |  QUEUE 5: dma_psdpram    |                 |  axis_demux by tdest[4] |
//   |  (128 B descriptor RAM)  |                 |  QUEUE 7,8: two         |
//   |  dma_client_axis_source  |                 |  axis_fifo_adapter      |
//   =============================                |  FRAME_FIFO 128 B,      |
//        |  dequeue req/resp/commit               |  store-and-forward,     |
//        v                                        |  64 -> 32 bit adapter   |
//   ==== queue_manager x2 =======                 ==========================
//   |  QUEUE 6: 4-entry op table |                     |  32-bit MAC x2
//   |  tx ring pair, rx ring pair|                     v
//   =============================                 env_mac x2  (loopback with
//        ^                                        |   a bounded stall and the
//        |  AXI-Lite bring-up                     |   transmit completion the
//   env_cfg_txq / env_cfg_rxq                     |   PTP path would give)
//                                                 v
//                                            ==== rx_fifo (PORTS=2) ====
//                                            |  QUEUE 9,10: two         |
//                                            |  axis_fifo_adapter       |
//                                            |  FRAME_FIFO 128 B,       |
//                                            |  32 -> 64 bit adapter    |
//                                            |  axis_arb_mux, tid=port  |
//                                            ===========================
//                                                 |  receive packet stream
//                                                 v
//   ==== mqnic_interface_rx ==========================================
//   |  mqnic_ingress: rx_hash + rx_checksum,                          |
//   |    QUEUE 11: rx_hash_fifo, QUEUE 12: rx_csum_fifo,              |
//   |    QUEUE 13: rx_hash_data_fifo (256 B)                          |
//   |  rx_engine -- desc req --> desc_op_mux (the second flow)        |
//   |    QUEUE 14: rx_desc_fifo (axis_fifo, 64 B)                     |
//   |    mqnic_rx_queue_map: MAC port -> receive ring                 |
//   |  QUEUE 15: dma_psdpram_rx (256 B receive packet RAM)            |
//   |  dma_client_axis_sink                                           |
//   ==================================================================
//        |  DMA write descriptor            |  completion request
//        v                                  v
//   env_hostwr_rx  (the far end of the      ==== cpl_op_mux ==== (2 flows:
//   packet: publishes each 64-bit word           TX and RX completions)
//   the receive DMA hands host memory)           |
//                                                v
//                                           ==== cpl_write ============
//                                           |  QUEUE 16: 4-entry table |
//                                           |  + 32 B completion data  |
//                                           ===========================
//                                                |  enqueue req/resp/commit
//                                                v
//                                           ==== cpl_queue_manager ====
//                                           |  QUEUE 17: 4-entry op    |
//                                           |  table, 2 completion     |
//                                           |  rings, phase bit        |
//                                           ===========================
//                                                |  DMA write descriptor
//                                                v
//                                           env_hostwr_cpl  (publishes the
//                                           256-bit completion word)
//
// Everything the environment CHOOSES is a free top-level input.  Everything
// the environment REMEMBERS lives in a submodule instance named `env_*` or in
// a top-level register named `ftenv_*`; `taskdef.json:design_keep` keeps that
// state out of the reset cut and cuts the whole design.
//
// THE ORACLE'S ONE IDEA.  Host memory is a pure function of its own address:
//
//     host_word(a) = { a[31:0], ~a[31:0] }
//
// so a 64-bit word carries its own address and its own complement.  A
// descriptor is a pure function of the address it was fetched from, and it
// names a packet buffer that is again a function of that address.  Nothing
// downstream has to be shadowed: the checker recomputes, it never copies.
// ===========================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module corundum_tx_rx_datapath_ft (
    input  wire       clk,
    input  wire       rst,

    // ---- transmit request generation -------------------------------------
    input  wire       env_tx_go,          // offer a transmit request
    input  wire       env_tx_queue,       // which transmit ring
    input  wire       env_tx_port,        // which MAC port (tdest[4])
    input  wire [2:0] env_tx_tag,         // the caller's tag, carried end to end

    // ---- bounded host-memory turnaround, 0..3 cycles each ----------------
    input  wire [1:0] env_desc_delay,     // descriptor fetch
    input  wire [1:0] env_txdata_delay,   // transmit packet read
    input  wire [1:0] env_rxdata_delay,   // receive packet write
    input  wire [1:0] env_cpl_delay,      // completion write

    // ---- MAC links: bounded stall, one bit per port ----------------------
    input  wire [1:0] env_mac_stall,

    // ---- driver: descriptor ring producer pointers -----------------------
    input  wire       env_txq_post_go,
    input  wire       env_txq_post_queue,
    input  wire       env_rxq_post_go,
    input  wire       env_rxq_post_queue,

    // ---- driver: completion ring consumer pointers -----------------------
    input  wire       env_cq_ret_go,
    input  wire       env_cq_ret_queue
);

// ================================================================ geometry
localparam PORTS                    = 2;    // MAC ports
localparam CL_PORTS                 = 1;

// packet streams
localparam AXIS_DATA_WIDTH          = 64;   // interface side
localparam AXIS_KEEP_WIDTH          = 8;
localparam MAC_DATA_WIDTH           = 32;   // MAC side
localparam MAC_KEEP_WIDTH           = 4;

// descriptors and completions
localparam DESC_SIZE                = 16;
localparam AXIS_DESC_DATA_WIDTH     = 128;
localparam AXIS_DESC_KEEP_WIDTH     = 16;
localparam CPL_SIZE                 = 32;

// queue indices
localparam TX_QUEUE_INDEX_WIDTH     = 1;
localparam RX_QUEUE_INDEX_WIDTH     = 1;
localparam QUEUE_INDEX_WIDTH        = 1;
localparam CQN_WIDTH                = 1;
localparam QUEUE_PTR_WIDTH          = 16;
localparam LOG_QUEUE_SIZE_WIDTH     = 4;
localparam LOG_BLOCK_SIZE_WIDTH     = 1;
localparam QUEUE_OP_TAG_WIDTH       = 2;
localparam QUEUE_OP_TABLE_SIZE      = 4;
localparam QUEUE_PIPELINE           = 2;

// tags
localparam TX_REQ_TAG_WIDTH         = 3;
localparam DESC_REQ_TAG_WIDTH_INT   = 3;
localparam DESC_REQ_TAG_WIDTH       = 4;
localparam QUEUE_REQ_TAG_WIDTH      = 4;
localparam CPL_REQ_TAG_WIDTH_INT    = 3;
localparam CPL_REQ_TAG_WIDTH        = 4;
localparam CPL_QUEUE_REQ_TAG_WIDTH  = 4;

// in-flight tables
localparam TX_DESC_TABLE_SIZE       = 4;
localparam RX_DESC_TABLE_SIZE       = 4;
localparam DF_DESC_TABLE_SIZE       = 4;
localparam CW_DESC_TABLE_SIZE       = 4;
localparam DESC_TABLE_DMA_OP_COUNT_WIDTH = 4;
localparam TX_TAG_WIDTH             = 3;    // $clog2(TX_DESC_TABLE_SIZE)+1

// DMA
localparam DMA_ADDR_WIDTH           = 64;
localparam DMA_LEN_WIDTH            = 16;
localparam DMA_TAG_WIDTH            = 4;

// packet RAM segments (both directions)
localparam RAM_SEG_COUNT            = 1;
localparam RAM_SEG_DATA_WIDTH       = 64;
localparam RAM_SEG_BE_WIDTH         = 8;
localparam RAM_SEG_ADDR_WIDTH       = 5;
localparam RAM_ADDR_WIDTH           = 8;    // 5 + clog2(1) + clog2(8)
localparam RAM_PIPELINE             = 2;
localparam TX_RAM_SIZE              = 256;
localparam RX_RAM_SIZE              = 256;

// descriptor RAM segments (inside desc_fetch)
localparam DSEG_COUNT               = 1;
localparam DSEG_DATA_WIDTH          = 128;
localparam DSEG_BE_WIDTH            = 16;
localparam DSEG_ADDR_WIDTH          = 3;
localparam DRAM_ADDR_WIDTH          = 7;    // 3 + clog2(1) + clog2(16)

// completion RAM segments (inside cpl_write)
localparam CSEG_COUNT               = 1;
localparam CSEG_DATA_WIDTH          = 256;
localparam CSEG_BE_WIDTH            = 32;
localparam CSEG_ADDR_WIDTH          = 3;
localparam CRAM_ADDR_WIDTH          = 8;    // 3 + clog2(1) + clog2(32)

// sizes
localparam MAX_TX_SIZE              = 64;
localparam MAX_RX_SIZE              = 64;
localparam TX_MAX_DESC_REQ          = 4;
localparam TX_DESC_FIFO_SIZE        = 4;
localparam RX_MAX_DESC_REQ          = 4;
localparam RX_DESC_FIFO_SIZE        = 4;
localparam MAC_FIFO_DEPTH           = 128;  // bytes, per MAC port
localparam MAC_FIFO_DEPTH_WIDTH     = 8;    // $clog2(128)+1

// features
localparam PTP_TS_ENABLE            = 0;
localparam PTP_TS_WIDTH             = 16;
localparam TX_CHECKSUM_ENABLE       = 1;
localparam RX_HASH_ENABLE           = 1;
localparam RX_CHECKSUM_ENABLE       = 1;

// derived stream widths
localparam AXIS_TX_ID_WIDTH         = TX_QUEUE_INDEX_WIDTH;   // 1
localparam AXIS_TX_DEST_WIDTH       = 5;                      // clog2(PORTS)+4
localparam AXIS_TX_USER_WIDTH       = TX_TAG_WIDTH + 1;       // 4
localparam AXIS_RX_ID_WIDTH         = 1;                      // clog2(PORTS)
localparam AXIS_RX_DEST_WIDTH       = RX_QUEUE_INDEX_WIDTH+1; // 2
localparam AXIS_RX_USER_WIDTH       = 1;                      // PTP disabled

// AXI-Lite
localparam AXIL_DATA_WIDTH          = 32;
localparam AXIL_STRB_WIDTH          = 4;
localparam TXQM_AXIL_AW             = TX_QUEUE_INDEX_WIDTH + 5;   // 6
localparam RXQM_AXIL_AW             = RX_QUEUE_INDEX_WIDTH + 5;   // 6
localparam CQM_AXIL_AW              = CQN_WIDTH + 4;              // 5
localparam RXIND_AXIL_AW            = 4;   // clog2(PORTS)+INDIR+2
localparam EVENT_WIDTH              = 2;

// receive-side register block (mqnic_rx_queue_map).  RB_NEXT_PTR must sit
// OUTSIDE [RB_BASE_ADDR, RB_BASE_ADDR+16+PORTS*16) or the block's own
// `initial` check fires.
localparam REG_ADDR_WIDTH           = 7;
localparam RB_BASE_ADDR             = 0;
localparam RB_NEXT_PTR              = 64;

// rings
localparam LOG_RING_SIZE            = 2;   // 4 entries
localparam RING_SIZE                = 4;
localparam LOG_DESC_BLOCK           = 0;   // one 16-byte descriptor per block

// host-memory map.  Every region is identified by an address bit, so the
// checker can tell what it is looking at without being told:
//   0x0001_0xxx  transmit descriptor rings   (bit 16)
//   0x0002_0xxx  receive  descriptor rings   (bit 17)
//   0x0003_0xxx  completion rings            (bits 16 and 17)
//   0x4xxx_xxxx  transmit packet buffers     (bit 30)
//   0x8xxx_xxxx  receive  packet buffers     (bit 31)
localparam [19:0] TXQ_BASE_HI20     = 20'h00010;
localparam [19:0] RXQ_BASE_HI20     = 20'h00020;
localparam [19:0] CQ_BASE_HI20      = 20'h00030;

// ================================================================== wires ==

// ---- transmit request (env -> mqnic_interface_tx) ------------------------
wire [TX_QUEUE_INDEX_WIDTH-1:0]  tx_req_queue;
wire [TX_REQ_TAG_WIDTH-1:0]      tx_req_tag;
wire [AXIS_TX_DEST_WIDTH-1:0]    tx_req_dest;
wire                             tx_req_valid;
wire                             tx_req_ready;

wire [DMA_LEN_WIDTH-1:0]         tx_req_status_len;
wire [TX_REQ_TAG_WIDTH-1:0]      tx_req_status_tag;
wire                             tx_req_status_valid;

// ---- descriptor requests: interface -> desc_op_mux -----------------------
wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_req_queue;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_req_tag;
wire                                tx_desc_req_valid;
wire                                tx_desc_req_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_req_queue;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_req_tag;
wire                                rx_desc_req_valid;
wire                                rx_desc_req_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_req_status_queue;
wire [QUEUE_PTR_WIDTH-1:0]          tx_desc_req_status_ptr;
wire [CQN_WIDTH-1:0]                tx_desc_req_status_cpl;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_req_status_tag;
wire                                tx_desc_req_status_empty;
wire                                tx_desc_req_status_error;
wire                                tx_desc_req_status_valid;

wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_req_status_queue;
wire [QUEUE_PTR_WIDTH-1:0]          rx_desc_req_status_ptr;
wire [CQN_WIDTH-1:0]                rx_desc_req_status_cpl;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_req_status_tag;
wire                                rx_desc_req_status_empty;
wire                                rx_desc_req_status_error;
wire                                rx_desc_req_status_valid;

wire [AXIS_DESC_DATA_WIDTH-1:0]     tx_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     tx_desc_tkeep;
wire                                tx_desc_tvalid;
wire                                tx_desc_tready;
wire                                tx_desc_tlast;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_tid;
wire                                tx_desc_tuser;

wire [AXIS_DESC_DATA_WIDTH-1:0]     rx_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     rx_desc_tkeep;
wire                                rx_desc_tvalid;
wire                                rx_desc_tready;
wire                                rx_desc_tlast;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_tid;
wire                                rx_desc_tuser;

// ---- desc_op_mux <-> desc_fetch ------------------------------------------
wire                                df_req_sel;
wire [QUEUE_INDEX_WIDTH-1:0]        df_req_queue;
wire [DESC_REQ_TAG_WIDTH-1:0]       df_req_tag;
wire                                df_req_valid;
wire                                df_req_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        df_st_queue;
wire [QUEUE_PTR_WIDTH-1:0]          df_st_ptr;
wire [CQN_WIDTH-1:0]                df_st_cpl;
wire [DESC_REQ_TAG_WIDTH-1:0]       df_st_tag;
wire                                df_st_empty;
wire                                df_st_error;
wire                                df_st_valid;

wire [AXIS_DESC_DATA_WIDTH-1:0]     df_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     df_desc_tkeep;
wire                                df_desc_tvalid;
wire                                df_desc_tready;
wire                                df_desc_tlast;
wire [DESC_REQ_TAG_WIDTH-1:0]       df_desc_tid;
wire                                df_desc_tuser;

// ---- desc_fetch <-> the two descriptor queue managers --------------------
wire [PORTS*QUEUE_INDEX_WIDTH-1:0]      dq_req_queue;
wire [PORTS*DESC_REQ_TAG_WIDTH-1:0]     dq_req_tag;
wire [PORTS-1:0]                        dq_req_valid;
wire [PORTS-1:0]                        dq_req_ready;

wire [PORTS*QUEUE_INDEX_WIDTH-1:0]      dq_resp_queue;
wire [PORTS*QUEUE_PTR_WIDTH-1:0]        dq_resp_ptr;
wire [PORTS*DMA_ADDR_WIDTH-1:0]         dq_resp_addr;
wire [PORTS*LOG_BLOCK_SIZE_WIDTH-1:0]   dq_resp_block_size;
wire [PORTS*CQN_WIDTH-1:0]              dq_resp_cpl;
wire [PORTS*QUEUE_REQ_TAG_WIDTH-1:0]    dq_resp_tag;
wire [PORTS*QUEUE_OP_TAG_WIDTH-1:0]     dq_resp_op_tag;
wire [PORTS-1:0]                        dq_resp_empty;
wire [PORTS-1:0]                        dq_resp_error;
wire [PORTS-1:0]                        dq_resp_valid;
wire [PORTS-1:0]                        dq_resp_ready;
wire [PORTS-1:0]                        dq_resp_phase;

wire [PORTS*QUEUE_OP_TAG_WIDTH-1:0]     dq_commit_op_tag;
wire [PORTS-1:0]                        dq_commit_valid;
wire [PORTS-1:0]                        dq_commit_ready;

wire [QUEUE_INDEX_WIDTH-1:0]            txq_doorbell_queue;
wire                                    txq_doorbell_valid;
wire [QUEUE_INDEX_WIDTH-1:0]            rxq_doorbell_queue;
wire                                    rxq_doorbell_valid;

// ---- desc_fetch <-> descriptor host memory --------------------------------
wire [DMA_ADDR_WIDTH-1:0]      dh_desc_dma_addr;
wire [DRAM_ADDR_WIDTH-1:0]     dh_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]       dh_desc_len;
wire [DMA_TAG_WIDTH-1:0]       dh_desc_tag;
wire                           dh_desc_valid;
wire                           dh_desc_ready;

wire [DMA_TAG_WIDTH-1:0]       dh_status_tag;
wire [3:0]                     dh_status_error;
wire                           dh_status_valid;

wire [DSEG_BE_WIDTH-1:0]       dh_ram_wr_be;
wire [DSEG_ADDR_WIDTH-1:0]     dh_ram_wr_addr;
wire [DSEG_DATA_WIDTH-1:0]     dh_ram_wr_data;
wire                           dh_ram_wr_valid;
wire                           dh_ram_wr_ready;
wire                           dh_ram_wr_done;

// ---- mqnic_interface_tx <-> transmit packet host memory -------------------
wire [DMA_ADDR_WIDTH-1:0]      th_desc_dma_addr;
wire [RAM_ADDR_WIDTH-1:0]      th_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]       th_desc_len;
wire [DMA_TAG_WIDTH-1:0]       th_desc_tag;
wire                           th_desc_valid;
wire                           th_desc_ready;

wire [DMA_TAG_WIDTH-1:0]       th_status_tag;
wire [3:0]                     th_status_error;
wire                           th_status_valid;

wire [RAM_SEG_BE_WIDTH-1:0]    th_ram_wr_be;
wire [RAM_SEG_ADDR_WIDTH-1:0]  th_ram_wr_addr;
wire [RAM_SEG_DATA_WIDTH-1:0]  th_ram_wr_data;
wire                           th_ram_wr_valid;
wire                           th_ram_wr_ready;
wire                           th_ram_wr_done;

// ---- mqnic_interface_rx <-> receive packet host memory --------------------
wire [DMA_ADDR_WIDTH-1:0]      rh_desc_dma_addr;
wire [RAM_ADDR_WIDTH-1:0]      rh_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]       rh_desc_len;
wire [DMA_TAG_WIDTH-1:0]       rh_desc_tag;
wire                           rh_desc_valid;
wire                           rh_desc_ready;

wire [DMA_TAG_WIDTH-1:0]       rh_status_tag;
wire [3:0]                     rh_status_error;
wire                           rh_status_valid;

wire [RAM_SEG_ADDR_WIDTH-1:0]  rh_ram_rd_addr;
wire                           rh_ram_rd_valid;
wire                           rh_ram_rd_ready;
wire [RAM_SEG_DATA_WIDTH-1:0]  rh_ram_rd_resp_data;
wire                           rh_ram_rd_resp_valid;
wire                           rh_ram_rd_resp_ready;

wire                           rx_host_wr_valid;
wire [DMA_ADDR_WIDTH-1:0]      rx_host_wr_addr;
wire [RAM_SEG_DATA_WIDTH-1:0]  rx_host_wr_data;

// ---- completion requests: interface -> cpl_op_mux ------------------------
wire [CQN_WIDTH-1:0]                tx_cpl_req_queue;
wire [CPL_REQ_TAG_WIDTH_INT-1:0]    tx_cpl_req_tag;
wire [CPL_SIZE*8-1:0]               tx_cpl_req_data;
wire                                tx_cpl_req_valid;
wire                                tx_cpl_req_ready;

wire [CQN_WIDTH-1:0]                rx_cpl_req_queue;
wire [CPL_REQ_TAG_WIDTH_INT-1:0]    rx_cpl_req_tag;
wire [CPL_SIZE*8-1:0]               rx_cpl_req_data;
wire                                rx_cpl_req_valid;
wire                                rx_cpl_req_ready;

wire [CPL_REQ_TAG_WIDTH_INT-1:0]    tx_cpl_req_status_tag;
wire                                tx_cpl_req_status_full;
wire                                tx_cpl_req_status_error;
wire                                tx_cpl_req_status_valid;

wire [CPL_REQ_TAG_WIDTH_INT-1:0]    rx_cpl_req_status_tag;
wire                                rx_cpl_req_status_full;
wire                                rx_cpl_req_status_error;
wire                                rx_cpl_req_status_valid;

// ---- cpl_op_mux <-> cpl_write --------------------------------------------
wire                                cw_req_sel;
wire [CQN_WIDTH-1:0]                cw_req_queue;
wire [CPL_REQ_TAG_WIDTH-1:0]        cw_req_tag;
wire [CPL_SIZE*8-1:0]               cw_req_data;
wire                                cw_req_valid;
wire                                cw_req_ready;

wire [CPL_REQ_TAG_WIDTH-1:0]        cw_req_status_tag;
wire                                cw_req_status_full;
wire                                cw_req_status_error;
wire                                cw_req_status_valid;

// ---- cpl_write <-> cpl_queue_manager -------------------------------------
wire [CQN_WIDTH-1:0]                    cq_enq_req_queue;
wire [CPL_QUEUE_REQ_TAG_WIDTH-1:0]      cq_enq_req_tag;
wire                                    cq_enq_req_valid;
wire                                    cq_enq_req_ready;

wire [CQN_WIDTH-1:0]                    cq_enq_resp_queue;
wire [QUEUE_PTR_WIDTH-1:0]              cq_enq_resp_ptr;
wire                                    cq_enq_resp_phase;
wire [DMA_ADDR_WIDTH-1:0]               cq_enq_resp_addr;
wire [EVENT_WIDTH-1:0]                  cq_enq_resp_event;
wire [CPL_QUEUE_REQ_TAG_WIDTH-1:0]      cq_enq_resp_tag;
wire [QUEUE_OP_TAG_WIDTH-1:0]           cq_enq_resp_op_tag;
wire                                    cq_enq_resp_full;
wire                                    cq_enq_resp_error;
wire                                    cq_enq_resp_valid;
wire                                    cq_enq_resp_ready;

wire [QUEUE_OP_TAG_WIDTH-1:0]           cq_enq_commit_op_tag;
wire                                    cq_enq_commit_valid;
wire                                    cq_enq_commit_ready;

wire [EVENT_WIDTH-1:0]                  cq_event;
wire [CQN_WIDTH-1:0]                    cq_event_source;
wire                                    cq_event_valid;

// ---- cpl_write <-> completion host memory --------------------------------
wire [DMA_ADDR_WIDTH-1:0]      ch_desc_dma_addr;
wire [CRAM_ADDR_WIDTH-1:0]     ch_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]       ch_desc_len;
wire [DMA_TAG_WIDTH-1:0]       ch_desc_tag;
wire                           ch_desc_valid;
wire                           ch_desc_ready;

wire [DMA_TAG_WIDTH-1:0]       ch_status_tag;
wire [3:0]                     ch_status_error;
wire                           ch_status_valid;

wire [CSEG_ADDR_WIDTH-1:0]     ch_ram_rd_addr;
wire                           ch_ram_rd_valid;
wire                           ch_ram_rd_ready;
wire [CSEG_DATA_WIDTH-1:0]     ch_ram_rd_resp_data;
wire                           ch_ram_rd_resp_valid;
wire                           ch_ram_rd_resp_ready;

wire                           cpl_host_wr_valid;
wire [DMA_ADDR_WIDTH-1:0]      cpl_host_wr_addr;
wire [CSEG_DATA_WIDTH-1:0]     cpl_host_wr_data;

// ---- transmit packet stream, interface -> tx_fifo ------------------------
wire [AXIS_DATA_WIDTH-1:0]     if_tx_tdata;
wire [AXIS_KEEP_WIDTH-1:0]     if_tx_tkeep;
wire                           if_tx_tvalid;
wire                           if_tx_tready;
wire                           if_tx_tlast;
wire [AXIS_TX_ID_WIDTH-1:0]    if_tx_tid;
wire [AXIS_TX_DEST_WIDTH-1:0]  if_tx_tdest;
wire [AXIS_TX_USER_WIDTH-1:0]  if_tx_tuser;

// ---- MAC-side transmit, tx_fifo -> env_mac -------------------------------
wire [PORTS*MAC_DATA_WIDTH-1:0]    mac_tx_tdata;
wire [PORTS*MAC_KEEP_WIDTH-1:0]    mac_tx_tkeep;
wire [PORTS-1:0]                   mac_tx_tvalid;
wire [PORTS-1:0]                   mac_tx_tready;
wire [PORTS-1:0]                   mac_tx_tlast;
wire [PORTS*AXIS_TX_ID_WIDTH-1:0]  mac_tx_tid;
wire [PORTS*AXIS_TX_DEST_WIDTH-1:0] mac_tx_tdest;
wire [PORTS*AXIS_TX_USER_WIDTH-1:0] mac_tx_tuser;

wire [MAC_FIFO_DEPTH_WIDTH*PORTS-1:0] tx_fifo_status_depth;
wire [MAC_FIFO_DEPTH_WIDTH*PORTS-1:0] tx_fifo_status_depth_commit;
wire [PORTS-1:0]                      tx_fifo_status_overflow;
wire [PORTS-1:0]                      tx_fifo_status_bad_frame;
wire [PORTS-1:0]                      tx_fifo_status_good_frame;

// ---- MAC-side receive, env_mac -> rx_fifo --------------------------------
wire [PORTS*MAC_DATA_WIDTH-1:0]    mac_rx_tdata;
wire [PORTS*MAC_KEEP_WIDTH-1:0]    mac_rx_tkeep;
wire [PORTS-1:0]                   mac_rx_tvalid;
wire [PORTS-1:0]                   mac_rx_tready;
wire [PORTS-1:0]                   mac_rx_tlast;
wire [PORTS*AXIS_RX_USER_WIDTH-1:0] mac_rx_tuser;

wire [MAC_FIFO_DEPTH_WIDTH*PORTS-1:0] rx_fifo_status_depth;
wire [MAC_FIFO_DEPTH_WIDTH*PORTS-1:0] rx_fifo_status_depth_commit;
wire [PORTS-1:0]                      rx_fifo_status_overflow;
wire [PORTS-1:0]                      rx_fifo_status_bad_frame;
wire [PORTS-1:0]                      rx_fifo_status_good_frame;

// ---- receive packet stream, rx_fifo -> interface -------------------------
wire [AXIS_DATA_WIDTH-1:0]     if_rx_tdata;
wire [AXIS_KEEP_WIDTH-1:0]     if_rx_tkeep;
wire                           if_rx_tvalid;
wire                           if_rx_tready;
wire                           if_rx_tlast;
wire [AXIS_RX_ID_WIDTH-1:0]    if_rx_tid;
wire [AXIS_RX_DEST_WIDTH-1:0]  if_rx_tdest;
wire [AXIS_RX_USER_WIDTH-1:0]  if_rx_tuser;

// ---- transmit completion, env_mac -> mqnic_interface_tx ------------------
wire [TX_TAG_WIDTH-1:0]        mac_cpl_tag  [0:PORTS-1];
wire [PORTS-1:0]               mac_cpl_valid;
wire [PORTS-1:0]               mac_cpl_ready;

wire [TX_TAG_WIDTH-1:0]        tx_cpl_tag;
wire                           tx_cpl_valid;
wire                           tx_cpl_ready;

// ---- AXI-Lite: transmit descriptor ring manager --------------------------
wire [TXQM_AXIL_AW-1:0]        txq_awaddr;
wire [2:0]                     txq_awprot;
wire                           txq_awvalid;
wire                           txq_awready;
wire [AXIL_DATA_WIDTH-1:0]     txq_wdata;
wire [AXIL_STRB_WIDTH-1:0]     txq_wstrb;
wire                           txq_wvalid;
wire                           txq_wready;
wire [1:0]                     txq_bresp;
wire                           txq_bvalid;
wire                           txq_bready;
wire [AXIL_DATA_WIDTH-1:0]     txq_rdata;
wire [1:0]                     txq_rresp;
wire                           txq_rvalid;

// ---- AXI-Lite: receive descriptor ring manager ---------------------------
wire [RXQM_AXIL_AW-1:0]        rxq_awaddr;
wire [2:0]                     rxq_awprot;
wire                           rxq_awvalid;
wire                           rxq_awready;
wire [AXIL_DATA_WIDTH-1:0]     rxq_wdata;
wire [AXIL_STRB_WIDTH-1:0]     rxq_wstrb;
wire                           rxq_wvalid;
wire                           rxq_wready;
wire [1:0]                     rxq_bresp;
wire                           rxq_bvalid;
wire                           rxq_bready;
wire [AXIL_DATA_WIDTH-1:0]     rxq_rdata;
wire [1:0]                     rxq_rresp;
wire                           rxq_rvalid;

// ---- AXI-Lite: completion ring manager -----------------------------------
wire [CQM_AXIL_AW-1:0]         cqm_awaddr;
wire [2:0]                     cqm_awprot;
wire                           cqm_awvalid;
wire                           cqm_awready;
wire [AXIL_DATA_WIDTH-1:0]     cqm_wdata;
wire [AXIL_STRB_WIDTH-1:0]     cqm_wstrb;
wire                           cqm_wvalid;
wire                           cqm_wready;
wire [1:0]                     cqm_bresp;
wire                           cqm_bvalid;
wire                           cqm_bready;
wire [AXIL_DATA_WIDTH-1:0]     cqm_rdata;
wire [1:0]                     cqm_rresp;
wire                           cqm_rvalid;

// ---- AXI-Lite: receive indirection table ---------------------------------
wire [RXIND_AXIL_AW-1:0]       ind_awaddr;
wire [2:0]                     ind_awprot;
wire                           ind_awvalid;
wire                           ind_awready;
wire [AXIL_DATA_WIDTH-1:0]     ind_wdata;
wire [AXIL_STRB_WIDTH-1:0]     ind_wstrb;
wire                           ind_wvalid;
wire                           ind_wready;
wire [1:0]                     ind_bresp;
wire                           ind_bvalid;
wire                           ind_bready;
wire [AXIL_DATA_WIDTH-1:0]     ind_rdata;
wire [1:0]                     ind_rresp;
wire                           ind_rvalid;

// ---- driver status --------------------------------------------------------
wire                           txq_init_done;
wire                           rxq_init_done;
wire                           cqm_init_done;
wire                           ind_init_done;

wire                           txq_adv_fire;
wire [QUEUE_INDEX_WIDTH-1:0]   txq_adv_fire_queue;
wire                           rxq_adv_fire;
wire [QUEUE_INDEX_WIDTH-1:0]   rxq_adv_fire_queue;
wire                           cqm_adv_fire;
wire [CQN_WIDTH-1:0]           cqm_adv_fire_queue;

wire all_configured = txq_init_done && rxq_init_done && cqm_init_done
                      && ind_init_done;

// ============================================== environment bookkeeping ==
// Ring credit.  `ftenv_*` is top-level environment state; `design_keep` holds
// it out of the reset cut for the same reason the checker's state is held out
// -- an arbitrary start makes the driver over-post and the conservation
// candidates false for a reason no design-side helper can repair.
reg [2:0] ftenv_tx_credit [0:1];   // descriptors posted and not yet handed out
reg [2:0] ftenv_rx_credit [0:1];
reg [2:0] ftenv_cq_live   [0:1];   // completions enqueued and not yet retired

integer qi;
initial begin
    for (qi = 0; qi < 2; qi = qi + 1) begin
        ftenv_tx_credit[qi] = 3'd0;
        ftenv_rx_credit[qi] = 3'd0;
        ftenv_cq_live[qi]   = 3'd0;
    end
end

// a descriptor actually leaves a descriptor ring when the manager answers a
// dequeue request without `empty` and without `error`
wire txq_taken = dq_resp_valid[0] && dq_resp_ready[0]
                 && !dq_resp_empty[0] && !dq_resp_error[0];
wire rxq_taken = dq_resp_valid[1] && dq_resp_ready[1]
                 && !dq_resp_empty[1] && !dq_resp_error[1];
wire txq_taken_q = dq_resp_queue[0*QUEUE_INDEX_WIDTH];
wire rxq_taken_q = dq_resp_queue[1*QUEUE_INDEX_WIDTH];

// a completion is really enqueued when the completion manager answers without
// `full` and without `error`
wire cq_started = cq_enq_resp_valid && cq_enq_resp_ready
                  && !cq_enq_resp_full && !cq_enq_resp_error;
wire cq_started_q = cq_enq_resp_queue[0];

always @(posedge clk) begin
    if (rst) begin
        for (qi = 0; qi < 2; qi = qi + 1) begin
            ftenv_tx_credit[qi] <= 3'd0;
            ftenv_rx_credit[qi] <= 3'd0;
            ftenv_cq_live[qi]   <= 3'd0;
        end
    end else begin
        // transmit ring: the driver posts, the manager hands out
        if (txq_adv_fire && !(txq_taken && txq_taken_q == txq_adv_fire_queue)) begin
            ftenv_tx_credit[txq_adv_fire_queue] <=
                ftenv_tx_credit[txq_adv_fire_queue] + 3'd1;
        end else if (txq_taken
                     && !(txq_adv_fire && txq_adv_fire_queue == txq_taken_q)) begin
            if (ftenv_tx_credit[txq_taken_q] != 3'd0) begin
                ftenv_tx_credit[txq_taken_q] <= ftenv_tx_credit[txq_taken_q] - 3'd1;
            end
        end

        // receive ring: same shape
        if (rxq_adv_fire && !(rxq_taken && rxq_taken_q == rxq_adv_fire_queue)) begin
            ftenv_rx_credit[rxq_adv_fire_queue] <=
                ftenv_rx_credit[rxq_adv_fire_queue] + 3'd1;
        end else if (rxq_taken
                     && !(rxq_adv_fire && rxq_adv_fire_queue == rxq_taken_q)) begin
            if (ftenv_rx_credit[rxq_taken_q] != 3'd0) begin
                ftenv_rx_credit[rxq_taken_q] <= ftenv_rx_credit[rxq_taken_q] - 3'd1;
            end
        end

        // completion ring: the design enqueues, the driver retires
        if (cq_started && !(cqm_adv_fire && cqm_adv_fire_queue == cq_started_q)) begin
            if (ftenv_cq_live[cq_started_q] != 3'd7) begin
                ftenv_cq_live[cq_started_q] <= ftenv_cq_live[cq_started_q] + 3'd1;
            end
        end else if (cqm_adv_fire
                     && !(cq_started && cq_started_q == cqm_adv_fire_queue)) begin
            if (ftenv_cq_live[cqm_adv_fire_queue] != 3'd0) begin
                ftenv_cq_live[cqm_adv_fire_queue] <=
                    ftenv_cq_live[cqm_adv_fire_queue] - 3'd1;
            end
        end
    end
end

wire [1:0] txq_post_allowed = {ftenv_tx_credit[1] < RING_SIZE,
                               ftenv_tx_credit[0] < RING_SIZE};
wire [1:0] rxq_post_allowed = {ftenv_rx_credit[1] < RING_SIZE,
                               ftenv_rx_credit[0] < RING_SIZE};
wire [1:0] cq_ret_allowed   = {ftenv_cq_live[1] != 3'd0,
                               ftenv_cq_live[0] != 3'd0};

// ==================================================== environment drivers ==

mqnic_axil_qcfg #(
    .CPL(0),
    .QUEUE_INDEX_WIDTH(TX_QUEUE_INDEX_WIDTH),
    .AXIL_ADDR_WIDTH(TXQM_AXIL_AW),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE),
    .LOG_BLOCK_SIZE(LOG_DESC_BLOCK),
    .BASE_HI20(TXQ_BASE_HI20),
    .BASE_UPPER(32'h0000_0000),
    .LINK_INDEX(24'd0)                  // transmit rings -> completion ring 0
)
env_cfg_txq (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(txq_awaddr), .m_axil_awprot(txq_awprot),
    .m_axil_awvalid(txq_awvalid), .m_axil_awready(txq_awready),
    .m_axil_wdata(txq_wdata), .m_axil_wstrb(txq_wstrb),
    .m_axil_wvalid(txq_wvalid), .m_axil_wready(txq_wready),
    .m_axil_bresp(txq_bresp), .m_axil_bvalid(txq_bvalid),
    .m_axil_bready(txq_bready),
    .adv_go(env_txq_post_go), .adv_queue(env_txq_post_queue),
    .adv_allowed(txq_post_allowed),
    .init_done(txq_init_done),
    .adv_fire(txq_adv_fire), .adv_fire_queue(txq_adv_fire_queue)
);

mqnic_axil_qcfg #(
    .CPL(0),
    .QUEUE_INDEX_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .AXIL_ADDR_WIDTH(RXQM_AXIL_AW),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE),
    .LOG_BLOCK_SIZE(LOG_DESC_BLOCK),
    .BASE_HI20(RXQ_BASE_HI20),
    .BASE_UPPER(32'h0000_0000),
    .LINK_INDEX(24'd1)                  // receive rings -> completion ring 1
)
env_cfg_rxq (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(rxq_awaddr), .m_axil_awprot(rxq_awprot),
    .m_axil_awvalid(rxq_awvalid), .m_axil_awready(rxq_awready),
    .m_axil_wdata(rxq_wdata), .m_axil_wstrb(rxq_wstrb),
    .m_axil_wvalid(rxq_wvalid), .m_axil_wready(rxq_wready),
    .m_axil_bresp(rxq_bresp), .m_axil_bvalid(rxq_bvalid),
    .m_axil_bready(rxq_bready),
    .adv_go(env_rxq_post_go), .adv_queue(env_rxq_post_queue),
    .adv_allowed(rxq_post_allowed),
    .init_done(rxq_init_done),
    .adv_fire(rxq_adv_fire), .adv_fire_queue(rxq_adv_fire_queue)
);

mqnic_axil_qcfg #(
    .CPL(1),
    .QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .AXIL_ADDR_WIDTH(CQM_AXIL_AW),
    .LOG_QUEUE_SIZE(LOG_RING_SIZE),
    .LOG_BLOCK_SIZE(0),
    .BASE_HI20(CQ_BASE_HI20),
    .BASE_UPPER(32'h0000_0000),
    .LINK_INDEX(24'd0)                  // event queue index (unused here)
)
env_cfg_cq (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(cqm_awaddr), .m_axil_awprot(cqm_awprot),
    .m_axil_awvalid(cqm_awvalid), .m_axil_awready(cqm_awready),
    .m_axil_wdata(cqm_wdata), .m_axil_wstrb(cqm_wstrb),
    .m_axil_wvalid(cqm_wvalid), .m_axil_wready(cqm_wready),
    .m_axil_bresp(cqm_bresp), .m_axil_bvalid(cqm_bvalid),
    .m_axil_bready(cqm_bready),
    .adv_go(env_cq_ret_go), .adv_queue(env_cq_ret_queue),
    .adv_allowed(cq_ret_allowed),
    .init_done(cqm_init_done),
    .adv_fire(cqm_adv_fire), .adv_fire_queue(cqm_adv_fire_queue)
);

// The receive-side indirection table: MAC port 0 -> receive ring 0, MAC port
// 1 -> receive ring 1.  With `app_mask` and `hash_mask` at their reset value
// of zero, `mqnic_rx_queue_map` indexes the table with {tid, 0}, so the two
// entries that matter are 0 and 2.
mqnic_rss_cfg #(
    .AXIL_ADDR_WIDTH(RXIND_AXIL_AW),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH)
)
env_cfg_ind (
    .clk(clk), .rst(rst),
    .m_axil_awaddr(ind_awaddr), .m_axil_awprot(ind_awprot),
    .m_axil_awvalid(ind_awvalid), .m_axil_awready(ind_awready),
    .m_axil_wdata(ind_wdata), .m_axil_wstrb(ind_wstrb),
    .m_axil_wvalid(ind_wvalid), .m_axil_wready(ind_wready),
    .m_axil_bresp(ind_bresp), .m_axil_bvalid(ind_bvalid),
    .m_axil_bready(ind_bready),
    .init_done(ind_init_done)
);

// The transmit request generator: one request at a time, payload stable until
// taken, and only for a ring the driver has actually posted a descriptor to.
mqnic_tx_req_gen #(
    .QUEUE_INDEX_WIDTH(TX_QUEUE_INDEX_WIDTH),
    .REQ_TAG_WIDTH(TX_REQ_TAG_WIDTH),
    .DEST_WIDTH(AXIS_TX_DEST_WIDTH)
)
env_txreq (
    .clk(clk), .rst(rst),
    .enable(all_configured),
    .env_go(env_tx_go),
    .env_queue(env_tx_queue),
    .env_port(env_tx_port),
    .env_tag(env_tx_tag),
    .env_credit({ftenv_tx_credit[1] != 3'd0, ftenv_tx_credit[0] != 3'd0}),
    .m_req_queue(tx_req_queue),
    .m_req_tag(tx_req_tag),
    .m_req_dest(tx_req_dest),
    .m_req_valid(tx_req_valid),
    .m_req_ready(tx_req_ready)
);

// ---- host memory: descriptor fetch ---------------------------------------
mqnic_desc_host_rd #(
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .SEG_ADDR_WIDTH(DSEG_ADDR_WIDTH),
    .SEG_DATA_WIDTH(DSEG_DATA_WIDTH),
    .SEG_BE_WIDTH(DSEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(DRAM_ADDR_WIDTH),
    .MAX_TX_LEN(32'd16),
    .MAX_RX_LEN(32'd64)
)
env_host_desc (
    .clk(clk), .rst(rst),
    .s_desc_dma_addr(dh_desc_dma_addr), .s_desc_ram_addr(dh_desc_ram_addr),
    .s_desc_len(dh_desc_len), .s_desc_tag(dh_desc_tag),
    .s_desc_valid(dh_desc_valid), .s_desc_ready(dh_desc_ready),
    .m_status_tag(dh_status_tag), .m_status_error(dh_status_error),
    .m_status_valid(dh_status_valid),
    .ram_wr_cmd_be(dh_ram_wr_be), .ram_wr_cmd_addr(dh_ram_wr_addr),
    .ram_wr_cmd_data(dh_ram_wr_data), .ram_wr_cmd_valid(dh_ram_wr_valid),
    .ram_wr_cmd_ready(dh_ram_wr_ready), .ram_wr_done(dh_ram_wr_done),
    .env_delay(env_desc_delay)
);

// ---- host memory: transmit packet data -----------------------------------
mqnic_data_host_rd #(
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH)
)
env_host_txdata (
    .clk(clk), .rst(rst),
    .s_desc_dma_addr(th_desc_dma_addr), .s_desc_ram_addr(th_desc_ram_addr),
    .s_desc_len(th_desc_len), .s_desc_tag(th_desc_tag),
    .s_desc_valid(th_desc_valid), .s_desc_ready(th_desc_ready),
    .m_status_tag(th_status_tag), .m_status_error(th_status_error),
    .m_status_valid(th_status_valid),
    .ram_wr_cmd_be(th_ram_wr_be), .ram_wr_cmd_addr(th_ram_wr_addr),
    .ram_wr_cmd_data(th_ram_wr_data), .ram_wr_cmd_valid(th_ram_wr_valid),
    .ram_wr_cmd_ready(th_ram_wr_ready), .ram_wr_done(th_ram_wr_done),
    .env_delay(env_txdata_delay)
);

// ---- host memory: receive packet data (the far end of the packet) --------
mqnic_host_wr #(
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH)
)
env_host_rxdata (
    .clk(clk), .rst(rst),
    .s_desc_dma_addr(rh_desc_dma_addr), .s_desc_ram_addr(rh_desc_ram_addr),
    .s_desc_len(rh_desc_len), .s_desc_tag(rh_desc_tag),
    .s_desc_valid(rh_desc_valid), .s_desc_ready(rh_desc_ready),
    .m_status_tag(rh_status_tag), .m_status_error(rh_status_error),
    .m_status_valid(rh_status_valid),
    .ram_rd_cmd_addr(rh_ram_rd_addr), .ram_rd_cmd_valid(rh_ram_rd_valid),
    .ram_rd_cmd_ready(rh_ram_rd_ready),
    .ram_rd_resp_data(rh_ram_rd_resp_data),
    .ram_rd_resp_valid(rh_ram_rd_resp_valid),
    .ram_rd_resp_ready(rh_ram_rd_resp_ready),
    .env_delay(env_rxdata_delay),
    .host_wr_valid(rx_host_wr_valid), .host_wr_addr(rx_host_wr_addr),
    .host_wr_data(rx_host_wr_data)
);

// ---- host memory: completion writeback (the far end of the descriptor) ---
mqnic_host_wr #(
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .SEG_ADDR_WIDTH(CSEG_ADDR_WIDTH),
    .SEG_DATA_WIDTH(CSEG_DATA_WIDTH),
    .SEG_BE_WIDTH(CSEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(CRAM_ADDR_WIDTH)
)
env_host_cpl (
    .clk(clk), .rst(rst),
    .s_desc_dma_addr(ch_desc_dma_addr), .s_desc_ram_addr(ch_desc_ram_addr),
    .s_desc_len(ch_desc_len), .s_desc_tag(ch_desc_tag),
    .s_desc_valid(ch_desc_valid), .s_desc_ready(ch_desc_ready),
    .m_status_tag(ch_status_tag), .m_status_error(ch_status_error),
    .m_status_valid(ch_status_valid),
    .ram_rd_cmd_addr(ch_ram_rd_addr), .ram_rd_cmd_valid(ch_ram_rd_valid),
    .ram_rd_cmd_ready(ch_ram_rd_ready),
    .ram_rd_resp_data(ch_ram_rd_resp_data),
    .ram_rd_resp_valid(ch_ram_rd_resp_valid),
    .ram_rd_resp_ready(ch_ram_rd_resp_ready),
    .env_delay(env_cpl_delay),
    .host_wr_valid(cpl_host_wr_valid), .host_wr_addr(cpl_host_wr_addr),
    .host_wr_data(cpl_host_wr_data)
);

// ---- the two MAC links ----------------------------------------------------
genvar p;
generate
for (p = 0; p < PORTS; p = p + 1) begin : mac
    mqnic_mac_loopback #(
        .DATA_WIDTH(MAC_DATA_WIDTH),
        .KEEP_WIDTH(MAC_KEEP_WIDTH),
        .TX_USER_WIDTH(AXIS_TX_USER_WIDTH),
        .RX_USER_WIDTH(AXIS_RX_USER_WIDTH),
        .TX_TAG_WIDTH(TX_TAG_WIDTH)
    )
    env_mac (
        .clk(clk), .rst(rst),
        .s_tdata(mac_tx_tdata[p*MAC_DATA_WIDTH +: MAC_DATA_WIDTH]),
        .s_tkeep(mac_tx_tkeep[p*MAC_KEEP_WIDTH +: MAC_KEEP_WIDTH]),
        .s_tvalid(mac_tx_tvalid[p]),
        .s_tready(mac_tx_tready[p]),
        .s_tlast(mac_tx_tlast[p]),
        .s_tuser(mac_tx_tuser[p*AXIS_TX_USER_WIDTH +: AXIS_TX_USER_WIDTH]),
        .m_tdata(mac_rx_tdata[p*MAC_DATA_WIDTH +: MAC_DATA_WIDTH]),
        .m_tkeep(mac_rx_tkeep[p*MAC_KEEP_WIDTH +: MAC_KEEP_WIDTH]),
        .m_tvalid(mac_rx_tvalid[p]),
        .m_tready(mac_rx_tready[p]),
        .m_tlast(mac_rx_tlast[p]),
        .m_tuser(mac_rx_tuser[p*AXIS_RX_USER_WIDTH +: AXIS_RX_USER_WIDTH]),
        .cpl_tag(mac_cpl_tag[p]),
        .cpl_valid(mac_cpl_valid[p]),
        .cpl_ready(mac_cpl_ready[p]),
        .env_stall(env_mac_stall[p])
    );
end
endgenerate

mqnic_txcpl_merge #(
    .TAG_WIDTH(TX_TAG_WIDTH)
)
env_txcpl (
    .clk(clk), .rst(rst),
    .s0_tag(mac_cpl_tag[0]), .s0_valid(mac_cpl_valid[0]),
    .s0_ready(mac_cpl_ready[0]),
    .s1_tag(mac_cpl_tag[1]), .s1_valid(mac_cpl_valid[1]),
    .s1_ready(mac_cpl_ready[1]),
    .m_tag(tx_cpl_tag), .m_valid(tx_cpl_valid), .m_ready(tx_cpl_ready)
);

// ==================================================== upstream instances ==

// ---- the two descriptor ring managers ------------------------------------
queue_manager #(
    .ADDR_WIDTH(DMA_ADDR_WIDTH),
    .REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .OP_TABLE_SIZE(QUEUE_OP_TABLE_SIZE),
    .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(TX_QUEUE_INDEX_WIDTH),
    .CPL_INDEX_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .PIPELINE(QUEUE_PIPELINE),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(TXQM_AXIL_AW),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH)
)
tx_qm_inst (
    .clk(clk), .rst(rst),
    .s_axis_dequeue_req_queue(dq_req_queue[0*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]),
    .s_axis_dequeue_req_tag(dq_req_tag[0*DESC_REQ_TAG_WIDTH +: DESC_REQ_TAG_WIDTH]),
    .s_axis_dequeue_req_valid(dq_req_valid[0]),
    .s_axis_dequeue_req_ready(dq_req_ready[0]),
    .m_axis_dequeue_resp_queue(dq_resp_queue[0*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]),
    .m_axis_dequeue_resp_ptr(dq_resp_ptr[0*QUEUE_PTR_WIDTH +: QUEUE_PTR_WIDTH]),
    .m_axis_dequeue_resp_phase(dq_resp_phase[0]),
    .m_axis_dequeue_resp_addr(dq_resp_addr[0*DMA_ADDR_WIDTH +: DMA_ADDR_WIDTH]),
    .m_axis_dequeue_resp_block_size(dq_resp_block_size[0*LOG_BLOCK_SIZE_WIDTH +: LOG_BLOCK_SIZE_WIDTH]),
    .m_axis_dequeue_resp_cpl(dq_resp_cpl[0*CQN_WIDTH +: CQN_WIDTH]),
    .m_axis_dequeue_resp_tag(dq_resp_tag[0*QUEUE_REQ_TAG_WIDTH +: QUEUE_REQ_TAG_WIDTH]),
    .m_axis_dequeue_resp_op_tag(dq_resp_op_tag[0*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
    .m_axis_dequeue_resp_empty(dq_resp_empty[0]),
    .m_axis_dequeue_resp_error(dq_resp_error[0]),
    .m_axis_dequeue_resp_valid(dq_resp_valid[0]),
    .m_axis_dequeue_resp_ready(dq_resp_ready[0]),
    .s_axis_dequeue_commit_op_tag(dq_commit_op_tag[0*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
    .s_axis_dequeue_commit_valid(dq_commit_valid[0]),
    .s_axis_dequeue_commit_ready(dq_commit_ready[0]),
    .m_axis_doorbell_queue(txq_doorbell_queue),
    .m_axis_doorbell_valid(txq_doorbell_valid),
    .s_axil_awaddr(txq_awaddr), .s_axil_awprot(txq_awprot),
    .s_axil_awvalid(txq_awvalid), .s_axil_awready(txq_awready),
    .s_axil_wdata(txq_wdata), .s_axil_wstrb(txq_wstrb),
    .s_axil_wvalid(txq_wvalid), .s_axil_wready(txq_wready),
    .s_axil_bresp(txq_bresp), .s_axil_bvalid(txq_bvalid),
    .s_axil_bready(txq_bready),
    .s_axil_araddr({TXQM_AXIL_AW{1'b0}}), .s_axil_arprot(3'd0),
    .s_axil_arvalid(1'b0), .s_axil_arready(),
    .s_axil_rdata(txq_rdata), .s_axil_rresp(txq_rresp),
    .s_axil_rvalid(txq_rvalid), .s_axil_rready(1'b1),
    .enable(1'b1)
);

queue_manager #(
    .ADDR_WIDTH(DMA_ADDR_WIDTH),
    .REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .OP_TABLE_SIZE(QUEUE_OP_TABLE_SIZE),
    .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .CPL_INDEX_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .PIPELINE(QUEUE_PIPELINE),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(RXQM_AXIL_AW),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH)
)
rx_qm_inst (
    .clk(clk), .rst(rst),
    .s_axis_dequeue_req_queue(dq_req_queue[1*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]),
    .s_axis_dequeue_req_tag(dq_req_tag[1*DESC_REQ_TAG_WIDTH +: DESC_REQ_TAG_WIDTH]),
    .s_axis_dequeue_req_valid(dq_req_valid[1]),
    .s_axis_dequeue_req_ready(dq_req_ready[1]),
    .m_axis_dequeue_resp_queue(dq_resp_queue[1*QUEUE_INDEX_WIDTH +: QUEUE_INDEX_WIDTH]),
    .m_axis_dequeue_resp_ptr(dq_resp_ptr[1*QUEUE_PTR_WIDTH +: QUEUE_PTR_WIDTH]),
    .m_axis_dequeue_resp_phase(dq_resp_phase[1]),
    .m_axis_dequeue_resp_addr(dq_resp_addr[1*DMA_ADDR_WIDTH +: DMA_ADDR_WIDTH]),
    .m_axis_dequeue_resp_block_size(dq_resp_block_size[1*LOG_BLOCK_SIZE_WIDTH +: LOG_BLOCK_SIZE_WIDTH]),
    .m_axis_dequeue_resp_cpl(dq_resp_cpl[1*CQN_WIDTH +: CQN_WIDTH]),
    .m_axis_dequeue_resp_tag(dq_resp_tag[1*QUEUE_REQ_TAG_WIDTH +: QUEUE_REQ_TAG_WIDTH]),
    .m_axis_dequeue_resp_op_tag(dq_resp_op_tag[1*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
    .m_axis_dequeue_resp_empty(dq_resp_empty[1]),
    .m_axis_dequeue_resp_error(dq_resp_error[1]),
    .m_axis_dequeue_resp_valid(dq_resp_valid[1]),
    .m_axis_dequeue_resp_ready(dq_resp_ready[1]),
    .s_axis_dequeue_commit_op_tag(dq_commit_op_tag[1*QUEUE_OP_TAG_WIDTH +: QUEUE_OP_TAG_WIDTH]),
    .s_axis_dequeue_commit_valid(dq_commit_valid[1]),
    .s_axis_dequeue_commit_ready(dq_commit_ready[1]),
    .m_axis_doorbell_queue(rxq_doorbell_queue),
    .m_axis_doorbell_valid(rxq_doorbell_valid),
    .s_axil_awaddr(rxq_awaddr), .s_axil_awprot(rxq_awprot),
    .s_axil_awvalid(rxq_awvalid), .s_axil_awready(rxq_awready),
    .s_axil_wdata(rxq_wdata), .s_axil_wstrb(rxq_wstrb),
    .s_axil_wvalid(rxq_wvalid), .s_axil_wready(rxq_wready),
    .s_axil_bresp(rxq_bresp), .s_axil_bvalid(rxq_bvalid),
    .s_axil_bready(rxq_bready),
    .s_axil_araddr({RXQM_AXIL_AW{1'b0}}), .s_axil_arprot(3'd0),
    .s_axil_arvalid(1'b0), .s_axil_arready(),
    .s_axil_rdata(rxq_rdata), .s_axil_rresp(rxq_rresp),
    .s_axil_rvalid(rxq_rvalid), .s_axil_rready(1'b1),
    .enable(1'b1)
);

// ---- the shared descriptor request arbiter -------------------------------
desc_op_mux #(
    .PORTS(2),
    .SELECT_WIDTH(1),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .CPL_QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .S_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH_INT),
    .M_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH),
    .AXIS_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .ARB_TYPE_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIORITY(1)
)
desc_op_mux_inst (
    .clk(clk), .rst(rst),
    .m_axis_req_sel(df_req_sel),
    .m_axis_req_queue(df_req_queue),
    .m_axis_req_tag(df_req_tag),
    .m_axis_req_valid(df_req_valid),
    .m_axis_req_ready(df_req_ready),
    .s_axis_req_status_queue(df_st_queue),
    .s_axis_req_status_ptr(df_st_ptr),
    .s_axis_req_status_cpl(df_st_cpl),
    .s_axis_req_status_tag(df_st_tag),
    .s_axis_req_status_empty(df_st_empty),
    .s_axis_req_status_error(df_st_error),
    .s_axis_req_status_valid(df_st_valid),
    .s_axis_desc_tdata(df_desc_tdata),
    .s_axis_desc_tkeep(df_desc_tkeep),
    .s_axis_desc_tvalid(df_desc_tvalid),
    .s_axis_desc_tready(df_desc_tready),
    .s_axis_desc_tlast(df_desc_tlast),
    .s_axis_desc_tid(df_desc_tid),
    .s_axis_desc_tuser(df_desc_tuser),
    .s_axis_req_sel({1'b1, 1'b0}),           // port 1 -> rx ring manager
    .s_axis_req_queue({rx_desc_req_queue, tx_desc_req_queue}),
    .s_axis_req_tag({rx_desc_req_tag, tx_desc_req_tag}),
    .s_axis_req_valid({rx_desc_req_valid, tx_desc_req_valid}),
    .s_axis_req_ready({rx_desc_req_ready, tx_desc_req_ready}),
    .m_axis_req_status_queue({rx_desc_req_status_queue, tx_desc_req_status_queue}),
    .m_axis_req_status_ptr({rx_desc_req_status_ptr, tx_desc_req_status_ptr}),
    .m_axis_req_status_cpl({rx_desc_req_status_cpl, tx_desc_req_status_cpl}),
    .m_axis_req_status_tag({rx_desc_req_status_tag, tx_desc_req_status_tag}),
    .m_axis_req_status_empty({rx_desc_req_status_empty, tx_desc_req_status_empty}),
    .m_axis_req_status_error({rx_desc_req_status_error, tx_desc_req_status_error}),
    .m_axis_req_status_valid({rx_desc_req_status_valid, tx_desc_req_status_valid}),
    .m_axis_desc_tdata({rx_desc_tdata, tx_desc_tdata}),
    .m_axis_desc_tkeep({rx_desc_tkeep, tx_desc_tkeep}),
    .m_axis_desc_tvalid({rx_desc_tvalid, tx_desc_tvalid}),
    .m_axis_desc_tready({rx_desc_tready, tx_desc_tready}),
    .m_axis_desc_tlast({rx_desc_tlast, tx_desc_tlast}),
    .m_axis_desc_tid({rx_desc_tid, tx_desc_tid}),
    .m_axis_desc_tuser({rx_desc_tuser, tx_desc_tuser})
);

// ---- the one descriptor fetcher ------------------------------------------
desc_fetch #(
    .PORTS(2),
    .SELECT_WIDTH(1),
    .SEG_COUNT(DSEG_COUNT),
    .SEG_DATA_WIDTH(DSEG_DATA_WIDTH),
    .SEG_ADDR_WIDTH(DSEG_ADDR_WIDTH),
    .SEG_BE_WIDTH(DSEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(DRAM_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH),
    .QUEUE_REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .QUEUE_OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CPL_QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .DESC_TABLE_SIZE(DF_DESC_TABLE_SIZE),
    .AXIS_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH)
)
desc_fetch_inst (
    .clk(clk), .rst(rst),
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
    .m_axis_desc_tdata(df_desc_tdata),
    .m_axis_desc_tkeep(df_desc_tkeep),
    .m_axis_desc_tvalid(df_desc_tvalid),
    .m_axis_desc_tready(df_desc_tready),
    .m_axis_desc_tlast(df_desc_tlast),
    .m_axis_desc_tid(df_desc_tid),
    .m_axis_desc_tuser(df_desc_tuser),
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
    .m_axis_dma_read_desc_dma_addr(dh_desc_dma_addr),
    .m_axis_dma_read_desc_ram_addr(dh_desc_ram_addr),
    .m_axis_dma_read_desc_len(dh_desc_len),
    .m_axis_dma_read_desc_tag(dh_desc_tag),
    .m_axis_dma_read_desc_valid(dh_desc_valid),
    .m_axis_dma_read_desc_ready(dh_desc_ready),
    .s_axis_dma_read_desc_status_tag(dh_status_tag),
    .s_axis_dma_read_desc_status_error(dh_status_error),
    .s_axis_dma_read_desc_status_valid(dh_status_valid),
    .dma_ram_wr_cmd_be(dh_ram_wr_be),
    .dma_ram_wr_cmd_addr(dh_ram_wr_addr),
    .dma_ram_wr_cmd_data(dh_ram_wr_data),
    .dma_ram_wr_cmd_valid(dh_ram_wr_valid),
    .dma_ram_wr_cmd_ready(dh_ram_wr_ready),
    .dma_ram_wr_done(dh_ram_wr_done),
    .enable(all_configured)
);

// ---- the transmit path ----------------------------------------------------
mqnic_interface_tx #(
    .PORTS(PORTS),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .TX_QUEUE_INDEX_WIDTH(TX_QUEUE_INDEX_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CQN_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .TX_MAX_DESC_REQ(TX_MAX_DESC_REQ),
    .TX_DESC_FIFO_SIZE(TX_DESC_FIFO_SIZE),
    .DESC_SIZE(DESC_SIZE),
    .CPL_SIZE(CPL_SIZE),
    .AXIS_DESC_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_DESC_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .REQ_TAG_WIDTH(TX_REQ_TAG_WIDTH),
    .DESC_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH_INT),
    .CPL_REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH_INT),
    .TX_DESC_TABLE_SIZE(TX_DESC_TABLE_SIZE),
    .DESC_TABLE_DMA_OP_COUNT_WIDTH(DESC_TABLE_DMA_OP_COUNT_WIDTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .TX_TAG_WIDTH(TX_TAG_WIDTH),
    .TX_CHECKSUM_ENABLE(TX_CHECKSUM_ENABLE),
    .MAX_TX_SIZE(MAX_TX_SIZE),
    .TX_RAM_SIZE(TX_RAM_SIZE),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_SEG_COUNT(RAM_SEG_COUNT),
    .RAM_SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .RAM_SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .AXIS_TX_ID_WIDTH(AXIS_TX_ID_WIDTH),
    .AXIS_TX_DEST_WIDTH(AXIS_TX_DEST_WIDTH),
    .AXIS_TX_USER_WIDTH(AXIS_TX_USER_WIDTH)
)
interface_tx_inst (
    .clk(clk), .rst(rst),
    .s_axis_tx_req_queue(tx_req_queue),
    .s_axis_tx_req_tag(tx_req_tag),
    .s_axis_tx_req_dest(tx_req_dest),
    .s_axis_tx_req_valid(tx_req_valid),
    .s_axis_tx_req_ready(tx_req_ready),
    .m_axis_tx_req_status_len(tx_req_status_len),
    .m_axis_tx_req_status_tag(tx_req_status_tag),
    .m_axis_tx_req_status_valid(tx_req_status_valid),
    .m_axis_desc_req_queue(tx_desc_req_queue),
    .m_axis_desc_req_tag(tx_desc_req_tag),
    .m_axis_desc_req_valid(tx_desc_req_valid),
    .m_axis_desc_req_ready(tx_desc_req_ready),
    .s_axis_desc_req_status_queue(tx_desc_req_status_queue),
    .s_axis_desc_req_status_ptr(tx_desc_req_status_ptr),
    .s_axis_desc_req_status_cpl(tx_desc_req_status_cpl),
    .s_axis_desc_req_status_tag(tx_desc_req_status_tag),
    .s_axis_desc_req_status_empty(tx_desc_req_status_empty),
    .s_axis_desc_req_status_error(tx_desc_req_status_error),
    .s_axis_desc_req_status_valid(tx_desc_req_status_valid),
    .s_axis_desc_tdata(tx_desc_tdata),
    .s_axis_desc_tkeep(tx_desc_tkeep),
    .s_axis_desc_tvalid(tx_desc_tvalid),
    .s_axis_desc_tready(tx_desc_tready),
    .s_axis_desc_tlast(tx_desc_tlast),
    .s_axis_desc_tid(tx_desc_tid),
    .s_axis_desc_tuser(tx_desc_tuser),
    .m_axis_cpl_req_queue(tx_cpl_req_queue),
    .m_axis_cpl_req_tag(tx_cpl_req_tag),
    .m_axis_cpl_req_data(tx_cpl_req_data),
    .m_axis_cpl_req_valid(tx_cpl_req_valid),
    .m_axis_cpl_req_ready(tx_cpl_req_ready),
    .s_axis_cpl_req_status_tag(tx_cpl_req_status_tag),
    .s_axis_cpl_req_status_full(tx_cpl_req_status_full),
    .s_axis_cpl_req_status_error(tx_cpl_req_status_error),
    .s_axis_cpl_req_status_valid(tx_cpl_req_status_valid),
    .m_axis_dma_read_desc_dma_addr(th_desc_dma_addr),
    .m_axis_dma_read_desc_ram_addr(th_desc_ram_addr),
    .m_axis_dma_read_desc_len(th_desc_len),
    .m_axis_dma_read_desc_tag(th_desc_tag),
    .m_axis_dma_read_desc_valid(th_desc_valid),
    .m_axis_dma_read_desc_ready(th_desc_ready),
    .s_axis_dma_read_desc_status_tag(th_status_tag),
    .s_axis_dma_read_desc_status_error(th_status_error),
    .s_axis_dma_read_desc_status_valid(th_status_valid),
    .dma_ram_wr_cmd_be(th_ram_wr_be),
    .dma_ram_wr_cmd_addr(th_ram_wr_addr),
    .dma_ram_wr_cmd_data(th_ram_wr_data),
    .dma_ram_wr_cmd_valid(th_ram_wr_valid),
    .dma_ram_wr_cmd_ready(th_ram_wr_ready),
    .dma_ram_wr_done(th_ram_wr_done),
    .m_axis_tx_tdata(if_tx_tdata),
    .m_axis_tx_tkeep(if_tx_tkeep),
    .m_axis_tx_tvalid(if_tx_tvalid),
    .m_axis_tx_tready(if_tx_tready),
    .m_axis_tx_tlast(if_tx_tlast),
    .m_axis_tx_tid(if_tx_tid),
    .m_axis_tx_tdest(if_tx_tdest),
    .m_axis_tx_tuser(if_tx_tuser),
    .s_axis_tx_cpl_ts({PTP_TS_WIDTH{1'b0}}),
    .s_axis_tx_cpl_tag(tx_cpl_tag),
    .s_axis_tx_cpl_valid(tx_cpl_valid),
    .s_axis_tx_cpl_ready(tx_cpl_ready),
    .mtu(MAX_TX_SIZE[DMA_LEN_WIDTH-1:0])
);

// ---- the MAC-side transmit frame buffers ---------------------------------
tx_fifo #(
    .FIFO_DEPTH(MAC_FIFO_DEPTH),
    .FIFO_DEPTH_WIDTH(MAC_FIFO_DEPTH_WIDTH),
    .PORTS(PORTS),
    .S_DATA_WIDTH(AXIS_DATA_WIDTH),
    .S_KEEP_ENABLE(1),
    .S_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .M_DATA_WIDTH(MAC_DATA_WIDTH),
    .M_KEEP_ENABLE(1),
    .M_KEEP_WIDTH(MAC_KEEP_WIDTH),
    .ID_ENABLE(1),
    .ID_WIDTH(AXIS_TX_ID_WIDTH),
    .S_DEST_WIDTH(AXIS_TX_DEST_WIDTH),
    .M_DEST_WIDTH(AXIS_TX_DEST_WIDTH),
    .USER_ENABLE(1),
    .USER_WIDTH(AXIS_TX_USER_WIDTH),
    .RAM_PIPELINE(1)
)
tx_fifo_inst (
    .clk(clk), .rst(rst),
    .s_axis_tdata(if_tx_tdata),
    .s_axis_tkeep(if_tx_tkeep),
    .s_axis_tvalid(if_tx_tvalid),
    .s_axis_tready(if_tx_tready),
    .s_axis_tlast(if_tx_tlast),
    .s_axis_tid(if_tx_tid),
    .s_axis_tdest(if_tx_tdest),
    .s_axis_tuser(if_tx_tuser),
    .m_axis_tdata(mac_tx_tdata),
    .m_axis_tkeep(mac_tx_tkeep),
    .m_axis_tvalid(mac_tx_tvalid),
    .m_axis_tready(mac_tx_tready),
    .m_axis_tlast(mac_tx_tlast),
    .m_axis_tid(mac_tx_tid),
    .m_axis_tdest(mac_tx_tdest),
    .m_axis_tuser(mac_tx_tuser),
    .status_depth(tx_fifo_status_depth),
    .status_depth_commit(tx_fifo_status_depth_commit),
    .status_overflow(tx_fifo_status_overflow),
    .status_bad_frame(tx_fifo_status_bad_frame),
    .status_good_frame(tx_fifo_status_good_frame)
);

// ---- the MAC-side receive frame buffers ----------------------------------
rx_fifo #(
    .FIFO_DEPTH(MAC_FIFO_DEPTH),
    .FIFO_DEPTH_WIDTH(MAC_FIFO_DEPTH_WIDTH),
    .PORTS(PORTS),
    .S_DATA_WIDTH(MAC_DATA_WIDTH),
    .S_KEEP_ENABLE(1),
    .S_KEEP_WIDTH(MAC_KEEP_WIDTH),
    .M_DATA_WIDTH(AXIS_DATA_WIDTH),
    .M_KEEP_ENABLE(1),
    .M_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .ID_ENABLE(1),
    .S_ID_WIDTH(1),
    .M_ID_WIDTH(AXIS_RX_ID_WIDTH),
    .DEST_ENABLE(0),
    .DEST_WIDTH(AXIS_RX_DEST_WIDTH),
    .USER_ENABLE(1),
    .USER_WIDTH(AXIS_RX_USER_WIDTH),
    .RAM_PIPELINE(1)
)
rx_fifo_inst (
    .clk(clk), .rst(rst),
    .s_axis_tdata(mac_rx_tdata),
    .s_axis_tkeep(mac_rx_tkeep),
    .s_axis_tvalid(mac_rx_tvalid),
    .s_axis_tready(mac_rx_tready),
    .s_axis_tlast(mac_rx_tlast),
    .s_axis_tid({PORTS{1'b0}}),
    .s_axis_tdest({(PORTS*AXIS_RX_DEST_WIDTH){1'b0}}),
    .s_axis_tuser(mac_rx_tuser),
    .m_axis_tdata(if_rx_tdata),
    .m_axis_tkeep(if_rx_tkeep),
    .m_axis_tvalid(if_rx_tvalid),
    .m_axis_tready(if_rx_tready),
    .m_axis_tlast(if_rx_tlast),
    .m_axis_tid(if_rx_tid),
    .m_axis_tdest(if_rx_tdest),
    .m_axis_tuser(if_rx_tuser),
    .status_depth(rx_fifo_status_depth),
    .status_depth_commit(rx_fifo_status_depth_commit),
    .status_overflow(rx_fifo_status_overflow),
    .status_bad_frame(rx_fifo_status_bad_frame),
    .status_good_frame(rx_fifo_status_good_frame)
);

// ---- the receive path -----------------------------------------------------
mqnic_interface_rx #(
    .PORTS(PORTS),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .RX_QUEUE_INDEX_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CQN_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .RX_MAX_DESC_REQ(RX_MAX_DESC_REQ),
    .RX_DESC_FIFO_SIZE(RX_DESC_FIFO_SIZE),
    .DESC_SIZE(DESC_SIZE),
    .CPL_SIZE(CPL_SIZE),
    .AXIS_DESC_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_DESC_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .DESC_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH_INT),
    .CPL_REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH_INT),
    .RX_DESC_TABLE_SIZE(RX_DESC_TABLE_SIZE),
    .DESC_TABLE_DMA_OP_COUNT_WIDTH(DESC_TABLE_DMA_OP_COUNT_WIDTH),
    .RX_INDIR_TBL_ADDR_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .RX_HASH_ENABLE(RX_HASH_ENABLE),
    .RX_CHECKSUM_ENABLE(RX_CHECKSUM_ENABLE),
    .MAX_RX_SIZE(MAX_RX_SIZE),
    .RX_RAM_SIZE(RX_RAM_SIZE),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_SEG_COUNT(RAM_SEG_COUNT),
    .RAM_SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .RAM_SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
    .REG_DATA_WIDTH(AXIL_DATA_WIDTH),
    .REG_STRB_WIDTH(AXIL_STRB_WIDTH),
    .RB_BASE_ADDR(RB_BASE_ADDR),
    .RB_NEXT_PTR(RB_NEXT_PTR),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(RXIND_AXIL_AW),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH),
    .AXIL_BASE_ADDR(0),
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .AXIS_RX_ID_WIDTH(AXIS_RX_ID_WIDTH),
    .AXIS_RX_DEST_WIDTH(AXIS_RX_DEST_WIDTH),
    .AXIS_RX_USER_WIDTH(AXIS_RX_USER_WIDTH)
)
interface_rx_inst (
    .clk(clk), .rst(rst),
    .ctrl_reg_wr_addr({REG_ADDR_WIDTH{1'b0}}),
    .ctrl_reg_wr_data({AXIL_DATA_WIDTH{1'b0}}),
    .ctrl_reg_wr_strb({AXIL_STRB_WIDTH{1'b0}}),
    .ctrl_reg_wr_en(1'b0),
    .ctrl_reg_wr_wait(),
    .ctrl_reg_wr_ack(),
    .ctrl_reg_rd_addr({REG_ADDR_WIDTH{1'b0}}),
    .ctrl_reg_rd_en(1'b0),
    .ctrl_reg_rd_data(),
    .ctrl_reg_rd_wait(),
    .ctrl_reg_rd_ack(),
    .s_axil_awaddr(ind_awaddr), .s_axil_awprot(ind_awprot),
    .s_axil_awvalid(ind_awvalid), .s_axil_awready(ind_awready),
    .s_axil_wdata(ind_wdata), .s_axil_wstrb(ind_wstrb),
    .s_axil_wvalid(ind_wvalid), .s_axil_wready(ind_wready),
    .s_axil_bresp(ind_bresp), .s_axil_bvalid(ind_bvalid),
    .s_axil_bready(ind_bready),
    .s_axil_araddr({RXIND_AXIL_AW{1'b0}}), .s_axil_arprot(3'd0),
    .s_axil_arvalid(1'b0), .s_axil_arready(),
    .s_axil_rdata(ind_rdata), .s_axil_rresp(ind_rresp),
    .s_axil_rvalid(ind_rvalid), .s_axil_rready(1'b1),
    .m_axis_desc_req_queue(rx_desc_req_queue),
    .m_axis_desc_req_tag(rx_desc_req_tag),
    .m_axis_desc_req_valid(rx_desc_req_valid),
    .m_axis_desc_req_ready(rx_desc_req_ready),
    .s_axis_desc_req_status_queue(rx_desc_req_status_queue),
    .s_axis_desc_req_status_ptr(rx_desc_req_status_ptr),
    .s_axis_desc_req_status_cpl(rx_desc_req_status_cpl),
    .s_axis_desc_req_status_tag(rx_desc_req_status_tag),
    .s_axis_desc_req_status_empty(rx_desc_req_status_empty),
    .s_axis_desc_req_status_error(rx_desc_req_status_error),
    .s_axis_desc_req_status_valid(rx_desc_req_status_valid),
    .s_axis_desc_tdata(rx_desc_tdata),
    .s_axis_desc_tkeep(rx_desc_tkeep),
    .s_axis_desc_tvalid(rx_desc_tvalid),
    .s_axis_desc_tready(rx_desc_tready),
    .s_axis_desc_tlast(rx_desc_tlast),
    .s_axis_desc_tid(rx_desc_tid),
    .s_axis_desc_tuser(rx_desc_tuser),
    .m_axis_cpl_req_queue(rx_cpl_req_queue),
    .m_axis_cpl_req_tag(rx_cpl_req_tag),
    .m_axis_cpl_req_data(rx_cpl_req_data),
    .m_axis_cpl_req_valid(rx_cpl_req_valid),
    .m_axis_cpl_req_ready(rx_cpl_req_ready),
    .s_axis_cpl_req_status_tag(rx_cpl_req_status_tag),
    .s_axis_cpl_req_status_full(rx_cpl_req_status_full),
    .s_axis_cpl_req_status_error(rx_cpl_req_status_error),
    .s_axis_cpl_req_status_valid(rx_cpl_req_status_valid),
    .m_axis_dma_write_desc_dma_addr(rh_desc_dma_addr),
    .m_axis_dma_write_desc_ram_addr(rh_desc_ram_addr),
    .m_axis_dma_write_desc_len(rh_desc_len),
    .m_axis_dma_write_desc_tag(rh_desc_tag),
    .m_axis_dma_write_desc_valid(rh_desc_valid),
    .m_axis_dma_write_desc_ready(rh_desc_ready),
    .s_axis_dma_write_desc_status_tag(rh_status_tag),
    .s_axis_dma_write_desc_status_error(rh_status_error),
    .s_axis_dma_write_desc_status_valid(rh_status_valid),
    .dma_ram_rd_cmd_addr(rh_ram_rd_addr),
    .dma_ram_rd_cmd_valid(rh_ram_rd_valid),
    .dma_ram_rd_cmd_ready(rh_ram_rd_ready),
    .dma_ram_rd_resp_data(rh_ram_rd_resp_data),
    .dma_ram_rd_resp_valid(rh_ram_rd_resp_valid),
    .dma_ram_rd_resp_ready(rh_ram_rd_resp_ready),
    .s_axis_rx_tdata(if_rx_tdata),
    .s_axis_rx_tkeep(if_rx_tkeep),
    .s_axis_rx_tvalid(if_rx_tvalid),
    .s_axis_rx_tready(if_rx_tready),
    .s_axis_rx_tlast(if_rx_tlast),
    .s_axis_rx_tid(if_rx_tid),
    .s_axis_rx_tdest(if_rx_tdest),
    .s_axis_rx_tuser(if_rx_tuser),
    .mtu(MAX_RX_SIZE[DMA_LEN_WIDTH-1:0])
);

// ---- the shared completion request arbiter -------------------------------
cpl_op_mux #(
    .PORTS(2),
    .SELECT_WIDTH(1),
    .QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .S_REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH_INT),
    .M_REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH),
    .CPL_SIZE(CPL_SIZE),
    .ARB_TYPE_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIORITY(1)
)
cpl_op_mux_inst (
    .clk(clk), .rst(rst),
    .m_axis_req_sel(cw_req_sel),
    .m_axis_req_queue(cw_req_queue),
    .m_axis_req_tag(cw_req_tag),
    .m_axis_req_data(cw_req_data),
    .m_axis_req_valid(cw_req_valid),
    .m_axis_req_ready(cw_req_ready),
    .s_axis_req_status_tag(cw_req_status_tag),
    .s_axis_req_status_full(cw_req_status_full),
    .s_axis_req_status_error(cw_req_status_error),
    .s_axis_req_status_valid(cw_req_status_valid),
    .s_axis_req_sel({1'b0, 1'b0}),
    .s_axis_req_queue({rx_cpl_req_queue, tx_cpl_req_queue}),
    .s_axis_req_tag({rx_cpl_req_tag, tx_cpl_req_tag}),
    .s_axis_req_data({rx_cpl_req_data, tx_cpl_req_data}),
    .s_axis_req_valid({rx_cpl_req_valid, tx_cpl_req_valid}),
    .s_axis_req_ready({rx_cpl_req_ready, tx_cpl_req_ready}),
    .m_axis_req_status_tag({rx_cpl_req_status_tag, tx_cpl_req_status_tag}),
    .m_axis_req_status_full({rx_cpl_req_status_full, tx_cpl_req_status_full}),
    .m_axis_req_status_error({rx_cpl_req_status_error, tx_cpl_req_status_error}),
    .m_axis_req_status_valid({rx_cpl_req_status_valid, tx_cpl_req_status_valid})
);

// ---- the one completion writer -------------------------------------------
cpl_write #(
    .PORTS(1),
    .SELECT_WIDTH(1),
    .SEG_COUNT(CSEG_COUNT),
    .SEG_DATA_WIDTH(CSEG_DATA_WIDTH),
    .SEG_ADDR_WIDTH(CSEG_ADDR_WIDTH),
    .SEG_BE_WIDTH(CSEG_BE_WIDTH),
    .RAM_ADDR_WIDTH(CRAM_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH),
    .QUEUE_REQ_TAG_WIDTH(CPL_QUEUE_REQ_TAG_WIDTH),
    .QUEUE_OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .CPL_SIZE(CPL_SIZE),
    .DESC_TABLE_SIZE(CW_DESC_TABLE_SIZE)
)
cpl_write_inst (
    .clk(clk), .rst(rst),
    .s_axis_req_sel(1'b0),
    .s_axis_req_queue(cw_req_queue),
    .s_axis_req_tag(cw_req_tag),
    .s_axis_req_data(cw_req_data),
    .s_axis_req_valid(cw_req_valid),
    .s_axis_req_ready(cw_req_ready),
    .m_axis_req_status_tag(cw_req_status_tag),
    .m_axis_req_status_full(cw_req_status_full),
    .m_axis_req_status_error(cw_req_status_error),
    .m_axis_req_status_valid(cw_req_status_valid),
    .m_axis_cpl_enqueue_req_queue(cq_enq_req_queue),
    .m_axis_cpl_enqueue_req_tag(cq_enq_req_tag),
    .m_axis_cpl_enqueue_req_valid(cq_enq_req_valid),
    .m_axis_cpl_enqueue_req_ready(cq_enq_req_ready),
    .s_axis_cpl_enqueue_resp_phase(cq_enq_resp_phase),
    .s_axis_cpl_enqueue_resp_addr(cq_enq_resp_addr),
    .s_axis_cpl_enqueue_resp_tag(cq_enq_resp_tag),
    .s_axis_cpl_enqueue_resp_op_tag(cq_enq_resp_op_tag),
    .s_axis_cpl_enqueue_resp_full(cq_enq_resp_full),
    .s_axis_cpl_enqueue_resp_error(cq_enq_resp_error),
    .s_axis_cpl_enqueue_resp_valid(cq_enq_resp_valid),
    .s_axis_cpl_enqueue_resp_ready(cq_enq_resp_ready),
    .m_axis_cpl_enqueue_commit_op_tag(cq_enq_commit_op_tag),
    .m_axis_cpl_enqueue_commit_valid(cq_enq_commit_valid),
    .m_axis_cpl_enqueue_commit_ready(cq_enq_commit_ready),
    .m_axis_dma_write_desc_dma_addr(ch_desc_dma_addr),
    .m_axis_dma_write_desc_ram_addr(ch_desc_ram_addr),
    .m_axis_dma_write_desc_len(ch_desc_len),
    .m_axis_dma_write_desc_tag(ch_desc_tag),
    .m_axis_dma_write_desc_valid(ch_desc_valid),
    .m_axis_dma_write_desc_ready(ch_desc_ready),
    .s_axis_dma_write_desc_status_tag(ch_status_tag),
    .s_axis_dma_write_desc_status_error(ch_status_error),
    .s_axis_dma_write_desc_status_valid(ch_status_valid),
    .dma_ram_rd_cmd_addr(ch_ram_rd_addr),
    .dma_ram_rd_cmd_valid(ch_ram_rd_valid),
    .dma_ram_rd_cmd_ready(ch_ram_rd_ready),
    .dma_ram_rd_resp_data(ch_ram_rd_resp_data),
    .dma_ram_rd_resp_valid(ch_ram_rd_resp_valid),
    .dma_ram_rd_resp_ready(ch_ram_rd_resp_ready),
    .enable(all_configured)
);

// ---- the completion ring manager -----------------------------------------
cpl_queue_manager #(
    .ADDR_WIDTH(DMA_ADDR_WIDTH),
    .REQ_TAG_WIDTH(CPL_QUEUE_REQ_TAG_WIDTH),
    .OP_TABLE_SIZE(QUEUE_OP_TABLE_SIZE),
    .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .EVENT_WIDTH(EVENT_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .CPL_SIZE(CPL_SIZE),
    .PIPELINE(QUEUE_PIPELINE),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(CQM_AXIL_AW),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH)
)
cq_manager_inst (
    .clk(clk), .rst(rst),
    .s_axis_enqueue_req_queue(cq_enq_req_queue),
    .s_axis_enqueue_req_tag(cq_enq_req_tag),
    .s_axis_enqueue_req_valid(cq_enq_req_valid),
    .s_axis_enqueue_req_ready(cq_enq_req_ready),
    .m_axis_enqueue_resp_queue(cq_enq_resp_queue),
    .m_axis_enqueue_resp_ptr(cq_enq_resp_ptr),
    .m_axis_enqueue_resp_phase(cq_enq_resp_phase),
    .m_axis_enqueue_resp_addr(cq_enq_resp_addr),
    .m_axis_enqueue_resp_event(cq_enq_resp_event),
    .m_axis_enqueue_resp_tag(cq_enq_resp_tag),
    .m_axis_enqueue_resp_op_tag(cq_enq_resp_op_tag),
    .m_axis_enqueue_resp_full(cq_enq_resp_full),
    .m_axis_enqueue_resp_error(cq_enq_resp_error),
    .m_axis_enqueue_resp_valid(cq_enq_resp_valid),
    .m_axis_enqueue_resp_ready(cq_enq_resp_ready),
    .s_axis_enqueue_commit_op_tag(cq_enq_commit_op_tag),
    .s_axis_enqueue_commit_valid(cq_enq_commit_valid),
    .s_axis_enqueue_commit_ready(cq_enq_commit_ready),
    .m_axis_event(cq_event),
    .m_axis_event_source(cq_event_source),
    .m_axis_event_valid(cq_event_valid),
    .m_axis_event_ready(1'b1),
    .s_axil_awaddr(cqm_awaddr), .s_axil_awprot(cqm_awprot),
    .s_axil_awvalid(cqm_awvalid), .s_axil_awready(cqm_awready),
    .s_axil_wdata(cqm_wdata), .s_axil_wstrb(cqm_wstrb),
    .s_axil_wvalid(cqm_wvalid), .s_axil_wready(cqm_wready),
    .s_axil_bresp(cqm_bresp), .s_axil_bvalid(cqm_bvalid),
    .s_axil_bready(cqm_bready),
    .s_axil_araddr({CQM_AXIL_AW{1'b0}}), .s_axil_arprot(3'd0),
    .s_axil_arvalid(1'b0), .s_axil_arready(),
    .s_axil_rdata(cqm_rdata), .s_axil_rresp(cqm_rresp),
    .s_axil_rvalid(cqm_rvalid), .s_axil_rready(1'b1),
    .enable(1'b1)
);

endmodule


// ===========================================================================
// mqnic_axil_qcfg -- the ring driver.
//
// Eight AXI-Lite writes bring one ring up: disable, base low, base high, size,
// linked index, producer pointer, consumer pointer, enable.  After that the
// module sits in RUN and bumps ONE pointer by one whenever the environment
// asks and its own credit account allows -- the producer pointer on a
// descriptor ring (software posting a descriptor), the consumer pointer on a
// completion ring (software retiring a completion).  The shadow pointer is
// this module's own; it never reads one back.
// ===========================================================================
module mqnic_axil_qcfg #(
    parameter CPL               = 0,
    parameter QUEUE_INDEX_WIDTH = 1,
    parameter AXIL_ADDR_WIDTH   = 6,
    parameter LOG_QUEUE_SIZE    = 2,
    parameter LOG_BLOCK_SIZE    = 0,
    parameter [19:0] BASE_HI20  = 20'h00010,
    parameter [31:0] BASE_UPPER = 32'h0000_0000,
    parameter [23:0] LINK_INDEX = 24'd0
)(
    input  wire                              clk,
    input  wire                              rst,

    output wire [AXIL_ADDR_WIDTH-1:0]        m_axil_awaddr,
    output wire [2:0]                        m_axil_awprot,
    output wire                              m_axil_awvalid,
    input  wire                              m_axil_awready,
    output wire [31:0]                       m_axil_wdata,
    output wire [3:0]                        m_axil_wstrb,
    output wire                              m_axil_wvalid,
    input  wire                              m_axil_wready,
    input  wire [1:0]                        m_axil_bresp,
    input  wire                              m_axil_bvalid,
    output wire                              m_axil_bready,

    input  wire                              adv_go,
    input  wire [QUEUE_INDEX_WIDTH-1:0]      adv_queue,
    input  wire [(2**QUEUE_INDEX_WIDTH)-1:0] adv_allowed,

    output wire                              init_done,
    output wire                              adv_fire,
    output wire [QUEUE_INDEX_WIDTH-1:0]      adv_fire_queue
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
            3'd4:    step_data = {8'hC0, LINK_INDEX};                  // CQN / EQN
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
// mqnic_rss_cfg -- writes the receive indirection table.
//
// `mqnic_rx_queue_map` selects a receive ring with
//     indir_tbl_mem[{tid, (tdest & app_mask) + (hash & hash_mask)}]
// and both masks are zero out of reset, so the index is {MAC port, 0}: table
// entries 0 and 2.  Two AXI-Lite writes are the whole of the receive-side
// steering configuration -- MAC port 0 -> receive ring 0, port 1 -> ring 1.
// ===========================================================================
module mqnic_rss_cfg #(
    parameter AXIL_ADDR_WIDTH = 4,
    parameter AXIL_DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        rst,

    output wire [AXIL_ADDR_WIDTH-1:0]  m_axil_awaddr,
    output wire [2:0]                  m_axil_awprot,
    output wire                        m_axil_awvalid,
    input  wire                        m_axil_awready,
    output wire [AXIL_DATA_WIDTH-1:0]  m_axil_wdata,
    output wire [3:0]                  m_axil_wstrb,
    output wire                        m_axil_wvalid,
    input  wire                        m_axil_wready,
    input  wire [1:0]                  m_axil_bresp,
    input  wire                        m_axil_bvalid,
    output wire                        m_axil_bready,

    output wire                        init_done
);

reg [1:0] step_reg;
reg       done_reg;
reg       busy_reg;
reg       aw_done_reg;
reg       w_done_reg;

// table index 0 -> ring 0, table index 2 -> ring 1
wire [AXIL_ADDR_WIDTH-1:0] addr_now = (step_reg == 2'd0)
                                      ? {{(AXIL_ADDR_WIDTH-4){1'b0}}, 4'h0}
                                      : {{(AXIL_ADDR_WIDTH-4){1'b0}}, 4'h8};
wire [AXIL_DATA_WIDTH-1:0] data_now = (step_reg == 2'd0)
                                      ? {AXIL_DATA_WIDTH{1'b0}}
                                      : {{(AXIL_DATA_WIDTH-1){1'b0}}, 1'b1};

assign m_axil_awvalid = busy_reg && !aw_done_reg;
assign m_axil_wvalid  = busy_reg && !w_done_reg;
assign m_axil_awaddr  = addr_now;
assign m_axil_wdata   = data_now;
assign m_axil_wstrb   = 4'hF;
assign m_axil_awprot  = 3'd0;
assign m_axil_bready  = 1'b1;
assign init_done      = done_reg;

always @(posedge clk) begin
    if (rst) begin
        step_reg    <= 2'd0;
        done_reg    <= 1'b0;
        busy_reg    <= 1'b0;
        aw_done_reg <= 1'b0;
        w_done_reg  <= 1'b0;
    end else if (!busy_reg) begin
        if (!done_reg) begin
            busy_reg    <= 1'b1;
            aw_done_reg <= 1'b0;
            w_done_reg  <= 1'b0;
        end
    end else begin
        if (m_axil_awvalid && m_axil_awready) aw_done_reg <= 1'b1;
        if (m_axil_wvalid  && m_axil_wready ) w_done_reg  <= 1'b1;
        if (m_axil_bvalid) begin
            busy_reg <= 1'b0;
            if (step_reg == 2'd1) done_reg <= 1'b1;
            else                  step_reg <= step_reg + 2'd1;
        end
    end
end

endmodule


// ===========================================================================
// mqnic_tx_req_gen -- one transmit request at a time.
//
// Holds queue, tag and destination stable from the cycle the request is
// offered until the cycle the transmit engine takes it, so no AXI-Stream
// source-stability assumption is needed.  A request is only offered for a ring
// the driver has actually posted a descriptor to; otherwise the dequeue comes
// back `empty` and the whole traversal is wasted cover depth.
// ===========================================================================
module mqnic_tx_req_gen #(
    parameter QUEUE_INDEX_WIDTH = 1,
    parameter REQ_TAG_WIDTH     = 3,
    parameter DEST_WIDTH        = 5
)(
    input  wire                          clk,
    input  wire                          rst,

    input  wire                          enable,
    input  wire                          env_go,
    input  wire [QUEUE_INDEX_WIDTH-1:0]  env_queue,
    input  wire                          env_port,
    input  wire [REQ_TAG_WIDTH-1:0]      env_tag,
    input  wire [1:0]                    env_credit,

    output wire [QUEUE_INDEX_WIDTH-1:0]  m_req_queue,
    output wire [REQ_TAG_WIDTH-1:0]      m_req_tag,
    output wire [DEST_WIDTH-1:0]         m_req_dest,
    output wire                          m_req_valid,
    input  wire                          m_req_ready
);

reg                          valid_reg;
reg [QUEUE_INDEX_WIDTH-1:0]  queue_reg;
reg [REQ_TAG_WIDTH-1:0]      tag_reg;
reg [DEST_WIDTH-1:0]         dest_reg;

assign m_req_valid = valid_reg;
assign m_req_queue = queue_reg;
assign m_req_tag   = tag_reg;
assign m_req_dest  = dest_reg;

always @(posedge clk) begin
    if (rst) begin
        valid_reg <= 1'b0;
        queue_reg <= {QUEUE_INDEX_WIDTH{1'b0}};
        tag_reg   <= {REQ_TAG_WIDTH{1'b0}};
        dest_reg  <= {DEST_WIDTH{1'b0}};
    end else begin
        if (valid_reg) begin
            if (m_req_ready) valid_reg <= 1'b0;
        end else if (enable && env_go && env_credit[env_queue]) begin
            valid_reg <= 1'b1;
            queue_reg <= env_queue;
            tag_reg   <= env_tag;
            // tdest[DEST_WIDTH-1] is what tx_fifo's demux routes on
            dest_reg  <= {env_port, {(DEST_WIDTH-1){1'b0}}};
        end
    end
end

endmodule


// ===========================================================================
// mqnic_desc_host_rd -- host memory, descriptor side.
//
// A descriptor is a PURE FUNCTION of the host address it is fetched from:
//
//     bit 17 of the address says which ring family it belongs to;
//     a transmit descriptor asks for 8 or 16 payload bytes, alternating with
//       bit 4 of its own address, from packet buffer 0x4000_0000 | a[15:0]<<8;
//     a receive descriptor offers a 64-byte buffer at
//       0x8000_0000 | a[15:0]<<8;
//     the control word is zero, so the transmit checksum offload is OFF and
//       the payload crosses `tx_checksum` unmodified.
//
// The checker never reads this RAM.  It recomputes the same function from the
// address it saw on the DMA read descriptor wire.
// ===========================================================================
module mqnic_desc_host_rd #(
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_LEN_WIDTH  = 16,
    parameter DMA_TAG_WIDTH  = 4,
    parameter SEG_ADDR_WIDTH = 3,
    parameter SEG_DATA_WIDTH = 128,
    parameter SEG_BE_WIDTH   = 16,
    parameter RAM_ADDR_WIDTH = 7,
    parameter [31:0] MAX_TX_LEN = 32'd16,
    parameter [31:0] MAX_RX_LEN = 32'd64
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

localparam CL_BE   = 4;                       // $clog2(16)
localparam ST_IDLE = 2'd0, ST_WRITE = 2'd1, ST_WAIT = 2'd2, ST_STATUS = 2'd3;

reg [1:0]                     st_reg;
reg [DMA_ADDR_WIDTH-1:0]      addr_reg;
reg [SEG_ADDR_WIDTH-1:0]      wa_reg;
reg [4:0]                     left_reg;
reg [DMA_TAG_WIDTH-1:0]       tag_reg;
reg [1:0]                     delay_reg;

function [127:0] desc_word;
    input [63:0] a;
    reg [31:0] len;
    reg [63:0] pbuf;
    begin
        if (a[17]) begin
            len  = MAX_RX_LEN;
            pbuf = {32'h0000_0000, 32'h8000_0000 | ({16'd0, a[15:0]} << 8)};
        end else begin
            len  = a[4] ? MAX_TX_LEN : (MAX_TX_LEN >> 1);
            pbuf = {32'h0000_0000, 32'h4000_0000 | ({16'd0, a[15:0]} << 8)};
        end
        desc_word = {pbuf, len, 32'h0000_0000};
    end
endfunction

assign s_desc_ready     = (st_reg == ST_IDLE);
assign ram_wr_cmd_valid = (st_reg == ST_WRITE);
assign ram_wr_cmd_be    = {SEG_BE_WIDTH{1'b1}};
assign ram_wr_cmd_addr  = wa_reg;
assign ram_wr_cmd_data  = desc_word(addr_reg);
assign m_status_valid   = (st_reg == ST_STATUS);
assign m_status_tag     = tag_reg;
assign m_status_error   = 4'd0;

wire [4:0] words_in = (s_desc_len[DMA_LEN_WIDTH-1:CL_BE] == 0)
                      ? 5'd1 : s_desc_len[CL_BE+4:CL_BE];

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
                    wa_reg    <= s_desc_ram_addr[RAM_ADDR_WIDTH-1:CL_BE];
                    left_reg  <= words_in;
                    tag_reg   <= s_desc_tag;
                    delay_reg <= env_delay;
                    st_reg    <= ST_WRITE;
                end
            end
            ST_WRITE: begin
                if (ram_wr_cmd_ready) begin
                    addr_reg <= addr_reg + 64'd16;
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
// mqnic_data_host_rd -- host memory, transmit packet side.
//
// Writes `host_word(a) = {a[31:0], ~a[31:0]}` for every 8-byte word the DMA
// read descriptor names.  Each word carries its own address AND that address's
// complement, so the far end can check a packet word without any shadow copy
// of the packet.
// ===========================================================================
module mqnic_data_host_rd #(
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_LEN_WIDTH  = 16,
    parameter DMA_TAG_WIDTH  = 4,
    parameter SEG_ADDR_WIDTH = 5,
    parameter SEG_DATA_WIDTH = 64,
    parameter SEG_BE_WIDTH   = 8,
    parameter RAM_ADDR_WIDTH = 8
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

localparam CL_BE   = 3;                       // $clog2(8)
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

wire [4:0] words_in = (s_desc_len[DMA_LEN_WIDTH-1:CL_BE] == 0)
                      ? 5'd1 : s_desc_len[CL_BE+4:CL_BE];

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
                    wa_reg    <= s_desc_ram_addr[RAM_ADDR_WIDTH-1:CL_BE];
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
// mqnic_host_wr -- host memory, write side.
//
// Reads the words the DMA write descriptor names out of the design's RAM,
// publishes each as `host_wr_*` -- the far observation point -- waits a
// bounded number of cycles and returns status.  Two instances: the receive
// packet data (8-byte words) and the completion writeback (32-byte words).
// ===========================================================================
module mqnic_host_wr #(
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_LEN_WIDTH  = 16,
    parameter DMA_TAG_WIDTH  = 4,
    parameter SEG_ADDR_WIDTH = 5,
    parameter SEG_DATA_WIDTH = 64,
    parameter SEG_BE_WIDTH   = 8,
    parameter RAM_ADDR_WIDTH = 8
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

localparam CL_BE = (SEG_BE_WIDTH == 32) ? 5 : 3;

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

wire [4:0] words_in = (s_desc_len[DMA_LEN_WIDTH-1:CL_BE] == 0)
                      ? 5'd1 : s_desc_len[CL_BE+4:CL_BE];

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
                    ra_reg    <= s_desc_ram_addr[RAM_ADDR_WIDTH-1:CL_BE];
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
                    addr_reg     <= addr_reg + (64'd1 << CL_BE);
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


// ===========================================================================
// mqnic_mac_loopback -- one MAC port.
//
// A wire from the transmit frame buffer to the receive frame buffer, with two
// jobs a real MAC also has:
//
//  * it can BACK-PRESSURE, but only for three consecutive cycles.  That bound
//    is what makes the fairness, bounded-response and deadlock candidates mean
//    something; with an unbounded link stall every one of them is false.
//  * it returns the TRANSMIT COMPLETION.  `tx_engine` marks each frame's
//    `tuser[TX_TAG_WIDTH:1]` with its own descriptor-table slot and will not
//    start the completion enqueue until that tag comes back, which in the real
//    design is the port's PTP timestamp path.  Here the loopback samples the
//    tag at the frame's last beat and hands it straight back.
// ===========================================================================
module mqnic_mac_loopback #(
    parameter DATA_WIDTH    = 32,
    parameter KEEP_WIDTH    = 4,
    parameter TX_USER_WIDTH = 4,
    parameter RX_USER_WIDTH = 1,
    parameter TX_TAG_WIDTH  = 3
)(
    input  wire                        clk,
    input  wire                        rst,

    input  wire [DATA_WIDTH-1:0]       s_tdata,
    input  wire [KEEP_WIDTH-1:0]       s_tkeep,
    input  wire                        s_tvalid,
    output wire                        s_tready,
    input  wire                        s_tlast,
    input  wire [TX_USER_WIDTH-1:0]    s_tuser,

    output wire [DATA_WIDTH-1:0]       m_tdata,
    output wire [KEEP_WIDTH-1:0]       m_tkeep,
    output wire                        m_tvalid,
    input  wire                        m_tready,
    output wire                        m_tlast,
    output wire [RX_USER_WIDTH-1:0]    m_tuser,

    output wire [TX_TAG_WIDTH-1:0]     cpl_tag,
    output wire                        cpl_valid,
    input  wire                        cpl_ready,

    input  wire                        env_stall
);

reg [1:0]                stall_cnt_reg;
reg                      cpl_valid_reg;
reg [TX_TAG_WIDTH-1:0]   cpl_tag_reg;

wire allow_stall = (stall_cnt_reg != 2'd3);
wire gate        = env_stall && allow_stall;
wire blocked     = s_tlast && cpl_valid_reg && !cpl_ready;

assign m_tdata  = s_tdata;
assign m_tkeep  = s_tkeep;
assign m_tlast  = s_tlast;
assign m_tuser  = {RX_USER_WIDTH{1'b0}};      // the MAC delivers a good frame
assign m_tvalid = s_tvalid && !gate && !blocked;
assign s_tready = m_tready && !gate && !blocked;

assign cpl_tag   = cpl_tag_reg;
assign cpl_valid = cpl_valid_reg;

wire beat_last = s_tvalid && s_tready && s_tlast;

always @(posedge clk) begin
    if (rst) begin
        stall_cnt_reg <= 2'd0;
        cpl_valid_reg <= 1'b0;
        cpl_tag_reg   <= {TX_TAG_WIDTH{1'b0}};
    end else begin
        if (s_tvalid && gate) begin
            if (stall_cnt_reg != 2'd3) stall_cnt_reg <= stall_cnt_reg + 2'd1;
        end else begin
            stall_cnt_reg <= 2'd0;
        end

        if (beat_last) begin
            cpl_valid_reg <= 1'b1;
            cpl_tag_reg   <= s_tuser[TX_TAG_WIDTH:1];
        end else if (cpl_valid_reg && cpl_ready) begin
            cpl_valid_reg <= 1'b0;
        end
    end
end

endmodule


// ===========================================================================
// mqnic_txcpl_merge -- two MAC ports, one transmit completion port.
//
// Round robin, one grant per handshake.  `tx_engine` holds its completion
// ready high, so this drains in a cycle; it exists so neither port can lose a
// completion to the other.
// ===========================================================================
module mqnic_txcpl_merge #(
    parameter TAG_WIDTH = 3
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire [TAG_WIDTH-1:0]    s0_tag,
    input  wire                    s0_valid,
    output wire                    s0_ready,

    input  wire [TAG_WIDTH-1:0]    s1_tag,
    input  wire                    s1_valid,
    output wire                    s1_ready,

    output wire [TAG_WIDTH-1:0]    m_tag,
    output wire                    m_valid,
    input  wire                    m_ready
);

reg last_sel_reg;

wire pick1 = s1_valid && (!s0_valid || last_sel_reg == 1'b0);

assign m_valid  = s0_valid || s1_valid;
assign m_tag    = pick1 ? s1_tag : s0_tag;
assign s0_ready = m_ready && !pick1 && s0_valid;
assign s1_ready = m_ready && pick1;

always @(posedge clk) begin
    if (rst) begin
        last_sel_reg <= 1'b0;
    end else if (m_valid && m_ready) begin
        last_sel_reg <= pick1;
    end
end

endmodule

`resetall
