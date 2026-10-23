# l15_l2_mshr_onehot_oraclefree provenance

assembled: 2026-08-20 from `tasks/l15_l2_mshr_onehot`, which is described in
full below. Everything is a verbatim copy of that package except:

  * `sva/targets_l15_l2_mshr_onehot.sv` -- rewritten;
  * `lists/hard_targets.txt`, `lists/targets.txt`, `lists/proven_targets.txt`
    -- rewritten to name what this file asserts.

`rtl/`, `ft/`, `sva/openpiton_l15l2_deadlock_checker.sv` and every `lists/*.tcl`
are byte-identical to the parent, so the task's own target
(`u_checker.T_L2_MSHR_ONEHOT`) and its diag resolve exactly as before.

## Why the arm exists

The parent's targets file ships a REFERENCE MODEL: a per-channel packet
framer, an outstanding-memory-request set keyed on MSG_MSHRID, a shadow FIFO
of the L1.5 NOC1 command buffer and four saturating wait counters, all written
as `always` blocks in the same file, with two thirds of its assertions
comparing the design against them. Sixteen of the parent's twenty hard rows
are on that side of the line. Building that instrument is the modelling work
this study wants to measure an agent doing, so this arm re-states the same
obligations without it and leaves the modelling to the agent's own notebook.

## What the rewrite does

The file declares NO STATE: zero `always` blocks, zero `reg`/`logic`
declarations. Every wire is a combinational view of a register that already
exists. Seventeen targets, all seventeen classed intrinsic by
`v6_dataset/oraclefree.py` (0 modelled signals).

  * pool one-hot / uniqueness -- pairwise, register-free, over
    `l2_mshr_wrap.state_mem_f` and `data_mem_f`;
  * NOC1 buffer conservation -- the design's own `command_buffer_val`,
    `command_wrindex` and `command_rdindex`, plus `$past` for the per-cycle
    push/pop law;
  * lifecycle -- written at the muxed MSHR write port (`wr_data_en`,
    `wr_index_in`, `data_in`, `data_mask_in`), which covers pipe2 as well as
    pipe1 where the parent covered only pipe1;
  * fairness / bounded response / deadlock freedom -- SVA consecutive
    repetition, `p[*N] |=> !p`, at the parent's own bounds (192, 128, 256).

Three parent rows could not be re-stated and are dropped, with the reason
recorded at the top of `lists/hard_targets.txt`:
`T_ORDER_MEM_ACK_IN_REQUEST_ORDER`, `T_DATA_MEM_ACK_KEY_MATCHES_MSHR`,
`T_BOUND_NOC1BUF_OCC_LE_SLOTS`.

## Caveat to report with any number from this arm

Three targets are marked `(env)` in `lists/hard_targets.txt` and
`ENVIRONMENT-DERIVED` in the SVA -- `T_BOUND_MEM_OUTSTANDING_LE_BUSY`,
`T_MUTEX_MEM_OUTSTANDING_KEY_ONEHOT`, `T_REQRSP_MEM_REQ_HAS_BUSY_ENTRY`.
Their subject is the set of memory requests that have left the L2 and not been
answered, and the design does not name that set: an L2 MSHR entry sits in
`WAIT` for reasons other than a memory miss, so `WAIT` is not that set. They
read it from the formal top's OWN memory responder queue (`u_mem.q_wr_f`,
`u_mem.q_rd_f`, `u_mem.hdr_q`, `u_mem.tx_state_f`) and from its NOC2
demultiplexer's framing bit (`n2_in_body_f`). No register is declared for
them -- this is a combinational view of environment state that was already in
the formal top -- but it is not design state either, and a number from those
three should say so.

## Untested

Nothing here has been elaborated; `slang` is not on this machine. What was
checked by inspection and by script: 17 assert labels and 15 cover labels, no
duplicates, the label set equal to `lists/hard_targets.txt` and
`lists/targets.txt`; `module` header and `bind` line byte-identical to the
parent's; `generate`/`endgenerate`, `begin`/`end`, parentheses, brackets and
braces balanced; no `always` and no state declaration;
`taskdefs.oracle_keep` returns `[]` for this package.

