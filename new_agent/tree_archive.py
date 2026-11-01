"""Inspection-only case trees; target references never enter inference prompts."""
import json
from pathlib import Path
from new_agent import assertion_tree, run_io


def build(source, prefix):
    try:
        return assertion_tree.build_tree(source, prefix)
    except assertion_tree.ParseError as error:
        return {'source_assertion': source, 'parse_error': str(error), 'context': {},
                'root': {'id': prefix + '_unparsed', 'kind': 'unparsed_assertion',
                         'value': source, 'children': [], 'parent_id': None, 'depth': 0}}


def inspection_tree(tree):
    """Keep recursive nodes and locations, omit duplicate flat summary arrays."""
    result = {key: tree[key] for key in ('source_assertion', 'root', 'context')}
    result['parser'] = tree.get('parser', 'original_source_only')
    if tree.get('parse_error'):
        result['parse_error'] = tree['parse_error']
    return result


def _write(directory, record):
    root = Path(record.get('summary_directory', directory))
    path = root / 'cases' / f"case_{record['inputs']['case_number']:04d}" / 'tree.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    run_io._atomic_write(path, json.dumps(record['_tree_archive'], ensure_ascii=False, indent=2) + '\n')
    record['tree_file'] = str(path.relative_to(root))


def record_generated(directory, record, round_number, generated):
    """Write immediately after extraction, including initial success/final round."""
    inputs = record['inputs']
    if '_tree_reference' not in record:
        record['_tree_reference'] = build(inputs['reference_assertion'], 'R')
    generated_tree = build(generated, 'G')
    archive = record.setdefault('_tree_archive', {
        'case': {key: inputs[key] for key in ('case_number', 'design_name', 'task_id')},
        'reference': inspection_tree(record['_tree_reference']),
        'rounds': [],
    })
    archive['rounds'].append({'round': round_number,
                              'generated': inspection_tree(generated_tree)})
    _write(directory, record)
    return {'reference': record['_tree_reference'], 'generated': generated_tree}


def finish_round(directory, record, round_number, evidence):
    """Attach outcomes without losing the tree on evaluator interruption."""
    archive = record.get('_tree_archive')
    if not archive:
        return
    entry = next((r for r in archive['rounds'] if r['round'] == round_number), None)
    if entry is None:
        entry = {'round': round_number, 'generated': None,
                 'note': 'No complete assertion was extracted in this round.'}
        archive['rounds'].append(entry)
    evaluation = evidence.get('evaluation')
    if isinstance(evaluation, dict):
        entry['evaluation'] = {key: evaluation.get(key) for key in
                               ('status', 'accepted', 'acceptance_reason', 'bleu')}
    _write(directory, record)

