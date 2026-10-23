// ===========================================================================
// Covers for the OpenTitan spi_device command-upload subsystem.
//
// These are NOT targets.  They exist so `COVER_DEPTH` can show that the
// scenario each target constrains is REACHABLE -- a target whose covers are
// unreachable is vacuous and the screen drops it.  At least one per category
// used in `sva/targets_opentitan_spi_device_fifo.sv`.
//
// Instantiated inside `opentitan_spi_device_fifo_ft` as `u_covers`.
// ===========================================================================

`default_nettype none

`define FT    opentitan_spi_device_fifo_ft
`define UPL   opentitan_spi_device_fifo_ft.u_upload
`define CFIFO opentitan_spi_device_fifo_ft.u_upload.u_cmdfifo
`define AFIFO opentitan_spi_device_fifo_ft.u_upload.u_addrfifo
`define PBUF  opentitan_spi_device_fifo_ft.u_upload.u_payload_buffer
`define STAT  opentitan_spi_device_fifo_ft.u_spid_status
`define SFIFO opentitan_spi_device_fifo_ft.u_spid_status.u_sw_status_update_sync
`define ORC   opentitan_spi_device_fifo_ft.u_targets

module spi_device_fifo_covers
  import spi_device_pkg::*;
(
  input wire logic clk_i,
  input wire logic rst_ni
);

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // --- the SPI front end gets a command at all --------------------------
  C_S2P_BYTE:               cover property (`FT.s2p_data_valid);
  C_CMD_SYNC_PULSE:         cover property (`FT.cmd_sync_pulse);

  // --- 1 ordering, 2 data integrity, 3 uniqueness, 4 conservation --------
  C_CMDFIFO_PUSH:           cover property (`ORC.cmd_push);
  C_CMDFIFO_POP:            cover property (`ORC.cmd_pop);
  C_CMDFIFO_PUSH_THEN_POP:  cover property (`ORC.cmd_push ##[1:64] `ORC.cmd_pop);
  C_ADDRFIFO_PUSH:          cover property (`ORC.addr_push);
  C_ADDRFIFO_POP:           cover property (`ORC.addr_pop);
  C_CMD_AND_ADDR_BOTH_HELD: cover property ((`ORC.cq_occ != 16'd0)
                                            && (`ORC.aq_occ != 16'd0));
  C_PAYLOAD_PUSH:           cover property (`ORC.pl_push);
  C_PAYLOAD_FOUR_BYTES:     cover property (`ORC.pl_idx >= 8'd4);
  C_PAYLOAD_WORD_READBACK:  cover property (`ORC.rd_return
                                            && `ORC.rq_head_is_payload
                                            && `ORC.pl_word_complete
                                            && (`ORC.pl_quiet >= 4'd4));
  C_STATUS_SYNC_PUSH:       cover property (`ORC.st_push);
  C_STATUS_SYNC_POP:        cover property (`ORC.st_pop);

  // --- 5 mutual exclusion ------------------------------------------------
  C_SEL_DP_READSTATUS:      cover property (`FT.cmd_dp_sel == DpReadStatus);
  C_SEL_DP_READJEDEC:       cover property (`FT.cmd_dp_sel == DpReadJEDEC);
  C_SEL_DP_UPLOAD:          cover property (`FT.cmd_dp_sel == DpUpload);

  // --- 6 occupancy and bounds -------------------------------------------
  C_CMDFIFO_TWO_HELD:       cover property (`ORC.cq_occ >= 16'd2);
  C_CMDFIFO_FOUR_HELD:      cover property (`ORC.cq_occ >= 16'd4);
  C_CMDFIFO_WRITE_SIDE_FULL:cover property (`CFIFO.w_full);
  C_STATUS_SYNC_TWO_HELD:   cover property (`ORC.sq_occ >= 16'd2);
  C_SYS_SRAM_TWO_IN_FLIGHT: cover property (`ORC.rq_occ >= 16'd2);

  // --- 7 allocator discipline -------------------------------------------
  C_PAYLOAD_PTR_ADVANCED:   cover property (`PBUF.fifoptr >= 8'd4);

  // --- 8 request-response ------------------------------------------------
  C_SYS_SRAM_READ_RETURNS:  cover property (`ORC.rd_return);

  // --- 9 protocol conformance -------------------------------------------
  C_CMDFIFO_RVALID_HELD:    cover property (`FT.cmdfifo_rvalid_o
                                            && !`FT.cmdfifo_rready_i);
  C_SPI_SRAM_WRITE:         cover property (`FT.mem_b_req && `FT.mem_b_write);

  // --- 10 fairness, 11 bounded response, 12 deadlock ---------------------
  C_SYS_ARB_CONTENTION:     cover property ($countones(`FT.sys_sram_req) >= 2);
  C_FW_PORT_NOT_GRANTED:    cover property (`FT.sys_sram_req[0]
                                            && !`FT.sys_sram_gnt[0]);
  C_SCK_ARB_CONTENTION:     cover property ($countones(`UPL.sck_sram_req) >= 2);
  C_CMD_VISIBILITY_WAIT:    cover property (`ORC.cmd_vis_wait >= 8'd4);
  C_CMD_DRAIN_WAIT:         cover property (`ORC.cmd_drain_wait >= 8'd2);

  // --- 13 reset / initialisation ----------------------------------------
  C_SPI_DOMAIN_RELEASED:    cover property (!`FT.rst_spi_n ##1 `FT.rst_spi_n);
  C_SECOND_TRANSACTION:     cover property (`FT.rst_spi_n ##[1:96] !`FT.rst_spi_n
                                            ##[1:96] `FT.rst_spi_n);

  // --- 14 lifecycle / access control ------------------------------------
  C_BUSY_SET:               cover property (`FT.sck_status_busy_set);
  C_BUSY_COMMITTED:         cover property (`FT.sck_status_busy);
  C_ADDR4B_ENABLED:         cover property (`FT.cfg_addr_4b_en);
  C_WREN_COMMAND:           cover property (`FT.cmd_only_dp_sel == DpWrEn);

  // --- 15 coherence ------------------------------------------------------
  C_CMDFIFO_TRUE_GAP_TWO:   cover property (`ORC.cq_true_gap >= 6'd2);

endmodule

`default_nettype wire