## Harness dependency -- must be handled at registration

`taskdefs.oracle_keep` adds a keep pattern only for a bound module that HAS
state, and this one has none, so it contributes nothing -- which is what we
want, and is also load-bearing. Had the file kept a combinational
`always @*`, `oracle_keep` would have added `l15_l2_targets\.` to
`DESIGN_KEEP`, that pattern would have matched zero registers, and
`ENTER_FRA_KEEP` fails a round on a design keep pattern that matches nothing.
That is the failure mode `taskdefs.py` records for nyuzi and cva6_frontend.

Registering the package still needs, in `taskdefs.py`: a `TASKS` entry copied
from `l15_l2_mshr_onehot` (same `top`, `mount`, `slang`, `elab_tcl`, `diag`,
`target_labels`), and `DESIGN_KEEP["l15_l2_mshr_onehot_oraclefree"] = []` --
the key must exist, since `round.py` looks it up unguarded.

---

# Parent package provenance, copied verbatim
---------------------------------------------------------------------------

# l15_l2_mshr_onehot provenance

assembled: 2026-08-13

source: an internal golden package
        (copied out; the source tree was not modified)

OpenPiton L1.5 + L2, one tile, the real `l15` and the real `l2` wired to each
other behind a formal top that supplies two bounded core sources, a NOC2
demultiplexer and a memory responder.

    top:     openpiton_l15l2_deadlock_ft
    diag:    lists/diag_l15_l2_mshr_onehot.tcl
    target:  T_L2_MSHR_ONEHOT
             assert property (@(posedge clk) disable iff (!reset_n) !cons_dup)
             at sva/openpiton_l15l2_deadlock_checker.sv:86

`cons_dup` is combinational over `l2_mshr_wrap.state_mem_f` and
`l2_mshr_wrap.data_mem_f`: at most one busy MSHR entry per L2 set index. The
key is `` `L2_MSHR_CMP_ADDR == `L2_TAG_INDEX ``, **3 bits at this build**
(`l2.tmp.h:133 L2_TAG_INDEX_WIDTH 3`), so 8 distinct keys over 8 entries.

## Status of the target — do not overstate it

The target is **believed true and is not proven**. The golden arm's
`min_length=infinite` result holds only with an **uncertified** fact assumed:
`H_NCW` (`!(l2_wr_data_en && fh_wr_collides)`). Its companion `H_ONSET2` is
certified; `H_NCW` is not, and the `gyC`/`gyD` ablation measures `H_NCW`'s
marginal contribution as the entire proof. On certified facts alone the target
is `undetermined@24` at cut=114. So the golden did not close this task — it
reduced it to one unproven fact. The task is genuinely open.

The naive arm spent 13556 s of a 14400 s budget over 13 rounds without closing
it; it is the only naive arm to spend its full budget. The unassisted proof is
memory-bound rather than time-bound (`TERM_MEMLIMIT` at 16384 MB), so more wall
clock alone changes nothing.

## What was removed, and why

The source `task/` is not a task statement. It is the golden agent's own
working tree, and the checker carries that agent's findings as **live code**,
not merely as commentary. Everything below was removed because this package is
copied into every agent workspace.

### 1. The golden helper web, which the checker declared as assertions

`sva/openpiton_l15l2_deadlock_checker.sv` declared **143 property labels**
(71 assert, 70 cover, 2 assume). **55 of the assertions are named `H_*`** and
are the golden agent's certified and candidate helper facts, written out in
full — the L2 CAM-key shadow agreement (`H_GHOST_KEY_AGREE`,
`H_KEY_AGREE_E`), the `rst_ctr` time anchors (25 `H_ANCHOR_*`), the FIFO
occupancy-vs-pointer coherence family (`H_*_PTR_COHERENT`), the credit and
buffer bounds (`H_L2_*_BOUND`, `H_L15_NOC1_*`), and the L1.5 tracker shadow
(`H_L15_LD_ADDR_AGREE`, `H_L15_ST_ADDR_AGREE`).

