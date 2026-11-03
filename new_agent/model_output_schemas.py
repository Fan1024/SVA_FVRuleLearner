"""Transport schemas matching the existing prompts; no task-specific values."""


def _object(**properties):
    return {'type': 'object', 'properties': properties,
            'required': list(properties), 'additionalProperties': False}


def _array(items):
    return {'type': 'array', 'items': items}


TRAINING_RULES = _object(
    diagnoses=_array(_object(category={'type': 'string'}, statement={'type': 'string'})),
    corrections=_array(_object(generated_node_id={'type': 'string'}, rule={'type': 'string'})),
)

INFERENCE_SELECTION = _object(
    selected_diagnoses=_array({'type': 'integer'}),
    selected_rules=_array(_object(rule_id={'type': 'string'})),
)
