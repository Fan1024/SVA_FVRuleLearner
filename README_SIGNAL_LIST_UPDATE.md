# Native PEC signal-list cleanup

This package supersedes the typed-PEC and byte-decoding packages. It keeps the
high-level diagnosis, requirement interpretation and active inference revision
prompts, while removing the PEC-file adaptation route.

Based on Fan1024/SVA_FVRuleLearner commit
`fb624d5b452a0dbeccea891e310f82ca9728e087` and the previous delivered prompt updates.
All required changed source files are included in full.

## Installation

Extract this ZIP into a separate folder. From that extracted folder, run:

```bash
python apply_signal_list_update.py /home/fwu44/research/SVA_FVRuleLearner
```

The installer copies the included files, removes obsolete adapter files, and
sets only `PEC_CONTEXT_MODE = "expanded_names"` in your existing config. Your
models, dataset paths, split, round budget and other settings are preserved.
Previous files are saved under `signal_list_backup_*` in the repository.
Do not merely copy the source files: use the installer to perform the deletions.

In your existing experiment environment, from the repository root:

```bash
python -m pip install -r requirements_new_agent.txt
python -m unittest discover -s tests -p 'test_pec_revision_update.py' -v
python -m unittest discover -s tests -p 'test_requirement_diagnosis.py' -v
python -m unittest discover -s tests -p 'test_native_signal_list.py' -v
```

Python 3.10 uses pyslang 11.0.0; Python 3.11+ uses 12.1.0. Pyslang is still needed
to collect names from the TB, locate candidate insertion for native SYN checking,
and construct assertion diagnosis trees. Missing pyslang now stops main.py at
startup before a model request.

## Exact PEC boundary

The evaluation wrapper calls the original native evaluator and launcher. It
changes only these launcher arguments:

- `lm_assertion_text` and `ref_assertion_text`: intact expressions extracted from
  the source assertion under the existing dataset-specific boundary policy, with
  bare TB integral parameter identifiers bound to their evaluated constants on
  both sides before invoking PEC. Original assertion sources remain unchanged.
- `signal_list_text`: the native quoted-name list plus declared TB signal names,
  deduplicated. Known parameters/localparams are excluded from this runtime-signal
  list; they are not converted into free inputs.

The v6 update fixes the observed case-1 `max`/`min` undeclared errors. Native Tcl
clears the TB design before standalone PEC and therefore does not inherit its
parameters. The same elaborated TB defaults used for name collection now provide
constant bindings. For Human case 1, `width=1`, `min=0`, and `max=1`; the native
arguments use `max -> 2'h1` and `min -> 32'sh0`, preserving width and signedness.
Signed negative values use explicit sized two's-complement literals. Original
candidate/reference strings, model prompts, generated assertions and similarity
metrics are not rewritten. Only the two evaluation arguments are specialized.

Bindings apply to bare parameter identifiers, not comments, strings, numeric
literals, member/scoped names or macros. Both sides use the same TB bindings.
Unknown or non-integral parameter values used in a formula are reported as an
input-preparation error rather than silently converted to a wrong value. This
checks the concrete default TB parameter configuration, not equivalence over
all parameter configurations. It does not copy TB state updates or assumptions.

Ports, nets and variables are collected by name. Ordinary helper signals and array
names are included; no packed/unpacked declaration adapter or type filter remains.
Unsupported escaped names that cannot be expressed by the existing name-list
interface are reported in `not_added`. Locals inside procedures/functions and
hierarchical scopes are not flattened into invented top-level signals.

Native `tcl_file_path` remains unchanged. There is no Tcl overlay, analyze-command
replacement, typed manifest, checker-source parser, declaration rewrite, encoding
conversion, or read of pec.sve in the evaluation adapter. Native PEC files may be
copied byte-for-byte into failure diagnostics; they are not modified.

This implements name-list customization and constant bindings in property
arguments. It does not supply signal type declarations or bus widths through
a name-only interface.
Real remaining native PEC compilation errors are reported and the case stops as
`BLOCKED_PEC_COMPILE`; compilation failure is not semantic correction evidence.
No claim is made that all previous native compilation failures are resolved.

The existing candidate SYN check remains: the complete candidate is inserted into
the plaintext TB sent to the original native Human/Machine evaluation path. That
small helper now lives in formal_check.py, rather than the removed adapter file.

