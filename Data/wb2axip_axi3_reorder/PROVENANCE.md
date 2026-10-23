# wb2axip_axi3_reorder provenance

assembled: 2026-08-19

source: an earlier internal task package
        (copied out of; the source tree was not modified)

upstream RTL: wb2axip @ 2e8d3bc2d26ddc33d1881022a2a2b9d3f0c16b9b (ZipCPU),
              `rtl/axi3reorder.v` and `rtl/sfifo.v`, byte-for-byte per the
              source's DERIVATION.json.

`axi3reorder` takes an AXI3 write stream whose W beats may arrive interleaved
across IDs and reorders them into AXI4's rule: the write data for one ID must
be delivered as one uninterrupted packet, and the packets must come out in the
order their AW addresses were accepted. The package instantiates it with
`OPT_METHOD(1)`, the shift-register implementation, 2-bit IDs, 8-bit data, an
8-deep AW FIFO and a 16-deep W FIFO. The checker keeps an independent 16-entry
AW ID queue and four independent 32-entry per-ID W queues, and the target says
the output is what those queues say it should be: the right ID (the one at the
head of the AW queue), the right beat of that ID's queue, and no queue ever
overflows.

top: testbench
environment: lists/diag_wb2axip_axi3_reorder.tcl
             (task `diag_wb2axip_axi3_reorder`; declares no assumptions of its
             own -- the package's five live in `ft/tb.sv`)
target: o_axi3_reorder_e2e  (testbench.o_axi3_reorder_e2e)

Note the target's name is lowercase, unlike the `T_*` of the other four
packages in this porting group. That is the upstream task's name and it is
taken as shipped; the label is what `RESOLVE` keys on, so it must not be
"normalised".

The source's `DERIVATION.json` also lists three covers -- `c_aw_backlog`,
`c_interleaved_ids`, `c_reference_wrap` -- and five assumptions --
`A_RESET_AW_IDLE`, `A_RESET_W_IDLE`, `A_AW_STICKY`, `A_W_STICKY`,
`A_FIXED_PACKET_LAST`. All eight elaborate with the package. The covers are
what `COVER_DEPTH` counts if a round is given `--cover-s`; they are not
targets.

Parameters, from the source's `DERIVATION.json`: `data_width=8`, `ids=4`,
`write_packet_beats=4`, `method="shift-register"`, `address_fifo_depth=8`,
`data_fifo_depth=16`, `reference_address_depth=16`,
`reference_data_depth_per_id=32`.

`A_FIXED_PACKET_LAST` is worth naming as an environment fact rather than a
protocol nicety: it forces every packet to be exactly four beats per ID, which
is what keeps a packet inside the 32-entry per-ID reference queue.

## What was carried over unchanged

Byte-identical to the source (checked with `diff -r`):

    rtl/axi3reorder.v
    rtl/sfifo.v

`ft/tb.sv` differs from the source by exactly one hunk, recorded under
"scrubbed" below. Every line of the composition, the reference model, the
assumptions, the target and the covers is the source's -- including
`` `undef FORMAL `` at line 2, which is what keeps the two ZipCPU files' own
formal harnesses out of the elaboration and is load-bearing.

Unlike the two verilog-axis ports and the verilog-ethernet one in this group,
this package needed NO `` `timescale `` repair: neither ZipCPU file declares a
time scale, so nothing in the design has one and Slang's mixed-time-scale
error does not arise.

`tcl/` was NOT copied. It is the source's own single-shot evaluator (see
below), and `DERIVATION.json` was not copied either (see "Dropped hash gates").

## What was written for this package

`lists/` did not exist in the source and is entirely new. v5 admits a task only
if `taskdefs.TASKS[name]` carries both `elab_tcl` and `diag`, then sources
`lists/<elab_tcl>` and calls `setup_<diag>` at global scope.

    lists/tc_elab.files        the analyzed file list, package-root-relative.
                               Also `TASKS[...]["slang"]["command_file"]`, the
                               file the round appends one
                               `../submission/<worker>.sv` line to per worker.
    lists/tc_elab.tcl          the elaboration recipe, derived from the
                               source's `tcl/setup.tcl` -- see below.
    lists/diag_wb2axip_axi3_reorder.tcl
                               defines `setup_diag_wb2axip_axi3_reorder`,
                               creates the Jasper task, prints the assumption
                               and target census.
    lists/reset_modes.tcl      `rm_all_registers` + `_rm_apply_reset` and their
                               globals, which is all `v5/cex.tcl` calls, plus a
                               little reporting. Copied from
                               `tasks/openpiton_pmesh_order/lists/` with the
                               reset expression changed to this package's
                               (`reset == 1'b1`, active high) and the header
                               retitled.

