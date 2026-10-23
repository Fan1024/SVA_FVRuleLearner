// ===========================================================================
// Formal top for the NVDLA convolution datapath, closed end to end:
//
//    memory -> CDMA -> CBUF -> CSC -> CMAC_A / CMAC_B -> CACC -> SDP
//                        ^        |                        |
//                        |        +-- entry credits -------+
//                        +-- CBUF entry / slice credits ---+
//
// All five blocks are the generated upstream RTL, byte-identical:
//
//    NV_NVDLA_cdma   fetch: two read-DMA channels (feature data and weights),
//                    each with an MCIF and a CVIF port; writes CBUF
//    NV_NVDLA_cbuf   512 KiB, 16 banks x 2 columns of 256 x 512b, one write
//                    port per producer and three read ports (dat, wt, wmb)
//    NV_NVDLA_csc    sequence control: reads CBUF, drives the two MAC halves
//    NV_NVDLA_cmac   the 128-lane MAC array, instantiated twice (A and B),
//                    exactly as `NV_NVDLA_partition_m` is instantiated twice
//    NV_NVDLA_cacc   accumulator: assembly buffer, delivery buffer, SDP egress
//
// The five module headers close on their own port names with ZERO multiply
// driven nets and no renaming except the two the chip itself renames: CSC's
// `sc2mac_*_a_*` / `_b_*` become each CMAC's `sc2mac_*_*`, and each CMAC's
// `mac2accu_*` becomes CACC's `mac_a2accu_*` / `mac_b2accu_*`.  The wire block
// below was generated from those headers rather than typed.
//
// NOT included, deliberately: the `NV_NVDLA_RT_*` partition retiming stages
// that sit on csc2cmac, cmac2cacc, csb2cmac and cacc2glb in the real floorplan.
// They are flop banks on unidirectional valid/data pipes with no ready, so
// leaving them out changes latency and nothing else -- and it keeps the
// CSC-to-CMAC latency the four cycles the CMAC RTL itself defines, which is
// what several targets are stated against.
//
// The ENVIRONMENT is task-authored and bounded:
//
//   * four `nvdla_conv_mem_responder` instances, one per read-DMA port, each
//     holding one command at a time with an exact 16-bit atom ledger and a
//     stall bounded to MAX_HOLD cycles;
//   * a CSB config stimulus per block, free: `csb2*_req_prdy` is a hard 1'b1
//     in every one of the five regfiles, so there is no handshake to model and
//     nothing to constrain;
//   * an SDP sink whose backpressure is free but bounded to SINK_MAX cycles;
//   * `pwrbus_ram_pd` in functional mode, clock-override syncs low, and
//     `tmc2slcg_disable_clock_gating` high.  With `+define+VLIB_BYPASS_POWER_CG`
//     every NV_CLK_gate_power is a wire-through, so the SLCG enables cannot
//     stop a clock; holding the disable high keeps that explicit.
//
// `sym_addr` / `sym_col` name the one CBUF half-line the data-integrity oracle
// watches.  They are free inputs frozen by an assumption in the checker.
// ===========================================================================

