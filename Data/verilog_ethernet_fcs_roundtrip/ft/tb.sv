`default_nettype none
`include "lfsr.v"
`include "axis_eth_fcs_insert.v"
`include "axis_eth_fcs_check.v"
// Restored after the includes: every verilog-ethernet file ends with
// `resetall, which clears the `timescale they set at their top.
`timescale 1ns / 1ps

module testbench (
    input wire       clock,
    input wire       reset,
    input wire [7:0] s_data,
    input wire       s_valid,
    input wire       s_last,
    input wire       s_user,
    input wire       m_ready
);
    wire       s_ready;
    wire [7:0] fcs_data;
    wire       fcs_valid;
    wire       fcs_ready;
    wire       fcs_last;
    wire       fcs_user;
    wire [7:0] m_data;
    wire       m_valid;
    wire       m_last;
    wire       m_user;
    wire       insert_busy;
    wire       check_busy;
    wire       error_bad_fcs;

    axis_eth_fcs_insert #(
        .ENABLE_PADDING(0),
        .MIN_FRAME_LENGTH(64)
    ) insert_dut (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(s_data),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .s_axis_tlast(s_last),
        .s_axis_tuser(s_user),
        .m_axis_tdata(fcs_data),
        .m_axis_tvalid(fcs_valid),
        .m_axis_tready(fcs_ready),
        .m_axis_tlast(fcs_last),
        .m_axis_tuser(fcs_user),
        .busy(insert_busy)
    );

    axis_eth_fcs_check check_dut (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(fcs_data),
        .s_axis_tvalid(fcs_valid),
        .s_axis_tready(fcs_ready),
        .s_axis_tlast(fcs_last),
        .s_axis_tuser(fcs_user),
        .m_axis_tdata(m_data),
        .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready),
        .m_axis_tlast(m_last),
        .m_axis_tuser(m_user),
        .busy(check_busy),
        .error_bad_fcs(error_bad_fcs)
    );

    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;

    reg [7:0] ref_data [0:63];
    reg       ref_last [0:63];
    reg [5:0] wr_ptr;
    reg [5:0] rd_ptr;
    reg [6:0] ref_count;
    reg [4:0] frame_len;
    reg [2:0] completed_frames;
    reg       saw_ref_wrap;

    reg       past_valid;
    reg [7:0] prev_data;
    reg       prev_valid;
    reg       prev_ready;
    reg       prev_last;
    reg       prev_user;

    integer i;
    always @(posedge clock) begin
        if (reset) begin
            A_RESET_IDLE: assume (!s_valid);
            wr_ptr <= 0;
            rd_ptr <= 0;
            ref_count <= 0;
            frame_len <= 0;
            completed_frames <= 0;
            saw_ref_wrap <= 0;
            past_valid <= 0;
            prev_data <= 0;
            prev_valid <= 0;
            prev_ready <= 0;
            prev_last <= 0;
            prev_user <= 0;
            for (i = 0; i < 64; i = i + 1) begin
                ref_data[i] <= 0;
                ref_last[i] <= 0;
            end
        end else begin
            A_INPUT_GOOD: assume (!s_valid || !s_user);
            if (past_valid && prev_valid && !prev_ready)
                A_INPUT_STICKY: assume (
                    s_valid &&
                    s_data == prev_data &&
                    s_last == prev_last &&
                    s_user == prev_user);
            if (s_valid && frame_len == 15)
                A_FRAME_AT_MOST_16_BYTES: assume (s_last);

            T_FCS_ROUNDTRIP: assert (
                !error_bad_fcs &&
                ref_count <= 64 &&
                !(push && !pop && ref_count == 64) &&
                (!m_valid ||
                 (ref_count != 0 &&
                  m_data == ref_data[rd_ptr] &&
                  m_last == ref_last[rd_ptr] &&
                  !m_user)));

            C_FCS_EMITTED: cover (
                fcs_valid && fcs_ready &&
                insert_dut.state_reg == 2'd3);
            C_OUTPUT_BACKPRESSURE: cover (
                m_valid && !m_ready && ref_count >= 4);
            C_TWO_FRAMES: cover (
                completed_frames >= 2 && m_valid && m_last);
            C_REFERENCE_WRAP: cover (
                saw_ref_wrap && m_valid && ref_count != 0);

            if (push) begin
                ref_data[wr_ptr] <= s_data;
                ref_last[wr_ptr] <= s_last;
                wr_ptr <= wr_ptr + 1'b1;
                if (wr_ptr == 6'd63)
                    saw_ref_wrap <= 1'b1;
                if (s_last)
                    frame_len <= 0;
                else
                    frame_len <= frame_len + 1'b1;
            end

            if (pop) begin
                rd_ptr <= rd_ptr + 1'b1;
                if (m_last && completed_frames != 7)
                    completed_frames <= completed_frames + 1'b1;
            end

            case ({push, pop})
                2'b10: ref_count <= ref_count + 1'b1;
                2'b01: ref_count <= ref_count - 1'b1;
                default: ref_count <= ref_count;
            endcase

            past_valid <= 1'b1;
            prev_data <= s_data;
            prev_valid <= s_valid;
            prev_ready <= s_ready;
            prev_last <= s_last;
            prev_user <= s_user;
        end
    end

endmodule

`default_nettype wire
