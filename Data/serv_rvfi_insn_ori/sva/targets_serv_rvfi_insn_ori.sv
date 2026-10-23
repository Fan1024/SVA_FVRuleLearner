// ===========================================================================
// Candidate target assertions for serv_rvfi_insn_ori.
//
// SERV is a BIT-SERIAL RV32I core. A 32-bit operation is 32 consecutive
// cycles through 1-bit datapaths, so ordering, data integrity and bounded
// response all have a PER-BIT shape here that no other task in this corpus
// has. Everything below is bound into the riscv-formal `testbench` and reads
// only hierarchical names. Nothing here is an assumption, and nothing here
// touches `rvfi_order_loopback` except to read it.
//
// FIVE INDEPENDENT ORACLES. None of them restates a design register:
//
//  1. SERIAL POSITION SHADOW -- a plain 5-bit binary counter of the bit
//     currently in the datapath, advanced by `o_cnt_en` alone. SERV's own
//     position is a 3-bit counter `o_cnt[4:2]` concatenated with a 4-bit
//     RING `cnt_lsb`, a different encoding of the same number, and the
//     ordering assertions compare the two encodings.
//
//  2. SERIAL ARITHMETIC RE-ASSEMBLY -- the ALU emits one sum bit per cycle
//     through a 1-bit carry register, and serv_ctrl increments the PC the
//     same way. This oracle collects 32 cycles of operand and result bits
//     into 32-bit words of its own and asserts ONE PARALLEL 32-bit add over
//     them. 32 serial one-bit adds versus one 32-bit add is the strongest
//     independence available on this design.
//
//  3. RVFI RETIREMENT MODEL -- a shadow 32x32 register file, a retirement
//     counter and an expected-PC register, built ONLY from what the RVFI
//     channel reports at the boundary. The design holds its architectural
//     state in a 2-bit-wide 576-entry SRAM behind a serial address counter;
//     this oracle is a flat array, so the correspondence is a claim about
//     the register file rather than a copy of it.
//
//  4. BUS TRANSACTION SHADOW -- own outstanding-fetch flag, own capture of
//     the fetch address, the fetched word and the data-bus beat, own
//     fetch/retire counters.
//
//  5. SATURATING COUNTERS -- fairness, bounded response and deadlock
//     freedom written as safety properties, per CATEGORIES.md. No
//     `s_eventually` anywhere in this file.
//
// CATEGORIES A FLAT SINGLE CORE DOES NOT ADMIT, stated rather than faked:
//
//   * 7  allocator discipline -- there is no allocator. No free list, no
//        MSHR pool, no credit pool, no tag store. The register file is
//        directly addressed by the instruction's own rd/rs fields.
//   * 15 coherence -- one core, no cache, no second agent, no permission
//        state. Nothing can conflict.
//
// TWO MORE ARE ADMITTED ONLY IN A WEAK FORM, and are labelled honestly:
//
//   * 10 arbitration fairness -- there is no arbiter. What exists is the
//        fixed time-multiplex of the ONE register-file SRAM port between the
//        rd write and the CSR write, and the 4-cycle ring that advances the
//        bit counter. Both are stated as "never bypassed for more than N".
//   * 11 bounded response -- NOTHING can be claimed about either Wishbone
//        bus. `MEMIO_FAIRNESS` is not defined in ft/defines.sv, so
//        `ibus_ack`/`dbus_ack` are free `(* keep *) reg`s that may never
//        ack; a target saying a fetch completes in N cycles would be a
//        counterexample, not a target. The bounded-response targets here
//        are all on paths INTERNAL to the core, where no bus is involved.
// ===========================================================================
`default_nettype wire
`include "defines.sv"