module nvdla_conv_pipeline_ft (
   input  wire         nvdla_core_clk,
   input  wire         nvdla_core_rstn,

   // CSB configuration stimulus, one per configurable block.
   input  wire         env_csb2cdma_req_pvld,
   input  wire [62:0]  env_csb2cdma_req_pd,
   input  wire         env_csb2csc_req_pvld,
   input  wire [62:0]  env_csb2csc_req_pd,
   input  wire         env_csb2cmac_a_req_pvld,
   input  wire [62:0]  env_csb2cmac_a_req_pd,
   input  wire         env_csb2cmac_b_req_pvld,
   input  wire [62:0]  env_csb2cmac_b_req_pd,
   input  wire         env_csb2cacc_req_pvld,
   input  wire [62:0]  env_csb2cacc_req_pd,

   // Memory responder environment.  Bit order: 0 dat/MCIF, 1 dat/CVIF,
   // 2 wt/MCIF, 3 wt/CVIF.
   input  wire [3:0]   env_mem_hold,
   input  wire [511:0] env_mem_dat_mcif_data,
   input  wire [511:0] env_mem_dat_cvif_data,
   input  wire [511:0] env_mem_wt_mcif_data,
   input  wire [511:0] env_mem_wt_cvif_data,

   // SDP sink backpressure.
   input  wire         env_sdp_hold,

   // The symbolic CBUF half-line under observation.
   input  wire [11:0]  env_sym_addr,
   input  wire         env_sym_col
);

   // ---- Static environment ------------------------------------------------
   wire [31:0] pwrbus_ram_pd                 = 32'd0;
   wire        dla_clk_ovr_on_sync           = 1'b0;
   wire        global_clk_ovr_on_sync        = 1'b0;
   wire        tmc2slcg_disable_clock_gating = 1'b1;

   wire        csb2cdma_req_pvld   = env_csb2cdma_req_pvld;
   wire [62:0] csb2cdma_req_pd     = env_csb2cdma_req_pd;
   wire        csb2csc_req_pvld    = env_csb2csc_req_pvld;
   wire [62:0] csb2csc_req_pd      = env_csb2csc_req_pd;
   wire        csb2cmac_a_req_pvld = env_csb2cmac_a_req_pvld;
   wire [62:0] csb2cmac_a_req_pd   = env_csb2cmac_a_req_pd;
   wire        csb2cmac_b_req_pvld = env_csb2cmac_b_req_pvld;
   wire [62:0] csb2cmac_b_req_pd   = env_csb2cmac_b_req_pd;
   wire        csb2cacc_req_pvld   = env_csb2cacc_req_pvld;
   wire [62:0] csb2cacc_req_pd     = env_csb2cacc_req_pd;

   // Nets the environment drives that the generated wire block above leaves to
   // this section: the four responder-side handshakes and the SDP ready.
   wire         cdma_dat2mcif_rd_req_ready;
   wire         cdma_dat2cvif_rd_req_ready;
   wire         cdma_wt2mcif_rd_req_ready;
   wire         cdma_wt2cvif_rd_req_ready;
   wire         mcif2cdma_dat_rd_rsp_valid;
   wire [513:0] mcif2cdma_dat_rd_rsp_pd;
   wire         cvif2cdma_dat_rd_rsp_valid;
   wire [513:0] cvif2cdma_dat_rd_rsp_pd;
   wire         mcif2cdma_wt_rd_rsp_valid;
   wire [513:0] mcif2cdma_wt_rd_rsp_pd;
   wire         cvif2cdma_wt_rd_rsp_valid;
   wire [513:0] cvif2cdma_wt_rd_rsp_pd;
   wire         cacc2sdp_ready;

   // ---- Inter-block nets ---------------------------------------------------
   // Generated from the five module headers: every net below is named by the
   // port that carries it upstream, and the five blocks close on those names
   // with zero multiply-driven nets.

   wire [2:0] accu2sc_credit_size;
   wire accu2sc_credit_vld;
   wire [33:0] cacc2csb_resp_pd;
   wire cacc2csb_resp_valid;
   wire [1:0] cacc2glb_done_intr_pd;
   wire [513:0] cacc2sdp_pd;
   wire cacc2sdp_valid;
   wire [11:0] cdma2buf_dat_wr_addr;
   wire [1023:0] cdma2buf_dat_wr_data;
   wire cdma2buf_dat_wr_en;
   wire [1:0] cdma2buf_dat_wr_hsel;
   wire [11:0] cdma2buf_wt_wr_addr;
   wire [511:0] cdma2buf_wt_wr_data;
   wire cdma2buf_wt_wr_en;
   wire cdma2buf_wt_wr_hsel;
   wire [33:0] cdma2csb_resp_pd;
   wire cdma2csb_resp_valid;
   wire [11:0] cdma2sc_dat_entries;
   wire cdma2sc_dat_pending_ack;
   wire [11:0] cdma2sc_dat_slices;
   wire cdma2sc_dat_updt;
   wire [8:0] cdma2sc_wmb_entries;
   wire [11:0] cdma2sc_wt_entries;
   wire [13:0] cdma2sc_wt_kernels;
   wire cdma2sc_wt_pending_ack;
   wire cdma2sc_wt_updt;
   wire [78:0] cdma_dat2cvif_rd_req_pd;
   wire cdma_dat2cvif_rd_req_valid;
   wire [1:0] cdma_dat2glb_done_intr_pd;
   wire [78:0] cdma_dat2mcif_rd_req_pd;
   wire cdma_dat2mcif_rd_req_valid;
   wire [78:0] cdma_wt2cvif_rd_req_pd;
   wire cdma_wt2cvif_rd_req_valid;
   wire [1:0] cdma_wt2glb_done_intr_pd;
   wire [78:0] cdma_wt2mcif_rd_req_pd;
   wire cdma_wt2mcif_rd_req_valid;
   wire [33:0] cmac_a2csb_resp_pd;
   wire cmac_a2csb_resp_valid;
   wire [33:0] cmac_b2csb_resp_pd;
   wire cmac_b2csb_resp_valid;
   wire csb2cacc_req_prdy;
   wire csb2cdma_req_prdy;
   wire csb2cmac_a_req_prdy;
   wire csb2cmac_b_req_prdy;
   wire csb2csc_req_prdy;
   wire [33:0] csc2csb_resp_pd;
   wire csc2csb_resp_valid;
   wire cvif2cdma_dat_rd_rsp_ready;
   wire cvif2cdma_wt_rd_rsp_ready;
   wire [175:0] mac_a2accu_data0;
   wire [175:0] mac_a2accu_data1;
   wire [175:0] mac_a2accu_data2;
   wire [175:0] mac_a2accu_data3;
   wire [175:0] mac_a2accu_data4;
   wire [175:0] mac_a2accu_data5;
   wire [175:0] mac_a2accu_data6;
   wire [175:0] mac_a2accu_data7;
   wire [7:0] mac_a2accu_mask;
   wire [7:0] mac_a2accu_mode;
   wire [8:0] mac_a2accu_pd;
   wire mac_a2accu_pvld;
   wire [175:0] mac_b2accu_data0;
   wire [175:0] mac_b2accu_data1;
   wire [175:0] mac_b2accu_data2;
   wire [175:0] mac_b2accu_data3;
   wire [175:0] mac_b2accu_data4;
   wire [175:0] mac_b2accu_data5;
   wire [175:0] mac_b2accu_data6;
   wire [175:0] mac_b2accu_data7;
   wire [7:0] mac_b2accu_mask;
   wire [7:0] mac_b2accu_mode;
   wire [8:0] mac_b2accu_pd;
   wire mac_b2accu_pvld;
   wire mcif2cdma_dat_rd_rsp_ready;
   wire mcif2cdma_wt_rd_rsp_ready;
   wire [11:0] sc2buf_dat_rd_addr;
   wire [1023:0] sc2buf_dat_rd_data;
   wire sc2buf_dat_rd_en;
   wire sc2buf_dat_rd_valid;
   wire [7:0] sc2buf_wmb_rd_addr;
   wire [1023:0] sc2buf_wmb_rd_data;
   wire sc2buf_wmb_rd_en;
   wire sc2buf_wmb_rd_valid;
   wire [11:0] sc2buf_wt_rd_addr;
   wire [1023:0] sc2buf_wt_rd_data;
   wire sc2buf_wt_rd_en;
   wire sc2buf_wt_rd_valid;
   wire [11:0] sc2cdma_dat_entries;
   wire sc2cdma_dat_pending_req;
   wire [11:0] sc2cdma_dat_slices;
   wire sc2cdma_dat_updt;
   wire [8:0] sc2cdma_wmb_entries;
   wire [11:0] sc2cdma_wt_entries;
   wire [13:0] sc2cdma_wt_kernels;
   wire sc2cdma_wt_pending_req;
   wire sc2cdma_wt_updt;
   wire [7:0] sc2mac_dat_a_data0;
   wire [7:0] sc2mac_dat_a_data1;
   wire [7:0] sc2mac_dat_a_data10;
   wire [7:0] sc2mac_dat_a_data100;
   wire [7:0] sc2mac_dat_a_data101;
   wire [7:0] sc2mac_dat_a_data102;
   wire [7:0] sc2mac_dat_a_data103;
   wire [7:0] sc2mac_dat_a_data104;
   wire [7:0] sc2mac_dat_a_data105;
   wire [7:0] sc2mac_dat_a_data106;
   wire [7:0] sc2mac_dat_a_data107;
   wire [7:0] sc2mac_dat_a_data108;
   wire [7:0] sc2mac_dat_a_data109;
   wire [7:0] sc2mac_dat_a_data11;
   wire [7:0] sc2mac_dat_a_data110;
   wire [7:0] sc2mac_dat_a_data111;
   wire [7:0] sc2mac_dat_a_data112;
   wire [7:0] sc2mac_dat_a_data113;
   wire [7:0] sc2mac_dat_a_data114;
   wire [7:0] sc2mac_dat_a_data115;
   wire [7:0] sc2mac_dat_a_data116;
   wire [7:0] sc2mac_dat_a_data117;
   wire [7:0] sc2mac_dat_a_data118;
   wire [7:0] sc2mac_dat_a_data119;
   wire [7:0] sc2mac_dat_a_data12;
   wire [7:0] sc2mac_dat_a_data120;
   wire [7:0] sc2mac_dat_a_data121;
   wire [7:0] sc2mac_dat_a_data122;
   wire [7:0] sc2mac_dat_a_data123;
   wire [7:0] sc2mac_dat_a_data124;
   wire [7:0] sc2mac_dat_a_data125;
   wire [7:0] sc2mac_dat_a_data126;
   wire [7:0] sc2mac_dat_a_data127;
   wire [7:0] sc2mac_dat_a_data13;
   wire [7:0] sc2mac_dat_a_data14;
   wire [7:0] sc2mac_dat_a_data15;
   wire [7:0] sc2mac_dat_a_data16;
   wire [7:0] sc2mac_dat_a_data17;
   wire [7:0] sc2mac_dat_a_data18;
   wire [7:0] sc2mac_dat_a_data19;
   wire [7:0] sc2mac_dat_a_data2;
   wire [7:0] sc2mac_dat_a_data20;
   wire [7:0] sc2mac_dat_a_data21;
   wire [7:0] sc2mac_dat_a_data22;
   wire [7:0] sc2mac_dat_a_data23;
   wire [7:0] sc2mac_dat_a_data24;
   wire [7:0] sc2mac_dat_a_data25;
   wire [7:0] sc2mac_dat_a_data26;
   wire [7:0] sc2mac_dat_a_data27;
   wire [7:0] sc2mac_dat_a_data28;
   wire [7:0] sc2mac_dat_a_data29;
   wire [7:0] sc2mac_dat_a_data3;
   wire [7:0] sc2mac_dat_a_data30;
   wire [7:0] sc2mac_dat_a_data31;
   wire [7:0] sc2mac_dat_a_data32;
   wire [7:0] sc2mac_dat_a_data33;
   wire [7:0] sc2mac_dat_a_data34;
   wire [7:0] sc2mac_dat_a_data35;
   wire [7:0] sc2mac_dat_a_data36;
   wire [7:0] sc2mac_dat_a_data37;
   wire [7:0] sc2mac_dat_a_data38;
   wire [7:0] sc2mac_dat_a_data39;
   wire [7:0] sc2mac_dat_a_data4;
   wire [7:0] sc2mac_dat_a_data40;
   wire [7:0] sc2mac_dat_a_data41;
   wire [7:0] sc2mac_dat_a_data42;
   wire [7:0] sc2mac_dat_a_data43;
   wire [7:0] sc2mac_dat_a_data44;
   wire [7:0] sc2mac_dat_a_data45;
   wire [7:0] sc2mac_dat_a_data46;
   wire [7:0] sc2mac_dat_a_data47;
   wire [7:0] sc2mac_dat_a_data48;
   wire [7:0] sc2mac_dat_a_data49;
   wire [7:0] sc2mac_dat_a_data5;
   wire [7:0] sc2mac_dat_a_data50;
   wire [7:0] sc2mac_dat_a_data51;
   wire [7:0] sc2mac_dat_a_data52;
   wire [7:0] sc2mac_dat_a_data53;
   wire [7:0] sc2mac_dat_a_data54;
   wire [7:0] sc2mac_dat_a_data55;
   wire [7:0] sc2mac_dat_a_data56;
   wire [7:0] sc2mac_dat_a_data57;
   wire [7:0] sc2mac_dat_a_data58;
   wire [7:0] sc2mac_dat_a_data59;
   wire [7:0] sc2mac_dat_a_data6;
   wire [7:0] sc2mac_dat_a_data60;
   wire [7:0] sc2mac_dat_a_data61;
   wire [7:0] sc2mac_dat_a_data62;
   wire [7:0] sc2mac_dat_a_data63;
   wire [7:0] sc2mac_dat_a_data64;
   wire [7:0] sc2mac_dat_a_data65;
   wire [7:0] sc2mac_dat_a_data66;
   wire [7:0] sc2mac_dat_a_data67;
   wire [7:0] sc2mac_dat_a_data68;
   wire [7:0] sc2mac_dat_a_data69;
   wire [7:0] sc2mac_dat_a_data7;
   wire [7:0] sc2mac_dat_a_data70;
   wire [7:0] sc2mac_dat_a_data71;
   wire [7:0] sc2mac_dat_a_data72;
   wire [7:0] sc2mac_dat_a_data73;
   wire [7:0] sc2mac_dat_a_data74;
   wire [7:0] sc2mac_dat_a_data75;
   wire [7:0] sc2mac_dat_a_data76;
   wire [7:0] sc2mac_dat_a_data77;
   wire [7:0] sc2mac_dat_a_data78;
   wire [7:0] sc2mac_dat_a_data79;
   wire [7:0] sc2mac_dat_a_data8;
   wire [7:0] sc2mac_dat_a_data80;
   wire [7:0] sc2mac_dat_a_data81;
   wire [7:0] sc2mac_dat_a_data82;
   wire [7:0] sc2mac_dat_a_data83;
   wire [7:0] sc2mac_dat_a_data84;
   wire [7:0] sc2mac_dat_a_data85;
   wire [7:0] sc2mac_dat_a_data86;
   wire [7:0] sc2mac_dat_a_data87;
   wire [7:0] sc2mac_dat_a_data88;
   wire [7:0] sc2mac_dat_a_data89;
   wire [7:0] sc2mac_dat_a_data9;
   wire [7:0] sc2mac_dat_a_data90;
   wire [7:0] sc2mac_dat_a_data91;
   wire [7:0] sc2mac_dat_a_data92;
   wire [7:0] sc2mac_dat_a_data93;
   wire [7:0] sc2mac_dat_a_data94;
   wire [7:0] sc2mac_dat_a_data95;
   wire [7:0] sc2mac_dat_a_data96;
   wire [7:0] sc2mac_dat_a_data97;
   wire [7:0] sc2mac_dat_a_data98;
   wire [7:0] sc2mac_dat_a_data99;
   wire [127:0] sc2mac_dat_a_mask;
   wire [8:0] sc2mac_dat_a_pd;
   wire sc2mac_dat_a_pvld;
   wire [7:0] sc2mac_dat_b_data0;
   wire [7:0] sc2mac_dat_b_data1;
   wire [7:0] sc2mac_dat_b_data10;
   wire [7:0] sc2mac_dat_b_data100;
   wire [7:0] sc2mac_dat_b_data101;
   wire [7:0] sc2mac_dat_b_data102;
   wire [7:0] sc2mac_dat_b_data103;
   wire [7:0] sc2mac_dat_b_data104;
   wire [7:0] sc2mac_dat_b_data105;
   wire [7:0] sc2mac_dat_b_data106;
   wire [7:0] sc2mac_dat_b_data107;
   wire [7:0] sc2mac_dat_b_data108;
   wire [7:0] sc2mac_dat_b_data109;
   wire [7:0] sc2mac_dat_b_data11;
   wire [7:0] sc2mac_dat_b_data110;
   wire [7:0] sc2mac_dat_b_data111;
   wire [7:0] sc2mac_dat_b_data112;
   wire [7:0] sc2mac_dat_b_data113;
   wire [7:0] sc2mac_dat_b_data114;
   wire [7:0] sc2mac_dat_b_data115;
   wire [7:0] sc2mac_dat_b_data116;
   wire [7:0] sc2mac_dat_b_data117;
   wire [7:0] sc2mac_dat_b_data118;
   wire [7:0] sc2mac_dat_b_data119;
   wire [7:0] sc2mac_dat_b_data12;
   wire [7:0] sc2mac_dat_b_data120;
   wire [7:0] sc2mac_dat_b_data121;
   wire [7:0] sc2mac_dat_b_data122;
   wire [7:0] sc2mac_dat_b_data123;
   wire [7:0] sc2mac_dat_b_data124;
   wire [7:0] sc2mac_dat_b_data125;
   wire [7:0] sc2mac_dat_b_data126;
   wire [7:0] sc2mac_dat_b_data127;
   wire [7:0] sc2mac_dat_b_data13;
   wire [7:0] sc2mac_dat_b_data14;
   wire [7:0] sc2mac_dat_b_data15;
   wire [7:0] sc2mac_dat_b_data16;
   wire [7:0] sc2mac_dat_b_data17;
   wire [7:0] sc2mac_dat_b_data18;
   wire [7:0] sc2mac_dat_b_data19;
   wire [7:0] sc2mac_dat_b_data2;
   wire [7:0] sc2mac_dat_b_data20;
   wire [7:0] sc2mac_dat_b_data21;
   wire [7:0] sc2mac_dat_b_data22;
   wire [7:0] sc2mac_dat_b_data23;
   wire [7:0] sc2mac_dat_b_data24;
   wire [7:0] sc2mac_dat_b_data25;
   wire [7:0] sc2mac_dat_b_data26;
   wire [7:0] sc2mac_dat_b_data27;
   wire [7:0] sc2mac_dat_b_data28;
   wire [7:0] sc2mac_dat_b_data29;
   wire [7:0] sc2mac_dat_b_data3;
   wire [7:0] sc2mac_dat_b_data30;
   wire [7:0] sc2mac_dat_b_data31;
   wire [7:0] sc2mac_dat_b_data32;
   wire [7:0] sc2mac_dat_b_data33;
   wire [7:0] sc2mac_dat_b_data34;
   wire [7:0] sc2mac_dat_b_data35;
   wire [7:0] sc2mac_dat_b_data36;
   wire [7:0] sc2mac_dat_b_data37;
   wire [7:0] sc2mac_dat_b_data38;
   wire [7:0] sc2mac_dat_b_data39;
   wire [7:0] sc2mac_dat_b_data4;
   wire [7:0] sc2mac_dat_b_data40;
   wire [7:0] sc2mac_dat_b_data41;
   wire [7:0] sc2mac_dat_b_data42;
   wire [7:0] sc2mac_dat_b_data43;
   wire [7:0] sc2mac_dat_b_data44;
   wire [7:0] sc2mac_dat_b_data45;
   wire [7:0] sc2mac_dat_b_data46;
   wire [7:0] sc2mac_dat_b_data47;
   wire [7:0] sc2mac_dat_b_data48;
   wire [7:0] sc2mac_dat_b_data49;
   wire [7:0] sc2mac_dat_b_data5;
   wire [7:0] sc2mac_dat_b_data50;
   wire [7:0] sc2mac_dat_b_data51;
   wire [7:0] sc2mac_dat_b_data52;
   wire [7:0] sc2mac_dat_b_data53;
   wire [7:0] sc2mac_dat_b_data54;
   wire [7:0] sc2mac_dat_b_data55;
   wire [7:0] sc2mac_dat_b_data56;
   wire [7:0] sc2mac_dat_b_data57;
   wire [7:0] sc2mac_dat_b_data58;
   wire [7:0] sc2mac_dat_b_data59;
   wire [7:0] sc2mac_dat_b_data6;
   wire [7:0] sc2mac_dat_b_data60;
   wire [7:0] sc2mac_dat_b_data61;
   wire [7:0] sc2mac_dat_b_data62;
   wire [7:0] sc2mac_dat_b_data63;
   wire [7:0] sc2mac_dat_b_data64;
   wire [7:0] sc2mac_dat_b_data65;
   wire [7:0] sc2mac_dat_b_data66;
   wire [7:0] sc2mac_dat_b_data67;
   wire [7:0] sc2mac_dat_b_data68;
   wire [7:0] sc2mac_dat_b_data69;
   wire [7:0] sc2mac_dat_b_data7;
   wire [7:0] sc2mac_dat_b_data70;
   wire [7:0] sc2mac_dat_b_data71;
   wire [7:0] sc2mac_dat_b_data72;
   wire [7:0] sc2mac_dat_b_data73;
   wire [7:0] sc2mac_dat_b_data74;
   wire [7:0] sc2mac_dat_b_data75;
   wire [7:0] sc2mac_dat_b_data76;
   wire [7:0] sc2mac_dat_b_data77;
   wire [7:0] sc2mac_dat_b_data78;
   wire [7:0] sc2mac_dat_b_data79;
   wire [7:0] sc2mac_dat_b_data8;
   wire [7:0] sc2mac_dat_b_data80;
   wire [7:0] sc2mac_dat_b_data81;
   wire [7:0] sc2mac_dat_b_data82;
   wire [7:0] sc2mac_dat_b_data83;
   wire [7:0] sc2mac_dat_b_data84;
   wire [7:0] sc2mac_dat_b_data85;
   wire [7:0] sc2mac_dat_b_data86;
   wire [7:0] sc2mac_dat_b_data87;
   wire [7:0] sc2mac_dat_b_data88;
   wire [7:0] sc2mac_dat_b_data89;
   wire [7:0] sc2mac_dat_b_data9;
   wire [7:0] sc2mac_dat_b_data90;
   wire [7:0] sc2mac_dat_b_data91;
   wire [7:0] sc2mac_dat_b_data92;
   wire [7:0] sc2mac_dat_b_data93;
   wire [7:0] sc2mac_dat_b_data94;
   wire [7:0] sc2mac_dat_b_data95;
   wire [7:0] sc2mac_dat_b_data96;
   wire [7:0] sc2mac_dat_b_data97;
   wire [7:0] sc2mac_dat_b_data98;
   wire [7:0] sc2mac_dat_b_data99;
   wire [127:0] sc2mac_dat_b_mask;
   wire [8:0] sc2mac_dat_b_pd;
   wire sc2mac_dat_b_pvld;
   wire [7:0] sc2mac_wt_a_data0;
   wire [7:0] sc2mac_wt_a_data1;
   wire [7:0] sc2mac_wt_a_data10;
   wire [7:0] sc2mac_wt_a_data100;
   wire [7:0] sc2mac_wt_a_data101;
   wire [7:0] sc2mac_wt_a_data102;
   wire [7:0] sc2mac_wt_a_data103;
   wire [7:0] sc2mac_wt_a_data104;
   wire [7:0] sc2mac_wt_a_data105;
   wire [7:0] sc2mac_wt_a_data106;
   wire [7:0] sc2mac_wt_a_data107;
   wire [7:0] sc2mac_wt_a_data108;
   wire [7:0] sc2mac_wt_a_data109;
   wire [7:0] sc2mac_wt_a_data11;
   wire [7:0] sc2mac_wt_a_data110;
   wire [7:0] sc2mac_wt_a_data111;
   wire [7:0] sc2mac_wt_a_data112;
   wire [7:0] sc2mac_wt_a_data113;
   wire [7:0] sc2mac_wt_a_data114;
   wire [7:0] sc2mac_wt_a_data115;
   wire [7:0] sc2mac_wt_a_data116;
   wire [7:0] sc2mac_wt_a_data117;
   wire [7:0] sc2mac_wt_a_data118;
   wire [7:0] sc2mac_wt_a_data119;
   wire [7:0] sc2mac_wt_a_data12;
   wire [7:0] sc2mac_wt_a_data120;
   wire [7:0] sc2mac_wt_a_data121;
   wire [7:0] sc2mac_wt_a_data122;
   wire [7:0] sc2mac_wt_a_data123;
   wire [7:0] sc2mac_wt_a_data124;
   wire [7:0] sc2mac_wt_a_data125;
   wire [7:0] sc2mac_wt_a_data126;
   wire [7:0] sc2mac_wt_a_data127;
   wire [7:0] sc2mac_wt_a_data13;
   wire [7:0] sc2mac_wt_a_data14;
   wire [7:0] sc2mac_wt_a_data15;
   wire [7:0] sc2mac_wt_a_data16;
   wire [7:0] sc2mac_wt_a_data17;
   wire [7:0] sc2mac_wt_a_data18;
   wire [7:0] sc2mac_wt_a_data19;
   wire [7:0] sc2mac_wt_a_data2;
   wire [7:0] sc2mac_wt_a_data20;
   wire [7:0] sc2mac_wt_a_data21;
   wire [7:0] sc2mac_wt_a_data22;
   wire [7:0] sc2mac_wt_a_data23;
   wire [7:0] sc2mac_wt_a_data24;
   wire [7:0] sc2mac_wt_a_data25;
   wire [7:0] sc2mac_wt_a_data26;
   wire [7:0] sc2mac_wt_a_data27;
   wire [7:0] sc2mac_wt_a_data28;
   wire [7:0] sc2mac_wt_a_data29;
   wire [7:0] sc2mac_wt_a_data3;
   wire [7:0] sc2mac_wt_a_data30;
   wire [7:0] sc2mac_wt_a_data31;
   wire [7:0] sc2mac_wt_a_data32;
   wire [7:0] sc2mac_wt_a_data33;
   wire [7:0] sc2mac_wt_a_data34;
   wire [7:0] sc2mac_wt_a_data35;
   wire [7:0] sc2mac_wt_a_data36;
   wire [7:0] sc2mac_wt_a_data37;
   wire [7:0] sc2mac_wt_a_data38;
   wire [7:0] sc2mac_wt_a_data39;
   wire [7:0] sc2mac_wt_a_data4;
   wire [7:0] sc2mac_wt_a_data40;
   wire [7:0] sc2mac_wt_a_data41;
   wire [7:0] sc2mac_wt_a_data42;
   wire [7:0] sc2mac_wt_a_data43;
   wire [7:0] sc2mac_wt_a_data44;
   wire [7:0] sc2mac_wt_a_data45;
   wire [7:0] sc2mac_wt_a_data46;
   wire [7:0] sc2mac_wt_a_data47;
   wire [7:0] sc2mac_wt_a_data48;
   wire [7:0] sc2mac_wt_a_data49;
   wire [7:0] sc2mac_wt_a_data5;
   wire [7:0] sc2mac_wt_a_data50;
   wire [7:0] sc2mac_wt_a_data51;
   wire [7:0] sc2mac_wt_a_data52;
   wire [7:0] sc2mac_wt_a_data53;
   wire [7:0] sc2mac_wt_a_data54;
   wire [7:0] sc2mac_wt_a_data55;
   wire [7:0] sc2mac_wt_a_data56;
   wire [7:0] sc2mac_wt_a_data57;
   wire [7:0] sc2mac_wt_a_data58;
   wire [7:0] sc2mac_wt_a_data59;
   wire [7:0] sc2mac_wt_a_data6;
   wire [7:0] sc2mac_wt_a_data60;
   wire [7:0] sc2mac_wt_a_data61;
   wire [7:0] sc2mac_wt_a_data62;
   wire [7:0] sc2mac_wt_a_data63;
   wire [7:0] sc2mac_wt_a_data64;
   wire [7:0] sc2mac_wt_a_data65;
   wire [7:0] sc2mac_wt_a_data66;
   wire [7:0] sc2mac_wt_a_data67;
   wire [7:0] sc2mac_wt_a_data68;
   wire [7:0] sc2mac_wt_a_data69;
   wire [7:0] sc2mac_wt_a_data7;
   wire [7:0] sc2mac_wt_a_data70;
   wire [7:0] sc2mac_wt_a_data71;
   wire [7:0] sc2mac_wt_a_data72;
   wire [7:0] sc2mac_wt_a_data73;
   wire [7:0] sc2mac_wt_a_data74;
   wire [7:0] sc2mac_wt_a_data75;
   wire [7:0] sc2mac_wt_a_data76;
   wire [7:0] sc2mac_wt_a_data77;
   wire [7:0] sc2mac_wt_a_data78;
   wire [7:0] sc2mac_wt_a_data79;
   wire [7:0] sc2mac_wt_a_data8;
   wire [7:0] sc2mac_wt_a_data80;
   wire [7:0] sc2mac_wt_a_data81;
   wire [7:0] sc2mac_wt_a_data82;
   wire [7:0] sc2mac_wt_a_data83;
   wire [7:0] sc2mac_wt_a_data84;
   wire [7:0] sc2mac_wt_a_data85;
   wire [7:0] sc2mac_wt_a_data86;
   wire [7:0] sc2mac_wt_a_data87;
   wire [7:0] sc2mac_wt_a_data88;
   wire [7:0] sc2mac_wt_a_data89;
   wire [7:0] sc2mac_wt_a_data9;
   wire [7:0] sc2mac_wt_a_data90;
   wire [7:0] sc2mac_wt_a_data91;
   wire [7:0] sc2mac_wt_a_data92;
   wire [7:0] sc2mac_wt_a_data93;
   wire [7:0] sc2mac_wt_a_data94;
   wire [7:0] sc2mac_wt_a_data95;
   wire [7:0] sc2mac_wt_a_data96;
   wire [7:0] sc2mac_wt_a_data97;
   wire [7:0] sc2mac_wt_a_data98;
   wire [7:0] sc2mac_wt_a_data99;
   wire [127:0] sc2mac_wt_a_mask;
   wire sc2mac_wt_a_pvld;
   wire [7:0] sc2mac_wt_a_sel;
   wire [7:0] sc2mac_wt_b_data0;
   wire [7:0] sc2mac_wt_b_data1;
   wire [7:0] sc2mac_wt_b_data10;
   wire [7:0] sc2mac_wt_b_data100;
   wire [7:0] sc2mac_wt_b_data101;
   wire [7:0] sc2mac_wt_b_data102;
   wire [7:0] sc2mac_wt_b_data103;
   wire [7:0] sc2mac_wt_b_data104;
   wire [7:0] sc2mac_wt_b_data105;
   wire [7:0] sc2mac_wt_b_data106;
   wire [7:0] sc2mac_wt_b_data107;
   wire [7:0] sc2mac_wt_b_data108;
   wire [7:0] sc2mac_wt_b_data109;
   wire [7:0] sc2mac_wt_b_data11;
   wire [7:0] sc2mac_wt_b_data110;
   wire [7:0] sc2mac_wt_b_data111;
   wire [7:0] sc2mac_wt_b_data112;
   wire [7:0] sc2mac_wt_b_data113;
   wire [7:0] sc2mac_wt_b_data114;
   wire [7:0] sc2mac_wt_b_data115;
   wire [7:0] sc2mac_wt_b_data116;
   wire [7:0] sc2mac_wt_b_data117;
   wire [7:0] sc2mac_wt_b_data118;
   wire [7:0] sc2mac_wt_b_data119;
   wire [7:0] sc2mac_wt_b_data12;
   wire [7:0] sc2mac_wt_b_data120;
   wire [7:0] sc2mac_wt_b_data121;
   wire [7:0] sc2mac_wt_b_data122;
   wire [7:0] sc2mac_wt_b_data123;
   wire [7:0] sc2mac_wt_b_data124;
   wire [7:0] sc2mac_wt_b_data125;
   wire [7:0] sc2mac_wt_b_data126;
   wire [7:0] sc2mac_wt_b_data127;
   wire [7:0] sc2mac_wt_b_data13;
   wire [7:0] sc2mac_wt_b_data14;
   wire [7:0] sc2mac_wt_b_data15;
   wire [7:0] sc2mac_wt_b_data16;
   wire [7:0] sc2mac_wt_b_data17;
   wire [7:0] sc2mac_wt_b_data18;
   wire [7:0] sc2mac_wt_b_data19;
   wire [7:0] sc2mac_wt_b_data2;
   wire [7:0] sc2mac_wt_b_data20;
   wire [7:0] sc2mac_wt_b_data21;
   wire [7:0] sc2mac_wt_b_data22;
   wire [7:0] sc2mac_wt_b_data23;
   wire [7:0] sc2mac_wt_b_data24;
   wire [7:0] sc2mac_wt_b_data25;
   wire [7:0] sc2mac_wt_b_data26;
   wire [7:0] sc2mac_wt_b_data27;
   wire [7:0] sc2mac_wt_b_data28;
   wire [7:0] sc2mac_wt_b_data29;
   wire [7:0] sc2mac_wt_b_data3;
   wire [7:0] sc2mac_wt_b_data30;
   wire [7:0] sc2mac_wt_b_data31;
   wire [7:0] sc2mac_wt_b_data32;
   wire [7:0] sc2mac_wt_b_data33;
   wire [7:0] sc2mac_wt_b_data34;
   wire [7:0] sc2mac_wt_b_data35;
   wire [7:0] sc2mac_wt_b_data36;
   wire [7:0] sc2mac_wt_b_data37;
   wire [7:0] sc2mac_wt_b_data38;
   wire [7:0] sc2mac_wt_b_data39;
   wire [7:0] sc2mac_wt_b_data4;
   wire [7:0] sc2mac_wt_b_data40;
   wire [7:0] sc2mac_wt_b_data41;
   wire [7:0] sc2mac_wt_b_data42;
   wire [7:0] sc2mac_wt_b_data43;
   wire [7:0] sc2mac_wt_b_data44;
   wire [7:0] sc2mac_wt_b_data45;
   wire [7:0] sc2mac_wt_b_data46;
   wire [7:0] sc2mac_wt_b_data47;
   wire [7:0] sc2mac_wt_b_data48;
   wire [7:0] sc2mac_wt_b_data49;
   wire [7:0] sc2mac_wt_b_data5;
   wire [7:0] sc2mac_wt_b_data50;
   wire [7:0] sc2mac_wt_b_data51;
   wire [7:0] sc2mac_wt_b_data52;
   wire [7:0] sc2mac_wt_b_data53;
   wire [7:0] sc2mac_wt_b_data54;
   wire [7:0] sc2mac_wt_b_data55;
   wire [7:0] sc2mac_wt_b_data56;
   wire [7:0] sc2mac_wt_b_data57;
   wire [7:0] sc2mac_wt_b_data58;
   wire [7:0] sc2mac_wt_b_data59;
   wire [7:0] sc2mac_wt_b_data6;
   wire [7:0] sc2mac_wt_b_data60;
   wire [7:0] sc2mac_wt_b_data61;
   wire [7:0] sc2mac_wt_b_data62;
   wire [7:0] sc2mac_wt_b_data63;
   wire [7:0] sc2mac_wt_b_data64;
   wire [7:0] sc2mac_wt_b_data65;
   wire [7:0] sc2mac_wt_b_data66;
   wire [7:0] sc2mac_wt_b_data67;
   wire [7:0] sc2mac_wt_b_data68;
   wire [7:0] sc2mac_wt_b_data69;
   wire [7:0] sc2mac_wt_b_data7;
   wire [7:0] sc2mac_wt_b_data70;
   wire [7:0] sc2mac_wt_b_data71;
   wire [7:0] sc2mac_wt_b_data72;
   wire [7:0] sc2mac_wt_b_data73;
   wire [7:0] sc2mac_wt_b_data74;
   wire [7:0] sc2mac_wt_b_data75;
   wire [7:0] sc2mac_wt_b_data76;
   wire [7:0] sc2mac_wt_b_data77;
   wire [7:0] sc2mac_wt_b_data78;
   wire [7:0] sc2mac_wt_b_data79;
   wire [7:0] sc2mac_wt_b_data8;
   wire [7:0] sc2mac_wt_b_data80;
   wire [7:0] sc2mac_wt_b_data81;
   wire [7:0] sc2mac_wt_b_data82;
   wire [7:0] sc2mac_wt_b_data83;
   wire [7:0] sc2mac_wt_b_data84;
   wire [7:0] sc2mac_wt_b_data85;
   wire [7:0] sc2mac_wt_b_data86;
   wire [7:0] sc2mac_wt_b_data87;
   wire [7:0] sc2mac_wt_b_data88;
   wire [7:0] sc2mac_wt_b_data89;
   wire [7:0] sc2mac_wt_b_data9;
   wire [7:0] sc2mac_wt_b_data90;
   wire [7:0] sc2mac_wt_b_data91;
   wire [7:0] sc2mac_wt_b_data92;
   wire [7:0] sc2mac_wt_b_data93;
   wire [7:0] sc2mac_wt_b_data94;
   wire [7:0] sc2mac_wt_b_data95;
   wire [7:0] sc2mac_wt_b_data96;
   wire [7:0] sc2mac_wt_b_data97;
   wire [7:0] sc2mac_wt_b_data98;
   wire [7:0] sc2mac_wt_b_data99;
   wire [127:0] sc2mac_wt_b_mask;
   wire sc2mac_wt_b_pvld;
   wire [7:0] sc2mac_wt_b_sel;

   NV_NVDLA_cdma u_cdma (
      .nvdla_core_clk              (nvdla_core_clk),
      .nvdla_core_rstn             (nvdla_core_rstn),
      .cdma2buf_dat_wr_en          (cdma2buf_dat_wr_en),
      .cdma2buf_dat_wr_addr        (cdma2buf_dat_wr_addr),
      .cdma2buf_dat_wr_hsel        (cdma2buf_dat_wr_hsel),
      .cdma2buf_dat_wr_data        (cdma2buf_dat_wr_data),
      .cdma2buf_wt_wr_en           (cdma2buf_wt_wr_en),
      .cdma2buf_wt_wr_addr         (cdma2buf_wt_wr_addr),
      .cdma2buf_wt_wr_hsel         (cdma2buf_wt_wr_hsel),
      .cdma2buf_wt_wr_data         (cdma2buf_wt_wr_data),
      .cdma2csb_resp_valid         (cdma2csb_resp_valid),
      .cdma2csb_resp_pd            (cdma2csb_resp_pd),
      .cdma2sc_dat_pending_ack     (cdma2sc_dat_pending_ack),
      .cdma2sc_wt_pending_ack      (cdma2sc_wt_pending_ack),
      .cdma_dat2cvif_rd_req_valid  (cdma_dat2cvif_rd_req_valid),
      .cdma_dat2cvif_rd_req_ready  (cdma_dat2cvif_rd_req_ready),
      .cdma_dat2cvif_rd_req_pd     (cdma_dat2cvif_rd_req_pd),
      .cdma_dat2glb_done_intr_pd   (cdma_dat2glb_done_intr_pd),
      .cdma_dat2mcif_rd_req_valid  (cdma_dat2mcif_rd_req_valid),
      .cdma_dat2mcif_rd_req_ready  (cdma_dat2mcif_rd_req_ready),
      .cdma_dat2mcif_rd_req_pd     (cdma_dat2mcif_rd_req_pd),
      .cdma_wt2cvif_rd_req_valid   (cdma_wt2cvif_rd_req_valid),
      .cdma_wt2cvif_rd_req_ready   (cdma_wt2cvif_rd_req_ready),
      .cdma_wt2cvif_rd_req_pd      (cdma_wt2cvif_rd_req_pd),
      .cdma_wt2glb_done_intr_pd    (cdma_wt2glb_done_intr_pd),
      .cdma_wt2mcif_rd_req_valid   (cdma_wt2mcif_rd_req_valid),
      .cdma_wt2mcif_rd_req_ready   (cdma_wt2mcif_rd_req_ready),
      .cdma_wt2mcif_rd_req_pd      (cdma_wt2mcif_rd_req_pd),
      .csb2cdma_req_pvld           (csb2cdma_req_pvld),
      .csb2cdma_req_prdy           (csb2cdma_req_prdy),
      .csb2cdma_req_pd             (csb2cdma_req_pd),
      .cvif2cdma_dat_rd_rsp_valid  (cvif2cdma_dat_rd_rsp_valid),
      .cvif2cdma_dat_rd_rsp_ready  (cvif2cdma_dat_rd_rsp_ready),
      .cvif2cdma_dat_rd_rsp_pd     (cvif2cdma_dat_rd_rsp_pd),
      .cvif2cdma_wt_rd_rsp_valid   (cvif2cdma_wt_rd_rsp_valid),
      .cvif2cdma_wt_rd_rsp_ready   (cvif2cdma_wt_rd_rsp_ready),
      .cvif2cdma_wt_rd_rsp_pd      (cvif2cdma_wt_rd_rsp_pd),
      .cdma2sc_dat_updt            (cdma2sc_dat_updt),
      .cdma2sc_dat_entries         (cdma2sc_dat_entries),
      .cdma2sc_dat_slices          (cdma2sc_dat_slices),
      .sc2cdma_dat_updt            (sc2cdma_dat_updt),
      .sc2cdma_dat_entries         (sc2cdma_dat_entries),
      .sc2cdma_dat_slices          (sc2cdma_dat_slices),
      .mcif2cdma_dat_rd_rsp_valid  (mcif2cdma_dat_rd_rsp_valid),
      .mcif2cdma_dat_rd_rsp_ready  (mcif2cdma_dat_rd_rsp_ready),
      .mcif2cdma_dat_rd_rsp_pd     (mcif2cdma_dat_rd_rsp_pd),
      .mcif2cdma_wt_rd_rsp_valid   (mcif2cdma_wt_rd_rsp_valid),
      .mcif2cdma_wt_rd_rsp_ready   (mcif2cdma_wt_rd_rsp_ready),
      .mcif2cdma_wt_rd_rsp_pd      (mcif2cdma_wt_rd_rsp_pd),
      .pwrbus_ram_pd               (pwrbus_ram_pd),
      .sc2cdma_dat_pending_req     (sc2cdma_dat_pending_req),
      .sc2cdma_wt_pending_req      (sc2cdma_wt_pending_req),
      .cdma2sc_wt_updt             (cdma2sc_wt_updt),
      .cdma2sc_wt_kernels          (cdma2sc_wt_kernels),
      .cdma2sc_wt_entries          (cdma2sc_wt_entries),
      .cdma2sc_wmb_entries         (cdma2sc_wmb_entries),
      .sc2cdma_wt_updt             (sc2cdma_wt_updt),
      .sc2cdma_wt_kernels          (sc2cdma_wt_kernels),
      .sc2cdma_wt_entries          (sc2cdma_wt_entries),
      .sc2cdma_wmb_entries         (sc2cdma_wmb_entries),
      .dla_clk_ovr_on_sync         (dla_clk_ovr_on_sync),
      .global_clk_ovr_on_sync      (global_clk_ovr_on_sync),
      .tmc2slcg_disable_clock_gating(tmc2slcg_disable_clock_gating)
   );

   NV_NVDLA_cbuf u_cbuf (
      .nvdla_core_clk              (nvdla_core_clk),
      .nvdla_core_rstn             (nvdla_core_rstn),
      .pwrbus_ram_pd               (pwrbus_ram_pd),
      .cdma2buf_dat_wr_en          (cdma2buf_dat_wr_en),
      .cdma2buf_dat_wr_addr        (cdma2buf_dat_wr_addr),
      .cdma2buf_dat_wr_hsel        (cdma2buf_dat_wr_hsel),
      .cdma2buf_dat_wr_data        (cdma2buf_dat_wr_data),
      .cdma2buf_wt_wr_en           (cdma2buf_wt_wr_en),
      .cdma2buf_wt_wr_addr         (cdma2buf_wt_wr_addr),
      .cdma2buf_wt_wr_hsel         (cdma2buf_wt_wr_hsel),
      .cdma2buf_wt_wr_data         (cdma2buf_wt_wr_data),
      .sc2buf_dat_rd_en            (sc2buf_dat_rd_en),
      .sc2buf_dat_rd_addr          (sc2buf_dat_rd_addr),
      .sc2buf_dat_rd_valid         (sc2buf_dat_rd_valid),
      .sc2buf_dat_rd_data          (sc2buf_dat_rd_data),
      .sc2buf_wt_rd_en             (sc2buf_wt_rd_en),
      .sc2buf_wt_rd_addr           (sc2buf_wt_rd_addr),
      .sc2buf_wt_rd_valid          (sc2buf_wt_rd_valid),
      .sc2buf_wt_rd_data           (sc2buf_wt_rd_data),
      .sc2buf_wmb_rd_en            (sc2buf_wmb_rd_en),
      .sc2buf_wmb_rd_addr          (sc2buf_wmb_rd_addr),
      .sc2buf_wmb_rd_valid         (sc2buf_wmb_rd_valid),
      .sc2buf_wmb_rd_data          (sc2buf_wmb_rd_data)
   );

   NV_NVDLA_csc u_csc (
      .nvdla_core_clk              (nvdla_core_clk),
      .nvdla_core_rstn             (nvdla_core_rstn),
      .sc2cdma_dat_pending_req     (sc2cdma_dat_pending_req),
      .sc2cdma_wt_pending_req      (sc2cdma_wt_pending_req),
      .accu2sc_credit_vld          (accu2sc_credit_vld),
      .accu2sc_credit_size         (accu2sc_credit_size),
      .cdma2sc_dat_pending_ack     (cdma2sc_dat_pending_ack),
      .cdma2sc_wt_pending_ack      (cdma2sc_wt_pending_ack),
      .csb2csc_req_pvld            (csb2csc_req_pvld),
      .csb2csc_req_prdy            (csb2csc_req_prdy),
      .csb2csc_req_pd              (csb2csc_req_pd),
      .csc2csb_resp_valid          (csc2csb_resp_valid),
      .csc2csb_resp_pd             (csc2csb_resp_pd),
      .cdma2sc_dat_updt            (cdma2sc_dat_updt),
      .cdma2sc_dat_entries         (cdma2sc_dat_entries),
      .cdma2sc_dat_slices          (cdma2sc_dat_slices),
      .sc2cdma_dat_updt            (sc2cdma_dat_updt),
      .sc2cdma_dat_entries         (sc2cdma_dat_entries),
      .sc2cdma_dat_slices          (sc2cdma_dat_slices),
      .pwrbus_ram_pd               (pwrbus_ram_pd),
      .sc2buf_dat_rd_en            (sc2buf_dat_rd_en),
      .sc2buf_dat_rd_addr          (sc2buf_dat_rd_addr),
      .sc2buf_dat_rd_valid         (sc2buf_dat_rd_valid),
      .sc2buf_dat_rd_data          (sc2buf_dat_rd_data),
      .sc2buf_wmb_rd_en            (sc2buf_wmb_rd_en),
      .sc2buf_wmb_rd_addr          (sc2buf_wmb_rd_addr),
      .sc2buf_wmb_rd_valid         (sc2buf_wmb_rd_valid),
      .sc2buf_wmb_rd_data          (sc2buf_wmb_rd_data),
      .sc2buf_wt_rd_en             (sc2buf_wt_rd_en),
      .sc2buf_wt_rd_addr           (sc2buf_wt_rd_addr),
      .sc2buf_wt_rd_valid          (sc2buf_wt_rd_valid),
      .sc2buf_wt_rd_data           (sc2buf_wt_rd_data),
      .sc2mac_dat_a_pvld           (sc2mac_dat_a_pvld),
      .sc2mac_dat_a_mask           (sc2mac_dat_a_mask),
      .sc2mac_dat_a_data0          (sc2mac_dat_a_data0),
      .sc2mac_dat_a_data1          (sc2mac_dat_a_data1),
      .sc2mac_dat_a_data2          (sc2mac_dat_a_data2),
      .sc2mac_dat_a_data3          (sc2mac_dat_a_data3),
      .sc2mac_dat_a_data4          (sc2mac_dat_a_data4),
      .sc2mac_dat_a_data5          (sc2mac_dat_a_data5),
      .sc2mac_dat_a_data6          (sc2mac_dat_a_data6),
      .sc2mac_dat_a_data7          (sc2mac_dat_a_data7),
      .sc2mac_dat_a_data8          (sc2mac_dat_a_data8),
      .sc2mac_dat_a_data9          (sc2mac_dat_a_data9),
      .sc2mac_dat_a_data10         (sc2mac_dat_a_data10),
      .sc2mac_dat_a_data11         (sc2mac_dat_a_data11),
      .sc2mac_dat_a_data12         (sc2mac_dat_a_data12),
      .sc2mac_dat_a_data13         (sc2mac_dat_a_data13),
      .sc2mac_dat_a_data14         (sc2mac_dat_a_data14),
      .sc2mac_dat_a_data15         (sc2mac_dat_a_data15),
      .sc2mac_dat_a_data16         (sc2mac_dat_a_data16),
      .sc2mac_dat_a_data17         (sc2mac_dat_a_data17),
      .sc2mac_dat_a_data18         (sc2mac_dat_a_data18),
      .sc2mac_dat_a_data19         (sc2mac_dat_a_data19),
      .sc2mac_dat_a_data20         (sc2mac_dat_a_data20),
      .sc2mac_dat_a_data21         (sc2mac_dat_a_data21),
      .sc2mac_dat_a_data22         (sc2mac_dat_a_data22),
      .sc2mac_dat_a_data23         (sc2mac_dat_a_data23),
      .sc2mac_dat_a_data24         (sc2mac_dat_a_data24),
      .sc2mac_dat_a_data25         (sc2mac_dat_a_data25),
      .sc2mac_dat_a_data26         (sc2mac_dat_a_data26),
      .sc2mac_dat_a_data27         (sc2mac_dat_a_data27),
      .sc2mac_dat_a_data28         (sc2mac_dat_a_data28),
      .sc2mac_dat_a_data29         (sc2mac_dat_a_data29),
      .sc2mac_dat_a_data30         (sc2mac_dat_a_data30),
      .sc2mac_dat_a_data31         (sc2mac_dat_a_data31),
      .sc2mac_dat_a_data32         (sc2mac_dat_a_data32),
      .sc2mac_dat_a_data33         (sc2mac_dat_a_data33),
      .sc2mac_dat_a_data34         (sc2mac_dat_a_data34),
      .sc2mac_dat_a_data35         (sc2mac_dat_a_data35),
      .sc2mac_dat_a_data36         (sc2mac_dat_a_data36),
      .sc2mac_dat_a_data37         (sc2mac_dat_a_data37),
      .sc2mac_dat_a_data38         (sc2mac_dat_a_data38),
      .sc2mac_dat_a_data39         (sc2mac_dat_a_data39),
      .sc2mac_dat_a_data40         (sc2mac_dat_a_data40),
      .sc2mac_dat_a_data41         (sc2mac_dat_a_data41),
      .sc2mac_dat_a_data42         (sc2mac_dat_a_data42),
      .sc2mac_dat_a_data43         (sc2mac_dat_a_data43),
      .sc2mac_dat_a_data44         (sc2mac_dat_a_data44),
      .sc2mac_dat_a_data45         (sc2mac_dat_a_data45),
      .sc2mac_dat_a_data46         (sc2mac_dat_a_data46),
      .sc2mac_dat_a_data47         (sc2mac_dat_a_data47),
      .sc2mac_dat_a_data48         (sc2mac_dat_a_data48),
      .sc2mac_dat_a_data49         (sc2mac_dat_a_data49),
      .sc2mac_dat_a_data50         (sc2mac_dat_a_data50),
      .sc2mac_dat_a_data51         (sc2mac_dat_a_data51),
      .sc2mac_dat_a_data52         (sc2mac_dat_a_data52),
      .sc2mac_dat_a_data53         (sc2mac_dat_a_data53),
      .sc2mac_dat_a_data54         (sc2mac_dat_a_data54),
      .sc2mac_dat_a_data55         (sc2mac_dat_a_data55),
      .sc2mac_dat_a_data56         (sc2mac_dat_a_data56),
      .sc2mac_dat_a_data57         (sc2mac_dat_a_data57),
      .sc2mac_dat_a_data58         (sc2mac_dat_a_data58),
      .sc2mac_dat_a_data59         (sc2mac_dat_a_data59),
      .sc2mac_dat_a_data60         (sc2mac_dat_a_data60),
      .sc2mac_dat_a_data61         (sc2mac_dat_a_data61),
      .sc2mac_dat_a_data62         (sc2mac_dat_a_data62),
      .sc2mac_dat_a_data63         (sc2mac_dat_a_data63),
      .sc2mac_dat_a_data64         (sc2mac_dat_a_data64),
      .sc2mac_dat_a_data65         (sc2mac_dat_a_data65),
      .sc2mac_dat_a_data66         (sc2mac_dat_a_data66),
      .sc2mac_dat_a_data67         (sc2mac_dat_a_data67),
      .sc2mac_dat_a_data68         (sc2mac_dat_a_data68),
      .sc2mac_dat_a_data69         (sc2mac_dat_a_data69),
      .sc2mac_dat_a_data70         (sc2mac_dat_a_data70),
      .sc2mac_dat_a_data71         (sc2mac_dat_a_data71),
      .sc2mac_dat_a_data72         (sc2mac_dat_a_data72),
      .sc2mac_dat_a_data73         (sc2mac_dat_a_data73),
      .sc2mac_dat_a_data74         (sc2mac_dat_a_data74),
      .sc2mac_dat_a_data75         (sc2mac_dat_a_data75),
      .sc2mac_dat_a_data76         (sc2mac_dat_a_data76),
      .sc2mac_dat_a_data77         (sc2mac_dat_a_data77),
      .sc2mac_dat_a_data78         (sc2mac_dat_a_data78),
      .sc2mac_dat_a_data79         (sc2mac_dat_a_data79),
      .sc2mac_dat_a_data80         (sc2mac_dat_a_data80),
      .sc2mac_dat_a_data81         (sc2mac_dat_a_data81),
      .sc2mac_dat_a_data82         (sc2mac_dat_a_data82),
      .sc2mac_dat_a_data83         (sc2mac_dat_a_data83),
      .sc2mac_dat_a_data84         (sc2mac_dat_a_data84),
      .sc2mac_dat_a_data85         (sc2mac_dat_a_data85),
      .sc2mac_dat_a_data86         (sc2mac_dat_a_data86),
      .sc2mac_dat_a_data87         (sc2mac_dat_a_data87),
      .sc2mac_dat_a_data88         (sc2mac_dat_a_data88),
      .sc2mac_dat_a_data89         (sc2mac_dat_a_data89),
      .sc2mac_dat_a_data90         (sc2mac_dat_a_data90),
      .sc2mac_dat_a_data91         (sc2mac_dat_a_data91),
      .sc2mac_dat_a_data92         (sc2mac_dat_a_data92),
      .sc2mac_dat_a_data93         (sc2mac_dat_a_data93),
      .sc2mac_dat_a_data94         (sc2mac_dat_a_data94),
      .sc2mac_dat_a_data95         (sc2mac_dat_a_data95),
      .sc2mac_dat_a_data96         (sc2mac_dat_a_data96),
      .sc2mac_dat_a_data97         (sc2mac_dat_a_data97),
      .sc2mac_dat_a_data98         (sc2mac_dat_a_data98),
      .sc2mac_dat_a_data99         (sc2mac_dat_a_data99),
      .sc2mac_dat_a_data100        (sc2mac_dat_a_data100),
      .sc2mac_dat_a_data101        (sc2mac_dat_a_data101),
      .sc2mac_dat_a_data102        (sc2mac_dat_a_data102),
      .sc2mac_dat_a_data103        (sc2mac_dat_a_data103),
      .sc2mac_dat_a_data104        (sc2mac_dat_a_data104),
      .sc2mac_dat_a_data105        (sc2mac_dat_a_data105),
      .sc2mac_dat_a_data106        (sc2mac_dat_a_data106),
      .sc2mac_dat_a_data107        (sc2mac_dat_a_data107),
      .sc2mac_dat_a_data108        (sc2mac_dat_a_data108),
      .sc2mac_dat_a_data109        (sc2mac_dat_a_data109),
      .sc2mac_dat_a_data110        (sc2mac_dat_a_data110),
      .sc2mac_dat_a_data111        (sc2mac_dat_a_data111),
      .sc2mac_dat_a_data112        (sc2mac_dat_a_data112),
      .sc2mac_dat_a_data113        (sc2mac_dat_a_data113),
      .sc2mac_dat_a_data114        (sc2mac_dat_a_data114),
      .sc2mac_dat_a_data115        (sc2mac_dat_a_data115),
      .sc2mac_dat_a_data116        (sc2mac_dat_a_data116),
      .sc2mac_dat_a_data117        (sc2mac_dat_a_data117),
      .sc2mac_dat_a_data118        (sc2mac_dat_a_data118),
      .sc2mac_dat_a_data119        (sc2mac_dat_a_data119),
      .sc2mac_dat_a_data120        (sc2mac_dat_a_data120),
      .sc2mac_dat_a_data121        (sc2mac_dat_a_data121),
      .sc2mac_dat_a_data122        (sc2mac_dat_a_data122),
      .sc2mac_dat_a_data123        (sc2mac_dat_a_data123),
      .sc2mac_dat_a_data124        (sc2mac_dat_a_data124),
      .sc2mac_dat_a_data125        (sc2mac_dat_a_data125),
      .sc2mac_dat_a_data126        (sc2mac_dat_a_data126),
      .sc2mac_dat_a_data127        (sc2mac_dat_a_data127),
      .sc2mac_dat_a_pd             (sc2mac_dat_a_pd),
      .sc2mac_dat_b_pvld           (sc2mac_dat_b_pvld),
      .sc2mac_dat_b_mask           (sc2mac_dat_b_mask),
      .sc2mac_dat_b_data0          (sc2mac_dat_b_data0),
      .sc2mac_dat_b_data1          (sc2mac_dat_b_data1),
      .sc2mac_dat_b_data2          (sc2mac_dat_b_data2),
      .sc2mac_dat_b_data3          (sc2mac_dat_b_data3),
      .sc2mac_dat_b_data4          (sc2mac_dat_b_data4),
      .sc2mac_dat_b_data5          (sc2mac_dat_b_data5),
      .sc2mac_dat_b_data6          (sc2mac_dat_b_data6),
      .sc2mac_dat_b_data7          (sc2mac_dat_b_data7),
      .sc2mac_dat_b_data8          (sc2mac_dat_b_data8),
      .sc2mac_dat_b_data9          (sc2mac_dat_b_data9),
      .sc2mac_dat_b_data10         (sc2mac_dat_b_data10),
      .sc2mac_dat_b_data11         (sc2mac_dat_b_data11),
      .sc2mac_dat_b_data12         (sc2mac_dat_b_data12),
      .sc2mac_dat_b_data13         (sc2mac_dat_b_data13),
      .sc2mac_dat_b_data14         (sc2mac_dat_b_data14),
      .sc2mac_dat_b_data15         (sc2mac_dat_b_data15),
      .sc2mac_dat_b_data16         (sc2mac_dat_b_data16),
      .sc2mac_dat_b_data17         (sc2mac_dat_b_data17),
      .sc2mac_dat_b_data18         (sc2mac_dat_b_data18),
      .sc2mac_dat_b_data19         (sc2mac_dat_b_data19),
      .sc2mac_dat_b_data20         (sc2mac_dat_b_data20),
      .sc2mac_dat_b_data21         (sc2mac_dat_b_data21),
      .sc2mac_dat_b_data22         (sc2mac_dat_b_data22),
      .sc2mac_dat_b_data23         (sc2mac_dat_b_data23),
      .sc2mac_dat_b_data24         (sc2mac_dat_b_data24),
      .sc2mac_dat_b_data25         (sc2mac_dat_b_data25),
      .sc2mac_dat_b_data26         (sc2mac_dat_b_data26),
      .sc2mac_dat_b_data27         (sc2mac_dat_b_data27),
      .sc2mac_dat_b_data28         (sc2mac_dat_b_data28),
      .sc2mac_dat_b_data29         (sc2mac_dat_b_data29),
      .sc2mac_dat_b_data30         (sc2mac_dat_b_data30),
      .sc2mac_dat_b_data31         (sc2mac_dat_b_data31),
      .sc2mac_dat_b_data32         (sc2mac_dat_b_data32),
      .sc2mac_dat_b_data33         (sc2mac_dat_b_data33),
      .sc2mac_dat_b_data34         (sc2mac_dat_b_data34),
      .sc2mac_dat_b_data35         (sc2mac_dat_b_data35),
      .sc2mac_dat_b_data36         (sc2mac_dat_b_data36),
      .sc2mac_dat_b_data37         (sc2mac_dat_b_data37),
      .sc2mac_dat_b_data38         (sc2mac_dat_b_data38),
      .sc2mac_dat_b_data39         (sc2mac_dat_b_data39),
      .sc2mac_dat_b_data40         (sc2mac_dat_b_data40),
      .sc2mac_dat_b_data41         (sc2mac_dat_b_data41),
      .sc2mac_dat_b_data42         (sc2mac_dat_b_data42),
      .sc2mac_dat_b_data43         (sc2mac_dat_b_data43),
      .sc2mac_dat_b_data44         (sc2mac_dat_b_data44),
      .sc2mac_dat_b_data45         (sc2mac_dat_b_data45),
      .sc2mac_dat_b_data46         (sc2mac_dat_b_data46),
      .sc2mac_dat_b_data47         (sc2mac_dat_b_data47),
      .sc2mac_dat_b_data48         (sc2mac_dat_b_data48),
      .sc2mac_dat_b_data49         (sc2mac_dat_b_data49),
      .sc2mac_dat_b_data50         (sc2mac_dat_b_data50),
      .sc2mac_dat_b_data51         (sc2mac_dat_b_data51),
      .sc2mac_dat_b_data52         (sc2mac_dat_b_data52),
      .sc2mac_dat_b_data53         (sc2mac_dat_b_data53),
      .sc2mac_dat_b_data54         (sc2mac_dat_b_data54),
      .sc2mac_dat_b_data55         (sc2mac_dat_b_data55),
      .sc2mac_dat_b_data56         (sc2mac_dat_b_data56),
      .sc2mac_dat_b_data57         (sc2mac_dat_b_data57),
      .sc2mac_dat_b_data58         (sc2mac_dat_b_data58),
      .sc2mac_dat_b_data59         (sc2mac_dat_b_data59),
      .sc2mac_dat_b_data60         (sc2mac_dat_b_data60),
      .sc2mac_dat_b_data61         (sc2mac_dat_b_data61),
      .sc2mac_dat_b_data62         (sc2mac_dat_b_data62),
      .sc2mac_dat_b_data63         (sc2mac_dat_b_data63),
      .sc2mac_dat_b_data64         (sc2mac_dat_b_data64),
      .sc2mac_dat_b_data65         (sc2mac_dat_b_data65),
      .sc2mac_dat_b_data66         (sc2mac_dat_b_data66),
      .sc2mac_dat_b_data67         (sc2mac_dat_b_data67),
      .sc2mac_dat_b_data68         (sc2mac_dat_b_data68),
      .sc2mac_dat_b_data69         (sc2mac_dat_b_data69),
      .sc2mac_dat_b_data70         (sc2mac_dat_b_data70),
      .sc2mac_dat_b_data71         (sc2mac_dat_b_data71),
      .sc2mac_dat_b_data72         (sc2mac_dat_b_data72),
      .sc2mac_dat_b_data73         (sc2mac_dat_b_data73),
      .sc2mac_dat_b_data74         (sc2mac_dat_b_data74),
      .sc2mac_dat_b_data75         (sc2mac_dat_b_data75),
      .sc2mac_dat_b_data76         (sc2mac_dat_b_data76),
      .sc2mac_dat_b_data77         (sc2mac_dat_b_data77),
      .sc2mac_dat_b_data78         (sc2mac_dat_b_data78),
      .sc2mac_dat_b_data79         (sc2mac_dat_b_data79),
      .sc2mac_dat_b_data80         (sc2mac_dat_b_data80),
      .sc2mac_dat_b_data81         (sc2mac_dat_b_data81),
      .sc2mac_dat_b_data82         (sc2mac_dat_b_data82),
      .sc2mac_dat_b_data83         (sc2mac_dat_b_data83),
      .sc2mac_dat_b_data84         (sc2mac_dat_b_data84),
      .sc2mac_dat_b_data85         (sc2mac_dat_b_data85),
      .sc2mac_dat_b_data86         (sc2mac_dat_b_data86),
      .sc2mac_dat_b_data87         (sc2mac_dat_b_data87),
      .sc2mac_dat_b_data88         (sc2mac_dat_b_data88),
      .sc2mac_dat_b_data89         (sc2mac_dat_b_data89),
      .sc2mac_dat_b_data90         (sc2mac_dat_b_data90),
      .sc2mac_dat_b_data91         (sc2mac_dat_b_data91),
      .sc2mac_dat_b_data92         (sc2mac_dat_b_data92),
      .sc2mac_dat_b_data93         (sc2mac_dat_b_data93),
      .sc2mac_dat_b_data94         (sc2mac_dat_b_data94),
      .sc2mac_dat_b_data95         (sc2mac_dat_b_data95),
      .sc2mac_dat_b_data96         (sc2mac_dat_b_data96),
      .sc2mac_dat_b_data97         (sc2mac_dat_b_data97),
      .sc2mac_dat_b_data98         (sc2mac_dat_b_data98),
      .sc2mac_dat_b_data99         (sc2mac_dat_b_data99),
      .sc2mac_dat_b_data100        (sc2mac_dat_b_data100),
      .sc2mac_dat_b_data101        (sc2mac_dat_b_data101),
      .sc2mac_dat_b_data102        (sc2mac_dat_b_data102),
      .sc2mac_dat_b_data103        (sc2mac_dat_b_data103),
      .sc2mac_dat_b_data104        (sc2mac_dat_b_data104),
      .sc2mac_dat_b_data105        (sc2mac_dat_b_data105),
      .sc2mac_dat_b_data106        (sc2mac_dat_b_data106),
      .sc2mac_dat_b_data107        (sc2mac_dat_b_data107),
      .sc2mac_dat_b_data108        (sc2mac_dat_b_data108),
      .sc2mac_dat_b_data109        (sc2mac_dat_b_data109),
      .sc2mac_dat_b_data110        (sc2mac_dat_b_data110),
      .sc2mac_dat_b_data111        (sc2mac_dat_b_data111),
      .sc2mac_dat_b_data112        (sc2mac_dat_b_data112),
      .sc2mac_dat_b_data113        (sc2mac_dat_b_data113),
      .sc2mac_dat_b_data114        (sc2mac_dat_b_data114),
      .sc2mac_dat_b_data115        (sc2mac_dat_b_data115),
      .sc2mac_dat_b_data116        (sc2mac_dat_b_data116),
      .sc2mac_dat_b_data117        (sc2mac_dat_b_data117),
      .sc2mac_dat_b_data118        (sc2mac_dat_b_data118),
      .sc2mac_dat_b_data119        (sc2mac_dat_b_data119),
      .sc2mac_dat_b_data120        (sc2mac_dat_b_data120),
      .sc2mac_dat_b_data121        (sc2mac_dat_b_data121),
      .sc2mac_dat_b_data122        (sc2mac_dat_b_data122),
      .sc2mac_dat_b_data123        (sc2mac_dat_b_data123),
      .sc2mac_dat_b_data124        (sc2mac_dat_b_data124),
      .sc2mac_dat_b_data125        (sc2mac_dat_b_data125),
      .sc2mac_dat_b_data126        (sc2mac_dat_b_data126),
      .sc2mac_dat_b_data127        (sc2mac_dat_b_data127),
      .sc2mac_dat_b_pd             (sc2mac_dat_b_pd),
      .sc2mac_wt_a_pvld            (sc2mac_wt_a_pvld),
      .sc2mac_wt_a_mask            (sc2mac_wt_a_mask),
      .sc2mac_wt_a_data0           (sc2mac_wt_a_data0),
      .sc2mac_wt_a_data1           (sc2mac_wt_a_data1),
      .sc2mac_wt_a_data2           (sc2mac_wt_a_data2),
      .sc2mac_wt_a_data3           (sc2mac_wt_a_data3),
      .sc2mac_wt_a_data4           (sc2mac_wt_a_data4),
      .sc2mac_wt_a_data5           (sc2mac_wt_a_data5),
      .sc2mac_wt_a_data6           (sc2mac_wt_a_data6),
      .sc2mac_wt_a_data7           (sc2mac_wt_a_data7),
      .sc2mac_wt_a_data8           (sc2mac_wt_a_data8),
      .sc2mac_wt_a_data9           (sc2mac_wt_a_data9),
      .sc2mac_wt_a_data10          (sc2mac_wt_a_data10),
      .sc2mac_wt_a_data11          (sc2mac_wt_a_data11),
      .sc2mac_wt_a_data12          (sc2mac_wt_a_data12),
      .sc2mac_wt_a_data13          (sc2mac_wt_a_data13),
      .sc2mac_wt_a_data14          (sc2mac_wt_a_data14),
      .sc2mac_wt_a_data15          (sc2mac_wt_a_data15),
      .sc2mac_wt_a_data16          (sc2mac_wt_a_data16),
      .sc2mac_wt_a_data17          (sc2mac_wt_a_data17),
      .sc2mac_wt_a_data18          (sc2mac_wt_a_data18),
      .sc2mac_wt_a_data19          (sc2mac_wt_a_data19),
      .sc2mac_wt_a_data20          (sc2mac_wt_a_data20),
      .sc2mac_wt_a_data21          (sc2mac_wt_a_data21),
      .sc2mac_wt_a_data22          (sc2mac_wt_a_data22),
      .sc2mac_wt_a_data23          (sc2mac_wt_a_data23),
      .sc2mac_wt_a_data24          (sc2mac_wt_a_data24),
      .sc2mac_wt_a_data25          (sc2mac_wt_a_data25),
      .sc2mac_wt_a_data26          (sc2mac_wt_a_data26),
      .sc2mac_wt_a_data27          (sc2mac_wt_a_data27),
      .sc2mac_wt_a_data28          (sc2mac_wt_a_data28),
      .sc2mac_wt_a_data29          (sc2mac_wt_a_data29),
      .sc2mac_wt_a_data30          (sc2mac_wt_a_data30),
      .sc2mac_wt_a_data31          (sc2mac_wt_a_data31),
      .sc2mac_wt_a_data32          (sc2mac_wt_a_data32),
      .sc2mac_wt_a_data33          (sc2mac_wt_a_data33),
      .sc2mac_wt_a_data34          (sc2mac_wt_a_data34),
      .sc2mac_wt_a_data35          (sc2mac_wt_a_data35),
      .sc2mac_wt_a_data36          (sc2mac_wt_a_data36),
      .sc2mac_wt_a_data37          (sc2mac_wt_a_data37),
      .sc2mac_wt_a_data38          (sc2mac_wt_a_data38),
      .sc2mac_wt_a_data39          (sc2mac_wt_a_data39),
      .sc2mac_wt_a_data40          (sc2mac_wt_a_data40),
      .sc2mac_wt_a_data41          (sc2mac_wt_a_data41),
      .sc2mac_wt_a_data42          (sc2mac_wt_a_data42),
      .sc2mac_wt_a_data43          (sc2mac_wt_a_data43),
      .sc2mac_wt_a_data44          (sc2mac_wt_a_data44),
      .sc2mac_wt_a_data45          (sc2mac_wt_a_data45),
      .sc2mac_wt_a_data46          (sc2mac_wt_a_data46),
      .sc2mac_wt_a_data47          (sc2mac_wt_a_data47),
      .sc2mac_wt_a_data48          (sc2mac_wt_a_data48),
      .sc2mac_wt_a_data49          (sc2mac_wt_a_data49),
      .sc2mac_wt_a_data50          (sc2mac_wt_a_data50),
      .sc2mac_wt_a_data51          (sc2mac_wt_a_data51),
      .sc2mac_wt_a_data52          (sc2mac_wt_a_data52),
      .sc2mac_wt_a_data53          (sc2mac_wt_a_data53),
      .sc2mac_wt_a_data54          (sc2mac_wt_a_data54),
      .sc2mac_wt_a_data55          (sc2mac_wt_a_data55),
      .sc2mac_wt_a_data56          (sc2mac_wt_a_data56),
      .sc2mac_wt_a_data57          (sc2mac_wt_a_data57),
      .sc2mac_wt_a_data58          (sc2mac_wt_a_data58),
      .sc2mac_wt_a_data59          (sc2mac_wt_a_data59),
      .sc2mac_wt_a_data60          (sc2mac_wt_a_data60),
      .sc2mac_wt_a_data61          (sc2mac_wt_a_data61),
      .sc2mac_wt_a_data62          (sc2mac_wt_a_data62),
      .sc2mac_wt_a_data63          (sc2mac_wt_a_data63),
      .sc2mac_wt_a_data64          (sc2mac_wt_a_data64),
      .sc2mac_wt_a_data65          (sc2mac_wt_a_data65),
      .sc2mac_wt_a_data66          (sc2mac_wt_a_data66),
      .sc2mac_wt_a_data67          (sc2mac_wt_a_data67),
      .sc2mac_wt_a_data68          (sc2mac_wt_a_data68),
      .sc2mac_wt_a_data69          (sc2mac_wt_a_data69),
      .sc2mac_wt_a_data70          (sc2mac_wt_a_data70),
      .sc2mac_wt_a_data71          (sc2mac_wt_a_data71),
      .sc2mac_wt_a_data72          (sc2mac_wt_a_data72),
      .sc2mac_wt_a_data73          (sc2mac_wt_a_data73),
      .sc2mac_wt_a_data74          (sc2mac_wt_a_data74),
      .sc2mac_wt_a_data75          (sc2mac_wt_a_data75),
      .sc2mac_wt_a_data76          (sc2mac_wt_a_data76),
      .sc2mac_wt_a_data77          (sc2mac_wt_a_data77),
      .sc2mac_wt_a_data78          (sc2mac_wt_a_data78),
      .sc2mac_wt_a_data79          (sc2mac_wt_a_data79),
      .sc2mac_wt_a_data80          (sc2mac_wt_a_data80),
      .sc2mac_wt_a_data81          (sc2mac_wt_a_data81),
      .sc2mac_wt_a_data82          (sc2mac_wt_a_data82),
      .sc2mac_wt_a_data83          (sc2mac_wt_a_data83),
      .sc2mac_wt_a_data84          (sc2mac_wt_a_data84),
      .sc2mac_wt_a_data85          (sc2mac_wt_a_data85),
      .sc2mac_wt_a_data86          (sc2mac_wt_a_data86),
      .sc2mac_wt_a_data87          (sc2mac_wt_a_data87),
      .sc2mac_wt_a_data88          (sc2mac_wt_a_data88),
      .sc2mac_wt_a_data89          (sc2mac_wt_a_data89),
      .sc2mac_wt_a_data90          (sc2mac_wt_a_data90),
      .sc2mac_wt_a_data91          (sc2mac_wt_a_data91),
      .sc2mac_wt_a_data92          (sc2mac_wt_a_data92),
      .sc2mac_wt_a_data93          (sc2mac_wt_a_data93),
      .sc2mac_wt_a_data94          (sc2mac_wt_a_data94),
      .sc2mac_wt_a_data95          (sc2mac_wt_a_data95),
      .sc2mac_wt_a_data96          (sc2mac_wt_a_data96),
      .sc2mac_wt_a_data97          (sc2mac_wt_a_data97),
      .sc2mac_wt_a_data98          (sc2mac_wt_a_data98),
      .sc2mac_wt_a_data99          (sc2mac_wt_a_data99),
      .sc2mac_wt_a_data100         (sc2mac_wt_a_data100),
      .sc2mac_wt_a_data101         (sc2mac_wt_a_data101),
      .sc2mac_wt_a_data102         (sc2mac_wt_a_data102),
      .sc2mac_wt_a_data103         (sc2mac_wt_a_data103),
      .sc2mac_wt_a_data104         (sc2mac_wt_a_data104),
      .sc2mac_wt_a_data105         (sc2mac_wt_a_data105),
      .sc2mac_wt_a_data106         (sc2mac_wt_a_data106),
      .sc2mac_wt_a_data107         (sc2mac_wt_a_data107),
      .sc2mac_wt_a_data108         (sc2mac_wt_a_data108),
      .sc2mac_wt_a_data109         (sc2mac_wt_a_data109),
      .sc2mac_wt_a_data110         (sc2mac_wt_a_data110),
      .sc2mac_wt_a_data111         (sc2mac_wt_a_data111),
      .sc2mac_wt_a_data112         (sc2mac_wt_a_data112),
      .sc2mac_wt_a_data113         (sc2mac_wt_a_data113),
      .sc2mac_wt_a_data114         (sc2mac_wt_a_data114),
      .sc2mac_wt_a_data115         (sc2mac_wt_a_data115),
      .sc2mac_wt_a_data116         (sc2mac_wt_a_data116),
      .sc2mac_wt_a_data117         (sc2mac_wt_a_data117),
      .sc2mac_wt_a_data118         (sc2mac_wt_a_data118),
      .sc2mac_wt_a_data119         (sc2mac_wt_a_data119),
      .sc2mac_wt_a_data120         (sc2mac_wt_a_data120),
      .sc2mac_wt_a_data121         (sc2mac_wt_a_data121),
      .sc2mac_wt_a_data122         (sc2mac_wt_a_data122),
      .sc2mac_wt_a_data123         (sc2mac_wt_a_data123),
      .sc2mac_wt_a_data124         (sc2mac_wt_a_data124),
      .sc2mac_wt_a_data125         (sc2mac_wt_a_data125),
      .sc2mac_wt_a_data126         (sc2mac_wt_a_data126),
      .sc2mac_wt_a_data127         (sc2mac_wt_a_data127),
      .sc2mac_wt_a_sel             (sc2mac_wt_a_sel),
      .sc2mac_wt_b_pvld            (sc2mac_wt_b_pvld),
      .sc2mac_wt_b_mask            (sc2mac_wt_b_mask),
      .sc2mac_wt_b_data0           (sc2mac_wt_b_data0),
      .sc2mac_wt_b_data1           (sc2mac_wt_b_data1),
      .sc2mac_wt_b_data2           (sc2mac_wt_b_data2),
      .sc2mac_wt_b_data3           (sc2mac_wt_b_data3),
      .sc2mac_wt_b_data4           (sc2mac_wt_b_data4),
      .sc2mac_wt_b_data5           (sc2mac_wt_b_data5),
      .sc2mac_wt_b_data6           (sc2mac_wt_b_data6),
      .sc2mac_wt_b_data7           (sc2mac_wt_b_data7),
      .sc2mac_wt_b_data8           (sc2mac_wt_b_data8),
      .sc2mac_wt_b_data9           (sc2mac_wt_b_data9),
      .sc2mac_wt_b_data10          (sc2mac_wt_b_data10),
      .sc2mac_wt_b_data11          (sc2mac_wt_b_data11),
      .sc2mac_wt_b_data12          (sc2mac_wt_b_data12),
      .sc2mac_wt_b_data13          (sc2mac_wt_b_data13),
      .sc2mac_wt_b_data14          (sc2mac_wt_b_data14),
      .sc2mac_wt_b_data15          (sc2mac_wt_b_data15),
      .sc2mac_wt_b_data16          (sc2mac_wt_b_data16),
      .sc2mac_wt_b_data17          (sc2mac_wt_b_data17),
      .sc2mac_wt_b_data18          (sc2mac_wt_b_data18),
      .sc2mac_wt_b_data19          (sc2mac_wt_b_data19),
      .sc2mac_wt_b_data20          (sc2mac_wt_b_data20),
      .sc2mac_wt_b_data21          (sc2mac_wt_b_data21),
      .sc2mac_wt_b_data22          (sc2mac_wt_b_data22),
      .sc2mac_wt_b_data23          (sc2mac_wt_b_data23),
      .sc2mac_wt_b_data24          (sc2mac_wt_b_data24),
      .sc2mac_wt_b_data25          (sc2mac_wt_b_data25),
      .sc2mac_wt_b_data26          (sc2mac_wt_b_data26),
      .sc2mac_wt_b_data27          (sc2mac_wt_b_data27),
      .sc2mac_wt_b_data28          (sc2mac_wt_b_data28),
      .sc2mac_wt_b_data29          (sc2mac_wt_b_data29),
      .sc2mac_wt_b_data30          (sc2mac_wt_b_data30),
      .sc2mac_wt_b_data31          (sc2mac_wt_b_data31),
      .sc2mac_wt_b_data32          (sc2mac_wt_b_data32),
      .sc2mac_wt_b_data33          (sc2mac_wt_b_data33),
      .sc2mac_wt_b_data34          (sc2mac_wt_b_data34),
      .sc2mac_wt_b_data35          (sc2mac_wt_b_data35),
      .sc2mac_wt_b_data36          (sc2mac_wt_b_data36),
      .sc2mac_wt_b_data37          (sc2mac_wt_b_data37),
      .sc2mac_wt_b_data38          (sc2mac_wt_b_data38),
      .sc2mac_wt_b_data39          (sc2mac_wt_b_data39),
      .sc2mac_wt_b_data40          (sc2mac_wt_b_data40),
      .sc2mac_wt_b_data41          (sc2mac_wt_b_data41),
      .sc2mac_wt_b_data42          (sc2mac_wt_b_data42),
      .sc2mac_wt_b_data43          (sc2mac_wt_b_data43),
      .sc2mac_wt_b_data44          (sc2mac_wt_b_data44),
      .sc2mac_wt_b_data45          (sc2mac_wt_b_data45),
      .sc2mac_wt_b_data46          (sc2mac_wt_b_data46),
      .sc2mac_wt_b_data47          (sc2mac_wt_b_data47),
      .sc2mac_wt_b_data48          (sc2mac_wt_b_data48),
      .sc2mac_wt_b_data49          (sc2mac_wt_b_data49),
      .sc2mac_wt_b_data50          (sc2mac_wt_b_data50),
      .sc2mac_wt_b_data51          (sc2mac_wt_b_data51),
      .sc2mac_wt_b_data52          (sc2mac_wt_b_data52),
      .sc2mac_wt_b_data53          (sc2mac_wt_b_data53),
      .sc2mac_wt_b_data54          (sc2mac_wt_b_data54),
      .sc2mac_wt_b_data55          (sc2mac_wt_b_data55),
      .sc2mac_wt_b_data56          (sc2mac_wt_b_data56),
      .sc2mac_wt_b_data57          (sc2mac_wt_b_data57),
      .sc2mac_wt_b_data58          (sc2mac_wt_b_data58),
      .sc2mac_wt_b_data59          (sc2mac_wt_b_data59),
      .sc2mac_wt_b_data60          (sc2mac_wt_b_data60),
      .sc2mac_wt_b_data61          (sc2mac_wt_b_data61),
      .sc2mac_wt_b_data62          (sc2mac_wt_b_data62),
      .sc2mac_wt_b_data63          (sc2mac_wt_b_data63),
      .sc2mac_wt_b_data64          (sc2mac_wt_b_data64),
      .sc2mac_wt_b_data65          (sc2mac_wt_b_data65),
      .sc2mac_wt_b_data66          (sc2mac_wt_b_data66),
      .sc2mac_wt_b_data67          (sc2mac_wt_b_data67),
      .sc2mac_wt_b_data68          (sc2mac_wt_b_data68),
      .sc2mac_wt_b_data69          (sc2mac_wt_b_data69),
      .sc2mac_wt_b_data70          (sc2mac_wt_b_data70),
      .sc2mac_wt_b_data71          (sc2mac_wt_b_data71),
      .sc2mac_wt_b_data72          (sc2mac_wt_b_data72),
      .sc2mac_wt_b_data73          (sc2mac_wt_b_data73),
      .sc2mac_wt_b_data74          (sc2mac_wt_b_data74),
      .sc2mac_wt_b_data75          (sc2mac_wt_b_data75),
      .sc2mac_wt_b_data76          (sc2mac_wt_b_data76),
      .sc2mac_wt_b_data77          (sc2mac_wt_b_data77),
      .sc2mac_wt_b_data78          (sc2mac_wt_b_data78),
      .sc2mac_wt_b_data79          (sc2mac_wt_b_data79),
      .sc2mac_wt_b_data80          (sc2mac_wt_b_data80),
      .sc2mac_wt_b_data81          (sc2mac_wt_b_data81),
      .sc2mac_wt_b_data82          (sc2mac_wt_b_data82),
      .sc2mac_wt_b_data83          (sc2mac_wt_b_data83),
      .sc2mac_wt_b_data84          (sc2mac_wt_b_data84),
      .sc2mac_wt_b_data85          (sc2mac_wt_b_data85),
      .sc2mac_wt_b_data86          (sc2mac_wt_b_data86),
      .sc2mac_wt_b_data87          (sc2mac_wt_b_data87),
      .sc2mac_wt_b_data88          (sc2mac_wt_b_data88),
      .sc2mac_wt_b_data89          (sc2mac_wt_b_data89),
      .sc2mac_wt_b_data90          (sc2mac_wt_b_data90),
      .sc2mac_wt_b_data91          (sc2mac_wt_b_data91),
      .sc2mac_wt_b_data92          (sc2mac_wt_b_data92),
      .sc2mac_wt_b_data93          (sc2mac_wt_b_data93),
      .sc2mac_wt_b_data94          (sc2mac_wt_b_data94),
      .sc2mac_wt_b_data95          (sc2mac_wt_b_data95),
      .sc2mac_wt_b_data96          (sc2mac_wt_b_data96),
      .sc2mac_wt_b_data97          (sc2mac_wt_b_data97),
      .sc2mac_wt_b_data98          (sc2mac_wt_b_data98),
      .sc2mac_wt_b_data99          (sc2mac_wt_b_data99),
      .sc2mac_wt_b_data100         (sc2mac_wt_b_data100),
      .sc2mac_wt_b_data101         (sc2mac_wt_b_data101),
      .sc2mac_wt_b_data102         (sc2mac_wt_b_data102),
      .sc2mac_wt_b_data103         (sc2mac_wt_b_data103),
      .sc2mac_wt_b_data104         (sc2mac_wt_b_data104),
      .sc2mac_wt_b_data105         (sc2mac_wt_b_data105),
      .sc2mac_wt_b_data106         (sc2mac_wt_b_data106),
      .sc2mac_wt_b_data107         (sc2mac_wt_b_data107),
      .sc2mac_wt_b_data108         (sc2mac_wt_b_data108),
      .sc2mac_wt_b_data109         (sc2mac_wt_b_data109),
      .sc2mac_wt_b_data110         (sc2mac_wt_b_data110),
      .sc2mac_wt_b_data111         (sc2mac_wt_b_data111),
      .sc2mac_wt_b_data112         (sc2mac_wt_b_data112),
      .sc2mac_wt_b_data113         (sc2mac_wt_b_data113),
      .sc2mac_wt_b_data114         (sc2mac_wt_b_data114),
      .sc2mac_wt_b_data115         (sc2mac_wt_b_data115),
      .sc2mac_wt_b_data116         (sc2mac_wt_b_data116),
      .sc2mac_wt_b_data117         (sc2mac_wt_b_data117),
      .sc2mac_wt_b_data118         (sc2mac_wt_b_data118),
      .sc2mac_wt_b_data119         (sc2mac_wt_b_data119),
      .sc2mac_wt_b_data120         (sc2mac_wt_b_data120),
      .sc2mac_wt_b_data121         (sc2mac_wt_b_data121),
      .sc2mac_wt_b_data122         (sc2mac_wt_b_data122),
      .sc2mac_wt_b_data123         (sc2mac_wt_b_data123),
      .sc2mac_wt_b_data124         (sc2mac_wt_b_data124),
      .sc2mac_wt_b_data125         (sc2mac_wt_b_data125),
      .sc2mac_wt_b_data126         (sc2mac_wt_b_data126),
      .sc2mac_wt_b_data127         (sc2mac_wt_b_data127),
      .sc2mac_wt_b_sel             (sc2mac_wt_b_sel),
      .cdma2sc_wt_updt             (cdma2sc_wt_updt),
      .cdma2sc_wt_kernels          (cdma2sc_wt_kernels),
      .cdma2sc_wt_entries          (cdma2sc_wt_entries),
      .cdma2sc_wmb_entries         (cdma2sc_wmb_entries),
      .sc2cdma_wt_updt             (sc2cdma_wt_updt),
      .sc2cdma_wt_kernels          (sc2cdma_wt_kernels),
      .sc2cdma_wt_entries          (sc2cdma_wt_entries),
      .sc2cdma_wmb_entries         (sc2cdma_wmb_entries),
      .dla_clk_ovr_on_sync         (dla_clk_ovr_on_sync),
      .global_clk_ovr_on_sync      (global_clk_ovr_on_sync),
      .tmc2slcg_disable_clock_gating(tmc2slcg_disable_clock_gating)
   );

   NV_NVDLA_cmac u_cmac_a (
      .nvdla_core_clk              (nvdla_core_clk),
      .nvdla_core_rstn             (nvdla_core_rstn),
      .cmac_a2csb_resp_valid       (cmac_a2csb_resp_valid),
      .cmac_a2csb_resp_pd          (cmac_a2csb_resp_pd),
      .csb2cmac_a_req_pvld         (csb2cmac_a_req_pvld),
      .csb2cmac_a_req_prdy         (csb2cmac_a_req_prdy),
      .csb2cmac_a_req_pd           (csb2cmac_a_req_pd),
      .mac2accu_pvld               (mac_a2accu_pvld),
      .mac2accu_mask               (mac_a2accu_mask),
      .mac2accu_mode               (mac_a2accu_mode),
      .mac2accu_data0              (mac_a2accu_data0),
      .mac2accu_data1              (mac_a2accu_data1),
      .mac2accu_data2              (mac_a2accu_data2),
      .mac2accu_data3              (mac_a2accu_data3),
      .mac2accu_data4              (mac_a2accu_data4),
      .mac2accu_data5              (mac_a2accu_data5),
      .mac2accu_data6              (mac_a2accu_data6),
      .mac2accu_data7              (mac_a2accu_data7),
      .mac2accu_pd                 (mac_a2accu_pd),
      .sc2mac_dat_pvld             (sc2mac_dat_a_pvld),
      .sc2mac_dat_mask             (sc2mac_dat_a_mask),
      .sc2mac_dat_data0            (sc2mac_dat_a_data0),
      .sc2mac_dat_data1            (sc2mac_dat_a_data1),
      .sc2mac_dat_data2            (sc2mac_dat_a_data2),
      .sc2mac_dat_data3            (sc2mac_dat_a_data3),
      .sc2mac_dat_data4            (sc2mac_dat_a_data4),
      .sc2mac_dat_data5            (sc2mac_dat_a_data5),
      .sc2mac_dat_data6            (sc2mac_dat_a_data6),
      .sc2mac_dat_data7            (sc2mac_dat_a_data7),
      .sc2mac_dat_data8            (sc2mac_dat_a_data8),
      .sc2mac_dat_data9            (sc2mac_dat_a_data9),
      .sc2mac_dat_data10           (sc2mac_dat_a_data10),
      .sc2mac_dat_data11           (sc2mac_dat_a_data11),
      .sc2mac_dat_data12           (sc2mac_dat_a_data12),
      .sc2mac_dat_data13           (sc2mac_dat_a_data13),
      .sc2mac_dat_data14           (sc2mac_dat_a_data14),
      .sc2mac_dat_data15           (sc2mac_dat_a_data15),
      .sc2mac_dat_data16           (sc2mac_dat_a_data16),
      .sc2mac_dat_data17           (sc2mac_dat_a_data17),
      .sc2mac_dat_data18           (sc2mac_dat_a_data18),
      .sc2mac_dat_data19           (sc2mac_dat_a_data19),
      .sc2mac_dat_data20           (sc2mac_dat_a_data20),
      .sc2mac_dat_data21           (sc2mac_dat_a_data21),
      .sc2mac_dat_data22           (sc2mac_dat_a_data22),
      .sc2mac_dat_data23           (sc2mac_dat_a_data23),
      .sc2mac_dat_data24           (sc2mac_dat_a_data24),
      .sc2mac_dat_data25           (sc2mac_dat_a_data25),
      .sc2mac_dat_data26           (sc2mac_dat_a_data26),
      .sc2mac_dat_data27           (sc2mac_dat_a_data27),
      .sc2mac_dat_data28           (sc2mac_dat_a_data28),
      .sc2mac_dat_data29           (sc2mac_dat_a_data29),
      .sc2mac_dat_data30           (sc2mac_dat_a_data30),
      .sc2mac_dat_data31           (sc2mac_dat_a_data31),
      .sc2mac_dat_data32           (sc2mac_dat_a_data32),
      .sc2mac_dat_data33           (sc2mac_dat_a_data33),
      .sc2mac_dat_data34           (sc2mac_dat_a_data34),
      .sc2mac_dat_data35           (sc2mac_dat_a_data35),
      .sc2mac_dat_data36           (sc2mac_dat_a_data36),
      .sc2mac_dat_data37           (sc2mac_dat_a_data37),
      .sc2mac_dat_data38           (sc2mac_dat_a_data38),
      .sc2mac_dat_data39           (sc2mac_dat_a_data39),
      .sc2mac_dat_data40           (sc2mac_dat_a_data40),
      .sc2mac_dat_data41           (sc2mac_dat_a_data41),
      .sc2mac_dat_data42           (sc2mac_dat_a_data42),
      .sc2mac_dat_data43           (sc2mac_dat_a_data43),
      .sc2mac_dat_data44           (sc2mac_dat_a_data44),
      .sc2mac_dat_data45           (sc2mac_dat_a_data45),
      .sc2mac_dat_data46           (sc2mac_dat_a_data46),
      .sc2mac_dat_data47           (sc2mac_dat_a_data47),
      .sc2mac_dat_data48           (sc2mac_dat_a_data48),
      .sc2mac_dat_data49           (sc2mac_dat_a_data49),
      .sc2mac_dat_data50           (sc2mac_dat_a_data50),
      .sc2mac_dat_data51           (sc2mac_dat_a_data51),
      .sc2mac_dat_data52           (sc2mac_dat_a_data52),
      .sc2mac_dat_data53           (sc2mac_dat_a_data53),
      .sc2mac_dat_data54           (sc2mac_dat_a_data54),
      .sc2mac_dat_data55           (sc2mac_dat_a_data55),
      .sc2mac_dat_data56           (sc2mac_dat_a_data56),
      .sc2mac_dat_data57           (sc2mac_dat_a_data57),
      .sc2mac_dat_data58           (sc2mac_dat_a_data58),
      .sc2mac_dat_data59           (sc2mac_dat_a_data59),
      .sc2mac_dat_data60           (sc2mac_dat_a_data60),
      .sc2mac_dat_data61           (sc2mac_dat_a_data61),
      .sc2mac_dat_data62           (sc2mac_dat_a_data62),
      .sc2mac_dat_data63           (sc2mac_dat_a_data63),
      .sc2mac_dat_data64           (sc2mac_dat_a_data64),
      .sc2mac_dat_data65           (sc2mac_dat_a_data65),
      .sc2mac_dat_data66           (sc2mac_dat_a_data66),
      .sc2mac_dat_data67           (sc2mac_dat_a_data67),
      .sc2mac_dat_data68           (sc2mac_dat_a_data68),
      .sc2mac_dat_data69           (sc2mac_dat_a_data69),
      .sc2mac_dat_data70           (sc2mac_dat_a_data70),
      .sc2mac_dat_data71           (sc2mac_dat_a_data71),
      .sc2mac_dat_data72           (sc2mac_dat_a_data72),
      .sc2mac_dat_data73           (sc2mac_dat_a_data73),
      .sc2mac_dat_data74           (sc2mac_dat_a_data74),
      .sc2mac_dat_data75           (sc2mac_dat_a_data75),
      .sc2mac_dat_data76           (sc2mac_dat_a_data76),
      .sc2mac_dat_data77           (sc2mac_dat_a_data77),
      .sc2mac_dat_data78           (sc2mac_dat_a_data78),
      .sc2mac_dat_data79           (sc2mac_dat_a_data79),
      .sc2mac_dat_data80           (sc2mac_dat_a_data80),
      .sc2mac_dat_data81           (sc2mac_dat_a_data81),
      .sc2mac_dat_data82           (sc2mac_dat_a_data82),
      .sc2mac_dat_data83           (sc2mac_dat_a_data83),
      .sc2mac_dat_data84           (sc2mac_dat_a_data84),
      .sc2mac_dat_data85           (sc2mac_dat_a_data85),
      .sc2mac_dat_data86           (sc2mac_dat_a_data86),
      .sc2mac_dat_data87           (sc2mac_dat_a_data87),
      .sc2mac_dat_data88           (sc2mac_dat_a_data88),
      .sc2mac_dat_data89           (sc2mac_dat_a_data89),
      .sc2mac_dat_data90           (sc2mac_dat_a_data90),
      .sc2mac_dat_data91           (sc2mac_dat_a_data91),
      .sc2mac_dat_data92           (sc2mac_dat_a_data92),
      .sc2mac_dat_data93           (sc2mac_dat_a_data93),
      .sc2mac_dat_data94           (sc2mac_dat_a_data94),
      .sc2mac_dat_data95           (sc2mac_dat_a_data95),
      .sc2mac_dat_data96           (sc2mac_dat_a_data96),
      .sc2mac_dat_data97           (sc2mac_dat_a_data97),
      .sc2mac_dat_data98           (sc2mac_dat_a_data98),
      .sc2mac_dat_data99           (sc2mac_dat_a_data99),
      .sc2mac_dat_data100          (sc2mac_dat_a_data100),
      .sc2mac_dat_data101          (sc2mac_dat_a_data101),
      .sc2mac_dat_data102          (sc2mac_dat_a_data102),
      .sc2mac_dat_data103          (sc2mac_dat_a_data103),
      .sc2mac_dat_data104          (sc2mac_dat_a_data104),
      .sc2mac_dat_data105          (sc2mac_dat_a_data105),
      .sc2mac_dat_data106          (sc2mac_dat_a_data106),
      .sc2mac_dat_data107          (sc2mac_dat_a_data107),
      .sc2mac_dat_data108          (sc2mac_dat_a_data108),
      .sc2mac_dat_data109          (sc2mac_dat_a_data109),
      .sc2mac_dat_data110          (sc2mac_dat_a_data110),
      .sc2mac_dat_data111          (sc2mac_dat_a_data111),
      .sc2mac_dat_data112          (sc2mac_dat_a_data112),
      .sc2mac_dat_data113          (sc2mac_dat_a_data113),
      .sc2mac_dat_data114          (sc2mac_dat_a_data114),
      .sc2mac_dat_data115          (sc2mac_dat_a_data115),
      .sc2mac_dat_data116          (sc2mac_dat_a_data116),
      .sc2mac_dat_data117          (sc2mac_dat_a_data117),
      .sc2mac_dat_data118          (sc2mac_dat_a_data118),
      .sc2mac_dat_data119          (sc2mac_dat_a_data119),
      .sc2mac_dat_data120          (sc2mac_dat_a_data120),
      .sc2mac_dat_data121          (sc2mac_dat_a_data121),
      .sc2mac_dat_data122          (sc2mac_dat_a_data122),
      .sc2mac_dat_data123          (sc2mac_dat_a_data123),
      .sc2mac_dat_data124          (sc2mac_dat_a_data124),
      .sc2mac_dat_data125          (sc2mac_dat_a_data125),
      .sc2mac_dat_data126          (sc2mac_dat_a_data126),
      .sc2mac_dat_data127          (sc2mac_dat_a_data127),
      .sc2mac_dat_pd               (sc2mac_dat_a_pd),
      .sc2mac_wt_pvld              (sc2mac_wt_a_pvld),
      .sc2mac_wt_mask              (sc2mac_wt_a_mask),
      .sc2mac_wt_data0             (sc2mac_wt_a_data0),
      .sc2mac_wt_data1             (sc2mac_wt_a_data1),
      .sc2mac_wt_data2             (sc2mac_wt_a_data2),
      .sc2mac_wt_data3             (sc2mac_wt_a_data3),
      .sc2mac_wt_data4             (sc2mac_wt_a_data4),
      .sc2mac_wt_data5             (sc2mac_wt_a_data5),
      .sc2mac_wt_data6             (sc2mac_wt_a_data6),
      .sc2mac_wt_data7             (sc2mac_wt_a_data7),
      .sc2mac_wt_data8             (sc2mac_wt_a_data8),
      .sc2mac_wt_data9             (sc2mac_wt_a_data9),
      .sc2mac_wt_data10            (sc2mac_wt_a_data10),
      .sc2mac_wt_data11            (sc2mac_wt_a_data11),
      .sc2mac_wt_data12            (sc2mac_wt_a_data12),
      .sc2mac_wt_data13            (sc2mac_wt_a_data13),
      .sc2mac_wt_data14            (sc2mac_wt_a_data14),
      .sc2mac_wt_data15            (sc2mac_wt_a_data15),
      .sc2mac_wt_data16            (sc2mac_wt_a_data16),
      .sc2mac_wt_data17            (sc2mac_wt_a_data17),
      .sc2mac_wt_data18            (sc2mac_wt_a_data18),
      .sc2mac_wt_data19            (sc2mac_wt_a_data19),
      .sc2mac_wt_data20            (sc2mac_wt_a_data20),
      .sc2mac_wt_data21            (sc2mac_wt_a_data21),
      .sc2mac_wt_data22            (sc2mac_wt_a_data22),
      .sc2mac_wt_data23            (sc2mac_wt_a_data23),
      .sc2mac_wt_data24            (sc2mac_wt_a_data24),
      .sc2mac_wt_data25            (sc2mac_wt_a_data25),
      .sc2mac_wt_data26            (sc2mac_wt_a_data26),
      .sc2mac_wt_data27            (sc2mac_wt_a_data27),
      .sc2mac_wt_data28            (sc2mac_wt_a_data28),
      .sc2mac_wt_data29            (sc2mac_wt_a_data29),
      .sc2mac_wt_data30            (sc2mac_wt_a_data30),
      .sc2mac_wt_data31            (sc2mac_wt_a_data31),
      .sc2mac_wt_data32            (sc2mac_wt_a_data32),
      .sc2mac_wt_data33            (sc2mac_wt_a_data33),
      .sc2mac_wt_data34            (sc2mac_wt_a_data34),
      .sc2mac_wt_data35            (sc2mac_wt_a_data35),
      .sc2mac_wt_data36            (sc2mac_wt_a_data36),
      .sc2mac_wt_data37            (sc2mac_wt_a_data37),
      .sc2mac_wt_data38            (sc2mac_wt_a_data38),
      .sc2mac_wt_data39            (sc2mac_wt_a_data39),
      .sc2mac_wt_data40            (sc2mac_wt_a_data40),
      .sc2mac_wt_data41            (sc2mac_wt_a_data41),
      .sc2mac_wt_data42            (sc2mac_wt_a_data42),
      .sc2mac_wt_data43            (sc2mac_wt_a_data43),
      .sc2mac_wt_data44            (sc2mac_wt_a_data44),
      .sc2mac_wt_data45            (sc2mac_wt_a_data45),
      .sc2mac_wt_data46            (sc2mac_wt_a_data46),
      .sc2mac_wt_data47            (sc2mac_wt_a_data47),
      .sc2mac_wt_data48            (sc2mac_wt_a_data48),
      .sc2mac_wt_data49            (sc2mac_wt_a_data49),
      .sc2mac_wt_data50            (sc2mac_wt_a_data50),
      .sc2mac_wt_data51            (sc2mac_wt_a_data51),
      .sc2mac_wt_data52            (sc2mac_wt_a_data52),
      .sc2mac_wt_data53            (sc2mac_wt_a_data53),
      .sc2mac_wt_data54            (sc2mac_wt_a_data54),
      .sc2mac_wt_data55            (sc2mac_wt_a_data55),
      .sc2mac_wt_data56            (sc2mac_wt_a_data56),
      .sc2mac_wt_data57            (sc2mac_wt_a_data57),
      .sc2mac_wt_data58            (sc2mac_wt_a_data58),
      .sc2mac_wt_data59            (sc2mac_wt_a_data59),
      .sc2mac_wt_data60            (sc2mac_wt_a_data60),
      .sc2mac_wt_data61            (sc2mac_wt_a_data61),
      .sc2mac_wt_data62            (sc2mac_wt_a_data62),
      .sc2mac_wt_data63            (sc2mac_wt_a_data63),
      .sc2mac_wt_data64            (sc2mac_wt_a_data64),
      .sc2mac_wt_data65            (sc2mac_wt_a_data65),
      .sc2mac_wt_data66            (sc2mac_wt_a_data66),
      .sc2mac_wt_data67            (sc2mac_wt_a_data67),
      .sc2mac_wt_data68            (sc2mac_wt_a_data68),
      .sc2mac_wt_data69            (sc2mac_wt_a_data69),
      .sc2mac_wt_data70            (sc2mac_wt_a_data70),
      .sc2mac_wt_data71            (sc2mac_wt_a_data71),
      .sc2mac_wt_data72            (sc2mac_wt_a_data72),
      .sc2mac_wt_data73            (sc2mac_wt_a_data73),
      .sc2mac_wt_data74            (sc2mac_wt_a_data74),
      .sc2mac_wt_data75            (sc2mac_wt_a_data75),
      .sc2mac_wt_data76            (sc2mac_wt_a_data76),
      .sc2mac_wt_data77            (sc2mac_wt_a_data77),
      .sc2mac_wt_data78            (sc2mac_wt_a_data78),
      .sc2mac_wt_data79            (sc2mac_wt_a_data79),
      .sc2mac_wt_data80            (sc2mac_wt_a_data80),
      .sc2mac_wt_data81            (sc2mac_wt_a_data81),
      .sc2mac_wt_data82            (sc2mac_wt_a_data82),
      .sc2mac_wt_data83            (sc2mac_wt_a_data83),
      .sc2mac_wt_data84            (sc2mac_wt_a_data84),
      .sc2mac_wt_data85            (sc2mac_wt_a_data85),
      .sc2mac_wt_data86            (sc2mac_wt_a_data86),
      .sc2mac_wt_data87            (sc2mac_wt_a_data87),
      .sc2mac_wt_data88            (sc2mac_wt_a_data88),
      .sc2mac_wt_data89            (sc2mac_wt_a_data89),
      .sc2mac_wt_data90            (sc2mac_wt_a_data90),
      .sc2mac_wt_data91            (sc2mac_wt_a_data91),
      .sc2mac_wt_data92            (sc2mac_wt_a_data92),
      .sc2mac_wt_data93            (sc2mac_wt_a_data93),
      .sc2mac_wt_data94            (sc2mac_wt_a_data94),
      .sc2mac_wt_data95            (sc2mac_wt_a_data95),
      .sc2mac_wt_data96            (sc2mac_wt_a_data96),
      .sc2mac_wt_data97            (sc2mac_wt_a_data97),
      .sc2mac_wt_data98            (sc2mac_wt_a_data98),
      .sc2mac_wt_data99            (sc2mac_wt_a_data99),
      .sc2mac_wt_data100           (sc2mac_wt_a_data100),
      .sc2mac_wt_data101           (sc2mac_wt_a_data101),
      .sc2mac_wt_data102           (sc2mac_wt_a_data102),
      .sc2mac_wt_data103           (sc2mac_wt_a_data103),
      .sc2mac_wt_data104           (sc2mac_wt_a_data104),
      .sc2mac_wt_data105           (sc2mac_wt_a_data105),
      .sc2mac_wt_data106           (sc2mac_wt_a_data106),
      .sc2mac_wt_data107           (sc2mac_wt_a_data107),
      .sc2mac_wt_data108           (sc2mac_wt_a_data108),
      .sc2mac_wt_data109           (sc2mac_wt_a_data109),
      .sc2mac_wt_data110           (sc2mac_wt_a_data110),
      .sc2mac_wt_data111           (sc2mac_wt_a_data111),
      .sc2mac_wt_data112           (sc2mac_wt_a_data112),
      .sc2mac_wt_data113           (sc2mac_wt_a_data113),
      .sc2mac_wt_data114           (sc2mac_wt_a_data114),
      .sc2mac_wt_data115           (sc2mac_wt_a_data115),
      .sc2mac_wt_data116           (sc2mac_wt_a_data116),
      .sc2mac_wt_data117           (sc2mac_wt_a_data117),
      .sc2mac_wt_data118           (sc2mac_wt_a_data118),
      .sc2mac_wt_data119           (sc2mac_wt_a_data119),
      .sc2mac_wt_data120           (sc2mac_wt_a_data120),
      .sc2mac_wt_data121           (sc2mac_wt_a_data121),
      .sc2mac_wt_data122           (sc2mac_wt_a_data122),
      .sc2mac_wt_data123           (sc2mac_wt_a_data123),
      .sc2mac_wt_data124           (sc2mac_wt_a_data124),
      .sc2mac_wt_data125           (sc2mac_wt_a_data125),
      .sc2mac_wt_data126           (sc2mac_wt_a_data126),
      .sc2mac_wt_data127           (sc2mac_wt_a_data127),
      .sc2mac_wt_sel               (sc2mac_wt_a_sel),
      .dla_clk_ovr_on_sync         (dla_clk_ovr_on_sync),
      .global_clk_ovr_on_sync      (global_clk_ovr_on_sync),
      .tmc2slcg_disable_clock_gating(tmc2slcg_disable_clock_gating)
   );

   NV_NVDLA_cmac u_cmac_b (
      .nvdla_core_clk              (nvdla_core_clk),
      .nvdla_core_rstn             (nvdla_core_rstn),
      .cmac_a2csb_resp_valid       (cmac_b2csb_resp_valid),
      .cmac_a2csb_resp_pd          (cmac_b2csb_resp_pd),
      .csb2cmac_a_req_pvld         (csb2cmac_b_req_pvld),
      .csb2cmac_a_req_prdy         (csb2cmac_b_req_prdy),
      .csb2cmac_a_req_pd           (csb2cmac_b_req_pd),
      .mac2accu_pvld               (mac_b2accu_pvld),
      .mac2accu_mask               (mac_b2accu_mask),
      .mac2accu_mode               (mac_b2accu_mode),
      .mac2accu_data0              (mac_b2accu_data0),
      .mac2accu_data1              (mac_b2accu_data1),
      .mac2accu_data2              (mac_b2accu_data2),
      .mac2accu_data3              (mac_b2accu_data3),
      .mac2accu_data4              (mac_b2accu_data4),
      .mac2accu_data5              (mac_b2accu_data5),
      .mac2accu_data6              (mac_b2accu_data6),
      .mac2accu_data7              (mac_b2accu_data7),
      .mac2accu_pd                 (mac_b2accu_pd),
      .sc2mac_dat_pvld             (sc2mac_dat_b_pvld),
      .sc2mac_dat_mask             (sc2mac_dat_b_mask),
      .sc2mac_dat_data0            (sc2mac_dat_b_data0),
      .sc2mac_dat_data1            (sc2mac_dat_b_data1),
      .sc2mac_dat_data2            (sc2mac_dat_b_data2),
      .sc2mac_dat_data3            (sc2mac_dat_b_data3),
      .sc2mac_dat_data4            (sc2mac_dat_b_data4),
      .sc2mac_dat_data5            (sc2mac_dat_b_data5),
      .sc2mac_dat_data6            (sc2mac_dat_b_data6),
      .sc2mac_dat_data7            (sc2mac_dat_b_data7),
      .sc2mac_dat_data8            (sc2mac_dat_b_data8),
      .sc2mac_dat_data9            (sc2mac_dat_b_data9),
      .sc2mac_dat_data10           (sc2mac_dat_b_data10),
      .sc2mac_dat_data11           (sc2mac_dat_b_data11),
      .sc2mac_dat_data12           (sc2mac_dat_b_data12),
      .sc2mac_dat_data13           (sc2mac_dat_b_data13),
      .sc2mac_dat_data14           (sc2mac_dat_b_data14),
      .sc2mac_dat_data15           (sc2mac_dat_b_data15),
      .sc2mac_dat_data16           (sc2mac_dat_b_data16),
      .sc2mac_dat_data17           (sc2mac_dat_b_data17),
      .sc2mac_dat_data18           (sc2mac_dat_b_data18),
      .sc2mac_dat_data19           (sc2mac_dat_b_data19),
      .sc2mac_dat_data20           (sc2mac_dat_b_data20),
      .sc2mac_dat_data21           (sc2mac_dat_b_data21),
      .sc2mac_dat_data22           (sc2mac_dat_b_data22),
      .sc2mac_dat_data23           (sc2mac_dat_b_data23),
      .sc2mac_dat_data24           (sc2mac_dat_b_data24),
      .sc2mac_dat_data25           (sc2mac_dat_b_data25),
      .sc2mac_dat_data26           (sc2mac_dat_b_data26),
      .sc2mac_dat_data27           (sc2mac_dat_b_data27),
      .sc2mac_dat_data28           (sc2mac_dat_b_data28),
      .sc2mac_dat_data29           (sc2mac_dat_b_data29),
      .sc2mac_dat_data30           (sc2mac_dat_b_data30),
      .sc2mac_dat_data31           (sc2mac_dat_b_data31),
      .sc2mac_dat_data32           (sc2mac_dat_b_data32),
      .sc2mac_dat_data33           (sc2mac_dat_b_data33),
      .sc2mac_dat_data34           (sc2mac_dat_b_data34),
      .sc2mac_dat_data35           (sc2mac_dat_b_data35),
      .sc2mac_dat_data36           (sc2mac_dat_b_data36),
      .sc2mac_dat_data37           (sc2mac_dat_b_data37),
      .sc2mac_dat_data38           (sc2mac_dat_b_data38),
      .sc2mac_dat_data39           (sc2mac_dat_b_data39),
      .sc2mac_dat_data40           (sc2mac_dat_b_data40),
      .sc2mac_dat_data41           (sc2mac_dat_b_data41),
      .sc2mac_dat_data42           (sc2mac_dat_b_data42),
      .sc2mac_dat_data43           (sc2mac_dat_b_data43),
      .sc2mac_dat_data44           (sc2mac_dat_b_data44),
      .sc2mac_dat_data45           (sc2mac_dat_b_data45),
      .sc2mac_dat_data46           (sc2mac_dat_b_data46),
      .sc2mac_dat_data47           (sc2mac_dat_b_data47),
      .sc2mac_dat_data48           (sc2mac_dat_b_data48),
      .sc2mac_dat_data49           (sc2mac_dat_b_data49),
      .sc2mac_dat_data50           (sc2mac_dat_b_data50),
      .sc2mac_dat_data51           (sc2mac_dat_b_data51),
      .sc2mac_dat_data52           (sc2mac_dat_b_data52),
      .sc2mac_dat_data53           (sc2mac_dat_b_data53),
      .sc2mac_dat_data54           (sc2mac_dat_b_data54),
      .sc2mac_dat_data55           (sc2mac_dat_b_data55),
      .sc2mac_dat_data56           (sc2mac_dat_b_data56),
      .sc2mac_dat_data57           (sc2mac_dat_b_data57),
      .sc2mac_dat_data58           (sc2mac_dat_b_data58),
      .sc2mac_dat_data59           (sc2mac_dat_b_data59),
      .sc2mac_dat_data60           (sc2mac_dat_b_data60),
      .sc2mac_dat_data61           (sc2mac_dat_b_data61),
      .sc2mac_dat_data62           (sc2mac_dat_b_data62),
      .sc2mac_dat_data63           (sc2mac_dat_b_data63),
      .sc2mac_dat_data64           (sc2mac_dat_b_data64),
      .sc2mac_dat_data65           (sc2mac_dat_b_data65),
      .sc2mac_dat_data66           (sc2mac_dat_b_data66),
      .sc2mac_dat_data67           (sc2mac_dat_b_data67),
      .sc2mac_dat_data68           (sc2mac_dat_b_data68),
      .sc2mac_dat_data69           (sc2mac_dat_b_data69),
      .sc2mac_dat_data70           (sc2mac_dat_b_data70),
      .sc2mac_dat_data71           (sc2mac_dat_b_data71),
      .sc2mac_dat_data72           (sc2mac_dat_b_data72),
      .sc2mac_dat_data73           (sc2mac_dat_b_data73),
      .sc2mac_dat_data74           (sc2mac_dat_b_data74),
      .sc2mac_dat_data75           (sc2mac_dat_b_data75),
      .sc2mac_dat_data76           (sc2mac_dat_b_data76),
      .sc2mac_dat_data77           (sc2mac_dat_b_data77),
      .sc2mac_dat_data78           (sc2mac_dat_b_data78),
      .sc2mac_dat_data79           (sc2mac_dat_b_data79),
      .sc2mac_dat_data80           (sc2mac_dat_b_data80),
      .sc2mac_dat_data81           (sc2mac_dat_b_data81),
      .sc2mac_dat_data82           (sc2mac_dat_b_data82),
      .sc2mac_dat_data83           (sc2mac_dat_b_data83),
      .sc2mac_dat_data84           (sc2mac_dat_b_data84),
      .sc2mac_dat_data85           (sc2mac_dat_b_data85),
      .sc2mac_dat_data86           (sc2mac_dat_b_data86),
      .sc2mac_dat_data87           (sc2mac_dat_b_data87),
      .sc2mac_dat_data88           (sc2mac_dat_b_data88),
      .sc2mac_dat_data89           (sc2mac_dat_b_data89),
      .sc2mac_dat_data90           (sc2mac_dat_b_data90),
      .sc2mac_dat_data91           (sc2mac_dat_b_data91),
      .sc2mac_dat_data92           (sc2mac_dat_b_data92),
      .sc2mac_dat_data93           (sc2mac_dat_b_data93),
      .sc2mac_dat_data94           (sc2mac_dat_b_data94),
      .sc2mac_dat_data95           (sc2mac_dat_b_data95),
      .sc2mac_dat_data96           (sc2mac_dat_b_data96),
      .sc2mac_dat_data97           (sc2mac_dat_b_data97),
      .sc2mac_dat_data98           (sc2mac_dat_b_data98),
      .sc2mac_dat_data99           (sc2mac_dat_b_data99),
      .sc2mac_dat_data100          (sc2mac_dat_b_data100),
      .sc2mac_dat_data101          (sc2mac_dat_b_data101),
      .sc2mac_dat_data102          (sc2mac_dat_b_data102),
      .sc2mac_dat_data103          (sc2mac_dat_b_data103),
      .sc2mac_dat_data104          (sc2mac_dat_b_data104),
      .sc2mac_dat_data105          (sc2mac_dat_b_data105),
      .sc2mac_dat_data106          (sc2mac_dat_b_data106),
      .sc2mac_dat_data107          (sc2mac_dat_b_data107),
      .sc2mac_dat_data108          (sc2mac_dat_b_data108),
      .sc2mac_dat_data109          (sc2mac_dat_b_data109),
      .sc2mac_dat_data110          (sc2mac_dat_b_data110),
      .sc2mac_dat_data111          (sc2mac_dat_b_data111),
      .sc2mac_dat_data112          (sc2mac_dat_b_data112),
      .sc2mac_dat_data113          (sc2mac_dat_b_data113),
      .sc2mac_dat_data114          (sc2mac_dat_b_data114),
      .sc2mac_dat_data115          (sc2mac_dat_b_data115),
      .sc2mac_dat_data116          (sc2mac_dat_b_data116),
      .sc2mac_dat_data117          (sc2mac_dat_b_data117),
      .sc2mac_dat_data118          (sc2mac_dat_b_data118),
      .sc2mac_dat_data119          (sc2mac_dat_b_data119),
      .sc2mac_dat_data120          (sc2mac_dat_b_data120),
      .sc2mac_dat_data121          (sc2mac_dat_b_data121),
      .sc2mac_dat_data122          (sc2mac_dat_b_data122),
      .sc2mac_dat_data123          (sc2mac_dat_b_data123),
      .sc2mac_dat_data124          (sc2mac_dat_b_data124),
      .sc2mac_dat_data125          (sc2mac_dat_b_data125),
      .sc2mac_dat_data126          (sc2mac_dat_b_data126),
      .sc2mac_dat_data127          (sc2mac_dat_b_data127),
      .sc2mac_dat_pd               (sc2mac_dat_b_pd),
      .sc2mac_wt_pvld              (sc2mac_wt_b_pvld),
      .sc2mac_wt_mask              (sc2mac_wt_b_mask),
      .sc2mac_wt_data0             (sc2mac_wt_b_data0),
      .sc2mac_wt_data1             (sc2mac_wt_b_data1),
      .sc2mac_wt_data2             (sc2mac_wt_b_data2),
      .sc2mac_wt_data3             (sc2mac_wt_b_data3),
      .sc2mac_wt_data4             (sc2mac_wt_b_data4),
      .sc2mac_wt_data5             (sc2mac_wt_b_data5),
      .sc2mac_wt_data6             (sc2mac_wt_b_data6),
      .sc2mac_wt_data7             (sc2mac_wt_b_data7),
      .sc2mac_wt_data8             (sc2mac_wt_b_data8),
      .sc2mac_wt_data9             (sc2mac_wt_b_data9),
      .sc2mac_wt_data10            (sc2mac_wt_b_data10),
      .sc2mac_wt_data11            (sc2mac_wt_b_data11),
      .sc2mac_wt_data12            (sc2mac_wt_b_data12),
      .sc2mac_wt_data13            (sc2mac_wt_b_data13),
      .sc2mac_wt_data14            (sc2mac_wt_b_data14),
      .sc2mac_wt_data15            (sc2mac_wt_b_data15),
      .sc2mac_wt_data16            (sc2mac_wt_b_data16),
      .sc2mac_wt_data17            (sc2mac_wt_b_data17),
      .sc2mac_wt_data18            (sc2mac_wt_b_data18),
      .sc2mac_wt_data19            (sc2mac_wt_b_data19),
      .sc2mac_wt_data20            (sc2mac_wt_b_data20),
      .sc2mac_wt_data21            (sc2mac_wt_b_data21),
      .sc2mac_wt_data22            (sc2mac_wt_b_data22),
      .sc2mac_wt_data23            (sc2mac_wt_b_data23),
      .sc2mac_wt_data24            (sc2mac_wt_b_data24),
      .sc2mac_wt_data25            (sc2mac_wt_b_data25),
      .sc2mac_wt_data26            (sc2mac_wt_b_data26),
      .sc2mac_wt_data27            (sc2mac_wt_b_data27),
      .sc2mac_wt_data28            (sc2mac_wt_b_data28),
      .sc2mac_wt_data29            (sc2mac_wt_b_data29),
      .sc2mac_wt_data30            (sc2mac_wt_b_data30),
      .sc2mac_wt_data31            (sc2mac_wt_b_data31),
      .sc2mac_wt_data32            (sc2mac_wt_b_data32),
      .sc2mac_wt_data33            (sc2mac_wt_b_data33),
      .sc2mac_wt_data34            (sc2mac_wt_b_data34),
      .sc2mac_wt_data35            (sc2mac_wt_b_data35),
      .sc2mac_wt_data36            (sc2mac_wt_b_data36),
      .sc2mac_wt_data37            (sc2mac_wt_b_data37),
      .sc2mac_wt_data38            (sc2mac_wt_b_data38),
      .sc2mac_wt_data39            (sc2mac_wt_b_data39),
      .sc2mac_wt_data40            (sc2mac_wt_b_data40),
      .sc2mac_wt_data41            (sc2mac_wt_b_data41),
      .sc2mac_wt_data42            (sc2mac_wt_b_data42),
      .sc2mac_wt_data43            (sc2mac_wt_b_data43),
      .sc2mac_wt_data44            (sc2mac_wt_b_data44),
      .sc2mac_wt_data45            (sc2mac_wt_b_data45),
      .sc2mac_wt_data46            (sc2mac_wt_b_data46),
      .sc2mac_wt_data47            (sc2mac_wt_b_data47),
      .sc2mac_wt_data48            (sc2mac_wt_b_data48),
      .sc2mac_wt_data49            (sc2mac_wt_b_data49),
      .sc2mac_wt_data50            (sc2mac_wt_b_data50),
      .sc2mac_wt_data51            (sc2mac_wt_b_data51),
      .sc2mac_wt_data52            (sc2mac_wt_b_data52),
      .sc2mac_wt_data53            (sc2mac_wt_b_data53),
      .sc2mac_wt_data54            (sc2mac_wt_b_data54),
      .sc2mac_wt_data55            (sc2mac_wt_b_data55),
      .sc2mac_wt_data56            (sc2mac_wt_b_data56),
      .sc2mac_wt_data57            (sc2mac_wt_b_data57),
      .sc2mac_wt_data58            (sc2mac_wt_b_data58),
      .sc2mac_wt_data59            (sc2mac_wt_b_data59),
      .sc2mac_wt_data60            (sc2mac_wt_b_data60),
      .sc2mac_wt_data61            (sc2mac_wt_b_data61),
      .sc2mac_wt_data62            (sc2mac_wt_b_data62),
      .sc2mac_wt_data63            (sc2mac_wt_b_data63),
      .sc2mac_wt_data64            (sc2mac_wt_b_data64),
      .sc2mac_wt_data65            (sc2mac_wt_b_data65),
      .sc2mac_wt_data66            (sc2mac_wt_b_data66),
      .sc2mac_wt_data67            (sc2mac_wt_b_data67),
      .sc2mac_wt_data68            (sc2mac_wt_b_data68),
      .sc2mac_wt_data69            (sc2mac_wt_b_data69),
      .sc2mac_wt_data70            (sc2mac_wt_b_data70),
      .sc2mac_wt_data71            (sc2mac_wt_b_data71),
      .sc2mac_wt_data72            (sc2mac_wt_b_data72),
      .sc2mac_wt_data73            (sc2mac_wt_b_data73),
      .sc2mac_wt_data74            (sc2mac_wt_b_data74),
      .sc2mac_wt_data75            (sc2mac_wt_b_data75),
      .sc2mac_wt_data76            (sc2mac_wt_b_data76),
      .sc2mac_wt_data77            (sc2mac_wt_b_data77),
      .sc2mac_wt_data78            (sc2mac_wt_b_data78),
      .sc2mac_wt_data79            (sc2mac_wt_b_data79),
      .sc2mac_wt_data80            (sc2mac_wt_b_data80),
      .sc2mac_wt_data81            (sc2mac_wt_b_data81),
      .sc2mac_wt_data82            (sc2mac_wt_b_data82),
      .sc2mac_wt_data83            (sc2mac_wt_b_data83),
      .sc2mac_wt_data84            (sc2mac_wt_b_data84),
      .sc2mac_wt_data85            (sc2mac_wt_b_data85),
      .sc2mac_wt_data86            (sc2mac_wt_b_data86),
      .sc2mac_wt_data87            (sc2mac_wt_b_data87),
      .sc2mac_wt_data88            (sc2mac_wt_b_data88),
      .sc2mac_wt_data89            (sc2mac_wt_b_data89),
      .sc2mac_wt_data90            (sc2mac_wt_b_data90),
      .sc2mac_wt_data91            (sc2mac_wt_b_data91),
      .sc2mac_wt_data92            (sc2mac_wt_b_data92),
      .sc2mac_wt_data93            (sc2mac_wt_b_data93),
      .sc2mac_wt_data94            (sc2mac_wt_b_data94),
      .sc2mac_wt_data95            (sc2mac_wt_b_data95),
      .sc2mac_wt_data96            (sc2mac_wt_b_data96),
      .sc2mac_wt_data97            (sc2mac_wt_b_data97),
      .sc2mac_wt_data98            (sc2mac_wt_b_data98),
      .sc2mac_wt_data99            (sc2mac_wt_b_data99),
      .sc2mac_wt_data100           (sc2mac_wt_b_data100),
      .sc2mac_wt_data101           (sc2mac_wt_b_data101),
      .sc2mac_wt_data102           (sc2mac_wt_b_data102),
      .sc2mac_wt_data103           (sc2mac_wt_b_data103),
      .sc2mac_wt_data104           (sc2mac_wt_b_data104),
      .sc2mac_wt_data105           (sc2mac_wt_b_data105),
      .sc2mac_wt_data106           (sc2mac_wt_b_data106),
      .sc2mac_wt_data107           (sc2mac_wt_b_data107),
      .sc2mac_wt_data108           (sc2mac_wt_b_data108),
      .sc2mac_wt_data109           (sc2mac_wt_b_data109),
      .sc2mac_wt_data110           (sc2mac_wt_b_data110),
      .sc2mac_wt_data111           (sc2mac_wt_b_data111),
      .sc2mac_wt_data112           (sc2mac_wt_b_data112),
      .sc2mac_wt_data113           (sc2mac_wt_b_data113),
      .sc2mac_wt_data114           (sc2mac_wt_b_data114),
      .sc2mac_wt_data115           (sc2mac_wt_b_data115),
      .sc2mac_wt_data116           (sc2mac_wt_b_data116),
      .sc2mac_wt_data117           (sc2mac_wt_b_data117),
      .sc2mac_wt_data118           (sc2mac_wt_b_data118),
      .sc2mac_wt_data119           (sc2mac_wt_b_data119),
      .sc2mac_wt_data120           (sc2mac_wt_b_data120),
      .sc2mac_wt_data121           (sc2mac_wt_b_data121),
      .sc2mac_wt_data122           (sc2mac_wt_b_data122),
      .sc2mac_wt_data123           (sc2mac_wt_b_data123),
      .sc2mac_wt_data124           (sc2mac_wt_b_data124),
      .sc2mac_wt_data125           (sc2mac_wt_b_data125),
      .sc2mac_wt_data126           (sc2mac_wt_b_data126),
      .sc2mac_wt_data127           (sc2mac_wt_b_data127),
      .sc2mac_wt_sel               (sc2mac_wt_b_sel),
      .dla_clk_ovr_on_sync         (dla_clk_ovr_on_sync),
      .global_clk_ovr_on_sync      (global_clk_ovr_on_sync),
      .tmc2slcg_disable_clock_gating(tmc2slcg_disable_clock_gating)
   );

   NV_NVDLA_cacc u_cacc (
      .nvdla_core_clk              (nvdla_core_clk),
      .nvdla_core_rstn             (nvdla_core_rstn),
      .pwrbus_ram_pd               (pwrbus_ram_pd),
      .csb2cacc_req_pvld           (csb2cacc_req_pvld),
      .csb2cacc_req_prdy           (csb2cacc_req_prdy),
      .csb2cacc_req_pd             (csb2cacc_req_pd),
      .cacc2csb_resp_valid         (cacc2csb_resp_valid),
      .cacc2csb_resp_pd            (cacc2csb_resp_pd),
      .mac_a2accu_pvld             (mac_a2accu_pvld),
      .mac_a2accu_mask             (mac_a2accu_mask),
      .mac_a2accu_mode             (mac_a2accu_mode),
      .mac_a2accu_data0            (mac_a2accu_data0),
      .mac_a2accu_data1            (mac_a2accu_data1),
      .mac_a2accu_data2            (mac_a2accu_data2),
      .mac_a2accu_data3            (mac_a2accu_data3),
      .mac_a2accu_data4            (mac_a2accu_data4),
      .mac_a2accu_data5            (mac_a2accu_data5),
      .mac_a2accu_data6            (mac_a2accu_data6),
      .mac_a2accu_data7            (mac_a2accu_data7),
      .mac_a2accu_pd               (mac_a2accu_pd),
      .mac_b2accu_pvld             (mac_b2accu_pvld),
      .mac_b2accu_mask             (mac_b2accu_mask),
      .mac_b2accu_mode             (mac_b2accu_mode),
      .mac_b2accu_data0            (mac_b2accu_data0),
      .mac_b2accu_data1            (mac_b2accu_data1),
      .mac_b2accu_data2            (mac_b2accu_data2),
      .mac_b2accu_data3            (mac_b2accu_data3),
      .mac_b2accu_data4            (mac_b2accu_data4),
      .mac_b2accu_data5            (mac_b2accu_data5),
      .mac_b2accu_data6            (mac_b2accu_data6),
      .mac_b2accu_data7            (mac_b2accu_data7),
      .mac_b2accu_pd               (mac_b2accu_pd),
      .cacc2sdp_valid              (cacc2sdp_valid),
      .cacc2sdp_ready              (cacc2sdp_ready),
      .cacc2sdp_pd                 (cacc2sdp_pd),
      .accu2sc_credit_vld          (accu2sc_credit_vld),
      .accu2sc_credit_size         (accu2sc_credit_size),
      .cacc2glb_done_intr_pd       (cacc2glb_done_intr_pd),
      .dla_clk_ovr_on_sync         (dla_clk_ovr_on_sync),
      .global_clk_ovr_on_sync      (global_clk_ovr_on_sync),
      .tmc2slcg_disable_clock_gating(tmc2slcg_disable_clock_gating)
   );

   // ---- Bounded memory responders -----------------------------------------
   // One per read-DMA port.  `atoms_owed` is exported so the checker can state
   // a fetch-side obligation against a ledger it does not itself maintain.
   wire [15:0] mem_owed_dat_mcif;
   wire [15:0] mem_owed_dat_cvif;
   wire [15:0] mem_owed_wt_mcif;
   wire [15:0] mem_owed_wt_cvif;

   nvdla_conv_mem_responder u_mem_dat_mcif (
      .nvdla_core_clk  (nvdla_core_clk),
      .nvdla_core_rstn (nvdla_core_rstn),
      .req_valid       (cdma_dat2mcif_rd_req_valid),
      .req_ready       (cdma_dat2mcif_rd_req_ready),
      .req_pd          (cdma_dat2mcif_rd_req_pd),
      .rsp_valid       (mcif2cdma_dat_rd_rsp_valid),
      .rsp_ready       (mcif2cdma_dat_rd_rsp_ready),
      .rsp_pd          (mcif2cdma_dat_rd_rsp_pd),
      .env_hold        (env_mem_hold[0]),
      .env_data        (env_mem_dat_mcif_data),
      .atoms_owed      (mem_owed_dat_mcif)
   );

   nvdla_conv_mem_responder u_mem_dat_cvif (
      .nvdla_core_clk  (nvdla_core_clk),
      .nvdla_core_rstn (nvdla_core_rstn),
      .req_valid       (cdma_dat2cvif_rd_req_valid),
      .req_ready       (cdma_dat2cvif_rd_req_ready),
      .req_pd          (cdma_dat2cvif_rd_req_pd),
      .rsp_valid       (cvif2cdma_dat_rd_rsp_valid),
      .rsp_ready       (cvif2cdma_dat_rd_rsp_ready),
      .rsp_pd          (cvif2cdma_dat_rd_rsp_pd),
      .env_hold        (env_mem_hold[1]),
      .env_data        (env_mem_dat_cvif_data),
      .atoms_owed      (mem_owed_dat_cvif)
   );

   nvdla_conv_mem_responder u_mem_wt_mcif (
      .nvdla_core_clk  (nvdla_core_clk),
      .nvdla_core_rstn (nvdla_core_rstn),
      .req_valid       (cdma_wt2mcif_rd_req_valid),
      .req_ready       (cdma_wt2mcif_rd_req_ready),
      .req_pd          (cdma_wt2mcif_rd_req_pd),
      .rsp_valid       (mcif2cdma_wt_rd_rsp_valid),
      .rsp_ready       (mcif2cdma_wt_rd_rsp_ready),
      .rsp_pd          (mcif2cdma_wt_rd_rsp_pd),
      .env_hold        (env_mem_hold[2]),
      .env_data        (env_mem_wt_mcif_data),
      .atoms_owed      (mem_owed_wt_mcif)
   );

   nvdla_conv_mem_responder u_mem_wt_cvif (
      .nvdla_core_clk  (nvdla_core_clk),
      .nvdla_core_rstn (nvdla_core_rstn),
      .req_valid       (cdma_wt2cvif_rd_req_valid),
      .req_ready       (cdma_wt2cvif_rd_req_ready),
      .req_pd          (cdma_wt2cvif_rd_req_pd),
      .rsp_valid       (cvif2cdma_wt_rd_rsp_valid),
      .rsp_ready       (cvif2cdma_wt_rd_rsp_ready),
      .rsp_pd          (cvif2cdma_wt_rd_rsp_pd),
      .env_hold        (env_mem_hold[3]),
      .env_data        (env_mem_wt_cvif_data),
      .atoms_owed      (mem_owed_wt_cvif)
   );

   // ---- SDP sink ----------------------------------------------------------
   // Free backpressure, bounded to SINK_MAX consecutive stalled cycles.  An
   // unbounded sink stall makes every drain obligation false for a reason that
   // is the environment's and not the design's.
   localparam [2:0] SINK_MAX = 3'd4;
   reg [2:0] ft_sdp_stall;
   assign cacc2sdp_ready = !(env_sdp_hold && (ft_sdp_stall != SINK_MAX));

   always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
      if (!nvdla_core_rstn) begin
         ft_sdp_stall <= 3'd0;
      end else if (cacc2sdp_valid && env_sdp_hold) begin
         ft_sdp_stall <= (ft_sdp_stall == SINK_MAX) ? SINK_MAX : (ft_sdp_stall + 3'd1);
      end else begin
         ft_sdp_stall <= 3'd0;
      end
   end

   // ---- Checker -----------------------------------------------------------
   nvdla_conv_pipeline_checker u_checker (
      .clk                      (nvdla_core_clk),
      .reset_n                  (nvdla_core_rstn),

      .sym_addr                 (env_sym_addr),
      .sym_col                  (env_sym_col),

      .mem_req_valid            ({cdma_wt2cvif_rd_req_valid,
                                  cdma_wt2mcif_rd_req_valid,
                                  cdma_dat2cvif_rd_req_valid,
                                  cdma_dat2mcif_rd_req_valid}),
      .mem_req_ready            ({cdma_wt2cvif_rd_req_ready,
                                  cdma_wt2mcif_rd_req_ready,
                                  cdma_dat2cvif_rd_req_ready,
                                  cdma_dat2mcif_rd_req_ready}),
      .mem_req_pd_flat          ({cdma_wt2cvif_rd_req_pd,
                                  cdma_wt2mcif_rd_req_pd,
                                  cdma_dat2cvif_rd_req_pd,
                                  cdma_dat2mcif_rd_req_pd}),
      .mem_rsp_valid            ({cvif2cdma_wt_rd_rsp_valid,
                                  mcif2cdma_wt_rd_rsp_valid,
                                  cvif2cdma_dat_rd_rsp_valid,
                                  mcif2cdma_dat_rd_rsp_valid}),
      .mem_rsp_ready            ({cvif2cdma_wt_rd_rsp_ready,
                                  mcif2cdma_wt_rd_rsp_ready,
                                  cvif2cdma_dat_rd_rsp_ready,
                                  mcif2cdma_dat_rd_rsp_ready}),
      .mem_owed_flat            ({mem_owed_wt_cvif, mem_owed_wt_mcif,
                                  mem_owed_dat_cvif, mem_owed_dat_mcif}),

      .buf_dat_wr_en            (cdma2buf_dat_wr_en),
      .buf_dat_wr_addr          (cdma2buf_dat_wr_addr),
      .buf_dat_wr_hsel          (cdma2buf_dat_wr_hsel),
      .buf_dat_wr_data          (cdma2buf_dat_wr_data),
      .buf_wt_wr_en             (cdma2buf_wt_wr_en),
      .buf_wt_wr_addr           (cdma2buf_wt_wr_addr),
      .buf_wt_wr_hsel           (cdma2buf_wt_wr_hsel),
      .buf_wt_wr_data           (cdma2buf_wt_wr_data),

      .buf_dat_rd_en            (sc2buf_dat_rd_en),
      .buf_dat_rd_addr          (sc2buf_dat_rd_addr),
      .buf_dat_rd_valid         (sc2buf_dat_rd_valid),
      .buf_dat_rd_data          (sc2buf_dat_rd_data),
      .buf_wt_rd_en             (sc2buf_wt_rd_en),
      .buf_wt_rd_addr           (sc2buf_wt_rd_addr),
      .buf_wt_rd_valid          (sc2buf_wt_rd_valid),
      .buf_wt_rd_data           (sc2buf_wt_rd_data),
      .buf_wmb_rd_en            (sc2buf_wmb_rd_en),
      .buf_wmb_rd_addr          (sc2buf_wmb_rd_addr),
      .buf_wmb_rd_valid         (sc2buf_wmb_rd_valid),
      .buf_wmb_rd_data          (sc2buf_wmb_rd_data),

      .cdma2sc_dat_updt         (cdma2sc_dat_updt),
      .cdma2sc_dat_entries      (cdma2sc_dat_entries),
      .sc2cdma_dat_updt         (sc2cdma_dat_updt),
      .sc2cdma_dat_entries      (sc2cdma_dat_entries),
      .cdma2sc_wt_updt          (cdma2sc_wt_updt),
      .cdma2sc_wt_entries       (cdma2sc_wt_entries),
      .sc2cdma_wt_updt          (sc2cdma_wt_updt),
      .sc2cdma_wt_entries       (sc2cdma_wt_entries),
      .cdma2sc_dat_pending_ack  (cdma2sc_dat_pending_ack),
      .sc2cdma_dat_pending_req  (sc2cdma_dat_pending_req),
      .cdma2sc_wt_pending_ack   (cdma2sc_wt_pending_ack),
      .sc2cdma_wt_pending_req   (sc2cdma_wt_pending_req),

      .sc2mac_dat_pvld          ({sc2mac_dat_b_pvld, sc2mac_dat_a_pvld}),
      .sc2mac_dat_pd_flat       ({sc2mac_dat_b_pd,   sc2mac_dat_a_pd}),
      .sc2mac_wt_pvld           ({sc2mac_wt_b_pvld,  sc2mac_wt_a_pvld}),

      .mac2accu_pvld            ({mac_b2accu_pvld,   mac_a2accu_pvld}),
      .mac2accu_pd_flat         ({mac_b2accu_pd,     mac_a2accu_pd}),

      .sdp_valid                (cacc2sdp_valid),
      .sdp_ready                (cacc2sdp_ready),
      .sdp_pd                   (cacc2sdp_pd),
      .accu2sc_credit_vld       (accu2sc_credit_vld),
      .accu2sc_credit_size      (accu2sc_credit_size),

      .csb_req_pvld             ({csb2cacc_req_pvld, csb2cmac_b_req_pvld,
                                  csb2cmac_a_req_pvld, csb2csc_req_pvld,
                                  csb2cdma_req_pvld}),
      .csb_req_prdy             ({csb2cacc_req_prdy, csb2cmac_b_req_prdy,
                                  csb2cmac_a_req_prdy, csb2csc_req_prdy,
                                  csb2cdma_req_prdy}),
      .csb_req_pd_flat          ({csb2cacc_req_pd, csb2cmac_b_req_pd,
                                  csb2cmac_a_req_pd, csb2csc_req_pd,
                                  csb2cdma_req_pd}),
      .csb_resp_valid           ({cacc2csb_resp_valid, cmac_b2csb_resp_valid,
                                  cmac_a2csb_resp_valid, csc2csb_resp_valid,
                                  cdma2csb_resp_valid})
   );

endmodule
