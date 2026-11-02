# PEC interface probe and BLEU continuation update (v7)

This package keeps FVRuleLearner's original embedded checker and native Tcl files
unchanged. It adds isolated server probes for declaration-entry compatibility and
allows the experiment to complete by BLEU when PEC cannot compile a case.
It includes the earlier high-level diagnosis and active inference revision prompts.

## Install

Extract the complete archive. Run its installer from the extracted package folder:

```bash
python apply_signal_list_update.py /home/fwu44/research/SVA_FVRuleLearner
```

This installs full replacement files, removes the superseded typed_pec.py adapter,
and preserves experiment settings except for selecting expanded_names mode.
Previous files are backed up. Use the installer from this freshly extracted
package, together with its manifest and new_agent directory.

From the repository root in the existing fvrule Conda environment:

```bash
python -m pip install -r requirements_new_agent.txt
python new_agent/probe_pec_interface.py --timeout 60
```

Pyslang remains 11.0.0 for Python 3.10, or 12.1.0 for Python >=3.11.

## What the server probe actually establishes

The checked-in documentation describes a signal-name list; it does not document
an explicit typed signature. The probe first prints the arguments exposed by
`info args prop_eq_checker`, when introspection is available. It does not inspect
or decrypt the protected procedure body.

It then tries two EXPERIMENTAL declaration-entry formats via the same signal-list
argument. These are compatibility trials, not claims of vendor-documented support:

- Range fragments: `[3:0] data`, `signed [3:0] s`, `[1:0] items [0:0]`.
- Full declarations: `logic [3:0] data`, `logic signed [3:0] s`,
  `logic [1:0] items [0:0]`.

Every trial uses a separate temporary probe Tcl entry point and isolated Jasper
project. The entry point includes the original pec.tcle and invokes its original
prop_eq_checker. It never renames analyze, changes the installed native Tcl, or
opens/rewrites generated pec.sve files.

The probe runs a scalar self-check and negative baseline, then tests:

1. A dynamically indexed packed-vector self-check.
2. A negative vector-width control that scalarization would wrongly make equal.
3. An unpacked array of packed vectors, compared with itself.
4. An array-element negative control.
5. Signed-vector behavior.
6. Ascending packed-range orientation.
7. An indexed one-bit packed-vector self-check, including arbitrary index values.

Each declaration format stops at its first failed control. A profile is recorded
as verified only if every control passes. A failed scalar baseline makes the
probe inconclusive, rather than proving that a typed interface does not exist.

Output is stored in new_agent/runs/PEC_interface_probe_*/probe_result.json with
per-control logs. A capability record is also written to
new_agent/pec_interface_probe.json. It contains the native checker SHA-256.

## Corresponding production behavior

- If no declaration profile is verified, production retains the existing name-only
  native interface. Probe failure does not block training or inference.
- If all controls verify a profile and the checker hash still matches, signal-list
  entries use that profile to supply fixed dimensions and signedness from the TB.
- Unsupported declarations in a real case fall back to names-only and record the
  reason. For example, the range-fragment form cannot express a different two-state
  base type. This is not a promise of support for arbitrary SV types/properties.
- The verified report is specific to the checker tested on your server. Rerun the
  probe after changing the checker or Jasper installation. To disable this route,
  remove new_agent/pec_interface_probe.json or set PEC_TYPED_INTERFACE_REPORT=None
  in config.py.
- Name expansion and evaluated integral parameter bindings from v6 remain active.
  No declarations, state updates or assumptions are copied into a checker file.

Metadata records native_signal_list_v7_interface_probe, the actual typed profile
(or null), and the effective signal-list entries. The repeat-comparison cache
includes the active profile, so it cannot reuse a names-only verdict after a
profile change.

After a profile passes, optionally retest the seven previously blocked references:

```bash
python new_agent/check_pec_context.py --dataset nl2sva_human --case-ids 13 15 34 37 47 51 61
```

The probe's small controls do not establish universal checker correctness. If it
fails or those cases remain unsupported, leave the original native behavior and
continue the experiment using the requested acceptance policy.

## BLEU acceptance and continuation

A case is accepted when the native PEC reports a pass OR native BLEU equals 1.0.
The BLEU branch no longer requires an available PEC verdict.

Example result for a BLEU-accepted case with unavailable PEC:

```json
{
  "status": "PEC_COMPILE_ERROR",
  "pec": null,
  "relax_pec": null,
  "bleu": 1.0,
  "accepted": true,
  "acceptance_reason": "bleu_match",
  "native_pec_passed": false
}
```

Formal status and native scores are not replaced with a fabricated equivalence
pass. A native NO_EQUIVALENCE with BLEU=1 may likewise be accepted overall while
its PEC score remains 0. Native BLEU is used as reported; BLEU=1 is not relabelled
as proof of exact source equality or functional equivalence.

When PEC compilation fails and BLEU is below 1, the case now continues through the
configured round budget rather than blocking at round 1. The existing training
rule generator or inference selector can assess the requirement/source with the
coarse NO_VERDICT statement. Compile failure itself is not evidence of a semantic
defect and is not an instruction to rewrite an assertion merely to appease PEC.
Training still has its reference; inference still never sends the target reference
to any model. Repeated unaccepted candidates receive the existing reassessment
procedure, without falsely claiming that a comparison completed.

The no-LLM reference self-check remains stricter: it requires actual native
FULL_EQUIVALENCE and functionality=1. It cannot pass solely on identical-reference
BLEU=1. Production experiments can start regardless of the probe outcome:

```bash
python -m new_agent.main
```

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

40 local tests pass on Python 3.12 with pyslang 11.0.0 and 12.1.0. Tests mock
native execution and LLM calls. They cover successful and failed capability
profiles, checker-hash matching, typed entry formatting and fallback, unchanged
opaque native files, BLEU-only acceptance, continued revisions in both phases,
no target-reference leakage, installer cleanup and the retained parser/category
regressions. Real Jasper execution and the actual availability of declaration
support must be established by the server probe; no such result is claimed here.