Copied verbatim from `tasks/openpiton_pmesh_order/lists/` because both are
task-agnostic:

    lists/proofgrid_profiles.tcl   sourced by our own tc_elab.tcl
    lists/vendor/iterdev_utils.tcl `safe_assume`. Our diag declares no
                                   assumptions and does not call it, but
                                   `cex.tcl`/`check.tcl` source it when present
                                   and it costs nothing to ship.

`taskdef.json` is new: a per-task definition dropped in beside the package
rather than an edit to `taskdefs.py`.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on every run.
It is derived, not authored, and `.gitignore` says so.

## The one thing this package does differently: Slang needs a switch, and Jasper cannot see it

This is the only port in this group whose `lists/tc_elab.tcl` does NOT say
`analyze -sv12 -f lists/tc_elab.files`. The reason is worth recording in full,
because the alternative was editing the design under proof.

`rtl/axi3reorder.v:337` is

        else if (sr_advance[gk] && gk<NSREG-1)
            sr_valid[gk] <= sr_valid[gk+1];

inside a `for (gk = 0; gk<NSREG; gk=gk+1)` generate, with
`reg [NSREG-1:0] sr_valid`. At `gk = NSREG-1` the index `gk+1` is one past the
end of the packed vector. The branch is statically dead there -- its own
condition contains `gk<NSREG-1` -- and an out-of-range bit-select of a packed
vector is legal Verilog in any case (IEEE 1800 11.5.1: the value is `x`). The
neighbouring lines 320, 357 and 364 write the same guard as a short-circuit
`gk < NSREG-1 && sr_valid[gk+1]`, which Slang folds away; line 337 puts the
guard in the `else if` and the index in the body, which it does not. Note
`sr_id`, `sr_data` and `sr_strb` are declared `[0:NSREG]` -- one entry longer
than needed -- precisely so their `gk+1` reads are in range; `sr_valid` and
`sr_last` were not given the same slack.

Jasper accepts it. Slang promotes `index-oob` to an ERROR and refuses to
elaborate:

    rtl/axi3reorder.v:337:58: error: cannot refer to element 16 of 'reg[15:0]'
                                    [-Windex-oob]

and `v6_dataset/elab_local.py` is the gate every port has to pass. Three routes
were tried:

- `` `pragma diagnostic push / ignore="-Windex-oob" `` around the include in
  `ft/tb.sv`. Does not work -- checked against both this package and a minimal
  reproduction; Slang's diagnostic pragmas do not downgrade a diagnostic that
  is an error by default.
- `-Wno-index-oob` on Slang's command line. Works -- 0 errors, 0 warnings --
  but the harness builds Slang's argv in `taskdefs.slang_args`, which this port
  must not edit.
- Editing `rtl/axi3reorder.v`. **Rejected.** The target is a property ABOUT
  `axi3reorder`; a package whose design source is not the upstream source is a
  different experiment, whatever the edit.

So the switch goes in `lists/tc_elab.files`, which is the only channel to
Slang: `taskdefs.slang_args` copies every non-comment line of that list into
`lists/tc_elab.files.slang` and passes it with `-f`. That same list is the ONE
appendable list the round adds worker lines to, and Jasper's `analyze -f` does
not understand `-W`. So `lists/tc_elab.tcl` reads the list itself
(`wb2axip_analyze_arguments`), drops blank lines, `//` and `#` comments and any
line starting with `-`, prints `SLANG_ONLY_SWITCH_SKIPPED` and
`ANALYZE_ARGUMENTS` for the log, and calls

    analyze -sv12 +incdir+rtl ft/tb.sv [../submission/<worker>.sv ...]

which is exactly what `analyze -f` would have done with the same list. Checked
with `tclsh` against the list as shipped and against a copy with two worker
lines appended: the worker lines come through in order and the switch does not.

## Only one file is analyzed, on purpose

