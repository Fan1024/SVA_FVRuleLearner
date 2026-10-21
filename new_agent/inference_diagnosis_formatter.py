"""Explicit requirement-based statement mappings for all 43 inference questions.

Keep the question IDs aligned with training. Format diagnosis answers only;
the statements remain hypotheses for the inference rule generator to assess.
"""


# Implication questions.
IMPLICATION = {
    "implication_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains implication operators "
            "(|->, |=>)."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain implication "
            "operators (|->, |=>)."
        ),
    },
    "implication_replace_operator": {
        True: (
            "Requirement-based diagnosis: an existing implication operator (|-> or |=>) may need "
            "replacement with an operator from a different category to express the required "
            "behavior."
        ),
    },
    "implication_insert_operator": {
        True: (
            "Requirement-based diagnosis: an implication operator (|-> or |=>) may need insertion "
            "to express a missing trigger-response relation."
        ),
    },
    "implication_remove_operator": {
        True: (
            "Requirement-based diagnosis: an unnecessary implication operator (|-> or |=>) may "
            "need removal to express the required behavior."
        ),
    },
    "implication_antecedent_consequent": {
        True: (
            "Requirement-based diagnosis: conditions may need relocation between the antecedent "
            "and consequent so the trigger and response occupy the sides required by the "
            "requirement."
        ),
    },
}


# Logical questions.
LOGICAL = {
    "logical_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains logical operators (!, "
            "&&, ||)."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain logical "
            "operators (!, &&, ||)."
        ),
    },
    "logical_replace_operator": {
        True: (
            "Requirement-based diagnosis: an existing logical operator (!, &&, or ||) may need "
            "replacement with a different operator to express the required condition."
        ),
    },
    "logical_insert_operator": {
        True: (
            "Requirement-based diagnosis: a logical operator (!, &&, or ||) may need insertion to "
            "express an operation or condition required by the requirement."
        ),
    },
    "logical_remove_operator": {
        True: (
            "Requirement-based diagnosis: an unnecessary logical operator (!, &&, or ||) may need "
            "removal to express the required condition."
        ),
    },
    "logical_scope": {
        True: (
            "Requirement-based diagnosis: the terms controlled by an existing !, &&, or || may "
            "need regrouping so the logical operation has the scope required by the requirement."
        ),
    },
}


# Comparison questions.
COMPARISON = {
    "comparison_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains comparison operators "
            "(==, !=, ===, !==, <, <=, >, >=)."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain comparison "
            "operators (==, !=, ===, !==, <, <=, >, >=)."
        ),
    },
    "comparison_replace_operator": {
        True: (
            "Requirement-based diagnosis: an existing comparison operator may need replacement "
            "with a different operator to express the required relation."
        ),
    },
    "comparison_insert_operator": {
        True: (
            "Requirement-based diagnosis: a comparison operator may need insertion to express a "
            "missing relation required by the requirement."
        ),
    },
    "comparison_remove_operator": {
        True: (
            "Requirement-based diagnosis: an unnecessary comparison operator may need removal to "
            "express the required behavior."
        ),
    },
    "comparison_operands": {
        True: (
            "Requirement-based diagnosis: an operand of an existing comparison may need "
            "replacement so the comparison relates the signals, values or expressions specified "
            "by the requirement."
        ),
    },
    "comparison_operand_order": {
        True: (
            "Requirement-based diagnosis: the left and right operands of an existing comparison "
            "may need exchanging to express the direction of the required relation."
        ),
    },
    "comparison_four_state_equality": {
        True: (
            "Requirement-based diagnosis: equality operators may need changing between ==/!= and "
            "===/!== to express the handling of X/Z values supported by the requirement and "
            "design context."
        ),
    },
}


# Bitwise questions.
BITWISE = {
    "bitwise_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains bitwise operators "
            "(binary &, |, ^, ~^, ^~, or unary ~)."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain bitwise "
            "operators (binary &, |, ^, ~^, ^~, or unary ~)."
        ),
    },
    "bitwise_replace_operator": {
        True: (
            "Requirement-based diagnosis: an existing bitwise operator may need replacement with "
            "a different operator to express the required bit-level operation."
        ),
    },
    "bitwise_insert_operator": {
        True: (
            "Requirement-based diagnosis: a bitwise operator may need insertion to express a "
            "missing bit-level operation required by the requirement."
        ),
    },
    "bitwise_remove_operator": {
        True: (
            "Requirement-based diagnosis: an unnecessary bitwise operator may need removal to "
            "express the required bit-level behavior."
        ),
    },
    "bitwise_operands": {
        True: (
            "Requirement-based diagnosis: an existing bitwise operation may need a different "
            "signal, vector, bit range or subexpression to operate on the bits specified by the "
            "requirement."
        ),
    },
}


# Reduction questions.
REDUCTION = {
    "reduction_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains unary reduction "
            "operators (&, |, ^, ~&, ~|, ~^, ^~)."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain unary "
            "reduction operators (&, |, ^, ~&, ~|, ~^, ^~)."
        ),
    },
    "reduction_replace_operator": {
        True: (
            "Requirement-based diagnosis: an existing unary reduction operator may need "
            "replacement with a different operator to express the required aggregate bit "
            "condition."
        ),
    },
    "reduction_insert_operator": {
        True: (
            "Requirement-based diagnosis: a unary reduction operator may need insertion to "
            "express a missing aggregate condition over the bits specified by the requirement."
        ),
    },
    "reduction_remove_operator": {
        True: (
            "Requirement-based diagnosis: an unnecessary unary reduction operator may need "
            "removal to express the required behavior."
        ),
    },
    "reduction_vector_coverage": {
        True: (
            "Requirement-based diagnosis: an existing reduction may need to cover a different "
            "vector, bit range or expression so it includes the bits required by the requirement."
        ),
    },
}


