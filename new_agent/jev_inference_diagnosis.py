"""Fixed-input inference diagnosis: grouped questions, one Jev call, terminal output."""

import json

from typesafe_sdk import Choice, Noul, TypeSafeClient


# Fixed example: edit these inputs for a different quick test.
requirement = (
    "Whenever a is high at a rising edge of clk, b must be high two rising clock edges "
    "later. Disable this check while rst_n is low."
)
generated_assertion = """asrt: assert property (@(posedge clk) disable iff (tb_reset)
    a |-> ##1 b
);"""
design_context = """module example_tb (
    input logic clk,
    input logic rst_n,
    input logic a,
    input logic b
);
    wire tb_reset;
    assign tb_reset = !rst_n;
endmodule
"""

state = {
    "background": (
        "Assess the generated SystemVerilog assertion against the requirement and design "
        "context. No reference assertion or formal-checker feedback is provided. Do not invent "
        "a hidden reference or assume the generated assertion is wrong. Each repair question "
        "asks whether the supplied inputs support that change. Answer no when the edit is "
        "unnecessary or does not apply; use a Noul value near 0.5 when the inputs do not "
        "support a decision. For Choice questions, use uncertain when appropriate. Judge "
        "behavior rather than textual style, respect clock/reset semantics and equivalent "
        "reset aliases, and do not propose edits solely because a different equivalent form "
        "exists. Each question is independent. Presence observations alone do not imply "
        "errors. These answers are diagnosis hypotheses, not formal proofs."
    ),
    "requirement": requirement,
    "generated_assertion": generated_assertion,
    "design_context": design_context,
}

