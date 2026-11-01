"""Reference self-checks through original native PEC with a prepared signal list; no LLM calls.

Example: python new_agent/check_pec_context.py --dataset nl2sva_human --case-ids 15 37 68
"""
import argparse
import csv
import hashlib
from datetime import datetime
import json
from pathlib import Path
import shutil
import sys
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from new_agent import config, formal_check
from new_agent.pec_context_adapter import VERSION, context_mode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', choices=['nl2sva_human', 'nl2sva_machine'], default=config.DATASET)
    parser.add_argument('--case-ids', type=int, nargs='*', default=[])
    parser.add_argument('--csv', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--timeout', type=float, default=config.JASPER_TIMEOUT_SECONDS)
    args = parser.parse_args()
    dataset_path = args.csv or (formal_check.REPO_ROOT / 'FVEval' / 'data_nl2sva' / 'data' / f'{args.dataset}.csv')
    with dataset_path.open(encoding='utf-8-sig', newline='') as source:
        rows = list(csv.DictReader(source))
    selected = args.case_ids or list(range(1, len(rows) + 1))
    if any(number < 1 or number > len(rows) for number in selected):
        parser.error(f'Case IDs must be between 1 and {len(rows)}.')
    output = args.output_dir or (config.RUNS_DIR / ('PEC_selfcheck_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f')))
    output.mkdir(parents=True, exist_ok=False)
    print(f'PEC mode: {context_mode()} | adapter: {VERSION}', flush=True)
    print(f'Evaluator: {formal_check.__file__}', flush=True)
    print(f'Output: {output.resolve()}', flush=True)
    metadata = {'dataset': args.dataset, 'csv_path': str(dataset_path.resolve()),
                'csv_sha256': hashlib.sha256(dataset_path.read_bytes()).hexdigest(),
                'context_mode': context_mode(), 'adapter_version': VERSION,
                'evaluator_file': str(Path(formal_check.__file__).resolve()),
                'case_ids': selected, 'timeout_seconds': args.timeout}
    (output / 'run_metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    formal_check.initialize_evaluator(output / 'native_logs', args.dataset, args.timeout)
    summary = []
    for number in selected:
        row = rows[number - 1]
        case_dir = output / f'case_{number:04d}'
        case_dir.mkdir()
        with TemporaryDirectory(prefix='pec_selfcheck_') as temporary:
            try:
                result = formal_check.evaluate_assertion(
                    generated_assertion=row['ref_solution'], reference_assertion=row['ref_solution'],
                    testbench=row['testbench'], requirement=row['prompt'],
                    run_dir=Path(temporary), timeout_seconds=args.timeout,
                    task_id=row['design_name'] + '/' + row['task_id'], dataset=args.dataset,
                    model_name='reference_selfcheck_no_llm')
            except Exception as error:
                result = {'status': 'SELF_CHECK_ERROR', 'evaluation_error': f'{type(error).__name__}: {error}'}
            # Do not use the experiment's PEC-or-BLEU acceptance flag here.
            # Identical references have BLEU=1 even if the native checker fails.
            passed = (result['status'] == 'FULL_EQUIVALENCE' and
                      result.get('native_metrics', {}).get('functionality') == 1.0)
            native = Path(temporary)
            files = [native / name for name in ('jasper.log', 'native_pec_inputs.json', 'evaluation_error.log')]
            files += sorted((native / '_work').glob('jg/*/pec/pec*.sve'))
            for path in files:
                if path.is_file():
                    shutil.copyfile(path, case_dir / path.name)
            result['self_check_passed'] = passed
            result['saved_diagnostics_directory'] = str(case_dir.resolve())
            (case_dir / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        summary.append({'case_number': number, 'design_name': row['design_name'], 'task_id': row['task_id'],
                        'status': result['status'], 'self_check_passed': passed,
                        'signal_count': len(result.get('pec_context_preparation', {}).get('effective_signal_list', []))})
        print(f"Case {number}: {result['status']} | self_check_passed={passed}", flush=True)
        if not passed:
            detail = result.get('evaluation_error') or (result.get('tool_output') or '')[-2000:]
            if detail:
                print(detail, flush=True)
        (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    with (output / 'summary.csv').open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=list(summary[0]))
        writer.writeheader()
        writer.writerows(summary)
    print(f"Native self-check passes: {sum(row['self_check_passed'] for row in summary)}/{len(summary)}")
    return 0 if all(row['self_check_passed'] for row in summary) else 1


if __name__ == '__main__':
    raise SystemExit(main())
