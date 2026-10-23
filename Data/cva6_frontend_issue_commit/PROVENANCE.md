# cva6_frontend_issue_commit provenance

assembled: 2026-08-19

sources (copied out of; neither tree was modified):

    an upstream cva6 clone            openhwgroup/cva6, `core/` only
    an upstream common-cells clone    pulp-platform common_cells

There was **no source task package**. Like `tasks/cva6_cache_subsystem`, this
package was assembled from bare upstream RTL: the formal top, the two memory
models, the configuration package, the target assertions, the oracles and the
whole of `lists/` are task-authored. Unlike that package, **nothing under
`rtl/` is authored** -- all 57 files there are byte-identical copies, verified
with `cmp` (57 compared, 0 differences).

top: `cva6_frontend_issue_commit_ft`
environment: `lists/diag_cva6_frontend_issue_commit.tcl` (task
`diag_cva6_frontend_issue_commit`, **NO assumptions**)
targets: 50 `T_<CATEGORY>_<NAME>` candidates in
`sva/targets_cva6_frontend_issue_commit.sv`, listed with category and intent in
`lists/targets.txt`, and named in the same order in `taskdef.json`.
covers: 41 `C_<NAME>` in `sva/covers_cva6_frontend_issue_commit.sv`. They are
not targets; they are what `COVER_DEPTH` counts.

## The cut: five pipeline stages, four buffers between them

`tasks/cva6_cache_subsystem` takes CVA6's write-through L1 pair, 27 files, and
covers only the caches. This is the **core pipeline** cut of the same upstream,
and it shares no design file with it:

    frontend            PC generation, BHT (32 entries, 3-bit history),
      |                 RAS (2), instr_scan x4, instr_realign, and the
      |                 INSTRUCTION QUEUE -- four 4-deep instruction fifos
      |                 plus a 2-deep branch-address fifo
      v   IF/ID handover      fetch_valid_if_id / fetch_ready_id_if
    id_stage            compressed decoder + decoder per issue port, and ONE
      |                 REGISTERED ISSUE SLOT per port
      v   ID/ISSUE handover   issue_entry_valid_id_issue / issue_instr_issue_id
    issue_stage         the SCOREBOARD: 8 entries, allocated IN ORDER at
      |                 `issue_pointer_q`, retired IN ORDER at
      |                 `commit_pointer_q`, COMPLETED OUT OF ORDER by five
      |                 writeback ports; plus issue_read_operands with the
      |                 32-entry GPR file, six RAW checkers and the forwarding
      |                 network
      v   FU issue            fu_data_id_ex, alu/alu2/branch/csr/mult/lsu valid
    ex_stage            2 ALUs (one bypassed), branch unit, CSR buffer,
      |                 mult + serdiv, cvxif_fu, and the LSU: lsu_bypass, a
      |                 2-entry LOAD BUFFER, a 4+4-entry STORE BUFFER
      |                 (speculative queue + non-speculative commit queue),
      v                 and PMP (8 entries)
      |   writeback          trans_id_ex_id / wt_valid_ex_id / wbdata_ex_id
    commit_stage        in-order retirement on 2 commit ports

with `controller` (the flush controller) and `csr_regfile` (trap and CSR
state, including the PMP entries) alongside, wired exactly as `core/cva6.sv`
wires them.

**Where the buffering sits**, which is the point of the package: the
instruction queue between fetch and decode, the ID slots between decode and
issue, the 8-entry scoreboard between issue and execute, and the load and
store buffers between execute and memory. An inductive invariant for
`T_CONSERV_SB_OCCUPANCY_MATCHES_LEDGER` has to span all four.

## What was carried over unchanged

