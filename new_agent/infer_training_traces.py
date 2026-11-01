"""Load compact, allowlisted training revision evidence after case retrieval."""
import json
from pathlib import Path
from new_agent.correction_locations import recover_location
from new_agent.diagnosis_context import linked_diagnoses, review_view


EVALUATION_FIELDS = ('status', 'syntax', 'pec', 'relax_pec', 'bleu', 'rouge',
                     'exact_match', 'accepted', 'acceptance_reason')


def compact_rounds(rounds):
    """Keep recorded feedback links; never infer that adjacency proves rule use."""
    result = []
    seen = set()
    for entry in rounds:
        if not isinstance(entry, dict):
            continue
        number = entry.get('round')
        if type(number) is not int or number < 1 or number in seen:
            continue
        seen.add(number)
        assertion = entry.get('assertion', entry.get('generated_assertion'))
        if not isinstance(assertion, str) or not assertion.strip():
            assertion = None
        evaluation = entry.get('evaluation')
        evaluation = ({key: evaluation[key] for key in EVALUATION_FIELDS
                       if key in evaluation and isinstance(evaluation[key],
                           (str, int, float, bool, type(None)))}
                      if isinstance(evaluation, dict) else {})
        diagnosis = entry.get('diagnosis', entry.get('tree_rule_diagnosis', entry))
        corrections = []
        if isinstance(diagnosis, dict) and isinstance(diagnosis.get('corrections'), list):
            for correction in diagnosis['corrections']:
                if not isinstance(correction, dict):
                    continue
                rule = correction.get('rule')
                if isinstance(rule, str) and rule.strip():
                    compact = {key: correction[key].strip()
                        for key in ('difference', 'why_it_matters', 'rule', 'location')
                        if isinstance(correction.get(key), str) and correction[key].strip()}
                    if 'location' not in compact:
                        tree = entry.get('generated_tree')
                        if tree is None and isinstance(entry.get('assertion_trees'), dict):
                            tree = entry['assertion_trees'].get('generated')
                        location = recover_location(assertion, correction.get('generated_node_id'), tree)
                        if location:
                            compact['location'] = location
                    compact['diagnoses'] = linked_diagnoses(correction, diagnosis)
                    corrections.append(compact)
        else:
            # Older runs store generated rules directly in round_evidence.
            generated = entry.get('rules_generated', {})
            if isinstance(generated, dict):
                for rule in generated.values():
                    text = rule.get('rule') if isinstance(rule, dict) else rule
                    if isinstance(text, str) and text.strip():
                        compact = {'rule': text.strip()}
                        if isinstance(rule, dict) and isinstance(rule.get('location'), str):
                            compact['location'] = rule['location'].strip()
                        compact['diagnoses'] = linked_diagnoses(rule) if isinstance(rule, dict) else []
                        corrections.append(compact)
        feedback_round = entry.get('diagnosis_from_round')
        if type(feedback_round) is not int:
            used = entry.get('rules_used', [])
            used = used if isinstance(used, list) else []
            origins = {rule.get('updated_round') for rule in used
                       if isinstance(rule, dict) and type(rule.get('updated_round')) is int}
            feedback_round = next(iter(origins)) if len(origins) == 1 else None
        if type(feedback_round) is not int or not 0 < feedback_round < number:
            feedback_round = None
        result.append({'round': number, 'assertion': assertion,
                       'diagnosis_from_round': feedback_round,
                       'corrections': corrections, 'evaluation': evaluation,
                       'behavior_review': review_view(diagnosis.get('behavior_review')) if isinstance(diagnosis, dict) else {}})
    return sorted(result, key=lambda item: item['round'])


def load_case_trace(directory, case_number, source):
    """Read only this selected TRAINING case; missing old evidence is explicit."""
    root = Path(directory).resolve()
    relative = source.get('trace_file')
    path = root / relative if isinstance(relative, str) and relative else (
        root / 'rules' / f'case_{case_number:04d}.json')
    path = path.resolve()
    if not path.is_relative_to(root):
        return [], 'unavailable_invalid_trace_path'
    if path.is_file():
        try:
            document = json.loads(path.read_text(encoding='utf-8-sig'))
            if not isinstance(document, dict):
                raise ValueError('Expected a training trace object')
            identity = document.get('case', {})
            if not isinstance(identity, dict) or identity.get('case_number') != case_number:
                return [], 'unavailable_case_mismatch'
            rounds = document.get('rounds')
            if not isinstance(rounds, list):
                raise ValueError('Expected a rounds list')
            compact = compact_rounds(rounds)
            return compact, 'available' if compact else 'unavailable_empty_trace'
        except (OSError, ValueError, TypeError):
            return [], 'unavailable_invalid_trace'
    legacy = source.get('round_evidence', [])
    compact = compact_rounds(legacy) if isinstance(legacy, list) else []
    return compact, 'available_legacy' if compact else 'unavailable_missing_trace'