# Same groups, question keys and repair wording as the training diagnosis.
# Presence answers are candidate-only because inference has no reference.
question_groups = {
    # 1. Implication
    "implication": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain implication operators (|->, |=>)?"
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "replace_operator": Noul(
            instructions="Should an existing implication operator (|-> or |=>) be replaced with a different operator category?",
        ),
        "insert_operator": Noul(
            instructions="Should an implication operator (|-> or |=>) be inserted to express a missing operation?",
        ),
        "remove_operator": Noul(
            instructions="Should an unnecessary implication operator (|-> or |=>) be removed? This question concerns an implication operator (|-> or |=>).",
        ),
        "antecedent_consequent": Noul(
            instructions=(
                "Should conditions be moved between the antecedent and "
                "consequent to put the trigger and response on the correct sides?"
            ),
        ),
    },

    # 2. Logical
    "logical": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain logical operators (!, &&, ||)?"
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "replace_operator": Noul(
            instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a logical operator (!, &&, or ||).",
        ),
        "insert_operator": Noul(
            instructions="Should a logical operator (!, &&, or ||) be inserted to express a missing operation?",
        ),
        "remove_operator": Noul(
            instructions="Should an unnecessary operator in this category be removed? This question concerns a logical operator (!, &&, or ||).",
        ),
        "scope": Noul(
            instructions={
                "background": (
                    "Logical scope means which terms !, &&, or || applies to. "
                    "Examples of different scope: !(a && b) versus (!a) && b; "
                    "a && (b || c) versus (a && b) || c; "
                    "a || (b && c) versus (a || b) && c. "
                    "These examples illustrate binding, not edits to copy. "
                    "A different expression is not wrong if its behavior is equivalent."
                ),
                "question": (
                    "Should the terms controlled by an existing logical operator "
                    "be regrouped to match the required behavior?"
                ),
            },
        ),
    },

    # 3. Comparison
    "comparison": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain comparison operators (==, !=, ===, !==, "
                "<, <=, >, >=)?"
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "replace_operator": Noul(
            instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a comparison operator.",
        ),
        "insert_operator": Noul(
            instructions="Should a comparison operator be inserted to express a missing operation?",
        ),
        "remove_operator": Noul(
            instructions="Should an unnecessary operator in this category be removed? This question concerns a comparison operator.",
        ),
        "operands": Noul(
            instructions="Should an operand of an existing comparison be replaced?",
        ),
        "operand_order": Noul(
            instructions="Should the left and right operands of an existing comparison be exchanged?",
        ),
        "four_state_equality": Noul(
            instructions=(
                "Should == or != be changed to === or !==, or vice versa, "
                "to handle X/Z values as required by the supplied context?"
            ),
        ),
    },

    # 4. Bitwise
    "bitwise": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain bitwise operators (binary &, |, ^, ~^, "
                "^~, unary ~)?"
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "replace_operator": Noul(
            instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a bitwise operator.",
        ),
        "insert_operator": Noul(
            instructions="Should a bitwise operator be inserted to express a missing operation?",
        ),
        "remove_operator": Noul(
            instructions="Should an unnecessary operator in this category be removed? This question concerns a bitwise operator.",
        ),
        "operands": Noul(
            instructions=(
                "Should a bitwise operation use a different signal, "
                "vector, bit range, or subexpression?"
            ),
        ),
    },

    # 5. Reduction
    "reduction": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain unary reduction operators (&, |, ^, ~&, "
                "~|, ~^, ^~)?"
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "replace_operator": Noul(
            instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a reduction operator.",
        ),
        "insert_operator": Noul(
            instructions="Should a reduction operator be inserted to express a missing operation?",
        ),
        "remove_operator": Noul(
            instructions="Should an unnecessary operator in this category be removed? This question concerns a reduction operator.",
        ),
        "vector_coverage": Noul(
            instructions=(
                "Should the reduction apply to a different vector, bit range, "
                "or expression to include the required bits?"
            ),
        ),
    },

    # 6. Temporal
    "temporal": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain ## delays or sampled-value functions "
                "($past, $rose, $fell, $stable, $changed)? Exclude |-> and |=>, which belong to "
                "implication."
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "insert_delay": Noul(
            instructions="Should a missing ## delay be inserted?",
        ),
        "remove_delay": Noul(
            instructions="Should an unnecessary ## delay be removed?",
        ),
        "delay_value": Noul(
            instructions="Should the cycle count of an existing fixed ## delay be changed?",
        ),
        "delay_lower_bound": Noul(
            instructions="Should the lower bound of an existing ## delay range be changed?",
        ),
        "delay_upper_bound": Noul(
            instructions="Should the upper bound of an existing ## delay range be changed?",
        ),
        "replace_sampling_function": Noul(
            instructions=(
                "Should an existing sampled-value function be replaced with "
                "a different function? Consider $past, $rose, $fell, $stable, and $changed."
            ),
        ),
        "insert_sampling_function": Noul(
            instructions="Should a missing sampled-value function be inserted?",
        ),
        "remove_sampling_function": Noul(
            instructions="Should an unnecessary sampled-value function be removed?",
        ),
        "past_offset": Noul(
            instructions="Should the history offset of an existing $past call be changed?",
        ),
        "sampling_clock": Noul(
            instructions=(
                "Should a clock signal, edge, or event used by the assertion "
                "or an existing sampled-value function be changed?"
            ),
        ),
        "scope": Noul(
            instructions={
                "background": (
                    "Scope means which expression a delay or sampled-value function "
                    "controls. For example, $past(a && b) samples both terms in the "
                    "previous cycle, whereas $past(a) && b samples only a in the "
                    "previous cycle and uses b from the current cycle. "
                    "Judge expression binding here, not the delay or history offset."
                ),
                "question": (
                    "Should an existing delay or sampled-value function be applied "
                    "to a different subexpression?"
                ),
            },
        ),
    },

    # 7. Parentheses
    "parentheses": {
        "presence": Choice(
            instructions=(
                "Does the generated assertion contain expression-grouping parentheses? Exclude "
                "assert property wrappers, clock events, and function-call delimiters."
            ),
            criteria={
                "present": "The construct is present in the generated assertion.",
                "absent": "The construct is absent from the generated assertion.",
                "uncertain": "The candidate cannot be interpreted reliably enough to decide.",
            },
        ),
        "grouping": Noul(
            instructions=(
                "Should the expression be grouped differently to fix "
                "operator precedence or scope? "
                "Ignore extra parentheses that preserve the same behavior."
            ),
        ),
    },

    # 8. Global
    "global": {
        "operator_category_error_count": Choice(
            instructions=(
                "How many operator categories need correction? Count implication, "
                "logical, comparison, bitwise excluding shifts, reduction, and "
                "temporal limited to delays and sampled-value functions. "
                "Count each category once even if it has several wrong, missing, "
                "or extra operators. A replacement between categories affects "
                "both categories. Exclude parentheses and equivalent rewrites."
            ),
            criteria={
                "zero": "0 categories.",
                "one": "1 category.",
                "two_or_three": "2 or 3 categories.",
                "more_than_three": "More than 3 categories.",
                "uncertain": "The supplied context is insufficient to determine the count.",
            },
        ),
        "operator_occurrence_edit_count": Choice(
            instructions=(
                "How many individual operator occurrences need correction? "
                "Count implication, logical, comparison, bitwise excluding shifts, "
                "reduction, and temporal delays and sampled-value functions only. "
                "Count each wrong, missing, or extra occurrence once. Repeated "
                "uses of the same operator count separately. A replacement "
                "counts once, even if several changes are needed at that occurrence. "
                "Exclude parentheses and equivalent rewrites."
            ),
            criteria={
                "zero": "0 operator occurrences.",
                "one": "1 operator occurrence.",
                "two_or_three": "2 or 3 operator occurrences.",
                "more_than_three": "More than 3 operator occurrences.",
                "uncertain": "The supplied context is insufficient to determine the count.",
            },
        ),
    },

}

