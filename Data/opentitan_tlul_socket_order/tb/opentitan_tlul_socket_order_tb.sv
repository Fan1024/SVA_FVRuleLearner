`timescale 1ns/1ps
`default_nettype none

module tlul_socket_targets (input wire clk, input wire rst,
    input logic h_av,
    input logic h_ar,
    input logic [7:0] h_asrc,
    input logic [31:0] h_aaddr,
    input logic [31:0] h_adata,
    input logic [1:0] h_adev,
    input logic h_dv,
    input logic h_dr,
    input logic [7:0] h_dsrc,
    input logic [31:0] h_ddata,
    input logic [1:0] h_dsize,
    input logic [2:0] h_dop,
    input logic h_derr,
    input logic h_rdy_in,
    input logic [8:0] nout,
    input logic [1:0] dsel_o,
    input logic hold,
    input logic [2:0] hq,
    input logic [2:0] hp,
    input logic [3:0] d_av,
    input logic [3:0] d_ar,
    input logic [3:0] d_dv,
    input logic [3:0] d_dr,
    input logic [7:0] d_asrc [0:3],
    input logic [31:0] d_aaddr [0:3],
    input logic [31:0] d_adata [0:3],
    input logic [7:0] d_dsrc [0:3],
    input logic [31:0] d_ddata [0:3],
    input logic [2:0] d_cnt [0:3],
    input logic [2:0] dq_req [0:3],
    input logic [2:0] dq_rsp [0:3],
    input logic [6:0] dut_ref_count
);

  localparam int unsigned RD = 32;

  wire [3:0]   d_av, d_ar, d_dv, d_dr;

  genvar gi;
  generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : g_dev

    end
  endgenerate

  wire       ev_hpush = h_av && h_ar;
  wire       ev_hpop  = h_dv && h_dr;
  wire [3:0] ev_dpush = d_av & d_ar;
  wire [3:0] ev_dpop  = d_dv & d_dr;
  wire       ev_dpush_any = |ev_dpush;
  wire       ev_dpop_any  = |ev_dpop;

  wire [1:0] fdev = ev_dpush[1] ? 2'd1 : ev_dpush[2] ? 2'd2 :
                    ev_dpush[3] ? 2'd3 : 2'd0;
  wire [1:0] gdev = ev_dpop[1]  ? 2'd1 : ev_dpop[2]  ? 2'd2 :
                    ev_dpop[3]  ? 2'd3 : 2'd0;

  reg [7:0]  q_src [0:RD-1];
  reg [31:0] q_dat [0:RD-1];
  reg [1:0]  q_dev [0:RD-1];
  reg [4:0]  w_ptr, f_ptr, g_ptr, r_ptr;

  reg [5:0] n_all;
  reg [5:0] n_wf;
  reg [5:0] n_fg;
  reg [5:0] n_gr;

  reg [3:0] dcnt [0:3];

  reg [6:0] w_hreq;
  reg [6:0] w_hrsp;
  reg [6:0] w_prog;
  reg [6:0] w_dev;
  reg [6:0] w_hold;

  reg rst_q;
  wire first = rst_q && !rst;

  wire        f_live = (n_wf == 6'd0) && ev_hpush;
  wire [7:0]  f_src  = f_live ? h_asrc : q_src[f_ptr];
  wire [31:0] f_dat  = f_live ? (h_adata ^ h_aaddr ^ {30'd0, h_adev})
                              : q_dat[f_ptr];
  wire [1:0]  f_dev  = f_live ? h_adev : q_dev[f_ptr];

  integer k;

  always @(posedge clk) begin
    rst_q <= rst;
    if (rst) begin
      w_ptr <= 5'd0; f_ptr <= 5'd0; g_ptr <= 5'd0; r_ptr <= 5'd0;
      n_all <= 6'd0; n_wf <= 6'd0; n_fg <= 6'd0; n_gr <= 6'd0;
      w_hreq <= 7'd0; w_hrsp <= 7'd0; w_prog <= 7'd0;
      w_dev <= 7'd0; w_hold <= 7'd0;
      for (k = 0; k < 4; k = k + 1) dcnt[k] <= 4'd0;
    end else begin
      if (ev_hpush) begin
        q_src[w_ptr] <= h_asrc;
        q_dat[w_ptr] <= h_adata ^ h_aaddr ^ {30'd0, h_adev};
        q_dev[w_ptr] <= h_adev;
        w_ptr <= w_ptr + 5'd1;
      end
      if (ev_dpush_any) f_ptr <= f_ptr + 5'd1;
      if (ev_dpop_any)  g_ptr <= g_ptr + 5'd1;
      if (ev_hpop)      r_ptr <= r_ptr + 5'd1;

      case ({ev_hpush, ev_hpop})
        2'b10: n_all <= n_all + 6'd1;
        2'b01: n_all <= n_all - 6'd1;
        default: n_all <= n_all;
      endcase
      case ({ev_hpush, ev_dpush_any})
        2'b10: n_wf <= n_wf + 6'd1;
        2'b01: n_wf <= n_wf - 6'd1;
        default: n_wf <= n_wf;
      endcase
      case ({ev_dpush_any, ev_dpop_any})
        2'b10: n_fg <= n_fg + 6'd1;
        2'b01: n_fg <= n_fg - 6'd1;
        default: n_fg <= n_fg;
      endcase
      case ({ev_dpop_any, ev_hpop})
        2'b10: n_gr <= n_gr + 6'd1;
        2'b01: n_gr <= n_gr - 6'd1;
        default: n_gr <= n_gr;
      endcase

      for (k = 0; k < 4; k = k + 1) begin
        case ({ev_dpush[k], ev_dpop[k]})
          2'b10: dcnt[k] <= dcnt[k] + 4'd1;
          2'b01: dcnt[k] <= dcnt[k] - 4'd1;
          default: dcnt[k] <= dcnt[k];
        endcase
      end

      if (!h_rdy_in || !h_av || h_ar) w_hreq <= 7'd0;
      else if (w_hreq != 7'h7f)       w_hreq <= w_hreq + 7'd1;

      if (!h_rdy_in || n_all == 6'd0 || ev_hpop) w_hrsp <= 7'd0;
      else if (w_hrsp != 7'h7f)                  w_hrsp <= w_hrsp + 7'd1;

      if (!h_rdy_in || (n_all == 6'd0 && !h_av) || ev_hpush || ev_hpop ||
          ev_dpush_any || ev_dpop_any)  w_prog <= 7'd0;
      else if (w_prog != 7'h7f)         w_prog <= w_prog + 7'd1;

      if (!h_rdy_in || n_fg == 6'd0 || ev_dpop_any) w_dev <= 7'd0;
      else if (w_dev != 7'h7f)                      w_dev <= w_dev + 7'd1;

      if (!h_rdy_in || !hold)     w_hold <= 7'd0;
      else if (w_hold != 7'h7f)   w_hold <= w_hold + 7'd1;
    end
  end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