52 analyzed source files plus 5 include files, all byte-identical:

    rtl/cva6/include/    config_pkg.sv  cv32a65x_config_pkg.sv  riscv_pkg.sv
                         ariane_pkg.sv  build_config_pkg.sv
                         rvfi_types.svh  cvxif_types.svh
    rtl/cva6/frontend/   frontend.sv  instr_queue.sv  instr_scan.sv  bht.sv  ras.sv
    rtl/cva6/            instr_realign.sv  id_stage.sv  compressed_decoder.sv
                         decoder.sv  cvxif_compressed_if_driver.sv
                         issue_stage.sv  scoreboard.sv  issue_read_operands.sv
                         ariane_regfile_ff.sv  raw_checker.sv
                         cvxif_issue_register_commit_if_driver.sv
                         ex_stage.sv  alu.sv  alu_wrapper.sv  branch_unit.sv
                         csr_buffer.sv  mult.sv  multiplier.sv  serdiv.sv
                         cvxif_fu.sv  load_store_unit.sv  load_unit.sv
                         store_unit.sv  store_buffer.sv  lsu_bypass.sv
                         commit_stage.sv  controller.sv  csr_regfile.sv
                         cva6_fifo_v3.sv
    rtl/cva6/pmp/        pmp.sv  pmp_entry.sv  pmp_data_if.sv
    rtl/common_cells/    cc_pkg.sv  cc_lzc.sv  cc_popcount.sv
                         cc_shift_register.sv  cc_shift_register_gated.sv
                         cc_unread.sv
                         deprecated/lzc.sv  deprecated/popcount.sv
                         deprecated/shift_reg.sv  deprecated/unread.sv
                         include/common_cells/assertions.svh
                         include/common_cells/registers.svh
                         include/common_cells/deprecated/registers.svh

**Nothing was scrubbed.** Not one line of upstream RTL was edited, deleted or
commented out -- including CVA6's own `pragma translate_off` assertions, which
are left where they are (see the census below).

Three deliberate omissions, all of them "this module is not instantiated at
this configuration", checked against the elaborated hierarchy rather than
assumed: `btb.sv` (`BTBEntries = 0`), `macro_decoder.sv` (`RVZCMP = 0`) and
`amo_buffer.sv` (`RVA = 0`). They were copied first, found to have no
instance, and removed so the file list contains no dead source.

