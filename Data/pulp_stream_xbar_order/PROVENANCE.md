# pulp_stream_xbar_order provenance

assembled: 2026-08-19

source: an earlier internal task package
        (copied out of; the source tree was not modified)

upstream RTL: common_cells @ c63eada47c050f78b320d0e854a24a9cd9c1cc80
              (pulp-platform), nine `src/cc_*.sv` files and three
              `include/common_cells/*.svh` headers, byte-for-byte per the
              source's DERIVATION.json. The `cc_` prefix is the upstream task's
              renaming of the library's own `src/` names, carried over as it
              found them.

Four ready/valid inputs each buffer in a 4-deep `cc_stream_fifo`, a 4x4
`cc_stream_xbar` (round-robin, `LockIn`, `AxiVldRdy`, with an output spill
register) switches them by a 2-bit destination carried in the payload, and each
output buffers in another 4-deep `cc_stream_fifo`. Sixteen independent
reference rings -- one per (source, destination) pair, 16 entries each --
record what was pushed, and the target says each output delivers its
(source, destination) stream in order and no ring overflows. The crossbar's own
`idx_o` is what names the source at the output.

top: testbench
environment: lists/diag_pulp_stream_xbar_order.tcl
             (task `diag_pulp_stream_xbar_order`; declares no assumptions of
             its own -- the package's five live in `ft/tb.sv`)
target: T_BUFFERED_XBAR_ORDER  (testbench.T_BUFFERED_XBAR_ORDER)

The source's `DERIVATION.json` also lists four covers -- `C_INPUT_BACKLOG`,
`C_SAME_OUTPUT_CONTENTION`, `C_ALL_OUTPUTS`, `C_REFERENCE_WRAP` -- and five
assumptions -- `A_RESET_IDLE`, `A_IN{0,1,2,3}_STICKY`. All nine elaborate with
the package. The covers are what `COVER_DEPTH` counts if a round is given
`--cover-s`; they are not targets.

Parameters, from the source's `DERIVATION.json`: `data_width=8`, `inputs=4`,
`outputs=4`, `input_fifo_depth=4`, `output_fifo_depth=4`,
`xbar_output_spill_register=true`, `reference_depth_per_source_output=16`.

## What was carried over unchanged

Byte-identical to the source:

    rtl/cc_pkg.sv
    rtl/cc_lzc.sv
    rtl/cc_rr_arb_tree.sv
    rtl/cc_spill_register_flushable.sv
    rtl/cc_spill_register.sv
    rtl/cc_stream_demux.sv
    rtl/cc_stream_xbar.sv
    rtl/cc_fifo.sv
    rtl/cc_stream_fifo.sv
    rtl/common_cells/assertions.svh
    rtl/common_cells/registers.svh
    rtl/common_cells/deprecated/registers.svh

`ft/tb.sv` differs from the source by exactly one hunk, recorded under
"scrubbed" below. Every line of the composition, the reference model, the
assumptions, the target and the covers is the source's -- including
`` `define COMMON_CELLS_ASSERTS_OFF `` at line 2, which is what compiles the
library's own `assert` macros out and is load-bearing.

This package needed NO `` `timescale `` repair: no common-cells file declares
one, so nothing in the design has one and Slang's mixed-time-scale error does
not arise.

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
    lists/diag_pulp_stream_xbar_order.tcl
                               defines `setup_diag_pulp_stream_xbar_order`,
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

## Only one file is analyzed, on purpose

`lists/tc_elab.files` lists one Slang switch (below), `+incdir+rtl` and
`ft/tb.sv`, and nothing else. The nine RTL files are pulled in by
`` `include `` at the top of `ft/tb.sv`, in dependency order and after
`COMMON_CELLS_ASSERTS_OFF` is defined, which is how the source's
`tcl/setup.tcl` reaches them too. Listing them as well would declare every
module twice under `--single-unit` and would compile `cc_pkg.sv` outside the
order the rest depends on. `+incdir+rtl` does double duty: it resolves those
nine includes AND the `common_cells/assertions.svh`,
`common_cells/registers.svh` and `common_cells/deprecated/registers.svh`
headers the RTL includes by that exact prefixed path.

## Slang needs a switch, and Jasper cannot see it

This package and `wb2axip_axi3_reorder` are the two in this porting group whose
`lists/tc_elab.tcl` does NOT say `analyze -sv12 -f lists/tc_elab.files`. The
reason is worth recording, because the alternative was editing the checker.

`ft/tb.sv` writes three variables from two processes:

    past_valid   `initial past_valid = 1'b0;` (line 171) and the `always_ff`
                 (line 174) -- the ordinary formal past-valid idiom.
    s, d         the loop counters, declared once as `integer` and reused by
                 BOTH the `always_comb` that computes `target_ok` and the
                 `always_ff` that maintains the reference rings. Each block
                 assigns them before reading them, so neither can see the
                 other's value.

Slang promotes `multiple-always-assigns` to an ERROR and refuses:

    ft/tb.sv:174:9: error: variable 'past_valid' driven by always_ff procedure
                           cannot be written to by any other process
                           [-Wmultiple-always-assigns]
    ft/tb.sv:178:18: error: variable 's' ...
    ft/tb.sv:179:22: error: variable 'd' ...

Jasper takes all three, and `v6_dataset/elab_local.py` is the gate every port
has to pass. `-Wno-multiple-always-assigns` on Slang's command line clears all
three (0 errors, 0 warnings), but the harness builds Slang's argv in
`taskdefs.slang_args`, which this port must not edit. Editing `ft/tb.sv` to
give the two blocks their own counters was rejected: the reference model IS the
task's statement of what it is checking, and a package whose checker is not the
upstream checker is a different experiment.

So the switch goes in `lists/tc_elab.files`, which is the only channel to
Slang: `taskdefs.slang_args` copies every non-comment line of that list into
`lists/tc_elab.files.slang` and passes it with `-f`. That same list is the ONE
appendable list the round adds worker lines to, and Jasper's `analyze -f` does
not understand `-W`. So `lists/tc_elab.tcl` reads the list itself
(`pulp_analyze_arguments`), drops blank lines, `//` and `#` comments and any
line starting with `-`, prints `SLANG_ONLY_SWITCH_SKIPPED` and
`ANALYZE_ARGUMENTS` for the log, and calls

    analyze -sv12 +incdir+rtl ft/tb.sv [../submission/<worker>.sv ...]

which is exactly what `analyze -f` would have done with the same list. Checked
with `tclsh` against the real list: the switch is dropped, `+incdir+rtl` and
`ft/tb.sv` come through in order, and appended worker lines would follow them.

## What changed from the source's tcl/setup.tcl, and why

Kept: `clear -all`, `analyze -sv12` with `+incdir+rtl` (by the route above),
`elaborate -top testbench -disable_auto_bbox`, `set_clock_reference_mode auto`,
`clock clock`, `set_cumulative_reset on`, `reset -expression {reset == 1'b1}
-max_iterations 100`. The reset is on the formal top's own active-high `reset`,
not on the library's `rst_ni`; `ft/tb.sv` derives the latter with
`logic rst_n; assign rst_n = !reset;`.

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
  `CHECK_LABEL_COLLISIONS` after this file. (This package's `setup.tcl` had
  already softened the COVER census to `fls_require_names_present` for the same
  reason -- Jasper adds diagnostic covers for submitted helpers.)
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
the proofgrid profile load, and `pulp_analyze_arguments` above.

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

Kept deliberately: `` `define COMMON_CELLS_ASSERTS_OFF `` at line 2. It is not
a comment and not a leak -- it is the task's statement that the common-cells
library's own assertion macros are NOT part of this property set. Removing it
would silently add the upstream library's assertions to the elaborated set.

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
`target_ok` is combinational, but every term it reads is checker state held in
the top level's `always_ff`:

    ref_count[s][d]   the per-(source,destination) occupancy the target
                      compares against
    ref_rptr[s][d]    where in the ring the next delivered beat must match
    ref_wptr[s][d]    where the next push lands (and so what rptr chases)

Under `ENTER_FRA_KEEP` every register not matched by a keep pattern starts
arbitrary. Cut, `ref_rptr` points at an arbitrary ring entry and
`T_BUFFERED_XBAR_ORDER` is falsified at cycle 0 for a reason that is not the
design's and that nothing in the design can correct.

The pattern reported for `taskdefs.DESIGN_KEEP`, from `taskdef.json`, is

    ref_(wptr|rptr|count)

matched unanchored with Tcl `regexp` against instance paths as
`get_design_info -list register` returns them, which is the form
`_CHECKER_KEEP` uses. Checked against the elaborated design: of the 656
registers in this package's 42 instances, exactly 3 names match, all three at
the top level. No common-cells file contains the substring `ref_wptr`,
`ref_rptr` or `ref_count` anywhere -- checked by reading them -- so the pattern
cannot reach design state. The 16 FIFOs, the arbiter tree, the demuxes and the
spill registers all stay cut.

### The rings' storage is unreset, and the keep set is pointers only

`data_ref` is deliberately NOT in the pattern, for the same reason
`openpiton_pmesh_order` leaves `ref_mem` out. The reset branch of `ft/tb.sv`
assigns `seen_wrap`, `ref_wptr`, `ref_rptr` and `ref_count` and nothing else;
`data_ref` is written only on a push. So it has no reset value at all, and
`stopat -reset` cuts a reset value -- keeping a register that has none is a
no-op. Those 4 x 4 x 16 x 8 = 2048 bits start arbitrary either way, and
matching them would only inflate the `KEEP_PATTERN design` count in the round
log, which is read as a measurement.

So the kept state is exactly

    ref_wptr    16 x 4 bits
    ref_rptr    16 x 4 bits
    ref_count   16 x 5 bits    = 208 bits

and the instrument is anchored at its POINTERS, not at its memory. "A read
entry was written" is therefore a property that has to hold, not something the
keep set establishes: the target requires `ref_count[src][d] != 0` before it
reads `data_ref[src][d][ref_rptr[src][d]]`, and a count only becomes non-zero
through a push, which is the same event that writes `data_ref` at `ref_wptr`.

Left cut deliberately:

- `past_valid` -- it only gates the four `A_IN*_STICKY` assumptions. Arbitrary
  either way it changes the assumption set, and an assumption cannot falsify a
  target. It also carries an `initial past_valid = 1'b0;`, which the reset cut
  does not touch.
- `seen_wrap` -- read by `C_REFERENCE_WRAP` only, never by `target_ok`.
- `rst_n` -- a continuous assign off `reset`, not state.

All three kept families are reset-assigned, so the pattern cannot match zero
and cannot trip `cex.tcl`'s "design keep pattern matched nothing" FAIL. Expect
48 hits if Jasper lists array elements individually, 3 if it lists arrays.

## Not verified

The Slang gate passes:

    uv run python v6_dataset/elab_local.py --task pulp_stream_xbar_order
    OK: pulp_stream_xbar_order elaborates

and `hierarchy.build_ir` builds the design map from it -- 42 instances, 656
registers, twenty-six of the names at the top level. What has NOT been run is
Jasper: no `analyze`/`elaborate` under `lists/tc_elab.tcl`, no register census,
no `KEEP_PATTERN design` hit count, no proof. Slang and Jasper disagree about
some SystemVerilog and only Jasper's verdict admits a file to a round.

`pulp_analyze_arguments` in particular has been exercised with `tclsh` against
the real list, but not inside Jasper. If it ever misbehaves the symptom will be
loud -- `ANALYZE_ARGUMENTS` is printed before `analyze` runs.

Also checked locally, because the `placement` string promises it: a standalone
module carrying one `assert property` and one `cover property`, bound in with
`bind testbench ...`, elaborates against this package (`elab_local.py --extra`).
That is the shape v5 stages one of per worker.

## Known caveat: the target is an immediate assertion, so `derive_targets` cannot locate it

`taskdefs.derive_targets` looks for a line that starts with `<label>:` and
contains the literal `assert property`. This package's target does not have
that shape -- it is an immediate assertion inside the checker's `always_ff`:

    T_BUFFERED_XBAR_ORDER: assert (target_ok);

so `derive_targets` returns `source: ""`, `line: 0` and the model phase renders

    - `T_BUFFERED_XBAR_ORDER` — not located in the mounted sources

instead of a file and line. Nothing else is affected: `v5/round.py` reads
`TASKS[task]["target_labels"]` and `cex.tcl:LABEL_INDEX` keys on the last
dot-separated component, so `T_BUFFERED_XBAR_ORDER` resolves in a round, and
the diag census finds it by name. The cost is that a model-phase agent is told
the target's name but not where to read it.

This is not fixable inside the package without rewriting the source's target
into a concurrent assertion, which would change what the task measures. The fix
is in `taskdefs.TARGET_PATTERN`, which this port was told not to touch. It
applies identically to the other four packages in this group.
