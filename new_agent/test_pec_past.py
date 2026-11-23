#!/usr/bin/env python3
"""Small black-box PEC diagnostic. Run on the Jasper server: python test_pec_past.py

Place in the repository root or new_agent/. Uses the same native Machine PEC
backend as Block-hard, with no dataset edits, API requests, or config-file edits.
All evidence is retained under new_agent/runs/PEC_past_probe_<timestamp>/.
"""
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import sys
import traceback


# The first eight tests compare an assertion with itself.
# The final control compares different signals and should be rejected.
TESTS = [
    ('01_plain', 'a', None),
    ('02_past_signal', '$past(a)', None),
    ('03_past_negation', '$past(!a)', None),
    ('04_past_boolean', '$past(a && b)', None),
    ('05_negated_past_boolean', '!$past(a && b)', None),
    ('06_gated_past', '$past(a, 1, en)', None),
    ('07_past_arithmetic', '$past(x + y) == x', None),
    ('08_history_guard', '$past(1\'b1) |-> !$past(a && b)', None),
    ('09_negative_control', 'a', 'b'),
]

TB = '''module pec_past_probe (
    input wire clk, rst, a, b, en,
    input wire [3:0] x, y
);
endmodule
'''


def assertion(body):
    return 'asrt: assert property (@(posedge clk) disable iff (rst)\n    ' + body + '\n);'


def classify(result, negative=False):
    native = result.get('native_metrics', {})
    syntax = result.get('raw_scores', {}).get('syntax', result.get('syntax'))
    status = result.get('status')
    if syntax != 1.0:
        return 'UNRESOLVED'
    if status == 'FULL_EQUIVALENCE' and native.get('functionality') == 1.0:
        return 'UNEXPECTED_PASS' if negative else 'PASS'
    if status in {'NO_EQUIVALENCE', 'IMPLIES'} and native.get('functionality') == 0.0:
        return 'EXPECTED_REJECTION' if negative else 'SELF_CHECK_FAILED'
    return 'UNRESOLVED'


def main():
    here = Path(__file__).resolve().parent
    repo = next((p for p in (here, here.parent)
                 if (p / 'new_agent/formal_check.py').is_file()), None)
    if repo is None:
        raise ValueError('Place this script in SVA_FVRuleLearner or its new_agent directory.')
    if shutil.which('jg') is None:
        raise ValueError("Run this on the Jasper server with 'jg' available on PATH.")
    sys.path.insert(0, str(repo))
    from new_agent import config, formal_check
    from new_agent.pec_context_adapter import context_mode, verified_interface_profile

    if context_mode() != 'expanded_names':
        raise ValueError('Use PEC_CONTEXT_MODE="expanded_names" in your existing setup.')
    profile, note = verified_interface_profile()
    if not profile:
        raise ValueError('A verified typed PEC profile is needed for these vector tests: ' + note)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%fZ')
    output = repo / 'new_agent/runs' / ('PEC_past_probe_' + stamp)
    output.mkdir(parents=True, exist_ok=False)
    (output / 'testbench.sv').write_text(TB, encoding='utf-8')
    (output / 'test_definitions.json').write_text(json.dumps({
        'backend': 'nl2sva_machine', 'typed_profile': profile, 'profile_note': note,
        'tests': TESTS, 'self_check_only_except_negative_control': True,
    }, indent=2), encoding='utf-8')
    print('Evidence:', output, flush=True)
    print('No model/API calls. All self-tests use identical expressions on both sides.', flush=True)
    previous = config.PEC_CONTEXT_MODULE
    rows = []
    try:
        config.PEC_CONTEXT_MODULE = None
        for name, body, other in TESTS:
            directory = output / name
            directory.mkdir()
            generated, reference = assertion(body), assertion(other if other is not None else body)
            (directory / 'generated.sva').write_text(generated, encoding='utf-8')
            (directory / 'reference.sva').write_text(reference, encoding='utf-8')
            try:
                result = formal_check.evaluate_assertion(
                    generated_assertion=generated, reference_assertion=reference,
                    testbench=TB, requirement='Diagnostic comparison of the supplied assertions.',
                    run_dir=directory, timeout_seconds=config.JASPER_TIMEOUT_SECONDS,
                    task_id='pec_past_probe/' + name, dataset='nl2sva_machine',
                    model_name='diagnostic_no_llm',
                )
            except Exception as error:
                result = {'status': 'PROBE_ERROR', 'evaluation_error': f'{type(error).__name__}: {error}'}
                (directory / 'probe_error.log').write_text(traceback.format_exc(), encoding='utf-8')
            # Deliberately ignore accepted/pec: BLEU=1 can override those fields.
            native = result.get('native_metrics', {})
            row = dict(test=name, expression=body,
                       comparison='different_signals' if other is not None else 'self',
                       result=classify(result, negative=other is not None),
                       formal_status=result.get('status'),
                       syntax=result.get('raw_scores', {}).get('syntax', result.get('syntax')),
                       native_pec=native.get('functionality'),
                       native_relax_pec=native.get('func_relaxed'),
                       error=result.get('evaluation_error', ''))
            rows.append(row)
            (directory / 'result.json').write_text(json.dumps(result, indent=2, default=str), encoding='utf-8')
            with (output / 'summary.csv').open('w', newline='', encoding='utf-8') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(row))
                writer.writeheader()
                writer.writerows(rows)
            print(f"{name}: {row['result']} | {row['formal_status']} | native PEC={row['native_pec']}", flush=True)
            if row['error']:
                print('  ' + str(row['error']), flush=True)
    finally:
        config.PEC_CONTEXT_MODULE = previous
    print('\nSummary:', output / 'summary.csv', flush=True)
    print('Send summary.csv and jasper.log from the first SELF_CHECK_FAILED test.', flush=True)
    return 0 if all(r['result'] in {'PASS', 'EXPECTED_REJECTION'} for r in rows) else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ImportError) as error:
        print('Probe stopped: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
