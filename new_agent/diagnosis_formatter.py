"""Format all 43 questions currently defined in jev_assertion_diagnosis.py.

Each input result contains an answer and an upstream confidence value.
The returned dictionary preserves the same unique question IDs as the input.
This module formats results only; it does not call an API or verify assertions.
"""


# Implication question mappings.
IMPLICATION = {
    "implication_replace_operator": {
        True: (
            "An existing implication operator (|-> or |=>) needs to be replaced with an "
            "operator from a different category."
        ),
    },
    "implication_presence": {
        "reference_only": (
            "Implication operators (|->, |=>) appear only in the reference assertion."
        ),
        "generated_only": (
            "Implication operators (|->, |=>) appear only in the generated assertion."
        ),
        "both": "Implication operators (|->, |=>) appear in both assertions.",
        "neither": "Neither assertion contains implication operators (|->, |=>).",
    },
    "implication_insert_operator": {
        True: (
            "Insert a missing implication operator (|-> or |=>) to express the required "
            "behavior."
        ),
    },
    "implication_remove_operator": {
        True: "Remove an unnecessary implication operator (|-> or |=>).",
    },
    "implication_antecedent_consequent": {
        True: (
            "Move conditions between the antecedent and consequent so the trigger and "
            "response are on the correct sides."
        ),
    },
}


# Logical question mappings.
LOGICAL = {
    "logical_presence": {
        "reference_only": "Logical operators (!, &&, ||) appear only in the reference assertion.",
        "generated_only": "Logical operators (!, &&, ||) appear only in the generated assertion.",
        "both": "Logical operators (!, &&, ||) appear in both assertions.",
        "neither": "Neither assertion contains logical operators (!, &&, ||).",
    },
    "logical_replace_operator": {
        True: "Replace an existing logical operator (!, &&, or ||) with a different operator.",
    },
    "logical_insert_operator": {
        True: "Insert a missing logical operator (!, &&, or ||).",
    },
    "logical_remove_operator": {
        True: "Remove an unnecessary logical operator (!, &&, or ||).",
    },
    "logical_scope": {
        True: (
            "Regroup the terms controlled by an existing logical operator to match the "
            "required behavior."
        ),
    },
}


# Comparison question mappings.
COMPARISON = {
    "comparison_presence": {
        "reference_only": (
            "Comparison operators (==, !=, ===, !==, <, <=, >, >=) appear only in the "
            "reference assertion."
        ),
        "generated_only": (
            "Comparison operators (==, !=, ===, !==, <, <=, >, >=) appear only in the "
            "generated assertion."
        ),
        "both": "Comparison operators (==, !=, ===, !==, <, <=, >, >=) appear in both assertions.",
        "neither": (
            "Neither assertion contains comparison operators (==, !=, ===, !==, <, <=, >, "
            ">=)."
        ),
    },
    "comparison_replace_operator": {
        True: "Replace an existing comparison operator with a different operator.",
    },
    "comparison_insert_operator": {
        True: "Insert a missing comparison operator.",
    },
    "comparison_remove_operator": {
        True: "Remove an unnecessary comparison operator.",
    },
    "comparison_operands": {
        True: "Replace an operand of an existing comparison.",
    },
    "comparison_operand_order": {
        True: "Exchange the left and right operands of an existing comparison.",
    },
    "comparison_four_state_equality": {
        True: "Change between ==/!= and ===/!== to match the required handling of X/Z values.",
    },
}


# Bitwise question mappings.
BITWISE = {
    "bitwise_presence": {
        "reference_only": (
            "Bitwise operators (binary &, |, ^, ~^, ^~, unary ~) appear only in the "
            "reference assertion."
        ),
        "generated_only": (
            "Bitwise operators (binary &, |, ^, ~^, ^~, unary ~) appear only in the "
            "generated assertion."
        ),
        "both": "Bitwise operators (binary &, |, ^, ~^, ^~, unary ~) appear in both assertions.",
        "neither": (
            "Neither assertion contains bitwise operators (binary &, |, ^, ~^, ^~, unary "
            "~)."
        ),
    },
    "bitwise_replace_operator": {
        True: "Replace an existing bitwise operator with a different operator.",
    },
    "bitwise_insert_operator": {
        True: "Insert a missing bitwise operator.",
    },
    "bitwise_remove_operator": {
        True: "Remove an unnecessary bitwise operator.",
    },
    "bitwise_operands": {
        True: (
            "Use a different signal, vector, bit range, or subexpression in an existing "
            "bitwise operation."
        ),
    },
}


# Reduction question mappings.
REDUCTION = {
    "reduction_presence": {
        "reference_only": (
            "Unary reduction operators (&, |, ^, ~&, ~|, ~^, ^~) appear only in the "
            "reference assertion."
        ),
        "generated_only": (
            "Unary reduction operators (&, |, ^, ~&, ~|, ~^, ^~) appear only in the "
            "generated assertion."
        ),
        "both": "Unary reduction operators (&, |, ^, ~&, ~|, ~^, ^~) appear in both assertions.",
        "neither": (
            "Neither assertion contains unary reduction operators (&, |, ^, ~&, ~|, ~^, "
            "^~)."
        ),
    },
    "reduction_replace_operator": {
        True: "Replace an existing reduction operator with a different operator.",
    },
    "reduction_insert_operator": {
        True: "Insert a missing reduction operator.",
    },
    "reduction_remove_operator": {
        True: "Remove an unnecessary reduction operator.",
    },
    "reduction_vector_coverage": {
        True: (
            "Apply an existing reduction to a different vector, bit range, or expression "
            "to include the required bits."
        ),
    },
}


