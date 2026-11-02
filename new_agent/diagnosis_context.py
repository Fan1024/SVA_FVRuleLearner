"""Carry model-authored diagnosis text; no semantic scoring or rejection."""
from copy import deepcopy

DIAGNOSIS_CATEGORIES = (
    'Scope mismatch',
    'Missing required behavior',
    'Additional obligation',
    'Unjustified exemption',
    'Overly broad activation',
    'Incorrect response relationship',
    'Timing mismatch',
    'Incorrect context interpretation',
    'Polarity or quantification mismatch',
    'Domain or boundary mismatch',
    'Invalid assertion structure',
)
INTERPRETATION_FIELDS = ('scope', 'activation', 'response', 'timing', 'context')


def category_label(value):
    """Read the requested category spelling; no semantic diagnosis scoring."""
    if not isinstance(value, str) or not value.strip():
        raise ValueError('diagnosis must be a nonempty category label')
    normalized = value.strip().casefold().replace('_', ' ')
    for category in DIAGNOSIS_CATEGORIES:
        if normalized == category.casefold():
            return category
    return value.strip()


def interpretation_view(value):
    if not isinstance(value, dict):
        return {}
    return {key: value[key].strip() for key in INTERPRETATION_FIELDS
            if isinstance(value.get(key), str) and value[key].strip()}


def interpretation_instruction():
    return ('Interpret the requirement using scope, activation, response, timing and context. '
            'Include only relevant components, grounded in the requirement/TB. '
            'Do not invent a signal, history marker or extra obligation.')


def category_instructions():
    return ('SUGGESTED HIGH-LEVEL CATEGORIES\n' + '\n'.join('- ' + item for item in DIAGNOSIS_CATEGORIES)
            + '\nThese are examples, not an exhaustive list. Use another concise category when it fits better. '
              'An assertion may have multiple diagnoses; give each category its own explanation.')


def diagnosis_view(value):
    if isinstance(value, str):
        try:
            return {'category': category_label(value)}
        except ValueError:
            return {'category': value.strip()} if value.strip() else {}
    if not isinstance(value, dict):
        return {}
    return {key: value[key] for key in ("category", "statement")
            if isinstance(value.get(key), str)}


def review_view(value):
    if not isinstance(value, dict):
        return {}
    return {key: value[key] for key in ("required_behavior", "generated_behavior")
            if isinstance(value.get(key), str)}


def linked_diagnoses(correction, response=None):
    """Read links in historical source records; new outputs are independent lists."""
    result = [diagnosis_view(item) for item in correction.get("diagnoses", [])
              if isinstance(item, (dict, str))]
    if isinstance(correction.get('diagnosis'), str):
        result.insert(0, diagnosis_view(correction['diagnosis']))
    ids = correction.get("diagnosis_ids", [])
    for item in (response or {}).get("diagnoses", []):
        if isinstance(item, dict) and item.get("id") in ids:
            result.append(diagnosis_view(item))
    unique = []
    for item in result:
        if item and item not in unique:
            unique.append(item)
    return deepcopy(unique)


def diagnosis_payload(response):
    """Forward category/explanation text, never interpretation or conflict records."""
    return {"diagnoses": [diagnosis_view(item) for item in response.get("diagnoses", [])
                          if isinstance(item, dict)]}
