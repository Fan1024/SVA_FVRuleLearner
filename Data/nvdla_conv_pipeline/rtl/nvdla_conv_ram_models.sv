// ===========================================================================
// Functional formal replacements for the nine generated NVDLA SRAM wrappers
// the convolution datapath instantiates.
//
// The public nvdlav1 wrappers under `vmod/rams/synth` wrap one or more
// foundry macros (RAMPDP_256X144_GL_M2_D2 and friends) in DFT, MBIST, JTAG,
// retention and power plumbing.  Those macro models are simulation-only --
// they carry `#1` delays, X clobber logic and `initial` blocks -- and neither
// the macros nor their `_logic` wrappers are useful to a formal tool.  What
// the datapath actually depends on is the interface behaviour, which is the
// same for all nine: one synchronous 1R1W memory.
//
//   posedge clk:  if (we) mem[wa] <= di;
//                 if (re) dout   <= mem[ra];
//
// Nonblocking updates give read-before-write on a same-cycle same-address
// collision.  That is a choice, not a fact about the foundry cell: the real
// dual-port macro treats a same-address read/write in one cycle as contention,
// which is why fifogen passes FORCE_CONTENTION_ASSERTION_RESET_ACTIVE down as
// the wrapper's one parameter.  Every property in this package that reads back
// what was written is guarded by a quiet window that excludes the collision
// case, so the choice is not load-bearing -- see PROVENANCE.md.
//
// `ore` on the `rwsp` (pipelined-output) wrappers is DFT-only: in
// `nv_ram_rwsp_*_logic.v` it appears in exactly one expression, the JTAG
// `captureDR_r0` term.  The CDMA fifogen FIFOs that instantiate these leave it
// undriven.  It is accepted and ignored here for the same reason.
//
// `pwrbus_ram_pd` is the power bus; the task fixes it to functional mode.
// ===========================================================================

`define NVDLA_CONV_RAM_RWS(NAME, AW, DW)                                      \
module NAME (                                                                 \
   input  wire            clk,                                                \
   input  wire [AW-1:0]   ra,                                                 \
   input  wire            re,                                                 \
   output reg  [DW-1:0]   dout,                                               \
   input  wire [AW-1:0]   wa,                                                 \
   input  wire            we,                                                 \
   input  wire [DW-1:0]   di,                                                 \
   input  wire [31:0]     pwrbus_ram_pd                                       \
);                                                                            \
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;                  \
   reg [DW-1:0] mem [0:(1<<AW)-1];                                            \
   always @(posedge clk) begin                                                \
      if (we) mem[wa] <= di;                                                  \
      if (re) dout    <= mem[ra];                                             \
   end                                                                        \
   wire _unused = &{1'b0, pwrbus_ram_pd,                                      \
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};                 \
endmodule

`define NVDLA_CONV_RAM_RWSP(NAME, AW, DW)                                     \
module NAME (                                                                 \
   input  wire            clk,                                                \
   input  wire [AW-1:0]   ra,                                                 \
   input  wire            re,                                                 \
   input  wire            ore,                                                \
   output reg  [DW-1:0]   dout,                                               \
   input  wire [AW-1:0]   wa,                                                 \
   input  wire            we,                                                 \
   input  wire [DW-1:0]   di,                                                 \
   input  wire [31:0]     pwrbus_ram_pd                                       \
);                                                                            \
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;                  \
   reg [DW-1:0] mem [0:(1<<AW)-1];                                            \
   always @(posedge clk) begin                                                \
      if (we) mem[wa] <= di;                                                  \
      if (re) dout    <= mem[ra];                                             \
   end                                                                        \
   wire _unused = &{1'b0, ore, pwrbus_ram_pd,                                 \
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};                 \
endmodule

// CBUF: 16 banks x 2 columns of 256 x 512b = 512 KiB of convolution buffer.
`NVDLA_CONV_RAM_RWS(nv_ram_rws_256x512, 8, 512)

// CDMA shared buffer (16 instances) and the CDMA WG fifo.
`NVDLA_CONV_RAM_RWS(nv_ram_rws_16x256, 4, 256)
`NVDLA_CONV_RAM_RWS(nv_ram_rws_64x10,  6, 10)

// CACC assembly and delivery buffers.
`NVDLA_CONV_RAM_RWS(nv_ram_rws_32x512, 5, 512)
`NVDLA_CONV_RAM_RWS(nv_ram_rws_32x544, 5, 544)
`NVDLA_CONV_RAM_RWS(nv_ram_rws_32x768, 5, 768)

// CDMA fifogen FIFOs (DC / WT / IMG command queues).
`NVDLA_CONV_RAM_RWSP(nv_ram_rwsp_128x6,  7, 6)
`NVDLA_CONV_RAM_RWSP(nv_ram_rwsp_128x11, 7, 11)
`NVDLA_CONV_RAM_RWSP(nv_ram_rwsp_32x32,  5, 32)
