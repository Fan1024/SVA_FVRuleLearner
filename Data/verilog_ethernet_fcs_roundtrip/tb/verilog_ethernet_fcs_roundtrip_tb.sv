`timescale 1ns/1ps
`default_nettype none

module eth_fcs_targets (input wire clock, input wire reset,
    input logic [7:0] s_dat,
    input logic s_val,
    input logic s_rdy,
    input logic s_lst,
    input logic s_usr,
    input logic [7:0] mid_dat,
    input logic mid_val,
    input logic mid_rdy,
    input logic mid_lst,
    input logic mid_usr,
    input logic [7:0] o_dat,
    input logic o_val,
    input logic o_rdy,
    input logic o_lst,
    input logic o_usr,
    input logic bad_fcs,
    input logic [1:0] ins_state,
    input logic [15:0] ins_fptr,
    input logic [31:0] ins_crc,
    input logic ins_oval,
    input logic ins_tval,
    input logic ins_busy,
    input logic [1:0] chk_state,
    input logic [31:0] chk_crc,
    input logic [7:0] chk_d0,
    input logic [7:0] chk_d1,
    input logic [7:0] chk_d2,
    input logic [7:0] chk_d3,
    input logic chk_v0,
    input logic chk_v1,
    input logic chk_v2,
    input logic chk_v3,
    input logic chk_oval,
    input logic chk_tval
);

    localparam integer DEPTH  = 64;
    localparam integer FRAMES = 8;

    localparam [1:0] INS_IDLE    = 2'd0;
    localparam [1:0] INS_PAYLOAD = 2'd1;
    localparam [1:0] INS_PAD     = 2'd2;
    localparam [1:0] INS_FCS     = 2'd3;

    localparam [7:0] N_MID_STALL   = 8'd8;
    localparam [7:0] N_OUT_STALL   = 8'd12;
    localparam [7:0] N_NO_MOVE     = 8'd16;
    localparam [7:0] N_INPUT_BLOCK = 8'd24;
    localparam [7:0] CTR_MAX       = 8'd255;

    function automatic [31:0] crc32_next(input [31:0] c, input [7:0] d);
        reg [31:0] x;
        integer    b;
        begin
            x = c ^ {24'd0, d};
            for (b = 0; b < 8; b = b + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_next = x;
        end
    endfunction

    wire       s_fire = s_val && s_rdy;

    wire       mid_fire = mid_val && mid_rdy;

    wire       o_fire = o_val && o_rdy;

    reg [7:0]  qa_dat [0:DEPTH-1];
    reg        qa_lst [0:DEPTH-1];
    reg [5:0]  qa_wr, qa_rd;
    reg [6:0]  qa_occ;

    reg [7:0]  qb_dat [0:DEPTH-1];
    reg        qb_lst [0:DEPTH-1];
    reg [5:0]  qb_wr, qb_rd;
    reg [6:0]  qb_occ;

    reg [31:0] fr_crc [0:FRAMES-1];
    reg [2:0]  fr_wr, fr_rd;
    reg [3:0]  fr_occ;

    reg [31:0] in_crc;
    reg [4:0]  in_len;

    reg        mid_fcs;
    reg [1:0]  mid_idx;
    reg [7:0]  mid_h0, mid_h1, mid_h2, mid_h3;
    reg [2:0]  mid_hist;

    reg [15:0] in_bytes, out_bytes, mid_bytes, rel_bytes;
    reg [7:0]  mid_frames, out_frames;

    reg [7:0]  mid_stall_ctr;
    reg [7:0]  out_stall_ctr;
    reg [7:0]  no_move_ctr;
    reg [7:0]  in_block_ctr;
    reg        after_reset;
    reg        seen_two_frames;

    wire       mid_payload = mid_fire && !mid_fcs;
    wire       mid_fcs_beat = mid_fire && mid_fcs;
    wire [4:0] fcs_shift = {mid_idx, 3'd0};
    wire [7:0] fcs_expect = ~fr_crc[fr_rd][fcs_shift +: 8];

    always @(posedge clock) begin
        after_reset <= reset;
        if (reset) begin
            qa_wr <= 6'd0; qa_rd <= 6'd0; qa_occ <= 7'd0;
            qb_wr <= 6'd0; qb_rd <= 6'd0; qb_occ <= 7'd0;
            fr_wr <= 3'd0; fr_rd <= 3'd0; fr_occ <= 4'd0;
            in_crc <= 32'hFFFFFFFF;
            in_len <= 5'd0;
            mid_fcs <= 1'b0;
            mid_idx <= 2'd0;
            mid_hist <= 3'd0;
            mid_h0 <= 8'd0; mid_h1 <= 8'd0; mid_h2 <= 8'd0; mid_h3 <= 8'd0;
            in_bytes <= 16'd0; out_bytes <= 16'd0;
            mid_bytes <= 16'd0; rel_bytes <= 16'd0;
            mid_frames <= 8'd0; out_frames <= 8'd0;
            mid_stall_ctr <= 8'd0;
            out_stall_ctr <= 8'd0;
            no_move_ctr   <= 8'd0;
            in_block_ctr  <= 8'd0;
            seen_two_frames <= 1'b0;
        end else begin

            if (s_fire) begin
                qa_dat[qa_wr] <= s_dat;
                qa_lst[qa_wr] <= s_lst;
                qa_wr <= qa_wr + 6'd1;
                if (in_bytes != 16'hffff)
                    in_bytes <= in_bytes + 16'd1;
                if (s_lst) begin
                    fr_crc[fr_wr] <= crc32_next(in_crc, s_dat);
                    fr_wr  <= fr_wr + 3'd1;
                    in_crc <= 32'hFFFFFFFF;
                    in_len <= 5'd0;
                end else begin
                    in_crc <= crc32_next(in_crc, s_dat);
                    in_len <= in_len + 5'd1;
                end
            end
            fr_occ <= fr_occ + {3'd0, (s_fire && s_lst)}
                             - {3'd0, (mid_fcs_beat && (mid_idx == 2'd3))};

            if (mid_fire) begin
                mid_h0 <= mid_dat;
                mid_h1 <= mid_h0;
                mid_h2 <= mid_h1;
                mid_h3 <= mid_h2;
                if (mid_hist != 3'd4)
                    mid_hist <= mid_hist + 3'd1;
                if (mid_bytes != 16'hffff)
                    mid_bytes <= mid_bytes + 16'd1;
                if (!mid_fcs) begin
                    qa_rd <= qa_rd + 6'd1;
                    qb_dat[qb_wr] <= mid_dat;
                    qb_lst[qb_wr] <= qa_lst[qa_rd];
                    qb_wr <= qb_wr + 6'd1;
                    if (rel_bytes != 16'hffff)
                        rel_bytes <= rel_bytes + 16'd1;
                    if (qa_lst[qa_rd]) begin
                        mid_fcs <= 1'b1;
                        mid_idx <= 2'd0;
                    end
                end else if (mid_idx == 2'd3) begin
                    mid_fcs <= 1'b0;
                    mid_idx <= 2'd0;
                    fr_rd   <= fr_rd + 3'd1;
                    mid_frames <= mid_frames + 8'd1;
                    if (mid_frames != 8'd0)
                        seen_two_frames <= 1'b1;
                end else begin
                    mid_idx <= mid_idx + 2'd1;
                end
            end
            qa_occ <= qa_occ + {6'd0, s_fire} - {6'd0, mid_payload};
            qb_occ <= qb_occ + {6'd0, mid_payload} - {6'd0, o_fire};

            if (o_fire) begin
                qb_rd <= qb_rd + 6'd1;
                if (out_bytes != 16'hffff)
                    out_bytes <= out_bytes + 16'd1;
                if (o_lst)
                    out_frames <= out_frames + 8'd1;
            end

            if ((qa_occ == 7'd0) || !mid_rdy || mid_fire)
                mid_stall_ctr <= 8'd0;
            else if (mid_stall_ctr != CTR_MAX)
                mid_stall_ctr <= mid_stall_ctr + 8'd1;

            if ((mid_frames == out_frames) || !o_rdy || o_fire)
                out_stall_ctr <= 8'd0;
            else if (out_stall_ctr != CTR_MAX)
                out_stall_ctr <= out_stall_ctr + 8'd1;

            if (!((qa_occ != 7'd0) || (mid_frames != out_frames))
                    || !o_rdy || !mid_rdy || mid_fire || o_fire || s_fire)
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
