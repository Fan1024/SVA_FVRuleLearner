from openai import OpenAI

import assertion_generator
import counter_example as example

from jev_assertion_diagnosis import diagnose_assertion_mismatches
from diagnosis_formatter import format_diagnosis


MODEL = "gpt-5.6-terra"


def main():
    # 1. Generate an assertion for the fixed counter example.
    user_prompt = assertion_generator.build_generation_prompt(
        requirement=example.REQUIREMENT,
        testbench=example.TESTBENCH,
    )

    client = OpenAI()
    response_text = assertion_generator.generate_assertion(
        client=client,
        model=MODEL,
        user_prompt=user_prompt,
    )
    generated_assertion = assertion_generator.extract_assertion(response_text)

    print("MODEL RESPONSE:")
    print(response_text)

    # 2. Compare the generated assertion with the fixed reference using Jev.
    diagnosis = diagnose_assertion_mismatches(
        requirement=example.REQUIREMENT,
        generated_assertion=generated_assertion,
        reference_assertion=example.REFERENCE_ASSERTION,
        design_context=example.TESTBENCH,
        formal_feedback="No formal verification has been run for this example.",
    )

    print("\nGENERATED ASSERTION SENT TO JEV:")
    print(diagnosis["state"]["generated_assertion"])
    print("\nREFERENCE ASSERTION SENT TO JEV:")
    print(diagnosis["state"]["reference_assertion"])

    for question_name in (
        "implication_presence",
        "implication_replace_operator",
    ):
        print("\nQuestion:", question_name)
        print("Raw answer:", diagnosis["raw_answers"][question_name])
        print("Processed answer:", diagnosis["answers"][question_name])

    # 3. Format the answers using your existing formatter.
    statements = format_diagnosis(
        diagnosis["answers"],
        confidence_threshold=0.4,
    )

    print("\nFORMATTED DIAGNOSIS:")
    for question_name, statement in statements.items():
        print(f"{question_name}: {statement}")


if __name__ == "__main__":
    main()

