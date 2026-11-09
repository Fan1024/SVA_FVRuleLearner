#!/usr/bin/env bash
set +x
set -eu
deepseek_case_python="${DEEPSEEK_DIAG_PYTHON:-python}"
exec "$deepseek_case_python" -u - "$@" <<'DEEPSEEK_CASE_PY'
import argparse
import hashlib
import json
from math import isfinite
import multiprocessing as mp
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.request

BASE_URL = 'https://api.deepseek.com'
SYSTEM = 'unused in real-case mode'
QUESTION = 'unused in real-case mode'
DIAGNOSTIC_REQUEST = None
NETWORK_READ_TIMEOUT = 300


def redact(value):
    text = str(value)
    secret = os.environ.get('DEEPSEEK_API_KEY', '').strip()
    if secret:
        text = text.replace(secret, '[REDACTED]')
    text = re.sub(r'(?i)(bearer\s+)\S+', r'\1[REDACTED]', text)
    text = re.sub(r'\bsk-[A-Za-z0-9_-]+', '[REDACTED]', text)
    return re.sub(r'(https?://)[^\s/@]+:[^\s/@]+@', r'\1[REDACTED]@', text)

def usage_fields(value):
    if not isinstance(value, dict):
        return None
    result = {k: value[k] for k in ('prompt_tokens', 'completion_tokens', 'total_tokens',
                                   'input_tokens', 'output_tokens') if k in value}
    details = value.get('completion_tokens_details') or {}
    if isinstance(details, dict) and 'reasoning_tokens' in details:
        result['reasoning_tokens'] = details['reasoning_tokens']
    return result or None

def raw_probe(kind, model, tokens, emit, base_url=BASE_URL):
    key = os.environ['DEEPSEEK_API_KEY'].strip()
    started = time.monotonic()
    last_progress = started
    if kind == 'models':
        url, body = base_url.rstrip('/') + '/models', None
    else:
        url = base_url.rstrip('/') + '/chat/completions'
        body = dict(model=model, messages=[{'role': 'system', 'content': SYSTEM},
                    {'role': 'user', 'content': QUESTION}], stream=True,
                    stream_options={'include_usage': True})
        if kind == 'no_thinking':
            body.update(thinking={'type': 'disabled'}, reasoning_effort='none', max_tokens=64)
        else:
            body.update(thinking={'type': 'enabled'}, reasoning_effort='low', max_tokens=tokens)
    if kind == 'real_case':
        body = dict(DIAGNOSTIC_REQUEST)
        body.update(stream=True, stream_options={'include_usage': True})
    request = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(),
        headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json',
                 'Accept': 'application/json' if kind == 'models' else 'text/event-stream'})
    try:
        # This is a socket-operation timeout. The parent enforces a separate wall deadline.
        with urllib.request.urlopen(request, timeout=NETWORK_READ_TIMEOUT) as response:
            elapsed = time.monotonic() - started
            emit('HTTP {} received at {:.2f}s'.format(response.status, elapsed))
            request_id = response.headers.get('x-request-id') or response.headers.get('x-ds-request-id')
            if request_id:
                emit('Request ID: ' + request_id)
            if kind == 'models':
                result = json.loads(response.read(1024 * 1024))
                ids = [r.get('id') for r in result.get('data', []) if isinstance(r, dict)]
                emit('Available models: ' + ', '.join(str(i) for i in ids))
                return dict(status='ok', model_listed=model in ids)
            content, reasoning_chars, content_chars, keepalives = [], 0, 0, 0
            first_reasoning = first_content = False
            finish, usage, done = None, None, False
            for line in iter(lambda: response.readline(1024 * 1024), b''):
                line = line.decode('utf-8', 'replace').strip()
                if not line or line.startswith(':'):
                    keepalives += 1
                    if keepalives == 1:
                        emit('Keep-alive received; the connection is open, with no model text yet.')
                    continue
                if not line.startswith('data:'):
                    raise ValueError('Unexpected non-SSE response: ' + line[:200])
                data = line[5:].strip()
                if data == '[DONE]':
                    done = True
                    break
                now = time.monotonic()
                if now - last_progress >= 10:
                    emit('Progress at {:.1f}s: reasoning_chars={}, final_chars={}'.format(
                        now-started, reasoning_chars, content_chars))
                    last_progress = now
                chunk = json.loads(data)
                if chunk.get('error'):
                    return dict(status='api_error', error=redact(json.dumps(chunk['error']))[:600])
                if chunk.get('usage'):
                    usage = usage_fields(chunk['usage'])
                for choice in chunk.get('choices', []):
                    delta = choice.get('delta') or {}
                    reasoning = delta.get('reasoning_content') or ''
                    answer = delta.get('content') or ''
                    if reasoning:
                        reasoning_chars += len(reasoning)
                        if not first_reasoning:
                            emit('First reasoning delta at {:.2f}s (reasoning text is not printed).'.format(
                                time.monotonic() - started))
                            first_reasoning = True
                    if answer:
                        content_chars += len(answer)
                        if not first_content:
                            emit('First final-answer delta at {:.2f}s'.format(time.monotonic() - started))
                            first_content = True
                        if sum(len(part) for part in content) < 160:
                            content.append(answer[:160])
                    if choice.get('finish_reason') is not None:
                        finish = choice['finish_reason']
            status = ('ok' if done and finish == 'stop' and content_chars else
                      'budget_limited' if done and finish == 'length' else 'incomplete')
            return dict(status=status, finish_reason=finish, received_done=done,
                        reasoning_chars=reasoning_chars, final_chars=content_chars,
                        answer=redact(''.join(content)[:160]), usage=usage)
    except urllib.error.HTTPError as error:
        details = error.read(4096).decode('utf-8', 'replace')
        return dict(status='http_error', http_status=error.code, error=redact(details)[:600])