The one define story: `PITON_ARIANE` is NOT defined, so `ariane_pkg`'s
`` `include "l15.tmp.h" `` is out. No `VERILATOR`, `SYNTHESIS` or `SIMULATION`
either. That is a define, not an edit.

### No common_cells shim, unlike cva6_cache_subsystem

CVA6 instantiates `lzc`, `popcount` and `shift_reg` -- the PRE-RENAME
pulp-platform names. `tasks/cva6_cache_subsystem` authored
`rtl/support/cva6_common_cells_shim.sv` to bridge that. It did not need to:
this common_cells checkout ships upstream compatibility wrappers under exactly
those names in `src/deprecated/`, and this package uses them. Both the wrapper
and the cell are byte-identical upstream files, so the `lzc` MODE default
(trailing zeros, which is what CVA6's `load_unit`, `alu`, `serdiv`,
`instr_queue` and `pmp_entry` rely on) is upstream's own choice rather than an
authored one.

## The configuration: upstream cv32a65x, UNCHANGED

`ft/cva6_pipe_fv_pkg.sv` computes
`build_config_pkg::build_config(cva6_config_pkg::cva6_cfg)` from
`cv32a65x_config_pkg` with **no field overridden**. Exactly one config package
may be in the list -- every config file in the CVA6 tree declares `package
cva6_config_pkg` -- and this is the one, chosen because it is the only
in-tree configuration that is simultaneously superscalar, MMU-less and
FPU-less.

Read out of an elaborated `$info`, not computed by hand:

    XLEN 32   VLEN 32   PLEN 34   GPLEN 34
    SuperscalarEn 1  NrIssuePorts 2  NrCommitPorts 2  NrALUs 2
    SpeculativeSb 1  ALUBypass 1     NrRgprPorts 4
    NR_SB_ENTRIES 8  TRANS_ID_BITS 3  NrWbPorts 5
    FETCH_WIDTH 64   INSTR_PER_FETCH 4  LOG2_INSTR_PER_FETCH 2
    NrLoadBufEntries 2  DcacheIdWidth 1  MaxOutstandingStores 7
    RVC 1  RVB 1  RVZCB 1  RVZCMP 0  RVZCMT 0  RVA 0  ZKN 0  FpPresent 0  RVV 0
    CvxifEn 1  MmuPresent 0  RVS 0  RVU 0  DebugEn 0  Sdtrig 0  PerfCounterEn 0
    BHTEntries 32  BHTHist 3  BTBEntries 0  RASDepth 2  NrPMPEntries 8
    DCACHE_INDEX_WIDTH 10  DCACHE_TAG_WIDTH 24  NonIdemPotenceEn 0  TvalEn 0

## VACUITY: does the parameterisation compile out the logic under test?

The failure mode to avoid is the one that forced `NUM_CORES 1 -> 2` in the
nyuzi package: a parameter at which the contended structure vanishes and every
target about it is vacuously true. For CVA6 the two numbers that matter are
the scoreboard depth and the number of functional units, and both were checked
against the ELABORATED design, not against the config file:

| what | value | why it is not vacuous |
| --- | --- | --- |
| scoreboard entries | **8** | `mem_q` is `[7:0]`, `issue_pointer_q`/`commit_pointer_q` are 3 bits and wrap. At 1 or 2 entries the pointer arithmetic and the "full" rule are trivial and every ordering target collapses. |
| issue ports | **2** | `issue_full[1]` (the two-slots-available rule) exists only when `SuperscalarEn`. At 1 port `T_ORDER_ISSUE_ACK_IN_ORDER` and half the allocator targets have no second port to talk about. |
| commit ports | **2** | `scoreboard.gen_commit_ports` computes `num_commit = ack[1] + ack[0]` only when `NrCommitPorts == 2`; at 1 the in-order dual-retire statements are vacuous. |
| writeback ports | **5** | FLU / STORE / LOAD / FPU / X. Three of them are live (`FpPresent = 0` leaves FPU dead, and the CVXIF port carries only rejections -- see below), so writeback really is out of order: a load answered by the cache model at cycle t+8 retires an entry younger than an ALU result at t+1. |
| ALUs | **2** | `alu_wrapper` instantiates `alu` twice; `NrALUs = 1` would make `alu2_valid_id_ex` dead and `T_MUTEX_*` weaker. |
| load buffer | **2** | two loads outstanding at once, so `T_UNIQ_LOAD_ID_NOT_REUSED_WHILE_OUTSTANDING` and `T_CONSERV_LOAD_ID_SET_MATCHES_BUFFER` have two ids to distinguish. At 1 entry `ldbuf_windex` is a constant and both are trivial. |
| store buffer | **4 + 4** | speculative and commit queues, both with counters. |
| instruction queue | **4 fifos x 4 deep** | `INSTR_PER_FETCH = 4` because `FETCH_WIDTH = 64` and `RVC = 1`. |
| PMP entries | **8** | `i_pmp_entry` has 8 instances, so the fetch and load/store permission path is real logic rather than a constant. |

Instance counts read out of the elaborated AST: `i_scoreboard` 1,
`i_fifo_instr_data` 4, `i_instr_scan` 4, `i_pmp_entry` 8, `i_load_unit` 1,
`store_buffer_i` 1, `i_ariane_regfile` 1.

**Can each target fail?** Every target is stated against an independent oracle
or a hand-chosen bound, not against a restatement of the RTL. The oracles are
driven only from handshakes; the design has no ledger, no program-order pc
array and no register-file shadow anywhere. `sva/covers_*.sv` names the
scenario each family constrains (`C_SB_FULL`, `C_DUAL_COMMIT`,
`C_WRITEBACK_OUT_OF_ORDER`, `C_TWO_LOADS_OUTSTANDING`, `C_MISPREDICT`,
`C_DROPPED_COMMIT`, `C_STORE_SPEC_QUEUE_FULL`, ...), and a target whose covers
do not hit is one the screen should drop. **The covers have NOT been run** --
see "Not verified".

## UPSTREAM ASSUMPTIONS: what survives elaboration

CVA6 ships its own SVA. Counted in the elaborated AST (Slang, all files, no
`--ignore-unknown-modules`):

    concurrent assertions in `u_targets`  50   <- this package's targets
    concurrent assertions in `u_covers`   41   <- this package's covers
    concurrent assertions elsewhere       45   <- UPSTREAM CVA6
    immediate assertions                  32   <- UPSTREAM CVA6

so the census is **NOT** 50 + 41. The difference is 45 concurrent and 32
immediate upstream statements, and they are:

    issue_stage_i.i_scoreboard                    29   (25 of them the
                                                        NrWbPorts x NrWbPorts
                                                        pairwise trans_id
                                                        check, plus 2 commit
                                                        and 2 issue)
    ex_stage_i.lsu_i.i_store_unit.store_buffer_i   4
    ex_stage_i.lsu_i.i_load_unit                   3
    i_frontend.i_instr_queue                       2
    i_frontend.i_instr_queue.i_fifo_address        2
    i_frontend.i_instr_queue.i_fifo_instr_data     2
    issue_stage_i.i_issue_read_operands            2
    csr_regfile_i                                  1

**Every one of them is an `assert`. There is not one `assume` and not one
`cover` in the upstream sources this package carries.** Checked by reading the
`assertionKind` of every property in the elaborated AST, which comes out
exactly `{ConcurrentAssertion: Assert 95, ConcurrentAssertion: CoverProperty
41, ImmediateAssertion: Assert 32}` -- 95 = 50 mine + 45 upstream, 41 = mine,
32 = upstream, **0 assumes**. The only `assume` text anywhere under `rtl/` is
the definition of the unused `ASSUME` macro in
`common_cells/include/common_cells/assertions.svh`; the one macro any source
here instantiates is `ASSERT_INIT` in `cc_lzc`, which is an immediate assert.
So no upstream statement can assume away
the behaviour the targets test, and the only effect of leaving them in is that
Jasper's own census is larger than this package's.

They all sit inside `pragma translate_off` / `synthesis translate_off`
regions. Slang skips only the format it is told about
(`--translate-off-format synopsys,translate_off,translate_on`, set by
`taskdefs.slang_args`), which is why the 45 and 32 show up locally. Whether
Jasper skips a `pragma translate_off` region is a property of that tool, so
`lists/tc_elab.tcl` PRINTS `ELABORATION_CENSUS` rather than predicting it.

Two of this package's targets deliberately overlap upstream ones and are worth
knowing about when reading a result: `T_MUTEX_WRITEBACK_TRANS_ID_UNIQUE` is
the FLU/LOAD case of the scoreboard's own pairwise check, and
`T_MUTEX_INSTR_QUEUE_SELECT_ONEHOT` is upstream's `output_select_onehot`
strengthened from `$onehot0` to `$onehot`.

## What was authored, and why each piece had to be

### `ft/cva6_pipe_fv_pkg.sv`

`core/cva6.sv` declares the pipeline's interface record types as `localparam
type` entries in its own parameter list and hands them to every stage. The cut
starts at `frontend` and ends at `commit_stage`, so `cva6.sv` is not part of
it and the types have to be restated. Every typedef is field for field the one
in `core/cva6.sv` lines 36-230: `branchpredict_sbe_t`, `exception_t`, the four
icache records, `fetch_entry_t`, `jvt_t`, `scoreboard_entry_t`, `writeback_t`,
`bp_resolve_t`, `irq_ctrl_t`, `lsu_ctrl_t`, `cbo_t`, `fu_data_t`, the two
dcache records, the two RVFI probe records and the thirteen CVXIF records
(built from upstream's own `cvxif_types.svh` / `rvfi_types.svh` macros, which
is why those two `.svh` files are carried).

### `ft/cva6_frontend_issue_commit_ft.sv`

The formal top. Its body is `core/cva6.sv` lines 349-1408 with the four blocks
that are not in the cut removed -- the cache subsystem, the accelerator
dispatcher, the performance counters and the RVFI/tracer probes -- and the
signals they drove supplied by the models below. The seven stage
instantiations (`frontend`, `id_stage`, `issue_stage`, `ex_stage`,
`commit_stage`, `csr_regfile`, `controller`) and the writeback-port muxing are
copied port for port, with the source line ranges marked in comments.

`boot_addr_i` is the constant `32'h8000_0000` and `hart_id_i` is 0: neither is
a pipeline behaviour and both would only add symbolic state. `irq_i`, `ipi_i`,
`time_irq_i` and `debug_req_i` are free inputs of the formal top, so an
interrupt may arrive at any time and the trap path is exercised.

