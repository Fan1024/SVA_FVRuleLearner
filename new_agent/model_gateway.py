"""Provider routing behind the experiment's existing Responses-shaped client.

Only verified text/JSON-object routes are enabled. Prompts, output parsing and
evaluation policy belong to the existing pipeline and are not rewritten here.
"""
import os
from types import SimpleNamespace

from new_agent import config

VERSION = 'official_text_json_gateway_v1'
PROVIDERS = {
    'openai': {'api_key_env': 'OPENAI_API_KEY', 'base_url': 'https://api.openai.com/v1'},
    'kimi': {'api_key_env': 'MOONSHOT_API_KEY', 'base_url': 'https://api.moonshot.ai/v1'},
    'deepseek': {'api_key_env': 'DEEPSEEK_API_KEY', 'base_url': 'https://api.deepseek.com'},
}
CHAT_MODELS = {
    'kimi': frozenset({'kimi-k3.1-pro', 'kimi-k3.1-pro-highspeed'}),
    'deepseek': frozenset({'deepseek-v4-pro', 'deepseek-flash'}),
}


def provider_for_model(model):
    if not isinstance(model, str) or not model.strip():
        raise ValueError('A nonempty model ID is required.')
    if model.startswith(('claude-', 'anthropic/')):
        raise ValueError(
            'Claude is not enabled: its OpenAI compatibility endpoint rejects '
            'json_object mode required by the unchanged rule/selector interface.')
    for provider, models in CHAT_MODELS.items():
        if model in models:
            return provider
    if model.startswith(('kimi-', 'moonshot-', 'deepseek-', 'kimi/', 'deepseek/')):
        supported = ', '.join(sorted(model for models in CHAT_MODELS.values() for model in models))
        raise ValueError('Unverified or retired provider model ID. Enabled IDs: '+supported)
    # Preserve the existing OpenAI model-ID behavior for all other names.
    return 'openai'


def model_settings(model):
    """Public run metadata and validation; never include credential values."""
    provider = provider_for_model(model)
    effort = getattr(config, 'MODEL_REASONING_EFFORT', None)
    allowed = ({'none', 'low', 'medium', 'high', 'xhigh', 'max'} if provider == 'openai'
               else {'low', 'high', 'max'})
    if effort is not None and effort not in allowed:
        raise ValueError(f'{provider} does not support the requested reasoning effort; '
                         f'use None or one of {sorted(allowed)}. No effort remapping is applied.')
    maximum = getattr(config, 'MODEL_MAX_OUTPUT_TOKENS', None)
    if maximum is not None and (type(maximum) is not int or maximum < 1):
        raise ValueError('MODEL_MAX_OUTPUT_TOKENS must be None or a positive integer.')
    settings = dict(PROVIDERS[provider], model=model, provider=provider,
                    api='responses' if provider == 'openai' else 'chat_completions',
                    reasoning_effort=effort, max_output_tokens=maximum)
    if provider == 'openai':
        settings['base_url'] = os.environ.get('OPENAI_BASE_URL') or settings['base_url']
    return settings


def required_api_keys(models):
    return sorted({model_settings(model)['api_key_env'] for model in models})


def _usage(usage):
    if usage is None:
        return None
    return {'input_tokens': getattr(usage, 'prompt_tokens', None),
            'output_tokens': getattr(usage, 'completion_tokens', None),
            'total_tokens': getattr(usage, 'total_tokens', None)}


class ModelGateway:
    """Lazy provider clients, including mixed assertion/rule providers per run."""

    def __init__(self):
        self._clients = {}
        self.responses = SimpleNamespace(create=self._create)

    def _client(self, settings):
        provider = settings['provider']
        if provider not in self._clients:
            from openai import OpenAI
            if not os.environ.get(settings['api_key_env'], '').strip():
                raise ValueError('Missing environment variable: '+settings['api_key_env'])
            if provider == 'openai':
                self._clients[provider] = OpenAI()
            else:
                self._clients[provider] = OpenAI(
                    api_key=os.environ[settings['api_key_env']], base_url=settings['base_url'])
        return self._clients[provider]

    def _create(self, *, model, instructions, input, **options):
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
