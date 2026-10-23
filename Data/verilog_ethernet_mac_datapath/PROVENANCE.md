# verilog_ethernet_mac_datapath provenance

assembled: 2026-08-19

source: **there is no source package.** This is not a port. The RTL is upstream
verilog-ethernet, copied byte-identical out of a working clone; the formal top,
the environment, the oracle, the candidate targets and everything under
`lists/` were written here.

    upstream: github.com/alexforencich/verilog-ethernet
    clone:    an upstream verilog-ethernet clone
    commit:   77320a9471d19c7dd383914bc049e02d9f4f1ffb  (2025-02-27)

top: `verilog_ethernet_mac_datapath_ft`
environment: `lists/diag_verilog_ethernet_mac_datapath.tcl`
(task `diag_verilog_ethernet_mac_datapath`, **NO assumptions** -- see "The
environment is built, not assumed" below)
candidates: 48 `T_*` assertions and 29 `C_*` covers in
`sva/targets_verilog_ethernet_mac_datapath.sv`, listed with category and intent
in `lists/targets.txt`.

## Why this cut, and how it differs from `verilog_ethernet_fcs_roundtrip`

The corpus already had a verilog-ethernet task. It uses **two** source files
(`axis_eth_fcs_insert.v`, `axis_eth_fcs_check.v`, plus `lfsr.v`) and one
`include`d testbench, and it is a block, not a subsystem: the frame never
leaves a single pair of combinational CRC engines and there is no buffering in
it at all.

This package is the deep cut of the same upstream. **18 source files, 6,610
lines, 23 upstream instances**, and the whole point is the buffering: a frame
is store-and-forwarded **three** separate times, and between the second and
third it is **split into a header and a payload that travel through different
fifos of different depths in different units**. Keeping those two together is
the design's obligation and nothing local enforces it.

## The chain, and where the fifos sit

    veth_frame_src                   authored generator: one well-formed
         |  8-bit AXI-Stream         Ethernet frame at a time
         v
    axis_gmii_tx (u_gmii_src)        UPSTREAM, used as the receive LINK:
         |  gmii                     preamble, SFD, CRC-32 FCS
         v
    +-- eth_mac_1g_fifo (u_mac), receive half -------------------------+
    |   axis_gmii_rx                                                   |
    |     -> BUFFER 1: axis_async_fifo_adapter, FRAME_FIFO, 32 bytes,  |
    |        store-and-forward, DROP_BAD_FRAME + DROP_WHEN_FULL        |
    +------------------------------------------------------------------+
         |  rx_axis: the frame without preamble and without FCS
         v
    eth_axis_rx (u_eth_rx)           SPLITS the frame: 14 header bytes
         |                           become one {dest,src,type} handshake,
         |  hdr  +  payload          the rest stays on the payload stream
         v
    axis_pipeline_register (u_pipe)  2 skid stages, payload only, so the
         |                           header arrives at the demux AHEAD of
         v                           its own payload
    eth_demux (u_demux)              two flows, selected by the LOW BIT OF
         |          \                THE ETHERTYPE -- which is frame data,
         v           v               not a side channel
    BUFFER 2, per flow AND per kind:
        axis_fifo u_hdr_fifo    DEPTH 4,  112-bit {dest,src,type}, one word
                                per frame, LAST_ENABLE(0)
        axis_fifo u_pay_fifo    DEPTH 32, 8-bit, one word per BYTE, tlast
         |          |
         v          v
    eth_arb_mux (u_arb)              round-robin, ARB_BLOCK_ACK: the grant is
         |                           locked for a whole frame
         v
    eth_axis_tx (u_eth_tx)           REJOINS header and payload
         |
         v
    +-- eth_mac_1g_fifo (u_mac), transmit half ------------------------+
    |     BUFFER 3: axis_async_fifo_adapter, FRAME_FIFO, 32 bytes,     |
    |     store-and-forward  ->  axis_gmii_tx (preamble, FCS)          |
    +------------------------------------------------------------------+
         |  gmii
         v
    axis_gmii_rx (u_gmii_mon)        UPSTREAM, used as a MONITOR on the
         |                           transmitted link: re-checks the FCS the
         v                           transmit path computed
    mon_* -- the far observation point

Three distinct blocks with real fifo buffering between them, as required:
the 1G MAC (`eth_mac_1g_fifo` and everything under it), the Ethernet frame
layer (`eth_axis_rx` / `eth_demux` / `eth_arb_mux` / `eth_axis_tx`), and the
AXI-Stream library that provides all four mid-chain queues.

### Geometry

| knob | value | why |
| --- | --- | --- |
| `AXIS_DATA_WIDTH` | 8 | the gmii byte, one lane, no tkeep |
| `ENABLE_PADDING` | 0 | padding a 15-byte frame to 64 costs ~50 cycles of cover depth per frame and adds nothing to any candidate |
| `RX_FIFO_DEPTH` / `TX_FIFO_DEPTH` | 32 bytes | a frame is 15..18 bytes, so the rx fifo holds one frame comfortably and overflows under a stalled transmit link -- which is the interesting case |
| `RX/TX_FIFO_RAM_PIPELINE` | 1 | **not 0**: `axis_async_fifo` has an unguarded `m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-2:0]` inside a run-time `if (RAM_PIPELINE > 0)`, which is a `[-1:0]` part select at 0 |
| `HDR_FIFO_DEPTH` | 4 headers | shallower than the payload fifo on purpose: the header side is the limiter, so head-of-line blocking is reachable |
| `PAY_FIFO_DEPTH` | 32 bytes | ~8 frames' payload, so the two fifos on one flow hold very different numbers of frames |
| `FLOWS` | 2 | one contended resource (`eth_arb_mux`) and two independent flows, the shape `CATEGORIES.md` asks for |
| `ARB_TYPE_ROUND_ROBIN` | 1 | **not the module default (0)**. With fixed LSB priority flow 1 starves whenever flow 0 has a header, and every fairness candidate is false for a reason that is a configuration choice rather than a bug |
| payload length | 1..4 bytes, free per frame | `eth_axis_rx` raises `error_header_early_termination` and produces NO header for a frame with zero payload, so 1 is the floor |
| `cfg_ifg` | 12 | the standard interframe gap |
| `mii_select` | 0 | gmii, one byte per enabled clock |

## What was carried over unchanged

Byte-identical to the clone, verified by `cmp`. **Nothing was scrubbed.** No
`+define+`, no `+incdir+`: none of the eighteen files has an `include or reads
a macro it does not define itself.

    upstream rtl/                        lines
    rtl/verilog_ethernet/eth_mac_1g_fifo.v          333
    rtl/verilog_ethernet/eth_mac_1g.v               644
    rtl/verilog_ethernet/axis_gmii_rx.v             358
    rtl/verilog_ethernet/axis_gmii_tx.v             458
    rtl/verilog_ethernet/eth_axis_rx.v              405
    rtl/verilog_ethernet/eth_axis_tx.v              409
    rtl/verilog_ethernet/eth_demux.v                309
    rtl/verilog_ethernet/eth_arb_mux.v              315
    rtl/verilog_ethernet/lfsr.v                     447

    upstream lib/axis/rtl/
    rtl/axis/axis_async_fifo_adapter.v              378
    rtl/axis/axis_async_fifo.v                      910
    rtl/axis/axis_adapter.v                         325
    rtl/axis/axis_fifo.v                            565
    rtl/axis/axis_pipeline_register.v               162
    rtl/axis/axis_register.v                        280
    rtl/axis/arbiter.v                              159
    rtl/axis/priority_encoder.v                      92
    rtl/axis/sync_reset.v                            61
                                            -----------
                                            18 files, 6,610 lines

Every one is reached: 23 upstream instances counting the ones nested inside
`eth_mac_1g_fifo` (2 x `axis_async_fifo_adapter`, each with an
`axis_async_fifo` and 2 x `axis_adapter`), inside `eth_mac_1g`
(`axis_gmii_rx`, `axis_gmii_tx`, each with an `lfsr`) and inside
`eth_arb_mux` (`arbiter`, with 2 x `priority_encoder`).

`mac_ctrl_tx.v`, `mac_ctrl_rx.v`, `mac_pause_ctrl_tx.v` and
`mac_pause_ctrl_rx.v` are NOT copied: `eth_mac_1g_fifo` instantiates
`eth_mac_1g` with `PAUSE_ENABLE`/`PFC_ENABLE` at their defaults of 0, so those
four sit inside a disabled `generate` and are never elaborated.
`priority_encoder.v` was taken from `lib/axis/rtl/`; the clone has no second
copy on any path this package uses.

### `default_nettype none` was kept, and the local gate is happy with it

Every upstream file opens with `` `resetall `` / `` `default_nettype none ``
and most close with `` `resetall ``, so the single-compilation-unit order in
`lists/tc_elab.files` cannot leak a directive across a file edge. The authored
files do the same. **No mass edit was made and none was needed** -- Slang 11.0
reports **0 errors** over the whole package. Whether Verific is equally happy
is not known here; if a Jasper elaboration rejects the strict nettype, the
correction is a `` `default_nettype wire `` prologue in `lists/tc_elab.files`,
not an edit to the upstream files.

## What was written for this package

### `ft/verilog_ethernet_mac_datapath_ft.sv` -- the formal top and the environment

842 lines with comments. Three authored modules:

- **`veth_frame_src`** offers one frame at a time on an 8-bit AXI-Stream and
  holds every byte stable until the link takes it. The frame is a **function
  of a 16-bit sequence number** that increments once per frame, plus a free
  payload length (1..4) and a free flow bit:

      byte  0..3   8'hDA                     dest_mac[47:16] = 32'hDADADADA
      byte  4..5   seq[15:8], seq[7:0]       dest_mac[15:0]  = seq
      byte  6..9   8'h5A                     src_mac[47:16]  = 32'h5A5A5A5A
      byte 10      plen                      src_mac[15:8]   = payload length
      byte 11      ~seq[7:0]                 src_mac[7:0]    = ~seq[7:0]
      byte 12..13  8'h08, {7'b0, flow}       eth_type = 16'h0800 | flow
      byte 14+j    seq[7:0] ^ (j+1) ^ 8'hA5  payload

  The redundancy is deliberate and it is what makes the far-end oracle a pure
  function: the sequence number is in the dest MAC, its complement is in the
  src MAC six bytes away, the length is in the src MAC, and the low byte of the
  sequence number is in every payload byte. A header that overtakes its own
  payload -- the failure mode a split header/payload fifo pair actually has --
  is visible at the far end with no shadow queue at all.

- **`veth_bounded_stall`** is the whole of the fairness environment. It drives
  a gmii byte-clock enable low only while its free `req` input is high AND
  fewer than three consecutive stalls have been taken, so a link is never
  stalled for more than three cycles in a row. Two instances: one for the
  receive link (gating `u_gmii_src.clk_enable` and `u_mac.rx_clk_enable`
  together, which is what keeps the source and the receiver in step) and one
  for the transmit link (gating `u_mac.tx_clk_enable` and
  `u_gmii_mon.clk_enable` together).

- **`verilog_ethernet_mac_datapath_ft`** wires the chain and holds one
  environment register, `ftenv_injected`.

Free top-level inputs: `env_go`, `env_flow`, `env_len[1:0]`,
`env_rx_link_stall`, `env_tx_link_stall`.

**Using upstream transmit logic as the receive link is the key decision.** A
free gmii input would force the solver to construct a valid CRC-32 before any
frame could get past `axis_gmii_rx`'s FCS check. Driving the receiver from an
`axis_gmii_tx` instance means the preamble, the SFD and the FCS are computed by
real transmit logic, so frames actually arrive -- and the same trick at the
far end (`u_gmii_mon`) means the FCS the transmit path computes is checked by
an independent receiver rather than by the checker.

### `sva/targets_verilog_ethernet_mac_datapath.sv` -- the oracle and the candidates

769 lines, bound into the formal top. The oracle is four things, none of them a
restatement of the design's logic:

1. **Its own gmii frame parser.** The checker re-counts the bytes coming off
   the transmitted link into its own `mon_idx` / `mon_dest` / `mon_src` /
   `mon_type` registers. It reuses nothing from `eth_axis_rx`.
2. **A recomputed reference byte.** `mon_expect = mon_dest[7:0] ^ (mon_idx-13)
   ^ 8'hA5`, derived from the header of the frame in progress. The checker
   never reads a fifo, a pointer or a state register to decide what the answer
   should be.
3. **Frame counters at seven boundaries** -- injected, rx-fifo good / bad /
   overflow, rx_axis out, per-flow header and payload in and out, delivered --
   all this file's own registers, all saturating.
4. **Five saturating wait timers.** Fairness, bounded response and deadlock are
   bounds on those timers. There is no `s_eventually`, no `F` and no `G F`
   anywhere in this package -- every candidate is a safety property.

48 `T_<CATEGORY>_<NAME>` assertions across **14 of the 15 categories**, and 29
`C_*` covers with at least one per category used.

**Category 15, coherence, is not used, and that is a result rather than an
omission.** There is no second agent holding a permission on a line anywhere in
this subsystem. The nearest thing is the arbiter's grant lock, which is filed
under allocator discipline (`T_ALLOC_ARB_GRANT_HELD_UNTIL_ACK`).

### `lists/` -- entirely new

    lists/tc_elab.files            the one analyzed, appendable list; ends with
                                   a newline, no absolute paths.
    lists/tc_elab.tcl              the elaboration recipe. verilog-ethernet
                                   ships cocotb testbenches, not a Jasper flow,
                                   so there is no upstream `tcl/setup.tcl` to
                                   derive it from; it follows the shape of the
                                   other ports in `tasks/` and adds only the
                                   clock name (`clk`) and the reset
                                   (`rst == 1'b1`, ACTIVE HIGH).
    lists/diag_verilog_ethernet_mac_datapath.tcl
                                   defines
                                   `setup_diag_verilog_ethernet_mac_datapath`
                                   at global scope, declares no assumptions,
                                   prints the target and cover census.
    lists/reset_modes.tcl          `rm_all_registers` + `_rm_apply_reset`,
                                   which is all `v5/cex.tcl` calls, on
                                   `rst == 1'b1`.
    lists/targets.txt              one `label<TAB>category<TAB>intent` line per
                                   candidate, checked to match the SVA labels
                                   exactly and in order.
    lists/proofgrid_profiles.tcl   copied verbatim from
    lists/vendor/iterdev_utils.tcl `tasks/corundum_dma_path/lists/`; both are
                                   task-agnostic.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on the first
run. It is derived, not authored, and is gitignored.

The repo's `.gitignore` tracks the authored half of a task package and leaves
the upstream tree out; the block appended for this one tracks `lists/`, `sva/`,
`ft/`, `taskdef.json` and this file, and leaves `rtl/` on disk only, the same
rule the other packages follow.

## The environment is built, not assumed

`lists/diag_verilog_ethernet_mac_datapath.tcl` declares **no assumptions**, and
neither does any file in the package. Everything a constraint would normally
say is synthesisable logic in the formal top instead:

- `veth_frame_src` offers one well-formed frame at a time and holds every byte
  stable until the link takes it, so no AXI-Stream source-stability assumption
  is needed;
- the receive link is an upstream `axis_gmii_tx` instance, so the FCS the
  receiver checks is a real CRC-32. No assumption says "the incoming frame has
  a good FCS" -- it has one because something built it;
- both gmii byte-clock enables come from `veth_bounded_stall`, so the fairness,
  bounded-response and deadlock candidates have a real bound rather than an
  assumed one. This is load-bearing: with an unbounded link stall every one of
  those eight candidates is false;
- `eth_demux.enable` is tied high and `eth_demux.drop` tied low, so the one
  mid-chain place that could discard a frame is wired shut rather than assumed
  quiet.

The consequence for a reader of a result is that these numbers are obtained
under a *built* environment, and a built environment is inside the reset cut's
scope. That is what `design_keep` is for.

## `design_keep`, and why each entry is there

    "veth_mac_targets\\."     the oracle's own state
    "env_src\\."              the frame generator's state
    "u_[rt]x_stall\\."        the two bounded-stall counters
    "ftenv_"                  the injected-frame counter in the formal top

`v5/cex.tcl:ENTER_FRA_KEEP` cuts **every** register that no keep pattern
matches. The rule is: preserve the instrument, cut the design.

1. **`veth_mac_targets\.`** -- the bound checker. Every one of the 48
   candidates reads it: the gmii parser, the per-flow last-sequence registers,
   the twelve frame counters and the five timers ARE the oracle. Cut, they
   start arbitrary and the targets are falsified at cycle 0 for a reason
   nothing in the design can correct.
2. **`env_src\.`** -- `busy_reg`, `idx_reg`, `seq_reg`, `plen_reg`, `flow_reg`.
   Cut, the generator can start mid-frame with a byte index that does not match
   the length it is about to claim, and emit a frame whose payload the checker
   cannot predict. That falsifies the data-integrity candidates through the
   *environment*, which no design-side helper can reach.
3. **`u_[rt]x_stall\.`** -- each is one 3-bit counter that bounds a link stall
   at three consecutive cycles. Cut, the counter starts anywhere in 0..7 and
   the worst-case stall becomes seven consecutive cycles, roughly doubling
   every latency the hand-chosen bounds in the fairness / bounded-response /
   deadlock candidates were computed from.
4. **`ftenv_`** -- `ftenv_injected`, which `T_REQRSP_MON_SEQ_WAS_INJECTED`
   compares a delivered sequence number against. Cut, it starts arbitrary and
   that candidate is false for an environment reason.

Everything else is cut: all eighteen upstream modules, all 23 instances, both
async frame fifos and their gray-code pointer synchronisers, all four
mid-chain fifos and their RAMs, both gmii CRC pipelines, the demux and arbiter
state, and the two `sync_reset` chains. That is where the difficulty is, and it
is the point -- proving that payload byte *j* of a transmitted frame is a
function of the dest MAC of the same frame needs an inductive invariant that
spans the rx frame fifo's commit pointer, `eth_axis_rx`'s header pointer, the
demux's latched select, the occupancies of two independent fifos, the
arbiter's grant lock and `eth_axis_tx`'s byte counter, none of which the target
mentions.

All four patterns match at least one register, so none can trip `cex.tcl`'s
"design keep pattern matched nothing" FAIL.

## The gate

    uv run python v6_dataset/elab_local.py --task verilog_ethernet_mac_datapath
    OK: verilog_ethernet_mac_datapath elaborates            (exit 0)

    uv run python -c "import taskdefs; print('verilog_ethernet_mac_datapath' in taskdefs.TASKS)"
    True

Slang 11.0 reports **0 errors** over the whole package. The 85 warnings are all
`unconnected-{input,output}-port` on the PTP and PFC/LFC ports that
`eth_mac_1g_fifo` leaves open on its own `eth_mac_1g` instance; none is in an
authored file.

`taskdefs.derive_targets` finds all 48 labels, and `lists/targets.txt` matches
the SVA labels exactly and in order.

## Not verified

**Nothing here has been simulated or elaborated in Jasper.** No simulator is
installed on this machine (`iverilog`, `verilator`, `vcs`, `xrun` are all
absent) and no cluster job was launched. What has been checked is Slang
elaboration plus a desk check of the parameter constraints the upstream modules
assert at run time in `initial` blocks -- which no elaborator evaluates, so
they were read and satisfied by hand:

- `axis_gmii_rx` / `axis_gmii_tx`: `DATA_WIDTH == 8`;
- `axis_fifo` (x4): `DROP_OVERSIZE_FRAME`, `DROP_BAD_FRAME`, `DROP_WHEN_FULL`
  and `MARK_WHEN_FULL` all clear, so none of the four `FRAME_FIFO`
  preconditions applies; the header fifos additionally have `LAST_ENABLE(0)`
  with `FRAME_FIFO(0)`, which is the one combination that requires it;
- `axis_async_fifo` (x2, inside `eth_mac_1g_fifo`): `FRAME_FIFO(1)` with
  `LAST_ENABLE`, `DROP_OVERSIZE_FRAME(1)`, `DROP_BAD_FRAME(1)` and
  `USER_BAD_FRAME_MASK(1'b1)` -- the mask must be non-zero when
  `DROP_BAD_FRAME` is set, and it is;
- `eth_axis_rx` / `eth_axis_tx` / `eth_demux` / `eth_arb_mux` at
  `DATA_WIDTH(8)`, `KEEP_ENABLE(0)`, `KEEP_WIDTH(1)`: one byte lane, so the
  `OFFSET`/`BYTE_LANES` shift path in `eth_axis_rx` degenerates to the
  passthrough branch.

The behavioural facts the oracle depends on were read out of the RTL, not
guessed, and are recorded here so the next reader does not have to re-derive
them:

- `axis_gmii_rx` outputs `gmii_rxd_d4`, five bytes behind the wire, and
  compares `{d0,d1,d2,d3}` against `~crc_next` at the end of the frame. So the
  four FCS bytes are **stripped** and the AXI-Stream is exactly
  dest+src+type+payload. `tuser` at `tlast` means bad FCS or a gmii error.
- `eth_axis_rx` assembles `dest_mac` MSB-first from wire bytes 0..5, `src_mac`
  from 6..11, `eth_type` from 12..13, and raises `m_eth_hdr_valid` at byte 13
  only if the frame does not end there. A zero-payload frame yields
  `error_header_early_termination` and **no header at all**.
- `eth_demux` latches `select` into `select_ctl` on the cycle it accepts a
  header and holds it for the whole frame.
- `eth_arb_mux` sets `request = s_eth_hdr_valid & ~grant` and
  `acknowledge = grant & payload tvalid & tready & tlast` on the **fifo** side,
  and instantiates `arbiter` with `ARB_BLOCK(1)`/`ARB_BLOCK_ACK(1)`, so the
  grant is held from the header until that fifo-side tlast -- one cycle ahead
  of the arb mux's own registered output tlast.
- `axis_async_fifo` pulses **exactly one** of `good_frame`, `bad_frame`,
  `overflow` per frame that reaches its `tlast`: good on commit, bad on an
  FCS-marked drop, overflow on a full or oversize drop. `eth_mac_1g_fifo`
  exposes the receive side's through a four-register toggle synchroniser, which
  in this single-clock top is three cycles of delay and no merging.
- `axis_fifo.status_depth` is `wr_ptr - rd_ptr` **registered**, and `rd_ptr`
  advances when a word moves into the output pipeline, so it under-reports by
  up to `RAM_PIPELINE+1` words. That is why the checker's own in-minus-out is
  bounded by `DEPTH + 2` and not by `DEPTH`.

## What is expected to be wrong

Recorded here because a number published without its known caveats is worse
than no number. These are the candidates most likely to come back `cex` from
the phase-1 screen, and the deferrals that go with them.

- **The eight hand-chosen bounds** -- `N_ARBWAIT(600)`, `N_MACTX(400)`,
  `N_RXSTALL(600)`, `N_PROGRESS(400)`, `N_E2E(2000)` and `MID_CAP(24)`. They
  are estimates from counting handshakes along the chain (a gmii byte costs up
  to four cycles, a frame on the wire is 39..42 byte times, so one frame
  occupies the transmit link for at most ~170 cycles), not measurements. If one
  is too tight the screen returns `cex` and the right correction is a larger
  constant, not a different property. `T_CONSERV_MID_INFLIGHT_BOUNDED` is the
  shakiest: 24 is a capacity estimate over four fifos, two pipeline registers
  and two gmii state machines.
- **`T_CONSERV_HDRPAY_LOCKSTEP_IN_FLOW0` and `..._OUT_FLOW0`** were both
  written as one-sided inequalities first and are now two-sided, because the
  skew has both signs: a full header fifo lets a frame's payload finish while
  its header is still in the demux output register, and the arb mux drives its
  payload ready off `grant_valid` alone so a one-byte payload can move on the
  grant cycle, before `s_eth_hdr_ready` consumes the header. The bound of 1
  rests on "only one frame is ever in that state", which is an argument, not a
  construction. If it can reach 2 these two come back `cex` and the fix is the
  constant.
- **`T_RESET_ARB_NO_GRANT_AT_START` and `T_RESET_HDRFIFOS_EMPTY_AT_START`** are
  assertions about design registers in the first cycle out of reset, and the
  reset cut starts those registers arbitrary. Under FRA they are falsified for
  a reason nothing can correct. They are here because the category exists and
  saying so is a result; expect them to be dropped. `CATEGORIES.md`'s own
  measured screen found 0 of 4 reset candidates hard.
- **`T_DATA_MON_FCS_GOOD`** assumes the transmit frame fifo never emits a
  partially-drained frame. `TX_FRAME_FIFO(1)` is store-and-forward and
  `tx_error_underflow` should therefore be impossible, but if the tx link stall
  interacts with the frame commit in a way this desk check missed, the monitor
  sees `gmii_tx_er` and this fails.
- **`T_ORDER_ERX_HDR_SEQ_INCREASING`** and the two `T_ORDER_HDRFIFO*` are the
  weakest of the ordering family, because each is provable from a single queue
  plus its writer. They are here for the "where did it break" split against the
  two `T_ORDER_MON_*`, which are the end-to-end ones.
- **Cover depth is the standing risk for this package, and it is deferred, not
  solved.** A minimal frame is 8 preamble + 15 data + 4 FCS = 27 byte times on
  the receive link, then the rx frame fifo's store-and-forward and its gray
  pointer synchronisers, then the split, the demux, two fifos, the arbiter, the
  rejoin, the transmit frame fifo's store-and-forward and 27 more byte times on
  the transmit link. Rough end-to-end latency for one frame with no stalls is
  120-180 cycles, and every stall multiplies a byte time by up to four. So
  `C_DELIVER_ONE_FRAME` and everything downstream of it are DEEP covers.
  The mitigation in the file is graduated: `C_INJECT_*`, `C_RX_*`, `C_ERX_*`,
  `C_DEMUX_*` and `C_HDRFIFO0_TWO_DEEP` sit at increasing depths along the
  chain, so a `COVER_DEPTH` run that cannot reach the far end still reports
  where it stopped. If the screen finds `C_DELIVER_ONE_FRAME` unreachable in
  budget, the cheapest correction is `ENABLE_PADDING(0)` on the *receive* link
  source (already done) plus dropping `axis_pipeline_register` and lowering
  `cfg_ifg`; the expensive one is moving the far observation point from the
  monitor to `mac_tx_*`, which costs the FCS check and the transmit fifo.