# Jev receives flat IDs; the editable question definitions stay grouped above.
questions = {}
for group, group_questions in question_groups.items():
    for name, question in group_questions.items():
        questions[f"{group}_{name}"] = question


def diagnose_inference_assertion(requirement, generated_assertion, design_context=""):
    """Return one batch of inference answers without accepting a reference."""
    request_state = {
        **state,
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "design_context": design_context,
    }
    with TypeSafeClient() as client:
        response = client.system_one(state=request_state, questions=questions)
    answers = {}
    raw_answers = {}
    for question_id in questions:
        raw = response.answers[question_id].model_dump(mode="json")
        raw_answers[question_id] = raw
        if raw["type"] == "noul":
            answers[question_id] = {
                "answer": raw["noul"] > 0.5,
                "confidence": round(abs(2 * raw["noul"] - 1), 12),
            }
        else:
            answers[question_id] = {"answer": raw["choice"], "confidence": raw["confidence"]}
    return {
        "answers": answers,
        "raw_answers": raw_answers,
        "model": response.model,
        "usage": getattr(response, "usage", None),
    }


if __name__ == "__main__":
    print("INPUTS")
    print(json.dumps(state, indent=2))
    print(f"\nSending {len(questions)} questions to Jev...", flush=True)
    diagnosis = diagnose_inference_assertion(requirement, generated_assertion, design_context)

    for group, group_questions in question_groups.items():
        print(f"\nGROUP: {group}")
        for name, question in group_questions.items():
            question_id = f"{group}_{name}"
            raw = diagnosis["raw_answers"][question_id]
            processed = diagnosis["answers"][question_id]

            print(f"\nQuestion: {question_id}")
            print(json.dumps(question.model_dump(mode="json", exclude_none=True), indent=2))
            print("Raw answer:", json.dumps(raw))
            print("Processed answer:", json.dumps(processed))

    print("\nModel:", diagnosis["model"])
    print("Usage:", diagnosis["usage"])
