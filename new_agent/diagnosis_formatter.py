# Group statement mappings by operator category.
IMPLICATION = {
    # Noul question: the answer is True or False.
    "implication_replace_operator": {
        True: (
            "An existing implication operator (|-> or |=>) needs to be "
            "replaced with an operator from a different category."
        ),
        False: (
            "No replacement of an implication operator (|-> or |=>) "
            "with an operator from a different category is recommended."
        ),
    },

    # Choice question: the answer is one of these four strings.
    "implication_presence": {
        "reference_only": "Implication operators (|->, |=>) appear only in the reference assertion.",
        "generated_only": "Implication operators (|->, |=>) appear only in the generated assertion.",
        "both": "Implication operators (|->, |=>) appear in both assertions.",
        "neither": "Neither assertion contains implication operators (|->, |=>).",
    },
}


def format_diagnosis(answers: dict, confidence_threshold: float = 0.4) -> dict[str, str]:
    """Format only the two implication questions mapped above."""
    statements = {}

    for question_name, result in answers.items():
        # Other questions are outside this starter's scope.
        if question_name not in IMPLICATION:
            continue

        if result["confidence"] < confidence_threshold:
            continue

        # First lookup: get the dictionary of possible statements.
        options = IMPLICATION[question_name]

        # Get the actual answer: a Boolean or a Choice option string.
        decision = result["answer"]

        # Second lookup: get the statement for that answer.
        statement = options[decision]

        statements[question_name] = statement

    return statements


if __name__ == "__main__":
    answers = {
        "implication_replace_operator": {"answer": True, "confidence": 0.8},
        "implication_presence": {"answer": "both", "confidence": 0.9},
    }

    output = format_diagnosis(answers)

    for question_name, statement in output.items():
        print(f"{question_name}: {statement}")
