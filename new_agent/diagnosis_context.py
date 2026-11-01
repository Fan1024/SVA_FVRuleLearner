"""Carry model-authored diagnosis text; no semantic scoring or rejection."""
from copy import deepcopy


def diagnosis_view(value):
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
              if isinstance(item, dict)]
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
    return {
        "behavior_review": review_view(response.get("behavior_review")),
        "diagnoses": [diagnosis_view(item) for item in response.get("diagnoses", [])
                      if isinstance(item, dict)],
    }
