`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (input wire clk, input wire rst,
    input logic t_v,
    input logic [63:0] t_order,
    input logic [31:0] t_insn,
    input logic t_trap,
    input logic t_halt,
    input logic t_intr,
    input logic [1:0] t_mode,
    input logic [1:0] t_ixl,
    input logic [4:0] t_rs1a,
    input logic [4:0] t_rs2a,
    input logic [31:0] t_rs1d,
    input logic [31:0] t_rs2d,
    input logic [4:0] t_rda,
    input logic [31:0] t_rdw,
    input logic [31:0] t_pcr,
    input logic [31:0] t_pcw,
    input logic [31:0] t_maddr,
    input logic [3:0] t_rmask,
    input logic [3:0] t_wmask,
    input logic [31:0] t_mrdata,
    input logic [31:0] t_mwdata,
    input logic ord_loop,
    input logic ib_cyc,
    input logic ib_ack,
    input logic [31:0] ib_adr,
    input logic [31:0] ib_rdt,
    input logic db_cyc,
    input logic db_ack,
    input logic [31:0] db_adr,
    input logic [31:0] db_dat,
    input logic [3:0] db_sel,
    input logic db_we,
    input logic [31:0] db_rdt,
    input logic cnt_en,
    input logic cnt_done,
    input logic [2:0] o_cnt,
    input logic [3:0] cnt_ring,
    input logic s_init,
    input logic s_idone,
    input logic s_pc_en,
    input logic s_jump,
    input logic s_trap,
    input logic s_ibcyc,
    input logic cnt0,
    input logic cnt1,
    input logic cnt2,
    input logic cnt3,
    input logic cnt7,
    input logic cnt11,
    input logic cnt12,
    input logic cnt0to3,
    input logic cnt12to31,
    input logic rf_rreq,
    input logic rf_wreq,
    input logic rf_ready,
    input logic wen0,
    input logic wen1,
    input logic wdata0,
    input logic [5:0] wreg0,
    input logic [4:0] rd_addr,
    input logic [4:0] rs1_addr,
    input logic [4:0] rs2_addr,
    input logic [3:0] immdec_en,
    input logic rd_op,
    input logic rd_en,
    input logic two_stage,
    input logic shift_op,
    input logic [2:0] alu_rd_sel,
    input logic mem_misal,
    input logic [4:0] d_opcode,
    input logic [2:0] d_funct3,
    input logic d_op20,
    input logic d_op21,
    input logic d_op22,
    input logic d_op26,
    input logic d_imm30,
    input logic d_imm25,
    input logic alu_rs1,
    input logic alu_addb,
    input logic alu_res,
    input logic alu_sub,
    input logic pc_bit,
    input logic pc_p4,
    input logic pc_newb,
    input logic pc_jmp,
    input logic pc_trp,
    input logic [31:0] ibus_adr_r,
    input logic [4:0] rcnt,
    input logic wtrig0,
    input logic wtrig1,
    input logic rtrig0,
    input logic rtrig1,
    input logic rgnt,
    input logic rreq_r,
    input logic rgate,
    input logic ram_wen,
    input logic csr_newirq,
    input logic csr_mtie,
    input logic spec_ok
);

   reg [4:0] sidx;
   reg [6:0] runpos;
   reg       ran;

   always @(posedge clk) begin
      if (rst) begin
         sidx   <= 5'd0;
         runpos <= 7'd0;
         ran    <= 1'b0;
      end else if (cnt_en) begin
         sidx   <= sidx + 5'd1;
         runpos <= (runpos == 7'd127) ? runpos : runpos + 7'd1;
         ran    <= 1'b1;
      end else begin
         sidx   <= 5'd0;
         runpos <= 7'd0;
         ran    <= 1'b0;
      end
   end

   wire [1:0] ring_pos = cnt_ring[1] ? 2'd1 :
                         cnt_ring[2] ? 2'd2 :
                         cnt_ring[3] ? 2'd3 : 2'd0;
   wire [4:0] didx = {o_cnt, ring_pos};

   reg [31:0] add_a, add_b, add_r;
   reg        add_s0;
   reg        add_chk;

   always @(posedge clk) begin
      if (rst) begin
         add_a <= 32'd0; add_b <= 32'd0; add_r <= 32'd0;
         add_s0 <= 1'b0; add_chk <= 1'b0;
      end else begin
         add_chk <= cnt_en && (runpos == 7'd31);
         if (cnt_en) begin
            add_a <= {alu_rs1,  add_a[31:1]};
            add_b <= {alu_addb, add_b[31:1]};
            add_r <= {alu_res,  add_r[31:1]};
            if (runpos == 7'd0) add_s0 <= alu_sub;
         end
      end
   end

   wire [31:0] add_exp = add_a + add_b + {31'd0, add_s0};

   reg [31:0] p4_pc, p4_sum, p4_new;
   reg [6:0]  pcpos;
   reg        p4_chk, p4_jmp0, p4_trp0;

   always @(posedge clk) begin
      if (rst) begin
         p4_pc <= 32'd0; p4_sum <= 32'd0; p4_new <= 32'd0;
         pcpos <= 7'd0; p4_chk <= 1'b0; p4_jmp0 <= 1'b0; p4_trp0 <= 1'b0;
      end else begin
         p4_chk <= s_pc_en && (pcpos == 7'd31);
         if (s_pc_en) begin
            p4_pc  <= {pc_bit,  p4_pc[31:1]};
            p4_sum <= {pc_p4,   p4_sum[31:1]};
            p4_new <= {pc_newb, p4_new[31:1]};
            pcpos  <= (pcpos == 7'd127) ? pcpos : pcpos + 7'd1;
            if (pcpos == 7'd0) begin
               p4_jmp0 <= pc_jmp;
               p4_trp0 <= pc_trp;
            end
         end else begin
            pcpos <= 7'd0;
         end
      end
   end

   reg [63:0] ret_cnt;
   reg [63:0] last_order;
   reg [31:0] exp_pc;
   reg        pc_known;
   reg        ret_seen;
   reg [31:0] xreg [0:31];
   reg [31:0] xknown;
   integer    i;

   wire [31:0] rs1_shadow = xreg[t_rs1a];
   wire [31:0] rs2_shadow = xreg[t_rs2a];

   always @(posedge clk) begin
      if (rst) begin
         ret_cnt <= 64'd0; last_order <= 64'd0; exp_pc <= 32'd0;
         pc_known <= 1'b0; ret_seen <= 1'b0; xknown <= 32'd0;
         for (i = 0; i < 32; i = i + 1) xreg[i] <= 32'd0;
      end else if (t_v) begin
         ret_cnt    <= ret_cnt + 64'd1;
         last_order <= t_order;
         exp_pc     <= t_pcw;
         pc_known   <= 1'b1;
         ret_seen   <= 1'b1;
         if (!t_trap && (t_rda != 5'd0)) begin
            xreg[t_rda]   <= t_rdw;
            xknown[t_rda] <= 1'b1;
         end
      end
   end

   reg [31:0] f_adr, f_word;
   reg        f_seen;
   reg [63:0] f_cnt, r_cnt;
   reg [31:0] m_adr, m_wdat, m_rdat;
   reg [3:0]  m_sel;
   reg        m_we, m_seen;

   always @(posedge clk) begin
      if (rst) begin
         f_adr <= 32'd0; f_word <= 32'd0; f_seen <= 1'b0;
         f_cnt <= 64'd0; r_cnt <= 64'd0;
         m_adr <= 32'd0; m_wdat <= 32'd0; m_rdat <= 32'd0;
         m_sel <= 4'd0; m_we <= 1'b0; m_seen <= 1'b0;
      end else begin
         if (ib_cyc && ib_ack) begin
            f_adr  <= ib_adr;
            f_word <= ib_rdt;
            f_seen <= 1'b1;
            f_cnt  <= f_cnt + 64'd1;
         end else if (t_v) begin
            f_seen <= 1'b0;
         end

         if (db_cyc && db_ack) begin
            m_adr  <= db_adr;
            m_wdat <= db_dat;
            m_rdat <= db_rdt;
            m_sel  <= db_sel;
            m_we   <= db_we;
            m_seen <= 1'b1;
         end else if (t_v) begin
            m_seen <= 1'b0;
         end

         if (t_v) r_cnt <= r_cnt + 64'd1;
      end
   end

   reg [31:0] sh_rd;
   reg [7:0]  wen0_cnt;

   always @(posedge clk) begin
      if (rst) begin
         sh_rd <= 32'd0; wen0_cnt <= 8'd0;
      end else begin
         if (wen0) sh_rd <= {wdata0, sh_rd[31:1]};
         if (t_v)
           wen0_cnt <= wen0 ? 8'd1 : 8'd0;
         else if (wen0)
           wen0_cnt <= (wen0_cnt == 8'hFF) ? wen0_cnt : wen0_cnt + 8'd1;
      end
   end

   reg [7:0]  c_rreq, c_ready, c_idle, c_ocnt, c_wtrig0, c_wtrig1;
   reg [15:0] c_norety;
   reg        p_rreq, p_ready;
   reg [2:0]  o_cnt_q;

   wire idle_now = !cnt_en && !ib_cyc && !db_cyc;

   always @(posedge clk) begin
      if (rst) begin
         c_rreq <= 8'd0; c_ready <= 8'd0; c_idle <= 8'd0; c_ocnt <= 8'd0;
         c_wtrig0 <= 8'd0; c_wtrig1 <= 8'd0; c_norety <= 16'd0;
         p_rreq <= 1'b0; p_ready <= 1'b0; o_cnt_q <= 3'd0;
      end else begin
         o_cnt_q <= o_cnt;

         if (rf_rreq)      begin p_rreq <= 1'b1; c_rreq <= 8'd0; end
         else if (cnt_en)  begin p_rreq <= 1'b0; c_rreq <= 8'd0; end
         else if (p_rreq)  c_rreq <= (c_rreq == 8'hFF) ? c_rreq : c_rreq + 8'd1;

         if (rf_ready)     begin p_ready <= 1'b1; c_ready <= 8'd0; end
         else if (cnt_en)  begin p_ready <= 1'b0; c_ready <= 8'd0; end
         else if (p_ready) c_ready <= (c_ready == 8'hFF) ? c_ready : c_ready + 8'd1;

         if (idle_now) c_idle <= (c_idle == 8'hFF) ? c_idle : c_idle + 8'd1;
         else          c_idle <= 8'd0;

         if (cnt_en && (o_cnt == o_cnt_q))
           c_ocnt <= (c_ocnt == 8'hFF) ? c_ocnt : c_ocnt + 8'd1;
         else
           c_ocnt <= 8'd0;

         if (wtrig0) c_wtrig0 <= 8'd0;
         else        c_wtrig0 <= (c_wtrig0 == 8'hFF) ? c_wtrig0 : c_wtrig0 + 8'd1;

         if (wtrig1) c_wtrig1 <= 8'd0;
         else        c_wtrig1 <= (c_wtrig1 == 8'hFF) ? c_wtrig1 : c_wtrig1 + 8'd1;

         if (t_v)                     c_norety <= 16'd0;
         else if (!ib_cyc && !db_cyc) c_norety <= (c_norety == 16'hFFFF) ? c_norety : c_norety + 16'd1;
      end
   end

   reg saw_run;
   always @(posedge clk) begin
      if (rst) saw_run <= 1'b0;
      else     saw_run <= 1'b1;
   end
   wire first = !rst && !saw_run;

   wire [6:0]  x_opcode = t_insn[6:0];
   wire [2:0]  x_funct3 = t_insn[14:12];
   wire [6:0]  x_funct7 = t_insn[31:25];
   wire [4:0]  x_rs1f   = t_insn[19:15];
   wire [4:0]  x_rs2f   = t_insn[24:20];
   wire [4:0]  x_rdf    = t_insn[11:7];
   wire [31:0] x_rs1v   = (x_rs1f != 5'd0) ? t_rs1d : 32'd0;
   wire [31:0] x_rs2v   = (x_rs2f != 5'd0) ? t_rs2d : 32'd0;
   wire [31:0] x_immi   = {{20{t_insn[31]}}, t_insn[31:20]};
   wire [31:0] x_imms   = {{20{t_insn[31]}}, t_insn[31:25], t_insn[11:7]};
   wire [31:0] x_immb   = {{19{t_insn[31]}}, t_insn[31], t_insn[7], t_insn[30:25], t_insn[11:8], 1'b0};
   wire [31:0] x_immj   = {{11{t_insn[31]}}, t_insn[31], t_insn[19:12], t_insn[20], t_insn[30:21], 1'b0};

   wire        x_is   = (x_opcode == 7'b1100011) && (x_funct3 == 3'b101);
   wire        x_cond = ($signed(x_rs1v) >= $signed(x_rs2v));
   wire [31:0] x_next = x_cond ? (t_pcr + x_immb) : (t_pcr + 32'd4);

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