The two RTL files are pulled in by `` `include `` at the top of `ft/tb.sv`,
which is how the source's `tcl/setup.tcl` reaches them too. Listing them as
well would declare both modules twice under `--single-unit`. `+incdir+rtl` is
what makes the includes resolve.

## What changed from the source's tcl/setup.tcl, and why

Kept: `clear -all`, `analyze -sv12` with `+incdir+rtl` (by the route above),
`elaborate -top testbench -disable_auto_bbox`, `set_clock_reference_mode auto`,
`clock clock`, `set_cumulative_reset on`, `reset -expression {reset == 1'b1}
-max_iterations 100`. The reset is on the formal top's own active-high `reset`,
not on the DUT's `S_AXI_ARESETN`; `ft/tb.sv` derives the latter with
`wire reset_n = !reset;`.

Dropped, with reasons:

- **`FROZEN_INPUT_MISSING`**, the existence check over the frozen input set. It
  requires `submission/helpers.sv` to exist before elaboration; v5 stages one
  standalone file per worker under a different name.
- **The name censuses** (`fls_require_exact_names` over
  `FLS_BASE_ASSERTIONS` + `FLS_HELPER_PROPERTIES`, and over
  `FLS_BASE_ASSUMPTIONS`). They demand the elaborated property set equal a list
  computed by a Python front end that v5 does not run. v5 stages a different
  helper set every round, so an exact-match census rejects every legal round.
  Not lost: `cex.tcl` runs `LABEL_INDEX`, `CHECK_FT_MODULES` and
  `CHECK_LABEL_COLLISIONS` after this file.
- **`TARGET_RESOLUTION_FAIL` / `HELPER_RESOLUTION_FAIL`.** Same reason. The
  target census survives in the diag as a printed count that fails only on
  zero.
- **`MULTI_DRIVEN` as an error.** Now reported as
  `MULTIPLE_DRIVEN count=... list=...`. An abort here kills the round before
  any verdict; the number in the log answers the same question.
- **`+define+FLS_EVALUATION` and `+incdir+<submission>`.** See the scrub below.
- **The whole of `tcl/evaluate.tcl`.** That is the source's own property ledger
  and proof policy. v5 brings its own (`v5/grid.tcl`, `CONFIG_GRID`) and writes
  its own report.

Added, not in the source: `AFRA_ELAB_EXTRA` handling (the payload exports it
unconditionally and a recipe that ignores it drops the run's elaborate switches
silently), `set_elab_time_limit`, `compilation -profile`, `task -create FPV`,
the proofgrid profile load, and `wb2axip_analyze_arguments` above.

Deliberately NOT added: `-create_related_covers` / `-witness_cover_property`.
The source task elaborates without them, and they would attach
precondition/witness covers to every helper an agent writes, changing what the
cover phase counts.

## Scrubbed

`ft/tb.sv`, one hunk. Nothing else in the package was edited -- `rtl/` is
byte-identical.

- **3 lines deleted** at the end of the module:

        `ifdef FLS_EVALUATION
        `include "helpers.sv"
        `endif

  Not a leak -- an incompatibility, and the same one `openpiton_pmesh_order`
  removed. In the source flow a submission is one `helpers.sv` textually
  included INSIDE `module testbench`. v5 stages one bound standalone file per
  worker and `v5/elab.tcl` fails a worker whose file does not bind under its
  own module name. Left in, the directive is either inert (no
  `FLS_EVALUATION`) or fatal (no such file), and it would tell an agent to
  write in a shape the harness rejects. This is why the `placement` string for
  this task is the standalone/`bind` one.

Kept deliberately: `` `undef FORMAL `` at line 2. It is not a comment and not
a leak -- it is the task's statement that the ZipCPU files' own `ifdef FORMAL`
harnesses (two in `sfifo.v`, two in `axi3reorder.v`) are NOT part of this
environment. Removing it would silently add the upstream author's own
assertions and assumptions to the property set.

## Dropped hash gates

The source's `DERIVATION.json` was NOT copied. It is a SHA-256 manifest --
`bare_source_task_sha256`, a `source_sha256`/`destination_sha256` pair per
file -- and this repo does not carry content hashes or hash-based validation
gates. Everything from it that is not a hash is recorded above: the top, the
target, the covers, the assumptions, the parameters, the upstream commit and
the derivation notes. The source file remains in the source tree if the
manifest is ever wanted.

## DESIGN_KEEP: this task needs a non-empty one

The target's instrument is registered, exactly as `openpiton_pmesh_order`'s is.
`o_axi3_reorder_e2e` reads `aw_count`, `aw_rptr`, `w_count[m_wid]`,
`w_rptr[m_wid]` and the queues they index, all held in the top level's
`always @(posedge clock)` block. Under `ENTER_FRA_KEEP` every register not
matched by a keep pattern starts arbitrary; cut, `aw_rptr` names an arbitrary
expected ID and `w_rptr` an arbitrary expected beat, so the target is falsified
at cycle 0 for a reason that is not the design's and that nothing in the design
can correct.

The pattern reported for `taskdefs.DESIGN_KEEP`, from `taskdef.json`, is

    (aw|w)_(wptr|rptr|count)

matched unanchored with Tcl `regexp` against instance paths as
`get_design_info -list register` returns them, which is the form
`_CHECKER_KEEP` uses. ONE pattern rather than two, deliberately: `aw_wptr`
contains the substring `w_wptr`, so a separate `w_(wptr|rptr|count)` pattern
would match the `aw_*` registers as well and the `KEEP_PATTERN design` count in
the round log would double-count them. Checked against the elaborated design:
of the 39 registers in this package, exactly 6 match, all six at the top level.
Neither `axi3reorder` nor `sfifo` contains the substring `aw_wptr`, `aw_rptr`,
`aw_count`, `w_wptr`, `w_rptr` or `w_count` anywhere -- checked by reading
them -- so the pattern cannot reach design state.

### The queues' storage is unreset, and the keep set is pointers only

`aw_ref`, `w_data_ref`, `w_strb_ref` and `w_last_ref` are deliberately NOT in
the pattern, for the same reason `openpiton_pmesh_order` leaves `ref_mem` out.
The reset branch of `ft/tb.sv` assigns `aw_wptr`, `aw_rptr`, `aw_count`, the
two `seen_*` cover flags and, per ID, `w_wptr`, `w_rptr`, `w_count` and
`input_beat` -- and nothing else. The four storage arrays are written only on a
push, so they have no reset value at all, and `stopat -reset` cuts a reset
value. Keeping a register that has none is a no-op: those
16 x 2 + 4 x 32 x 10 = 1312 bits start arbitrary whether or not a pattern
matches them, and matching them would only inflate a number that is read as a
measurement.

So the kept state is exactly

    aw_wptr     4 bits
    aw_rptr     4 bits
    aw_count    5 bits
    w_wptr      4 x 5 bits
    w_rptr      4 x 5 bits
    w_count     4 x 6 bits     = 77 bits

and the instrument is anchored at its POINTERS, not at its memory. "A read
entry was written" is therefore a property that has to hold, not something the
keep set establishes: the target requires `aw_count != 0` before reading
`aw_ref[aw_rptr]` and `w_count[m_wid] != 0` before reading
`w_data_ref[m_wid][w_rptr[m_wid]]`, and a count only becomes non-zero through
a push, which is the same event that writes the entry at the write pointer.

Left cut deliberately:

- `input_beat` -- stimulus, not instrument. It only gates
  `A_FIXED_PACKET_LAST`, which forces `s_wlast` on the fourth beat of an ID.
  An arbitrary start moves where the first packet of that ID ends; an
  assumption cannot falsify a target.
- `past_valid` -- it only gates `A_AW_STICKY` and `A_W_STICKY`, again
  assumptions. It also carries an `initial past_valid = 1'b0;`, which the reset
  cut does not touch.
- `seen_interleaved`, `seen_wrap` -- read by covers only, never by the target.

All six kept families are reset-assigned, so the pattern cannot match zero and
cannot trip `cex.tcl`'s "design keep pattern matched nothing" FAIL. Expect 18
hits if Jasper lists array elements individually, 6 if it lists arrays.

## Not verified

The Slang gate passes:

    uv run python v6_dataset/elab_local.py --task wb2axip_axi3_reorder
    OK: wb2axip_axi3_reorder elaborates

and `hierarchy.build_ir` builds the design map from it -- 3 instances, 39
registers, the fifteen top-level registers among them. What has NOT been run is
Jasper: no `analyze`/`elaborate` under `lists/tc_elab.tcl`, no register census,
no `KEEP_PATTERN design` hit count, no proof. Slang and Jasper disagree about
some SystemVerilog and only Jasper's verdict admits a file to a round.

`wb2axip_analyze_arguments` in particular has been exercised with `tclsh`
against the real list, but not inside Jasper. If it ever misbehaves the symptom
will be loud -- `ANALYZE_ARGUMENTS` is printed before `analyze` runs.

Also checked locally, because the `placement` string promises it: a standalone
module carrying one `assert property` and one `cover property`, bound in with
`bind testbench ...`, elaborates against this package (`elab_local.py --extra`).
That is the shape v5 stages one of per worker.

## Known caveat: the target is an immediate assertion, so `derive_targets` cannot locate it

`taskdefs.derive_targets` looks for a line that starts with `<label>:` and
contains the literal `assert property`. This package's target does not have
that shape -- it is an immediate assertion inside the checker's clocked always
block, `o_axi3_reorder_e2e: assert (` followed by the condition on later lines
-- so `derive_targets` returns `source: ""`, `line: 0` and the model phase
renders

    - `o_axi3_reorder_e2e` — not located in the mounted sources

instead of a file and line. Nothing else is affected: `v5/round.py` reads
`TASKS[task]["target_labels"]` and `cex.tcl:LABEL_INDEX` keys on the last
dot-separated component, so `o_axi3_reorder_e2e` resolves in a round, and the
diag census finds it by name. The cost is that a model-phase agent is told the
target's name but not where to read it.

This is not fixable inside the package without rewriting the source's target
into a concurrent assertion, which would change what the task measures. The fix
is in `taskdefs.TARGET_PATTERN`, which this port was told not to touch. It
applies identically to the other four packages in this group.

## Phase-1 candidate targets, added 2026-08-19

    sva/targets_wb2axip_axi3_reorder.sv  35 `T_*` assertions, 21 `C_*` covers
    lists/targets.txt                    35 rows, `label TAB category TAB intent`

Appended LAST to `lists/tc_elab.files` as a PLAIN path line -- this package's
`tc_elab.tcl` parses that list itself and drops `-`-prefixed lines, so only a
plain path reaches `analyze`. Checked by running the recipe's own parser over
the edited list:

    SLANG_ONLY_SWITCH_SKIPPED -Wno-index-oob
    ANALYZE_ARGUMENTS +incdir+rtl ft/tb.sv sva/targets_wb2axip_axi3_reorder.sv

`taskdef.json`'s `mount` gained `sva`. The gate passes without `--extra`:

    uv run python v6_dataset/elab_local.py --task wb2axip_axi3_reorder
    OK: wb2axip_axi3_reorder elaborates

The oracle is deliberately a different SHAPE from `ft/tb.sv`'s four per-ID
rings: one 32-entry ARRIVAL ring shared by every ID, each entry carrying its
ID, payload, in-packet beat position and a live bit. The beat the master port
presents must be the oldest live entry of that ID, found by walking the ring
from its oldest slot -- per-ID FIFO order stated without a per-ID pointer.
`taskdefs.oracle_keep` derives `axi3_reorder_targets\.` from the bind.

Twelve of the fifteen categories are admitted. NOT admitted, and why: **10
arbitration fairness** (there is no arbitration freedom -- output order is
dictated by the AW queue, which is category 1 here); **14 lifecycle / access
control** (`current_id` advances one beat before the packet's last beat is
accepted, so the obvious "token stable within a packet" statement is false, and
what remains is the non-interleaving rule already in category 5); **15
coherence** (no agents).

### Not verified, and what is uncertain

Jasper has NOT been run. The judgement calls:

- `T_CONSERV_AW_OUTSTANDING_EQ_FIFO_PLUS_CURRENT` carries the
  `(M_AXI_WVALID && M_AXI_WLAST)` term because `read_awid_fifo` pops the next
  ID when the last beat is LOADED, one step before it is accepted. If that
  reading is wrong the assertion is a cex, and it is the one most worth
  watching.
- `T_REQRSP_CURRENT_ID_IS_AW_QUEUE_ENTRY` has the same off-by-one built into
  it, as `expect_cid`.
- `T_MUTEX_SR_VALID_IS_CONTIGUOUS` claims the shift register's valid bits are
  one run from station zero.
- Every bounded-response and deadlock counter is guarded on the HEAD packet's
  ID having a beat inside the design. Unguarded they are false, and that is the
  module's own documented caveat: fill the W FIFO with the wrong IDs and it
  waits forever. `T_DEADLOCK_SHIFT_REGISTER_DRAINS_WITHIN_N` was considered and
  deliberately NOT written for that reason.
