`default_nettype wire
`define COMMON_CELLS_ASSERTS_OFF
`include "cc_pkg.sv"
`include "cc_lzc.sv"
`include "cc_rr_arb_tree.sv"
`include "cc_spill_register_flushable.sv"
`include "cc_spill_register.sv"
`include "cc_stream_demux.sv"
`include "cc_stream_xbar.sv"
`include "cc_fifo.sv"
`include "cc_stream_fifo.sv"
`default_nettype none

module testbench (
    input  wire        clock,
    input  wire        reset,
    input  wire [31:0] in_data,
    input  wire [7:0]  in_dest,
    input  wire [3:0]  in_valid,
    input  wire [3:0]  out_ready
);
    localparam int unsigned Ports = 4;
    localparam int unsigned RefDepth = 16;

    typedef struct packed {
        logic [1:0] dest;
        logic [7:0] data;
    } in_payload_t;

    typedef struct packed {
        logic [1:0] source;
        logic [7:0] data;
    } out_payload_t;

    logic rst_n;
    assign rst_n = !reset;

    in_payload_t [Ports-1:0] source_payload;
    in_payload_t [Ports-1:0] buffered_payload;
    logic [Ports-1:0] input_ready;
    logic [Ports-1:0] buffered_valid;
    logic [Ports-1:0] buffered_ready;
    logic [Ports-1:0][2:0] input_usage;

    in_payload_t [Ports-1:0] switched_payload;
    logic [Ports-1:0][1:0] switched_source;
    logic [Ports-1:0] switched_valid;
    logic [Ports-1:0] switched_ready;

    out_payload_t [Ports-1:0] output_fifo_in;
    out_payload_t [Ports-1:0] output_fifo_out;
    logic [Ports-1:0] output_valid;
    logic [Ports-1:0][2:0] output_usage;

    for (genvar i = 0; i < Ports; i++) begin : gen_input_fifo
        always_comb begin
            source_payload[i].data = in_data[8*i +: 8];
            source_payload[i].dest = in_dest[2*i +: 2];
        end
        cc_stream_fifo #(
            .FallThrough(1'b0),
            .Depth(4),
            .data_t(in_payload_t)
        ) input_fifo (
            .clk_i(clock),
            .rst_ni(rst_n),
            .clr_i(1'b0),
            .flush_i(1'b0),
            .usage_o(input_usage[i]),
            .data_i(source_payload[i]),
            .valid_i(in_valid[i]),
            .ready_o(input_ready[i]),
            .data_o(buffered_payload[i]),
            .valid_o(buffered_valid[i]),
            .ready_i(buffered_ready[i])
        );
    end

    cc_stream_xbar #(
        .NumInp(Ports),
        .NumOut(Ports),
        .payload_t(in_payload_t),
        .OutSpillReg(1'b1),
        .ExtPrio(1'b0),
        .AxiVldRdy(1'b1),
        .LockIn(1'b1)
    ) xbar (
        .clk_i(clock),
        .rst_ni(rst_n),
        .clr_i(1'b0),
        .clr_arb_i(1'b0),
        .rr_i('0),
        .data_i(buffered_payload),
        .sel_i({
            buffered_payload[3].dest,
            buffered_payload[2].dest,
            buffered_payload[1].dest,
            buffered_payload[0].dest
        }),
        .valid_i(buffered_valid),
        .ready_o(buffered_ready),
        .data_o(switched_payload),
        .idx_o(switched_source),
        .valid_o(switched_valid),
        .ready_i(switched_ready)
    );

    for (genvar o = 0; o < Ports; o++) begin : gen_output_fifo
        always_comb begin
            output_fifo_in[o].data = switched_payload[o].data;
            output_fifo_in[o].source = switched_source[o];
        end
        cc_stream_fifo #(
            .FallThrough(1'b0),
            .Depth(4),
            .data_t(out_payload_t)
        ) output_fifo (
            .clk_i(clock),
            .rst_ni(rst_n),
            .clr_i(1'b0),
            .flush_i(1'b0),
            .usage_o(output_usage[o]),
            .data_i(output_fifo_in[o]),
            .valid_i(switched_valid[o]),
            .ready_o(switched_ready[o]),
            .data_o(output_fifo_out[o]),
            .valid_o(output_valid[o]),
            .ready_i(out_ready[o])
        );
    end

    logic [3:0] push;
    logic [3:0] pop;
    assign push = in_valid & input_ready;
    assign pop = output_valid & out_ready;

    logic [7:0] data_ref [0:Ports-1][0:Ports-1][0:RefDepth-1];
    logic [3:0] ref_wptr [0:Ports-1][0:Ports-1];
    logic [3:0] ref_rptr [0:Ports-1][0:Ports-1];
    logic [4:0] ref_count [0:Ports-1][0:Ports-1];
    logic past_valid;
    logic seen_wrap;
    logic target_ok;
    integer s;
    integer d;

    always_comb begin
        target_ok = 1'b1;
        for (s = 0; s < Ports; s = s + 1) begin
            for (d = 0; d < Ports; d = d + 1) begin
                target_ok &= ref_count[s][d] <= RefDepth;
            end
            if (push[s]) begin
                target_ok &=
                    ref_count[s][in_dest[2*s +: 2]] < RefDepth ||
                    (pop[in_dest[2*s +: 2]] &&
                     output_fifo_out[in_dest[2*s +: 2]].source == s);
            end
        end
        for (d = 0; d < Ports; d = d + 1) begin
            if (output_valid[d]) begin
                target_ok &=
                    ref_count[output_fifo_out[d].source][d] != 0 &&
                    output_fifo_out[d].data ==
                        data_ref[output_fifo_out[d].source][d]
                                [ref_rptr[output_fifo_out[d].source][d]];
            end
        end
    end

    initial past_valid = 1'b0;

    always_ff @(posedge clock) begin
        past_valid <= 1'b1;
        if (reset) begin
            A_RESET_IDLE: assume (in_valid == 0);
            seen_wrap <= 1'b0;
            for (s = 0; s < Ports; s = s + 1) begin
                for (d = 0; d < Ports; d = d + 1) begin
                    ref_wptr[s][d] <= 0;
                    ref_rptr[s][d] <= 0;
                    ref_count[s][d] <= 0;
                end
            end
        end else begin
            if (past_valid && $past(!reset)) begin
                if ($past(in_valid[0] && !input_ready[0]))
                    A_IN0_STICKY: assume (
                        in_valid[0] &&
                        in_data[7:0] == $past(in_data[7:0]) &&
                        in_dest[1:0] == $past(in_dest[1:0]));
                if ($past(in_valid[1] && !input_ready[1]))
                    A_IN1_STICKY: assume (
                        in_valid[1] &&
                        in_data[15:8] == $past(in_data[15:8]) &&
                        in_dest[3:2] == $past(in_dest[3:2]));
                if ($past(in_valid[2] && !input_ready[2]))
                    A_IN2_STICKY: assume (
                        in_valid[2] &&
                        in_data[23:16] == $past(in_data[23:16]) &&
                        in_dest[5:4] == $past(in_dest[5:4]));
                if ($past(in_valid[3] && !input_ready[3]))
                    A_IN3_STICKY: assume (
                        in_valid[3] &&
                        in_data[31:24] == $past(in_data[31:24]) &&
                        in_dest[7:6] == $past(in_dest[7:6]));
            end

            for (s = 0; s < Ports; s = s + 1) begin
                if (push[s]) begin
                    data_ref[s][in_dest[2*s +: 2]]
                            [ref_wptr[s][in_dest[2*s +: 2]]] <=
                        in_data[8*s +: 8];
                    ref_wptr[s][in_dest[2*s +: 2]] <=
                        ref_wptr[s][in_dest[2*s +: 2]] + 1'b1;
                    if (ref_wptr[s][in_dest[2*s +: 2]] == 4'hf)
                        seen_wrap <= 1'b1;
                end
            end
            for (d = 0; d < Ports; d = d + 1) begin
                if (pop[d])
                    ref_rptr[output_fifo_out[d].source][d] <=
                        ref_rptr[output_fifo_out[d].source][d] + 1'b1;
            end
            for (s = 0; s < Ports; s = s + 1) begin
                for (d = 0; d < Ports; d = d + 1) begin
                    case ({
                        push[s] && in_dest[2*s +: 2] == d,
                        pop[d] && output_fifo_out[d].source == s
                    })
                        2'b10: ref_count[s][d] <= ref_count[s][d] + 1'b1;
                        2'b01: ref_count[s][d] <= ref_count[s][d] - 1'b1;
                        default: ref_count[s][d] <= ref_count[s][d];
                    endcase
                end
            end

            T_BUFFERED_XBAR_ORDER: assert (target_ok);
            C_INPUT_BACKLOG: cover (
                input_usage[0] >= 2 && input_usage[1] >= 2 &&
                input_usage[2] >= 2 && input_usage[3] >= 2);
            C_SAME_OUTPUT_CONTENTION: cover (
                ref_count[0][0] != 0 && ref_count[1][0] != 0 &&
                ref_count[2][0] != 0 && ref_count[3][0] != 0 &&
                output_valid[0]);
            C_ALL_OUTPUTS: cover (&output_valid);
            C_REFERENCE_WRAP: cover (seen_wrap && |output_valid);
        end
    end

endmodule

`default_nettype wire
