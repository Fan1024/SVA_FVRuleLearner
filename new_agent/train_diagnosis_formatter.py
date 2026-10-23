"""Format all 52 questions defined in train_diagnosis.py.

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
    "temporal_implication_timing": {
        True: (
            "Correct the consequent start time of an existing implication by changing "
            "|-> to |=> or vice versa as required. |-> starts the consequent at the "
            "antecedent's endpoint; |=> starts it one clock later. Account for existing "
            "## delays and sampled values so the correction does not shift time twice."
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
        True: "Change the clock signal, edge or event used by the assertion or an existing sampled-value function.",
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
    "global_signal_identity": {
        True: (
            "Replace a wrong signal identifier with the intended declared signal for "
            "that operand. For example, a data check may use another channel's data "
            "instead of the intended channel's data. Determine the replacement from "
            "the reference and testbench; equivalent aliases or PEC-only declaration "
            "failures do not justify renaming a valid signal."
        ),
    },
    "global_signal_role": {
        True: (
            "Use an operand representing the required behavioral role, rather than "
            "a different event, state, data source or time snapshot. For example, "
            "distinguish a request from an accepted transaction, a current value from "
            "a registered snapshot, and observed data from the model output. Select "
            "the role required by the reference and testbench definitions."
        ),
    },
    "global_missing_behavioral_branch": {
        True: (
            "Add an omitted behavioral scenario together with its required check. "
            "For example, checking stored FIFO data on a nonempty read does not cover "
            "an empty simultaneous-transfer path that requires comparison with incoming "
            "write data. Identify the missing scenario and its obligation from the "
            "reference; adding == 1'b1 alone does not supply a missing branch."
        ),
    },
    "global_wrong_applicability_condition": {
        True: (
            "Correct, remove, repolarize or regroup an existing applicability guard "
            "that enables the wrong situations or exempts required ones. For example, "
            "a nonzero-previous-grant guard addresses later arbitration rather than "
            "first arbitration, and an unnecessary no-write guard can exempt a "
            "required simultaneous transaction. Preserve the intended obligation."
        ),
    },
    "global_missing_applicability_condition": {
        True: (
            "Insert a missing qualification on an already represented obligation, so "
            "the check applies in its required circumstances. For example, qualify an "
            "operation-specific data check with its required accepted-transaction guard. "
            "This adds an absent guard; it does not replace an incorrect existing "
            "guard or introduce a separate behavioral branch."
        ),
    },
    "global_any_vs_all": {
        True: (
            "Correct any-member versus all-members semantics over the intended set. "
            "For a multi-bit vector, |v checks whether any bit is one, whereas &v "
            "checks whether every bit is one; equivalent comparisons or member-wise "
            "conditions may express the same distinction. Choose the quantification "
            "required by the reference while respecting width and X/Z behavior."
        ),
    },
    "global_required_vs_forbidden_condition": {
        True: (
            "Correct the truth requirement or failure polarity of the complete check: "
            "require the valid condition or reject the violation condition, rather "
            "than requiring a violation or forbidding valid behavior. For example, "
            "ok === 1'b1 requires definitely true success, while bad !== 1'b1 rejects "
            "a definitely true violation. Choose the predicate and comparison together "
            "from the reference's intended behavior, including X/Z semantics."
        ),
    },
    "global_cosmetic_vs_semantic": {
        "no_difference": (
            "No differences were identified within comparison_scope. PEC compilation "
            "failure alone does not establish a semantic defect."
        ),
        "cosmetic_only": (
            "Only textual or behavior-preserving differences were identified within "
            "comparison_scope, such as redundant parentheses or equivalent rewrites. "
            "Any formatting normalization must preserve behavior; do not present it "
            "as a semantic repair."
        ),
        "semantic_difference": (
            "At least one difference within comparison_scope changes required behavior. "
            "Address the behavioral difference; cosmetic normalization alone cannot "
            "correct it. Cosmetic differences may also be present."
        ),
        "uncertain": (
            "Whether the observed differences change behavior is unresolved from the "
            "available context. Do not treat PEC compilation failure or text mismatch "
            "alone as evidence of a specific semantic defect."
        ),
    },
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