### `ft/cva6_fv_icache.sv`

One outstanding fetch, answered with a **free 64-bit word**, so every
instruction encoding the two decoders can see is reachable. It obeys the two
rules the frontend depends on -- a response carries the vaddr of the request
it answers, and `kill_s1` / `kill_s2` withdraw a request that is then never
answered -- and it drives the address-translation handshake the real
`cva6_icache` drives, so a PMP denial comes back as an instruction access
fault exactly as upstream.

### `ft/cva6_fv_dcache.sv`

The load port and the store port. The rule it must keep, read out of
`load_unit.sv` rather than assumed: a load-buffer entry is allocated by
`data_req & data_gnt` and freed **only** by a `data_rvalid` carrying its
`data_rid`; `kill_req` does not free it, it only marks it flushed. So every
granted load is answered exactly once, killed or not. A model that dropped
killed loads would wedge the LSU after two kills for a reason that is the
environment's. Responses may come back in either order (`fv_ld_sel_i` picks),
which is what a write-through cache does when one load hits and the other
misses; read data is a free input.

### Bounded latency is a property of the models, not an assumption

Each model refuses for at most `MAX_WAIT = 8` consecutive cycles and answers a
pending request within 8. This lives in `ft/`, where it can be read, for the
same reason the cache package's AXI slave does: a memory that may refuse for
ever is not a memory, and with a free-running responder every bounded-response,
fairness and deadlock statement above it is false for a reason that has nothing
to do with the pipeline. **No assumption is declared anywhere in this
package**, and the diag prints `diagnostic_assumption_count=0`.

