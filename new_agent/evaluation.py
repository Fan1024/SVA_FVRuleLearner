#!/usr/bin/env python3
"""Offline run summaries. Standard library only; never calls a model or Jasper.

python new_agent/evaluation.py /path/to/run [--budgets 1 5] [--training-run PATH]
Or edit RUN_DIRECTORY below and run without arguments.
"""
import argparse
import csv
import hashlib
import importlib
import json
import math
import re
import sys
from pathlib import Path

RUN_DIRECTORY = ""
BUDGETS = [1, 5]
SEED = 100
TRAIN_FRACTION = 0.8
TRAINING_RUN = None


def read_json(path):
    with Path(path).open(encoding="utf-8-sig") as f:
        return json.load(f)


def read_csv(path):
    if not path.is_file():
        return []
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path, rows, fields=None):
    fields = fields or list(dict.fromkeys(k for row in rows for k in row))
    with path.open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def number(value):
    if value is None or value == '' or value == 'unavailable':
        return None
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f'Non-finite value: {value}')
    return int(result) if result.is_integer() else result


def total(values):
    values = list(values)
    return None if any(v is None for v in values) else sum(values)


def safe_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f'Path escapes run: {relative}')
    return path


def module(name):
    return importlib.import_module(f'{__package__}.{name}' if __package__ else name)


def table(rows, columns=None):
    if not rows:
        return '_No records._\n'
    columns = columns or list(rows[0])
    def cell(v):
        if v is None:
            return '—'
        if isinstance(v, float):
            return f'{v:,.4f}'
        return str(v).replace('|', '\\|').replace('\n', ' ')
    return '\n'.join(['| ' + ' | '.join(columns) + ' |',
                      '| ' + ' | '.join('---' for _ in columns) + ' |'] +
                     ['| ' + ' | '.join(cell(r.get(k)) for k in columns) + ' |' for r in rows]) + '\n'


def trace_rounds(text):
    """Only explicit ROUND headers and reassessment markers define requests."""
    result = {}
    matches = list(re.finditer(r'^ROUND (\d+)\s*\n=+', text, re.M))
    for i, match in enumerate(matches):
        r = int(match.group(1))
        if r in result:
            raise ValueError(f'Duplicate round {r} in debug trace; ambiguous appended history.')
        block = text[match.end():matches[i+1].start() if i+1 < len(matches) else len(text)]
        retry = len(re.findall(r'^REVISION REASSESSMENT\s*$', block, re.M))
        responses = re.findall(r'```systemverilog\s*\n(.*?)```', block, re.S)
        formal = re.search(r'^FORMAL RESULT\s*\nStatus: ([^\n]+)', block, re.M)
        scores = {}
        if formal:
            formal_text = block[formal.start():]
            for label, key in [('Syntax', 'syntax'), ('Strict PEC', 'pec'),
                               ('Relaxed PEC', 'relax_pec'), ('BLEU', 'bleu')]:
                found = re.search(r'^' + label + r': ([^\n]+)', formal_text, re.M)
                if found:
                    scores[key] = number(found.group(1).strip())
        result[r] = dict(round=r, reassessments=retry, responses=responses,
                         repeated_rounds=[int(v) for v in re.findall(r'\d+', (re.search(r'^Repeated a known non-equivalent attempt from rounds ([^\n]+)', block, re.M) or ['',''])[1])],
                         formal_status=formal.group(1).strip() if formal else None,
                         scores=scores)
    return result


