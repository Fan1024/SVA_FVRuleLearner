# corundum_dma_path provenance

assembled: 2026-08-19

source: **there is no source package.** This is not a port. The RTL is upstream
Corundum, copied byte-identical out of a working clone; the formal top, the
environment, the oracle, the candidate targets and everything under `lists/`
were written here.

    upstream: github.com/corundum/corundum
    clone:    an upstream corundum clone
    commit:   1ca0151b97af85aa5dd306d74b6bcec65904d2ce  (2023-12-02)

top: `corundum_dma_path_ft`
environment: `lists/diag_corundum_dma_path.tcl` (task `diag_corundum_dma_path`,
**NO assumptions** -- see "The environment is built, not assumed" below)
candidates: 50 `T_*` assertions and 25 `C_*` covers in
`sva/targets_corundum_dma_path.sv`, listed with category and intent in
`lists/targets.txt`.

## What the subsystem is

Corundum's mqnic descriptor / DMA / completion datapath, the chain a NIC walks
for every packet it sends: a descriptor is dequeued from a host ring, fetched
over DMA into a local RAM, streamed out as an AXI-Stream descriptor, turned
into work, and answered with a completion enqueued into a second host ring and
DMA-written back. Every boundary in that chain is a queue, and several
operations are in flight at once.

Instantiated here, at the smallest geometry that keeps every stage:

| upstream file | lines | instances | what it is |
| --- | --- | --- | --- |
| `fpga/common/rtl/desc_fetch.v` | 651 | 1 | descriptor fetch: a 4-entry in-order operation table, a DMA read per fetch, a descriptor RAM and an AXI-Stream source |
| `fpga/common/rtl/queue_manager.v` | 686 | 2 | descriptor rings: queue RAM, a 4-entry operation table, dequeue request/response/commit, AXI-Lite config |
| `fpga/common/rtl/cpl_write.v` | 480 | 1 | completion write: a 4-entry operation table, an enqueue per completion, a DMA write per completion |
| `fpga/common/rtl/cpl_queue_manager.v` | 718 | 2 | completion rings: same shape, with a full check and a phase bit |
| `fpga/lib/pcie/rtl/dma_psdpram.v` | 165 | 1 (inside `desc_fetch`) | the descriptor RAM |
| `fpga/lib/pcie/rtl/dma_client_axis_source.v` | 568 | 1 (inside `desc_fetch`) | RAM to AXI-Stream |
| `fpga/lib/pcie/rtl/priority_encoder.v` | 92 | 2 | the response arbiters inside `desc_fetch` and `cpl_write` |

3,360 lines of upstream RTL, 6 upstream top-level instances (10 counting the
two nested inside `desc_fetch` and the two encoders). Nothing was cut down:
the full chain elaborates, which is the outcome the task brief asked for in
preference to the descriptor-fetch-only fallback.

The geometry: `PORTS=2`, one ring index bit (2 rings per manager, so 4
descriptor rings and 4 completion rings), 4-entry rings, 8-byte descriptors in
blocks of 2 (so a descriptor is two AXI-Stream beats), 8-byte completions,
4-entry operation tables everywhere, one 64-bit RAM segment, 16-bit ring
pointers. `PORTS=1` is not expressible -- `SELECT_WIDTH = $clog2(PORTS)` is
zero and the select port's range becomes `[-1:0]` -- so two of everything is
the floor, and it is also what puts a real arbiter in the middle.

## What was carried over unchanged

Byte-identical to the clone, verified by `cmp`:

    rtl/corundum/desc_fetch.v
    rtl/corundum/cpl_write.v
    rtl/corundum/queue_manager.v
    rtl/corundum/cpl_queue_manager.v
    rtl/corundum/dma_psdpram.v
    rtl/corundum/dma_client_axis_source.v
    rtl/corundum/priority_encoder.v