### `sva/targets_*.sv` -- six oracles and 50 candidates

The oracles are driven from HANDSHAKES ONLY -- the IF/ID handover, the
ID/ISSUE handover, the commit acknowledge, the flush lines, the five writeback
ports and the two memory ports -- and each keeps its own storage:

1. **the instruction ledger**: its own issue pointer, commit pointer, live set
   and occupancy counter, plus its own copy of the decoded pc / rd / fu per
   position and its own record of which writeback each position took. The
   design has no such structure; the scoreboard's `mem_q` and pointers are
   what the ledger is compared against, never read into it.
2. **one symbolic scoreboard entry** followed from allocation to retirement,
   with a retirement counter and an age counter.
3. **a register-file shadow** of one symbolic architectural register.
4. **an IF/ID occupancy counter.**
5. **a load-id set and a store-queue counter.**
6. **five saturating wait counters** -- the bounded-safety encoding of
   fairness, bounded response and deadlock freedom. No `s_eventually` and no
   `F` appears anywhere in this package.

`sym_id_q` and `sym_rd_q` are registers whose only driver is themselves: under
any reset scheme they hold their arbitrary initial value for the whole trace,
which is a symbolic constant obtained WITHOUT writing an assumption.

## Environment restrictions -- what this package does NOT explore

Recorded here because they change how good the search is, not what a number
means, and a reader of a result needs them.

* **The CVXIF coprocessor accepts nothing.** `CvxifEn = 1` in this
  configuration, so `cvxif_fu`, `cvxif_compressed_if_driver` and
  `cvxif_issue_register_commit_if_driver` are all instantiated and the X
  writeback port is the fifth one. The model completes every handshake and
  accepts no instruction, so the X port carries ONLY illegal-instruction
  exceptions. A coprocessor that accepted and returned results would add a
  fifth live writeback port with free latency and make out-of-order completion
  richer; it would also have to guarantee a result for every accepted id or
  strand a scoreboard entry, and that is the failure mode worth avoiding on a
  first assembly. **This is a deferred coverage gap, not a correctness one.**