def load_evidence(run, saved, row, phase, warnings, flat_text):
    n = int(saved['case_number'])
    relative = saved.get('directory')
    directory = safe_path(run, relative or f'cases/case_{n:04d}')
    result_path = directory / 'result.json'
    record = read_json(result_path) if result_path.is_file() else {}
    if record:
        inputs = record.get('inputs', {})
        if (int(inputs.get('case_number', -1)) != n or
                inputs.get('design_name') != saved['design_name'] or
                str(record.get('case_id', inputs.get('task_id'))) != str(saved['task_id'])):
            raise ValueError(f'Case {n}: result.json identity mismatch')
    traces = directory / 'debug_trace.txt'
    text = traces.read_text(encoding='utf-8-sig') if traces.is_file() else flat_text.get(n, '')
    rounds = trace_rounds(text)
    traced_round_ids = sorted(rounds)
    metrics = {}
    for metric in record.get('round_metrics', []):
        r = int(metric['round'])
        if r in metrics:
            raise ValueError(f'Case {n}: duplicate round_metrics round {r}')
        metrics[r] = metric
    last = int(row.get('last_evaluated_round') or 0) if row else 0
    used = int(row.get('rounds_used') or last) if row else int(record.get('rounds_used') or 0)
    for r, metric in metrics.items():
        tr = rounds.setdefault(r, dict(round=r, reassessments=None, responses=[], scores={}))
        for key in ('syntax', 'pec', 'relax_pec', 'bleu'):
            value = number(metric.get(key))
            if key in tr['scores'] and tr['scores'][key] != value:
                raise ValueError(f'Case {n}, round {r}: trace and result scores disagree')
            tr['scores'][key] = value
        tr['formal_status'] = metric.get('status')
    if row and last:
        tr = rounds.setdefault(last, dict(round=last, reassessments=None, responses=[], scores={}))
        for key in ('syntax', 'pec', 'relax_pec', 'bleu'):
            value = number(row.get(key))
            if key in tr['scores'] and tr['scores'][key] != value:
                raise ValueError(f'Case {n}: evaluation.csv and round evidence disagree for {key}')
            tr['scores'][key] = value
        tr['formal_status'] = row.get('formal_status')
    complete_trace = bool(text and re.search(r'^FINAL RESULT\s*$', text, re.M))
    exact = phase == 'inference_only' or used == 1 or (complete_trace and traced_round_ids == list(range(1, used+1)))
    if phase != 'inference_only' and not exact:
        warnings.append(f'Case {n}: full debug trace unavailable; reassessment count/attempt mapping may be incomplete.')
    attempt_index = 0
    prefix_exact = True
    attempts = []
    reassessments = 0
    for r in range(1, used+1):
        tr = rounds.get(r, {})
        retries = tr.get('reassessments')
        if phase == 'inference_only' or r == 1:
            retries = 0 if retries is None else retries
        if retries is not None:
            reassessments += retries
        else:
            prefix_exact = False
        for offset in range(1 + (retries or 0)):
            attempt_index += 1
            retained = offset == (retries or 0)
            scores = tr.get('scores', {}) if retained else dict(rounds.get(next(iter(tr.get('repeated_rounds', [])), -1), {}).get('scores', {}))
            if not retained:
                scores['pec'] = 0
            attempts.append(dict(case_number=n, design_name=saved['design_name'], task_id=saved['task_id'],
                original_round=r, attempt=attempt_index if prefix_exact else None,
                generation_type='reassessment' if offset else 'normal',
                evaluation_source='round_result' if retained else 'prior_matching_semantic_failure',
                syntax=scores.get('syntax'), pec=scores.get('pec'), relax_pec=scores.get('relax_pec'),
                bleu=scores.get('bleu'), formal_status=tr.get('formal_status') if retained else 'KNOWN_SEMANTIC_FAILURE',
                exact_attempt_mapping=prefix_exact))
    return dict(record=record, rounds=rounds, attempts=attempts,
                original_rounds=used, attempts_exact=exact,
                generator_requests=attempt_index if exact else None,
                observed_reassessments=reassessments,
                reassessments=reassessments if exact else None,
                trace_available=bool(text))


