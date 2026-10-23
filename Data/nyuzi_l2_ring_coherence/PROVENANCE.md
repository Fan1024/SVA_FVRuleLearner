# nyuzi_l2_ring_coherence provenance

assembled: 2026-08-19

source: an upstream nyuzi clone — the Nyuzi
Processor (jbush001/NyuziProcessor), Apache 2.0, checkout at
`ed5c1a5 2024-11-07 "Fix NUM_COUNTERS to properly match hardware."`, sparse to
`hardware/core`. The source tree was not modified.

A NEW upstream family for this corpus: an experimental GPGPU, not a CPU core
and not a NoC.

top: `nyuzi_l2_ring_coherence_ft`
environment: `lists/diag_nyuzi_l2_ring_coherence.tcl` (task
`diag_nyuzi_l2_ring_coherence`, **NO assumptions**)
targets: 49 labelled `T_*` in `u_targets`, listed in `lists/targets.txt` and in
`taskdef.json`'s `target_labels`
covers: 17 labelled `C_*` in `u_covers` — reachability only, not targets

## The cut, and why it is this one

The package is a **subsystem, not a block**. Two Nyuzi L1 agents share one L2
cache, with system memory behind it:

    nyuzi_l1_agent#(CORE_ID=0)  ---\                                /--- AXI read
      ifetch_tag_stage (L1I tags     >-- l2_cache --------------------<
        + ITLB + fetch arbitration)  /     l2_cache_arb_stage        \--- AXI write
      ifetch_data_stage (L1I data)  /      l2_cache_tag_stage
      dcache_tag_stage (L1D tags   /       l2_cache_read_stage         nyuzi_axi_mem
        + DTLB + SNOOP port)      /        l2_cache_update_stage       (task-authored)
      dcache_data_stage (L1D data)/        l2_axi_bus_interface
      l1_l2_interface            /           pending_fill_fifo
        l1_load_miss_queue x2   /            pending_writeback_fifo
        l1_store_queue         /             l2_cache_pending_miss_cam
    nyuzi_l1_agent#(CORE_ID=1)-/
                                       l2_response is BROADCAST to both cores

**A transaction is buffered between blocks four times before it comes back.**
That depth is the reason this package exists:

1. `l1_load_miss_queue` (one per L1I and L1D, 4 entries each) and
   `l1_store_queue` (4 entries) hold the request in the requesting core until
   that core's own round-robin arbiter dequeues it;
2. `l2_cache_arb_stage` arbitrates between the two cores with an `rr_arbiter`,
   and is pre-empted entirely by anything coming back from memory;
3. on a miss the request **leaves the L2 pipeline**, sits in
   `pending_fill_fifo` (8 entries) inside `l2_axi_bus_interface` while an AXI
   burst runs, and is **re-injected at the arb stage**, out of order with
   respect to everything the other core did meanwhile. Dirty evictions take the
   parallel `pending_writeback_fifo` (8 entries), which has priority over
   reads;
4. the broadcast response goes through a three-stage pipeline in **both**
   `l1_l2_interface` instances, which snoops the L1D tags one cycle before it
   writes them.

Nothing observable at the L1/L2 boundary is a local fact about any one block,
which is what the targets are written to exploit.

### What was deliberately left out

The rest of `core.sv` — the instruction decoder, the scoreboard, the integer
and floating-point pipes, `writeback_stage`, `control_registers`,
`thread_select_stage`, `io_request_queue`, `on_chip_debugger` and the JTAG TAP.
Everything they would drive (`of_*`, `cr_*`, `wb_*`, `ts_*`, `ocd_*`) is an
**unconstrained input of the formal top**. That is a stronger environment for
the L1/L2 protocol than a real decoder, and it is what makes the miss queues
and the store queue fill. It is also what keeps the package at 6.9k lines
rather than the 10.5k of `hardware/core`.

`nyuzi.sv` itself was not used: it wires `NUM_CORES` cores plus
`io_interconnect`, `performance_counters` and the debug path, none of which is
on the path between an L1 and the L2.

## Files

