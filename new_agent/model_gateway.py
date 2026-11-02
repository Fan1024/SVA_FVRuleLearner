"""Provider routing behind the experiment's existing Responses-shaped client.

Only verified text/JSON-object routes are enabled. Prompts, output parsing and
evaluation policy belong to the existing pipeline and are not rewritten here.
"""
import os
from types import SimpleNamespace

from new_agent import config

VERSION = 'official_text_json_gateway_v2_native_claude'
PROVIDERS = {
    'openai': {'api_key_env': 'OPENAI_API_KEY', 'base_url': 'https://api.openai.com/v1'},
    'kimi': {'api_key_env': 'MOONSHOT_API_KEY', 'base_url': 'https://api.moonshot.ai/v1'},
    'deepseek': {'api_key_env': 'DEEPSEEK_API_KEY', 'base_url': 'https://api.deepseek.com'},
    'claude': {'api_key_env': 'ANTHROPIC_API_KEY', 'base_url': 'https://api.anthropic.com/v1'},
}
CHAT_MODELS = {
    'kimi': frozenset({'kimi-k3.1-pro', 'kimi-k3.1-pro-highspeed'}),
    'deepseek': frozenset({'deepseek-v4-pro', 'deepseek-flash'}),
}
CLAUDE_MODELS = frozenset({'claude-sonnet-5-5', 'claude-opus-5-5'})


def provider_for_model(model):
    if not isinstance(model, str) or not model.strip():
        raise ValueError('A nonempty model ID is required.')
    if model in CLAUDE_MODELS:
        return 'claude'
    for provider, models in CHAT_MODELS.items():
        if model in models:
            return provider
    if model.startswith(('kimi-', 'moonshot-', 'deepseek-', 'kimi/', 'deepseek/', 'claude-', 'anthropic/')):
        supported = ', '.join(sorted(CLAUDE_MODELS | set().union(*CHAT_MODELS.values())))
        raise ValueError('Unverified or retired provider model ID. Enabled IDs: '+supported)
    # Preserve the existing OpenAI model-ID behavior for all other names.
    return 'openai'


def model_settings(model):
    """Public run metadata and validation; never include credential values."""
    provider = provider_for_model(model)
    effort = getattr(config, 'MODEL_REASONING_EFFORT', None)
    allowed = ({'none', 'low', 'medium', 'high', 'xhigh', 'max'} if provider == 'openai'
               else {'low', 'medium', 'high', 'xhigh', 'max'} if provider == 'claude'
               else {'low', 'high', 'max'})
    if effort is not None and effort not in allowed:
        raise ValueError(f'{provider} does not support the requested reasoning effort; '
                         f'use None or one of {sorted(allowed)}. No effort remapping is applied.')
    maximum = getattr(config, 'MODEL_MAX_OUTPUT_TOKENS', None)
    if maximum is not None and (type(maximum) is not int or maximum < 1):
        raise ValueError('MODEL_MAX_OUTPUT_TOKENS must be None or a positive integer.')
    if provider == 'claude' and maximum is None:
        raise ValueError('Claude requires an explicit MODEL_MAX_OUTPUT_TOKENS; use e.g. 32768.')
    settings = dict(PROVIDERS[provider], model=model, provider=provider,
                    api=('responses' if provider == 'openai' else
                         'messages' if provider == 'claude' else 'chat_completions'),
                    reasoning_effort=effort, max_output_tokens=maximum)
    settings['json_output_mode'] = ('native_stage_schema' if provider == 'claude' else 'json_object')
    if provider == 'openai':
        settings['base_url'] = os.environ.get('OPENAI_BASE_URL') or settings['base_url']
    return settings


def required_api_keys(models):
    return sorted({model_settings(model)['api_key_env'] for model in models})


def validate_runtime(models):
    if any(provider_for_model(model) == 'claude' for model in models):
        try:
            from anthropic import Anthropic
        except ImportError as error:
            raise RuntimeError('Claude requires its SDK: python -m pip install --upgrade "anthropic>=1.0"') from error


def _usage(usage):
    if usage is None:
        return None
    return {'input_tokens': getattr(usage, 'prompt_tokens', None),
            'output_tokens': getattr(usage, 'completion_tokens', None),
            'total_tokens': getattr(usage, 'total_tokens', None)}


