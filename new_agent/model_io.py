"""Shared OpenAI transport and output parsing for both experiment stages."""

import json
import re


def request_text(client, model: str, instructions: str, user_prompt: str, *,
                 json_output: bool = False, usage_callback=None) -> str:
    """Save provider usage even if a response is incomplete or invalid."""
    options = {"text": {"format": {"type": "json_object"}}} if json_output else {}
    response = client.responses.create(
        model=model, instructions=instructions, input=user_prompt, **options,
    )
    if usage_callback is not None:
        usage_callback(getattr(response, "usage", None))
    if response.status != "completed":
        raise RuntimeError(f"Model response did not complete: {response.status}")
    if not response.output_text.strip():
        raise RuntimeError("The model returned no output text.")
    return response.output_text


def extract_assertion(response_text: str) -> str:
    """Extract exactly one nonempty systemverilog code block."""
    match = re.fullmatch(r"\s*```systemverilog\s*(.*?)\s*```\s*", response_text, re.DOTALL)
    if match is None or not match.group(1).strip() or "```" in match.group(1):
        raise ValueError("Expected one nonempty systemverilog Markdown code block.")
    return match.group(1).strip()


def parse_rules(response_text: str) -> dict:
    """Validate the shared grouped-rule schema before any registry is updated."""
    rules = json.loads(response_text)
    if not isinstance(rules, dict) or not rules:
        raise ValueError("Expected a nonempty object of labeled rules.")
    if set(rules) != {f"rule_{number}" for number in range(1, len(rules) + 1)}:
        raise ValueError("Use consecutive names: rule_1, rule_2, and so on.")
    groups = set()
    for name, entry in rules.items():
        if not isinstance(entry, dict) or set(entry) != {"group", "rule"}:
            raise ValueError(f"{name} must contain only group and rule.")
        group = entry["group"]
        if (not isinstance(group, list) or not group or
            any(not isinstance(label, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", label)
                for label in group)):
            raise ValueError(f"{name}.group needs lowercase snake_case labels.")
        key = tuple(sorted(set(group)))
        if len(key) != len(group) or key in groups:
            raise ValueError("Rule output contains duplicate labels or canonical groups.")
        groups.add(key)
        if not isinstance(entry["rule"], str) or not entry["rule"].strip():
            raise ValueError(f"{name}.rule must contain an editing instruction.")
    return rules
