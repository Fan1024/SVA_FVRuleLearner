`default_nettype wire
`include "priority_encoder.v"
`include "arbiter.v"
`include "axis_fifo.v"
`include "axis_arb_mux.v"
// Restored after the includes: every verilog-axis file ends with
// `resetall, which clears the `timescale they set at their top.
`timescale 1ns / 1ps
`default_nettype none

module testbench (
    input wire        clock,
    input wire        reset,
    input wire [31:0] in_data,
    input wire [3:0]  in_valid,
    input wire        out_ready
);
    localparam integer Sources = 4;
    localparam integer RefDepth = 64;

    wire [3:0] input_ready;
    wire [31:0] input_fifo_data;
    wire [3:0] input_fifo_valid;
    wire [3:0] input_fifo_ready;
    wire [3:0] input_fifo_last;
    wire [3:0] input_last;
    wire [3:0] push;
    reg  [1:0] frame_pos [0:Sources-1];
    wire [3:0] input_depth [0:Sources-1];

    genvar source;
    generate
        for (source = 0; source < Sources; source = source + 1) begin : G_INPUT_FIFO
            assign input_last[source] = frame_pos[source] == 2'd3;
            axis_fifo #(
                .DEPTH(8),
                .DATA_WIDTH(8),
                .KEEP_ENABLE(0),
                .LAST_ENABLE(1),
                .ID_ENABLE(1),
                .ID_WIDTH(1),
                .DEST_ENABLE(0),
                .DEST_WIDTH(1),
                .USER_ENABLE(0),
                .USER_WIDTH(1),
                .RAM_PIPELINE(1),
                .OUTPUT_FIFO_ENABLE(1),
                .FRAME_FIFO(0),
                .PAUSE_ENABLE(0)
            ) input_fifo (
                .clk(clock),
                .rst(reset),
                .s_axis_tdata(in_data[8*source +: 8]),
                .s_axis_tkeep(1'b1),
                .s_axis_tvalid(in_valid[source]),
                .s_axis_tready(input_ready[source]),
                .s_axis_tlast(input_last[source]),
                .s_axis_tid(1'b0),
                .s_axis_tdest(1'b0),
                .s_axis_tuser(1'b0),
                .m_axis_tdata(input_fifo_data[8*source +: 8]),
                .m_axis_tkeep(),
                .m_axis_tvalid(input_fifo_valid[source]),
                .m_axis_tready(input_fifo_ready[source]),
                .m_axis_tlast(input_fifo_last[source]),
                .m_axis_tid(),
                .m_axis_tdest(),
                .m_axis_tuser(),
                .pause_req(1'b0),
                .pause_ack(),
                .status_depth(input_depth[source]),
                .status_depth_commit(),
                .status_overflow(),
                .status_bad_frame(),
                .status_good_frame()
            );
        end
    endgenerate

    assign push = in_valid & input_ready;

    wire [7:0] mux_data;
    wire       mux_valid;
    wire       mux_ready;
    wire       mux_last;
    wire [2:0] mux_id;

    axis_arb_mux #(
        .S_COUNT(Sources),
        .DATA_WIDTH(8),
        .KEEP_ENABLE(0),
        .LAST_ENABLE(1),
        .ID_ENABLE(1),
        .S_ID_WIDTH(1),
        .M_ID_WIDTH(3),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .UPDATE_TID(1),
        .ARB_TYPE_ROUND_ROBIN(1),
        .ARB_LSB_HIGH_PRIORITY(1)
    ) frame_mux (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(input_fifo_data),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(input_fifo_valid),
        .s_axis_tready(input_fifo_ready),
        .s_axis_tlast(input_fifo_last),
        .s_axis_tid(4'b0000),
        .s_axis_tdest(4'b0000),
        .s_axis_tuser(4'b0000),
        .m_axis_tdata(mux_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(mux_valid),
        .m_axis_tready(mux_ready),
        .m_axis_tlast(mux_last),
        .m_axis_tid(mux_id),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    wire [7:0] output_data;
    wire       output_valid;
    wire       output_last;
    wire [2:0] output_id;
    wire [4:0] output_depth;

    axis_fifo #(
        .DEPTH(16),
        .DATA_WIDTH(8),
        .KEEP_ENABLE(0),
        .LAST_ENABLE(1),
        .ID_ENABLE(1),
        .ID_WIDTH(3),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .RAM_PIPELINE(1),
        .OUTPUT_FIFO_ENABLE(1),
        .FRAME_FIFO(0),
        .PAUSE_ENABLE(0)
    ) output_fifo (
        .clk(clock),
        .rst(reset),
        .s_axis_tdata(mux_data),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(mux_valid),
        .s_axis_tready(mux_ready),
        .s_axis_tlast(mux_last),
        .s_axis_tid(mux_id),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(output_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(output_valid),
        .m_axis_tready(out_ready),
        .m_axis_tlast(output_last),
        .m_axis_tid(output_id),
        .m_axis_tdest(),
        .m_axis_tuser(),
        .pause_req(1'b0),
        .pause_ack(),
        .status_depth(output_depth),
        .status_depth_commit(),
        .status_overflow(),
        .status_bad_frame(),
        .status_good_frame()
    );

    wire       pop = output_valid && out_ready;
    wire [1:0] output_source = output_id[2:1];

    reg [7:0] ref_data [0:Sources-1][0:RefDepth-1];
    reg       ref_last [0:Sources-1][0:RefDepth-1];
    reg [5:0] ref_wptr [0:Sources-1];
    reg [5:0] ref_rptr [0:Sources-1];
    reg [6:0] ref_count [0:Sources-1];

    reg       output_frame_active;
    reg [1:0] output_frame_source;
    reg [3:0] seen_sources;
    reg       seen_wrap;
    reg       past_valid;
    reg       target_ok;
    integer check_source;
    integer update_source;

    always @* begin
        target_ok = 1'b1;
        for (check_source = 0; check_source < Sources;
             check_source = check_source + 1) begin
            target_ok = target_ok && ref_count[check_source] <= RefDepth;
            if (push[check_source]) begin
                target_ok = target_ok &&
                    (ref_count[check_source] < RefDepth ||
                     (pop && output_source == check_source[1:0]));
            end
        end

        if (output_valid) begin
            target_ok = target_ok &&
                output_id[0] == 1'b0 &&
                ref_count[output_source] != 0 &&
                output_data == ref_data[output_source][ref_rptr[output_source]] &&
                output_last == ref_last[output_source][ref_rptr[output_source]];
            if (output_frame_active)
                target_ok = target_ok && output_source == output_frame_source;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            A_RESET_IDLE: assume (in_valid == 4'b0000);
            past_valid <= 1'b0;
            output_frame_active <= 1'b0;
            output_frame_source <= 2'b00;
            seen_sources <= 4'b0000;
            seen_wrap <= 1'b0;
            for (update_source = 0; update_source < Sources;
                 update_source = update_source + 1) begin
                frame_pos[update_source] <= 2'b00;
                ref_wptr[update_source] <= 6'b000000;
                ref_rptr[update_source] <= 6'b000000;
                ref_count[update_source] <= 7'b0000000;
            end
        end else begin
            past_valid <= 1'b1;
            if (past_valid && $past(!reset)) begin
                if ($past(in_valid[0] && !input_ready[0]))
                    A_IN0_STICKY: assume (
                        in_valid[0] && in_data[7:0] == $past(in_data[7:0]));
                if ($past(in_valid[1] && !input_ready[1]))
                    A_IN1_STICKY: assume (
                        in_valid[1] && in_data[15:8] == $past(in_data[15:8]));
                if ($past(in_valid[2] && !input_ready[2]))
                    A_IN2_STICKY: assume (
                        in_valid[2] && in_data[23:16] == $past(in_data[23:16]));
                if ($past(in_valid[3] && !input_ready[3]))
                    A_IN3_STICKY: assume (
                        in_valid[3] && in_data[31:24] == $past(in_data[31:24]));
            end

            for (update_source = 0; update_source < Sources;
                 update_source = update_source + 1) begin
                if (push[update_source]) begin
                    ref_data[update_source][ref_wptr[update_source]] <=
                        in_data[8*update_source +: 8];
                    ref_last[update_source][ref_wptr[update_source]] <=
                        input_last[update_source];
                    ref_wptr[update_source] <= ref_wptr[update_source] + 1'b1;
                    frame_pos[update_source] <= frame_pos[update_source] + 1'b1;
                    if (ref_wptr[update_source] == 6'h3f)
                        seen_wrap <= 1'b1;
                end

                case ({push[update_source],
                       pop && output_source == update_source[1:0]})
                    2'b10: ref_count[update_source] <=
                        ref_count[update_source] + 1'b1;
                    2'b01: ref_count[update_source] <=
                        ref_count[update_source] - 1'b1;
                    default: ref_count[update_source] <=
                        ref_count[update_source];
                endcase
            end

            if (pop) begin
                ref_rptr[output_source] <= ref_rptr[output_source] + 1'b1;
                seen_sources[output_source] <= 1'b1;
                if (!output_frame_active) begin
                    output_frame_source <= output_source;
                    output_frame_active <= !output_last;
                end else if (output_last) begin
                    output_frame_active <= 1'b0;
                end
            end

            T_ARB_MUX_FRAME_ORDER: assert (target_ok);
            C_INPUT_BACKLOG: cover (
                input_depth[0] >= 2 && input_depth[1] >= 2 &&
                input_depth[2] >= 2 && input_depth[3] >= 2);
            C_FOUR_WAY_CONTENTION: cover (
                ref_count[0] >= 4 && ref_count[1] >= 4 &&
                ref_count[2] >= 4 && ref_count[3] >= 4 &&
                output_valid);
            C_OUTPUT_BACKLOG: cover (output_depth >= 4);
            C_ALL_SOURCES_OUTPUT: cover (&seen_sources);
            C_REFERENCE_WRAP: cover (seen_wrap && output_valid);
        end
    end

endmodule

`default_nettype wire
