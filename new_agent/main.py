from jev_assertion_diagnosis import diagnose_assertion_mismatches
from diagnosis_formatter import format_diagnosis

def main():
    #1. Call Jev with the assertion example
    diagnosis = diagnose_assertion_mismatches(
        requirement="Whenever a is high, b must be high on the next clock cycle.",
        generated_assertion="assert property (@(psedge clk) a -> b);",
        reference_assertion="assert property (@(posedge clk) a => b);",
        design_context="a and b are signle-bit signals samples on posedge clk.",
    )
    # Check the actual assertions sent to Jev.
    print("Generated:", diagnosis["state"]["generated_assertion"])
    print("Reference:", diagnosis["state"]["reference_assertion"])

    # Check the two answers before formatting.
    for question_name in (
        "implication_presence",
        "implication_replace_operator",
    ):
        print("Question:", question_name)
        print("Raw answer:", diagnosis["raw_answers"][question_name])
        print("Processed answer:", diagnosis["answers"][question_name])
    
    #2. Get the processed answer, including their confidence values,
    answers = diagnosis["answers"]
    
    #3. Covner retained answers into statements.
    statements = format_diagnosis(answers, confidence_threshold=0.4)
    
    #4. Print each question ad its statement.
    for question_name, statement in statements.items():
        print(f"{question_name}:{statement}")
        
if __name__ == "__main__":
    # Running this file makes one live Jev API call.
    main()