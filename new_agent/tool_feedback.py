"""Compact checker facts with FVRuleLearner's released error-line extraction.

The extraction block follows src/hardware_general_agent.py in
NVlabs/FVRuleLearner. Only candidate compilation logs enter model feedback.
"""
import json
import re

POLICY_VERSION = 'compact_status_original_jasper_errors_v1'
PEC_VERDICTS = frozenset({'FULL_EQUIVALENCE', 'IMPLIES', 'NO_EQUIVALENCE'})


def extract_jasper_errors(jasper_out_str, dataset='nl2sva_human'):
    """Reuse the released Human/Machine and OpenCore extraction blocks."""
    if dataset in {'nl2sva_human', 'nl2sva_machine'}:
        error_lines = [line for line in re.findall(r'ERROR.*', jasper_out_str) if 'dummy' not in line]
    elif dataset == 'nl2sva_opencore':
        summary_index = jasper_out_str.find('Summary of errors detected:')
        if summary_index != -1:
            errors_section = jasper_out_str[summary_index:]
            error_lines = [line for line in re.findall(r'\[ERROR.*', errors_section) if 'PEC' not in line]
        else:
            error_lines = []
    else:
        error_lines = []
    # Keep the original extraction, but bound the amount forwarded to a model.
    return '\n'.join(error_lines[:6])[:1500]


def compact_tool_feedback(value, dataset='nl2sva_human'):
    """Whitelist two statuses and, only on compilation failure, error text."""
    if isinstance(value, str):
        value = {'status': value}
    value = value if isinstance(value, dict) else {}
    if 'candidate_syntax' in value:
        syntax = value.get('candidate_syntax')
        syntax = syntax if syntax in {'PASS', 'FAIL', 'UNKNOWN'} else 'UNKNOWN'
        pec = value.get('pec_status')
        result = {'candidate_syntax': syntax,
                  'pec_status': pec if pec in PEC_VERDICTS else 'UNAVAILABLE'}
        errors = value.get('jasper_errors')
        if syntax == 'FAIL' and isinstance(errors, str) and errors.strip():
            result['jasper_errors'] = '\n'.join(errors.splitlines()[:6])[:1500]
        return result

    status = value.get('status')
    syn_result = value.get('candidate_syn') or {}
    syntax_score = syn_result.get('syntax')
    if syntax_score is None:
        if status == 'SYNTAX_ERROR':
            syntax_score = 0.0
        elif status != 'PEC_COMPILE_ERROR':
            syntax_score = value.get('syntax')
    syntax = ('PASS' if syntax_score == 1.0 else
              'FAIL' if syntax_score == 0.0 or status == 'SYNTAX_ERROR' else 'UNKNOWN')
    result = {'candidate_syntax': syntax,
              'pec_status': status if status in PEC_VERDICTS else 'UNAVAILABLE'}
    if syntax == 'FAIL':
        # SYN-only fallback logs never contain the subsequent reference PEC run.
        log = syn_result.get('tool_output')
        if not isinstance(log, str) or not log:
            log = value.get('tool_output', '') if status == 'SYNTAX_ERROR' else ''
        if isinstance(log, str):
            errors = extract_jasper_errors(log, dataset)
            if errors:
                result['jasper_errors'] = errors
    return result


def feedback_for_round(evidence, round_number):
    """Use the verdict belonging to the supplied previous assertion's round."""
    if round_number is None:
        return None
    entry = next((row for row in reversed(evidence) if row.get('round') == round_number), None)
    evaluation = (entry or {}).get('evaluation')
    if not isinstance(evaluation, dict):
        return None
    return compact_tool_feedback(evaluation.get('tool_feedback') or evaluation)


def feedback_text(value):
    return json.dumps(compact_tool_feedback(value), ensure_ascii=False, indent=2)
