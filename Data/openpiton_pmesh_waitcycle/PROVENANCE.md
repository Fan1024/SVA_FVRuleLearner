# openpiton_pmesh_waitcycle provenance

assembled: 2026-08-19

source: an earlier internal task package
        (copied out of; the source tree was not modified)

Nine one-shot eight-flit packets, one from every processor port, converge on
tile 8 of a real 3x3 OpenPiton P-Mesh at `+define+PMESH_X_TILES=3
+define+PMESH_Y_TILES=3` over real dimension-ordered routes. The formal top taps
each of the nine active-NoC routers for three things -- directional input-FIFO
occupancy (`elements_in_array_f`), the head flit's route requests
(`route_req_<in>_to_<out>`) and per-output downstream credit
(`space_avail_connection`) -- and the checker builds the live 36-node
inter-router wait-for graph from them (9 tiles x 4 directions), computes its
exact transitive closure with a Floyd-Warshall triple loop in one `always @*`,
and asserts that the closure has no self-reachable node: no wait-for cycle. The
router RTL is upstream OpenPiton; the mesh wrapper is shared with
`tasks/openpiton_pmesh_order/`; the packet sources, the formal top and the
checker are task-authored.

top: openpiton_pmesh_deadlock_ft
environment: lists/diag_pmesh_waitcycle.tcl  (task `diag_pmesh_waitcycle`)
target: T_WAIT_GRAPH_ACYCLIC
        (openpiton_pmesh_deadlock_ft.u_checker.T_WAIT_GRAPH_ACYCLIC)

## The names say "deadlock". That is not a mistake

The top module is `openpiton_pmesh_deadlock_ft`, the checker module is
`openpiton_pmesh_deadlock_checker`, and the two files are named after them.
Upstream, this task was derived from `openpiton_pmesh_deadlock_v7` and the
names came along; the two packages ship files with the SAME names and DIFFERENT
contents. They were not renamed here, because renaming the files without
renaming the modules would leave a package whose file names disagree with the
modules they declare, and renaming the modules is a source edit that PORTING.md
does not want.

So: the task is `openpiton_pmesh_waitcycle`, the target is
`T_WAIT_GRAPH_ACYCLIC`, and `openpiton_pmesh_deadlock_ft` is just what the top
is called. `tasks/openpiton_pmesh_deadlock/` is a different package with a
different checker, a different target (`T_DEADLOCK`), a 2x2 mesh and four
assumptions instead of one. Nothing is shared between them but the fabric.

## The environment

One assumption, `u_checker.A_FAIR_SINK`: the destination processor egress at
tile 8 -- modelled as an explicit four-credit buffer, and the only endpoint
that does not drain immediately -- accepts at least once in every four-cycle
window. Every other tile's `pIn_yummy` is wired straight to its own
`pOut_valid`, so those endpoints return credit the same cycle.

The source `DERIVATION.json` also lists 5 covers (`C_ALL_SOURCES_ACTIVE`,
`C_WAIT_EDGE`, `C_TWO_WAIT_EDGES`, `C_TWO_HOP_WAIT`, `C_XY_WAIT`). They
elaborate with the package and are what `COVER_DEPTH` will count if a round is
given `--cover-s`. They are not targets.

Parameters, from `DERIVATION.json`: X_TILES 3, Y_TILES 3, NOCS 3, ACTIVE_NOC 0,
ACTIVE_FLOWS 9, PACKETS_PER_SOURCE 1, PACKET_BODY_FLITS 7, FAIR_SINK_WINDOW 4,
WAIT_GRAPH_NODES 36.

## What was carried over unchanged