module serv_bitserial_targets (input wire clk, input wire rst);

   // =====================================================================
   // ALIASES -- the RVFI channel at the formal top
   // =====================================================================
   wire        t_v      = testbench.rvfi_valid[0];
   wire [63:0] t_order  = testbench.rvfi_order;
   wire [31:0] t_insn   = testbench.rvfi_insn;
   wire        t_trap   = testbench.rvfi_trap[0];
   wire        t_halt   = testbench.rvfi_halt[0];
   wire        t_intr   = testbench.rvfi_intr[0];
   wire [1:0]  t_mode   = testbench.rvfi_mode;
   wire [1:0]  t_ixl    = testbench.rvfi_ixl;
   wire [4:0]  t_rs1a   = testbench.rvfi_rs1_addr;
   wire [4:0]  t_rs2a   = testbench.rvfi_rs2_addr;
   wire [31:0] t_rs1d   = testbench.rvfi_rs1_rdata;
   wire [31:0] t_rs2d   = testbench.rvfi_rs2_rdata;
   wire [4:0]  t_rda    = testbench.rvfi_rd_addr;
   wire [31:0] t_rdw    = testbench.rvfi_rd_wdata;
   wire [31:0] t_pcr    = testbench.rvfi_pc_rdata;
   wire [31:0] t_pcw    = testbench.rvfi_pc_wdata;
   wire [31:0] t_maddr  = testbench.rvfi_mem_addr;
   wire [3:0]  t_rmask  = testbench.rvfi_mem_rmask;
   wire [3:0]  t_wmask  = testbench.rvfi_mem_wmask;
   wire [31:0] t_mrdata = testbench.rvfi_mem_rdata;
   wire [31:0] t_mwdata = testbench.rvfi_mem_wdata;

   // read only: the CIll loopback guard, this package's one design_keep
   wire        ord_loop = testbench.rvfi_order_loopback;

   // =====================================================================
   // ALIASES -- the two Wishbone buses at the rvfi_wrapper
   // =====================================================================
   wire        ib_cyc = testbench.wrapper.ibus_cyc;
   wire        ib_ack = testbench.wrapper.ibus_ack;
   wire [31:0] ib_adr = testbench.wrapper.ibus_adr;
   wire [31:0] ib_rdt = testbench.wrapper.ibus_rdt;
   wire        db_cyc = testbench.wrapper.dbus_cyc;
   wire        db_ack = testbench.wrapper.dbus_ack;
   wire [31:0] db_adr = testbench.wrapper.dbus_adr;
   wire [31:0] db_dat = testbench.wrapper.dbus_dat;
   wire [3:0]  db_sel = testbench.wrapper.dbus_sel;
   wire        db_we  = testbench.wrapper.dbus_we;
   wire [31:0] db_rdt = testbench.wrapper.dbus_rdt;

   // =====================================================================
   // ALIASES -- the serial control state (serv_state)
   // =====================================================================
   wire       cnt_en    = testbench.wrapper.uut.cpu.state.o_cnt_en;
   wire       cnt_done  = testbench.wrapper.uut.cpu.state.o_cnt_done;
   wire [2:0] o_cnt     = testbench.wrapper.uut.cpu.state.o_cnt;
   wire [3:0] cnt_ring  = testbench.wrapper.uut.cpu.state.gen_cnt_w_eq_1.cnt_lsb;
   wire       s_init    = testbench.wrapper.uut.cpu.state.o_init;
   wire       s_idone   = testbench.wrapper.uut.cpu.state.init_done;
   wire       s_pc_en   = testbench.wrapper.uut.cpu.state.o_ctrl_pc_en;
   wire       s_jump    = testbench.wrapper.uut.cpu.state.o_ctrl_jump;
   wire       s_trap    = testbench.wrapper.uut.cpu.state.o_ctrl_trap;
   wire       s_ibcyc   = testbench.wrapper.uut.cpu.state.ibus_cyc;
   wire       cnt0      = testbench.wrapper.uut.cpu.state.o_cnt0;
   wire       cnt1      = testbench.wrapper.uut.cpu.state.o_cnt1;
   wire       cnt2      = testbench.wrapper.uut.cpu.state.o_cnt2;
   wire       cnt3      = testbench.wrapper.uut.cpu.state.o_cnt3;
   wire       cnt7      = testbench.wrapper.uut.cpu.state.o_cnt7;
   wire       cnt11     = testbench.wrapper.uut.cpu.state.o_cnt11;
   wire       cnt12     = testbench.wrapper.uut.cpu.state.o_cnt12;
   wire       cnt0to3   = testbench.wrapper.uut.cpu.state.o_cnt0to3;
   wire       cnt12to31 = testbench.wrapper.uut.cpu.state.o_cnt12to31;

   // =====================================================================
   // ALIASES -- register file interface, decoder, ALU, PC, RF SRAM port
   // =====================================================================
   wire       rf_rreq  = testbench.wrapper.uut.rf_rreq;
   wire       rf_wreq  = testbench.wrapper.uut.rf_wreq;
   wire       rf_ready = testbench.wrapper.uut.rf_ready;
   wire       wen0     = testbench.wrapper.uut.wen0;
   wire       wen1     = testbench.wrapper.uut.wen1;
   wire       wdata0   = testbench.wrapper.uut.wdata0;
   wire [5:0] wreg0    = testbench.wrapper.uut.wreg0;

   wire [4:0] rd_addr   = testbench.wrapper.uut.cpu.rd_addr;
   wire [4:0] rs1_addr  = testbench.wrapper.uut.cpu.rs1_addr;
   wire [4:0] rs2_addr  = testbench.wrapper.uut.cpu.rs2_addr;
   wire [3:0] immdec_en = testbench.wrapper.uut.cpu.immdec_en;
   wire       rd_op     = testbench.wrapper.uut.cpu.rd_op;
   wire       rd_en     = testbench.wrapper.uut.cpu.rd_en;
   wire       two_stage = testbench.wrapper.uut.cpu.two_stage_op;
   wire       shift_op  = testbench.wrapper.uut.cpu.shift_op;
   wire [2:0] alu_rd_sel = testbench.wrapper.uut.cpu.alu_rd_sel;
   wire       mem_misal  = testbench.wrapper.uut.cpu.mem_misalign;

   wire [4:0] d_opcode = testbench.wrapper.uut.cpu.decode.opcode;
   wire [2:0] d_funct3 = testbench.wrapper.uut.cpu.decode.funct3;
   wire       d_op20   = testbench.wrapper.uut.cpu.decode.op20;
   wire       d_op21   = testbench.wrapper.uut.cpu.decode.op21;
   wire       d_op22   = testbench.wrapper.uut.cpu.decode.op22;
   wire       d_op26   = testbench.wrapper.uut.cpu.decode.op26;
   wire       d_imm30  = testbench.wrapper.uut.cpu.decode.imm30;
   wire       d_imm25  = testbench.wrapper.uut.cpu.decode.imm25;

   wire       alu_rs1  = testbench.wrapper.uut.cpu.alu.i_rs1;
   wire       alu_addb = testbench.wrapper.uut.cpu.alu.add_b;
   wire       alu_res  = testbench.wrapper.uut.cpu.alu.result_add;
   wire       alu_sub  = testbench.wrapper.uut.cpu.alu.i_sub;

   wire        pc_bit  = testbench.wrapper.uut.cpu.ctrl.pc;
   wire        pc_p4   = testbench.wrapper.uut.cpu.ctrl.pc_plus_4;
   wire        pc_newb = testbench.wrapper.uut.cpu.ctrl.new_pc;
   wire        pc_jmp  = testbench.wrapper.uut.cpu.ctrl.i_jump;
   wire        pc_trp  = testbench.wrapper.uut.cpu.ctrl.i_trap;
   wire [31:0] ibus_adr_r = testbench.wrapper.uut.cpu.ctrl.o_ibus_adr;

   wire [4:0] rcnt    = testbench.wrapper.uut.rf_ram_if.rcnt;
   wire       wtrig0  = testbench.wrapper.uut.rf_ram_if.wtrig0;
   wire       wtrig1  = testbench.wrapper.uut.rf_ram_if.wtrig1;
   wire       rtrig0  = testbench.wrapper.uut.rf_ram_if.rtrig0;
   wire       rtrig1  = testbench.wrapper.uut.rf_ram_if.rtrig1;
   wire       rgnt    = testbench.wrapper.uut.rf_ram_if.rgnt;
   wire       rreq_r  = testbench.wrapper.uut.rf_ram_if.rreq_r;
   wire       rgate   = testbench.wrapper.uut.rf_ram_if.rgate;
   wire       ram_wen = testbench.wrapper.uut.wen;

   wire       csr_newirq = testbench.wrapper.uut.cpu.gen_csr.csr.o_new_irq;
   wire       csr_mtie   = testbench.wrapper.uut.cpu.gen_csr.csr.mie_mtie;

   // =====================================================================
   // ORACLE 1 -- SERIAL POSITION SHADOW
   //
   // `sidx` is this file's own binary bit counter: it is zero on the first
   // cycle a pass runs and counts one per `cnt_en` cycle. `didx` is the same
   // number as SERV encodes it -- the 3-bit `o_cnt` above a 4-bit ring.
   // `runpos` is the 0-based position within the CURRENT run of consecutive
   // `cnt_en` cycles, saturating so it can never wrap into a false pass.
   // =====================================================================
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

   // =====================================================================
   // ORACLE 2 -- SERIAL ARITHMETIC RE-ASSEMBLY
   //
   // 2a: the ALU adder. `add_a`/`add_b`/`add_r` collect 32 cycles of
   //     operand and sum bits, LSB first. `add_s0` is the carry the design
   //     loads at position 0 (`add_cy_r <= i_sub` whenever the count is
   //     stopped). The check fires one cycle after position 31 and only for
   //     the FIRST 32-bit window of a run, because a 64-cycle two-stage run
   //     carries the carry-out of bit 31 into the second window.
   //
   // 2b: the PC incrementer in serv_ctrl, same shape, over `i_pc_en`.
   // =====================================================================
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

   // =====================================================================
   // ORACLE 3 -- RVFI RETIREMENT MODEL
   //
   // Built only from the boundary channel: a retirement counter, the order
   // and PC of the previous retirement, and a flat 32x32 shadow register
   // file. A retirement that the core reports as trapping writes MTVAL
   // through the same RF write port under a CSR address, so the shadow does
   // not record it -- see PROVENANCE and the note in lists/targets.txt.
   // =====================================================================
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

   // =====================================================================
   // ORACLE 4 -- BUS TRANSACTION SHADOW
   // =====================================================================
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

   // =====================================================================
   // ORACLE 5 -- SERIAL rd ASSEMBLY AND ITS BIT CENSUS
   //
   // The destination register leaves the core one bit per cycle on the RF
   // write port. This oracle re-assembles the word from that port and counts
   // the bits, so "the RVFI channel reports what the register file was
   // given" and "exactly 32 bits were given" are separate claims.
   // =====================================================================
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

   // =====================================================================
   // ORACLE 6 -- SATURATING COUNTERS
   //
   // Every one of these is on a path INTERNAL to the core. Nothing here
   // counts a wait on `ibus_ack` or `dbus_ack`: those are free and may never
   // arrive, so a bound on them would be false.
   // =====================================================================
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

   // first cycle out of reset, this file's own flag rather than $past
   reg saw_run;
   always @(posedge clk) begin
      if (rst) saw_run <= 1'b0;
      else     saw_run <= 1'b1;
   end
   wire first = !rst && !saw_run;

   // =====================================================================
   // 1 -- END-TO-END ORDERING
   // The two observation points are the position of the bit in the serial
   // datapath and the retirement channel. The oracle owns both counts.
   // =====================================================================
   T_ORDER_SERIAL_INDEX_TRACKS_RING: assert property (@(posedge clk) disable iff (rst) cnt_en |-> (didx == sidx));

   T_ORDER_CNT_DONE_AT_LAST_BIT: assert property (@(posedge clk) disable iff (rst) cnt_en |-> (cnt_done == (sidx == 5'd31)));

   T_ORDER_POSITION_STROBES_DECODE_INDEX: assert property (@(posedge clk) disable iff (rst) cnt_en |-> (({cnt12, cnt11, cnt7, cnt3, cnt2, cnt1, cnt0} == {(sidx == 5'd12), (sidx == 5'd11), (sidx == 5'd7), (sidx == 5'd3), (sidx == 5'd2), (sidx == 5'd1), (sidx == 5'd0)}) && (cnt0to3 == (sidx <= 5'd3)) && (cnt12to31 == (sidx >= 5'd12))));

   T_ORDER_RUN_IS_WHOLE_WORDS: assert property (@(posedge clk) disable iff (rst) (!cnt_en && ran) |-> ((runpos == 7'd32) || (runpos == 7'd64)));

   T_ORDER_PC_CHAINS_FORWARD: assert property (@(posedge clk) disable iff (rst) (t_v && pc_known) |-> (t_pcr == exp_pc));

   // =====================================================================
   // 2 -- DATA INTEGRITY
   // =====================================================================
   T_DATA_SERIAL_ADD_EQUALS_PARALLEL_ADD: assert property (@(posedge clk) disable iff (rst) add_chk |-> (add_r == add_exp));

   T_DATA_SERIAL_PC_INCREMENT_IS_PLUS_FOUR: assert property (@(posedge clk) disable iff (rst) p4_chk |-> (p4_sum == (p4_pc + 32'd4)));

   T_DATA_RD_SERIAL_ASSEMBLY_MATCHES_RVFI: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && (t_rda != 5'd0)) |-> (t_rdw == sh_rd));

   T_DATA_RF_SOURCE_READBACK: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap) |-> ((((t_rs1a == 5'd0) || !xknown[t_rs1a]) || (t_rs1d == rs1_shadow)) && (((t_rs2a == 5'd0) || !xknown[t_rs2a]) || (t_rs2d == rs2_shadow))));

   T_DATA_RVFI_PC_IS_FETCH_ADDRESS: assert property (@(posedge clk) disable iff (rst) (t_v && f_seen) |-> ((t_pcr == f_adr) && (t_insn == f_word)));

   T_DATA_DECODE_FIELDS_FROM_FETCHED_WORD: assert property (@(posedge clk) disable iff (rst) f_seen |-> ((d_opcode == f_word[6:2]) && (d_funct3 == f_word[14:12]) && ({d_imm30, d_imm25, d_op26, d_op22, d_op21, d_op20} == {f_word[30], f_word[25], f_word[26], f_word[22], f_word[21], f_word[20]})));

   T_DATA_RVFI_MEM_BEAT_MATCHES_DBUS: assert property (@(posedge clk) disable iff (rst) (t_v && m_seen) |-> ((t_maddr == m_adr) && (t_wmask == (m_we ? m_sel : 4'd0)) && (t_rmask == (m_we ? 4'd0 : m_sel)) && (m_we ? (t_mwdata == m_wdat) : (t_mrdata == m_rdat))));

   // =====================================================================
   // 3 -- UNIQUENESS / NO DUPLICATION
   // =====================================================================
   T_UNIQ_RETIRE_ORDER_IS_RETIRE_COUNT: assert property (@(posedge clk) disable iff (rst) t_v |-> (t_order == ret_cnt));

   T_UNIQ_NO_SECOND_FETCH_BEFORE_RETIRE: assert property (@(posedge clk) disable iff (rst) (ib_cyc && ib_ack && f_seen) |-> t_v);

   T_UNIQ_ONE_BIT_POSITION_LIVE: assert property (@(posedge clk) disable iff (rst) $onehot0(cnt_ring));

   // =====================================================================
   // 4 -- NO LOSS / CONSERVATION
   // =====================================================================
   T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE: assert property (@(posedge clk) disable iff (rst) (((f_cnt - r_cnt) <= 64'd1) && (r_cnt <= f_cnt)));

   T_CONSERV_RD_WRITE_IS_EXACTLY_32_BITS: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap) |-> (wen0_cnt == ((t_rda != 5'd0) ? 8'd32 : 8'd0)));

   T_CONSERV_PC_REGISTER_HOLDS_ASSEMBLED_NEW_PC: assert property (@(posedge clk) disable iff (rst) p4_chk |-> (ibus_adr_r == p4_new));

   // =====================================================================
   // 5 -- MUTUAL EXCLUSION / ONE-HOT
   // =====================================================================
   T_MUTEX_RF_SRAM_PORT_ONE_WRITER: assert property (@(posedge clk) disable iff (rst) !(wtrig0 && wtrig1));

   T_MUTEX_NEVER_BOTH_BUS_REQUESTS: assert property (@(posedge clk) disable iff (rst) !(ib_cyc && db_cyc));

   T_MUTEX_INIT_AND_INIT_DONE_EXCLUSIVE: assert property (@(posedge clk) disable iff (rst) !(s_init && s_idone));

   // =====================================================================
   // 6 -- OCCUPANCY AND BOUNDS
   // =====================================================================
   T_BOUND_SERIAL_RUN_LE_64: assert property (@(posedge clk) disable iff (rst) (runpos <= 7'd64));

   T_BOUND_PC_RUN_LE_32: assert property (@(posedge clk) disable iff (rst) (pcpos <= 7'd32));

   // =====================================================================
   // 8 -- REQUEST-RESPONSE CORRESPONDENCE
   // =====================================================================
   T_REQRSP_RETIREMENT_HAS_A_FETCH: assert property (@(posedge clk) disable iff (rst) t_v |-> f_seen);

   T_REQRSP_MEM_MASK_IMPLIES_A_DBUS_BEAT: assert property (@(posedge clk) disable iff (rst) (t_v && ((t_rmask | t_wmask) != 4'd0)) |-> m_seen);

   T_REQRSP_DBUS_BEAT_IMPLIES_MEM_MASK: assert property (@(posedge clk) disable iff (rst) (t_v && m_seen) |-> ((t_rmask | t_wmask) != 4'd0));

   // =====================================================================
   // 9 -- PROTOCOL CONFORMANCE  (Wishbone classic, both buses)
   // =====================================================================
   T_PROTO_IBUS_CYC_HELD_UNTIL_ACK: assert property (@(posedge clk) disable iff (rst) (ib_cyc && !ib_ack) |=> ib_cyc);

   T_PROTO_IBUS_ADR_STABLE_WHILE_HELD: assert property (@(posedge clk) disable iff (rst) (ib_cyc && !ib_ack) |=> $stable(ib_adr));

   T_PROTO_DBUS_CYC_HELD_UNTIL_ACK: assert property (@(posedge clk) disable iff (rst) (db_cyc && !db_ack) |=> db_cyc);

   T_PROTO_DBUS_REQUEST_STABLE_WHILE_HELD: assert property (@(posedge clk) disable iff (rst) (db_cyc && !db_ack) |=> ($stable(db_adr) && $stable(db_we) && $stable(db_sel) && $stable(db_dat)));

   // =====================================================================
   // 10 -- ARBITRATION FAIRNESS (bounded-safety form; see the header for
   //       why a flat single core admits this only weakly)
   // =====================================================================
   T_FAIR_BIT_POSITION_ADVANCES_WITHIN_FOUR: assert property (@(posedge clk) disable iff (rst) (c_ocnt <= 8'd5));

   T_FAIR_RF_SRAM_PORT_SERVED_WITHIN_EIGHT: assert property (@(posedge clk) disable iff (rst) ((c_wtrig0 <= 8'd8) && (c_wtrig1 <= 8'd8)));

   // =====================================================================
   // 11 -- BOUNDED RESPONSE (bounded-safety form, core-internal only:
   //       nothing here waits on a bus ack, which may never come)
   // =====================================================================
   T_BOUNDRSP_RF_READ_GRANTED_WITHIN_FOUR: assert property (@(posedge clk) disable iff (rst) ((c_rreq <= 8'd4) && (c_ready <= 8'd2)));

   T_BOUNDRSP_SERIAL_PASS_COMPLETES_IN_32: assert property (@(posedge clk) disable iff (rst) (cnt_en && (runpos == 7'd31)) |-> cnt_done);

   // =====================================================================
   // 12 -- DEADLOCK FREEDOM (bounded-safety form)
   // =====================================================================
   T_DEADLOCK_NO_GLOBAL_STALL: assert property (@(posedge clk) disable iff (rst) (c_idle <= 8'd48));

   T_DEADLOCK_RETIREMENT_NOT_STARVED_OFF_BUS: assert property (@(posedge clk) disable iff (rst) (c_norety <= 16'd192));

   // =====================================================================
   // 13 -- RESET / INITIALISATION
   // =====================================================================
   T_RESET_FETCH_STARTS_AT_RESET_PC: assert property (@(posedge clk) disable iff (rst) first |-> (s_ibcyc && (ibus_adr_r == 32'd0)));

   T_RESET_SERIAL_ENGINE_AND_RF_PORT_IDLE: assert property (@(posedge clk) disable iff (rst) first |-> ((cnt_ring == 4'd0) && (o_cnt == 3'd0) && !cnt_en && !s_idone && !s_jump && (rcnt == 5'd0) && !rgnt && !rreq_r && !rgate));

   T_RESET_RVFI_CHANNEL_QUIET: assert property (@(posedge clk) disable iff (rst) first |-> (!t_v && (t_order == 64'd0) && (t_insn == 32'd0) && !t_trap && !t_halt && !t_intr && !ord_loop && !csr_newirq && !csr_mtie));

   // =====================================================================
   // 14 -- LIFECYCLE / ACCESS CONTROL
   // =====================================================================
   T_LIFECYCLE_X0_READS_ZERO: assert property (@(posedge clk) disable iff (rst) t_v |-> (((t_rs1a != 5'd0) || (t_rs1d == 32'd0)) && ((t_rs2a != 5'd0) || (t_rs2d == 32'd0))));

   T_LIFECYCLE_X0_NEVER_WRITTEN: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && (t_rda == 5'd0)) |-> (t_rdw == 32'd0));

   T_LIFECYCLE_NO_INTERRUPT_EVER_TAKEN: assert property (@(posedge clk) disable iff (rst) !csr_newirq);

   T_LIFECYCLE_RETIREMENT_CHANNEL_CONSTANTS: assert property (@(posedge clk) disable iff (rst) saw_run |-> ((t_mode == 2'b11) && (t_ixl == 2'b01) && !t_halt && !t_intr));

   // =====================================================================
   // THIS PACKAGE'S INSTRUCTION -- decoded by THIS FILE.
   //
   // The riscv-formal spec module in sva/ is the thing the protected target
   // compares against; it is deliberately NOT read here. Every field, every
   // immediate and every expected value below is this file's own arithmetic
   // over `rvfi_insn` and the two source words the channel reports.
   // =====================================================================
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

   // the riscv-formal spec's own precondition, read ONLY to cover it
   wire        spec_ok  = testbench.checker_inst.spec_valid;

   wire        x_is  = (x_opcode == 7'b0010011) && (x_funct3 == 3'b110);
   wire [31:0] x_res = x_rs1v | x_immi;

   T_DATA_ORI_RD_MATCHES_INDEPENDENT_MODEL: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && x_is) |-> (t_rdw == ((x_rdf != 5'd0) ? x_res : 32'd0)));

   T_DATA_ORI_RD_ADDR_IS_INSN_FIELD: assert property (@(posedge clk) disable iff (rst) (t_v && x_is) |-> (t_rda == x_rdf));

   T_DATA_ORI_RS1_ADDR_IS_INSN_FIELD: assert property (@(posedge clk) disable iff (rst) (t_v && x_is) |-> (t_rs1a == x_rs1f));

   T_DATA_ORI_RESULT_COVERS_RS1: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && x_is && (x_rdf != 5'd0)) |-> (((t_rdw & x_rs1v) == x_rs1v) && ((t_rdw & x_immi) == x_immi)));

   T_ORDER_ORI_PC_ADVANCES_BY_FOUR: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && x_is) |-> (t_pcw == (t_pcr + 32'd4)));

   T_REQRSP_ORI_TOUCHES_NO_MEMORY: assert property (@(posedge clk) disable iff (rst) (t_v && x_is) |-> (((t_rmask | t_wmask) == 4'd0) && !m_seen));

   C_INSN_ORI_RETIRED: cover property (@(posedge clk) disable iff (rst) (t_v && x_is));
   C_INSN_ORI_SIGN_EXTENDED_IMMEDIATE: cover property (@(posedge clk) disable iff (rst) (t_v && x_is && t_insn[31]));
   C_INSN_ORI_SPEC_VALID: cover property (@(posedge clk) disable iff (rst) spec_ok);

   // =====================================================================
   // COVERS -- at least one per category used above, so the screen can see
   // that the scenario each target constrains is reachable.
   // =====================================================================
   C_ORDER_SERIAL_PASS_MIDWAY: cover property (@(posedge clk) disable iff (rst) (cnt_en && (sidx == 5'd16)));
   C_ORDER_TWO_STAGE_RUN: cover property (@(posedge clk) disable iff (rst) (!cnt_en && ran && (runpos == 7'd64)));
   C_ORDER_SECOND_RETIREMENT: cover property (@(posedge clk) disable iff (rst) (t_v && ret_seen));

   C_DATA_SERIAL_ADD_CHECKED: cover property (@(posedge clk) disable iff (rst) add_chk);
   C_DATA_SERIAL_ADD_BOTH_OPERANDS_NONZERO: cover property (@(posedge clk) disable iff (rst) (add_chk && (add_a != 32'd0) && (add_b != 32'd0)));
   C_DATA_PC_INCREMENT_CHECKED: cover property (@(posedge clk) disable iff (rst) p4_chk);
   C_DATA_RF_READBACK_OF_KNOWN_REGISTER: cover property (@(posedge clk) disable iff (rst) (t_v && (t_rs1a != 5'd0) && xknown[t_rs1a]));
   C_DATA_MEMORY_ACCESS_RETIRED: cover property (@(posedge clk) disable iff (rst) (t_v && ((t_rmask | t_wmask) != 4'd0)));

   C_UNIQ_FOURTH_RETIREMENT: cover property (@(posedge clk) disable iff (rst) (t_v && (ret_cnt >= 64'd3)));
   C_UNIQ_RING_AT_TOP_POSITION: cover property (@(posedge clk) disable iff (rst) cnt_ring[3]);

   C_CONSERV_FETCH_OUTSTANDING: cover property (@(posedge clk) disable iff (rst) ((f_cnt - r_cnt) == 64'd1));
   C_CONSERV_FULL_WORD_WRITTEN_TO_RD: cover property (@(posedge clk) disable iff (rst) (t_v && (t_rda != 5'd0) && (wen0_cnt == 8'd32)));

   C_MUTEX_RF_SRAM_WRITE: cover property (@(posedge clk) disable iff (rst) ram_wen);
   C_MUTEX_DBUS_REQUEST_PENDING: cover property (@(posedge clk) disable iff (rst) db_cyc);
   C_MUTEX_TWO_STAGE_SECOND_STAGE: cover property (@(posedge clk) disable iff (rst) (s_idone && cnt_en));

   C_BOUND_RUN_REACHES_64: cover property (@(posedge clk) disable iff (rst) (runpos == 7'd64));
   C_BOUND_PC_RUN_REACHES_32: cover property (@(posedge clk) disable iff (rst) (pcpos == 7'd32));

   C_REQRSP_LOAD_RETIRED: cover property (@(posedge clk) disable iff (rst) (t_v && (t_rmask != 4'd0)));
   C_REQRSP_STORE_RETIRED: cover property (@(posedge clk) disable iff (rst) (t_v && (t_wmask != 4'd0)));

   C_PROTO_IBUS_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst) (ib_cyc && !ib_ack));
   C_PROTO_IBUS_ACK_TAKEN: cover property (@(posedge clk) disable iff (rst) (ib_cyc && ib_ack));
   C_PROTO_DBUS_BACKPRESSURE: cover property (@(posedge clk) disable iff (rst) (db_cyc && !db_ack));
   C_PROTO_DBUS_ACK_TAKEN: cover property (@(posedge clk) disable iff (rst) (db_cyc && db_ack));

   C_FAIR_BIT_POSITION_HELD_THREE: cover property (@(posedge clk) disable iff (rst) (c_ocnt >= 8'd3));
   C_FAIR_RF_PORT_GAP: cover property (@(posedge clk) disable iff (rst) (c_wtrig0 >= 8'd2));

   C_BOUNDRSP_READ_REQUEST_PENDING: cover property (@(posedge clk) disable iff (rst) (c_rreq >= 8'd2));
   C_BOUNDRSP_SECOND_STAGE_RUNNING: cover property (@(posedge clk) disable iff (rst) (cnt_en && (runpos >= 7'd33)));

   C_DEADLOCK_IDLE_GAP: cover property (@(posedge clk) disable iff (rst) (c_idle >= 8'd2));
   C_DEADLOCK_LONG_INSTRUCTION: cover property (@(posedge clk) disable iff (rst) (c_norety >= 16'd64));

   C_RESET_FIRST_CYCLE_OUT_OF_RESET: cover property (@(posedge clk) disable iff (rst) first);

   C_LIFECYCLE_X0_READ: cover property (@(posedge clk) disable iff (rst) (t_v && (t_rs1a == 5'd0)));
   C_LIFECYCLE_TRAPPING_RETIREMENT: cover property (@(posedge clk) disable iff (rst) (t_v && t_trap));

endmodule

bind testbench serv_bitserial_targets serv_tgt (.clk(clock), .rst(reset));
