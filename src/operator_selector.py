import config
from typesafe_sdk import Noul, TypeSafeClient


def rank_operator_categories(
    requirement: str,
    generated_sva: str,
    reference_sva: str = "",
    top_k: int = 3,
) -> tuple[list[str], dict[str, float]]:

    state = {
        "background": (
            "The generated SystemVerilog Assertion (SVA) in `generated_sva` "
            "did not pass the JasperGold formal verification check. "
            "The `requirement` is the natural-language question for this case. "
            "Investigate which operator categories may explain the failure."
        ),
        "requirement": requirement,
        "generated_sva": generated_sva,
    }

    if config.oracle:
        state["reference_sva"] = reference_sva
        state["background"] += " The `reference_sva` is the known-correct assertion."
        question_start = (
            "Given the natural-language question in `requirement`, the failed "
            "assertion in `generated_sva`, and the known-correct assertion "
            "in `reference_sva`, should"
        )
    else:
        question_start = (
            "Given the natural-language question in `requirement` and the failed "
            "assertion in `generated_sva`, should"
        )

    questions = {
        "logical_operators": Noul(
            instructions=(
                f"{question_start} logical operators (&&, ||, !) "
                "be investigated as a possible source of incorrect behavior?"
            )
        ),
        "temporal_operators": Noul(
            instructions=(
                f"{question_start} temporal operators such as delays (##), "
                "$past, or $rose "
                "be investigated as a possible source of incorrect behavior?"
            )
        ),
        "comparison_operators": Noul(
            instructions=(
                f"{question_start} comparison operators such as ==, ===, "
                "!=, <, or >= be investigated as a possible source of "
                "incorrect behavior?"
            )
        ),
        "implication_operators": Noul(
            instructions=(
                f"{question_start} implication operators such as overlapping "
                "|-> and nonoverlapping |=> be investigated as a possible "
                "source of incorrect behavior?"
            )
        ),
        "bitwise_operators": Noul(
            instructions=(
                f"{question_start} bitwise or reduction operators such as "
                "&, |, ~, or ^ be investigated as a possible source of "
                "incorrect behavior?"
            )
        ),
    }

    with TypeSafeClient() as client:
        response = client.system_one(
            model="jev-latest",
            state=state,
            questions=questions,
        )

    scores = {}
    for category in questions:
        scores[category] = response.answers[category].noul

    ranking = sorted(scores, key=scores.get, reverse=True)
    return ranking[:top_k], scores


if __name__ == "__main__":
    chosen, values = rank_operator_categories(
        requirement="If req is high, grant must be high on the next clock cycle.",
        generated_sva="assert property (@(posedge clk) req |-> grant);",
        reference_sva="assert property (@(posedge clk) req |=> grant);",
    )

    print("Selected categories:", chosen)
    for category in sorted(values, key=values.get, reverse=True):
        print(f"{category}: {values[category]:.3f}")