An agent that read that file would not have to discover a helper web; it could
copy one. The whole `H_*` set is removed.

The kept set is **16 labels**: the target, the two environment fairness
assumptions, and 13 covers. **127 labels were removed.**

### 2. The other target families

The source checker also carried three unrelated obligation families:
`T_L15L2_WAIT_ACYCLIC` (a combinational wait-for graph over 6 resource-class
nodes), `T_L15L2_BOUNDED_PROGRESS` with 14 `f_g_deadlock` monitor instances and
their `T_PROGRESS_SEQ` / `A_MON_MAX_BOUND` / `A_WF_*` families, and the covers
serving them. None of them is this task's target. They are removed, with the
`f_g_deadlock` module itself, for three reasons: their comments are saturated
with golden-run results (`cex, min_length=20, Ht, 26.04 s`), the 14 monitors
add checker state and 84 registers to a proof already reported memory-bound,
and a false or unknown sibling assertion is noise in every round report.

Also removed as finding-shaped or stale:
`A_PIGEONHOLE` and `A_TARGET_NEEDS_LE4` (written for the earlier 2-bit-key
geometry and documented in the source as expected to fail at 3 bits),
`A_ADDR_ONEHOT` (a per-element restatement of the target, and it loops over
only 4 of the 8 buckets — another 2-bit leftover), `A_NO_PIPE2_RESURRECT`,
`A_NO_RESURRECT_BY_MEMACK`, `A_N1B_NO_OVERWRITE`, `A_GHOST_SEES_ALL_FREES`,
and `T_L2_MSHR_STATE_LEGAL` / `T_L2_MSHR_OWNER_ONEHOT`.

### 3. The golden FT instrument

`ft/openpiton_l15l2_deadlock_ft.sv` went from 1019 to 589 lines. The
environment — core sources, the `l15` and `l2` instantiations and every port
connection, the NOC2 demultiplexer, the memory responder, the NOC3 merge — is
**verbatim**. What was deleted is the block the source labels `FT-MODEL: a
SHADOW of the L2 MSHR` and everything after it up to the conservation
flattening:

  * `ghost_key`, `ghost_keyed`, `ghost_key_agree`, `ghost_mshrid`,
    `ghost_mshrid_agree` — a prebuilt shadow model of the L2 MSHR, keyed on
    exactly the field the target is about;
  * `rst_ctr`, the saturating time anchor the 25 `H_ANCHOR_*` facts are
    written against;
  * `gl15_ld_addr` / `gl15_st_addr` / `gl15_*_agree` — the L1.5 tracker shadow;
  * `ghost_blind_free`, `l2_free_edge`, `pending_free_fires`,
    `site482_fires` / `site494_fires` / `site503_fires`, `ctrl_pend_busy`,
    `ctrl_cam_busy` — detectors for named RTL lines the golden hypothesised
    about;
  * `n1b_overwrite` / `n1b_write_free` / `l15_credit_*` — the credit trace;
  * `l15_age` / `l15_uage` / `l15_free_*_max` — the free-latency ladder;
  * the `l2_wr_*` write-port decomposition the source labels `cex@31 TRACE`.

Leaving these would hand an agent the instrument the golden built. Building
that instrument is a large part of the task.

Observation wires that no kept property consumes went with them
(`l2_mshr_way_*`, `l15_st_way_*`, `l2_wbg_counter`, `l2_pending`,
`l2_p2_active`, `l2_out_backed`, the `l15_stall_*` and `l2_stall_*` set,
`noc3_l15_starved`, `l2_mshr_owner_flat`). That set is also the golden
author's curated list of which signals matter, which is itself a hint.