Byte-identical to the source:

    rtl/openpiton_dn/*   20 files + define.tmp.vh, upstream OpenPiton
    sva/openpiton_pmesh_deadlock_checker.sv

`rtl/openpiton_dn/` was taken from `tasks/openpiton_pmesh_order/rtl/` rather
than from this source, after checking with `diff -r` that the two are identical
-- the source's own transform note says the same ("Reused the byte-identical
real OpenPiton dynamic-node and P-Mesh sources from the registered ordering
task"). `rtl/pmesh_top.v` came from there too; the source's copy and the
ordering task's source copy are byte-identical, checked with `diff`.

`ft/openpiton_pmesh_deadlock_ft.sv` differs from the source by the three
deleted lines recorded under "scrubbed" below and by nothing else.

## What was written for this package

`lists/` did not exist in the source and is entirely new. Every file in it is
the corresponding `tasks/openpiton_pmesh_order/lists/` file with the top
module, the task name, the source file names and the target label changed; the
tile-count defines are the same 3x3. That package's `PROVENANCE.md` records why
each file says what it says, and none of that reasoning changes here.

    lists/tc_elab.files            the analyzed file list, package-root-relative.
                                   Also `TASKS[...]["slang"]["command_file"]`,
                                   which is the file the round appends one
                                   `../submission/<worker>.sv` line to per
                                   worker.
    lists/tc_elab.tcl              the elaboration recipe. `elaborate -top
                                   openpiton_pmesh_deadlock_ft`.
    lists/diag_pmesh_waitcycle.tcl defines `setup_diag_pmesh_waitcycle`, creates
                                   the Jasper task `diag_pmesh_waitcycle`,
                                   prints the assumption and target census.
                                   Unlike the pmesh_order diag it counts ALL
                                   elaborated assumptions, not only
                                   `diag_*`-prefixed ones, because this package
                                   ships its own and a `diag_*` filter would
                                   print 0 and read as "unconstrained".
    lists/reset_modes.tcl          `rm_all_registers` + `_rm_apply_reset` and
                                   their globals, which is all `v5/cex.tcl`
                                   calls, plus a little reporting.
    taskdef.json                   the per-task definition, dropped in beside the
                                   package rather than added to
                                   `taskdefs.TASKS`.

Copied verbatim from `tasks/openpiton_pmesh_order/lists/` because both are
task-agnostic: `proofgrid_profiles.tcl`, `vendor/iterdev_utils.tcl`.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on the first
model run. It is derived, not authored.

## What changed from the source's tcl/setup.tcl, and why

Identical in shape to what `tasks/openpiton_pmesh_order/PROVENANCE.md` records;
the two source `setup.tcl` files differ only in a header comment and the target
name.

Kept: `clear -all`, the analyze set, `+incdir+rtl/openpiton_dn`, the two
`PMESH_*_TILES` defines, `elaborate -top openpiton_pmesh_deadlock_ft
-disable_auto_bbox`, `set_clock_reference_mode auto`, `clock clk`,
`set_cumulative_reset on`, `reset -expression {reset_n == 1'b0}
-max_iterations 100`.

Dropped, with reasons: the `FROZEN_INPUT_MISSING` check; the name censuses
(`fls_require_exact_names` over `FLS_BASE_ASSERTIONS` + `FLS_HELPER_PROPERTIES`
and over the assumptions) -- they demand the elaborated property set equal a
list a Python front end computes, and v5 stages a different helper set every
round; `TARGET_RESOLUTION_FAIL` / `HELPER_RESOLUTION_FAIL`, same reason;
`MULTI_DRIVEN` as an error, now reported as `MULTIPLE_DRIVEN count=... list=...`;
`+define+FLS_EVALUATION` and `+incdir+<submission>`, see the scrub;
`tcl/evaluate.tcl` in its entirety. `tcl/` was not copied at all.

Two analyze calls became one, for the reason recorded for the other two pmesh
packages: v5 appends each worker's file to ONE list, and the Verilog-2001
dynamic-node files declare no identifier that SystemVerilog-2012 reserves.

Added, not in the source: `AFRA_ELAB_EXTRA` handling, `set_elab_time_limit`,
`compilation -profile`, `task -create FPV`, the proofgrid profile load.

Deliberately NOT added: `-create_related_covers` / `-witness_cover_property`.

## Scrubbed

- `ft/openpiton_pmesh_deadlock_ft.sv`, 3 lines deleted at the end of the
  module:

        `ifdef FLS_EVALUATION
        `include "helpers.sv"
        `endif

  Not a leak -- an incompatibility, and the same one recorded for
  `openpiton_pmesh_order`. In the source flow a submission is one `helpers.sv`
  textually included INSIDE the top module. v5 stages one bound standalone file
  per worker and `v5/elab.tcl` fails a worker whose file does not bind under
  its own module name. Left in, the directive is either inert (no
  `FLS_EVALUATION`) or fatal (no such file), and it would tell an agent to
  write in a shape the harness rejects.

- `rtl/pmesh_top.v`, 4 comment hunks, inherited by taking the already-scrubbed
  copy from `tasks/openpiton_pmesh_order/`: references to a golden FV
  environment that is not in this package -- the bound `fv_pmesh` harness,
  `FV_pmesh.sv`, `FV_pmesh_assumes`, `FV_pmesh_endpoint_model`, and the
  an internal FV model comparison -- and to the VC-deadlock proof this fabric
  was first packaged for.

  As for `openpiton_pmesh_deadlock`, the case is stronger here than it was for
  pmesh_order. The deleted sentence "the VC-deadlock property lives in the NoC
  priority scheme (NoC3 never blocked by NoC1/2)" is about the multi-NoC
  priority argument; this task runs ONE NoC (`NOC_ID = 0`) and asks whether the
  single-NoC inter-router wait-for graph is acyclic. Left in, it is an
  authoritative-sounding pointer at the wrong invariant, on top of naming an
  environment an agent could go hunting for. Code untouched; all three pmesh
  packages carry the identical file.

Kept deliberately: the formal top's header comment (nine finite eight-flit
packets converging on tile 8, and what the target observes) and the comment
above the observation block that fixes the direction encoding
("north, east, south, west; `route_req[T][4*I+O]` is input I to output O").
That encoding is load-bearing for reading the checker at all and is recoverable
from the twelve `assign` statements below it in any case.

## Dropped hash gates

The source's `DERIVATION.json` was NOT copied. It is a SHA-256 manifest --
`bare_source_task_sha256`, a `source_sha256`/`destination_sha256` pair per file
-- and this repo does not carry content hashes or hash-based validation gates.
Everything from it that is not a hash is recorded above: the top, the target,
the assumption, the 5 covers, the parameters and the derivation notes.

## DESIGN_KEEP: empty, and that IS the rule here

`taskdef.json` carries `"design_keep": []`.

Unlike the other two pmesh packages, this target's instrument holds no state.
The whole checker is one combinational `always @*`: `wait_edge`, `reach`,
`wait_cycle`, `wait_edge_count`, `wait_path2`, `horizontal_wait` and
`vertical_wait` are declared `reg` but are assigned with blocking assignments
in a combinational block, driven every evaluation from the formal top's taps.
`T_WAIT_GRAPH_ACYCLIC` reads `wait_cycle` and nothing else. There is no
register a reset cut could make arbitrary, so there is nothing to keep, and an
invented pattern would either match nothing -- which trips `cex.tcl`'s "design
keep pattern matched nothing" FAIL -- or keep design state and delete the task.
This is the same call `l15_l2_mshr_onehot` makes for the same reason.

Everything that IS registered is design or environment and stays cut: the nine
packet sources (`active_f`, `launched_f`, `body_left_f`, `payload_f`), the nine
`space_avail_top` credit counters, `sink_occupancy` in the formal top, and
every register inside the nine routers -- including the input FIFOs whose
occupancy and the output credit state the wait graph is built from. Starting
those arbitrary is exactly what makes the target hard, and constraining them
back to reachable shapes is what a round is asking an agent to do.

`dut_ready` in the formal top is also left cut. It gates `checker_reset_n`;
arbitrary-1 is the normal case and arbitrary-0 merely holds the checker in
reset for one cycle with `T_WAIT_GRAPH_ACYCLIC` disabled by its own
`disable iff`. Same call as pmesh_order.

## Verified

    uv run python v6_dataset/elab_local.py --task openpiton_pmesh_waitcycle
    OK: openpiton_pmesh_waitcycle elaborates

Slang, run directly with the same argv, reports `0 errors, 0 warnings`. That
run is what proves the formal top's taps resolve through the 3x3 generate
hierarchy: 36 `...<dir>_input.NIB.elements_in_array_f`, 144
`...route_req_<in>_to_<out>` and 36 `...<dir>_output.space_avail_connection`
hierarchical references, any one of which is an elaboration error if the name
is wrong.

`taskdefs.TASKS` admits the task, `taskdefs.DESIGN_KEEP` carries the empty
list, and `taskdefs.derive_targets` locates `T_WAIT_GRAPH_ACYCLIC` at
`sva/openpiton_pmesh_deadlock_checker.sv:100`.

## Not verified

No Jasper elaboration has been run: `tc_elab.tcl`, `diag_pmesh_waitcycle.tcl`
and `reset_modes.tcl` are unexecuted. Slang and Jasper disagree about some
SystemVerilog and only Jasper's verdict admits a package to a round.

One thing to watch on the first Jasper run, specific to this package: the
checker's transitive closure is a 36 x 36 x 36 triple loop over 36-bit vectors
inside a single combinational block, unrolled at elaboration. That is the
largest single combinational cone in any of the four packages ported today and
it is the plausible place for `set_elab_time_limit 3600s` to matter. It costs
Slang nothing measurable, which is weak evidence about Jasper.

## Known blocker, not fixable inside this package

The one recorded at the end of `tasks/openpiton_pmesh_order/PROVENANCE.md`
applies unchanged: `v5/round.py` emits the hardcoded `v4pre_round.TARGETS`
the internal reference task pair rather than `taskdefs.TASKS[task]["target_labels"]`, so a round
on this task resolves no target and `cex.tcl` aborts with `no target property
resolved`. The model phase is unaffected. The fix is one line in
`v5/round.py`, which a porting agent was told not to touch.