Nothing was scrubbed. No `+define+`, no `+incdir+`: these seven files have no
`include and read no macro they do not define themselves.

`priority_encoder.v` was taken from `fpga/lib/pcie/rtl/`, the copy that ships
next to the DMA library the other two `fpga/lib` files come from. The clone
carries two other identical-looking copies under `fpga/lib/axi/rtl/` and
`fpga/lib/eth/lib/axis/rtl/`; only one may be analyzed or the module is
declared twice.

## What was written for this package

### `ft/corundum_dma_path_ft.sv` -- the formal top and the environment

Five authored modules, 1,457 lines with comments:

- **`corundum_dma_path_ft`** wires the chain together and holds the ring credit
  accounting.
- **`corundum_axil_qcfg`** (x4, one per queue manager) is the driver. Eight
  AXI-Lite writes per ring bring it up -- disable, base low, base high, size,
  linked queue index, producer pointer, consumer pointer, enable -- and after
  that it sits in RUN and bumps one pointer by one whenever the environment
  asks and its own credit account allows: the producer pointer on a descriptor
  ring (software posting a descriptor), the consumer pointer on a completion
  ring (software retiring a completion). The shadow pointer is the module's
  own; it never reads one back.
- **`corundum_host_rd`** is the bounded descriptor-side host memory. A DMA read
  descriptor names a host address, a RAM address, a length and a tag; it writes
  `len` bytes of `host_word(byte address) = {a[31:0], ~a[31:0]}` into the
  design's descriptor RAM, waits 0..3 cycles (a free two-bit delay latched at
  accept) and returns status.
- **`corundum_desc_engine`** is what an mqnic TX engine reduces to here. It
  remembers which completion ring each successful fetch was told to write to,
  consumes the descriptor stream, and on the last beat turns the descriptor
  into one completion write request carrying its tag and last word.
- **`corundum_host_wr`** is the bounded completion-side host memory. It reads
  the completion word out of `cpl_write`'s own data table over the DMA RAM read
  port, publishes it as `host_cpl_*` -- the far observation point of the whole
  chain -- waits 0..3 cycles and returns status.

### `sva/targets_corundum_dma_path.sv` -- the oracle and the candidates

Bound into the formal top. Six independent oracles, none of them a restatement
of the design's own logic:

1. a **per-port shadow queue of dequeue requests**, this file's own pointers
   and payload copy, checked against the response the manager presents;
2. **two started-fetch queues** -- one caller tag per successful dequeue
   response, one {host address, length} per DMA read descriptor -- both popped
   at the last beat of a descriptor, which is where the AXI-Stream is compared
   with the fetch that produced it;
3. **`host_word()` recomputed**. The checker never reads the descriptor RAM. It
   recomputes what the environment must have written from the address it saw on
   the DMA read descriptor wire, and compares it with what came out of the
   AXI-Stream three modules later;
4. **tag-keyed outstanding sets** for both DMA channels and for all four
   managers' operation tags -- the `l15_l2_mshr_onehot` pattern, which is what
   catches a reused tag or an unsolicited completion;
5. **ring accounting**: posts and takes per descriptor ring, starts and
   retirements per completion ring, counted by the checker from boundary events
   only;
6. **saturating wait counters**. Fairness, bounded response and deadlock are
   written as bounds on those counters. There is no `s_eventually`, no `F` and
   no `G F` anywhere in the package -- every candidate is a safety property.

50 `T_<CATEGORY>_<NAME>` assertions across 14 of the 15 categories, 25 `C_*`
covers with at least one per category used.

**Category 15, coherence, is not used, and that is a result rather than an
omission.** There is no second agent holding a permission on a line anywhere in
this subsystem: the two queue managers own disjoint ring sets, and the two DMA
channels do not share a target. The nearest thing to a coherence obligation is
`T_ALLOC_QM0_OPSET_SUBSET_OF_DESIGN`, which is filed under allocator
discipline.

### `lists/` -- entirely new

    lists/tc_elab.files            the one analyzed, appendable list.
    lists/tc_elab.tcl              the elaboration recipe. There is no upstream
                                   `tcl/setup.tcl` to derive it from; it
                                   follows the shape of the other ports in
                                   `tasks/` and adds only the clock name
                                   (`clk`) and the reset (`rst == 1'b1`,
                                   ACTIVE HIGH, Corundum's convention).
    lists/diag_corundum_dma_path.tcl  defines `setup_diag_corundum_dma_path`,
                                   declares no assumptions, prints the target
                                   and cover census.
    lists/reset_modes.tcl          `rm_all_registers` + `_rm_apply_reset`,
                                   which is all `v5/cex.tcl` calls, on
                                   `rst == 1'b1`.
    lists/targets.txt              one `label<TAB>category<TAB>intent` line per
                                   candidate, checked to match the SVA labels
                                   exactly.
    lists/proofgrid_profiles.tcl   copied verbatim from
    lists/vendor/iterdev_utils.tcl `tasks/verilog_axis_arb_mux_order/lists/`;
                                   both are task-agnostic.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on the first
