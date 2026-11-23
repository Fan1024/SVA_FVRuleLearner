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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
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



// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE serv_rvfi_insn_sll_44
`endif