# Temporal questions.
TEMPORAL = {
    "temporal_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains ## delays or "
            "sampled-value functions ($past, $rose, $fell, $stable, $changed); implication "
            "operators are counted separately."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain ## delays or "
            "sampled-value functions ($past, $rose, $fell, $stable, $changed); implication "
            "operators are counted separately."
        ),
    },
    "temporal_insert_delay": {
        True: (
            "Requirement-based diagnosis: a missing ## delay may need insertion to express the "
            "response timing specified by the requirement."
        ),
    },
    "temporal_remove_delay": {
        True: (
            "Requirement-based diagnosis: an unnecessary ## delay may need removal to express the "
            "timing specified by the requirement."
        ),
    },
    "temporal_delay_value": {
        True: (
            "Requirement-based diagnosis: the cycle count of an existing fixed ## delay may need "
            "changing to express the timing specified by the requirement."
        ),
    },
    "temporal_delay_lower_bound": {
        True: (
            "Requirement-based diagnosis: the lower bound of an existing ## delay range may need "
            "changing to express the earliest response cycle permitted by the requirement."
        ),
    },
    "temporal_delay_upper_bound": {
        True: (
            "Requirement-based diagnosis: the upper bound of an existing ## delay range may need "
            "changing to express the latest response cycle permitted by the requirement."
        ),
    },
    "temporal_replace_sampling_function": {
        True: (
            "Requirement-based diagnosis: an existing sampled-value function may need replacement "
            "with a different function ($past, $rose, $fell, $stable or $changed) to express the "
            "required sampled behavior."
        ),
    },
    "temporal_insert_sampling_function": {
        True: (
            "Requirement-based diagnosis: a sampled-value function may need insertion to express "
            "a historical value, edge, stability or change condition required by the requirement."
        ),
    },
    "temporal_remove_sampling_function": {
        True: (
            "Requirement-based diagnosis: an unnecessary sampled-value function may need removal "
            "to express the sampled behavior required by the requirement."
        ),
    },
    "temporal_past_offset": {
        True: (
            "Requirement-based diagnosis: the history offset of an existing $past call may need "
            "changing so the sampled value comes from the cycle required by the requirement."
        ),
    },
    "temporal_sampling_clock": {
        True: (
            "Requirement-based diagnosis: a clock signal, edge or event used by the assertion or "
            "an existing sampled-value function may need changing to match the sampling specified "
            "by the requirement and design context."
        ),
    },
    "temporal_scope": {
        True: (
            "Requirement-based diagnosis: an existing delay or sampled-value function may need to "
            "apply to a different subexpression so its scope matches the temporal behavior "
            "specified by the requirement."
        ),
    },
}


# Parentheses questions.
PARENTHESES = {
    "parentheses_presence": {
        "present": (
            "Requirement-based diagnosis: the generated assertion contains expression-grouping "
            "parentheses, excluding assert property wrappers, clock events and function-call "
            "delimiters."
        ),
        "absent": (
            "Requirement-based diagnosis: the generated assertion does not contain "
            "expression-grouping parentheses, excluding assert property wrappers, clock events "
            "and function-call delimiters."
        ),
    },
    "parentheses_grouping": {
        True: (
            "Requirement-based diagnosis: expression grouping may need changing so operator "
            "precedence or scope expresses the required behavior; equivalent extra parentheses "
            "alone do not require correction."
        ),
    },
}


# Global questions. These counts describe diagnosis estimates, not proofs.
GLOBAL = {
    "global_operator_category_error_count": {
        "zero": (
            "Requirement-based diagnosis: no operator category has been identified as requiring "
            "correction."
        ),
        "one": (
            "Requirement-based diagnosis: one operator category has been identified as "
            "potentially requiring correction."
        ),
        "two_or_three": (
            "Requirement-based diagnosis: two or three operator categories have been identified "
            "as potentially requiring correction."
        ),
        "more_than_three": (
            "Requirement-based diagnosis: more than three operator categories have been "
            "identified as potentially requiring correction."
        ),
    },
    "global_operator_occurrence_edit_count": {
        "zero": (
            "Requirement-based diagnosis: no individual operator occurrence has been identified "
            "as requiring correction."
        ),
        "one": (
            "Requirement-based diagnosis: one individual operator occurrence has been identified "
            "as potentially requiring correction."
        ),
        "two_or_three": (
            "Requirement-based diagnosis: two or three individual operator occurrences have been "
            "identified as potentially requiring correction."
        ),
        "more_than_three": (
            "Requirement-based diagnosis: more than three individual operator occurrences have "
            "been identified as potentially requiring correction."
        ),
    },
}


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


def format_inference_diagnosis(answers, confidence_threshold=0.4):
    """Preserve IDs; format confident True/Choice answers, skipping False/uncertain."""
    statements = {}
    for question_id, result in answers.items():
        if question_id not in STATEMENT_MAPPINGS:
            continue
        decision = result["answer"]
        if decision is False or decision == "uncertain":
            continue
        if result["confidence"] < confidence_threshold:
            continue
        options = STATEMENT_MAPPINGS[question_id]
        if decision not in options:
            raise ValueError(f"Unsupported inference answer for {question_id}: {decision!r}")
        statements[question_id] = options[decision]
    return statements
