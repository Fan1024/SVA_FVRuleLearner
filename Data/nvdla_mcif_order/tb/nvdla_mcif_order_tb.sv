`timescale 1ns/1ps
`default_nettype none

module nvdla_mcif_targets (input wire clk, input wire reset_n,
    input logic [3:0] req_valid,
    input logic [3:0] req_ready,
    input logic [315:0] req_pd,
    input logic [3:0] rsp_valid,
    input logic [3:0] rsp_ready,
    input logic [2055:0] rsp_pd,
    input logic ar_valid,
    input logic ar_ready,
    input logic [7:0] ar_id,
    input logic [3:0] ar_len,
    input logic [63:0] ar_addr,
    input logic r_valid,
    input logic r_ready,
    input logic [7:0] r_id,
    input logic [511:0] r_data,
    input logic [5:0] dead_rsp_valid,
    input logic [8:0] os_cnt,
    input logic os_sub_d,
    input logic [9:0] ig_gnt,
    input logic [9:0] ig_req,
    input logic ig_arb_ready,
    input logic [9:0] eg_gnt,
    input logic [9:0] eg_req,
    input logic [9:0] lat_wr_pvld,
    input logic [254:0] cq_free,
    input logic [8:0] cq_count,
    input logic cq_busy,
    input logic cq_push,
    input logic [7:0] cq_push_adr,
    input logic cq_pop,
    input logic [7:0] cq_pop_adr,
    input logic cq_wr_pvld,
    input logic [3:0] cq_wr_tid,
    input logic p1_pv,
    input logic p1_sv,
    input logic [3:0] p1_pid,
    input logic [3:0] p1_sid,
    input logic eg2ig,
    input logic [1:0] spt_beat,
    input logic [1:0] eg_cq_lens,
    input logic eg_cq_swizzle,
    input logic eg_cq_odd,
    input logic [1:0] eg_wen,
    input logic [9:0] ig_wrr,
    input logic [9:0] eg_wrr,
    input logic [2:0] lat_cnt [0:3],
    input logic [2:0] ro0_cnt [0:3],
    input logic [2:0] ro1_cnt [0:3],
    input logic out_pv [0:3],
    input logic out_sv [0:3],
    input logic [2:0] dead_lat_cnt [0:5],
    input logic [7:0] bpt_lat [0:3],
    input logic [12:0] bpt_cnt_req [0:3]
);

   localparam integer NC = 4;
   localparam integer QD = 8;

   localparam [9:0] N_OS_WINDOW   = 10'd16;
   localparam [9:0] N_CLIENT_HOLD = 10'd20;
   localparam [5:0] N_ARB_BYPASS  = 6'd12;
   localparam [9:0] N_DRAIN       = 10'd128;
   localparam [9:0] N_ISSUE       = 10'd128;
   localparam [9:0] N_STALL       = 10'd256;

   wire       ar_fire   = ar_valid && ar_ready;
   wire       r_fire    = r_valid  && r_ready;
   wire [3:0] req_fire  = req_valid & req_ready;
   wire [3:0] rsp_fire  = rsp_valid & rsp_ready;

   wire       ar_active = (ar_id[7:2] == 6'd0);
   wire       r_active  = (r_id[7:2]  == 6'd0);
   wire [1:0] ar_c      = ar_id[1:0];
   wire [1:0] r_c       = r_id[1:0];

   wire [3:0] ar_fire_c = { (ar_fire && ar_active && (ar_c == 2'd3)),
                            (ar_fire && ar_active && (ar_c == 2'd2)),
                            (ar_fire && ar_active && (ar_c == 2'd1)),
                            (ar_fire && ar_active && (ar_c == 2'd0)) };
   wire [3:0] r_fire_c  = { (r_fire && r_active && (r_c == 2'd3)),
                            (r_fire && r_active && (r_c == 2'd2)),
                            (r_fire && r_active && (r_c == 2'd1)),
                            (r_fire && r_active && (r_c == 2'd0)) };

   wire [255:0] cq_free_ext = {1'b0, cq_free};

   reg [55:0] q_addr [0:(4*QD)-1];
   reg [2:0]  q_wr [0:3];
   reg [2:0]  q_rd [0:3];
   reg [3:0]  q_occ [0:3];
   reg        q_ovf [0:3];
   reg [1:0]  sub [0:3];

   wire [3:0] cmd_pop = { (ar_fire_c[3] && (sub[3] == 2'd3)),
                          (ar_fire_c[2] && (sub[2] == 2'd3)),
                          (ar_fire_c[1] && (sub[1] == 2'd3)),
                          (ar_fire_c[0] && (sub[0] == 2'd3)) };

   reg [9:0] atoms_owed [0:3];
   reg [9:0] beats_owed [0:3];
   reg [9:0] rsp_atoms  [0:3];
   reg [9:0] pub_out;
   reg [2:0] eg_in_pipe;

   reg [511:0] r_xor   [0:3];
   reg [511:0] rsp_xor [0:3];

   reg [1:0] g_sub;
   reg [3:0] g_id;

   reg [5:0] ctr_ig_bypass [0:3];
   reg [5:0] ctr_eg_bypass [0:3];
   reg [9:0] ctr_drain;
   reg [9:0] ctr_issue;
   reg [9:0] ctr_stall;

   reg [3:0] rsp_stall_q;
   reg       post_reset;

   wire all_rsp_ready = &rsp_ready;
   wire any_rsp_fire  = |rsp_fire;
   wire any_beat_owed = (beats_owed[0] != 0) || (beats_owed[1] != 0)
                     || (beats_owed[2] != 0) || (beats_owed[3] != 0);
   wire any_atom_owed = (atoms_owed[0] != 0) || (atoms_owed[1] != 0)
                     || (atoms_owed[2] != 0) || (atoms_owed[3] != 0);

   wire window_open   = (pub_out < 10'd8);
   wire ig_evt        = |ig_gnt;
   wire eg_evt        = |eg_gnt;

   integer i;
   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         for (i = 0; i < NC; i = i + 1) begin
            q_wr[i]       <= 3'd0;
            q_rd[i]       <= 3'd0;
            q_occ[i]      <= 4'd0;
            q_ovf[i]      <= 1'b0;
            sub[i]        <= 2'd0;
            atoms_owed[i] <= 10'd0;
            beats_owed[i] <= 10'd0;
            rsp_atoms[i]  <= 10'd0;
            r_xor[i]      <= 512'd0;
            rsp_xor[i]    <= 512'd0;
            ctr_ig_bypass[i] <= 6'd0;
            ctr_eg_bypass[i] <= 6'd0;
         end
         pub_out     <= 10'd0;
         eg_in_pipe  <= 3'd0;
         g_sub       <= 2'd0;
         g_id        <= 4'd0;
         ctr_drain   <= 10'd0;
         ctr_issue   <= 10'd0;
         ctr_stall   <= 10'd0;
         rsp_stall_q <= 4'd0;
         post_reset  <= 1'b0;
      end else begin
         post_reset  <= 1'b1;
         rsp_stall_q <= rsp_valid & ~rsp_ready;

         pub_out    <= pub_out    + (ar_fire ? 10'd1 : 10'd0)
                                  - (r_fire  ? 10'd1 : 10'd0);
         eg_in_pipe <= eg_in_pipe + (r_fire ? 3'd1 : 3'd0)
                                  - (eg2ig  ? 3'd1 : 3'd0);

         if (ar_fire) begin
            if (g_sub == 2'd0) g_id <= ar_id[3:0];
            g_sub <= g_sub + 2'd1;
         end

         for (i = 0; i < NC; i = i + 1) begin
            if (req_fire[i]) begin
               q_addr[(i*QD) + q_wr[i]] <= req_pd[(i*79) + 8 +: 56];
               q_wr[i] <= q_wr[i] + 3'd1;
               if (q_occ[i] == QD) q_ovf[i] <= 1'b1;
            end
            if (cmd_pop[i]) q_rd[i] <= q_rd[i] + 3'd1;

            case ({req_fire[i], cmd_pop[i]})
               2'b10:   q_occ[i] <= q_occ[i] + 4'd1;
               2'b01:   q_occ[i] <= q_occ[i] - 4'd1;
               default: begin end
            endcase

            if (ar_fire_c[i]) sub[i] <= sub[i] + 2'd1;

            atoms_owed[i] <= atoms_owed[i] + (req_fire[i]  ? 10'd4 : 10'd0)
                                           - (ar_fire_c[i] ? 10'd1 : 10'd0);
            beats_owed[i] <= beats_owed[i] + (r_fire_c[i]  ? 10'd1 : 10'd0)
                                           - (rsp_fire[i]  ? 10'd1 : 10'd0);
            rsp_atoms[i]  <= rsp_atoms[i]  + (req_fire[i]  ? 10'd4 : 10'd0)
                                           - (rsp_fire[i]  ? 10'd1 : 10'd0);

            if (r_fire_c[i]) r_xor[i]   <= r_xor[i]   ^ r_data;
            if (rsp_fire[i]) rsp_xor[i] <= rsp_xor[i] ^ rsp_pd[(i*514) +: 512];

            if (!ig_evt)
               ctr_ig_bypass[i] <= ctr_ig_bypass[i];
            else if (ig_req[i] && !ig_gnt[i])
               ctr_ig_bypass[i] <= (ctr_ig_bypass[i] == 6'd63)
                                    ? ctr_ig_bypass[i] : ctr_ig_bypass[i] + 6'd1;
            else
               ctr_ig_bypass[i] <= 6'd0;

            if (!eg_evt)
               ctr_eg_bypass[i] <= ctr_eg_bypass[i];
            else if (eg_req[i] && !eg_gnt[i])
               ctr_eg_bypass[i] <= (ctr_eg_bypass[i] == 6'd63)
                                    ? ctr_eg_bypass[i] : ctr_eg_bypass[i] + 6'd1;
            else
               ctr_eg_bypass[i] <= 6'd0;
         end

         ctr_drain <= !(all_rsp_ready && any_beat_owed && !any_rsp_fire) ? 10'd0
                    : (ctr_drain == 10'd1023) ? ctr_drain : ctr_drain + 10'd1;

         ctr_issue <= !(ar_ready && any_atom_owed && !ar_fire && window_open)
                        ? 10'd0
                    : (ctr_issue == 10'd1023) ? ctr_issue : ctr_issue + 10'd1;

         ctr_stall <= !(ar_ready && all_rsp_ready && window_open
                        && (any_atom_owed || any_beat_owed)
                        && !(ar_fire || r_fire || any_rsp_fire)) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   wire [9:0] held [0:3];
   assign held[0] = {9'd0, (p1_pv && (p1_pid == 4'd0))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd0))}
                  + {7'd0, lat_cnt[0]} + {7'd0, ro0_cnt[0]}
                  + {9'd0, out_pv[0]} + {9'd0, out_sv[0]};
   assign held[1] = {9'd0, (p1_pv && (p1_pid == 4'd1))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd1))}
                  + {7'd0, lat_cnt[1]} + {7'd0, ro0_cnt[1]}
                  + {9'd0, out_pv[1]} + {9'd0, out_sv[1]};
   assign held[2] = {9'd0, (p1_pv && (p1_pid == 4'd2))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd2))}
                  + {7'd0, lat_cnt[2]} + {7'd0, ro0_cnt[2]}
                  + {9'd0, out_pv[2]} + {9'd0, out_sv[2]};
   assign held[3] = {9'd0, (p1_pv && (p1_pid == 4'd3))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd3))}
                  + {7'd0, lat_cnt[3]} + {7'd0, ro0_cnt[3]}
                  + {9'd0, out_pv[3]} + {9'd0, out_sv[3]};

   wire [63:0] expect_ar_addr [0:3];
   assign expect_ar_addr[0] = {q_addr[(0*QD) + q_rd[0]], sub[0], 6'd0};
   assign expect_ar_addr[1] = {q_addr[(1*QD) + q_rd[1]], sub[1], 6'd0};
   assign expect_ar_addr[2] = {q_addr[(2*QD) + q_rd[2]], sub[2], 6'd0};
   assign expect_ar_addr[3] = {q_addr[(3*QD) + q_rd[3]], sub[3], 6'd0};

   wire ar_checkable = ar_fire && ar_active
                    && !q_ovf[ar_c] && (q_occ[ar_c] != 4'd0);
   wire [63:0] ar_expect = expect_ar_addr[ar_c];

   wire clients_drained = (beats_owed[0] == 0) && (beats_owed[1] == 0)
                       && (beats_owed[2] == 0) && (beats_owed[3] == 0);
   wire xor_matches = (r_xor[0] == rsp_xor[0]) && (r_xor[1] == rsp_xor[1])
                   && (r_xor[2] == rsp_xor[2]) && (r_xor[3] == rsp_xor[3]);

   reg [8:0] cq_free_pop;
   integer f;
   always @* begin
      cq_free_pop = 9'd0;
      for (f = 0; f < 255; f = f + 1)
         if (cq_free[f]) cq_free_pop = cq_free_pop + 9'd1;
   end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
