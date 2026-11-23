// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_1
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_1
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic cnt_en,
    input wire logic [ 2 : 0 ] o_cnt,
    input wire logic [ 3 : 0 ] cnt_ring
);

reg [ 4 : 0 ] sidx ;

always @ ( posedge clk ) begin if ( rst ) begin sidx <= 5 'd 0 ; end else if ( cnt_en ) begin sidx <= sidx + 5 'd 1 ; end else begin sidx <= 5 'd 0 ; end end

T_ORDER_SERIAL_INDEX_TRACKS_RING: assert property (@(posedge clk) disable iff (rst) cnt_en |-> (({o_cnt, $unsigned(2'(cnt_ring[1] ? 2'd1 :
                         cnt_ring[2] ? 2'd2 :
                         cnt_ring[3] ? 2'd3 : 2'd0))}) == sidx));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_1
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_5
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_5
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_pcr,
    input wire logic [ 31 : 0 ] t_pcw
);

reg pc_known ;

always @ ( posedge clk ) begin if ( rst ) begin pc_known <= 1 'b 0 ; end else if ( t_v ) begin pc_known <= 1 'b 1 ; end end

T_ORDER_PC_CHAINS_FORWARD: assert property (@(posedge clk) disable iff (rst)
    (t_v && pc_known) |-> (t_pcr == $past(t_pcw, 1, t_v))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_5
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_6
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_6
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic s_pc_en,
    input wire logic pc_bit,
    input wire logic pc_p4
);

reg [ 31 : 0 ] p4_pc , p4_sum ;

reg [ 6 : 0 ] pcpos ;

always @ ( posedge clk ) begin if ( rst ) begin p4_pc <= 32 'd 0 ; p4_sum <= 32 'd 0 ; pcpos <= 7 'd 0 ; end else begin if ( s_pc_en ) begin p4_pc <= { pc_bit , p4_pc [ 31 : 1 ] } ; p4_sum <= { pc_p4 , p4_sum [ 31 : 1 ] } ; pcpos <= ( pcpos == 7 'd 127 ) ? pcpos : pcpos + 7 'd 1 ; end else begin pcpos <= 7 'd 0 ; end end end

T_DATA_SERIAL_PC_INCREMENT_IS_PLUS_FOUR: assert property (@(posedge clk) disable iff (rst)
    $past(!rst && s_pc_en && (pcpos == 7'd31)) |-> (p4_sum == (p4_pc + 32'd4))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_6
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_8
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_8
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic ib_cyc,
    input wire logic ib_ack,
    input wire logic [ 31 : 0 ] ib_rdt,
    input wire logic [ 4 : 0 ] d_opcode,
    input wire logic [ 2 : 0 ] d_funct3,
    input wire logic d_op20,
    input wire logic d_op21,
    input wire logic d_op22,
    input wire logic d_op26,
    input wire logic d_imm30,
    input wire logic d_imm25
);

reg f_seen ;

always @ ( posedge clk ) begin if ( rst ) begin f_seen <= 1 'b 0 ; end else begin if ( ib_cyc && ib_ack ) begin f_seen <= 1 'b 1 ; end else if ( t_v ) begin f_seen <= 1 'b 0 ; end end end

T_DATA_DECODE_FIELDS_FROM_FETCHED_WORD: assert property (@(posedge clk) disable iff (rst)
    f_seen |-> ((d_opcode == $past(ib_rdt[6:2], 1, ib_cyc && ib_ack)) && (d_funct3 == $past(ib_rdt[14:12], 1, ib_cyc && ib_ack)) && ({d_imm30, d_imm25, d_op26, d_op22, d_op21, d_op20} == {$past(ib_rdt[30], 1, ib_cyc && ib_ack), $past(ib_rdt[25], 1, ib_cyc && ib_ack), $past(ib_rdt[26], 1, ib_cyc && ib_ack), $past(ib_rdt[22], 1, ib_cyc && ib_ack), $past(ib_rdt[21], 1, ib_cyc && ib_ack), $past(ib_rdt[20], 1, ib_cyc && ib_ack)}))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_8
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_9
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_9
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_maddr,
    input wire logic [ 3 : 0 ] t_rmask,
    input wire logic [ 3 : 0 ] t_wmask,
    input wire logic [ 31 : 0 ] t_mrdata,
    input wire logic [ 31 : 0 ] t_mwdata,
    input wire logic db_cyc,
    input wire logic db_ack,
    input wire logic [ 31 : 0 ] db_adr,
    input wire logic [ 31 : 0 ] db_dat,
    input wire logic [ 3 : 0 ] db_sel,
    input wire logic db_we,
    input wire logic [ 31 : 0 ] db_rdt
);

