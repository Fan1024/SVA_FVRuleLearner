// ===========================================================================
// Candidate target assertions for the OpenTitan spi_device command-upload
// subsystem.
//
//   SPI pins -> spi_s2p -> spi_cmdparse -> spid_upload -> DPSRAM -> arbiter
//                                 |                                   |
//                                 +-> spid_status <- prim_fifo_async -+
//
// Instantiated inside `opentitan_spi_device_fifo_ft` as `u_targets`, so every
// reference below is an absolute hierarchical name from the formal top.
// Nothing here is an assumption.
//
// WHAT THE ORACLES ARE.  Four shadow queues and a set of saturating counters,
// all of them this file's own arithmetic:
//
//   A  CMD FIFO SHADOW -- a 16-deep copy of the 16-bit words the SPI clock
//      domain pushed into `spid_upload.u_cmdfifo`, with this file's own push
//      and pop counters.  The design's copy lives in the dual-port SRAM and is
//      addressed by GRAY-CODED pointers that cross the clock boundary through
//      two 2-flop synchronisers; nothing below is read from `w_wptr_q`,
//      `r_rptr_q`, `rdepth_o` or `stored` except where a target deliberately
//      COMPARES the design's pointer against this file's count, and those rows
//      say so in `lists/targets.txt`.
//
//   B  ADDR FIFO SHADOW -- the same, 32 bits wide, for `u_addrfifo`.
//
//   C  PAYLOAD SHADOW -- this file's own copy of the first 16 payload bytes of
//      the current SPI transaction and its own byte index, compared against
//      the SRAM write the packer issues and against the word the bus side
//      reads back out of the SRAM.
//
//   D  STATUS SYNC SHADOW -- a 2-deep copy of the 24-bit FLASH_STATUS words
//      the bus clock domain pushed into `spid_status.u_sw_status_update_sync`,
//      a `prim_fifo_async` running the OTHER way (bus -> SPI).
//
//   E  SATURATING WAIT COUNTERS.  That is how the fairness, bounded-response
//      and deadlock obligations are written as SAFETY properties.  There is no
//      `s_eventually` in this file and there must not be: the reset cut admits
//      states not reachable from reset, so a liveness property is either false
//      or vacuous.
//
// WHERE THE ORACLE DOES READ A DESIGN WIRE.  The push events.  A shadow needs
// to know WHEN a word entered the FIFO, and that is
// `cmdfifo_wvalid && cmdfifo_wready` (and the two siblings) and nothing else --
// the same shape as `tasks/l15_l2_mshr_onehot`'s shadow of the L1.5 NOC1
// command buffer, which takes the design's push and pop events and keeps its
// own pointers, occupancy and payload copy.  The PAYLOAD, the ORDER, the
// COUNTS and the OCCUPANCY below are this file's own, and every comparison
// happens at the FORMAL TOP's boundary (`cmdfifo_rdata_o` at
// `cmdfifo_rvalid_o && cmdfifo_rready_i`), not inside the design.
//
// WHY THE CMD/ADDR FIFO TARGETS ARE HARD.  Between the push and the pop sit:
// the gray encode, a 2-flop synchroniser, the gray decode, the read-side
// pointer, an SRAM read request through a round-robin `prim_sram_arbiter`
// SHARED WITH AN UNCONSTRAINED SOFTWARE PORT, a 2-cycle SRAM pipeline, and the
// `stored`/`r_sram_rvalid` holding register.  The software port
// (`fw_req_i`/`fw_write_i`/`fw_addr_i`/`fw_wdata_i`) is FREE: it may hammer
// the arbiter and it may write anywhere.  `T_DATA_CMDFIFO_POP_EQ_PUSH` is
// therefore also the statement that software cannot corrupt an uploaded
// command -- `spid_dpram` routes bus-side writes to the egress memory only.
// ===========================================================================

`default_nettype none

`define FT    opentitan_spi_device_fifo_ft
`define UPL   opentitan_spi_device_fifo_ft.u_upload
`define CFIFO opentitan_spi_device_fifo_ft.u_upload.u_cmdfifo
`define AFIFO opentitan_spi_device_fifo_ft.u_upload.u_addrfifo
`define PBUF  opentitan_spi_device_fifo_ft.u_upload.u_payload_buffer
`define STAT  opentitan_spi_device_fifo_ft.u_spid_status
`define SFIFO opentitan_spi_device_fifo_ft.u_spid_status.u_sw_status_update_sync

module spi_device_fifo_targets
  import spi_device_pkg::*;