# Temporal question mappings.
TEMPORAL = {
    "temporal_presence": {
        "reference_only": (
            "Temporal delays and sampled-value functions (##, $past, $rose, $fell, "
            "$stable, $changed) appear only in the reference assertion."
        ),
        "generated_only": (
            "Temporal delays and sampled-value functions (##, $past, $rose, $fell, "
            "$stable, $changed) appear only in the generated assertion."
        ),
        "both": (
            "Temporal delays and sampled-value functions (##, $past, $rose, $fell, "
            "$stable, $changed) appear in both assertions."
        ),
        "neither": (
            "Neither assertion contains temporal delays and sampled-value functions (##, "
            "$past, $rose, $fell, $stable, $changed)."
        ),
    },
    "temporal_insert_delay": {
        True: "Insert a missing ## delay.",
    },
    "temporal_remove_delay": {
        True: "Remove an unnecessary ## delay.",
    },
    "temporal_delay_value": {
        True: "Change the cycle count of an existing fixed ## delay.",
    },
    "temporal_delay_lower_bound": {
        True: "Change the lower bound of an existing ## delay range.",
    },
    "temporal_delay_upper_bound": {
        True: "Change the upper bound of an existing ## delay range.",
    },
    "temporal_replace_sampling_function": {
        True: (
            "Replace an existing sampled-value function with a different function ($past, "
            "$rose, $fell, $stable, or $changed)."
        ),
    },
    "temporal_insert_sampling_function": {
        True: "Insert a missing sampled-value function.",
    },
    "temporal_remove_sampling_function": {
        True: "Remove an unnecessary sampled-value function.",
    },
    "temporal_past_offset": {
        True: "Change the history offset of an existing $past call.",
    },
    "temporal_sampling_clock": {
        True: "Change the sampling clock used by an existing sampled-value function.",
    },
    "temporal_scope": {
        True: "Apply an existing delay or sampled-value function to a different subexpression.",
    },
}


# Parentheses question mappings.
PARENTHESES = {
    "parentheses_presence": {
        "reference_only": "Expression-grouping parentheses appear only in the reference assertion.",
        "generated_only": "Expression-grouping parentheses appear only in the generated assertion.",
        "both": "Expression-grouping parentheses appear in both assertions.",
        "neither": "Neither assertion contains expression-grouping parentheses.",
    },
    "parentheses_grouping": {
        True: "Change expression grouping to correct operator precedence or scope.",
    },
}


# Global question mappings.
GLOBAL = {
    "global_operator_category_error_count": {
        "zero": "No operator categories require correction.",
        "one": "One operator category requires correction.",
        "two_or_three": "Two or three operator categories require correction.",
        "more_than_three": "More than three operator categories require correction.",
    },
    "global_operator_occurrence_edit_count": {
        "zero": "No individual operator occurrences require correction.",
        "one": "One individual operator occurrence requires correction.",
        "two_or_three": "Two or three individual operator occurrences require correction.",
        "more_than_three": "More than three individual operator occurrences require correction.",
    },
}


# Combine the category dictionaries into one question-to-statement lookup.
STATEMENT_MAPPINGS = {
    **IMPLICATION,
    **LOGICAL,
    **COMPARISON,
    **BITWISE,
    **REDUCTION,
    **TEMPORAL,
    **PARENTHESES,
    **GLOBAL,
}


def format_diagnosis(answers: dict, confidence_threshold: float = 0.4) -> dict[str, str]:
    """Format confident True and Choice answers; skip Boolean False."""
    statements = {}

    for question_name, result in answers.items():
        if question_name not in STATEMENT_MAPPINGS:
            continue

        decision = result["answer"]

        # Suppress "no change needed" statements.
        if decision is False:
            continue

        if result["confidence"] < confidence_threshold:
            continue

        options = STATEMENT_MAPPINGS[question_name]
        statements[question_name] = options[decision]

    return statements


if __name__ == "__main__":
    # A small local example; running this file makes no API calls.
    answers = {
        "implication_presence": {"answer": "generated_only", "confidence": 1.0},
        "implication_replace_operator": {"answer": False, "confidence": 0.0},
        "logical_scope": {"answer": True, "confidence": 0.8},
        "comparison_four_state_equality": {"answer": False, "confidence": 0.9},
        "temporal_past_offset": {"answer": True, "confidence": 0.7},
        "parentheses_grouping": {"answer": True, "confidence": 0.85},
        "global_operator_category_error_count": {"answer": "two_or_three", "confidence": 0.8},
        "global_operator_occurrence_edit_count": {"answer": "more_than_three", "confidence": 0.9},
    }

    output = format_diagnosis(answers)

    for question_name, statement in output.items():
        print(f"{question_name}: {statement}")