The checker's port list shrank from 45 to 16 and the instantiation was rewritten
to match; all 16 are connected and every connected signal is declared.

### 4. The submission hook

`` `ifdef FLS_EVALUATION / `include "helpers.sv" `` at the end of the FT is
removed. That is the old harness's mechanism. v5 delivers each worker's web as
a bound module appended to `lists/tc_elab.files`, so the include has no role
and the missing file would only confuse.

### 5. Comments

Scrubbed throughout, per the rule that no comment may name a keep/cut
configuration, an engine, a proof outcome, a helper, or why a target was
chosen or disqualified. Specifically removed:

  * the `REGISTER-FREE ... exactly like RN's f_ptag_leaked function ... not
    exposed to the instrument-cut hazard that made the bounded-progress target
    read `cex@1` at `total_keep = 0` ... NO invented constant, which is what
    disqualified that target` block above `cons_count`;
  * the `NOT AUTHORED, DELIBERATELY` block explaining that per-pair key
    disjointness is the target restated and would have been the largest source
    of helper volume — a direct instruction in what to write and what not to;
  * the `SOUNDNESS NOTE` recording that the first wait-graph formulation
    measured `cex, min_length=20, Ht, 26.04 s` under real reset;
  * the `cex@31 DISCRIMINATOR` block naming `l2_pipe2_dpath.v:843` and the
    stale-key mechanism, the `cex@24 DISCRIMINATOR`, and the `THE OTHER THREE
    RESURRECTION SITES` list of `l2_mshr_wrap.v` line numbers;
  * per-class helper commentary (`CLASS A/B/B2/C/D/D'/D''/E/F/G`), including
    `proved infinite in 0.74 s`, `18/18-proven shape`, `8/8 proven`, and the
    `ft_keep` / `dut_keep` arm descriptions;
  * cross-references to the golden's own working notes and sibling tasks
    (`TASK-B5.md` sections, `docs/DEADLOCK-CHECKER-MODELLING.md`, `S68`,
    `S87`, `S92.1/2/3`, `f457b12`, `plan rule 7b/9b`, `plan section 1a2a/1b`,
    an internal catalogue, an internal task's rule-per-design note, the internal reference task's helper file,
    `openpiton_pmesh_waitcycle_4x4_v1`, and "the pmesh FT");
  * `MSG_MSHRID is preserved, which is what l2_pipe2_dpath uses as
    mshr_rd_index_S1` in the memory responder header — restated as the
    environment contract it is, without the pointer to the RTL mechanism;
  * `REBUILD (S92.2)` in the responder, which named the declared restriction
    it lifted and that the old form `silently trivialised the target (S87)`.

The RTL under `rtl/openpiton_l15l2/` was **not** scrubbed and is a verbatim
copy: it is the design under test, its comments are OpenPiton's and the
BSD headers', and a sweep for the leak vocabulary found nothing.

### 6. `DERIVATION.json` — dropped

Not carried into the package. It records the environment declarations (useful)
alongside the golden's target selection, cover classification, bound
provenance and scale ladder (not useful to an agent). It is also **stale**: it
states `L2_TAG_INDEX_WIDTH: 2` where the shipped RTL has 3, and names
`T_L15L2_WAIT_ACYCLIC` as the target. The environment facts worth keeping were
folded into the FT header comment instead.

### 7. `tcl/setup.tcl` — replaced, not carried

Replaced by `lists/tc_elab.tcl`. What went:

  * `fls_require_exact_names` / `fls_require_names_present` — a strict name
    census over the expected assertion, assumption and cover sets. It is a
    fail-closed gate for a fixed submission; under v5 the property set changes
    every round by design, so it would fail every round.
  * the `FROZEN_INPUT_MISSING` check, which requires `submission/helpers.sv`
    to exist — v5 never writes that file.
  * `TARGET_RESOLUTION_FAIL` on `T_L15L2_WAIT_ACYCLIC`. The equivalent check
    for **this** package's target lives in
    `lists/diag_l15_l2_mshr_onehot.tcl`, which errors unless exactly one
    `u_checker.T_L2_MSHR_ONEHOT` resolves.