(
  input wire logic clk_i,
  input wire logic rst_ni
);

  // -------------------------------------------------------------------------
  // Sizes.  Restated here rather than read out of the design, so that a target
  // about a bound is a statement about the bound and not a tautology.
  // -------------------------------------------------------------------------
  localparam int unsigned CDepth   = 16;   // SramCmdFifoDepth
  localparam int unsigned ADepth   = 16;   // SramAddrFifoDepth
  localparam int unsigned SDepth   = 2;    // spid_status sync FIFO depth
  localparam int unsigned PlShadow = 16;   // payload bytes this file shadows
  localparam int unsigned RdQDepth = 4;    // prim_sram_arbiter response FIFO

  // The four opcodes the formal top configures with `upload` set.  A word that
  // leaves the command FIFO must carry one of them in its low byte.
  localparam logic [7:0] OpPageProgram = 8'h02;
  localparam logic [7:0] OpSectorErase = 8'h20;
  localparam logic [7:0] OpChipErase   = 8'hc7;
  localparam logic [7:0] OpWriteStatus = 8'h01;

  // The ingress window: everything the SPI clock domain is allowed to write.
  localparam int unsigned IngressWords = SramPayloadDepth + SramCmdFifoDepth
                                       + SramAddrFifoDepth + SramTpmWrFifoDepth;

  // -------------------------------------------------------------------------
  // Boot guard.  `spid_status`'s async FIFO is held in reset by
  // `status_fifo_clr_n`, a flop that is 0 under reset and 1 from the first
  // edge after reset release, and the free software inputs are live from cycle
  // 0.  `started` is the SAME one-cycle shape, so this file's status shadow
  // opens on exactly the cycle the design's FIFO does; a shadow that opened
  // earlier would be one push ahead for a reason that is not the design's.
  // -------------------------------------------------------------------------
  logic started;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) started <= 1'b0;
    else         started <= 1'b1;
  end

  // -------------------------------------------------------------------------
  // The events, taken at the two FIFO boundaries
  // -------------------------------------------------------------------------
  logic cmd_push, cmd_pop;
  logic addr_push, addr_pop;
  logic pl_push;
  logic st_push, st_pop;

  assign cmd_push  = started & `UPL.cmdfifo_wvalid  & `UPL.cmdfifo_wready;
  assign cmd_pop   = started & `FT.cmdfifo_rvalid_o & `FT.cmdfifo_rready_i;
  assign addr_push = started & `UPL.addrfifo_wvalid & `UPL.addrfifo_wready;
  assign addr_pop  = started & `FT.addrfifo_rvalid_o & `FT.addrfifo_rready_i;
  assign pl_push   = started & `UPL.payload_wvalid  & `UPL.payload_wready;
  assign st_push   = started & `FT.sys_status_we_i  & `SFIFO.wready_o;
  assign st_pop    = started & `STAT.sck_sw_we      & `STAT.sck_sw_ack;

  // -------------------------------------------------------------------------
  // Oracle A -- the command FIFO shadow
  // -------------------------------------------------------------------------
  logic [15:0] cq_data [CDepth];
  logic [15:0] cq_push_cnt, cq_pop_cnt;
  logic [15:0] cq_occ;

  assign cq_occ = cq_push_cnt - cq_pop_cnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cq_push_cnt <= 16'd0;
      cq_pop_cnt  <= 16'd0;
      for (int unsigned i = 0 ; i < CDepth ; i++) cq_data[i] <= 16'd0;
    end else begin
      if (cmd_push) begin
        cq_data[cq_push_cnt[3:0]] <= `UPL.cmdfifo_wdata;
        cq_push_cnt               <= cq_push_cnt + 16'd1;
      end
      if (cmd_pop) cq_pop_cnt <= cq_pop_cnt + 16'd1;
    end
  end

  // -------------------------------------------------------------------------
  // Oracle B -- the address FIFO shadow
  // -------------------------------------------------------------------------
  logic [31:0] aq_data [ADepth];
  logic [15:0] aq_push_cnt, aq_pop_cnt;
  logic [15:0] aq_occ;

  assign aq_occ = aq_push_cnt - aq_pop_cnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aq_push_cnt <= 16'd0;
      aq_pop_cnt  <= 16'd0;
      for (int unsigned i = 0 ; i < ADepth ; i++) aq_data[i] <= 32'd0;
    end else begin
      if (addr_push) begin
        aq_data[aq_push_cnt[3:0]] <= `UPL.addrfifo_wdata;
        aq_push_cnt               <= aq_push_cnt + 16'd1;
      end
      if (addr_pop) aq_pop_cnt <= aq_pop_cnt + 16'd1;
    end
  end

  // -------------------------------------------------------------------------
  // Oracle C -- the payload shadow
  //
  // `spid_fifo2sram_adapter`'s pointer and `spid_dpram`'s `initialized_words_q`
  // are both reset by the SPI-domain reset, i.e. by CSb de-assertion, so the
  // shadow is cleared on the same event.  A word whose four lanes were all
  // written in the CURRENT transaction is exactly those four bytes in the
  // memory; a word left over from a previous transaction is not, because the
  // first write to it zero-fills the other lanes.  `pl_quiet` keeps the read
  // comparison away from the 3-cycle write pipeline.
  // -------------------------------------------------------------------------
  logic [7:0]           pl_data [PlShadow];
  logic [PlShadow-1:0]  pl_valid;
  logic [7:0]           pl_idx;
  logic [3:0]           pl_quiet;
  logic [PlShadow-1:0]  pl_valid_d1, pl_valid_d2;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pl_idx      <= 8'd0;
      pl_valid    <= '0;
      pl_valid_d1 <= '0;
      pl_valid_d2 <= '0;
      pl_quiet    <= 4'hf;
      for (int unsigned i = 0 ; i < PlShadow ; i++) pl_data[i] <= 8'd0;
    end else begin
      pl_valid_d1 <= pl_valid;
      pl_valid_d2 <= pl_valid_d1;
      if (!`FT.rst_spi_n) begin
        // CSb de-asserted: a new transaction restarts the payload buffer.
        pl_idx   <= 8'd0;
        pl_valid <= '0;
        pl_quiet <= 4'hf;
      end else begin
        if (pl_push) begin
          if (pl_idx < 8'(PlShadow)) begin
            pl_data[pl_idx[3:0]] <= `UPL.payload_wdata;
            pl_valid[pl_idx[3:0]] <= 1'b1;
          end
          pl_idx   <= pl_idx + 8'd1;
          pl_quiet <= 4'd0;
        end else if (pl_quiet != 4'hf) begin
          pl_quiet <= pl_quiet + 4'd1;
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Oracle D -- the bus -> SPI status sync FIFO shadow
  // -------------------------------------------------------------------------
  logic [23:0] sq_data [SDepth];
  logic [15:0] sq_push_cnt, sq_pop_cnt;
  logic [15:0] sq_occ;

  assign sq_occ = sq_push_cnt - sq_pop_cnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sq_push_cnt <= 16'd0;
      sq_pop_cnt  <= 16'd0;
      for (int unsigned i = 0 ; i < SDepth ; i++) sq_data[i] <= 24'd0;
    end else begin
      if (st_push) begin
        sq_data[sq_push_cnt[0]] <= `FT.sys_status_i;
        sq_push_cnt             <= sq_push_cnt + 16'd1;
      end
      if (st_pop) sq_pop_cnt <= sq_pop_cnt + 16'd1;
    end
  end

  // -------------------------------------------------------------------------
  // Oracle C' -- this file's own queue of the addresses the bus-side SRAM
  // read pipeline owes a response for.  `prim_ram_1r1w_async_adv` is a fixed
  // latency pipeline, so responses come back in issue order.
  // -------------------------------------------------------------------------
  logic [SramAw-1:0] rq_addr [RdQDepth];
  logic [15:0]       rq_push_cnt, rq_pop_cnt;
  logic [15:0]       rq_occ;
  logic              rd_issue, rd_return;

  assign rd_issue  = started & `FT.mem_a_req & ~`FT.mem_a_write;
  assign rd_return = started & `FT.mem_a_rvalid;
  assign rq_occ    = rq_push_cnt - rq_pop_cnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rq_push_cnt <= 16'd0;
      rq_pop_cnt  <= 16'd0;
      for (int unsigned i = 0 ; i < RdQDepth ; i++) rq_addr[i] <= '0;
    end else begin
      if (rd_issue) begin
        rq_addr[rq_push_cnt[1:0]] <= `FT.mem_a_addr;
        rq_push_cnt               <= rq_push_cnt + 16'd1;
      end
      if (rd_return) rq_pop_cnt <= rq_pop_cnt + 16'd1;
    end
  end

  // The word index inside the payload region that the returning read is for.
  logic [SramAw-1:0] rq_head_addr;
  logic              rq_head_is_payload;
  logic [1:0]        rq_head_word;

  assign rq_head_addr       = rq_addr[rq_pop_cnt[1:0]];
  assign rq_head_word       = rq_head_addr[1:0];
  assign rq_head_is_payload = (rq_head_addr >= SramPayloadIdx)
                            && (rq_head_addr < (SramPayloadIdx + 4));

  // -------------------------------------------------------------------------
  // Oracle E -- the saturating wait counters
  // -------------------------------------------------------------------------
  logic [7:0] fw_arb_wait;      // bus arbiter, software port
  logic [7:0] pl_arb_wait;      // SPI arbiter, payload port
  logic [7:0] rd_wait;          // an outstanding bus-side SRAM read
  logic [7:0] cmd_vis_wait;     // pushed but not yet visible to the reader
  logic [7:0] cmd_drain_wait;   // reader ready, entries present, no pop
  logic [7:0] addr_drain_wait;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fw_arb_wait     <= 8'd0;
      pl_arb_wait     <= 8'd0;
      rd_wait         <= 8'd0;
      cmd_vis_wait    <= 8'd0;
      cmd_drain_wait  <= 8'd0;
      addr_drain_wait <= 8'd0;
    end else begin
      // fairness: requesting and not granted
      if (`FT.sys_sram_req[0] && !`FT.sys_sram_gnt[0])
        fw_arb_wait <= (fw_arb_wait == 8'hff) ? fw_arb_wait : fw_arb_wait + 8'd1;
      else
        fw_arb_wait <= 8'd0;

      if (`UPL.sck_sram_req[2] && !`UPL.sck_sram_gnt[2])
        pl_arb_wait <= (pl_arb_wait == 8'hff) ? pl_arb_wait : pl_arb_wait + 8'd1;
      else
        pl_arb_wait <= 8'd0;

      // bounded response: a read is outstanding and has not come back
      if ((rq_push_cnt != rq_pop_cnt) && !rd_return)
        rd_wait <= (rd_wait == 8'hff) ? rd_wait : rd_wait + 8'd1;
      else
        rd_wait <= 8'd0;

      // bounded response: pushed on the SPI side, not yet offered on the bus
      if (started && (cq_push_cnt != cq_pop_cnt) && !`FT.cmdfifo_rvalid_o)
        cmd_vis_wait <= (cmd_vis_wait == 8'hff) ? cmd_vis_wait : cmd_vis_wait + 8'd1;
      else
        cmd_vis_wait <= 8'd0;

      // deadlock: the reader is ready and there is something to give it
      if (started && `FT.cmdfifo_rready_i && (cq_push_cnt != cq_pop_cnt) && !cmd_pop)
        cmd_drain_wait <= (cmd_drain_wait == 8'hff) ? cmd_drain_wait
                                                    : cmd_drain_wait + 8'd1;
      else
        cmd_drain_wait <= 8'd0;

      if (started && `FT.addrfifo_rready_i && (aq_push_cnt != aq_pop_cnt) && !addr_pop)
        addr_drain_wait <= (addr_drain_wait == 8'hff) ? addr_drain_wait
                                                      : addr_drain_wait + 8'd1;
      else
        addr_drain_wait <= 8'd0;
    end
  end

  // -------------------------------------------------------------------------
  // Helper wires
  // -------------------------------------------------------------------------
  logic [9:0] dp_sel_bits;
  assign dp_sel_bits = `FT.cmd_dp_sel;

  // The TRUE (unsynchronised) pointer gap of the command FIFO: the write
  // pointer in the SPI domain against the read pointer in the bus domain.
  // PtrW is $clog2(16)+1 = 5, msb is the phase bit.
  logic [4:0] cq_wp_raw, cq_rp_raw;
  logic [5:0] cq_true_gap;
  assign cq_wp_raw = `CFIFO.w_wptr_q;
  assign cq_rp_raw = `CFIFO.r_rptr_q;
  assign cq_true_gap = (cq_wp_raw[4] == cq_rp_raw[4])
                     ? (6'({1'b0, cq_wp_raw[3:0]}) - 6'({1'b0, cq_rp_raw[3:0]}))
                     : (6'd16 + 6'({1'b0, cq_wp_raw[3:0]})
                              - 6'({1'b0, cq_rp_raw[3:0]}));

  // The lane the payload packer is writing this cycle.
  logic [7:0] pl_sram_lane_byte;
  assign pl_sram_lane_byte =
      8'(`UPL.sck_sram_wdata[2] >> (8 * {29'd0, pl_idx[1:0]}));

  logic [3:0] pl_sram_strb;
  assign pl_sram_strb = sram_mask2strb(`UPL.sck_sram_wmask[2]);

  // The four payload bytes this file says word `rq_head_word` holds.
  logic [31:0] pl_expected_word;
  logic        pl_word_complete;
  assign pl_expected_word = {pl_data[{rq_head_word, 2'd3}],
                             pl_data[{rq_head_word, 2'd2}],
                             pl_data[{rq_head_word, 2'd1}],
                             pl_data[{rq_head_word, 2'd0}]};
  assign pl_word_complete = pl_valid_d2[{rq_head_word, 2'd3}]
                          & pl_valid_d2[{rq_head_word, 2'd2}]
                          & pl_valid_d2[{rq_head_word, 2'd1}]
                          & pl_valid_d2[{rq_head_word, 2'd0}];

  // The opcode carried in a command FIFO word.
  logic [7:0] cq_pop_opcode;
  assign cq_pop_opcode = `FT.cmdfifo_rdata_o[7:0];

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // =========================================================================
  // 1 -- END-TO-END ORDERING
  // =========================================================================

  // ORACLE: the reader consumes command FIFO slots in the order the SPI side
  // filled them, so the design's own read pointer (bus domain, binary, low 4
  // bits) has to track this file's independent pop count modulo the depth.
  // Any reordering, any skipped slot, any double-consume moves them apart.
  T_ORDER_CMDFIFO_RPTR_TRACKS_POP_COUNT: assert property (
    started |-> (`CFIFO.r_rptr_q[3:0] == cq_pop_cnt[3:0]));

  // ORACLE: same for the address FIFO.
  T_ORDER_ADDRFIFO_RPTR_TRACKS_POP_COUNT: assert property (
    started |-> (`AFIFO.r_rptr_q[3:0] == aq_pop_cnt[3:0]));

  // ORACLE: `spid_upload`'s FSM pushes the opcode word at the 8th SCK beat and
  // the address word only after the address has been shifted in, so a command
  // is always in the command FIFO before its address is in the address FIFO.
  // A command without an address pushes only the first, never the second.
  T_ORDER_CMD_PUSH_PRECEDES_ADDR_PUSH: assert property (
    addr_push |-> (cq_push_cnt > aq_push_cnt));

  // =========================================================================
  // 2 -- DATA INTEGRITY
  // =========================================================================

  // ORACLE: the 16-bit word the bus side pops is the word this file recorded
  // at the SPI-side push of the same index.  This is the headline target: the
  // value has to survive the gray encode, the 2-flop synchroniser, the SRAM
  // write, the round-robin arbiter shared with a FREE software port, the SRAM
  // read pipeline and the `stored` holding register.
  T_DATA_CMDFIFO_POP_EQ_PUSH: assert property (
    (cmd_pop && (cq_push_cnt != cq_pop_cnt)) |->
      (`FT.cmdfifo_rdata_o == cq_data[cq_pop_cnt[3:0]]));

  // ORACLE: the same for the 32-bit address word.
  T_DATA_ADDRFIFO_POP_EQ_PUSH: assert property (
    (addr_pop && (aq_push_cnt != aq_pop_cnt)) |->
      (`FT.addrfifo_rdata_o == aq_data[aq_pop_cnt[3:0]]));

  // ORACLE: the FLASH_STATUS word the SPI clock domain receives is the word
  // software wrote, in order.  This is the CDC running the OTHER way, through
  // `prim_fifo_async`.
  T_DATA_STATUS_SYNC_POP_EQ_PUSH: assert property (
    (st_pop && (sq_push_cnt != sq_pop_cnt)) |->
      (`STAT.sck_sw_status == sq_data[sq_pop_cnt[0]]));

  // ORACLE: `spid_fifo2sram_adapter` packs four SPI bytes into one SRAM word.
  // The byte it puts on the SRAM write bus has to be the byte the host just
  // shifted in, in the lane this file's own index selects.
  T_DATA_PAYLOAD_SRAM_LANE_IS_PUSHED_BYTE: assert property (
    (pl_push && `FT.rst_spi_n) |->
      (pl_sram_lane_byte == `UPL.payload_wdata));

  // ORACLE: and it has to go to the word this file's own byte index names,
  // offset from the payload region base.
  T_DATA_PAYLOAD_SRAM_ADDR_IS_INDEX: assert property (
    (pl_push && `FT.rst_spi_n) |->
      (`UPL.sck_sram_addr[2] == (SramPayloadIdx + SramAw'({2'd0, pl_idx[7:2]}))));

  // ORACLE: a payload word whose four lanes were all written in this
  // transaction reads back on the BUS side as those four bytes.  The read
  // crosses the async dual-port SRAM in the opposite direction from the
  // pointers; `pl_quiet` keeps the comparison clear of the 3-cycle write
  // pipeline, and `pl_valid_d2` of the same.
  T_DATA_PAYLOAD_SYS_READ_EQ_SHADOW: assert property (
    (rd_return && rq_head_is_payload && pl_word_complete
     && (pl_quiet >= 4'd4) && `FT.rst_spi_n) |->
      (`FT.mem_a_rdata == pl_expected_word));

  // =========================================================================
  // 3 -- UNIQUENESS / NO DUPLICATION
  // =========================================================================

  // ORACLE: the bus side never delivers more command words than the SPI side
  // pushed -- no word is delivered twice and none is invented.
  T_UNIQ_CMDFIFO_POPS_LE_PUSHES: assert property (
    started |-> (cq_pop_cnt <= cq_push_cnt));

  // ORACLE: the packer writes exactly one byte lane per push, so the write
  // strobe it puts on the SRAM bus is one-hot.  Two lanes at once would mean
  // one payload byte landed in two places.
  T_UNIQ_PAYLOAD_LANE_STRB_ONEHOT: assert property (
    pl_push |-> $onehot(pl_sram_strb));

  // =========================================================================
  // 4 -- NO LOSS / CONSERVATION
  // =========================================================================

  // ORACLE: the design's SPI-domain write pointer counts exactly the pushes
  // this file counted, modulo the depth.  A dropped or duplicated push shows
  // up here even if the reader never looks.
  T_CONSERV_CMDFIFO_WPTR_EQ_PUSH_COUNT: assert property (
    started |-> (`CFIFO.w_wptr_q[3:0] == cq_push_cnt[3:0]));

  // ORACLE: the status sync FIFO delivers no more than software wrote.
  T_CONSERV_STATUS_POPS_LE_PUSHES: assert property (
    started |-> (sq_pop_cnt <= sq_push_cnt));

  // ORACLE: the SRAM returns no more read responses than the arbiter issued
  // read requests.  Conservation across the bus-side memory pipeline.
  T_CONSERV_SYS_SRAM_RVALID_LE_READS: assert property (
    started |-> (rq_pop_cnt <= rq_push_cnt));

  // =========================================================================
  // 5 -- MUTUAL EXCLUSION / ONE-HOT
  // =========================================================================

  // ORACLE: `spid_upload`'s FSM is in exactly one of StIdle/StAddress/
  // StPayload, so at most one of its three SRAM clients can be pushing.  Two
  // at once would collide in the SPI-side arbiter and one push would be lost.
  // (This is upstream's own `FifosOnlyOneValid_A`, which SYNTHESIS removes.)
  T_MUTEX_UPLOAD_WVALID_ONEHOT0: assert property (
    $onehot0({`UPL.cmdfifo_wvalid, `UPL.addrfifo_wvalid, `UPL.payload_wvalid}));

  // ORACLE: an arbiter grants one requester per cycle.
  T_MUTEX_SCK_SRAM_GNT_ONEHOT0: assert property ($onehot0(`UPL.sck_sram_gnt));

  T_MUTEX_SYS_SRAM_GNT_ONEHOT0: assert property ($onehot0(`FT.sys_sram_gnt));

  // ORACLE: `sel_datapath_e` is a one-hot encoding and `spi_cmdparse` selects
  // at most one downstream datapath.  Two selected would let two blocks drive
  // the SPI-side SRAM mux and the p2s mux at once.
  T_MUTEX_CMD_DP_SEL_ONEHOT0: assert property ($onehot0(dp_sel_bits));

  // =========================================================================
  // 6 -- OCCUPANCY AND BOUNDS
  // =========================================================================

  // ORACLE: this file's independent occupancy never exceeds the configured
  // depth.  The write side is supposed to stall on `w_full`, which it computes
  // from a read pointer that has crossed the clock boundary and is therefore
  // STALE -- if the staleness is mishandled the FIFO overruns and this is what
  // catches it.
  T_BOUND_CMDFIFO_OCC_LE_DEPTH: assert property (
    started |-> (cq_occ <= 16'(CDepth)));

  T_BOUND_ADDRFIFO_OCC_LE_DEPTH: assert property (
    started |-> (aq_occ <= 16'(ADepth)));

  // ORACLE: the depth the design reports on the READ side is computed from the
  // synchronised (delayed) write pointer, so it can only ever be at or behind
  // this file's true occupancy.  Ahead of it would mean the reader believes in
  // entries that were never pushed.
  T_BOUND_CMDFIFO_RDEPTH_LE_OCC: assert property (
    started |-> (16'({11'd0, `CFIFO.rdepth_o}) <= cq_occ));

  // ORACLE: and neither reported depth may exceed the array that holds it.
  T_BOUND_CMDFIFO_WDEPTH_LE_DEPTH: assert property (
    `CFIFO.wdepth_o <= 5'(CDepth));

  T_BOUND_ADDRFIFO_RDEPTH_LE_DEPTH: assert property (
    `AFIFO.rdepth_o <= 5'(ADepth));

  // ORACLE: the status sync FIFO is two deep.
  T_BOUND_STATUS_SYNC_OCC_LE_DEPTH: assert property (
    started |-> (sq_occ <= 16'(SDepth)));

  // ORACLE: `prim_sram_arbiter` steers read responses through a 4-deep FIFO,
  // so it can never have more than four reads in flight without losing one.
  T_BOUND_SYS_SRAM_OUTSTANDING_LE_4: assert property (
    started |-> (rq_occ <= 16'(RdQDepth)));

  // =========================================================================
  // 7 -- ALLOCATOR DISCIPLINE
  // =========================================================================

  // ORACLE: a FIFO slot is allocated by a push and by nothing else.  The write
  // pointer must not move on a cycle this file saw no accepted push, and must
  // move by exactly one when it did.
  T_ALLOC_CMDFIFO_WPTR_ONLY_ON_PUSH: assert property (
    (started && !cmd_push) |=> $stable(`CFIFO.w_wptr_q));

  T_ALLOC_CMDFIFO_WPTR_STEPS_BY_ONE: assert property (
    cmd_push |=> (`CFIFO.w_wptr_q == ($past(`CFIFO.w_wptr_q) + 5'd1)));

  // ORACLE: the payload packer's circular pointer advances by exactly one word
  // slot per granted SRAM write and wraps at the end of the buffer.
  T_ALLOC_PAYLOAD_FIFOPTR_STEPS_BY_ONE: assert property (
    (pl_push && `FT.rst_spi_n) |=>
      (!`FT.rst_spi_n
       || (`PBUF.fifoptr == (($past(`PBUF.fifoptr) == 8'd255)
                              ? 8'd0 : ($past(`PBUF.fifoptr) + 8'd1)))));

  // =========================================================================
  // 8 -- REQUEST-RESPONSE CORRESPONDENCE
  // =========================================================================

  // ORACLE: the bus side is never offered a command word this file did not see
  // pushed on the SPI side.  An unsolicited `rvalid` here would be the reader
  // consuming stale SRAM contents -- including anything the free software port
  // wrote.
  T_REQRSP_CMDFIFO_RVALID_IMPLIES_PUSHED: assert property (
    (started && `FT.cmdfifo_rvalid_o) |-> (cq_push_cnt != cq_pop_cnt));

  T_REQRSP_ADDRFIFO_RVALID_IMPLIES_PUSHED: assert property (
    (started && `FT.addrfifo_rvalid_o) |-> (aq_push_cnt != aq_pop_cnt));

  // ORACLE: the SPI clock domain is never handed a status word software did
  // not write.
  T_REQRSP_STATUS_RVALID_IMPLIES_PUSHED: assert property (
    (started && `STAT.sck_sw_we) |-> (sq_push_cnt != sq_pop_cnt));

  // ORACLE: every SRAM read response answers a read this file saw issued.
  T_REQRSP_SYS_SRAM_RVALID_SOLICITED: assert property (
    rd_return |-> (rq_push_cnt != rq_pop_cnt));

  // =========================================================================
  // 9 -- PROTOCOL CONFORMANCE
  // =========================================================================

  // ORACLE: a FIFO read interface may not withdraw `rvalid` without a
  // handshake.  In this FIFO that is what the `stored` register exists for --
  // the SRAM data arrives one cycle after the request and has to be held.
  T_PROTO_CMDFIFO_RVALID_STABLE: assert property (
    (`FT.cmdfifo_rvalid_o && !`FT.cmdfifo_rready_i) |=> `FT.cmdfifo_rvalid_o);

  // ORACLE: and the data may not change under a held `rvalid`.
  T_PROTO_CMDFIFO_RDATA_STABLE: assert property (
    (`FT.cmdfifo_rvalid_o && !`FT.cmdfifo_rready_i) |=>
      $stable(`FT.cmdfifo_rdata_o));

  T_PROTO_ADDRFIFO_RVALID_STABLE: assert property (
    (`FT.addrfifo_rvalid_o && !`FT.addrfifo_rready_i) |=> `FT.addrfifo_rvalid_o);

  // ORACLE: the SPI clock domain owns the INGRESS window of the SRAM and
  // nothing else.  `spid_dpram` truncates the address into a 7-bit index, so
  // a write outside the window would silently alias onto a live FIFO entry.
  T_PROTO_SPI_SRAM_WRITE_IN_INGRESS: assert property (
    (`FT.mem_b_req && `FT.mem_b_write) |->
      ((`FT.mem_b_addr >= SramIngressIdx)
       && (`FT.mem_b_addr < (SramIngressIdx + SramAw'(IngressWords)))));

  // =========================================================================
  // 10 -- ARBITRATION FAIRNESS (bounded safety)
  // =========================================================================

  // ORACLE: `prim_arbiter_ppc` is round-robin over N=3 with `ready_i` tied
  // high, so a requester that holds its request is passed over at most twice
  // before it is granted.  The counter is this file's own; 4 is 2 with margin.
  T_FAIR_SYS_SRAM_FW_WAIT_LE_4: assert property (fw_arb_wait <= 8'd4);

  // ORACLE: the same arbiter, N=3, inside `spid_upload`.
  T_FAIR_SCK_SRAM_PAYLOAD_WAIT_LE_4: assert property (pl_arb_wait <= 8'd4);

  // =========================================================================
  // 11 -- BOUNDED RESPONSE (bounded safety)
  // =========================================================================

  // ORACLE: the SRAM read pipeline is fixed latency (input register, array
  // read, output register) and the arbiter's `ready_i` is tied high, so a
  // read that was issued comes back in a small constant number of cycles.
  T_BOUNDRSP_SYS_SRAM_READ_LE_8: assert property (rd_wait <= 8'd8);

  // ORACLE: a word pushed on the SPI side becomes visible to the bus side
  // after the 2-flop pointer synchroniser, an arbiter grant and the SRAM read
  // latency.  Two plus at most three plus three, rounded up.
  T_BOUNDRSP_CMDFIFO_VISIBLE_LE_16: assert property (cmd_vis_wait <= 8'd16);

  // =========================================================================
  // 12 -- DEADLOCK FREEDOM (bounded safety)
  // =========================================================================

  // ORACLE: a reader holding `rready` with entries in the FIFO cannot be
  // starved.  Nothing in the read path can block for ever: the arbiter always
  // grants, the SRAM always answers, and `stored` always drains.
  T_DEADLOCK_CMDFIFO_DRAIN_LE_32: assert property (cmd_drain_wait <= 8'd32);

  T_DEADLOCK_ADDRFIFO_DRAIN_LE_32: assert property (addr_drain_wait <= 8'd32);

  // =========================================================================
  // 13 -- RESET / INITIALISATION
  // =========================================================================

  // ORACLE: out of reset the command FIFO offers nothing and its pointers are
  // at zero.
  T_RESET_CMDFIFO_EMPTY: assert property (
    @(posedge clk_i) $rose(rst_ni) |->
      (!`FT.cmdfifo_rvalid_o && (`CFIFO.w_wptr_q == 5'd0)
       && (`CFIFO.r_rptr_q == 5'd0)));

  // ORACLE: the upload FSM starts in StIdle (encoded 0).
  T_RESET_UPLOAD_FSM_IDLE: assert property (
    @(posedge clk_i) $rose(rst_ni) |-> (`UPL.st_q == 2'd0));

  // ORACLE: the payload buffer's circular pointer starts at the base of the
  // buffer, so the first byte of the first transaction lands at offset 0.
  T_RESET_PAYLOAD_PTR_ZERO: assert property (
    @(posedge clk_i) $rose(rst_ni) |->
      ((`PBUF.fifoptr == 8'd0) && (`UPL.payloadptr == 8'd0)));

  // =========================================================================
  // 14 -- LIFECYCLE / ACCESS CONTROL
  // =========================================================================

  // ORACLE: BUSY is set by hardware when an upload command arrives and may be
  // cleared only by a software status write that carries a zero in bit 0.  A
  // BUSY that clears itself would let the next command through while the
  // uploaded one is still unread.
  T_LIFE_BUSY_STICKY_UNTIL_SW_CLEARS: assert property (
    (`STAT.sck_status_staged[0] && !(`STAT.sck_sw_we && !`STAT.sck_sw_status[0]))
      |=> `STAT.sck_status_staged[0]);

  // ORACLE: the 3B/4B address mode is committed only at the command sync pulse
  // -- the 8th SCK beat of a command -- so it can never change in the middle
  // of an address phase and split one address across two modes.
  T_LIFE_ADDR4B_ONLY_ON_CMD_SYNC: assert property (
    !`FT.cmd_sync_pulse |=> $stable(`FT.cfg_addr_4b_en));

  // ORACLE: `spid_upload` builds the command FIFO word as
  // {addr4b, wel, busy, 5'h00, opcode}.  Bits 12:8 are a hard-wired zero, so a
  // popped word with any of them set is a word that did not come from the
  // upload path -- the free software port reaching the ingress memory, say.
  T_ACCESS_CMDFIFO_RESERVED_BITS_ZERO: assert property (
    cmd_pop |-> (`FT.cmdfifo_rdata_o[12:8] == 5'h00));

  // ORACLE: `spi_cmdparse` selects the upload datapath only for a command slot
  // configured with `upload`, and this formal top configures exactly four.  A
  // word carrying any other opcode out of the FIFO is either a mis-parse or a
  // corrupted SRAM entry.
  T_ACCESS_CMDFIFO_OPCODE_IS_CONFIGURED_UPLOAD: assert property (
    (cmd_pop && (cq_push_cnt != cq_pop_cnt)) |->
      (cq_pop_opcode inside {OpPageProgram, OpSectorErase,
                             OpChipErase, OpWriteStatus}));

  // =========================================================================
  // 15 -- COHERENCE
  // =========================================================================

  // ORACLE: the two clock domains hold DIFFERENT views of the same FIFO -- the
  // writer sees a stale read pointer, the reader a stale write pointer.  The
  // gap between the TRUE pointers, one from each domain, must never exceed the
  // depth: if it did, the two views would disagree about who owns a slot and
  // the writer would overwrite an entry the reader still owns.
  T_COHERE_CMDFIFO_TRUE_PTR_GAP_LE_DEPTH: assert property (
    started |-> (cq_true_gap <= 6'(CDepth)));

endmodule

`default_nettype wire
