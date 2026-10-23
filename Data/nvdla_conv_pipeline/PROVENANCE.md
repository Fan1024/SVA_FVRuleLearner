# nvdla_conv_pipeline provenance

assembled: 2026-08-19

source: an upstream nvdla clone (copied out of; the source
tree was not modified). Upstream is the public NVDLA `nvdlav1` release.

**No source task package exists for this one.** Unlike every other port in
`tasks/`, there was nothing to port: this package was assembled from raw
upstream RTL. The RTL is byte-identical upstream; the formal top, the bounded
environment, the oracle, the assertions and all of `lists/` are task-authored.
`tasks/openpiton_pmesh_order` is the closest precedent — there too only the
router RTL came from upstream.

top: `nvdla_conv_pipeline_ft`
environment: `lists/diag_nvdla_conv_pipeline.tcl` (task
`diag_nvdla_conv_pipeline`, declares no assumption of its own)
targets: 48 `T_*` labels in `sva/nvdla_conv_pipeline_checker.sv`, listed with
their category and intent in `lists/targets.txt`
covers: 33 `C_*`, not targets — they are what `COVER_DEPTH` counts

## What this is

The whole NVDLA convolution datapath, five blocks deep, closed end to end:

    memory -> CDMA -> CBUF -> CSC -> CMAC_A / CMAC_B -> CACC -> SDP
                        ^        |                       |
                        |        +--- entry credits -----+
                        +--- CBUF entry / slice credits -+

    NV_NVDLA_cdma   fetch: two read-DMA channels (feature data, weights),
                    each with an MCIF and a CVIF port; writes CBUF
    NV_NVDLA_cbuf   512 KiB: 16 banks x 2 columns of 256 x 512b, two write
                    ports and three read ports over one shared bank array
    NV_NVDLA_csc    sequence control: reads CBUF, drives both MAC halves
    NV_NVDLA_cmac   the 128-lane MAC array, instantiated TWICE, exactly as
                    `NV_nvdla.v` instantiates `NV_NVDLA_partition_m` twice
    NV_NVDLA_cacc   accumulator: assembly buffer, delivery buffer, SDP egress

Elaborated: **983 instances, 143 distinct module definitions.**

The five module headers close on their own port names with **zero multiply
driven nets** and no renaming except the two the chip itself does: CSC's
`sc2mac_*_a_*` / `_b_*` become each CMAC's `sc2mac_*_*`, and each CMAC's
`mac2accu_*` becomes CACC's `mac_a2accu_*` / `mac_b2accu_*`. The 620-line wire
block and the six port maps in the formal top were GENERATED from the headers
rather than typed, and the generator reported the undriven-input set, which is
what the environment section then drives and nothing more.

Depth was the point, and no stage was dropped. The fallback the work item
allowed — retreating to `csc -> cmac -> cacc` — was not needed: the full
five-stage closure elaborates.

## What came over unchanged