run. It is derived, not authored, and is gitignored.

The repo's `.gitignore` tracks the authored half of a task package and leaves
the upstream tree out; the block appended for this one tracks `lists/`, `sva/`,
`ft/`, `taskdef.json` and this file, and leaves `rtl/corundum/` on disk only,
the same rule the other nine packages follow.

## The environment is built, not assumed

`lists/diag_corundum_dma_path.tcl` declares **no assumptions**, and neither does
any file in the package. Everything a constraint would normally say is
synthesisable logic in the formal top instead:

- the request generator holds one fetch request at a time with a stable
  payload, so no AXI-Stream source-stability assumption is needed;
- the driver brings all four rings up over AXI-Lite before the first request is
  offered (`all_configured` gates `desc_fetch.enable` and `cpl_write.enable`),
  so no assumption about queue configuration is needed;
- the driver is the only writer of a producer or consumer pointer and it bumps
  one by one only while its own credit account allows, so no assumption keeps
  it from over-filling or over-draining a ring;
- both host-memory responders answer within a bounded number of cycles and the
  descriptor sink cannot stall more than three cycles running, so the fairness,
  bounded-response and deadlock candidates have a real bound rather than an
  assumed one. This is load-bearing: with an unbounded responder every one of
  those eight candidates is false.

The consequence for a reader of a result is that these numbers are obtained
under a *built* environment, and a built environment is inside the reset cut's
scope. That is what `design_keep` is for.

## `design_keep`, and why each entry is there

    "corundum_dma_targets\\."     the oracle's own state
    "\\.env_[a-z0-9_]+\\."        the environment submodules' own state
    "ftenv_"                      the environment state in the formal top

`v5/cex.tcl:ENTER_FRA_KEEP` cuts **every** register in the elaborated design
that no keep pattern matches -- the checker's and the formal top's included.
The rule is: preserve the instrument, cut the design.

1. **`corundum_dma_targets\.`** -- the bound checker. Every one of the 50
   candidates reads it: the shadow queues, the tag sets, the ring counters and
   the saturating timers ARE the oracle. Cut, they start arbitrary and the
   targets are falsified at cycle 0 for a reason nothing in the design can
   correct.
2. **`\.env_[a-z0-9_]+\.`** -- `env_cfg_dq0/1`, `env_cfg_cq0/1`, `env_host_rd`,
   `env_host_wr`, `env_engine`. Cut, the driver's shadow pointers and its
   init-sequence state start arbitrary, so it can post into a ring it never
   configured or claim it has finished configuring when it has not; and the
   descriptor host memory can start mid-transfer with a latched address it
   never received, writing a word the checker cannot predict. Both falsify
   conservation and data-integrity candidates through the *environment*, which
   no design-side helper can reach.
3. **`ftenv_`** -- the request generator's held request, the four ring credit
   counters and the operation-tag-to-ring map that decides which ring a
   completion commit is credited to. Cut, the credit accounts start arbitrary
   and the driver over-drains a completion ring, which sends
   `T_BOUND_CPL_RING_OCCUPANCY` negative for an environment reason.

Everything else is cut: all seven upstream modules, all ten instances, both
queue RAMs, both operation-table sets, the descriptor psdpram, the AXI-Stream
source's pipeline. That is where the difficulty is, and it is the whole point
-- proving that beat *j* of a descriptor is the host word at *(fetch address +
8j)* needs an inductive invariant that spans `desc_fetch`'s operation table,
the psdpram contents, `dma_client_axis_source`'s read state and the queue
manager's pointer arithmetic, none of which the target mentions.

All three patterns match at least one register, so none can trip `cex.tcl`'s
"design keep pattern matched nothing" FAIL.

## The gate

    uv run python v6_dataset/elab_local.py --task corundum_dma_path
    OK: corundum_dma_path elaborates                       (exit 0)

    uv run python -c "import taskdefs; print('corundum_dma_path' in taskdefs.TASKS)"
    True

Slang 11.0 reports **0 errors and 0 warnings** over the whole package.

## Not verified

**Nothing here has been simulated or elaborated in Jasper.** No simulator is
installed on this machine (`iverilog`, `verilator`, `vcs`, `xrun` are all
absent) and no cluster job was launched. What has been checked is Slang
elaboration, plus a desk check of the parameter constraints the upstream
modules assert at runtime in `initial` blocks -- which no elaborator evaluates,
so they were read and satisfied by hand:

