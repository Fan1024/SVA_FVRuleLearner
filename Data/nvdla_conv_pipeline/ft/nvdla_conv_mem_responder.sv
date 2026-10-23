// ===========================================================================
// Bounded memory responder for one NVDLA read-DMA port.
//
// Task-authored.  Nothing upstream corresponds to it: in the real chip these
// four ports terminate in the MCIF / CVIF arbiters and then in DRAM or SRAM,
// which is another 100k lines and a second AXI protocol.  What the convolution
// datapath needs from memory is only this:
//
//   * a read command carries a 64-bit byte address and a 15-bit size field
//     that counts 32-byte atoms MINUS ONE (`NV_NVDLA_CDMA_dc.v`,
//     `dma_rd_req_pd[63:0] = addr`, `[78:64] = size`);
//   * a read response carries 512 bits of data and a two-bit mask, one bit per
//     32-byte atom in the beat (`dma_rd_rsp_pd[511:0]`, `[513:512]`), and the
//     requester counts atoms as `mask[0] + mask[1]`.
//
// This model is STRICTLY ORDERED and holds ONE command at a time: `req_ready`
// is asserted only when the previous command has fully drained.  That is what
// makes `owed` exact rather than saturating -- one command asks for at most
// 2^15 atoms, so `owed` fits in 16 bits with no clamp, and the atom ledger the
// checker keeps is an equation rather than an inequality.
//
// `env_hold` lets the environment stall the return channel, but only for
// MAX_HOLD consecutive cycles.  An unbounded stall would make every
// bounded-response obligation on the fetch path false for an environment
// reason, which measures nothing.  `hold_cnt` is the register that bounds it
// and it must be kept out of the reset cut -- see PROVENANCE.md.
//
// `env_data` is free: the payload is whatever the environment offers.  The
// data-integrity oracle watches what CDMA writes into CBUF, not what memory
// returned, so nothing here needs to generate structured data.
// ===========================================================================

module nvdla_conv_mem_responder #(
   parameter integer MAX_HOLD = 4
) (
   input  wire         nvdla_core_clk,
   input  wire         nvdla_core_rstn,

   input  wire         req_valid,
   output wire         req_ready,
   input  wire [78:0]  req_pd,

   output wire         rsp_valid,
   input  wire         rsp_ready,
   output wire [513:0] rsp_pd,

   input  wire         env_hold,
   input  wire [511:0] env_data,

   output wire [15:0]  atoms_owed
);
   localparam [2:0] MAX_HOLD_C = MAX_HOLD[2:0];

   reg  [15:0] owed;
   reg  [2:0]  hold_cnt;

   // The size field counts atoms minus one.
   wire [15:0] req_atoms = {1'b0, req_pd[78:64]} + 16'd1;

   wire        req_fire  = req_valid && req_ready;
   wire [1:0]  rsp_mask  = (owed >= 16'd2) ? 2'b11 : 2'b01;
   wire        stalling  = (owed != 16'd0) && env_hold;

   assign req_ready  = (owed == 16'd0);
   assign rsp_valid  = (owed != 16'd0) && !(env_hold && (hold_cnt != MAX_HOLD_C));
   assign rsp_pd     = {rsp_mask, env_data};
   assign atoms_owed = owed;

   wire        rsp_fire   = rsp_valid && rsp_ready;
   wire [15:0] rsp_atoms  = {15'd0, rsp_mask[0]} + {15'd0, rsp_mask[1]};

   always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
      if (!nvdla_core_rstn) begin
         owed <= 16'd0;
      end else if (req_fire) begin
         owed <= req_atoms;
      end else if (rsp_fire) begin
         owed <= owed - rsp_atoms;
      end
   end

   always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
      if (!nvdla_core_rstn) begin
         hold_cnt <= 3'd0;
      end else if (stalling) begin
         hold_cnt <= (hold_cnt == MAX_HOLD_C) ? MAX_HOLD_C : (hold_cnt + 3'd1);
      end else begin
         hold_cnt <= 3'd0;
      end
   end
endmodule