Byte-identical to upstream, verified with `cmp` file by file:

    rtl/cdma/*.v    25 files   103,010 lines   vmod/nvdla/cdma
    rtl/cbuf/*.v     1 file      7,268 lines   vmod/nvdla/cbuf
    rtl/csc/*.v     12 files   104,575 lines   vmod/nvdla/csc
    rtl/cmac/*.v    14 files    67,977 lines   vmod/nvdla/cmac
    rtl/cacc/*.v    13 files    30,743 lines   vmod/nvdla/cacc
    rtl/vlibs/*.v    5 files       297 lines   vmod/vlibs
    include/simulate_x_tick.vh     41 lines    vmod/include

313,573 lines of generated NVDLA RTL, plus the five library cells the datapath
instantiates: `NV_BLKBOX_SINK`, `NV_CLK_gate_power`, and the three behavioural
DesignWare stand-ins `NV_DW02_tree`, `NV_DW_minmax`, `NV_DW_lsd`.

Nothing was scrubbed. Nothing in these files describes a verification
environment or a solution; the fifty-odd `nv_assert_*` instances they carry are
all inside `// synopsys translate_off` and are excluded by the
`--translate-off-format` flag `taskdefs.slang_args` already passes and by
Jasper's own handling.

## What was authored

    ft/nvdla_conv_pipeline_ft.sv       2,193 lines   the formal top
    ft/nvdla_conv_mem_responder.sv        91 lines   bounded memory model
    sva/nvdla_conv_pipeline_checker.sv   829 lines   oracle, 48 targets,
                                                     33 covers, 1 assumption
    rtl/nvdla_conv_ram_models.sv          90 lines   nine SRAM models
    lists/*                                          entirely new

### The RAM models, and why they are not upstream

The datapath instantiates nine generated SRAM wrappers:
`nv_ram_rws_256x512` (x32, the CBUF banks), `nv_ram_rws_16x256` (x16, the CDMA
shared buffer), `nv_ram_rws_64x10`, `nv_ram_rws_32x512`, `nv_ram_rws_32x544`,
`nv_ram_rws_32x768` (CACC), and `nv_ram_rwsp_128x6` / `_128x11` / `_32x32` (the
CDMA fifogen FIFOs). The upstream wrappers under `vmod/rams/synth` wrap foundry
macros (`RAMPDP_256X144_GL_M2_D2` and friends) in DFT, MBIST, JTAG, retention
and power plumbing, and the only models of those macros, under
`vmod/rams/model`, are simulation-only: `#1` delays, X-clobber logic, `initial`
blocks. `rtl/nvdla_conv_ram_models.sv` replaces all nine with the one behaviour
the datapath depends on, a synchronous 1R1W memory:

    posedge clk:  if (we) mem[wa] <= di;
                  if (re) dout   <= mem[ra];

`tasks/nvdla_mcif_order/rtl/nvdla_formal_ram_models.sv` does exactly this for
two wrappers; this is the same decision at nine.

Two facts about the models are load-bearing and are stated here so a reader
does not have to re-derive them:

- **Read-before-write on a same-cycle same-address collision** is this file's
  choice, not the foundry cell's. The real dual-port macro calls that
  contention, which is why fifogen threads
  `FORCE_CONTENTION_ASSERTION_RESET_ACTIVE` down as the wrapper's one
  parameter. Every read-back target in this package is guarded by a
  four-cycle quiet window that excludes the collision, so the choice does not
  decide any result.
- **`ore` on the three `rwsp` wrappers is DFT-only.** In
  `nv_ram_rwsp_*_logic.v` it appears in exactly one expression, the JTAG
  `captureDR_r0` term, and the CDMA FIFOs that instantiate these leave it
  undriven. It is accepted and ignored.

### The formal top and its bounded environment

Not included, deliberately: the `NV_NVDLA_RT_*` partition retiming stages that
sit on csc2cmac, cmac2cacc, csb2cmac and cacc2glb in the real floorplan. They
are flop banks on unidirectional valid/data pipes with no ready, so leaving
them out changes latency and nothing else — and it keeps the CSC-to-CMAC
latency at the four cycles the CMAC RTL itself defines, which is what
`T_DATA_MAC_A_PD_PRESERVED` and `T_BOUNDRSP_MAC_A_OUTPUT_IN_4` are stated
against.

**Memory.** Four `nvdla_conv_mem_responder` instances, one per read-DMA port.
Each holds ONE command at a time — `req_ready` is asserted only when the
previous command has fully drained. That is what makes its `owed` ledger exact
rather than saturating: one command asks for at most 2^15 atoms, so a 16-bit
counter covers it with no clamp. Payload (`env_data`) is free; the
data-integrity oracle watches what CDMA writes into CBUF, not what memory
returned, so no structured data is needed. The return channel can be stalled
freely by `env_hold` but only for `MAX_HOLD` = 4 consecutive cycles: an
unbounded stall would make every drain obligation on the fetch path false for
an environment reason, which measures nothing.

Field positions were read out of the RTL, not a spec:
`NV_NVDLA_CDMA_dc.v:7911` gives `dma_rd_req_pd[63:0]` = byte address and
`[78:64]` = size, and `:7915` shows the address is `{addr[58:0], 5'b0}`, i.e.
32-byte aligned; `:8001` gives `dma_rd_rsp_pd[511:0]` = data and `[513:512]` =
a mask with one bit per 32-byte atom, counted as `mask[0] + mask[1]`. The size
field counts atoms MINUS ONE, which `tasks/nvdla_mcif_order`'s checker also
records.

**Configuration.** `csb2*_req_prdy` is a hard `assign ... = 1'b1` in all five
generated regfiles (`NV_NVDLA_CDMA_regfile.v:1097`, `CSC_regfile.v:781`,
`CMAC_reg.v:536`, `CACC_regfile.v:627`). There is no handshake to model, so the
CSB stimulus is five free inputs and nothing constrains them. Under the reset
cut the configuration registers start arbitrary anyway; constraining the
request stream would buy nothing and could hide a real state.

**SDP sink.** `cacc2sdp_ready` is free backpressure bounded to `SINK_MAX` = 4
consecutive stalled cycles, for the same reason as `MAX_HOLD`.

**Statics.** `pwrbus_ram_pd` = 0 (functional mode), both clock-override syncs
low, `tmc2slcg_disable_clock_gating` high. With `+define+VLIB_BYPASS_POWER_CG`
every `NV_CLK_gate_power` is a wire-through, so no SLCG can stop a clock;
holding the disable high keeps that explicit rather than incidental.

### The oracle

Everything the checker observes crosses a block boundary. It reaches inside no
block: not CDMA's sequencers, not CBUF's bank decode, not CSC's dual-line
buffer, not the MAC array, not CACC's assembly and delivery buffers. There is
not one hierarchical tap in this package.

Four independent instruments:

1. **A symbolic CBUF half-line.** `sym_addr` / `sym_col` name one 512-bit
   column entry, frozen by `A_SYM_FROZEN`. `shadow` records what CDMA last
   wrote there, `quiet` counts cycles since anything could have disturbed it,
   and three arming shift registers — one per CBUF read port — carry an armed
   read to the cycle its data is due. This is the whole cdma->cbuf->csc
   closure in one property: what came out is what went in, through a 512 KiB
   banked memory with a two-deep write pipeline and a six-deep read pipeline
   that the checker does not model.

   The disturbance rules are the checker's own and are deliberately
   conservative, because CBUF ORs decoded addresses rather than arbitrating
   them. Two writers to one bank in one cycle produce an address that is
   neither of theirs, so that case POISONS the shadow instead of updating it;
   another read port selecting the symbolic bank DISARMS instead of being
   modelled. The port-to-bank reach was read off the RAM address muxes: the
   dat port reaches banks 0..14, the wt port 1..15, the wmb port 15 only.

2. **A token queue per MAC half.** `sc2mac_dat_*_pd` is pushed on its valid,
   `mac_*2accu_pd` pops. The queue, its pointers and its occupancy are the
   checker's; the design is asked only to deliver the head.

3. **Ledgers.** CBUF entry credits granted versus released (the `entries`
   fields are deltas — `NV_NVDLA_CSC_sg.v:8323` adds them to an availability
   counter), SDP beats accepted versus credits returned to CSC, and CBUF data
   write beats.

4. **Saturating wait counters** — how fairness, bounded response and deadlock
   freedom are written as safety here. There is no `s_eventually` anywhere in
   this package: under the reset cut a liveness property is vacuous or false
   for a reason the design cannot correct.

### The one assumption

`A_SYM_FROZEN` in the checker:

    A_SYM_FROZEN: assume property (@(posedge clk)
       1'b1 |=> ($stable(sym_addr) && $stable(sym_col)));

It freezes two FREE FORMAL-TOP INPUTS so that "one CBUF half-line" is a
constant rather than a moving target. It constrains no design output and no
target depends on it being anything in particular. It is the standard
symbolic-constant idiom and it is the only assumption in the package;
`diag_nvdla_conv_pipeline` adds none.

## `age`: why almost every target is gated on a warm-up counter

Under `ENTER_FRA_KEEP` every design register not matched by a keep pattern
starts arbitrary. A property about a pipeline of depth d says nothing before
that pipeline has been driven for d cycles — CBUF's read valid is a six-deep
shift register and CMAC's is four deep, and at cycle zero both hold noise.
`age` is the checker's own saturating cycle counter and `warm4` / `warm8` /
`warm16` are the gates written against it.

This is a statement about what is being measured, not a way to make targets
pass. A gate of 8 flushes the CBUF read pipeline; it does not flush CDMA's DMA
sequencer or CSC's slice state, so the targets that depend on those stay hard,
which is the band the screen is looking for.

## DESIGN_KEEP: this task needs a large one, and here is the reason per entry

`taskdef.json`'s `design_keep` is matched unanchored against instance paths as
`get_design_info -list register` returns them, the form `_CHECKER_KEEP` uses.
Every entry is instrument, not design. The rule is the repository's: **preserve
the instrument, cut the design.** The two NVDLA packages assembled before this
one, `nvdla_rubik_merge_transpose` and `nvdla_sdp_wdma_pack_order`, both found
their FORMAL TOP holding state of this kind; that was checked here and this one
does too, which is why the last two entries are not in `u_checker`.

| pattern | why |
| --- | --- |
| `u_checker\.(age\|shadow\|shadow_valid\|quiet\|dat_arm\|wt_arm\|wmb_arm\|dat_exp\|wt_exp\|wmb_exp)` | `age` gates 40 of the 48 targets: arbitrary, it satisfies every warm-up gate at cycle 0 and falsifies them all for a reason the design cannot correct. The rest is the CBUF read-back instrument — an arbitrary `shadow` or `quiet` arms a read against a value never written. |
| `u_checker\.(last_dat_half\|last_dat_valid\|dat_en_sr\|wt_en_sr\|wmb_en_sr\|dat_inflight)` | `*_en_sr` is the checker's own six-deep record of issued CBUF reads and is the entire right-hand side of `T_ORDER_CBUF_*_RD_VALID_TRACKS_ISSUE`. `last_dat_*` is the right-hand side of the stability and coherence targets. |
| `u_checker\.(tok_wr\|tok_rd\|tok_cnt\|tok_push\|tok_pop)` | the MAC token queue's pointers and totals; `T_ORDER_MAC_*_PD_IS_QUEUE_HEAD` and `T_CONSERV_MAC_A_TOKENS` read all of them. |
| `u_checker\.(sdp_beats\|sdp_beats_d1\|sdp_credits\|dat_wr_beats)` | both sides of `T_CONSERV_SDP_BEATS_EQ_CREDITS`, and the witness `T_ALLOC_CBUF_DAT_NO_GRANT_BEFORE_WRITE` tests. |
| `u_checker\.(dat_granted\|dat_released\|wt_granted\|wt_released)` | both sides of the two entry-credit conservation targets and the two allocator targets. |
| `u_checker\.(wait_mem_rsp0\|wait_dat_pending\|wait_wt_pending\|wait_owed0\|wait_progress)` | the five saturating wait counters. Each IS its target: cut, a counter starting above its bound fails at cycle 0. |
| `u_checker\.seen_(dat_readback\|wt_readback\|wmb_readback\|mem_dat_rsp\|mem_wt_rsp)` | cover state only, no target reads it. Kept anyway: arbitrary, these make `C_REQRSP_MEM_DAT_AND_WT_BOTH_SERVED` reachable for free and OVERSTATE coverage, which is worse than a target failing. |
| `u_mem_(dat\|wt)_(mcif\|cvif)\.(owed\|hold_cnt)` | FORMAL TOP state. `owed` arbitrary means the responder returns beats nobody asked for, which breaks the fetch ledger and `T_DEADLOCK_MEM_DAT_COMMAND_DRAINS_WITHIN_256` for an environment reason. `hold_cnt` arbitrary un-bounds the stall the responder is supposed to bound. |
| `ft_sdp_stall` | FORMAL TOP state, the SDP sink's stall counter. Arbitrary, it only makes the sink ready sooner, so it cannot falsify a target — but it is the register that bounds the sink and it is kept for the same reason as `hold_cnt`. Renamed from `sdp_stall` because `NV_NVDLA_CACC_delivery_buffer.v` has a cover property containing `cacc2sdp_stall`, and an unanchored pattern must not reach into the design. |

### What is deliberately NOT kept

`u_checker.tok_mem`, the 16 x 9-bit token storage. Its reset branch assigns
`tok_wr`, `tok_rd` and the counters and nothing else, so `tok_mem` has no reset
value at all — and `stopat -reset` cuts a reset value. Keeping a register that
has none is a no-op that inflates the logged `KEEP_PATTERN design` count, which
is read as a measurement. This is the same argument
`tasks/openpiton_pmesh_order/PROVENANCE.md` makes about `ref_mem`, and it
carries the same obligation: `T_ORDER_MAC_A_PD_IS_QUEUE_HEAD` requires
`tok_cnt != 0` before it reads `tok_mem[tok_rd]`, and a count only becomes
nonzero through a push, which is the same event that writes `tok_mem` at
`tok_wr`. So an entry is never read before it is written — PROVIDED the
pointers start at reset, which is what the keep set buys. That is an argument,
not a construction, and anyone reading a result from this task should know the
difference.

Every kept family is reset-assigned, so no pattern can match zero and trip
`cex.tcl`'s "design keep pattern matched nothing" FAIL.

## The gate

    uv run python v6_dataset/elab_local.py --task nvdla_conv_pipeline
    OK: nvdla_conv_pipeline elaborates          # exit 0

Also checked, beyond what the gate asks:

- the same elaboration WITHOUT `--ignore-unknown-modules`: **0 errors, 0
  warnings**, so the package is closed — no blackboxed cell, no missing RAM.
- 983 instances, 143 module definitions, top-level children exactly
  `u_cdma u_cbuf u_csc u_cmac_a u_cmac_b u_cacc u_mem_{dat,wt}_{mcif,cvif}
  u_checker`.
- all 70 upstream files `cmp`-identical to `vmod`.
- `taskdefs.TASKS["nvdla_conv_pipeline"]` loads with 48 target labels, and
  `lists/targets.txt` names exactly the same 48.

## Not verified

Nothing here has been elaborated in Jasper and no proof has been run. Slang and
Jasper disagree about some SystemVerilog and only Jasper's verdict admits a
package to a round. In particular the register census, the `KEEP_PATTERN
design` hit count and every claim below about which targets are true are
UNPROVEN.

### Targets whose truth rests on a reading of the RTL, not on a proof

Stated so the screen's verdicts can be read against an expectation rather than
against nothing.

**Expected true, from a specific line of RTL.** `mac2accu_pvld(t) ==
sc2mac_dat_pvld(t-4)` for t >= 4 comes from four unconditional flops on the
ungated core clock: `CMAC_CORE_rt_in.v:1661`, `CMAC_core.v:1094` and `:1111`,
`CMAC_CORE_rt_out.v:444`. The pd flops beside them are each enabled by the
corresponding valid stage, which is what makes `T_DATA_MAC_A_PD_PRESERVED`
follow. `sc2buf_*_rd_valid` is `sc2buf_*_rd_en` delayed exactly six cycles
(`NV_NVDLA_cbuf.v:4605, 5180, 5426, 5997, 6212, 6219`). `accu2sc_credit_vld <=
cacc2sdp_valid & cacc2sdp_ready` and `accu2sc_credit_size = 3'h1` are
`CACC_delivery_ctrl.v:4273-4278`. The CSB response is two flops
(`CDMA_regfile.v:1022, 1030, 1141`).

**Expected FALSE under the reset cut, and included as candidates anyway.** The
four `T_RESET_*` targets assert a post-reset shape that `stopat -reset` removes
by construction. They are in the list for the same reason
`tasks/l15_l2_mshr_onehot` carries four of them: the screen's job is to sort
candidates, and a category with no candidate is a gap in the corpus rather
than a result.

**Genuinely uncertain — these are the ones to watch.**

- `T_MUTEX_CBUF_WR_PORT_BANK_EXCLUSIVE`, `T_MUTEX_CBUF_RD_PORT_BANK_EXCLUSIVE`
  and `T_BOUND_CBUF_DAT_WR_ADDR_IN_RANGE`. CBUF's port-to-bank map (dat 0..14,
  wt 1..15, wmb 15) says NVDLA intends the data and weight regions to be
  disjoint, and the OR-mux on the RAM addresses says the hardware does not
  enforce it. Whether the CSC and CDMA sequencers keep them disjoint from an
  ARBITRARY configuration and an arbitrary starting state is exactly the open
  question, and I do not know the answer.
- `T_FAIR_CSC_DAT_PENDING_ACKED_WITHIN_512` and its weight twin. The semantics
  of `sc2cdma_*_pending_req` / `cdma2sc_*_pending_ack` were not traced past the
  ports. If the request is a level that CDMA leaves unacknowledged while it has
  no data, 512 is arbitrary and the target is false.
- `T_BOUND_MEM_DAT_REQ_ATOMS_LE256`. 256 atoms is a guess at what a legal CDMA
  burst is; the field is 15 bits wide and an arbitrary configuration may well
  exceed it.
- `T_CONSERV_CBUF_*_ENTRIES_NOT_OVERRELEASED` and the two
  `T_ALLOC_*_NO_RELEASE_WITHOUT_GRANT`. These read `entries` as a delta, which
  `NV_NVDLA_CSC_sg.v:8323` supports for the CDMA-to-CSC direction. The
  CSC-to-CDMA direction was NOT traced to its consumer, so the two ledgers may
  not be in the same units.
- `T_LIFECYCLE_MAC_A_PD_HELD_UNLESS_VALID`. Derived from `out_rt_pd_d1` being
  enabled by `out_rt_pvld_d0` while `mac2accu_pvld` is `out_rt_pvld_d1`; if
  there is a second writer to that register the target is false.
- `T_DEADLOCK_CONV_PIPELINE_PROGRESS_WITHIN_1024` and
  `T_BOUNDRSP_MEM_DAT_RSP_TAKEN_WITHIN_256`. The bounds are round numbers, not
  derived. They are the shape the category asks for; the constants are a first
  guess.
- The three `T_DATA_CBUF_*_READBACK` targets — the flagship pair with
  `T_DATA_CBUF_DAT_LINE_STABLE_WITHOUT_WRITE`. I believe them: the quiet
  window covers the two-cycle write pipeline, the arming excludes every bank
  collision the OR-muxes admit, and the six-cycle arming shift register matches
  the read pipeline. But the argument has four moving parts and none of it has
  been run. If one of them is wrong it is most likely the write-commit depth —
  `cbuf_wa_*_d2` is two flops from the port, and the quiet window is four.
