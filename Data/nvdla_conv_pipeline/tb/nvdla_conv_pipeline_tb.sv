`timescale 1ns/1ps
`default_nettype none

module nvdla_conv_pipeline_checker (
   input wire         clk,
   input wire         reset_n,

   input wire [11:0]  sym_addr,
   input wire         sym_col,

   input wire [3:0]   mem_req_valid,
   input wire [3:0]   mem_req_ready,
   input wire [315:0] mem_req_pd_flat,
   input wire [3:0]   mem_rsp_valid,
   input wire [3:0]   mem_rsp_ready,
   input wire [63:0]  mem_owed_flat,

   input wire         buf_dat_wr_en,
   input wire [11:0]  buf_dat_wr_addr,
   input wire [1:0]   buf_dat_wr_hsel,
   input wire [1023:0] buf_dat_wr_data,
   input wire         buf_wt_wr_en,
   input wire [11:0]  buf_wt_wr_addr,
   input wire         buf_wt_wr_hsel,
   input wire [511:0] buf_wt_wr_data,

   input wire         buf_dat_rd_en,
   input wire [11:0]  buf_dat_rd_addr,
   input wire         buf_dat_rd_valid,
   input wire [1023:0] buf_dat_rd_data,
   input wire         buf_wt_rd_en,
   input wire [11:0]  buf_wt_rd_addr,
   input wire         buf_wt_rd_valid,
   input wire [1023:0] buf_wt_rd_data,
   input wire         buf_wmb_rd_en,
   input wire [7:0]   buf_wmb_rd_addr,
   input wire         buf_wmb_rd_valid,
   input wire [1023:0] buf_wmb_rd_data,

   input wire         cdma2sc_dat_updt,
   input wire [11:0]  cdma2sc_dat_entries,
   input wire         sc2cdma_dat_updt,
   input wire [11:0]  sc2cdma_dat_entries,
   input wire         cdma2sc_wt_updt,
   input wire [11:0]  cdma2sc_wt_entries,
   input wire         sc2cdma_wt_updt,
   input wire [11:0]  sc2cdma_wt_entries,
   input wire         cdma2sc_dat_pending_ack,
   input wire         sc2cdma_dat_pending_req,
   input wire         cdma2sc_wt_pending_ack,
   input wire         sc2cdma_wt_pending_req,

   input wire [1:0]   sc2mac_dat_pvld,
   input wire [17:0]  sc2mac_dat_pd_flat,
   input wire [1:0]   sc2mac_wt_pvld,

   input wire [1:0]   mac2accu_pvld,
   input wire [17:0]  mac2accu_pd_flat,

   input wire         sdp_valid,
   input wire         sdp_ready,
   input wire [513:0] sdp_pd,
   input wire         accu2sc_credit_vld,
   input wire [2:0]   accu2sc_credit_size,

   input wire [4:0]   csb_req_pvld,
   input wire [4:0]   csb_req_prdy,
   input wire [314:0] csb_req_pd_flat,
   input wire [4:0]   csb_resp_valid
);

   reg [7:0] age;
   always @(posedge clk) begin
      if (!reset_n)          age <= 8'd0;
      else if (age != 8'hff) age <= age + 8'd1;
   end

   wire warm4  = (age >= 8'd4);
   wire warm8  = (age >= 8'd8);
   wire warm16 = (age >= 8'd16);

   wire [3:0] sym_bank = sym_addr[11:8];
   wire [7:0] sym_row  = sym_addr[7:0];

   wire [3:0] dat_wr_bank = buf_dat_wr_addr[11:8];
   wire [3:0] wt_wr_bank  = buf_wt_wr_addr[11:8];
   wire [3:0] dat_rd_bank = buf_dat_rd_addr[11:8];
   wire [3:0] wt_rd_bank  = buf_wt_rd_addr[11:8];

   wire wr_bank_clash = buf_dat_wr_en && buf_wt_wr_en &&
                        (dat_wr_bank == wt_wr_bank);
   wire wr_poison     = wr_bank_clash &&
                        ((dat_wr_bank == sym_bank) || (wt_wr_bank == sym_bank));

   wire [511:0] dat_wr_half = sym_col ? buf_dat_wr_data[1023:512]
                                      : buf_dat_wr_data[511:0];
   wire dat_wr_hit = buf_dat_wr_en && (buf_dat_wr_addr == sym_addr) &&
                     buf_dat_wr_hsel[sym_col];
   wire wt_wr_hit  = buf_wt_wr_en  && (buf_wt_wr_addr  == sym_addr) &&
                     (buf_wt_wr_hsel == sym_col);
   wire line_write = (dat_wr_hit || wt_wr_hit) && !wr_bank_clash;
   wire line_touch = line_write || wr_poison;

   reg [511:0] shadow;
   reg         shadow_valid;
   reg [3:0]   quiet;

   always @(posedge clk) begin
      if (!reset_n) begin
         shadow       <= 512'd0;
         shadow_valid <= 1'b0;
         quiet        <= 4'd0;
      end else if (wr_poison) begin
         shadow_valid <= 1'b0;
         quiet        <= 4'd0;
      end else if (line_write) begin
         shadow       <= wt_wr_hit ? buf_wt_wr_data : dat_wr_half;
         shadow_valid <= 1'b1;
         quiet        <= 4'd0;
      end else if (quiet != 4'hf) begin
         quiet        <= quiet + 4'd1;
      end
   end

   wire line_settled = shadow_valid && (quiet >= 4'd4);

   wire dat_rd_issue = buf_dat_rd_en && (buf_dat_rd_addr == sym_addr);
   wire dat_rd_clash = (buf_wt_rd_en && (wt_rd_bank == sym_bank)) ||
                       (buf_wmb_rd_en && (sym_bank == 4'd15));
   wire dat_arm_now  = dat_rd_issue && (sym_bank <= 4'd14) &&
                       !dat_rd_clash && line_settled;

   wire wt_rd_issue  = buf_wt_rd_en && (buf_wt_rd_addr == sym_addr);
   wire wt_rd_clash  = (buf_dat_rd_en && (dat_rd_bank == sym_bank)) ||
                       (buf_wmb_rd_en && (sym_bank == 4'd15));
   wire wt_arm_now   = wt_rd_issue && (sym_bank >= 4'd1) &&
                       !wt_rd_clash && line_settled;

   wire wmb_rd_issue = buf_wmb_rd_en && (buf_wmb_rd_addr == sym_row);
   wire wmb_rd_clash = buf_wt_rd_en && (wt_rd_bank == 4'd15);
   wire wmb_arm_now  = wmb_rd_issue && (sym_bank == 4'd15) &&
                       !wmb_rd_clash && line_settled;

   reg [5:0]   dat_arm;  reg [511:0] dat_exp;
   reg [5:0]   wt_arm;   reg [511:0] wt_exp;
   reg [5:0]   wmb_arm;  reg [511:0] wmb_exp;

   always @(posedge clk) begin
      if (!reset_n) begin
         dat_arm <= 6'd0;  wt_arm <= 6'd0;  wmb_arm <= 6'd0;
         dat_exp <= 512'd0; wt_exp <= 512'd0; wmb_exp <= 512'd0;
      end else begin
         if (line_touch)        dat_arm <= 6'd0;
         else if (dat_arm_now)  dat_arm <= 6'b000001;
         else                   dat_arm <= {dat_arm[4:0], 1'b0};

         if (line_touch)        wt_arm <= 6'd0;
         else if (wt_arm_now)   wt_arm <= 6'b000001;
         else                   wt_arm <= {wt_arm[4:0], 1'b0};

         if (line_touch)        wmb_arm <= 6'd0;
         else if (wmb_arm_now)  wmb_arm <= 6'b000001;
         else                   wmb_arm <= {wmb_arm[4:0], 1'b0};

         if (!line_touch && dat_arm_now) dat_exp <= shadow;
         if (!line_touch && wt_arm_now)  wt_exp  <= shadow;
         if (!line_touch && wmb_arm_now) wmb_exp <= shadow;
      end
   end

   wire [511:0] dat_rd_half = sym_col ? buf_dat_rd_data[1023:512]
                                      : buf_dat_rd_data[511:0];
   wire [511:0] wt_rd_half  = sym_col ? buf_wt_rd_data[1023:512]
                                      : buf_wt_rd_data[511:0];
   wire [511:0] wmb_rd_half = sym_col ? buf_wmb_rd_data[1023:512]
                                      : buf_wmb_rd_data[511:0];

   reg [511:0] last_dat_half;
   reg         last_dat_valid;
   always @(posedge clk) begin
      if (!reset_n) begin
         last_dat_half  <= 512'd0;
         last_dat_valid <= 1'b0;
      end else if (line_touch) begin
         last_dat_valid <= 1'b0;
      end else if (dat_arm[5]) begin
         last_dat_half  <= dat_rd_half;
         last_dat_valid <= 1'b1;
      end
   end

   reg [5:0] dat_en_sr, wt_en_sr, wmb_en_sr;
   reg [3:0] dat_inflight;
   always @(posedge clk) begin
      if (!reset_n) begin
         dat_en_sr <= 6'd0; wt_en_sr <= 6'd0; wmb_en_sr <= 6'd0;
         dat_inflight <= 4'd0;
      end else begin
         dat_en_sr <= {dat_en_sr[4:0], buf_dat_rd_en};
         wt_en_sr  <= {wt_en_sr[4:0],  buf_wt_rd_en};
         wmb_en_sr <= {wmb_en_sr[4:0], buf_wmb_rd_en};
         case ({buf_dat_rd_en, dat_en_sr[5]})
            2'b10: if (dat_inflight != 4'hf) dat_inflight <= dat_inflight + 4'd1;
            2'b01: if (dat_inflight != 4'd0) dat_inflight <= dat_inflight - 4'd1;
            default: ;
         endcase
      end
   end

   wire [8:0] sc_pd   [0:1];
   wire [8:0] mac_pd  [0:1];
   assign sc_pd[0]  = sc2mac_dat_pd_flat[8:0];
   assign sc_pd[1]  = sc2mac_dat_pd_flat[17:9];
   assign mac_pd[0] = mac2accu_pd_flat[8:0];
   assign mac_pd[1] = mac2accu_pd_flat[17:9];

   reg [8:0]  tok_mem [0:15];
   reg [2:0]  tok_wr  [0:1];
   reg [2:0]  tok_rd  [0:1];
   reg [3:0]  tok_cnt [0:1];
   reg [15:0] tok_push [0:1];
   reg [15:0] tok_pop  [0:1];

   wire [1:0] tok_push_now = sc2mac_dat_pvld;
   wire [1:0] tok_pop_now  = mac2accu_pvld & {2{warm4}};

   integer L;
   always @(posedge clk) begin
      if (!reset_n) begin
         for (L = 0; L < 2; L = L + 1) begin
            tok_wr[L]   <= 3'd0;
            tok_rd[L]   <= 3'd0;
            tok_cnt[L]  <= 4'd0;
            tok_push[L] <= 16'd0;
            tok_pop[L]  <= 16'd0;
         end
      end else begin
         for (L = 0; L < 2; L = L + 1) begin
            if (tok_push_now[L]) begin
               tok_mem[(L*8) + tok_wr[L]] <= sc_pd[L];
               tok_wr[L]   <= tok_wr[L] + 3'd1;
               if (tok_push[L] != 16'hffff) tok_push[L] <= tok_push[L] + 16'd1;
            end
            if (tok_pop_now[L]) begin
               tok_rd[L]  <= tok_rd[L] + 3'd1;
               if (tok_pop[L] != 16'hffff) tok_pop[L] <= tok_pop[L] + 16'd1;
            end
            case ({tok_push_now[L], tok_pop_now[L]})
               2'b10: if (tok_cnt[L] != 4'hf) tok_cnt[L] <= tok_cnt[L] + 4'd1;
               2'b01: if (tok_cnt[L] != 4'd0) tok_cnt[L] <= tok_cnt[L] - 4'd1;
               default: ;
            endcase
         end
      end
   end

   wire sdp_fire = sdp_valid && sdp_ready;
   reg [15:0] sdp_beats, sdp_beats_d1, sdp_credits;
   always @(posedge clk) begin
      if (!reset_n) begin
         sdp_beats <= 16'd0; sdp_beats_d1 <= 16'd0; sdp_credits <= 16'd0;
      end else begin
         sdp_beats_d1 <= sdp_beats;
         if (sdp_fire && (sdp_beats != 16'hffff))
            sdp_beats <= sdp_beats + 16'd1;
         if (accu2sc_credit_vld && (sdp_credits != 16'hffff))
            sdp_credits <= sdp_credits + 16'd1;
      end
   end

   reg [15:0] dat_wr_beats;
   always @(posedge clk) begin
      if (!reset_n)                                        dat_wr_beats <= 16'd0;
      else if (buf_dat_wr_en && (dat_wr_beats != 16'hffff)) dat_wr_beats <= dat_wr_beats + 16'd1;
   end

   reg [23:0] dat_granted, dat_released, wt_granted, wt_released;
   always @(posedge clk) begin
      if (!reset_n) begin
         dat_granted <= 24'd0; dat_released <= 24'd0;
         wt_granted  <= 24'd0; wt_released  <= 24'd0;
      end else begin
         if (cdma2sc_dat_updt)
            dat_granted  <= (dat_granted  > (24'hffffff - {12'd0, cdma2sc_dat_entries}))
                            ? 24'hffffff : dat_granted + {12'd0, cdma2sc_dat_entries};
         if (sc2cdma_dat_updt)
            dat_released <= (dat_released > (24'hffffff - {12'd0, sc2cdma_dat_entries}))
                            ? 24'hffffff : dat_released + {12'd0, sc2cdma_dat_entries};
         if (cdma2sc_wt_updt)
            wt_granted   <= (wt_granted   > (24'hffffff - {12'd0, cdma2sc_wt_entries}))
                            ? 24'hffffff : wt_granted + {12'd0, cdma2sc_wt_entries};
         if (sc2cdma_wt_updt)
            wt_released  <= (wt_released  > (24'hffffff - {12'd0, sc2cdma_wt_entries}))
                            ? 24'hffffff : wt_released + {12'd0, sc2cdma_wt_entries};
      end
   end

   wire [78:0] mem_req_pd0  = mem_req_pd_flat[78:0];
   wire [78:0] mem_req_pd2  = mem_req_pd_flat[236:158];
   wire [15:0] mem_owed0    = mem_owed_flat[15:0];
   wire [15:0] mem_owed2    = mem_owed_flat[47:32];

   reg [9:0] wait_mem_rsp0;
   reg [9:0] wait_dat_pending;
   reg [9:0] wait_wt_pending;
   reg [11:0] wait_owed0;
   reg [11:0] wait_progress;

   wire any_boundary_event =
      (|(mem_req_valid & mem_req_ready)) || (|(mem_rsp_valid & mem_rsp_ready)) ||
      buf_dat_wr_en || buf_wt_wr_en ||
      buf_dat_rd_en || buf_wt_rd_en || buf_wmb_rd_en ||
      (|sc2mac_dat_pvld) || (|sc2mac_wt_pvld) || (|mac2accu_pvld) || sdp_fire;

   wire any_work_outstanding =
      (mem_owed_flat != 64'd0) || (dat_inflight != 4'd0) ||
      (tok_cnt[0] != 4'd0) || (tok_cnt[1] != 4'd0) || sdp_valid;

   always @(posedge clk) begin
      if (!reset_n) begin
         wait_mem_rsp0    <= 10'd0;
         wait_dat_pending <= 10'd0;
         wait_wt_pending  <= 10'd0;
         wait_owed0       <= 12'd0;
         wait_progress    <= 12'd0;
      end else begin
         if (mem_rsp_valid[0] && !mem_rsp_ready[0]) begin
            if (wait_mem_rsp0 != 10'h3ff) wait_mem_rsp0 <= wait_mem_rsp0 + 10'd1;
         end else wait_mem_rsp0 <= 10'd0;

         if (sc2cdma_dat_pending_req && !cdma2sc_dat_pending_ack) begin
            if (wait_dat_pending != 10'h3ff) wait_dat_pending <= wait_dat_pending + 10'd1;
         end else wait_dat_pending <= 10'd0;

         if (sc2cdma_wt_pending_req && !cdma2sc_wt_pending_ack) begin
            if (wait_wt_pending != 10'h3ff) wait_wt_pending <= wait_wt_pending + 10'd1;
         end else wait_wt_pending <= 10'd0;

         if ((mem_owed0 != 16'd0) && !(mem_rsp_valid[0] && mem_rsp_ready[0])) begin
            if (wait_owed0 != 12'hfff) wait_owed0 <= wait_owed0 + 12'd1;
         end else wait_owed0 <= 12'd0;

         if (any_work_outstanding && !any_boundary_event) begin
            if (wait_progress != 12'hfff) wait_progress <= wait_progress + 12'd1;
         end else wait_progress <= 12'd0;
      end
   end

   wire [62:0] csb_pd [0:4];
   assign csb_pd[0] = csb_req_pd_flat[62:0];
   assign csb_pd[1] = csb_req_pd_flat[125:63];
   assign csb_pd[2] = csb_req_pd_flat[188:126];
   assign csb_pd[3] = csb_req_pd_flat[251:189];
   assign csb_pd[4] = csb_req_pd_flat[314:252];

   wire [4:0] csb_answerable;
   assign csb_answerable[0] = csb_req_pvld[0] && (!csb_pd[0][54] || csb_pd[0][55]);
   assign csb_answerable[1] = csb_req_pvld[1] && (!csb_pd[1][54] || csb_pd[1][55]);
   assign csb_answerable[2] = csb_req_pvld[2] && (!csb_pd[2][54] || csb_pd[2][55]);
   assign csb_answerable[3] = csb_req_pvld[3] && (!csb_pd[3][54] || csb_pd[3][55]);
   assign csb_answerable[4] = csb_req_pvld[4] && (!csb_pd[4][54] || csb_pd[4][55]);

   wire [4:0] csb_posted_write;
   assign csb_posted_write[0] = csb_req_pvld[0] && csb_pd[0][54] && !csb_pd[0][55];
   assign csb_posted_write[1] = csb_req_pvld[1] && csb_pd[1][54] && !csb_pd[1][55];
   assign csb_posted_write[2] = csb_req_pvld[2] && csb_pd[2][54] && !csb_pd[2][55];
   assign csb_posted_write[3] = csb_req_pvld[3] && csb_pd[3][54] && !csb_pd[3][55];
   assign csb_posted_write[4] = csb_req_pvld[4] && csb_pd[4][54] && !csb_pd[4][55];

   reg seen_dat_readback, seen_wt_readback, seen_wmb_readback;
   reg seen_mem_dat_rsp, seen_mem_wt_rsp;
   always @(posedge clk) begin
      if (!reset_n) begin
         seen_dat_readback <= 1'b0; seen_wt_readback <= 1'b0;
         seen_wmb_readback <= 1'b0;
         seen_mem_dat_rsp  <= 1'b0; seen_mem_wt_rsp  <= 1'b0;
      end else begin
         if (dat_arm[5]) seen_dat_readback <= 1'b1;
         if (wt_arm[5])  seen_wt_readback  <= 1'b1;
         if (wmb_arm[5]) seen_wmb_readback <= 1'b1;
         if (mem_rsp_valid[0] && mem_rsp_ready[0]) seen_mem_dat_rsp <= 1'b1;
         if (mem_rsp_valid[2] && mem_rsp_ready[2]) seen_mem_wt_rsp  <= 1'b1;
      end
   end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
