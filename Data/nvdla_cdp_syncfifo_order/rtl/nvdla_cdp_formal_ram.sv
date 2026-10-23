// Functional replacements for the three generated NVDLA SRAM wrappers used
// by NV_NVDLA_CDP_DP_syncfifo.  The public wrappers add power, DFT, and
// foundry-cell plumbing around synchronous 1R1W arrays.  In functional mode,
// `re` captures the array output and `ore` captures either that value or the
// FIFO's empty-write bypass value.

module nvdla_cdp_formal_rwsthp #(
   parameter integer DEPTH = 80,
   parameter integer WIDTH = 15,
   parameter integer AWIDTH = 7
) (
   input  wire                 clk,
   input  wire [AWIDTH-1:0]    ra,
   input  wire                 re,
   input  wire                 ore,
   output reg  [WIDTH-1:0]     dout,
   input  wire [AWIDTH-1:0]    wa,
   input  wire                 we,
   input  wire [WIDTH-1:0]     di,
   input  wire                 byp_sel,
   input  wire [WIDTH-1:0]     dbyp
);
   reg [WIDTH-1:0] mem [0:DEPTH-1];
   reg [WIDTH-1:0] read_data;
   reg             write_through_valid;
   reg [WIDTH-1:0] write_through_data;
   wire            write_through = re && we && ra == wa;

   always @(posedge clk) begin
      if (we)
         mem[wa] <= di;
      if (re)
         read_data <= mem[ra];
      write_through_valid <=
         write_through || (write_through_valid && !re);
      if (write_through)
         write_through_data <= di;
      if (ore)
         dout <= byp_sel ? dbyp :
                 (write_through_valid ? write_through_data : read_data);
   end
endmodule

module nv_ram_rwsthp_80x15 (
   input wire clk, input wire [6:0] ra, input wire re, input wire ore,
   output wire [14:0] dout, input wire [6:0] wa, input wire we,
   input wire [14:0] di, input wire byp_sel, input wire [14:0] dbyp,
   input wire [31:0] pwrbus_ram_pd
);
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;
   nvdla_cdp_formal_rwsthp #(.DEPTH(80), .WIDTH(15), .AWIDTH(7)) u_ram (
      .clk, .ra, .re, .ore, .dout, .wa, .we, .di, .byp_sel, .dbyp
   );
   wire _unused = &{1'b0, pwrbus_ram_pd,
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};
endmodule

module nv_ram_rwsthp_80x72 (
   input wire clk, input wire [6:0] ra, input wire re, input wire ore,
   output wire [71:0] dout, input wire [6:0] wa, input wire we,
   input wire [71:0] di, input wire byp_sel, input wire [71:0] dbyp,
   input wire [31:0] pwrbus_ram_pd
);
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;
   nvdla_cdp_formal_rwsthp #(.DEPTH(80), .WIDTH(72), .AWIDTH(7)) u_ram (
      .clk, .ra, .re, .ore, .dout, .wa, .we, .di, .byp_sel, .dbyp
   );
   wire _unused = &{1'b0, pwrbus_ram_pd,
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};
endmodule

module nv_ram_rwsthp_60x168 (
   input wire clk, input wire [5:0] ra, input wire re, input wire ore,
   output wire [167:0] dout, input wire [5:0] wa, input wire we,
   input wire [167:0] di, input wire byp_sel, input wire [167:0] dbyp,
   input wire [31:0] pwrbus_ram_pd
);
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;
   nvdla_cdp_formal_rwsthp #(.DEPTH(60), .WIDTH(168), .AWIDTH(6)) u_ram (
      .clk, .ra, .re, .ore, .dout, .wa, .we, .di, .byp_sel, .dbyp
   );
   wire _unused = &{1'b0, pwrbus_ram_pd,
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};
endmodule
