`default_nettype none

module ordered_tlul_device #(
    parameter int unsigned DeviceId = 0
) (
    input  wire logic                clock,
    input  wire logic                reset_n,
    input  wire tlul_pkg::tl_h2d_t   tl_i,
    output tlul_pkg::tl_d2h_t   tl_o
);
    localparam int unsigned Depth = 4;

    logic [top_pkg::TL_AIW-1:0] source_mem [0:Depth-1];
    logic [top_pkg::TL_SZW-1:0] size_mem [0:Depth-1];
    logic [top_pkg::TL_DW-1:0] data_mem [0:Depth-1];
    logic [1:0] write_pointer;
    logic [1:0] read_pointer;
    logic [2:0] count;

    logic request_accept;
    logic response_accept;

    always_comb begin
        tl_o = '0;
        tl_o.a_ready = count < Depth;
        tl_o.d_valid = count != 0;
        tl_o.d_opcode = tlul_pkg::AccessAckData;
        tl_o.d_param = '0;
        tl_o.d_size = size_mem[read_pointer];
        tl_o.d_source = source_mem[read_pointer];
        tl_o.d_sink = '0;
        tl_o.d_data = data_mem[read_pointer];
        tl_o.d_user = '0;
        tl_o.d_error = 1'b0;
    end

    assign request_accept = tl_i.a_valid && tl_o.a_ready;
    assign response_accept = tl_o.d_valid && tl_i.d_ready;

    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            write_pointer <= '0;
            read_pointer <= '0;
            count <= '0;
        end else begin
            if (request_accept) begin
                source_mem[write_pointer] <= tl_i.a_source;
                size_mem[write_pointer] <= tl_i.a_size;
                data_mem[write_pointer] <=
                    tl_i.a_data ^ tl_i.a_address ^ DeviceId;
                write_pointer <= write_pointer + 1'b1;
            end
            if (response_accept)
                read_pointer <= read_pointer + 1'b1;

            case ({request_accept, response_accept})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

module testbench (
    input wire logic                         clock,
    input wire logic                         reset,
    input wire logic                         request_valid,
    input wire logic [1:0]                   request_device,
    input wire logic [top_pkg::TL_AIW-1:0]  request_source,
    input wire logic [top_pkg::TL_AW-1:0]   request_address,
    input wire logic [top_pkg::TL_DW-1:0]   request_data,
    input wire logic                         response_ready
);
    localparam int unsigned Devices = 4;
    localparam int unsigned RefDepth = 64;

    tlul_pkg::tl_h2d_t host_to_socket;
    tlul_pkg::tl_d2h_t socket_to_host;
    tlul_pkg::tl_h2d_t socket_to_device [Devices];
    tlul_pkg::tl_d2h_t device_to_socket [Devices];

    always_comb begin
        host_to_socket = '0;
        host_to_socket.a_valid = request_valid;
        host_to_socket.a_opcode = tlul_pkg::Get;
        host_to_socket.a_param = '0;
        host_to_socket.a_size = top_pkg::TL_SZW'(2);
        host_to_socket.a_source = request_source;
        host_to_socket.a_address = request_address;
        host_to_socket.a_mask = '1;
        host_to_socket.a_data = request_data;
        host_to_socket.a_user = '0;
        host_to_socket.a_user.instr_type = prim_mubi_pkg::MuBi4False;
        host_to_socket.d_ready = response_ready;
    end

    tlul_socket_1n #(
        .N(Devices),
        .HReqPass(1'b1),
        .HRspPass(1'b1),
        .DReqPass(4'b1111),
        .DRspPass(4'b1111),
        .HReqDepth(4),
        .HRspDepth(4),
        .DReqDepth({Devices{4'd4}}),
        .DRspDepth({Devices{4'd4}}),
        .ExplicitErrs(1'b0)
    ) dut (
        .clk_i(clock),
        .rst_ni(!reset),
        .tl_h_i(host_to_socket),
        .tl_h_o(socket_to_host),
        .tl_d_o(socket_to_device),
        .tl_d_i(device_to_socket),
        .dev_select_i(request_device)
    );

    genvar device;
    generate
        for (device = 0; device < Devices; device = device + 1) begin : G_DEVICE
            ordered_tlul_device #(
                .DeviceId(device)
            ) responder (
                .clock(clock),
                .reset_n(!reset),
                .tl_i(socket_to_device[device]),
                .tl_o(device_to_socket[device])
            );
        end
    endgenerate

    logic [top_pkg::TL_AIW-1:0] ref_source [0:RefDepth-1];
    logic [top_pkg::TL_DW-1:0] ref_data [0:RefDepth-1];
    logic [5:0] ref_write_pointer;
    logic [5:0] ref_read_pointer;
    logic [6:0] ref_count;

    logic [3:0] seen_devices;
    logic seen_hold;
    logic seen_wrap;
    logic past_valid;
    logic target_ok;

    wire host_accept =
        host_to_socket.a_valid && socket_to_host.a_ready;
    wire host_response =
        socket_to_host.d_valid && host_to_socket.d_ready;

    always_comb begin
        target_ok = ref_count <= RefDepth;
        if (host_accept)
            target_ok = target_ok && ref_count < RefDepth;
        if (socket_to_host.d_valid) begin
            target_ok = target_ok &&
                ref_count != 0 &&
                socket_to_host.d_opcode == tlul_pkg::AccessAckData &&
                socket_to_host.d_source == ref_source[ref_read_pointer] &&
                socket_to_host.d_data == ref_data[ref_read_pointer] &&
                !socket_to_host.d_error;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            A_RESET_IDLE: assume (!request_valid);
            ref_write_pointer <= '0;
            ref_read_pointer <= '0;
            ref_count <= '0;
            seen_devices <= '0;
            seen_hold <= 1'b0;
            seen_wrap <= 1'b0;
            past_valid <= 1'b0;
        end else begin
            past_valid <= 1'b1;

            if (past_valid && $past(!reset) &&
                $past(request_valid && !socket_to_host.a_ready)) begin
                A_REQUEST_STICKY: assume (
                    request_valid &&
                    request_device == $past(request_device) &&
                    request_source == $past(request_source) &&
                    request_address == $past(request_address) &&
                    request_data == $past(request_data));
            end

            if (host_accept) begin
                ref_source[ref_write_pointer] <= request_source;
                ref_data[ref_write_pointer] <=
                    request_data ^ request_address ^ request_device;
                ref_write_pointer <= ref_write_pointer + 1'b1;
                seen_devices[request_device] <= 1'b1;
                if (ref_write_pointer == 6'h3f)
                    seen_wrap <= 1'b1;
            end

            if (host_response)
                ref_read_pointer <= ref_read_pointer + 1'b1;

            case ({host_accept, host_response})
                2'b10: ref_count <= ref_count + 1'b1;
                2'b01: ref_count <= ref_count - 1'b1;
                default: ref_count <= ref_count;
            endcase

            if (dut.hold_all_requests)
                seen_hold <= 1'b1;

            T_TLUL_SOCKET_RESPONSE_ORDER: assert (target_ok);
            C_ALL_DEVICES: cover (&seen_devices);
            C_HOST_BACKLOG: cover (ref_count >= 8);
            C_DEVICE_SWITCH_HOLD: cover (
                seen_hold && dut.num_req_outstanding >= 2);
            C_RESPONSE_BACKPRESSURE: cover (
                socket_to_host.d_valid && !response_ready);
            C_REFERENCE_WRAP: cover (seen_wrap && socket_to_host.d_valid);
        end
    end

endmodule

`default_nettype wire