`lists/tc_elab.files` names **28 source files, 6923 lines**, plus
`rtl/nyuzi/config.svh` and `rtl/nyuzi/defines.svh` which are pulled in by
`+incdir+rtl/nyuzi` rather than listed (every RTL file opens with
`include "defines.svh"`, and `defines.svh` includes `config.svh`). 30 files in
all; 25 of them are upstream.

### Upstream, byte-identical (24 of 25)

    rtl/nyuzi/defines.svh              the `defines` package AND the
                                       `axi4_interface` / `io_bus_interface`
                                       declarations
    rtl/nyuzi/idx_to_oh.sv             leaf cells
    rtl/nyuzi/oh_to_idx.sv
    rtl/nyuzi/rr_arbiter.sv
    rtl/nyuzi/cam.sv
    rtl/nyuzi/sram_1r1w.sv
    rtl/nyuzi/sram_2r1w.sv
    rtl/nyuzi/sync_fifo.sv
    rtl/nyuzi/cache_lru.sv
    rtl/nyuzi/tlb.sv
    rtl/nyuzi/ifetch_tag_stage.sv      L1 side
    rtl/nyuzi/ifetch_data_stage.sv
    rtl/nyuzi/dcache_tag_stage.sv
    rtl/nyuzi/dcache_data_stage.sv
    rtl/nyuzi/l1_load_miss_queue.sv
    rtl/nyuzi/l1_store_queue.sv
    rtl/nyuzi/l1_l2_interface.sv
    rtl/nyuzi/l2_cache_arb_stage.sv    L2 side
    rtl/nyuzi/l2_cache_tag_stage.sv
    rtl/nyuzi/l2_cache_read_stage.sv
    rtl/nyuzi/l2_cache_update_stage.sv
    rtl/nyuzi/l2_cache_pending_miss_cam.sv
    rtl/nyuzi/l2_axi_bus_interface.sv
    rtl/nyuzi/l2_cache.sv

Checked with `diff` against
`an upstream nyuzi clone, hardware/core/<same name>`: only `config.svh`
differs.

### Task-authored

    ft/nyuzi_l1_agent.sv               one core's L1 side, the same five blocks
                                       `core.sv` wraps, with `.*` exactly as
                                       upstream uses it
    ft/nyuzi_axi_mem.sv                the system-memory responder
    ft/nyuzi_l2_ring_coherence_ft.sv   the formal top
    sva/covers_nyuzi_l2_ring_coherence.sv    17 reachability covers
    sva/targets_nyuzi_l2_ring_coherence.sv   the oracle and 49 candidates

    lists/tc_elab.files                the analyzed file list, package-root
                                       relative, ends with a newline, no
                                       absolute paths. Also
                                       `TASKS[...]["slang"]["command_file"]`,
                                       which is the file the round appends one
                                       `../submission/<worker>.sv` line to.
    lists/tc_elab.tcl                  the elaboration recipe
    lists/diag_nyuzi_l2_ring_coherence.tcl   defines
                                       `setup_diag_nyuzi_l2_ring_coherence` at
                                       global scope
    lists/reset_modes.tcl              `rm_all_registers` + `_rm_apply_reset`,
                                       which is all `v5/cex.tcl` calls
    taskdef.json                       per PORTING.md; `taskdefs.py` untouched
    PROVENANCE.md                      this file