reg m_seen ;

always @ ( posedge clk ) begin if ( rst ) begin m_seen <= 1 'b 0 ; end else begin if ( db_cyc && db_ack ) begin m_seen <= 1 'b 1 ; end else if ( t_v ) begin m_seen <= 1 'b 0 ; end end end

T_DATA_RVFI_MEM_BEAT_MATCHES_DBUS: assert property (@(posedge clk) disable iff (rst)
    (t_v && m_seen) |-> ((t_maddr == $past(db_adr, 1, db_cyc && db_ack)) && (t_wmask == ($past(db_we, 1, db_cyc && db_ack) ? $past(db_sel, 1, db_cyc && db_ack) : 4'd0)) && (t_rmask == ($past(db_we, 1, db_cyc && db_ack) ? 4'd0 : $past(db_sel, 1, db_cyc && db_ack))) && ($past(db_we, 1, db_cyc && db_ack) ? (t_mwdata == $past(db_dat, 1, db_cyc && db_ack)) : (t_mrdata == $past(db_rdt, 1, db_cyc && db_ack))))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_9
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_14
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_14
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic s_pc_en,
    input wire logic pc_newb,
    input wire logic [ 31 : 0 ] ibus_adr_r
);

reg [ 31 : 0 ] p4_new ;

reg [ 6 : 0 ] pcpos ;

