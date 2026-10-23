# verilog_ethernet_fcs_roundtrip provenance

assembled: 2026-08-19

source: an earlier internal task package
        (copied out of; the source tree was not modified)

upstream RTL: verilog-ethernet @ 77320a9471d19c7dd383914bc049e02d9f4f1ffb
              (alexforencich), `rtl/lfsr.v`, `rtl/axis_eth_fcs_insert.v` and
              `rtl/axis_eth_fcs_check.v`, byte-for-byte per the source's
              DERIVATION.json.

An 8-bit AXI-Stream goes through `axis_eth_fcs_insert`, which appends a
four-byte Ethernet FCS computed by the `lfsr` CRC32 core, straight into
`axis_eth_fcs_check`, which recomputes it, strips it and raises
`error_bad_fcs` if it does not match. A 64-entry reference ring records every
accepted input byte and its `tlast`. The target says the round trip is the
identity: `error_bad_fcs` never rises, the output stream is the ring in order
byte for byte and `tlast` for `tlast`, no output beat is marked bad, and the
ring never overflows.

top: testbench
environment: lists/diag_verilog_ethernet_fcs_roundtrip.tcl
             (task `diag_verilog_ethernet_fcs_roundtrip`; declares no
             assumptions of its own -- the package's four live in `ft/tb.sv`)
target: T_FCS_ROUNDTRIP  (testbench.T_FCS_ROUNDTRIP)

The source's `DERIVATION.json` also lists four covers -- `C_FCS_EMITTED`,
`C_OUTPUT_BACKPRESSURE`, `C_TWO_FRAMES`, `C_REFERENCE_WRAP` -- and four
assumptions -- `A_RESET_IDLE`, `A_INPUT_GOOD`, `A_INPUT_STICKY`,
`A_FRAME_AT_MOST_16_BYTES`. All eight elaborate with the package. The covers
are what `COVER_DEPTH` counts if a round is given `--cover-s`; they are not
targets. `C_FCS_EMITTED` reaches into the DUT by hierarchical name
(`insert_dut.state_reg == 2'd3`); that is the source's own code and it is kept.

Parameters, from the source's `DERIVATION.json`: `stream_width_bits=8`,
`maximum_source_frame_bytes=16`, `reference_bytes=64`. The insert core is
instantiated with `ENABLE_PADDING(0)`, `MIN_FRAME_LENGTH(64)`.

`A_FRAME_AT_MOST_16_BYTES` is worth naming as an environment fact rather than a
nicety: it is what keeps a frame plus its FCS inside the 64-entry ring.

## Ported from `tasks/`, not from the earlier partial attempt

There is a 2026-07-30 staging attempt at
an internal staging area.
It was not a port to this harness at all: it targets the **ric3** engine
(`engine/ric3.toml`, `parser = "yosys_slang"`, `[dut] files = ["ft/tb.sv"]`,
`reset = "reset"`, `top = "testbench"`) and carries no Jasper recipe, no
property census and no submission hook. Its `ft/tb.sv` is otherwise identical
to the one in `tasks/` -- the only difference is the `FLS_EVALUATION` include
block that the `tasks/` version added and this port scrubs back out. Reading it
was useful only to establish that; **this port is from the current
`tasks/verilog_ethernet_fcs_roundtrip_v2`** and nothing was taken from the
staging tree.

## What was carried over unchanged

Byte-identical to the source:

    rtl/lfsr.v
    rtl/axis_eth_fcs_insert.v
    rtl/axis_eth_fcs_check.v

`ft/tb.sv` differs from the source by exactly the two hunks recorded under
"scrubbed" below. Every line of the composition, the reference model, the
assumptions, the target and the covers is the source's.

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
    lists/diag_verilog_ethernet_fcs_roundtrip.tcl
                               defines
                               `setup_diag_verilog_ethernet_fcs_roundtrip`,
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

`lists/tc_elab.files` lists `+incdir+rtl` and `ft/tb.sv`, and nothing else. The
three RTL files are pulled in by `` `include `` at the top of `ft/tb.sv`, which
is how the source's `tcl/setup.tcl` reaches them too. Listing them as well
would declare every module twice under `--single-unit`. `+incdir+rtl` is what
makes the includes resolve, and it is the one thing in the list that is not a
source line -- the round's appended `../submission/<worker>.sv` lines stay
source lines at the end, as they must.

## What changed from the source's tcl/setup.tcl, and why

Kept: `clear -all`, `analyze -sv12` with `+incdir+rtl`, `elaborate -top
testbench -disable_auto_bbox`, `set_clock_reference_mode auto`, `clock clock`,
`set_cumulative_reset on`, `reset -expression {reset == 1'b1}
-max_iterations 100`.

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
and the proofgrid profile load.

Deliberately NOT added: `-create_related_covers` / `-witness_cover_property`.
The source task elaborates without them, and they would attach
precondition/witness covers to every helper an agent writes, changing what the
cover phase counts.

## Scrubbed

`ft/tb.sv`, two hunks. Nothing else in the package was edited.

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

- **3 lines added** after the includes:

        // Restored after the includes: every verilog-ethernet file ends with
        // `resetall, which clears the `timescale they set at their top.
        `timescale 1ns / 1ps

  All three verilog-ethernet files open with `` `resetall ``,
  `` `timescale 1ns / 1ps ``, `` `default_nettype none `` and close with
  `` `resetall ``. The closing `` `resetall `` clears the time scale, so
  `module testbench` -- declared after the includes -- has none while the three
  RTL modules do. Slang rejects that outright (`design element does not have a
  time scale defined but others in the design do`) and
  `v6_dataset/elab_local.py` is the gate. The fix has to live in the source
  rather than in the file list, because that list is fed to BOTH Jasper's
  `analyze -f` and Slang's `-f`, and `--timescale` is a Slang-only option
  Jasper would reject. Restoring the RTL's own `1ns / 1ps` is inert for FPV --
  a time scale affects delays and `$time`, and this package has neither -- and
  it carries forward through the single compilation unit to the worker files
  the round appends, which have no time scale of their own.

  The `` `resetall `` also clears the file's own leading
  `` `default_nettype none ``, so `module testbench` compiles under
  `default_nettype wire` in the source. The inserted line does not change that;
  it sets a time scale and nothing else.

Nothing else was removed. In particular `C_FCS_EMITTED`'s hierarchical
reference into `insert_dut.state_reg` stays: it is load-bearing code for that
cover, and the name is recoverable from `rtl/axis_eth_fcs_insert.v` in any
case.

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
`T_FCS_ROUNDTRIP` reads `ref_count`, `rd_ptr` and the ring they index, all held
in the top level's `always @(posedge clock)` block. Under `ENTER_FRA_KEEP`
every register not matched by a keep pattern starts arbitrary; cut, `rd_ptr`
points at an arbitrary ring entry and the target is falsified at cycle 0 for a
reason that is not the design's and that nothing in the design can correct.

The pattern reported for `taskdefs.DESIGN_KEEP`, from `taskdef.json`, is

    (wr_ptr|rd_ptr|ref_count)

matched unanchored with Tcl `regexp` against instance paths as
`get_design_info -list register` returns them, which is the form
`_CHECKER_KEEP` uses. It is deliberately unanchored on the left so it matches
whether Jasper prints a top-level register as `wr_ptr` or as
`testbench.wr_ptr`. Checked against the elaborated design: of the 81 registers
in this package, exactly 3 match, all three at the top level. None of
`lfsr`, `axis_eth_fcs_insert` or `axis_eth_fcs_check` contains the substring
`wr_ptr`, `rd_ptr` or `ref_` anywhere -- checked by reading them -- so the
pattern cannot reach design state.

### The ring's storage IS reset here, and is still left cut

This package differs from `openpiton_pmesh_order` and from the other
verilog-axis ports in one respect worth stating, because the reasoning would
otherwise look copied rather than derived. `ref_data` and `ref_last` are NOT
unreset here: the reset branch runs `for (i = 0; i < 64; i = i + 1)` and zeroes
both. So keeping them would not be a no-op the way it is for pmesh's `ref_mem`.
They are still left cut, on the argument rather than the construction:

`T_FCS_ROUNDTRIP` reads `ref_data[rd_ptr]` only under `ref_count != 0`, and
`ref_count` only becomes non-zero through a push, which is the same event that
writes `ref_data` at `wr_ptr`. With the three pointers anchored at their reset
values, an entry is never read before it has been written, so the arbitrary
initial ring contents are unobservable. Keeping them would add 64 x 9 = 576
bits to the `KEEP_PATTERN design` count in the round log -- a number that is
read as a measurement and that should stay comparable with the other four
packages in this group.

So the kept state is exactly

    wr_ptr      6 bits
    rd_ptr      6 bits
    ref_count   7 bits    = 19 bits

and the instrument is anchored at its POINTERS, not at its memory. Anyone
reading an FCS result later needs that distinction: "a read entry was written"
is a property that has to hold, not something the keep set establishes.

Left cut deliberately:

- `past_valid`, `prev_data`, `prev_valid`, `prev_ready`, `prev_last`,
  `prev_user` -- they exist only to feed `A_INPUT_STICKY`. Arbitrary either way
  they change the assumption set, and an assumption cannot falsify a target.
  (This package registers its own history instead of using `$past`, which is
  why there are five of them.)
- `frame_len` -- it gates `A_FRAME_AT_MOST_16_BYTES`, again an assumption. An
  arbitrary start moves where the first frame is forced to end; it cannot
  falsify anything.
- `completed_frames`, `saw_ref_wrap` -- read by covers only, never by the
  target.

All three kept families are reset-assigned, so the pattern cannot match zero
and cannot trip `cex.tcl`'s "design keep pattern matched nothing" FAIL.

## Not verified

The Slang gate passes:

    uv run python v6_dataset/elab_local.py --task verilog_ethernet_fcs_roundtrip
    OK: verilog_ethernet_fcs_roundtrip elaborates

and `hierarchy.build_ir` builds the design map from it -- 5 instances, 81
registers, the fifteen top-level registers among them. What has NOT been run is
Jasper: no `analyze`/`elaborate` under `lists/tc_elab.tcl`, no register census,
no `KEEP_PATTERN design` hit count, no proof. Slang and Jasper disagree about
some SystemVerilog and only Jasper's verdict admits a file to a round.

Also checked locally, because the `placement` string promises it: a standalone
module carrying one `assert property` and one `cover property`, bound in with
`bind testbench ...`, elaborates against this package (`elab_local.py --extra`).
That is the shape v5 stages one of per worker.

## Known caveat: the target is an immediate assertion, so `derive_targets` cannot locate it

`taskdefs.derive_targets` looks for a line that starts with `<label>:` and
contains the literal `assert property`. This package's target does not have
that shape -- it is an immediate assertion inside the checker's clocked always
block, `T_FCS_ROUNDTRIP: assert (` followed by the condition on later lines --
so `derive_targets` returns `source: ""`, `line: 0` and the model phase renders

    - `T_FCS_ROUNDTRIP` — not located in the mounted sources

instead of a file and line. Nothing else is affected: `v5/round.py` reads
`TASKS[task]["target_labels"]` and `cex.tcl:LABEL_INDEX` keys on the last
dot-separated component, so `T_FCS_ROUNDTRIP` resolves in a round, and the diag
census finds it by name. The cost is that a model-phase agent is told the
target's name but not where to read it.

This is not fixable inside the package without rewriting the source's target
into a concurrent assertion, which would change what the task measures. The fix
is in `taskdefs.TARGET_PATTERN`, which this port was told not to touch. It
applies identically to the other four packages in this group.

## Phase-1 candidate targets, added 2026-08-19

    sva/targets_verilog_ethernet_fcs_roundtrip.sv  34 `T_*` assertions, 20 `C_*` covers
    lists/targets.txt                              34 rows, `label TAB category TAB intent`

Appended LAST to `lists/tc_elab.files` and `taskdef.json`'s `mount` gained
`sva`. The gate passes without `--extra`:

    uv run python v6_dataset/elab_local.py --task verilog_ethernet_fcs_roundtrip
    OK: verilog_ethernet_fcs_roundtrip elaborates

The oracle is independent of `ft/tb.sv`'s single end-to-end byte ring: it cuts
at the framed middle, keeps a payload queue on each side of it, frames the
middle with its own payload/FCS state rather than the design's, and computes
its OWN reflected CRC-32 (`crc32_next`, poly 0xEDB88320, seeded all-ones) over
the payload bytes it saw at the source port. `taskdefs.oracle_keep` derives
`eth_fcs_targets\.` from the bind.

Ten of the fifteen categories are admitted. NOT admitted, and why: **5 mutual
exclusion**, **7 allocator discipline**, **8 request-response correspondence**
and **10 arbitration fairness** -- one flow, one frame at a time, no allocator
and no request/response pair; **15 coherence** (no agents).

### The reference CRC was checked against the design's `lfsr`, offline

`rtl/lfsr.v`'s mask construction for `LFSR_CONFIG="GALOIS"`, `REVERSE=1`,
`LFSR_POLY=32'h4c11db7`, `DATA_WIDTH=8` was re-implemented in Python and run
against `crc32_next` for 200 random payloads of 1..16 bytes: the states agree
exactly, and `~state` low-byte-first equals `zlib.crc32` little-endian. So
`T_DATA_MID_FCS_BYTE_IS_REFERENCE_CRC` rests on the FRAMING being right, not on
the CRC convention.

### Not verified, and what is uncertain

Jasper has NOT been run. The judgement calls:

- `T_BOUND_QA_OCC_LE_THREE` and `T_BOUND_QB_OCC_LE_EIGHT` are read out of the
  skid depths (2) and the checker's four-byte delay line plus its skid.
- `T_BOUNDRSP_COMPLETED_FRAME_DRAINS_WITHIN_N` is guarded on a frame having
  FULLY crossed the middle. Unguarded it is false: the checker only shifts its
  delay line when a new byte arrives, so a payload byte waits indefinitely if
  the source stops.
- `T_ORDER_MID_LAST_ONLY_ON_FOURTH_FCS_BYTE` and
  `T_DATA_MID_NEVER_MARKED_BAD` depend on the package's existing
  `A_INPUT_GOOD`, which keeps the inserter off its `tuser` early-terminate
  path. No assumption was added.