def find_repo():
    for base in (Path.cwd(), *Path.cwd().parents):
        for folder in (base, base / 'new_agent'):
            if (folder / 'model_gateway.py').is_file() and (folder / 'config.py').is_file():
                return folder
    return None

def worker(connection, operation, arguments):
    def emit(message):
        connection.send(('event', redact(message)))
    try:
        result = operation(*arguments, emit)
    except Exception as error:
        result = dict(status='error', error=redact(type(error).__name__ + ': ' + str(error))[:800])
    try:
        connection.send(('result', result))
    finally:
        connection.close()

def run_probe(label, operation, arguments, deadline):
    print('\n' + label, flush=True)
    context = mp.get_context('fork')
    parent, child = context.Pipe(duplex=False)
    process = context.Process(target=worker, args=(child, operation, arguments), daemon=True)
    started = time.monotonic()
    process.start()
    child.close()
    result, next_notice = None, 10.0
    try:
        while result is None:
            elapsed = time.monotonic() - started
            remaining = deadline - elapsed
            if remaining <= 0:
                result = dict(status='wall_timeout', error='Hard wall deadline reached; probe stopped.')
                break
            if parent.poll(min(0.25, remaining)):
                try:
                    kind, value = parent.recv()
                except EOFError:
                    result = dict(status='error', error='Probe exited without a result.')
                    break
                if kind == 'result':
                    result = value
                else:
                    print('  ' + redact(value), flush=True)
            elapsed = time.monotonic() - started
            if result is None and elapsed >= next_notice:
                print('  Waiting {:.0f}s; hard deadline {:.0f}s.'.format(elapsed, deadline), flush=True)
                next_notice += 10
    finally:
        if process.is_alive():
            process.terminate()
        process.join(2)
        if process.is_alive():
            process.kill()
            process.join(2)
        parent.close()
    result['elapsed_seconds'] = round(time.monotonic() - started, 2)
    print('  RESULT ' + redact(json.dumps(result, ensure_ascii=False)), flush=True)
    return result