def _claude_usage(usage):
    if usage is None:
        return None
    inputs = [getattr(usage, 'input_tokens', None),
              getattr(usage, 'cache_creation_input_tokens', 0),
              getattr(usage, 'cache_read_input_tokens', 0)]
    inputs = None if any(value is None for value in inputs) else sum(inputs)
    outputs = getattr(usage, 'output_tokens', None)
    return {'input_tokens': inputs, 'output_tokens': outputs,
            'total_tokens': None if inputs is None or outputs is None else inputs+outputs}


class ModelGateway:
    """Lazy provider clients, including mixed assertion/rule providers per run."""

    def __init__(self):
        self._clients = {}
        self.responses = SimpleNamespace(create=self._create)

    def _client(self, settings):
        provider = settings['provider']
        if provider not in self._clients:
            if not os.environ.get(settings['api_key_env'], '').strip():
                raise ValueError('Missing environment variable: '+settings['api_key_env'])
            if provider == 'claude':
                validate_runtime([settings['model']])
                from anthropic import Anthropic
                headers = {}
                if os.environ.get('ANTHROPIC_WORKSPACE_ID'):
                    headers['anthropic-workspace-id'] = os.environ['ANTHROPIC_WORKSPACE_ID']
                self._clients[provider] = Anthropic(
                    api_key=os.environ[settings['api_key_env']],
                    base_url=settings['base_url'].removesuffix('/v1'),
                    **({'default_headers': headers} if headers else {}))
                return self._clients[provider]
            from openai import OpenAI
            if provider == 'openai':
                self._clients[provider] = OpenAI()
            else:
                self._clients[provider] = OpenAI(
                    api_key=os.environ[settings['api_key_env']], base_url=settings['base_url'])
        return self._clients[provider]

    def _create(self, *, model, instructions, input, output_schema=None, **options):
        settings = model_settings(model)
        provider = settings['provider']
        effort, maximum = settings['reasoning_effort'], settings['max_output_tokens']
        if provider == 'openai':
            # With both optional settings None, this is the original request.
            if effort is not None:
                options['reasoning'] = {'effort': effort}
            if maximum is not None:
                options['max_output_tokens'] = maximum
            return self._client(settings).responses.create(
                model=model, instructions=instructions, input=input, **options)

        if set(options) - {'text'}:
            raise ValueError('Unsupported gateway option for Chat Completions.')
        text_format = options.get('text', {}).get('format', {})
        if text_format and text_format != {'type': 'json_object'}:
            raise ValueError('This gateway preserves text or JSON-object output only.')
        if provider == 'claude':
            if text_format and output_schema is None:
                raise ValueError('Claude JSON calls require the existing stage output schema.')
            request = {'model': model, 'system': instructions,
                       'messages': [{'role': 'user', 'content': input}], 'max_tokens': maximum}
            output_config = {}
            if effort is not None:
                output_config['effort'] = effort
            if text_format:
                output_config['format'] = {'type': 'json_schema', 'schema': output_schema}
            if output_config:
                request['output_config'] = output_config
            # Buffer streaming internally so large reasoning budgets do not hit
            # the SDK's non-streaming duration limit. Callers still get one string.
            with self._client(settings).messages.stream(**request) as stream:
                response = stream.get_final_message()
            finish = response.stop_reason
            if getattr(getattr(response, 'stop_details', None), 'type', None) == 'refusal':
                finish = 'refusal'
            text = ''.join(block.text for block in response.content if block.type == 'text')
            return SimpleNamespace(
                status='completed' if finish == 'end_turn' else f'incomplete (stop_reason={finish})',
                output_text=text, usage=_claude_usage(response.usage))
        request = {'model': model, 'messages': [
            {'role': 'system', 'content': instructions}, {'role': 'user', 'content': input}]}
        if text_format:
            request['response_format'] = {'type': 'json_object'}
        if effort is not None:
            request['reasoning_effort'] = effort
            if provider == 'deepseek':
                request['extra_body'] = {'thinking': {'type': 'enabled'}}
        if maximum is not None:
            request['max_completion_tokens' if provider == 'kimi' else 'max_tokens'] = maximum
        completion = self._client(settings).chat.completions.create(**request)
        choices = completion.choices
        choice = choices[0] if len(choices) == 1 else None
        finish = getattr(choice, 'finish_reason', None)
        content = getattr(getattr(choice, 'message', None), 'content', None)
        # Only final content enters the experiment. Separate reasoning fields
        # never become generated assertions or selector/rule output.
        return SimpleNamespace(
            status='completed' if finish == 'stop' else f'incomplete (finish_reason={finish})',
            output_text=content if isinstance(content, str) else '',
            usage=_usage(completion.usage),
        )