* **No MMU and no page faults.** `MmuPresent = 0`: `cva6_mmu`, `cva6_tlb`,
  `cva6_ptw` and `cva6_shared_tlb` are not instantiated, the PTW dcache port is
  tied off by `gen_no_mmu`, and virtual and physical addresses are identical.
  The `ABORT_TRANSACTION` / `WAIT_TRANSLATION` arms of the load FSM are
  unreachable.
* **No atomics** (`RVA = 0`, `amo_buffer` not instantiated, `amo_resp` tied
  off) and **no floating point** (`FpPresent = 0`, the FPU writeback port is
  dead).
* **No supervisor or user mode** (`RVS = RVU = 0`), **no debug**
  (`DebugEn = 0`), **no triggers** (`Sdtrig = 0`), **no Zcmp/Zcmt macro
  instructions**, **no performance counters**. The privilege level never
  leaves machine mode, so the PMP always permits in the absence of a locked
  entry and category 14 is thinner than it would be on a config with RVU.
* **No branch target buffer** (`BTBEntries = 0`). The BHT and the RAS are
  present; indirect-jump prediction is not.
* **The data cache has no write buffer**, so `dcache_wbuffer_empty` is
  constant 1 and the fence path never waits on one. The store buffer's own two
  queues are real and are where the store-side targets are stated.
* **Category 15, coherence, is not admitted by this subsystem and has no
  target.** One hart, one instruction stream, no second agent to conflict
  with. Saying so is the result, per
  `v6_dataset/prompts/targets/CATEGORIES.md`.

## What I expect to be wrong

Written BEFORE any proof has been run, so that a screen result can be read
next to the author's prior rather than after it.

* **The three `T_CONSERV_*` equalities against a design structure are the ones
  I most expect to come back `cex`, and for a reason that is mine.**
  `T_CONSERV_SB_LIVE_SET_MATCHES_LEDGER`,
  `T_CONSERV_SB_OCCUPANCY_MATCHES_LEDGER` and
  `T_CONSERV_ID_STAGE_OCCUPANCY_MATCHES` compare a ledger that starts empty
  with a design structure that, under the FRA reset cut, starts arbitrary.
  At REAL RESET -- which is where the phase-1 screen runs -- both start empty
  and the statements are meaningful. Under `ENTER_FRA_KEEP` they are false at
  cycle 0 whatever the design does. `design_keep` preserves the checker, not
  the scoreboard, and no keep pattern can fix this: it is a property of
  comparing a shadow against state the cut randomises. Same caveat for
  `T_ORDER_SB_ISSUE_POINTER_IS_PROGRAM_ORDER` and
  `T_ORDER_SB_COMMIT_POINTER_IS_OLDEST`.
* **`T_UNIQ_ONE_WRITEBACK_PER_ENTRY`.** It rests on the argument that a load
  flushed while in memory never writes back, because `load_unit` suppresses
  `valid_o` for a slot whose `ldbuf_flushed_q` bit is set. That was derived by
  reading the flush branch of `ldbuf_comb` (where `flush_i` deliberately wins
  the lexical priority contest against a simultaneous `ldbuf_w`), and it is an
  argument rather than a construction. A single missed path makes it false.
* **`T_REQRSP_WRITEBACK_NAMES_LIVE_ENTRY`.** Its `!flush` guard is a one-cycle
  guard, and the case it is guarding against -- an in-flight memory operation
  writing back after the pipeline was flushed -- can plainly last longer than
  one cycle. The scoreboard's own `mem_q[trans_id].issued` test exists exactly
  because upstream expects this to happen. I expect `cex`, and the
  counterexample will say how many cycles the guard actually needs.