## Settings and diagnostics

- Default/effective mode: `expanded_names`.
- `legacy`: pass the native original name list through exactly.
- An old `typed` config value or `FVRULE_PEC_CONTEXT_MODE=typed` environment
  override is mapped to `expanded_names`. It cannot activate the removed adapter.
- Adapter metadata: `native_signal_list_v6_constant_bindings`.
- The existing `pec_context_preparation` result key now contains only signal-list
  audit data: original/effective lists, additions and removed parameter names.
  It also records the parameter names and sized literals supplied to PEC.
- Compact results retain this audit and a bounded native PEC compilation-error
  excerpt. No obsolete typed-context success marker is required for a verdict.

The native reference self-check is retained because it exercises the real server
path without model calls. From the repository root:

```bash
python new_agent/check_pec_context.py --dataset nl2sva_human --case-ids 1
```

Or, from the `new_agent` directory:

```bash
python check_pec_context.py --dataset nl2sva_human --case-ids 1
```

It now prints applied parameter bindings and native error details on failure. Its pass condition still requires
actual FULL_EQUIVALENCE and native functionality=1; identical-reference BLEU alone
cannot pass the self-check.

## Removed files/functions

The installer deletes:

- `new_agent/typed_pec.py`: declaration rewriting, encoding fallback, typed file
  manifests, Tcl overlays and analyze interception are removed completely.
- `tests/test_pec_array_context.py` and `tests/test_pec_source_bytes.py`: tests of
  the discarded rewriting route.
- The old compilation/requirement update notes, obsolete manifests and
  `requirements_pec_compilation.txt`, superseded by this guide and dependency file.
- Cached bytecode for the removed typed_pec module.

Typed-context tests inside test_pec_revision_update.py are also removed; parser
and revision-loop regressions remain. The native self-check is simplified, and
the type collector, checker-context reader and typed-context error guards are gone.
Unrelated legacy workflows in the original repository are not deleted.

## Diagnosis behavior retained

Training assertion generation receives the requirement/TB, latest assertion and
coarse result, and latest interpretation plus category/location/rule feedback.
It outputs only a complete assertion. Training rule generation receives the
requirement/TB, current generated tree, raw reference and last transition; it
outputs a brief requirement interpretation and concrete conditional corrections.

All eleven category options remain: Scope mismatch; Missing required behavior;
Additional obligation; Unjustified exemption; Overly broad activation; Incorrect
response relationship; Timing mismatch; Incorrect context interpretation;
Polarity or quantification mismatch; Domain or boundary mismatch; Invalid
assertion structure. Diagnosis is a label; the separate interpretation and rule
provide current-case construction constraints and concrete editing guidance.

Training saves categories with rules and source locations, plus linked generated
before/after traces. At inference, requirement similarity retrieves passed source
cases. The selector sees masked source requirement/category/rule/location/example
data; it independently interprets and diagnoses the current target, then ranks
existing rules. Source interpretation maps remain in saved traces but are not
copied into the selector's source bank. Target interpretation is produced afresh.

The inference assertion generator retains its active high-level-to-specific
revision procedure and the complete category list. It diagnoses the last-round
assertion, finds specific causes, and considers retrieved rules as optional
examples. It receives the selector's latest interpretation, current located
categories, resolved ranked rule texts/reasons/source categories, and up to three
accepted-generated training example pairs. It outputs one complete assertion.
The target reference never enters the inference model prompts.

## Validation

34 local tests cover the retained parser/revision/category routes, signal-name
collection, parameter exclusion, old-setting migration, startup dependency failure,
candidate SYN packaging, and the cleanup installer. A native-launcher fixture
uses an opaque non-UTF-8 PEC file and fails the test if the adapter tries to read
or rewrite it; the original Tcl path and file bytes remain unchanged. Native
compilation failures are still surfaced rather than converted into successes.
Six parameter-binding regressions cover width/signedness, negative constants,
lexical boundaries, temporal/ternary ranges, unsupported values, the exact case-1
reference in a scalar-declaration fixture, and both native argument bindings.

The tests use mocked LLM/native execution and run on local Python 3.12 with both
pyslang 11.0.0 and 12.1.0. Actual JasperGold execution and Python 3.10 runtime
execution still require the user's server; these tests do not prove formal
correctness or native support for every property/type.