always @ ( posedge clk ) begin if ( rst ) begin p4_new <= 32 'd 0 ; pcpos <= 7 'd 0 ; end else begin if ( s_pc_en ) begin p4_new <= { pc_newb , p4_new [ 31 : 1 ] } ; pcpos <= ( pcpos == 7 'd 127 ) ? pcpos : pcpos + 7 'd 1 ; end else begin pcpos <= 7 'd 0 ; end end end

T_CONSERV_PC_REGISTER_HOLDS_ASSEMBLED_NEW_PC: assert property (@(posedge clk) disable iff (rst)
    $past(!rst && s_pc_en && (pcpos == 7'd31)) |-> (ibus_adr_r == p4_new)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_14
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_33
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_33
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic s_ibcyc,
    input wire logic [ 31 : 0 ] ibus_adr_r
);



T_RESET_FETCH_STARTS_AT_RESET_PC: assert property (@(posedge clk) disable iff (rst)
    (!rst && !$past(!rst)) |-> (s_ibcyc && (ibus_adr_r == 32'd0))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_33
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_34
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_34
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic cnt_en,
    input wire logic [ 2 : 0 ] o_cnt,
    input wire logic [ 3 : 0 ] cnt_ring,
    input wire logic s_idone,
    input wire logic s_jump,
    input wire logic [ 4 : 0 ] rcnt,
    input wire logic rgnt,
    input wire logic rreq_r,
    input wire logic rgate
);



T_RESET_SERIAL_ENGINE_AND_RF_PORT_IDLE: assert property (@(posedge clk) disable iff (rst)
    (!rst && !$past(!rst)) |-> ((cnt_ring == 4'd0) && (o_cnt == 3'd0) && !cnt_en && !s_idone && !s_jump && (rcnt == 5'd0) && !rgnt && !rreq_r && !rgate)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_34
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_35
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_35
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 63 : 0 ] t_order,
    input wire logic [ 31 : 0 ] t_insn,
    input wire logic t_trap,
    input wire logic t_halt,
    input wire logic t_intr,
    input wire logic ord_loop,
    input wire logic csr_newirq,
    input wire logic csr_mtie
);



T_RESET_RVFI_CHANNEL_QUIET: assert property (@(posedge clk) disable iff (rst)
    (!rst && !$past(!rst)) |-> (!t_v && (t_order == 64'd0) && (t_insn == 32'd0) && !t_trap && !t_halt && !t_intr && !ord_loop && !csr_newirq && !csr_mtie)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_35
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_39
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_39
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_halt,
    input wire logic t_intr,
    input wire logic [ 1 : 0 ] t_mode,
    input wire logic [ 1 : 0 ] t_ixl
);



T_LIFECYCLE_RETIREMENT_CHANNEL_CONSTANTS: assert property (@(posedge clk) disable iff (rst)
    $past(!rst) |-> ((t_mode == 2'b11) && (t_ixl == 2'b01) && !t_halt && !t_intr)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_39
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_40
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_40
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_insn,
    input wire logic t_trap,
    input wire logic [ 31 : 0 ] t_rs1d,
    input wire logic [ 31 : 0 ] t_rs2d,
    input wire logic [ 31 : 0 ] t_rdw
);



T_DATA_SLL_RD_MATCHES_INDEPENDENT_MODEL: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && (((t_insn[6:0]) == 7'b0110011) && ((t_insn[14:12]) == 3'b001) && ((t_insn[31:25]) == 7'b0000000))) |-> (t_rdw == (((t_insn[11:7]) != 5'd0) ? $unsigned(32'($unsigned(32'(((t_insn[19:15]) != 5'd0) ? t_rs1d : 32'd0)) << $unsigned(5'(((t_insn[24:20]) != 5'd0) ? t_rs2d[4:0] : 5'd0)))) : 32'd0)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_40
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_41
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_41
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_insn,
    input wire logic [ 4 : 0 ] t_rda
);



T_DATA_SLL_RD_ADDR_IS_INSN_FIELD: assert property (@(posedge clk) disable iff (rst) (t_v && (((t_insn[6:0]) == 7'b0110011) && ((t_insn[14:12]) == 3'b001) && ((t_insn[31:25]) == 7'b0000000))) |-> (t_rda == (t_insn[11:7])));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_41
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_42
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_42
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_insn,
    input wire logic [ 4 : 0 ] t_rs1a,
    input wire logic [ 4 : 0 ] t_rs2a
);



T_DATA_SLL_SOURCE_ADDRS_ARE_INSN_FIELDS: assert property (@(posedge clk) disable iff (rst) (t_v && (((t_insn[6:0]) == 7'b0110011) && ((t_insn[14:12]) == 3'b001) && ((t_insn[31:25]) == 7'b0000000))) |-> ((t_rs1a == (t_insn[19:15])) && (t_rs2a == (t_insn[24:20]))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_42
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_43
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_43
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_insn,
    input wire logic t_trap,
    input wire logic [ 31 : 0 ] t_rs1d,
    input wire logic [ 31 : 0 ] t_rs2d,
    input wire logic [ 31 : 0 ] t_rdw
);



T_DATA_SLL_ZERO_SHAMT_IS_A_MOVE: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && (((t_insn[6:0]) == 7'b0110011) && ((t_insn[14:12]) == 3'b001) && ((t_insn[31:25]) == 7'b0000000)) && ($unsigned(5'(((t_insn[24:20]) != 5'd0) ? t_rs2d[4:0] : 5'd0)) == 5'd0) && ((t_insn[11:7]) != 5'd0)) |-> (t_rdw == $unsigned(32'(((t_insn[19:15]) != 5'd0) ? t_rs1d : 32'd0))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_43
`endif

`ifdef BLOCK_HARD_CASE_serv_rvfi_insn_sll_44
// BEGIN BLOCK_HARD_CASE serv_rvfi_insn_sll_44
`timescale 1ns/1ps
`default_nettype none

module serv_bitserial_targets (
    input wire  clk,
    input wire  rst,
    input wire logic t_v,
    input wire logic [ 31 : 0 ] t_insn,
    input wire logic t_trap,
    input wire logic [ 31 : 0 ] t_rs2d,
    input wire logic [ 31 : 0 ] t_rdw
);



T_DATA_SLL_LOW_BITS_ARE_ZERO: assert property (@(posedge clk) disable iff (rst) (t_v && !t_trap && (((t_insn[6:0]) == 7'b0110011) && ((t_insn[14:12]) == 3'b001) && ((t_insn[31:25]) == 7'b0000000)) && ((t_insn[11:7]) != 5'd0)) |-> ((t_rdw & ~(32'hFFFFFFFF << $unsigned(5'(((t_insn[24:20]) != 5'd0) ? t_rs2d[4:0] : 5'd0)))) == 32'd0));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_44
`endif