- `desc_fetch`: `DMA_TAG_WIDTH(4) >= CL_DESC_TABLE_SIZE(2)`,
  `QUEUE_REQ_TAG_WIDTH(4) >= CL_DESC_TABLE_SIZE` and `>= REQ_TAG_WIDTH(4)`,
  `AXIS_KEEP_WIDTH*8 == AXIS_DATA_WIDTH`, `DESC_SIZE(8)` a power of two;
- `cpl_write`: `DMA_TAG_WIDTH(4) >= CL_DESC_TABLE_SIZE+1(3)`,
  `SEG_ADDR_WIDTH(3) >= CL_DESC_TABLE_SIZE(2)`,
  `SEG_COUNT*SEG_DATA_WIDTH(64) >= CPL_SIZE*8(64)`;
- both queue managers: `OP_TAG_WIDTH(2) >= CL_OP_TABLE_SIZE(2)`,
  `AXIL_DATA_WIDTH == 32`, `AXIL_ADDR_WIDTH >= QUEUE_INDEX_WIDTH+5` (and `+4`
  for the completion side), `PIPELINE(2) >= 2`;
- `dma_psdpram` inside `desc_fetch`: `SEG_ADDR_WIDTH(3) >= INT_ADDR_WIDTH`,
  where `SIZE = 4*8*2 = 64` bytes over 8-byte segments gives 3;
- `dma_client_axis_source` inside `desc_fetch`: word sizes match at 8,
  `RAM_ADDR_WIDTH(6) == SEG_ADDR_WIDTH+clog2(SEG_COUNT)+clog2(SEG_BE_WIDTH)`,
  `AXIS_DATA_WIDTH(64) <= SEG_COUNT*SEG_DATA_WIDTH(64)` and
  `AXIS_DATA_WIDTH * 2**clog2(PART_COUNT=1) == SEG_COUNT*SEG_DATA_WIDTH`.

The AXI-Lite register encodings the driver writes (`0x400001zz` enable,
`0x8002zzzz` size, `0xC0zzzzzz` linked index, `0x8080zzzz` producer,
`0x8090zzzz` consumer) and the register addressing (`awaddr >> 5` for the
descriptor side, `>> 4` for the completion side) were read out of the two
managers' `casez` blocks, not guessed. They have not been exercised.

## What is expected to be wrong

Recorded here because a number published without its known caveats is worse
than no number. These are the candidates most likely to come back `cex` from
the phase-1 screen:

- **`T_RESET_DF_TABLE_IDLE`, `T_RESET_QM_OP_TABLES_IDLE`.** Both are
  assertions about design registers in the first cycle out of reset, and the
  reset cut starts those registers arbitrary. Under FRA they are falsified for
  a reason nothing can correct. They are here because the category exists and
  saying so is a result; expect them to be dropped.
- **The eight bounded counters** (`T_FAIR_*`, `T_BOUNDRSP_*`,
  `T_DEADLOCK_*`). The bounds -- 96 cycles for a blocked channel, 255 for a
  round trip -- are estimates from counting handshakes along the chain, not
  measurements. If they are too tight the screen returns `cex` and the right
  correction is a larger constant, not a different property.
- **`T_LIFECYCLE_DQ0_BASE_STABLE_WHILE_ENABLED`** relies on the driver never
  overlapping two AXI-Lite writes. It does not overlap them -- it waits for
  `bvalid` -- but the driver reads `bvalid` from a cut register, so an
  arbitrary early `bvalid` can break the serialisation. Design-side and
  repairable, but it is the one lifecycle candidate whose antecedent the
  environment can spoil.
- **`T_CONSERV_DEQ_NOT_MORE_THAN_POSTED`** is stated as "the 8-bit modular
  difference posted-minus-taken never has its top bit set", which detects a
  violation only while the true difference stays inside +/-128. Every trace the
  screen will reach is far shorter than that, but the statement is not the
  unconditional one.
- **`T_DATA_CPL_PAYLOAD_TO_HOST`** compares against `cs_data[hw_slot]` without
  requiring the slot to be live; if `cpl_write` DMA-writes a slot that was
  never allocated the comparison reads an unwritten checker entry.
  `T_ALLOC_CPL_DMA_WRITE_SLOT_LIVE` is the candidate that says that cannot
  happen, so the pair should be screened together.
