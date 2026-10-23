from typing import Any, Optional

from typesafe_sdk import Choice, Noul, TypeSafeClient

from new_agent.formal_check import COMPARISON_SCOPE


def diagnose_assertion_mismatches(
    requirement: str,
    generated_assertion: str,
    reference_assertion: str,
    *,
    design_context: str = "",
    formal_feedback: str = "",
    comparison_scope: str = COMPARISON_SCOPE,
    model: Optional[str] = None,
    client: Optional[TypeSafeClient] = None,
    usage_callback=None,
) -> dict[str, Any]:
    inputs = {
        "requirement": requirement,
        "generated_assertion": generated_assertion,
        "reference_assertion": reference_assertion,
        "design_context": design_context,
        "formal_feedback": formal_feedback,
        "comparison_scope": comparison_scope,
    }
    for name, value in inputs.items():
        if not isinstance(value, str):
            raise TypeError(f"{name} must be a string")
        if name in {"requirement", "generated_assertion", "reference_assertion"}:
            if not value.strip():
                raise ValueError(f"{name} must not be empty")

    state = {
        "background": (
            "The generated assertion has not been accepted by the experiment. "
            "PEC may have returned a mismatch, or its compilation may have failed "
            "without an equivalence verdict. A checker compilation failure alone "
            "does not establish any defect in the generated assertion. "
            "Diagnose it using the formal feedback and the supplied comparison_scope. "
            "The supplied comparison_scope determines which assertion parts PEC compares. "
            "Keep the complete assertion valid, but do not infer that PEC checked excluded wrappers. "
            "Use testbench definitions to recognize equivalent reset aliases. "
            "A textual reset difference alone does not require a correction. "
            "Identify the changes needed to fix it using the requirement and "
            "the known-correct reference assertion. Do not recheck whether the "
            "whole assertion has an error. An unaccepted assertion can still contain "
            "correct operators; recommend only changes required by the behavior. "
            "Different syntax can express the same behavior. "
            "For each repair question, answer yes only when that change is needed. "
            "Answer no when it is not needed or the question does not apply. "
            "Each question is independent; related repair questions may both be yes. "
            "Judge Noul repair questions as yes/no decisions, with uncertainty near 0.5; "
            "Choice questions classify the supplied alternatives. General examples "
            "illustrate distinctions, not edits to copy into this case. "
            "Use the reference to establish the benchmark target when prose is ambiguous. "
            "Use the supplied design and tool context."
            " Inspect the testbench or module interface to clarify signal meanings, widths, "
            "parameters and relationships. If the requirement omits information needed to "
            "express its intended behavior, consider additional declared signals supported "
            "by that context. Do not add signals or conditions merely because they are "
            "available, and do not invent undeclared signals."
        ),
        **inputs,
    }

    # Noul questions ask about a specific change, not overall correctness.
    # Choice questions show their options directly beside the question.
    question_groups = {
        # 1. Implication
        "implication": {
            "presence": Choice(
                instructions="Where are implication operators (|->, |=>) used?",
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
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
                instructions="Where are logical operators (!, &&, ||) used?",
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
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
                instructions="Where are comparison operators (==, !=, ===, !==, <, <=, >, >=) used?",
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
                },
            ),
            "replace_operator": Noul(
                instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a comparison operator (==, !=, ===, !==, <, <=, >, >=).",
            ),
            "insert_operator": Noul(
                instructions="Should a comparison operator be inserted to express a missing operation?",
            ),
            "remove_operator": Noul(
                instructions="Should an unnecessary operator in this category be removed? This question concerns a comparison operator (==, !=, ===, !==, <, <=, >, >=).",
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
                instructions="Where are bitwise operators (binary &, |, ^, ~^, ^~, unary ~) used?",
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
                },
            ),
            "replace_operator": Noul(
                instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a bitwise operator (binary &, |, ^, ~^, ^~, or unary ~).",
            ),
            "insert_operator": Noul(
                instructions="Should a bitwise operator be inserted to express a missing operation?",
            ),
            "remove_operator": Noul(
                instructions="Should an unnecessary operator in this category be removed? This question concerns a bitwise operator (binary &, |, ^, ~^, ^~, or unary ~).",
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
                instructions="Where are unary reduction operators (&, |, ^, ~&, ~|, ~^, ^~) used?",
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
                },
            ),
            "replace_operator": Noul(
                instructions="Should an existing operator in this category be replaced with a different operator? This question concerns a unary reduction operator (&, |, ^, ~&, ~|, ~^, or ^~).",
            ),
            "insert_operator": Noul(
                instructions="Should a reduction operator be inserted to express a missing operation?",
            ),
            "remove_operator": Noul(
                instructions="Should an unnecessary operator in this category be removed? This question concerns a unary reduction operator (&, |, ^, ~&, ~|, ~^, or ^~).",
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
                    "Where are ## delays and sampled-value functions "
                    "($past, $rose, $fell, $stable, $changed) used? "
                    "Exclude |-> and |=> from this presence question; their timing "
                    "is assessed separately by temporal_implication_timing."
                ),
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
                },
            ),
            "implication_timing": Noul(
                instructions={
                    "background": (
                        "This question concerns the start time of an existing implication's "
                        "consequent: a |-> b starts b at the antecedent's endpoint, while "
                        "a |=> b starts it one clock later. For a sequence antecedent, use "
                        "its endpoint, not its first cycle. Account for explicit ## delays "
                        "and sampled-value functions; different spellings may be equivalent."
                    ),
                    "question": (
                        "Should an existing |-> be changed to |=>, or vice versa, to "
                        "correct same-cycle versus next-cycle timing? Answer no if the "
                        "complete timing already matches the reference or if the needed "
                        "repair is only insertion/removal of implication or a ## delay."
                    ),
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
                    "Where are expression-grouping parentheses used? Exclude "
                    "assert property wrappers, clock events, and function-call delimiters."
                ),
                criteria={
                    "reference_only": "Only in the reference assertion.",
                    "generated_only": "Only in the generated assertion.",
                    "both": "In both assertions.",
                    "neither": "In neither assertion.",
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

        # Global: behavioral repairs across operator categories, plus operator counts.
        "global": {
            "signal_identity": Noul(
                instructions={
                    "background": (
                        "Signal identity means selecting the intended declared signal at "
                        "an operand, independently of the surrounding operator. For example, "
                        "a data comparison may use another channel's data signal instead "
                        "of the intended channel's data. Equivalent aliases are not errors. "
                        "Check original testbench declarations: a missing declaration only "
                        "in PEC's generated stub does not justify renaming a valid signal."
                    ),
                    "question": (
                        "Should a signal identifier in the generated assertion be replaced "
                        "because it names the wrong signal for the required behavior?"
                    ),
                },
            ),
            "signal_role": Noul(
                instructions={
                    "background": (
                        "Signal role means the information a signal represents: request "
                        "versus accepted transaction, current value versus registered "
                        "snapshot, raw input versus derived tracker, or observed data versus "
                        "model output. Similar names or widths do not establish equal roles. "
                        "Use testbench definitions and the reference to determine the role."
                    ),
                    "question": (
                        "Should an operand be changed to a signal or subexpression with "
                        "the correct behavioral role, because the current operand "
                        "represents a different event, state, data source or time snapshot?"
                    ),
                },
            ),
            "missing_behavioral_branch": Noul(
                instructions={
                    "background": (
                        "A behavioral branch is a required scenario with its own obligation, "
                        "not merely an extra Boolean operator. For example, a read may need "
                        "stored-data comparison when nonempty and incoming-write-data "
                        "comparison for an empty simultaneous transfer. Checking one path "
                        "does not cover the other. Adding == 1'b1 alone does not create a "
                        "missing scenario. A branch may be encoded without explicit if/else."
                    ),
                    "question": (
                        "Should a missing scenario and its required check be added because "
                        "the generated assertion omits an entire behavioral branch covered "
                        "by the reference? Distinguish a missing branch from a wrong or "
                        "missing guard on an obligation that is already represented."
                    ),
                },
            ),
            "wrong_applicability_condition": Noul(
                instructions={
                    "background": (
                        "An applicability condition determines when an existing obligation "
                        "must hold. A wrong existing guard can enable the wrong mode or "
                        "exempt a required scenario. For example, last_grant != 0 checks "
                        "later arbitration rather than first arbitration, or an extra "
                        "no-write guard may incorrectly exempt simultaneous transactions."
                    ),
                    "question": (
                        "Should an existing applicability guard be replaced, removed, "
                        "repolarized or regrouped because it checks the wrong situations "
                        "for an otherwise represented obligation? Do not classify a wholly "
                        "absent qualification as a wrong existing guard."
                    ),
                },
            ),
            "missing_applicability_condition": Noul(
                instructions={
                    "background": (
                        "A missing applicability condition is an absent qualification on "
                        "an already represented obligation. For example, an operation-specific "
                        "data check may require an accepted-transaction guard that is absent. "
                        "This differs from replacing an incorrect existing guard or adding "
                        "a separate scenario with a different obligation."
                    ),
                    "question": (
                        "Should a missing applicability condition be inserted so an "
                        "existing check is enforced under the required circumstances, "
                        "rather than applying without a necessary qualification?"
                    ),
                },
            ),
            "any_vs_all": Noul(
                instructions={
                    "background": (
                        "This question concerns existential versus universal coverage of "
                        "the intended bits or members, regardless of syntax. For a multi-bit "
                        "vector, |v asks whether any bit is one, while &v asks whether every "
                        "bit is one. All-ones comparisons and member-wise conditions can "
                        "express the same distinction. Check actual width and X/Z behavior; "
                        "any and all coincide on a one-bit vector. Wrong vector/range "
                        "selection is assessed separately by operand/coverage questions."
                    ),
                    "question": (
                        "Should the generated assertion change from requiring any member "
                        "to requiring all members, or vice versa, over the intended set "
                        "to match the reference's required behavior?"
                    ),
                },
            ),
            "required_vs_forbidden_condition": Noul(
                instructions={
                    "background": (
                        "A property can require a success condition or reject a violation "
                        "condition. For example, ok === 1'b1 requires definitely true ok, "
                        "whereas bad !== 1'b1 rejects definitely true bad. Negation, ordinary "
                        "equality and case equality are not interchangeable for X/Z values. "
                        "Changing == to === alone concerns comparison_four_state_equality; "
                        "here judge the intended meaning and polarity of the whole check."
                    ),
                    "question": (
                        "Should the assertion's truth requirement or failure polarity be "
                        "changed because it requires a violation, forbids a valid condition, "
                        "or otherwise confuses a required condition with a forbidden one? "
                        "Judge behavior, not a preference for either assertion style."
                    ),
                },
            ),
            "cosmetic_vs_semantic": Choice(
                instructions=(
                    "Classify differences within comparison_scope using the reference "
                    "and design context. Redundant parentheses, whitespace, and demonstrably "
                    "equivalent rewrites do not change behavior. If both cosmetic and "
                    "behavioral differences exist, select semantic_difference. Do not "
                    "classify an assertion as semantically wrong solely because PEC "
                    "compilation failed; choose uncertain when behavior cannot be established."
                ),
                criteria={
                    "no_difference": "No differences are identified within comparison_scope.",
                    "cosmetic_only": "Differences are textual or behavior-preserving only; no semantic repair is supported.",
                    "semantic_difference": "At least one difference changes required behavior, with or without cosmetic differences.",
                    "uncertain": "The available context does not establish whether differences change behavior.",
                },
            ),
            "operator_category_error_count": Choice(
                instructions=(
                    "How many operator categories need correction? Count implication, "
                    "logical, comparison, bitwise excluding shifts, reduction, and "
                    "temporal limited to delays and sampled-value functions. "
                    "Count each category once even if it has several wrong, missing, "
                    "or extra operators. A replacement between categories affects "
                    "both categories. A |-> versus |=> timing repair counts as implication, "
                    "not as a second temporal category. Count behavioral repairs only "
                    "when they require these operator changes. Exclude parentheses "
                    "and equivalent rewrites."
                ),
                criteria={
                    "zero": "0 categories.",
                    "one": "1 category.",
                    "two_or_three": "2 or 3 categories.",
                    "more_than_three": "More than 3 categories.",
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
                    "Count |-> versus |=> as one implication occurrence edit. "
                    "Exclude parentheses and equivalent rewrites."
                ),
                criteria={
                    "zero": "0 operator occurrences.",
                    "one": "1 operator occurrence.",
                    "two_or_three": "2 or 3 operator occurrences.",
                    "more_than_three": "More than 3 operator occurrences.",
                },
            ),
        },
    }

    # Build unique IDs once and use those same IDs throughout the pipeline.
    questions = {}
    question_definitions = {}
    question_group_names = {}

    for group, group_questions in question_groups.items():
        names = []

        for name, question in group_questions.items():
            question_id = f"{group}_{name}"
            instructions = question.instructions
            question = question.model_copy(update={"instructions": {
                "question_type": "yes/no repair (Noul)" if isinstance(question, Noul) else "classification (Choice)",
                "category": group,
                **(instructions if isinstance(instructions, dict) else {"question": instructions}),
            }})
            questions[question_id] = question
            question_definitions[question_id] = question.model_dump(
                mode="json", exclude_none=True
            )
            names.append(question_id)

        question_group_names[group] = names

    request = {"state": state, "questions": questions}
    if model is not None:
        request["model"] = model
    if client is None:
        with TypeSafeClient() as owned_client:
            response = owned_client.system_one(**request)
    else:
        response = client.system_one(**request)
    if usage_callback is not None:
        usage_callback(getattr(response, "usage", None))
    if set(response.answers) != set(questions):
        raise RuntimeError("Jev response question names do not match the request")

    # Store the raw answer and the processed answer under the same question ID.
    raw_answers = {}
    answers = {}

    for question_name, answer_object in response.answers.items():
        result = answer_object.model_dump(mode="json")
        raw_answers[question_name] = result

        if result["type"] == "noul":
            p = result["noul"]
            answers[question_name] = {
                "answer": p > 0.5,
                "confidence": round(abs(2 * p - 1), 12),
            }
        elif result["type"] == "choice":
            answers[question_name] = {
                "answer": result["choice"],
                "confidence": result["confidence"],
            }
        else:
            raise ValueError(f"Unsupported Jev answer type: {result['type']}")

    return {
        "state": state,
        "question_groups": question_group_names,
        "questions": question_definitions,
        "answers": answers,
        "raw_answers": raw_answers,
        "model": response.model,
    }
