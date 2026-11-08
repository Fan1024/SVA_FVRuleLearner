`timescale 1ns/1ps
`default_nettype none

module nvdla_bdma_targets (input wire clk, input wire reset_n,
    input logic cmd_valid,
    input logic cmd_ready,
    input logic rreq_valid,
    input logic rreq_ready,
    input logic [78:0] rreq_pd,
    input logic rrsp_valid,
    input logic rrsp_ready,
    input logic [513:0] rrsp_pd,
    input logic wreq_valid,
    input logic wreq_ready,
    input logic [514:0] wreq_pd,
    input logic cv_rreq_valid,
    input logic cv_wreq_valid,
    input logic grp0_done,
    input logic grp1_done,
    input logic ld_tran_valid,
    input logic ld_cmd_ready,
    input logic [23:0] ld_line_count,
    input logic [23:0] ld_surf_count,
    input logic [63:0] ld_line_addr,
    input logic [63:0] ld_surf_addr,
    input logic [12:0] ld_line_size,
    input logic [31:0] ld_line_strd,
    input logic [31:0] ld_surf_strd,
    input logic [23:0] ld_line_rpt,
    input logic [23:0] ld_surf_rpt,
    input logic ld_src_type,
    input logic ld_cv_req_vld,
    input logic ld_mc_req_vld,
    input logic [4:0] cq_wr_count,
    input logic [4:0] cq_rd_count,
    input logic [4:0] cq_wr_adr,
    input logic [4:0] cq_rd_adr,
    input logic cq_push,
    input logic cq_pop,
    input logic cq_rd_pvld,
    input logic st_cmd_en,
    input logic st_dat_en,
    input logic st_tran_cmd_v,
    input logic [11:0] st_beat_count,
    input logic [12:0] st_line_count,
    input logic [12:0] st_surf_count,
    input logic [12:0] st_line_size,
    input logic st_mc_rsp_vld,
    input logic st_cv_rsp_vld,
    input logic st_cv_wr_vld,
    input logic st_mc_wr_vld,
    input logic st_intr_wr,
    input logic [7:0] lat_wr_count,
    input logic [7:0] lat_rd_count,
    input logic [7:0] lat_wr_adr,
    input logic [7:0] lat_rd_adr,
    input logic lat_push,
    input logic lat_pop,
    input logic lat_rd_push,
    input logic lat_wr_pop,
    input logic [6:0] pkg_ref_count,
    input logic [6:0] pkg_os_beats,
    input logic [2:0] pkg_cmds_seen
);

   localparam [7:0]  N_REQ_OWED   = 8'd8;
   localparam [7:0]  N_BEAT_OWED  = 8'd64;
   localparam [7:0]  N_HELD       = 8'd64;
   localparam [7:0]  N_WCMD_OWED  = 8'd64;
   localparam [9:0]  N_WDAT_OWED  = 10'd512;
   localparam [9:0]  N_ISSUE      = 10'd64;
   localparam [9:0]  N_DRAIN      = 10'd128;
   localparam [9:0]  N_STALL      = 10'd256;

   wire cmd_fire  = cmd_valid  && cmd_ready;
   wire rreq_fire = rreq_valid && rreq_ready;
   wire rrsp_fire = rrsp_valid && rrsp_ready;
   wire wreq_fire = wreq_valid && wreq_ready;
   wire wcmd_fire = wreq_fire && !wreq_pd[514];
   wire wdat_fire = wreq_fire &&  wreq_pd[514];

   wire       cmd_seen      = (pkg_cmds_seen != 3'd0);

   reg [7:0] req_owed;
   reg [7:0] beat_owed;
   reg [7:0] held;
   reg [7:0] wcmd_owed;
   reg [9:0] wdat_owed;

   reg [511:0] rsp_xor;
   reg [511:0] wr_xor;

   reg [9:0] ctr_issue;
   reg [9:0] ctr_drain;
   reg [9:0] ctr_stall;

   reg       post_reset;
   reg [3:0] settle;
   reg       rreq_stall_q;
   reg       wreq_stall_q;

   wire warm = (settle == 4'd15);

   wire can_issue = rreq_ready && (req_owed != 8'd0) && (beat_owed <= 8'd56);
   wire can_drain = wreq_ready && (held != 8'd0);
   wire any_fire  = rreq_fire || rrsp_fire || wreq_fire;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         req_owed   <= 8'd0;
         beat_owed  <= 8'd0;
         held       <= 8'd0;
         wcmd_owed  <= 8'd0;
         wdat_owed  <= 10'd0;
         rsp_xor    <= 512'd0;
         wr_xor     <= 512'd0;
         ctr_issue  <= 10'd0;
         ctr_drain  <= 10'd0;
         ctr_stall  <= 10'd0;
         post_reset <= 1'b0;
         settle     <= 4'd0;
         rreq_stall_q <= 1'b0;
         wreq_stall_q <= 1'b0;
      end else begin
         post_reset <= 1'b1;
         if (settle != 4'd15) settle <= settle + 4'd1;
         rreq_stall_q <= rreq_valid && !rreq_ready;
         wreq_stall_q <= wreq_valid && !wreq_ready;

         req_owed  <= req_owed  + (cmd_fire  ? 8'd2  : 8'd0)
                                - (rreq_fire ? 8'd1  : 8'd0);
         beat_owed <= beat_owed + (rreq_fire ? 8'd8  : 8'd0)
                                - (rrsp_fire ? 8'd1  : 8'd0);
         held      <= held      + (rrsp_fire ? 8'd1  : 8'd0)
                                - (wdat_fire ? 8'd1  : 8'd0);
         wcmd_owed <= wcmd_owed + (cmd_fire  ? 8'd2  : 8'd0)
                                - (wcmd_fire ? 8'd1  : 8'd0);
         wdat_owed <= wdat_owed + (cmd_fire  ? 10'd16 : 10'd0)
                                - (wdat_fire ? 10'd1  : 10'd0);

         if (rrsp_fire) rsp_xor <= rsp_xor ^ rrsp_pd[511:0];
         if (wdat_fire) wr_xor  <= wr_xor  ^ wreq_pd[511:0];

         ctr_issue <= !(can_issue && !rreq_fire) ? 10'd0
                    : (ctr_issue == 10'd1023) ? ctr_issue : ctr_issue + 10'd1;
         ctr_drain <= !(can_drain && !wreq_fire) ? 10'd0
                    : (ctr_drain == 10'd1023) ? ctr_drain : ctr_drain + 10'd1;
         ctr_stall <= !((can_issue || can_drain) && !any_fire) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