def build_request(folder, case_id, effort, maximum):
    sys.path.insert(0, str(Path(folder).parent))
    from new_agent import config
    from new_agent import train_assertion_generator as generator
    from new_agent.dataset_loader import load_cases
    from new_agent.training_prompt_context import statement_template
    case = load_cases(config.DATASET_PATH, [case_id])[0]
    model = config.MODEL
    if model not in ('deepseek-v4-pro', 'deepseek-flash'):
        raise ValueError('Set MODEL to a supported DeepSeek model in your experiment config first.')
    user = generator.build_generation_prompt(case['requirement'], case['testbench'],
        assertion_template=case.get('assertion_template') or statement_template(config.DATASET))
    request = dict(model=model, messages=[{'role': 'system', 'content': generator.SYSTEM_PROMPT},
                                        {'role': 'user', 'content': user}])
    if effort == 'config':
        effort = getattr(config, 'MODEL_REASONING_EFFORT', None)
    if effort is not None:
        if effort not in ('none', 'low', 'high', 'max'):
            raise ValueError('Unsupported DeepSeek effort: ' + str(effort))
        request['reasoning_effort'] = effort
        request['thinking'] = {'type': 'disabled' if effort == 'none' else 'enabled'}
    if maximum == 'config':
        maximum = getattr(config, 'MODEL_MAX_OUTPUT_TOKENS', None)
    elif maximum is not None:
        maximum = int(maximum)
    if maximum is not None:
        if type(maximum) is not int or not 1 <= maximum <= 393216:
            raise ValueError('max-tokens must be config or an integer from 1 through 393216')
        request['max_tokens'] = maximum
    info = dict(case_number=case_id, design_name=case['design_name'], task_id=case['task_id'],
                model=model, requested_effort=effort, max_tokens=request.get('max_tokens', 'provider default'),
                original_config_effort=getattr(config, 'MODEL_REASONING_EFFORT', None),
                original_config_max_tokens=getattr(config, 'MODEL_MAX_OUTPUT_TOKENS', None),
                system_chars=len(generator.SYSTEM_PROMPT), user_chars=len(user),
                input_sha256=hashlib.sha256((generator.SYSTEM_PROMPT+'\0'+user).encode()).hexdigest())
    return request, info


def main():
    global DIAGNOSTIC_REQUEST, NETWORK_READ_TIMEOUT
    parser=argparse.ArgumentParser(description='Stream the actual initial TRAINING assertion prompt; no Jasper or experiment files are written.')
    parser.add_argument('--case-id',type=int,default=1)
    parser.add_argument('--effort',choices=('config','none','low','high','max'),default='config')
    parser.add_argument('--max-tokens',default='8192',help='Diagnostic cap (default 8192), or config to preserve the experiment setting.')
    parser.add_argument('--wall-seconds',type=float,default=300,help='Hard total deadline (default 300 seconds).')
    args=parser.parse_args()
    if args.case_id<1 or not isfinite(args.wall_seconds) or args.wall_seconds<=0:
        parser.error('case-id and finite wall-seconds must be positive')
    if not os.environ.get('DEEPSEEK_API_KEY','').strip():
        print('DEEPSEEK_API_KEY is absent; its value is never printed.')
        return 2
    folder=find_repo()
    if folder is None:
        print('Run from your repository new_agent directory.')
        return 2
    try:
        DIAGNOSTIC_REQUEST,info=build_request(folder,args.case_id,args.effort,args.max_tokens)
    except Exception as error:
        print(redact(type(error).__name__+': '+str(error)))
        return 2
    NETWORK_READ_TIMEOUT=min(args.wall_seconds,600)
    print('One diagnostic request using the repository initial TRAINING prompt.')
    print('Only streaming, chosen effort/token cap, and the hard deadline differ from the experiment.')
    print(json.dumps(info,ensure_ascii=False,indent=2))
    print('The input_sha256 should match between high/low tests of the same case.')
    print('Reasoning progress is reported as character counts; reasoning text is not printed.')
    result=run_probe('Actual training prompt, streaming',raw_probe,
                     ('real_case',DIAGNOSTIC_REQUEST['model'],DIAGNOSTIC_REQUEST.get('max_tokens',8192)),args.wall_seconds)
    print('\nINTERPRETATION')
    print('reasoning_chars grows: model inference is active; this is not proof of a network block.')
    print('HTTP 200 / keep-alives but no reasoning: provider wait/queue or inference stall remains possible.')
    print('No HTTP response / connection error: investigate network, TLS, DNS, SDK-independent connectivity.')
    print('finish_reason=length: the diagnostic output budget was reached, not the input-context limit.')
    print('wall_timeout: hard deadline reached; this does not prove the model generated zero tokens.')
    print('Usage is exact only when returned by the provider. Character counts are not token counts.')
    print('No experiment files, prompts or config.py were changed; no Jasper process was started.')
    return 0 if result['status'] in ('ok','budget_limited') else 1


if __name__=='__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\nDiagnostic interrupted.',flush=True)
        sys.exit(130)

DEEPSEEK_CASE_PY