def build(run, phase, args):
    meta = read_json(run / 'run_metadata.json')
    selected = meta.get('selected_cases', [])
    if not selected:
        raise ValueError('run_metadata.json has no selected_cases')
    universe = {}
    for saved in selected:
        n = int(saved['case_number'])
        if n in universe:
            raise ValueError(f'Duplicate selected case {n}')
        universe[n] = saved
    rows = {}
    for row in read_csv(run / 'evaluation.csv'):
        n = int(row['case_number'])
        if n in rows or n not in universe or any(row[k] != str(universe[n][k]) for k in ('design_name', 'task_id')):
            raise ValueError(f'Duplicate or mismatched evaluation case {n}')
        rows[n] = row
    warnings = []
    flat = {}
    flat_path = run / 'debug_trace.txt'
    if flat_path.is_file():
        text = flat_path.read_text(encoding='utf-8-sig')
        chunks = list(re.finditer(r'^CASE (\d+):[^\n]*\n', text, re.M))
        for i, match in enumerate(chunks):
            n = int(match.group(1))
            if n in flat:
                raise ValueError(f'Duplicate CASE {n} in shared trace')
            flat[n] = text[match.end():chunks[i+1].start() if i+1 < len(chunks) else len(text)]
    evidence = {n: load_evidence(run, saved, rows.get(n), phase, warnings, flat) for n, saved in universe.items()}
    out = run / 'evaluation'
    out.mkdir(exist_ok=True)
    attempts = [a for ev in evidence.values() for a in ev['attempts']]
    write_csv(out / 'attempts.csv', attempts, list(attempts[0]) if attempts else ['case_number','attempt'])
    case_rows = []
    for n, saved in universe.items():
        row, ev = rows.get(n, {}), evidence[n]
        earlier_relaxed = any(r.get('scores', {}).get('relax_pec') == 1 for r in ev['rounds'].values())
        final_strict = number(row.get('pec'))
        final_relaxed = number(row.get('relax_pec'))
        first = next((a for a in ev['attempts'] if a['pec'] == 1), None)
        first_score = ev['rounds'].get(1, {}).get('scores', {}).get('pec')
        passed = final_strict == 1
        outcome = ('missing_result' if not row else 'passed_initially' if passed and first_score == 1
                   else 'passed_later' if passed else 'not_passed')
        case_rows.append(dict(case_number=n, design_name=saved['design_name'], task_id=saved['task_id'],
            outcome=outcome, original_rounds=ev['original_rounds'], generator_requests=ev['generator_requests'],
            reassessments=ev['reassessments'], observed_reassessments=ev['observed_reassessments'],
            triggered_reassessment=(ev['observed_reassessments'] > 0) if ev['attempts_exact'] or ev['observed_reassessments'] else None,
            attempt_mapping_exact=ev['attempts_exact'], first_strict_pass_round=first['original_round'] if first else None,
            first_strict_pass_attempt=first['attempt'] if first else None, syntax=number(row.get('syntax')),
            bleu=number(row.get('bleu')), pec=final_strict, relax_pec=final_relaxed,
            relaxed_success=(earlier_relaxed or final_relaxed == 1) if phase == 'inference_only' else final_relaxed == 1,
            formal_status=row.get('formal_status'), pipeline_status=row.get('pipeline_status'), stop_reason=row.get('stop_reason')))
    write_csv(out / 'case_outcomes.csv', case_rows)
    reassess = [dict(case_number=r['case_number'], task_id=r['task_id'],
                     reassessments=r['reassessments'], observed_reassessments=r['observed_reassessments'],
                     triggered_reassessment=r['triggered_reassessment'],
                     original_rounds=r['original_rounds'], generator_requests=r['generator_requests'],
                     attempt_mapping_exact=r['attempt_mapping_exact']) for r in case_rows]
    write_csv(out / 'reassessment_cases.csv', reassess)
    ncases = len(universe)
    quality = [dict(model=json.dumps(meta.get('models', {}), sort_keys=True), cases=ncases,
        mean_bleu=(sum(r['bleu'] for r in case_rows if r['bleu'] is not None) /
                   sum(r['bleu'] is not None for r in case_rows)) if any(r['bleu'] is not None for r in case_rows) else None,
        bleu_available_cases=sum(r['bleu'] is not None for r in case_rows),
        syntax_passed=sum(r['syntax'] == 1 for r in case_rows),
        strict_passed=sum(r['pec'] == 1 for r in case_rows),
        relaxed_passed=sum(r['relaxed_success'] for r in case_rows),
        strict_percent=100*sum(r['pec'] == 1 for r in case_rows)/ncases,
        relaxed_percent=100*sum(r['relaxed_success'] for r in case_rows)/ncases,
        strict_unavailable=sum(r['pec'] is None for r in case_rows),
        relaxed_unavailable=sum(r['relax_pec'] is None for r in case_rows),
        score_policy='pipeline_reported',
        relaxed_selection='any_recorded_attempt' if phase == 'inference_only' else 'last_round')]
    write_csv(out / 'quality.csv', quality)
    # Aggregate costs using case_total rows only; keep original-round detail separately.
    usage = read_csv(run / 'token_time.csv')
    current = None
    case_costs, round_costs = [], []
    seen_costs = set()
    for u in usage:
        if u.get('case_id'):
            match = re.match(r'^(\d+): ', u['case_id'])
            if match:
                current = int(match.group(1))
            else:
                candidates = [n for n, c in universe.items() if u['case_id'] in
                              {str(c['task_id']), f"{c['design_name']}/{c['task_id']}"}]
                if len(candidates) != 1:
                    raise ValueError(f'Ambiguous token_time case label: {u["case_id"]}')
                current = candidates[0]
        if current not in universe:
            raise ValueError('token_time.csv has missing/unknown case identity')
        cost = {'case_number': current, 'round': u['round']}
        cost.update({k:number(v) for k,v in u.items() if k not in ('case_id','round','passed')})
        if u['round'] == 'case_total':
            if current in seen_costs:
                raise ValueError(f'Duplicate case_total usage for case {current}')
            seen_costs.add(current)
            case_costs.append(cost)
        else:
            cost['observed_reassessments'] = evidence[current]['rounds'].get(int(u['round']), {}).get('reassessments')
            round_costs.append(cost)
    write_csv(out / 'case_costs.csv', case_costs, None if case_costs else ['case_number'])
    write_csv(out / 'round_costs.csv', round_costs, None if round_costs else ['case_number','round'])
    costs_complete = len(case_costs) == len(rows) and bool(case_costs)
    def sum_cost(field):
        return total(c.get(field) for c in case_costs) if case_costs else None
    components = []
    labels = [('assertion','Assertion generation'),('rule', 'Diagnosis/rule generation' if phase == 'train' else 'Rule selection'),
              ('diagnosis','Tree processing / legacy diagnosis')]
    for stage, label in labels:
        components.append(dict(component=label,
            input_tokens=sum_cost(stage+'_input_tokens'), output_tokens=sum_cost(stage+'_output_tokens'),
            total_tokens=sum_cost(stage+'_total_tokens'), seconds=sum_cost(stage+'_seconds')))
    components.extend([dict(component='Formal evaluation', seconds=sum_cost('tool_seconds')),
                       dict(component='Other recorded case time', seconds=sum_cost('other_seconds'))])
    all_tokens, all_seconds = sum_cost('total_tokens'), sum_cost('total_seconds')
    for c in components:
        c['token_percent'] = 100*c['total_tokens']/all_tokens if c.get('total_tokens') is not None and all_tokens else None
        c['time_percent'] = 100*c['seconds']/all_seconds if c.get('seconds') is not None and all_seconds else None
    write_csv(out / 'component_costs.csv', components)
    top = []
    for field in ('total_tokens','total_seconds','assertion_total_tokens','assertion_seconds','rule_total_tokens','rule_seconds'):
        for rank, cost in enumerate(sorted((c for c in case_costs if c.get(field) is not None), key=lambda c:c[field], reverse=True)[:args.top],1):
            top.append(dict(ranking=field, rank=rank, **cost))
    write_csv(out / 'top_cost_cases.csv', top, None if top else ['ranking','rank','case_number'])
    observed = sum(e['observed_reassessments'] for e in evidence.values())
    exact_counts = all(e['attempts_exact'] for e in evidence.values()) and len(rows) == ncases
    triggered = sum(e['observed_reassessments'] > 0 for e in evidence.values())
    summary = dict(phase=phase, selected_cases=ncases, recorded_cases=len(rows),
        passed_initially=sum(e['rounds'].get(1, {}).get('scores', {}).get('pec') == 1 for e in evidence.values()),
        final_strict_passed=quality[0]['strict_passed'], final_relaxed_passed=quality[0]['relaxed_passed'],
        pipeline_accepted=sum(r.get('passed') == 'True' for r in rows.values()),
        cases_with_reassessment=triggered, observed_reassessment_requests=observed,
        reassessment_counts_exact=exact_counts, cases_without_complete_attempt_mapping=sum(not e['attempts_exact'] for e in evidence.values()),
        original_rounds=sum(e['original_rounds'] for e in evidence.values()),
        generator_requests=total(e['generator_requests'] for e in evidence.values()) if exact_counts else None,
        input_tokens=sum_cost('input_tokens'), output_tokens=sum_cost('output_tokens'), total_tokens=all_tokens,
        average_tokens_per_usage_case=all_tokens/len(case_costs) if all_tokens is not None and case_costs else None,
        recorded_case_seconds=all_seconds, average_seconds_per_usage_case=all_seconds/len(case_costs) if all_seconds is not None and case_costs else None,
        experiment_seconds=meta.get('experiment_seconds'), usage_rows_complete=costs_complete,
        token_values='as_recorded_no_recovery', usage_recording_version=meta.get('usage_recording_version','legacy_or_unknown'))
    summary['additional_cases_passed_later'] = summary['final_strict_passed']-summary['passed_initially']
    summary['average_generator_requests_per_case'] = summary['generator_requests']/ncases if summary['generator_requests'] is not None else None
    if observed and meta.get('usage_recording_version', 0) != 2:
        warnings.append('Reassessment observed in a legacy/unknown recording version. Tokens are reported exactly as saved; no recovery attempted.')
    if not costs_complete:
        warnings.append('Usage rows are missing or incomplete. Cost totals cover available case_total rows only.')
    write_csv(out / 'summary.csv', [summary])
    if phase == 'inference_only':
        argv = [str(run), '--seed', str(args.seed), '--train-fraction', str(args.train_fraction), '--budgets', *map(str,args.budgets)]
        if args.training_run:
            argv += ['--training-run', str(args.training_run)]
        if args.assume_stop_on_strict_pass:
            argv += ['--assume-stop-on-strict-pass']
        module('evaluation_infer_only').main(argv)
        budgets = read_csv(out / 'infer_only_evaluation.csv')
    else:
        budgets = []
        for k in args.budgets:
            entry = dict(budget=k, total_cases=ncases, score_selection='last_round_at_or_before_budget', score_policy='pipeline_reported')
            for key, prefix in [('pec','strict'),('relax_pec','relaxed')]:
                low = high = unknown = 0
                for n, ev in evidence.items():
                    candidates = [a for a in ev['attempts'] if a['attempt'] is not None and a['attempt'] <= k]
                    if not candidates or (not ev['attempts_exact'] and candidates[-1]['original_round'] < ev['original_rounds'] and candidates[-1]['attempt'] < k):
                        unknown += 1; high += 1; continue
                    value = candidates[-1].get(key)
                    if value == 1:
                        low += 1; high += 1
                    elif value is None:
                        unknown += 1; high += 1
                entry.update({prefix+'_passed_lower':low, prefix+'_passed_upper':high,
                              prefix+'_percent_lower':100*low/ncases, prefix+'_percent_upper':100*high/ncases,
                              prefix+'_unknown_cases':unknown, prefix+'_exact':low == high})
            budgets.append(entry)
    write_csv(out / 'success_by_attempt.csv', budgets)
    source_paths = [run/'run_metadata.json', run/'evaluation.csv', run/'token_time.csv', flat_path]
    for saved in universe.values():
        folder = safe_path(run, saved.get('directory') or f"cases/case_{int(saved['case_number']):04d}")
        source_paths.extend([folder/'result.json',folder/'debug_trace.txt'])
    hashes = {str(p.relative_to(run)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths if p.is_file()}
    report_meta = dict(evaluator_version=1, phase=phase, original_files_modified=False,
                       source_sha256=hashes, warnings=list(dict.fromkeys(warnings)),
                       token_recovery=False, score_policy='pipeline_reported',
                       relaxed_policy='any_previous_pass' if phase == 'inference_only' else 'last_round_only')
    (out/'evaluation_metadata.json').write_text(json.dumps(report_meta,indent=2)+'\n',encoding='utf-8')
    report = '# Evaluation\n\nScores follow the saved pipeline policy. Tokens are used as recorded; no recovery is attempted.\n\n'
    report += '## Summary\n\n'+table([{'Metric':k,'Value':v} for k,v in summary.items()])
    q = quality[0]
    def rate(count):
        return f'{count}/{ncases} ({100*count/ncases:.2f}%)'
    report += '\n## Quality\n\n'+table([{
        'Model': q['model'], 'BLEU': q['mean_bleu'], 'SYN': rate(q['syntax_passed']),
        'FUNC': rate(q['strict_passed']), 'R.FUNC': rate(q['relaxed_passed'])}])
    report += '\nTrain/inference use final-round scores. Inference-only retains earlier relaxed successes. Missing scores are listed in quality.csv.\n'
    compact_budgets = []
    for b in budgets:
        if phase == 'inference_only':
            compact_budgets.append({'Scope': b['scope'], 'Budget': b['budget'],
                                    'FUNC': b['strict_pec_result'], 'R.FUNC': b['relaxed_pec_result']})
        else:
            compact = {'Budget': b['budget']}
            for prefix, label in [('strict','FUNC'),('relaxed','R.FUNC')]:
                low, high = b[prefix+'_passed_lower'], b[prefix+'_passed_upper']
                compact[label] = rate(low) if low == high else f'{low}..{high}/{ncases} (incomplete evidence)'
            compact_budgets.append(compact)
    report += '\n## Success by generator budget\n\n'+table(compact_budgets)
    report += '\n## Reassessment cases\n\n'+table([r for r in reassess if r['observed_reassessments']])
    report += '\n## Repaired and unsuccessful cases\n\n'+table([r for r in case_rows if r['outcome'] != 'passed_initially'], ['case_number','outcome','first_strict_pass_round','first_strict_pass_attempt','generator_requests','reassessments','formal_status'])
    report += '\n## Component costs\n\n'+table(components)
    report += '\n## Most expensive cases\n\n'+table(top, ['ranking','rank','case_number','total_tokens','total_seconds','assertion_total_tokens','rule_total_tokens'])
    if warnings:
        report += '\n## Data notes\n\n'+'\n'.join('- '+w for w in dict.fromkeys(warnings))+'\n'
    (out/'report.md').write_text(report,encoding='utf-8')
    qualifier = 'exact' if exact_counts else 'observed minimum; missing traces exist'
    print(f'Reassessment: {triggered}/{ncases} cases; {observed} extra requests ({qualifier}).')
    print(f'Saved: {out / "report.md"}')
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_directory', nargs='?', default=RUN_DIRECTORY)
    parser.add_argument('--budgets', nargs='+', type=int, default=BUDGETS)
    parser.add_argument('--seed', type=int, default=SEED)
    parser.add_argument('--train-fraction', type=float, default=TRAIN_FRACTION)
    parser.add_argument('--training-run', type=Path, default=TRAINING_RUN)
    parser.add_argument('--top', type=int, default=10)
    parser.add_argument('--assume-stop-on-strict-pass', action='store_true')
    args = parser.parse_args(argv)
    if not args.run_directory:
        parser.error('Provide a run directory or set RUN_DIRECTORY.')
    if min(args.budgets) < 1 or args.top < 1:
        parser.error('Budgets and --top must be positive.')
    args.budgets = sorted(set(args.budgets))
    run = Path(args.run_directory).expanduser().resolve()
    meta = read_json(run/'run_metadata.json')
    phase = meta.get('phase', meta.get('settings',{}).get('phase'))
    if phase == 'train':
        module('evaluation_train').evaluate(run,args)
    elif phase == 'infer':
        module('evaluation_inference').evaluate(run,args)
    elif phase == 'inference_only':
        build(run,phase,args)
    else:
        raise ValueError(f'Unsupported phase: {phase!r}')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'ERROR: {error}',file=sys.stderr)
        raise SystemExit(2)
