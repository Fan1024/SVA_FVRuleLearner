import math

OPERATOR_CATEGORIES = (
    "logical_operators",
    "temporal_operators",
    "comparison_operators",
    "implication_operators",
    "bitwise_operators",
)

def rank_operator_categories(
    requirement: str,
    generated_sva: str,
    reference_sva: str = "",
    top_k: int = 3,
    *,
    oracle: bool = True,
) -> tuple[list[str], dict[str, float]]:
   
    from typesafe_sdk import Noul, TypeSafeClient

    state = {
        "background": (
            "The generated SystemVerilog Assertion (SVA) in generated_sva "
            "is being analyzed after the pipeline's evaluation. "
            "The requirement is the natural-language question for this case. "
            "Investigate which operator categories may explain incorrect behavior."
        ),
        "requirement": requirement,
        "generated_sva": generated_sva,
    }
    if oracle:
        state["reference_sva"] = reference_sva
        state["background"] += " The reference_sva is the known-correct assertion."
        question_start = (
            "Given the requirement, generated_sva, and known-correct "
            "reference_sva, should"
        )
    else:
        question_start = "Given the requirement and generated_sva, should"

    descriptions = {
        "logical_operators": "logical operators (&&, ||, !)",
        "temporal_operators": (
            "temporal operators such as delays (##), $past, or $rose"
        ),
        "comparison_operators": (
            "comparison operators such as ==, ===, !=, <, or >="
        ),
        "implication_operators": (
            "implication operators such as overlapping |-> and nonoverlapping |=>"
        ),
        "bitwise_operators": (
            "bitwise or reduction operators such as &, |, ~, or ^"
        ),
    }
    questions = {
        category: Noul(
            instructions=(
                f"{question_start} {descriptions[category]} "
                "be investigated as a possible source of incorrect behavior?"
            )
        )
        for category in OPERATOR_CATEGORIES
    }

    with TypeSafeClient() as client:
        response = client.system_one(
            model="jev-latest",
            state=state,
            questions=questions,
        )

    scores = {}
    for category in OPERATOR_CATEGORIES:
        score = float(response.answers[category].noul)
        if not math.isfinite(score):
            raise ValueError(f"Invalid Jev score for {category}: {score}")
        scores[category] = score

    # Stable sorting keeps the category order above for tied scores.
    ranking = sorted(OPERATOR_CATEGORIES, key=scores.get, reverse=True)
    return ranking[:top_k], scores


if __name__ == "__main__":
    chosen, values = rank_operator_categories(
        requirement="If req is high, grant must be high on the next clock cycle.",
        generated_sva="assert property (@(posedge clk) req |-> grant);",
        reference_sva="assert property (@(posedge clk) req |=> grant);",
        top_k=3,
        oracle=True,
    )
    print("Selected categories:", chosen)
    for category in sorted(values, key=values.get, reverse=True):
        print(f"{category}: {values[category]:.3f}")