**No hashing.** The source carries no SHA256SUMS, checksum or hash-based gate,
so none had to be dropped and none was added. Its gates were name censuses,
and they are described above.

## What was invented

Everything under `lists/`. The source package had no v5-shaped list directory.

  * **`lists/tc_elab.files`** — one list holding every source. It has to be
    one list: `v5/round.py:117` appends `../submission/<web>.sv` to
    `TASKS[task]["slang"]["command_file"]`, and `taskdefs.slang_args` reads
    that same file to build the design map. Splitting it would silently drop
    either the workers' helper files or the whole DUT from the design map.
    RTL first (it carries the `` `include `` of `l2.tmp.h` / `l15.tmp.h` whose
    macros the checker and FT then use), then the checker, then the FT;
    appended worker files land last.

  * **`lists/tc_elab.tcl`** — one `analyze -sv12 -f lists/tc_elab.files` where
    the source used `analyze -v2k` for the RTL and `analyze -sv12` for the
    SVA. Checked before changing it: with comments stripped, no source under
    `rtl/openpiton_l15l2/` uses a SystemVerilog-2012-only keyword as an
    identifier, so nothing needs the older mode. Everything else follows the
    source recipe — `USE_GENERIC_SRAM_IMPLEMENTATION`, `-disable_auto_bbox`,
    `clock clk`, `set_cumulative_reset on`,
    `reset -expression {reset_n == 1'b0} -max_iterations 100`, and the
    multiple-driven check. It creates task `FPV`, which the diag starts from,
    and reads `AFRA_ELAB_EXTRA`. Nothing is escalated to an error: the trimmed
    checker leaves some design outputs unread and that class of warning says
    nothing about the task.

  * **`lists/diag_l15_l2_mshr_onehot.tcl`** — required by v5 (`cex.tcl` sources
    `lists/<diag>.tcl`, calls `setup_<diag>`, then `task -set <diag>`).
    It installs **no assumptions**, unlike the internal reference task diags: the internal reference task's
    cell is a symmetric fabric whose diag pins the observed source/destination
    pair, whereas here the environment is built into the FT and is not
    steerable from Tcl. Its real work is creating the `diag_l15_l2_mshr_onehot`
    task and failing loudly if the target did not elaborate. It needs no
    `safe_assume`, so no `lists/vendor/iterdev_utils.tcl` is shipped — v5
    sources that file only when the package has one.

  * **`lists/reset_modes.tcl`** — load-bearing: `v5/cex.tcl` and
    `v5/check.tcl` source it unconditionally, and `ENTER_FRA_KEEP` calls
    `rm_all_registers` and `_rm_apply_reset` out of it. Written from
    the internal reference task's, with `::rm_reset_expr` set to this design's
    `{reset_n == 1'b0}` and the `xig0`-specific keep machinery dropped.

  * **`lists/proofgrid_profiles.tcl`** — copied verbatim from
    `an internal reference task/lists/`. Sourced by this package's own
    `tc_elab.tcl`, not by the harness. `CONFIG_GRID` runs after the load and
    overrides `max_jobs` and the per-engine limits; the profile still decides
    `restarts`, `pending_time_limit`, `persistent_timeout` and local execution
    mode.

Module and file names are the source's and were deliberately **not** renamed,
so receipts from the golden and naive arms still line up. Note that
`openpiton_l15l2_deadlock_{ft,checker}` now carries no deadlock property; the
name is history, not a description.

## Untested

Nothing here has been elaborated. `slang` is not on this machine, so the
package has not been parsed either. What was checked, by inspection only:
every path in `lists/tc_elab.files` exists (61); the checker's 16 ports and the
FT's 16 instance connections match exactly and every connected signal is
declared in the FT; `module`/`endmodule` and `generate`/`endgenerate` balance;
no identifier from a deleted block survives anywhere; and
`taskdefs.derive_targets` locates `T_L2_MSHR_ONEHOT`.

## Harness dependency — was a blocker, now satisfied

When this port started, `v5/round.py` read
`set target_labels {tcl_list(v4pre_round.TARGETS)}` — hardcoded to the internal reference task's
two RGB labels, ignoring `TASKS[task]["target_labels"]`. On this task `RESOLVE`
would have matched neither and `v5/cex.tcl:827` would have fired
`FAIL "no target property resolved"`, killing every round.

It was fixed concurrently while this package was being assembled; `round.py`
now reads `set target_labels {tcl_list(taskdefs.TASKS[self.task]["target_labels"])}`.
So this package's `target_labels: ["T_L2_MSHR_ONEHOT"]` is what the round will
prove. Recorded because the dependency is invisible from inside the package: if
that line is ever reverted, this task fails at the first round with a message
that names neither the task nor the cause.

Two smaller ones, both quality-of-coverage rather than correctness, recorded so
they are not rediscovered:

  * `taskdefs.LIBRARY_FILES` has no entry for this task, so nothing is
    classified as a library cell. Low impact — this package ships no
    standard-cell `.vlib` files, only RTL.
  * `v5/helper.py:226 PACKAGE_SWALLOWS` lists the internal reference task's `-from_assert`
    tokens. This package converts no assertion into an assumption, so nothing
    is swallowed and no token list is needed.

  * The repo `.gitignore` ignores `tasks/*` and allowlists each package's
    `lists/` explicitly. Nothing here is version-controlled until those lines
    are added, and unlike the internal reference task packages this one's `sva/` and `ft/`
    are hand-edited rather than vendored — by the gitignore's own rule
    ("a one-line change inside one is a change nobody can reproduce if it
    lives only on one disk") they belong in the history. `rtl/` (1.4M,
    verbatim OpenPiton) should stay out. The lines are reported with the
    taskdefs entry rather than added here, because `.gitignore` is shared with
    the task being ported in parallel.

## Keep set

`DESIGN_KEEP["l15_l2_mshr_onehot"] = []`, an empty list under the key — the
key must exist, since `v5/round.py:148` looks it up unguarded. Empty is
correct and not merely convenient: `ENTER_FRA_KEEP` fails only on a *design*
pattern that matches nothing, so no patterns cannot fail; the FT-model keep is
derived per round from each worker's own bind name
(`ft_keep_patterns = [rf"{web['name']}\." for web in webs]`, `round.py:385`);
and the target itself needs no keep, because `cons_dup` is combinational over
two design arrays and the checker holds no register for a cut to make
arbitrary. The one FT register in the target's cone is `dut_ready`, which only
suppresses the target for the first cycle out of reset; cut, it starts
arbitrary and settles to 1, which cannot cause a false failure.

The run should keep the FT model (`fra_keep_notebook`), per the nightly plan:
an agent cannot anchor a shadow model to a design register it has not found
yet, so cutting the notebook makes every shadow it writes start arbitrary and
its equalities vacuous.

## Comparability caveat — report this with any number from this task

This package is **not** the package the naive and golden arms ran. Those arms
saw all 143 checker properties, the 55 `H_*` helpers among them, and the full
FT instrument. This one sees 16 properties and no instrument. A round count or
a wall-clock figure from this package is therefore not comparable with the
naive arm's 13 rounds / 13556 s, and the 55 removed `H_*` facts are not
available to be assumed. If comparability matters more than blindness, the
removals in sections 1-3 are the ones to reverse; the source file is intact at
the path named at the top.

golden helper web (review only, never mount):
  the 55 `H_*` in the source's
  `task/sva/openpiton_l15l2_deadlock_checker.sv`, plus the submission web at
  an internal golden package
  (`helpers.sv`, `round1/r1_helpers.sv`, `final/final_helpers.sv`)
