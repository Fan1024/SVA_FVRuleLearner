`timescale 1ns/1ps
`default_nettype none

module axis_width_targets (input wire clock, input wire reset,
    input logic [7:0] s_dat,
    input logic s_val,
    input logic s_rdy,
    input logic s_lst,
    input logic [31:0] pk_dat,
    input logic [3:0] pk_kep,
    input logic pk_val,
    input logic pk_rdy,
    input logic pk_lst,
    input logic [31:0] bf_dat,
    input logic [3:0] bf_kep,
    input logic bf_val,
    input logic bf_rdy,
    input logic bf_lst,
    input logic [7:0] o_dat,
    input logic o_kep,
    input logic o_val,
    input logic o_rdy,
    input logic o_lst,
    input logic [1:0] up_seg,
    input logic up_skid,
    input logic up_oval,
    input logic [3:0] up_okeep,
    input logic pp_v0,
    input logic pp_v1,
    input logic pp_v2,
    input logic pp_v3,
    input logic [5:0] pp_ofw,
    input logic [5:0] pp_ofr,
    input logic pp_oval,
    input logic dn_skid,
    input logic [3:0] dn_skeep,
    input logic dn_oval
);

    localparam integer DEPTH = 64;

    localparam [7:0] N_OUT_STALL   = 8'd8;
    localparam [7:0] N_BUF_STALL   = 8'd16;
    localparam [7:0] N_NO_MOVE     = 8'd24;
    localparam [7:0] N_INPUT_BLOCK = 8'd128;
    localparam [7:0] CTR_MAX       = 8'd255;

    wire        s_fire = s_val && s_rdy;

    wire        pk_fire = pk_val && pk_rdy;

    wire        bf_fire = bf_val && bf_rdy;

    wire        o_fire = o_val && o_rdy;

    wire [2:0] pk_n = {2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]};
    wire [2:0] bf_n = {2'd0, bf_kep[0]} + {2'd0, bf_kep[1]}
                    + {2'd0, bf_kep[2]} + {2'd0, bf_kep[3]};
    wire [2:0] up_n = {2'd0, up_okeep[0]} + {2'd0, up_okeep[1]}
                    + {2'd0, up_okeep[2]} + {2'd0, up_okeep[3]};
    wire [2:0] dn_n = {2'd0, dn_skeep[0]} + {2'd0, dn_skeep[1]}
                    + {2'd0, dn_skeep[2]} + {2'd0, dn_skeep[3]};
    wire [2:0] pp_nv = {2'd0, pp_v0} + {2'd0, pp_v1}
                     + {2'd0, pp_v2} + {2'd0, pp_v3};

    reg [7:0]  qa_dat [0:DEPTH-1];
    reg        qa_lst [0:DEPTH-1];
    reg [5:0]  qa_wr, qa_rd;
    reg [6:0]  qa_occ;

    reg [31:0] qw_dat [0:DEPTH-1];
    reg [3:0]  qw_kep [0:DEPTH-1];
    reg        qw_lst [0:DEPTH-1];
    reg [5:0]  qw_wr, qw_rd;
    reg [6:0]  qw_occ;
    reg [9:0]  qw_bytes;

    reg [7:0]  qb_dat [0:DEPTH-1];
    reg        qb_lst [0:DEPTH-1];
    reg [5:0]  qb_wr, qb_rd;
    reg [6:0]  qb_occ;

    reg [15:0] in_bytes, out_bytes;

    reg [7:0]  out_stall_ctr;
    reg [7:0]  buf_stall_ctr;
    reg [7:0]  no_move_ctr;
    reg [7:0]  in_block_ctr;
    reg        after_reset;
    reg        seen_partial;
    reg        seen_full_word;

    reg        pk_data_bad;
    reg        pk_last_bad;
    reg        pk_short;
    reg [5:0]  ai;
    integer    i;
    always @* begin
        pk_data_bad = 1'b0;
        pk_last_bad = 1'b0;
        pk_short    = 1'b0;
        if (pk_fire) begin
            if (qa_occ < {4'd0, pk_n})
                pk_short = 1'b1;
            else
                for (i = 0; i < 4; i = i + 1)
                    if (i < pk_n) begin
                        ai = qa_rd + i[5:0];
                        if (pk_dat[8*i +: 8] != qa_dat[ai])
                            pk_data_bad = 1'b1;
                        if (qa_lst[ai] !=
                                ((i == (pk_n - 3'd1)) ? pk_lst : 1'b0))
                            pk_last_bad = 1'b1;
                    end
        end
    end

    wire [3:0] up_hold = (up_oval ? {1'b0, up_n} : {2'd0, up_seg})
                       + {3'd0, up_skid};

    wire [3:0] dn_hold = (dn_skid ? {1'b0, dn_n} : 4'd0) + {3'd0, dn_oval};

    always @(posedge clock) begin
        after_reset <= reset;
        if (reset) begin
            qa_wr <= 6'd0; qa_rd <= 6'd0; qa_occ <= 7'd0;
            qw_wr <= 6'd0; qw_rd <= 6'd0; qw_occ <= 7'd0; qw_bytes <= 10'd0;
            qb_wr <= 6'd0; qb_rd <= 6'd0; qb_occ <= 7'd0;
            in_bytes <= 16'd0; out_bytes <= 16'd0;
            out_stall_ctr <= 8'd0;
            buf_stall_ctr <= 8'd0;
            no_move_ctr   <= 8'd0;
            in_block_ctr  <= 8'd0;
            seen_partial  <= 1'b0;
            seen_full_word<= 1'b0;
        end else begin

            if (s_fire) begin
                qa_dat[qa_wr] <= s_dat;
                qa_lst[qa_wr] <= s_lst;
                qa_wr <= qa_wr + 6'd1;
                if (in_bytes != 16'hffff)
                    in_bytes <= in_bytes + 16'd1;
            end
            if (pk_fire)
                qa_rd <= qa_rd + {3'd0, pk_n};
            qa_occ <= qa_occ + {6'd0, s_fire} - (pk_fire ? {4'd0, pk_n} : 7'd0);

            if (pk_fire) begin
                qw_dat[qw_wr] <= pk_dat;
                qw_kep[qw_wr] <= pk_kep;
                qw_lst[qw_wr] <= pk_lst;
                qw_wr <= qw_wr + 6'd1;
                if (pk_kep != 4'hf)
                    seen_partial <= 1'b1;
                else
                    seen_full_word <= 1'b1;
            end
            if (bf_fire)
                qw_rd <= qw_rd + 6'd1;
            qw_occ <= qw_occ + {6'd0, pk_fire} - {6'd0, bf_fire};
            qw_bytes <= qw_bytes + (pk_fire ? {7'd0, pk_n} : 10'd0)
                                 - (bf_fire ? {7'd0, bf_n} : 10'd0);

            if (bf_fire) begin
                if (bf_n > 3'd0) begin
                    qb_dat[qb_wr] <= bf_dat[7:0];
                    qb_lst[qb_wr] <= (bf_n == 3'd1) ? bf_lst : 1'b0;
                end
                if (bf_n > 3'd1) begin
                    qb_dat[qb_wr + 6'd1] <= bf_dat[15:8];
                    qb_lst[qb_wr + 6'd1] <= (bf_n == 3'd2) ? bf_lst : 1'b0;
                end
                if (bf_n > 3'd2) begin
                    qb_dat[qb_wr + 6'd2] <= bf_dat[23:16];
                    qb_lst[qb_wr + 6'd2] <= (bf_n == 3'd3) ? bf_lst : 1'b0;
                end
                if (bf_n > 3'd3) begin
                    qb_dat[qb_wr + 6'd3] <= bf_dat[31:24];
                    qb_lst[qb_wr + 6'd3] <= bf_lst;
                end
                qb_wr <= qb_wr + {3'd0, bf_n};
            end
            if (o_fire) begin
                qb_rd <= qb_rd + 6'd1;
                if (out_bytes != 16'hffff)
                    out_bytes <= out_bytes + 16'd1;
            end
            qb_occ <= qb_occ + (bf_fire ? {4'd0, bf_n} : 7'd0) - {6'd0, o_fire};

            if ((qb_occ == 7'd0) || !o_rdy || o_fire)
                out_stall_ctr <= 8'd0;
            else if (out_stall_ctr != CTR_MAX)
                out_stall_ctr <= out_stall_ctr + 8'd1;

            if ((qw_occ == 7'd0) || !bf_rdy || bf_fire)
                buf_stall_ctr <= 8'd0;
            else if (buf_stall_ctr != CTR_MAX)
                buf_stall_ctr <= buf_stall_ctr + 8'd1;

            if (((qw_occ == 7'd0) && (qb_occ == 7'd0)) || !o_rdy
                    || bf_fire || o_fire)
                no_move_ctr <= 8'd0;
            else if (no_move_ctr != CTR_MAX)
                no_move_ctr <= no_move_ctr + 8'd1;

            if (!s_val || s_rdy || !o_rdy)
                in_block_ctr <= 8'd0;
            else if (in_block_ctr != CTR_MAX)
                in_block_ctr <= in_block_ctr + 8'd1;
        end
    end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