* **The bounds.** `FETCH_BOUND` / `LOAD_BOUND` / `STORE_BOUND` = 32,
  `RETIRE_BOUND` = 256 and `PROGRESS_BOUND` = 128 are estimated from the
  models' `MAX_WAIT = 8` plus slack, not computed. `T_BOUNDRSP_RETIREMENT_WITHIN_N`
  is the most exposed: an instruction at the commit pointer that is a fence
  waits for the store buffer to drain, which waits on the store port, and I
  have not multiplied that chain out. `T_FAIR_STORE_PORT_GRANTED_WITHIN_N` is
  the safest, because the store port's grant is bounded by the model directly.
* **`T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N`.** Its `any_progress` term includes
  a fetch handshake, so any state in which the frontend keeps fetching counts
  as progress even if nothing retires. That makes it weaker than it looks and I
  expect it to PROVE rather than to be hard.
* **`T_MUTEX_INSTR_QUEUE_SELECT_ONEHOT`** is upstream's `$onehot0`
  strengthened to `$onehot`. If `idx_ds_q` can legitimately be all-zero the
  strengthening is simply wrong and it will `cex` immediately.
* **`T_PROTO_ISSUE_ENTRY_STABLE_UNTIL_ACK` and
  `T_PROTO_FETCH_ENTRY_STABLE_UNTIL_READY`** guard on `!flush_if` only. Both
  the ID stage and the frontend have other reasons to replace the entry they
  are offering (`replay`, `is_mispredict`, `halt_frontend`), and I did not
  enumerate them. Expect `cex` on at least one.
* **The three `T_RESET_*`** will prove, and will not be hard. That is what the
  first screen found for every reset target and there is no reason this
  subsystem is different. They are kept because a proven target is a free
  labelled helper.
* **`T_DATA_COMMIT_WDATA_IS_WRITEBACK_DATA`** excludes `CSR` because commit
  substitutes `csr_rdata_i`. I believe that is the only substitution, but
  `fu == NONE` entries (which the scoreboard marks valid without any
  writeback) are handled by the `sb_wbseen_q` guard rather than by an
  exclusion, and if any other functional unit retires a value it never wrote
  back this is false.

## design_keep: this task needs a non-empty one, with THREE entries

    "design_keep": ["u_targets\\.", "u_icache\\.", "u_dcache\\."]

matched unanchored against instance paths as `get_design_info -list register`
returns them, which is the form `_CHECKER_KEEP` uses. All three match; none can
trip `cex.tcl`'s "design keep pattern matched nothing" FAIL.

**`u_targets\.` -- the instrument.** Every oracle register is in it: the
ledger's two pointers, its live set, its occupancy counter, the per-position
pc / rd / fu arrays, the writeback record, the register-file shadow, the load
id set, the store queue counter and the five wait counters. Under
`ENTER_FRA_KEEP` every register not matched by a keep pattern starts arbitrary;
cut, the ledger starts with garbage in it and most of the 50 are falsified at
cycle 0 for a reason that is not the design's and that nothing in the design
can correct. Same rule as `openpiton_pmesh_order`'s `u_checker.ref_*`.

**`u_icache\.` and `u_dcache\.` -- the formal top holds environment state that
must not start arbitrary.** Cut, `u_dcache.pend_q` starts non-empty, so the
model returns `data_rvalid` for loads nobody requested: an unsolicited
response that falsifies `T_REQRSP_LOAD_RESPONSE_WAS_REQUESTED` and
`T_CONSERV_LOAD_ID_SET_MATCHES_BUFFER` directly and writes garbage into the
register file. `u_icache.pending_q` starting set makes the icache answer a
fetch that was never issued. Both wait-counter sets starting near `MAX_WAIT`
would force an immediate grant, which is harmless, but the queue state is not.
Every register in both models is written in its reset branch, so keeping them
is meaningful rather than a no-op.

**Left cut deliberately**: everything in the design proper, including
`csr_regfile`'s CSRs and the PMP entries. An arbitrary CSR state is a state
software could have written, so anchoring it would only narrow the search.

