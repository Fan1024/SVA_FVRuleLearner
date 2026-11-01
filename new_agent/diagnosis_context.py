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
    if not isinstance(value, str):
        raise ValueError('diagnosis must be a category label')
    normalized = value.strip().casefold().replace('_', ' ')
    for category in DIAGNOSIS_CATEGORIES:
        if normalized == category.casefold():
            return category
    raise ValueError('diagnosis must use one of DIAGNOSIS_CATEGORIES')


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
    return ('HIGH-LEVEL DIAGNOSIS OPTIONS\n' + '\n'.join('- ' + item for item in DIAGNOSIS_CATEGORIES)
            + '\nUse one primary category per correction/location. diagnosis is only the short '
              'category label, never a case-specific explanatory sentence. '
              'Describe construction details in requirement_interpretation and the useful correction action.')


def diagnosis_view(value):
    if isinstance(value, str):
        try:
            return {'category': category_label(value)}
        except ValueError:
            return {'category': value.strip()} if value.strip() else {}
    if not isinstance(value, dict):
        return {}
    return {key: value[key] for key in ("id", "category", "statement")
            if isinstance(value.get(key), str)}


def review_view(value):
    if not isinstance(value, dict):
        return {}
    return {key: value[key] for key in ("required_behavior", "generated_behavior")
            if isinstance(value.get(key), str)}


def linked_diagnoses(correction, response=None):
    """Resolve optional links, including legacy records with no diagnosis."""
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
    """An allowlisted copy for the next training assertion generator."""
    if 'requirement_interpretation' in response or any(
            'diagnosis' in item for item in response.get('corrections', []) if isinstance(item, dict)):
        result = {'requirement_interpretation': interpretation_view(response.get('requirement_interpretation'))}
        if isinstance(response.get('reference_conflict'), str) and response['reference_conflict'].strip():
            result['reference_conflict'] = response['reference_conflict'].strip()
        return result
    return {
        "behavior_review": review_view(response.get("behavior_review")),
        "diagnoses": [diagnosis_view(item) for item in response.get("diagnoses", [])
                      if isinstance(item, dict)],
    }