Copied verbatim from `tasks/cva6_cache_subsystem/lists/` because both are
task-agnostic (checked: byte-identical to `openpiton_pmesh_order`'s copies):

    lists/proofgrid_profiles.tcl       sourced by our own tc_elab.tcl
    lists/vendor/iterdev_utils.tcl     `safe_assume`. Our diag declares no
                                       assumptions and does not call it, but
                                       `cex.tcl` / `check.tcl` source it when
                                       present and it costs nothing to ship.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on every run.
It is derived, not authored, and `.gitignore`d.

## Scrubbed

**`rtl/nyuzi/config.svh`, 9 macro values.** Nothing else in the package differs
from upstream by a single byte. `config.svh` is Nyuzi's own configuration file
— the comment block above these lines is the upstream author's list of what may
legally be changed and it is untouched — so this is configuration, not a code
edit. It is recorded here because the file is no longer byte-identical.

    -`define NUM_CORES 1              +`define NUM_CORES 2
    -`define L1D_SETS 64              +`define L1D_SETS 4
    -`define L1I_SETS 64              +`define L1I_SETS 4
    -`define L2_WAYS 8                +`define L2_WAYS 2
    -`define L2_SETS 256              +`define L2_SETS 4
    -`define AXI_DATA_WIDTH 32        +`define AXI_DATA_WIDTH 128
    -`define ITLB_ENTRIES 64          +`define ITLB_ENTRIES 8
    -`define DTLB_ENTRIES 64          +`define DTLB_ENTRIES 8
    -`define TLB_WAYS 4               +`define TLB_WAYS 2

Reasons, one per group:

- **`NUM_CORES 1 -> 2` is the whole task.** At one core `l2_cache_arb_stage`
  compiles out its `rr_arbiter` entirely (`generate if (NUM_CORES > 1)`), there
  is no second observer for the invalidate broadcast, and there is no
  arbitration, no fairness and no coherence question left. Every `T_COH_*`,
  every `T_FAIR_*` and `T_MUTEX_L2_READY_ONEHOT` would be vacuous.
- **The cache geometries.** 4 sets x 4 ways of L1D, 4 sets x 2 ways of L2. The
  upstream numbers give an L2 data array of 2048 x 512 bits, which elaborates
  but is not a formal problem. The set count is what the targets index into,
  not what they are about. Upstream's own constraint list is respected: ways
  are 1/2/4/8 (`cache_lru`), sets are powers of two, `L1D_SETS <= 64`
  (`dcache_tag_stage` asserts both), and `L1D_WAYS >= THREADS_PER_CORE`.
- **`THREADS_PER_CORE` was NOT reduced**, deliberately. It is
  `$clog2` -> `l1_miss_entry_idx_t`, which is the request/response **id**, and
  it is the number of entries in each of the three L1 queues. At 4 the id field
  is 2 bits and the outstanding table has something to say; at 2 the whole
  request-response category shrinks.
- **`AXI_DATA_WIDTH 32 -> 128`** makes `BURST_BEATS` 4 instead of 16, so a
  cache-line fill is a 4-beat burst. This is the depth of every AXI-side target
  and of `T_BOUNDRSP_FILL_ANSWERED_IN_4`'s round trip; at 16 beats the memory
  round trip alone is longer than a phase-1 screen will bound-check.
- **TLB sizes** are off the critical path for every target here and only add
  state.

No other file was touched. In particular nothing was deleted for being a
solution hint: Nyuzi ships no formal environment, no `helpers.sv` and no golden
proof, so there was nothing of that kind to scrub.

## Configuration facts the targets depend on

Two of them, recorded because they are not obvious from the assertion text:

- **`L1D_SETS == L2_SETS == 4`**, so `DCACHE_TAG_BITS == $bits(l2_tag_t) == 24`
  and the L2 response address `{tag, set_idx}` splits at the same bit position
  the L1D uses. `T_COH_DINVALIDATE_CLEARS_ALL_L1D` slices the response address
  into an L1D tag and set on that basis. It is how `l1_l2_interface` itself
  does it (`{dcache_tag_stage2, dcache_set_stage2} = response_stage2.address`),
  so the two agree by construction, but a future re-configuration that split
  the two would have to revisit that assertion.
- **`TOTAL_THREADS = 8`**, so `l2_cache_read_stage`'s synchronised-load slot
  index `GLOBAL_THREAD_IDX_WIDTH'({core, id})` is exactly `{core[0], id[1:0]}`
  and no two threads alias onto one sync slot.

## The environment: no assumptions anywhere

The diag declares none, the target file declares none, the cover file declares
none, and `check_assumptions -show` in `tc_elab.tcl` reports from the other
side. Everything an assumption would do is synthesisable RTL in `ft/`:

- The **request stream** is produced by real Nyuzi caches, not by a generator,
  so there is nothing to constrain about it. The pipeline-facing inputs are
  free.
- **`nyuzi_axi_mem`** is the AXI slave. It is the weakest legal responder:
  `s_awready`, `s_wready`, `s_arready` and `s_rvalid` are each gated by an
  unconstrained top-level input, so memory may stall the address phase and any
  beat for any number of cycles. Read data is unconstrained **except on one
  line**: `probe_line` is a register whose only driver is itself, so it keeps
  its arbitrary initial value for the whole trace — a symbolic constant with no
  assumption — and for that one line the model is a real memory whose write
  bursts are stored and replayed. That is what makes
  `T_DATA_WRITEBACK_BEAT_MATCHES_L2_LINE` and the round-trip cover mean
  something.

  The beat-to-lane mapping is the master's, not invented: `m_wdata <=
  writeback_lanes[~burst_offset_nxt]` and `l2bi_data_from_memory[i] =
  fill_buffer[BURST_BEATS-i-1]` both put beat *n* at line lane
  *BURST_BEATS-1-n*, and the model stores and replays at that lane.

The same trick — a self-driving register — supplies the symbolic slot
(`f_core`, `f_id`, `f_cls`), the symbolic byte (`f_byte`) and the symbolic beat
lane (`f_lane`) that the focussed targets are stated on.

## The oracle

`sva/targets_nyuzi_l2_ring_coherence.sv` is bound into the formal top as
`u_targets` and holds ten independent instruments. None of them is a copy of an
RTL structure; the design has no equivalent of the first one anywhere.

1. **The outstanding-request table**, `os_valid[core][id][class]`, filled at
   the admission boundary and read at the response boundary. `id` is the
   requesting *thread* index and three L1 queues use the same id space at once,
   so the key needs `class`:

       class 0  d-cache load    L2REQ_LOAD / L2REQ_LOAD_SYNC, CT_DCACHE
       class 1  i-cache load    L2REQ_LOAD, CT_ICACHE
       class 2  store / cache control

   which is exactly how `l1_l2_interface` demultiplexes a response onto
   `dcache_l2_response_valid` / `icache_l2_response_valid` /
   `storebuf_l2_response_valid`. The request-side and response-side class
   functions are duals.
2. **One symbolic slot** followed in detail — its address, request type,
   cache type and admission/response counts.
3. **In-flight accounting**: admissions minus responses.
4. **An independent reassembly of the AXI read burst**, carried down the four
   registered stages the fill data travels through, which is what makes
   `T_DATA_LOAD_FILL_RESPONSE_MATCHES_AXI` an end-to-end statement.
5. **A shadow queue for `pending_fill_fifo`** — the ordering oracle.
6. **One probed writeback beat**, guarded so it is only read when exactly one
   writeback for the probed line is outstanding.
7. **A per-core arbitration wait counter** and a **global progress counter**,
   the two bounded-safety encodings of the liveness-shaped categories.
8. **The invalidate broadcast followed into both L1 tag arrays.**
9. **A store-merge probe** on one symbolic byte lane.
10. **An L1 miss-queue allocation check.**

Categories 10 (fairness), 11 (bounded response) and 12 (deadlock) are written
as bounded safety, per `CATEGORIES.md`: a counter in the checker and an
assertion on its bound. No `s_eventually` appears anywhere in the package.

The counter bounds and their arguments are in each target's oracle comment.
The two that are stated as candidates rather than certainties, and should be
read as such:

- `T_OCC_INFLIGHT_LE_12` is the tighter of a pair; `T_OCC_INFLIGHT_LE_24` is
  the one that can be argued from the FIFO depths alone.
- `T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_32` picks 32 cycles for a writeback and a
  fill back to back with the memory granting every cycle. That window is
  hand-chosen and is exactly the kind of bound the phase-1 screen exists to
  sort.

## DESIGN_KEEP

    "u_mem\.(w_beat|r_beat|b_pending|mem_wr_line|mem_wr_active|mem_rd_line|mem_rd_active|mem_probe_valid)"

`taskdefs.oracle_keep` reads the `bind` statements in `sva/` and adds
`u_targets\.` and `u_covers\.` automatically, so the checker's own registers do
not need to be named here.

`u_mem` does, and it is the same rule — **preserve the instrument, cut the
design**. `nyuzi_axi_mem` is the environment, not the DUT. Cut at reset, its
burst counters start mid-burst and its ready/valid state starts arbitrary, and
`T_PROTO_AXI_WLAST_ON_LAST_BEAT` and `T_ORDER_AXI_READ_BEATS_IN_SEQUENCE`
compare the master's burst offset against exactly those counters. They would
fail for a reason that is not the design's and that nothing in the design can
correct.

Only the reset-assigned registers are named. `probe_line` and
`mem_probe_data` are deliberately absent: neither has a reset branch, so
`stopat -reset` has no reset value to cut and keeping them would be a no-op
that only inflates the `KEEP_PATTERN design` count in the round log — the same
argument `openpiton_pmesh_order` records for `ref_mem`. Their arbitrary initial
values are the point: `probe_line` is meant to be symbolic, and
`mem_probe_data` is only read through `mem_probe_valid`, which IS kept and IS
reset.

## Verified, and not

**Verified.** `uv run python v6_dataset/elab_local.py --task
nyuzi_l2_ring_coherence` exits 0 with the target file listed in
`lists/tc_elab.files` (no `--extra`). Slang 11.0 reports `0 errors, 0 warnings`
and the elaborated design carries **49 `Assert` and 17 `CoverProperty`**
properties, so no candidate is stranded. The instance census shows every block
in the diagram above present and instantiated — including both
`nyuzi_l1_agent`s and both `l1_l2_interface`s at their distinct `CORE_ID`s.
`taskdefs.TASKS` admits the task, it is in `V5_TASKS`, and
`taskdefs.derive_targets` finds all 49 labels.

**Not verified.** Nothing here has been through Jasper; per the task
constraints no cluster job was launched. Two things a first Jasper load should
be watched for:

- **`$random()` in the SRAM models.** `sram_1r1w`, `sram_2r1w` and their
  `initial` blocks use `DATA_WIDTH'($random())` for the read-during-write
  don't-care and for array initialisation. Slang accepts it. If Jasper refuses
  it, the fix is a scrub of those two files, not a change to the cut. It is
  left byte-identical until there is evidence it has to change.
- **Nyuzi's own 139 unlabelled immediate `assert(...)` statements** inside
  `always_ff` blocks. They elaborate as properties and are counted by
  `ELABORATION_CENSUS assertions=`, which is therefore NOT the candidate count.
  The diag censuses `u_targets.T_*` by regex for exactly this reason. They are
  left in place: they are upstream design intent, and several of the authored
  targets are labelled restatements of the same claims at the subsystem
  boundary rather than inside one block.

No target has been proven, disproven or screened. Which of the 49 land in the
`undetermined`-with-reachable-covers band is the phase-1 screen's answer, not
this file's.

## Scrubbed after the first Jasper screen failed

`rtl/nyuzi/defines.svh`, 2 lines (435 and 452). `AXI_ADDR_WIDTH` is declared at
line 409 INSIDE `package defines`, which ends at 411. `axi4_interface` at line
430 is OUTSIDE that package and referenced the name unqualified. Slang resolves
it and reports nothing; Verific does not, and the first screen died with
7 errors:

    ERROR (VERI-1128) defines.svh(435): 'AXI_ADDR_WIDTH' is not declared
    ERROR (VERI-1952) defines.svh(435): range must be bounded by constant expressions
    ERROR (VERI-1072) defines.svh(469): interface 'axi4_interface' is ignored
                                        due to previous errors

Both references are now `defines::AXI_ADDR_WIDTH`. Value unchanged, package
contents unchanged, only the two out-of-package uses are qualified. The
alternative -- moving the parameter out of the package -- would have changed
what the package exports, which is a larger change for the same effect.

This is a Jasper-only failure: `v6_dataset/elab_local.py` passed this package
before and after the scrub, because Slang never had a problem with it.
