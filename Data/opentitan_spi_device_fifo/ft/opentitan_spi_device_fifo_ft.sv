// ===========================================================================
// opentitan_spi_device_fifo_ft -- the formal top for the OpenTitan spi_device
// command-upload subsystem, task-authored.
//
//   SPI pins -> spi_s2p -> spi_cmdparse -> spid_upload -> DPSRAM -> arbiter
//                                \                                    |
//                                 -> spid_status  <-- async FIFO <-----+
//                                 -> spid_jedec        (sys -> SCK)
//                                 -> spi_p2s -> SPI pins
//
// Wired the way `hw/ip/spi_device/rtl/spi_device.sv` wires the same blocks.
// The TL-UL register file (`spi_device_reg_top`, 22 kloc) and the whole
// `tlul_*` closure are OUT: every block here takes plain signals rather than a
// TL-UL port, so tying the CSR side off with CONSTANTS removes the register
// file without touching the datapath.  That is the same scoping decision
// `tasks/opentitan_entropy_chain` made with the three `_core` modules.
//
// THE BUFFERING, which is what this package is for:
//
//   * `spid_upload.u_cmdfifo`  and `.u_addrfifo` are two
//     `prim_fifo_async_sram_adapter` instances: a genuine asynchronous FIFO
//     with GRAY-CODED pointers, a 2-flop synchroniser in each direction, and
//     its storage in the dual-port SRAM.  Write side is the SPI clock domain,
//     read side is the bus clock domain.
//   * `spid_upload.u_payload_buffer` is a `spid_fifo2sram_adapter` packing
//     four SPI bytes into one SRAM word in the payload region, read back on
//     the bus side through the SRAM arbiter.
//   * `spid_status.u_sw_status_update_sync` is a `prim_fifo_async` running the
//     OTHER way, bus clock -> SPI clock.
//
// ONE CLOCK.  `clk_i` drives the bus domain, the SPI input domain and the SPI
// output domain.  See PROVENANCE.md, "The clock assumption" -- this is the
// single-clock constraint the harness needs, it is a 1:1 edge-aligned ratio,
// and it does NOT remove the CDC structure: the gray pointers, both 2-flop
// synchronisers, the SRAM read latency and the `stored`/`rvalid` handshake are
// all still under proof.
//
// FREE INPUTS, and they are the only ones:
//
//   csb_i                        SPI chip select, active low
//   sd_i[3:0]                    SPI data pins into the device
//   cmdfifo_rready_i             software pops the command FIFO
//   addrfifo_rready_i            software pops the address FIFO
//   fw_req_i / fw_write_i /      the software SRAM port on the bus side,
//   fw_addr_i / fw_wdata_i /       one of the three requesters on the
//   fw_wmask_i                     `prim_sram_arbiter`
//   sys_status_we_i,             software writes FLASH_STATUS
//   sys_status_i[23:0]
//
// There is no assumption in this file and none in
// `lists/diag_opentitan_spi_device_fifo.tcl`.
// ===========================================================================

