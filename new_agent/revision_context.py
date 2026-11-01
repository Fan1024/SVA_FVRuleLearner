"""Small revision memory and reuse of completed comparisons within one case."""
from copy import deepcopy
import json
from pathlib import Path
import shutil

from new_agent import model_io, run_io
from new_agent.pec_input_adapter import _tokens
from new_agent.training_prompt_context import evaluation_feedback

SEMANTIC_FAILURES = {'IMPLIES', 'NO_EQUIVALENCE'}


def candidate_key(source):
    # Keep strings and escaped identifiers intact; ignore comments/spacing only.
    return tuple(token.text for token in _tokens(source))


def last_transition(evidence, assertion, status):
    if len(evidence) < 2:
        return None
    previous = evidence[-2]
    before = previous.get('generated_assertion')
    if not isinstance(before, str):
        return None
    guidance = previous.get('selector_guidance')
    if previous.get('tree_rule_diagnosis') is not None:
        from new_agent.correction_locations import feedback_json
        guidance = json.loads(feedback_json(previous['tree_rule_diagnosis'], assertion=before))
    return {'before_assertion': before, 'previous_guidance': guidance,
            'after_assertion': assertion, 'outcome': evaluation_feedback(status),
            'unchanged': candidate_key(before) == candidate_key(assertion)}


def reconsider_repeat(*, directory, record, attempt, assertion, response_text,
                      user_prompt, instructions, client, model):
    """One explicit reassessment if generation repeats a known semantic failure."""
    key = candidate_key(assertion)
    matches = [row['round'] for row in record['round_evidence'][:-1]
               if isinstance(row.get('generated_assertion'), str)
               and (row.get('evaluation') or {}).get('status') in SEMANTIC_FAILURES
               and candidate_key(row['generated_assertion']) == key]
    if not matches:
        return response_text, assertion
    retry = user_prompt + (
        '\n\nREASSESS THIS REVISION\nYour proposed response repeats an assertion whose completed '
        f'equivalence comparison failed in round(s) {matches}.\nREPEATED PROPOSAL\n{assertion}\n'
        'Reassess the complete required behavior and this proposal before choosing edits. '
        'Check whether the supplied diagnosis missed scope, activation, timing, history, '
        'polarity or a required case. Reconsider the premise of any ineffective suggestion; '
        'derive a supported corrected assertion rather than repeating the same attempt. '
        'A cosmetic rewrite is not a correction. Return only the complete assertion.')
    attempt['prompts']['repeat_retry_user'] = retry
    attempt['generation']['first_response'] = response_text
    run_io.save_debug_event(directory, record, 'revision_retry', rounds=matches)
    with run_io.measure_stage(record, 'assertion') as capture:
        revised = model_io.request_text(client, model, instructions, retry, usage_callback=capture)
    run_io.save_debug_event(directory, record, 'assertion_response', raw_response=revised)
    return revised, model_io.extract_assertion(revised)


def evaluate_once(record, round_number, **arguments):
    """Never cache compilation errors, timeouts or other missing verdicts."""
    from new_agent import formal_check
    from new_agent.pec_context_adapter import context_mode
    key = (candidate_key(arguments['generated_assertion']), context_mode(), arguments['dataset'],
           arguments['testbench'], arguments['reference_assertion'])
    cache = record.setdefault('_completed_comparison_cache', {})
    if key in cache:
        origin, result = cache[key]
        result = deepcopy(result)
        result.update(evaluation_reused_from_round=origin,
                      native_timing={'total_seconds': 0.0, 'cached_result': True},
                      run_dir=str(arguments['run_dir']),
                      work_dir=str(arguments['run_dir'] / '_work'))
        return result
    result = formal_check.evaluate_assertion(**arguments)
    if result['status'] in {'FULL_EQUIVALENCE', *SEMANTIC_FAILURES}:
        cache[key] = (round_number, deepcopy(result))
    return result


def retain_checker_failure(directory, record, round_number, result):
    """Keep small failure inputs/logs before the round's temporary tree disappears."""
    if (not record['settings'].get('save_debug_traces') or
            result['status'] not in {'PEC_COMPILE_ERROR', 'TOOL_ERROR'}):
        return
    source = Path(result['run_dir'])
    target = Path(directory) / 'diagnostics' / f'round_{round_number:04d}'
    target.mkdir(parents=True, exist_ok=True)
    files = [source / name for name in ('jasper.log', 'native_pec_inputs.json', 'evaluation_error.log')]
    work = Path(result['work_dir'])
    files += sorted(work.glob('jg/*/pec/pec*.sve'))
    saved = []
    for path in files:
        if path.is_file():
            destination = target / path.name
            shutil.copyfile(path, destination)
            saved.append(str(destination))
    result['retained_diagnostics'] = saved

