`default_nettype none
`include "axis_adapter.v"
`include "axis_pipeline_fifo.v"
// Restored after the includes: every verilog-axis file ends with
// `resetall, which clears the `timescale they set at their top.
`timescale 1ns / 1ps

module testbench (
    input wire       clock,
    input wire       reset,
    input wire [7:0] s_data,
    input wire       s_valid,
    input wire       s_last,
    input wire       m_ready
);
    localparam REF_DEPTH = 128;
    localparam REF_PTR_W = $clog2(REF_DEPTH);

    wire s_ready;

    wire [31:0] packed_data;
    wire [3:0]  packed_keep;
    wire        packed_valid;
    wire        packed_ready;
    wire        packed_last;

    wire [31:0] buffered_data;
    wire [3:0]  buffered_keep;
    wire        buffered_valid;
    wire        buffered_ready;
    wire        buffered_last;

    wire [7:0] out_data;
    wire       out_keep;
    wire       out_valid;
    wire       out_last;

    axis_adapter #(
        .S_DATA_WIDTH(8),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(1),
        .M_DATA_WIDTH(32),
        .M_KEEP_ENABLE(1),
        .M_KEEP_WIDTH(4),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) upsize (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(s_data),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .s_axis_tlast(s_last),
        .s_axis_tid(8'b0),
        .s_axis_tdest(8'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(packed_data),
        .m_axis_tkeep(packed_keep),
        .m_axis_tvalid(packed_valid),
        .m_axis_tready(packed_ready),
        .m_axis_tlast(packed_last),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    axis_pipeline_fifo #(
        .DATA_WIDTH(32),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(4),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .LENGTH(4)
    ) wide_pipeline (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(packed_data),
        .s_axis_tkeep(packed_keep),
        .s_axis_tvalid(packed_valid),
        .s_axis_tready(packed_ready),
        .s_axis_tlast(packed_last),
        .s_axis_tid(8'b0),
        .s_axis_tdest(8'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(buffered_data),
        .m_axis_tkeep(buffered_keep),
        .m_axis_tvalid(buffered_valid),
        .m_axis_tready(buffered_ready),
        .m_axis_tlast(buffered_last),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    axis_adapter #(
        .S_DATA_WIDTH(32),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(4),
        .M_DATA_WIDTH(8),
        .M_KEEP_ENABLE(1),
        .M_KEEP_WIDTH(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) downsize (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(buffered_data),
        .s_axis_tkeep(buffered_keep),
        .s_axis_tvalid(buffered_valid),
        .s_axis_tready(buffered_ready),
        .s_axis_tlast(buffered_last),
        .s_axis_tid(8'b0),
        .s_axis_tdest(8'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(out_data),
        .m_axis_tkeep(out_keep),
        .m_axis_tvalid(out_valid),
        .m_axis_tready(m_ready),
        .m_axis_tlast(out_last),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    wire push = s_valid && s_ready;
    wire pop = out_valid && m_ready;

    reg [7:0] data_ref [0:REF_DEPTH-1];
    reg       last_ref [0:REF_DEPTH-1];
    reg [REF_PTR_W-1:0] ref_wptr;
    reg [REF_PTR_W-1:0] ref_rptr;
    reg [REF_PTR_W:0]   ref_count;
    reg past_valid;
    reg seen_packed_word;
    reg seen_partial_frame;
    reg seen_wrap;

    initial past_valid = 1'b0;

    always @(posedge clock) begin
        past_valid <= 1'b1;
        if (reset) begin
            A_RESET_IDLE: assume (!s_valid);
            ref_wptr <= 0;
            ref_rptr <= 0;
            ref_count <= 0;
            seen_packed_word <= 0;
            seen_partial_frame <= 0;
            seen_wrap <= 0;
        end else begin
            if (past_valid && $past(!reset) &&
                    $past(s_valid && !s_ready)) begin
                A_INPUT_STICKY: assume (
                    s_valid &&
                    s_data == $past(s_data) &&
                    s_last == $past(s_last));
            end

            if (push) begin
                data_ref[ref_wptr] <= s_data;
                last_ref[ref_wptr] <= s_last;
                ref_wptr <= ref_wptr + 1'b1;
                if (ref_wptr == REF_DEPTH-1)
                    seen_wrap <= 1'b1;
            end
            if (pop)
                ref_rptr <= ref_rptr + 1'b1;
            case ({push, pop})
                2'b10: ref_count <= ref_count + 1'b1;
                2'b01: ref_count <= ref_count - 1'b1;
                default: ref_count <= ref_count;
            endcase

            if (packed_valid && packed_ready && packed_keep == 4'hf)
                seen_packed_word <= 1'b1;
            if (packed_valid && packed_ready && packed_last &&
                    packed_keep != 4'hf)
                seen_partial_frame <= 1'b1;

            T_WIDTH_ROUNDTRIP: assert (
                ref_count <= REF_DEPTH &&
                (!push || ref_count < REF_DEPTH || pop) &&
                (!out_valid ||
                    (ref_count != 0 &&
                     out_keep == 1'b1 &&
                     out_data == data_ref[ref_rptr] &&
                     out_last == last_ref[ref_rptr]))
            );

            C_PACKED_WORD: cover (seen_packed_word);
            C_PARTIAL_FRAME: cover (seen_partial_frame);
            C_BACKPRESSURED_PIPELINE: cover (
                ref_count >= 12 && out_valid && !m_ready);
            C_DEEP_DUT_BACKPRESSURE: cover (
                ref_count > REF_DEPTH/2 &&
                s_valid && !m_ready && !s_ready);
            C_REFERENCE_WRAP: cover (seen_wrap && out_valid);
        end
    end

endmodule

`default_nettype wire