## `lists/` -- entirely new

None of it exists upstream.

    lists/tc_elab.files     the analyzed file list, package-root-relative, and
                            also `TASKS[...]["slang"]["command_file"]`, which
                            is the file the round appends one
                            `../submission/<worker>.sv` line to per worker.
                            58 source lines: 52 upstream RTL, 4 `ft/`, 2 `sva/`.
    lists/tc_elab.tcl       the elaboration recipe. `clock clk_i`,
                            `reset -expression {rst_ni == 1'b0}`.
    lists/diag_cva6_frontend_issue_commit.tcl
                            defines `setup_diag_cva6_frontend_issue_commit` --
                            the harness calls `setup_${diag}` where `diag` is
                            the taskdef field `diag_cva6_frontend_issue_commit`,
                            so any other name is silently never applied. It
                            creates the Jasper task, declares NO assumptions,
                            and fails loudly if zero `u_targets.T_*` resolved.
    lists/reset_modes.tcl   copied from `tasks/cva6_cache_subsystem/lists/`
                            with one change: the reset expression names
                            `rst_ni`, this package's reset pin.
    lists/targets.txt       one `label<TAB>category<TAB>intent` line per
                            candidate, 50 lines, in the same order as
                            `taskdef.json`'s `target_labels` and as the
                            assertions in `sva/targets_*.sv`.

Copied verbatim from `tasks/cva6_cache_subsystem/lists/` because both are
task-agnostic:

    lists/proofgrid_profiles.tcl   sourced by our own tc_elab.tcl
    lists/vendor/iterdev_utils.tcl `safe_assume`. This diag declares no
                                   assumptions and does not call it, but
                                   `cex.tcl`/`check.tcl` source it when
                                   present and it costs nothing to ship.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args`. It is
derived, not authored, and is gitignored.

`sva/covers_*.sv` and `sva/targets_*.sv` are both IN `lists/tc_elab.files`,
targets last, because a `bind` must be analyzed after the module it binds
into. Forgetting that is silent: the local gate passes with `--extra` while
the real Jasper run analyzes only what the list says.

## The gate

    cd an internal golden package
    uv run python v6_dataset/elab_local.py --task cva6_frontend_issue_commit
    -> OK: cva6_frontend_issue_commit elaborates

Run WITHOUT `--extra`. Slang reports **0 errors and 0 warnings** over the whole
package.

The gate uses `--ignore-unknown-modules`, which BLACK-BOXES a module the
package failed to carry instead of failing. This package was therefore also
elaborated with that flag removed, and that is what found two missing
common_cells (`cc_shift_register_gated` and `unread`, both instantiated one
level below cells that were already in the list) and one missing include
(`common_cells/registers.svh`). With them added:

    slang --single-unit --top cva6_frontend_issue_commit_ft -f lists/tc_elab.files.slang
    -> Build succeeded: 0 errors, 0 warnings

## Not verified

Nothing here has been elaborated in Jasper and no proof and no cover has been
run. What HAS been checked, by running the repo's own loaders:

* Slang elaborates the package, 0 errors / 0 warnings, WITHOUT
  `--ignore-unknown-modules`
* the AST census finds 50 `T_*` in `u_targets`, 41 `C_*` in `u_covers` and 45
  upstream concurrent assertions, none of them an `assume` or a `cover`
* all 57 files under `rtl/` are byte-identical to upstream (`cmp`, 0
  differences)
* `taskdefs.TASKS` admits the task and `taskdefs.derive_targets` locates all 50
  `target_labels` in `sva/targets_cva6_frontend_issue_commit.sv`
* the configuration values above were read out of an elaborated `$info`, not
  computed by hand
* the instance counts above were read out of the elaborated AST

The Jasper elaboration, the `ELABORATION_CENSUS`, the cover depths and the
phase-1 screen are the smoke test.

## No hashing

No content hash, checksum or hash-based identifier is recorded anywhere in
this package. Identity is the readable name plus this file.