`default_nettype none

module opentitan_spi_device_fifo_ft
  import spi_device_pkg::*;
(
  input wire logic                  clk_i,
  input wire logic                  rst_ni,

  // ---- SPI pins ----------------------------------------------------------
  input wire logic                  csb_i,
  input wire logic [3:0]            sd_i,
  output     logic [3:0]            sd_o,
  output     logic [3:0]            sd_en_o,

  // ---- bus clock domain, the software side -------------------------------
  input wire logic                  cmdfifo_rready_i,
  input wire logic                  addrfifo_rready_i,
  input wire logic                  fw_req_i,
  input wire logic                  fw_write_i,
  input wire logic [SramAw-1:0]     fw_addr_i,
  input wire logic [SramDw-1:0]     fw_wdata_i,
  input wire logic [SramDw-1:0]     fw_wmask_i,
  input wire logic                  sys_status_we_i,
  input wire logic [23:0]           sys_status_i,

  output     logic                  cmdfifo_rvalid_o,
  output     logic [15:0]           cmdfifo_rdata_o,
  output     logic                  addrfifo_rvalid_o,
  output     logic [31:0]           addrfifo_rdata_o,
  output     logic                  fw_rvalid_o,
  output     logic [SramDw-1:0]     fw_rdata_o,
  output     logic [23:0]           sys_status_o,
  output     logic                  cmdfifo_set_o,
  output     logic                  cmdfifo_notempty_o,
  output     logic                  addrfifo_notempty_o,
  output     logic                  payload_overflow_o
);

  import prim_mubi_pkg::mubi4_t;
  import prim_mubi_pkg::MuBi4False;

  // -------------------------------------------------------------------------
  // Clocks and resets
  // -------------------------------------------------------------------------
  // CSb is registered into the bus clock domain first.  In the real chip CSb
  // is asynchronous to everything and `spid_csb_sync` / `spid_status` clock a
  // flop on its POSEDGE; registering it here makes that a clock DERIVED from
  // `clk_i` rather than a second free-running primary clock, which is what the
  // single-clock setup needs.  Recorded in PROVENANCE.md.
  logic csb_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) csb_q <= 1'b1;
    else         csb_q <= csb_i;
  end

  // `rst_spi_n = rst_ni & ~csb`, exactly as spi_device.sv derives it: CSb
  // de-assertion resets the SPI-clock-domain logic, which is what frames a
  // transaction.  The async FIFO write ports deliberately use `rst_ni` (the
  // bus reset) instead, so the FIFO pointers survive across transactions --
  // that is upstream's own comment in `spid_upload`.
  logic rst_spi_n;
  assign rst_spi_n = rst_ni & ~csb_q;

  // -------------------------------------------------------------------------
  // Constant configuration, standing in for the CSR block
  // -------------------------------------------------------------------------
  localparam spi_mode_e SpiModeCfg = FlashMode;
  localparam logic      RxOrderCfg = 1'b0;   // MSB first
  localparam logic      TxOrderCfg = 1'b0;   // MSB first

  localparam jedec_cfg_t JedecCfg = '{
    num_cc:    8'h02,
    cc:        8'h7f,
    jedec_id:  8'h1f,
    device_id: 16'h1234
  };

  function automatic cmd_info_t ci_none();
    cmd_info_t ci;
    ci = '{payload_dir:        payload_dir_e'(PayloadIn),
           addr_mode:          addr_mode_e'(0),
           read_pipeline_mode: read_pipeline_mode_e'(0),
           default:            '0};
    return ci;
  endfunction

  // A command the device answers itself: opcode, then it drives MISO.
  function automatic cmd_info_t ci_read(logic [7:0] opcode);
    cmd_info_t ci;
    ci = ci_none();
    ci.valid       = 1'b1;
    ci.opcode      = opcode;
    ci.payload_en  = 4'b0010;                 // MISO
    ci.payload_dir = payload_dir_e'(PayloadOut);
    return ci;
  endfunction

  // A command the device UPLOADS: opcode, optional address, optional payload.
  function automatic cmd_info_t ci_upload(logic [7:0]  opcode,
                                          addr_mode_e  addr_mode,
                                          logic        has_payload);
    cmd_info_t ci;
    ci = ci_none();
    ci.valid       = 1'b1;
    ci.opcode      = opcode;
    ci.addr_mode   = addr_mode;
    ci.payload_en  = has_payload ? 4'b0001 : 4'b0000;   // MOSI
    ci.payload_dir = payload_dir_e'(PayloadIn);
    ci.upload      = 1'b1;
    ci.busy        = 1'b1;
    return ci;
  endfunction

  // A command with an opcode and nothing else (EN4B/EX4B/WREN/WRDI).
  function automatic cmd_info_t ci_opcode_only(logic [7:0] opcode);
    cmd_info_t ci;
    ci = ci_none();
    ci.valid  = 1'b1;
    ci.opcode = opcode;
    return ci;
  endfunction

  cmd_info_t [NumTotalCmdInfo-1:0] cmd_info;

  always_comb begin
    for (int unsigned i = 0 ; i < NumTotalCmdInfo ; i++) begin
      cmd_info[i] = ci_none();
    end

    // Read Status 1/2/3 -- answered by spid_status out of the async FIFO.
    cmd_info[CmdInfoReadStatus1] = ci_read(8'h05);
    cmd_info[CmdInfoReadStatus2] = ci_read(8'h35);
    cmd_info[CmdInfoReadStatus3] = ci_read(8'h15);

    // Read JEDEC ID -- answered by spid_jedec.
    cmd_info[CmdInfoReadJedecId] = ci_read(8'h9f);

    // Read SFDP and the six read-data slots stay INVALID: `spi_readcmd` is not
    // in this package, so a command that selects it would drive a datapath
    // with nothing behind it.

    // The three upload flavours, in the reserve slots, so that the four
    // command shapes the upload FSM has to distinguish are all reachable:
    //   Page Program : opcode + address + payload
    //   Sector Erase : opcode + address, no payload
    //   Chip Erase   : opcode only
    //   Write Status : opcode + payload, no address
    cmd_info[CmdInfoReserveStart + 0] =
        ci_upload(8'h02, addr_mode_e'(AddrCfg),      1'b1);
    cmd_info[CmdInfoReserveStart + 1] =
        ci_upload(8'h20, addr_mode_e'(AddrCfg),      1'b0);
    cmd_info[CmdInfoReserveStart + 2] =
        ci_upload(8'hc7, addr_mode_e'(AddrDisabled), 1'b0);
    cmd_info[CmdInfoReserveStart + 3] =
        ci_upload(8'h01, addr_mode_e'(AddrDisabled), 1'b1);

    // The four fixed opcode-only slots.
    cmd_info[CmdInfoEn4B] = ci_opcode_only(8'hb7);
    cmd_info[CmdInfoEx4B] = ci_opcode_only(8'he9);
    cmd_info[CmdInfoWrEn] = ci_opcode_only(8'h06);
    cmd_info[CmdInfoWrDi] = ci_opcode_only(8'h04);
  end

  // -------------------------------------------------------------------------
  // Signals between the blocks
  // -------------------------------------------------------------------------
  logic                   s2p_data_valid;
  spi_byte_t              s2p_data;

  io_mode_e               io_mode, io_mode_outclk;
  io_mode_e               iomode_cmdparse, iomode_status, iomode_jedec,
                          iomode_upload;

  sel_datapath_e          cmd_dp_sel, cmd_only_dp_sel;
  cmd_info_t              cmd_info_broadcast, cmd_only_info_broadcast;
  logic [CmdInfoIdxW-1:0] cmd_info_idx_broadcast, cmd_only_info_idx_broadcast;
  logic                   cmd_sync_pulse;

  logic                   p2s_valid, p2s_sent;
  spi_byte_t              p2s_data;
  logic                   p2s_valid_status, p2s_valid_jedec, p2s_valid_upload;
  spi_byte_t              p2s_data_status,  p2s_data_jedec,  p2s_data_upload;
  logic                   p2s_sent_status,  p2s_sent_jedec,  p2s_sent_upload;

  logic                   sck_status_busy, sck_status_busy_set;
  logic                   sck_status_wr_set, sck_status_wr_clr;
  logic                   cmd_sync_status_busy, cmd_sync_status_wel;
  logic                   csb_status_busy_broadcast;
  logic                   sys_csb_deasserted_pulse;

  logic                   cmd_sync_addr_4b_en, cfg_addr_4b_en;
  logic                   addr_4b_pending, addr_4b_en_readback;

  logic                   cmd_en4b_pulse, cmd_ex4b_pulse;

  // SRAM, SPI side
  sram_l2m_t              upload_sck_sram_l2m, flash_sram_l2m, mem_b_l2m;
  sram_m2l_t              upload_sck_sram_m2l, flash_sram_m2l, mem_b_m2l;

  // SRAM, bus side: three requesters on one arbiter.
  //   0 = software (free inputs), 1 = command FIFO read, 2 = address FIFO read
  localparam int unsigned NumSysSram   = 3;
  localparam int unsigned SysSramFw    = 0;
  localparam int unsigned SysSramCmd   = 1;
  localparam int unsigned SysSramAddr  = 2;

  sram_l2m_t              sys_cmdfifo_l2m, sys_addrfifo_l2m;
  sram_m2l_t              sys_cmdfifo_m2l, sys_addrfifo_m2l;

  logic [NumSysSram-1:0]  sys_sram_req;
  logic [NumSysSram-1:0]  sys_sram_gnt;
  logic [NumSysSram-1:0]  sys_sram_write;
  logic [SramAw-1:0]      sys_sram_addr  [NumSysSram];
  logic [SramDw-1:0]      sys_sram_wdata [NumSysSram];
  logic [SramDw-1:0]      sys_sram_wmask [NumSysSram];
  logic [NumSysSram-1:0]  sys_sram_rvalid;
  logic [SramDw-1:0]      sys_sram_rdata [NumSysSram];
  logic [1:0]             sys_sram_rerror[NumSysSram];

  logic                   mem_a_req, mem_a_write, mem_a_rvalid;
  logic [SramAw-1:0]      mem_a_addr;
  logic [SramDw-1:0]      mem_a_wdata, mem_a_wmask, mem_a_rdata;
  logic [1:0]             mem_a_rerror;

  logic                   mem_b_req, mem_b_write, mem_b_rvalid;
  logic [SramAw-1:0]      mem_b_addr;
  logic [SramDw-1:0]      mem_b_wdata, mem_b_wmask, mem_b_rdata;
  logic [1:0]             mem_b_rerror;

  logic [15:0]            cmdfifo_rdata;
  logic [31:0]            addrfifo_rdata;

  // Widths taken from spid_upload's own derivation.
  localparam int unsigned CmdPtrW  = $clog2(SramCmdFifoDepth  + 1);
  localparam int unsigned AddrPtrW = $clog2(SramAddrFifoDepth + 1);
  localparam int unsigned PayloadByte = SramPayloadDepth * (SramDw / 8);
  localparam int unsigned PayloadPtrW = $clog2(PayloadByte + 1);
  localparam int unsigned PayloadIdxW = $clog2(PayloadByte);

  logic [CmdPtrW-1:0]     cmdfifo_depth;
  logic [AddrPtrW-1:0]    addrfifo_depth;
  logic [PayloadPtrW-1:0] payload_depth;
  logic [PayloadIdxW-1:0] payload_start_idx;
  logic                   cmdfifo_full, addrfifo_full;

  // -------------------------------------------------------------------------
  // Serial <-> parallel
  // -------------------------------------------------------------------------
  spi_s2p u_s2p (
    .clk_i        (clk_i),
    .rst_ni       (rst_spi_n),
    .s_i          (sd_i),
    .data_valid_o (s2p_data_valid),
    .data_o       (s2p_data),
    .order_i      (RxOrderCfg),
    .io_mode_i    (io_mode_outclk)
  );

  spi_p2s u_p2s (
    .clk_i        (clk_i),
    .rst_ni       (rst_spi_n),
    .data_valid_i (p2s_valid),
    .data_i       (p2s_data),
    .data_sent_o  (p2s_sent),
    .csb_i        (csb_q),
    .s_en_o       (sd_en_o),
    .s_o          (sd_o),
    .order_i      (TxOrderCfg),
    .io_mode_i    (io_mode_outclk)
  );

  // io_mode is latched on the output clock in the real design; with one clock
  // it is a plain register, and the register is what keeps the combinational
  // loop s2p -> cmdparse -> io_mode -> s2p broken.
  always_ff @(posedge clk_i or negedge rst_spi_n) begin
    if (!rst_spi_n) io_mode_outclk <= SingleIO;
    else            io_mode_outclk <= io_mode;
  end

  // -------------------------------------------------------------------------
  // Command parser
  // -------------------------------------------------------------------------
  spi_cmdparse u_cmdparse (
    .clk_i                     (clk_i),
    .rst_ni                    (rst_spi_n),
    .data_valid_i              (s2p_data_valid),
    .data_i                    (s2p_data),
    .spi_mode_i                (SpiModeCfg),
    .cmd_info_i                (cmd_info),
    .sck_status_busy_i         (sck_status_busy),
    .io_mode_o                 (iomode_cmdparse),
    .sel_dp_o                  (cmd_dp_sel),
    .cmd_only_sel_dp_o         (cmd_only_dp_sel),
    .cmd_info_o                (cmd_info_broadcast),
    .cmd_info_idx_o            (cmd_info_idx_broadcast),
    .cmd_only_info_o           (cmd_only_info_broadcast),
    .cmd_only_info_idx_o       (cmd_only_info_idx_broadcast),
    .cmd_sync_pulse_o          (cmd_sync_pulse),
    .cfg_intercept_en_status_i (1'b0),
    .cfg_intercept_en_jedec_i  (1'b0),
    .cfg_intercept_en_sfdp_i   (1'b0),
    .cmd_read_pipeline_sel_o   (),
    .intercept_status_o        (),
    .intercept_jedec_o         (),
    .intercept_sfdp_o          (),
    .cmd_config_req_o          (),
    .cmd_config_idx_o          ()
  );

  // -------------------------------------------------------------------------
  // CSb de-assertion pulse in the bus clock domain
  // -------------------------------------------------------------------------
  spid_csb_sync u_spid_csb_sync (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .sck_i                  (clk_i),
    .sck_pulse_en_i         (1'b1),
    .csb_i                  (csb_q),
    .csb_deasserted_pulse_o (sys_csb_deasserted_pulse)
  );

  // -------------------------------------------------------------------------
  // Read Status -- the bus -> SPI async FIFO
  // -------------------------------------------------------------------------
  assign sck_status_wr_set = (cmd_only_dp_sel == DpWrEn);
  assign sck_status_wr_clr = (cmd_only_dp_sel == DpWrDi);

  spid_status u_spid_status (
    .clk_i                      (clk_i),
    .rst_ni                     (rst_spi_n),
    .clk_out_i                  (clk_i),
    .rst_out_ni                 (rst_spi_n),
    .clk_csb_i                  (csb_q),
    .sys_clk_i                  (clk_i),
    .sys_rst_ni                 (rst_ni),
    .sys_csb_deasserted_pulse_i (sys_csb_deasserted_pulse),
    .sys_update_clr_i           (1'b0),
    .sys_status_we_i            (sys_status_we_i),
    .sys_status_i               (sys_status_i),
    .sys_status_o               (sys_status_o),
    .sel_dp_i                   (cmd_dp_sel),
    .cmd_info_i                 (cmd_info_broadcast),
    .cmd_info_idx_i             (cmd_info_idx_broadcast),
    .outclk_p2s_valid_o         (p2s_valid_status),
    .outclk_p2s_byte_o          (p2s_data_status),
    .outclk_p2s_sent_i          (p2s_sent_status),
    .io_mode_o                  (iomode_status),
    .inclk_busy_set_i           (sck_status_busy_set),
    .inclk_we_set_i             (sck_status_wr_set),
    .inclk_we_clr_i             (sck_status_wr_clr),
    .inclk_status_commit_i      (s2p_data_valid),
    .cmd_sync_status_busy_o     (cmd_sync_status_busy),
    .cmd_sync_status_wel_o      (cmd_sync_status_wel),
    .sck_status_busy_o          (sck_status_busy),
    .csb_busy_broadcast_o       (csb_status_busy_broadcast),
    .scan_rst_ni                (1'b1),
    .scanmode_i                 (MuBi4False)
  );

  // -------------------------------------------------------------------------
  // Read JEDEC ID
  // -------------------------------------------------------------------------
  spid_jedec u_jedec (
    .clk_i              (clk_i),
    .rst_ni             (rst_spi_n),
    .clk_out_i          (clk_i),
    .rst_out_ni         (rst_spi_n),
    .cmd_sync_pulse_i   (cmd_sync_pulse),
    .sys_jedec_i        (JedecCfg),
    .io_mode_o          (iomode_jedec),
    .sel_dp_i           (cmd_dp_sel),
    .cmd_info_i         (cmd_info_broadcast),
    .cmd_info_idx_i     (cmd_info_idx_broadcast),
    .outclk_p2s_valid_o (p2s_valid_jedec),
    .outclk_p2s_byte_o  (p2s_data_jedec),
    .outclk_p2s_sent_i  (p2s_sent_jedec)
  );

  // -------------------------------------------------------------------------
  // Upload -- the two SPI -> bus async FIFOs and the payload buffer
  // -------------------------------------------------------------------------
  spid_upload #(
    .CmdFifoBaseAddr  (SramCmdFifoIdx),
    .CmdFifoDepth     (SramCmdFifoDepth),
    .AddrFifoBaseAddr (SramAddrFifoIdx),
    .AddrFifoDepth    (SramAddrFifoDepth),
    .PayloadBaseAddr  (SramPayloadIdx),
    .PayloadDepth     (SramPayloadDepth),
    .SpiByte          ($bits(spi_byte_t))
  ) u_upload (
    .clk_i                     (clk_i),
    .rst_ni                    (rst_spi_n),
    .sys_clk_i                 (clk_i),
    .sys_rst_ni                (rst_ni),
    .clk_csb_i                 (csb_q),

    .sel_dp_i                  (cmd_dp_sel),
    .cmd_only_sel_dp_i         (cmd_only_dp_sel),

    .sck_sram_o                (upload_sck_sram_l2m),
    .sck_sram_i                (upload_sck_sram_m2l),

    .sys_cmdfifo_sram_o        (sys_cmdfifo_l2m),
    .sys_cmdfifo_sram_i        (sys_cmdfifo_m2l),
    .sys_cmdfifo_gnt_i         (sys_sram_gnt[SysSramCmd]),

    .sys_addrfifo_sram_o       (sys_addrfifo_l2m),
    .sys_addrfifo_sram_i       (sys_addrfifo_m2l),
    .sys_addrfifo_gnt_i        (sys_sram_gnt[SysSramAddr]),

    .sys_cmdfifo_rvalid_o      (cmdfifo_rvalid_o),
    .sys_cmdfifo_rready_i      (cmdfifo_rready_i),
    .sys_cmdfifo_rdata_o       (cmdfifo_rdata),

    .sys_addrfifo_rvalid_o     (addrfifo_rvalid_o),
    .sys_addrfifo_rready_i     (addrfifo_rready_i),
    .sys_addrfifo_rdata_o      (addrfifo_rdata),

    .s2p_valid_i               (s2p_data_valid),
    .s2p_byte_i                (s2p_data),

    .p2s_valid_o               (p2s_valid_upload),
    .p2s_data_o                (p2s_data_upload),
    .p2s_sent_i                (p2s_sent_upload),

    .spi_mode_i                (SpiModeCfg),

    .cmd_sync_cfg_addr_4b_en_i (cmd_sync_addr_4b_en),
    .cmd_sync_status_wel_i     (cmd_sync_status_wel),
    .cmd_sync_status_busy_i    (cmd_sync_status_busy),

    .cmd_only_info_i           (cmd_only_info_broadcast),
    .cmd_only_info_idx_i       (cmd_only_info_idx_broadcast),

    .io_mode_o                 (iomode_upload),

    .set_busy_o                (sck_status_busy_set),

    .sys_cmdfifo_set_o         (cmdfifo_set_o),
    .sys_cmdfifo_notempty_o    (cmdfifo_notempty_o),
    .sys_cmdfifo_full_o        (cmdfifo_full),
    .sys_addrfifo_notempty_o   (addrfifo_notempty_o),
    .sys_addrfifo_full_o       (addrfifo_full),
    .sys_payload_overflow_o    (payload_overflow_o),

    .sys_cmdfifo_depth_o       (cmdfifo_depth),
    .sys_addrfifo_depth_o      (addrfifo_depth),
    .sys_payload_depth_o       (payload_depth),
    .sys_payload_start_idx_o   (payload_start_idx)
  );

  assign cmdfifo_rdata_o  = cmdfifo_rdata;
  assign addrfifo_rdata_o = addrfifo_rdata;

  // -------------------------------------------------------------------------
  // 3B/4B address mode tracker
  // -------------------------------------------------------------------------
  assign cmd_en4b_pulse = (cmd_only_dp_sel == DpEn4B);
  assign cmd_ex4b_pulse = (cmd_only_dp_sel == DpEx4B);

  spid_addr_4b u_spid_addr_4b (
    .sys_clk_i                        (clk_i),
    .sys_rst_ni                       (rst_ni),
    .spi_clk_i                        (clk_i),
    .cmd_sync_pulse_i                 (cmd_sync_pulse),
    .reg2hw_addr_mode_addr_4b_en_q_i  (1'b0),
    .reg2hw_addr_mode_addr_4b_en_qe_i (1'b0),
    .hw2reg_addr_mode_pending_d_o     (addr_4b_pending),
    .hw2reg_addr_mode_addr_4b_en_d_o  (addr_4b_en_readback),
    .spi_cfg_addr_4b_en_o             (cfg_addr_4b_en),
    .cmd_sync_cfg_addr_4b_en_o        (cmd_sync_addr_4b_en),
    .spi_addr_4b_set_i                (cmd_en4b_pulse),
    .spi_addr_4b_clr_i                (cmd_ex4b_pulse)
  );

  // -------------------------------------------------------------------------
  // The SPI-side SRAM mux and the p2s / io_mode mux, as spi_device.sv has them
  // -------------------------------------------------------------------------
  always_comb begin
    flash_sram_l2m      = '{default: '0};
    upload_sck_sram_m2l = '{rvalid: 1'b0, rdata: '0,
                            rerror: '{uncorr: 1'b0, corr: 1'b0}};

    if ((cmd_dp_sel == DpUpload) || (cmd_only_dp_sel == DpUpload)) begin
      flash_sram_l2m      = upload_sck_sram_l2m;
      upload_sck_sram_m2l = flash_sram_m2l;
    end
  end

  always_comb begin
    mem_b_l2m      = '{default: '0};
    flash_sram_m2l = '{rvalid: 1'b0, rdata: '0,
                       rerror: '{uncorr: 1'b0, corr: 1'b0}};

    if (!csb_q) begin
      mem_b_l2m      = flash_sram_l2m;
      flash_sram_m2l = mem_b_m2l;
    end
  end

  always_comb begin
    io_mode          = SingleIO;
    p2s_valid        = 1'b0;
    p2s_data         = 8'h00;
    p2s_sent_status  = 1'b0;
    p2s_sent_jedec   = 1'b0;
    p2s_sent_upload  = 1'b0;

    case (cmd_dp_sel)
      DpReadStatus: begin
        io_mode         = iomode_status;
        p2s_valid       = p2s_valid_status;
        p2s_data        = p2s_data_status;
        p2s_sent_status = p2s_sent;
      end

      DpReadJEDEC: begin
        io_mode        = iomode_jedec;
        p2s_valid      = p2s_valid_jedec;
        p2s_data       = p2s_data_jedec;
        p2s_sent_jedec = p2s_sent;
      end

      DpUpload: begin
        io_mode         = iomode_upload;
        p2s_valid       = p2s_valid_upload;
        p2s_data        = p2s_data_upload;
        p2s_sent_upload = p2s_sent;
      end

      default: begin
        io_mode = iomode_cmdparse;
      end
    endcase
  end

  // -------------------------------------------------------------------------
  // The bus-side SRAM arbiter: software, command FIFO read, address FIFO read
  // -------------------------------------------------------------------------
  always_comb begin
    sys_sram_req  [SysSramFw]  = fw_req_i;
    sys_sram_write[SysSramFw]  = fw_write_i;
    sys_sram_addr [SysSramFw]  = fw_addr_i;
    sys_sram_wdata[SysSramFw]  = fw_wdata_i;
    sys_sram_wmask[SysSramFw]  = fw_wmask_i;

    sys_sram_req  [SysSramCmd] = sys_cmdfifo_l2m.req;
    sys_sram_write[SysSramCmd] = sys_cmdfifo_l2m.we;
    sys_sram_addr [SysSramCmd] = sys_cmdfifo_l2m.addr;
    sys_sram_wdata[SysSramCmd] = sys_cmdfifo_l2m.wdata;
    sys_sram_wmask[SysSramCmd] = sram_strb2mask(sys_cmdfifo_l2m.wstrb);

    sys_sram_req  [SysSramAddr] = sys_addrfifo_l2m.req;
    sys_sram_write[SysSramAddr] = sys_addrfifo_l2m.we;
    sys_sram_addr [SysSramAddr] = sys_addrfifo_l2m.addr;
    sys_sram_wdata[SysSramAddr] = sys_addrfifo_l2m.wdata;
    sys_sram_wmask[SysSramAddr] = sram_strb2mask(sys_addrfifo_l2m.wstrb);
  end

  assign sys_cmdfifo_m2l = '{rvalid: sys_sram_rvalid[SysSramCmd],
                             rdata:  sys_sram_rdata [SysSramCmd],
                             rerror: '{uncorr: sys_sram_rerror[SysSramCmd][1],
                                       corr:   sys_sram_rerror[SysSramCmd][0]}};

  assign sys_addrfifo_m2l = '{rvalid: sys_sram_rvalid[SysSramAddr],
                              rdata:  sys_sram_rdata [SysSramAddr],
                              rerror: '{uncorr: sys_sram_rerror[SysSramAddr][1],
                                        corr:   sys_sram_rerror[SysSramAddr][0]}};

  assign fw_rvalid_o = sys_sram_rvalid[SysSramFw];
  assign fw_rdata_o  = sys_sram_rdata [SysSramFw];

  prim_sram_arbiter #(
    .N      (NumSysSram),
    .SramDw (SramDw),
    .SramAw (SramAw),
    .EnMask (1'b1)
  ) u_sys_sram_arbiter (
    .clk_i,
    .rst_ni,

    .req_i        (sys_sram_req),
    .req_addr_i   (sys_sram_addr),
    .req_write_i  (sys_sram_write),
    .req_wdata_i  (sys_sram_wdata),
    .req_wmask_i  (sys_sram_wmask),
    .gnt_o        (sys_sram_gnt),

    .rsp_rvalid_o (sys_sram_rvalid),
    .rsp_rdata_o  (sys_sram_rdata),
    .rsp_error_o  (sys_sram_rerror),

    .sram_req_o    (mem_a_req),
    .sram_addr_o   (mem_a_addr),
    .sram_write_o  (mem_a_write),
    .sram_wdata_o  (mem_a_wdata),
    .sram_wmask_o  (mem_a_wmask),
    .sram_rvalid_i (mem_a_rvalid),
    .sram_rdata_i  (mem_a_rdata),
    .sram_rerror_i (mem_a_rerror)
  );

  // -------------------------------------------------------------------------
  // The dual-port SRAM: bus clock on the A port, SPI clock on the B port
  // -------------------------------------------------------------------------
  assign mem_b_req   = mem_b_l2m.req;
  assign mem_b_write = mem_b_l2m.we;
  assign mem_b_addr  = mem_b_l2m.addr;
  assign mem_b_wdata = mem_b_l2m.wdata;
  assign mem_b_wmask = sram_strb2mask(mem_b_l2m.wstrb);

  assign mem_b_m2l = '{rvalid: mem_b_rvalid,
                       rdata:  mem_b_rdata,
                       rerror: '{uncorr: mem_b_rerror[1],
                                 corr:   mem_b_rerror[0]}};

  spid_dpram #(
    .SramType             (DefaultSramType),
    .EnableECC            (0),
    .EnableParity         (1),
    .EnableInputPipeline  (0),
    .EnableOutputPipeline (0)
  ) u_spid_dpram (
    .clk_sys_i     (clk_i),
    .rst_sys_ni    (rst_ni),

    .clk_spi_i     (clk_i),
    .rst_spi_ni    (rst_spi_n),

    .sys_req_i     (mem_a_req),
    .sys_write_i   (mem_a_write),
    .sys_addr_i    (mem_a_addr),
    .sys_wdata_i   (mem_a_wdata),
    .sys_wmask_i   (mem_a_wmask),
    .sys_rvalid_o  (mem_a_rvalid),
    .sys_rdata_o   (mem_a_rdata),
    .sys_rerror_o  (mem_a_rerror),

    .spi_req_i     (mem_b_req),
    .spi_write_i   (mem_b_write),
    .spi_addr_i    (mem_b_addr),
    .spi_wdata_i   (mem_b_wdata),
    .spi_wmask_i   (mem_b_wmask),
    .spi_rvalid_o  (mem_b_rvalid),
    .spi_rdata_o   (mem_b_rdata),
    .spi_rerror_o  (mem_b_rerror),

    .cfg_sys2spi_i (prim_ram_1r1w_pkg::RAM_1R1W_CFG_REQ_DEFAULT),
    .cfg_sys2spi_o (),
    .cfg_spi2sys_i (prim_ram_1r1w_pkg::RAM_1R1W_CFG_REQ_DEFAULT),
    .cfg_spi2sys_o ()
  );

  // -------------------------------------------------------------------------
  // Sinks for the signals nothing else reads, so that nothing in the closure
  // is dropped as dangling before a target can look at it.
  // -------------------------------------------------------------------------
  logic unused_ft;
  assign unused_ft = ^{cmdfifo_depth, addrfifo_depth, payload_depth,
                       payload_start_idx, cmdfifo_full, addrfifo_full,
                       csb_status_busy_broadcast, cfg_addr_4b_en,
                       addr_4b_pending, addr_4b_en_readback,
                       cmd_info_broadcast, cmd_only_info_broadcast,
                       cmd_only_info_idx_broadcast, iomode_cmdparse};

  // -------------------------------------------------------------------------
  // The oracle and its assertions, and the covers.  Instantiated rather than
  // bound: this top is task-authored, so there is nothing to bind AROUND.
  // -------------------------------------------------------------------------
  spi_device_fifo_targets u_targets (.clk_i(clk_i), .rst_ni(rst_ni));
  spi_device_fifo_covers  u_covers  (.clk_i(clk_i), .rst_ni(rst_ni));

endmodule

`default_nettype wire
