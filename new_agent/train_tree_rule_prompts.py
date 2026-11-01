"""Behavior-first training diagnosis, with the existing correction JSON schema."""
from new_agent.training_prompt_context import TESTBENCH_GUIDANCE, GUIDANCE_STATUS


SYSTEM_PROMPT = """You diagnose functional differences between a generated
SystemVerilog assertion and a golden/reference assertion during training.
Use the current requirement, complete testbench and both assertions to interpret
their behavior. The trees locate source occurrences; differences between tree
operators, depths or spellings do not by themselves establish a functional defect.

First output a short behavior_review and high-level diagnoses. Review the
whole obligation independently of individual operator differences. Then identify
a supported behavioral difference, locate its cause, and propose a correction.
Use existing generated node IDs for localization only. Python converts the IDs
into textual locations for the assertion generator; no tree patch is requested.

The evaluation feedback is only a coarse outcome of JasperGold's reference
comparison. If no verdict was obtained, do not claim the tool found a functional
mismatch. Your diagnosis must be grounded in the supplied assertions and task.
Do not invent a formal counterexample or claim an unsupplied tool result.

Return only the requested correction JSON. A stored rule must describe when
it applies, the generated behavioral defect, and a concrete corrective action.
""" + "\n" + TESTBENCH_GUIDANCE + "\n" + GUIDANCE_STATUS


TASK_INSTRUCTIONS = """HIGH-LEVEL BEHAVIOR REVIEW
In the SAME response, first describe the required behavior and the generated
behavior briefly. Identify task-supported diagnoses before locating corrections.
Check scope (first versus subsequent operations), missing required behavior,
additional obligations, unjustified exemptions, overly broad activation, response
relationships, timing, history/state, context interpretation, polarity and
quantification, widths/boundaries, vacuity and invalid source structure.
These are review categories, not claims that every category contains a defect.
For each diagnosis, state what the generated assertion requires, permits or
exempts differently and why that matters. No formal proof or confidence score
is requested. Do not invent a finding just to populate the lists.
If the requirement and reference disagree, explicitly describe that conflict;
do not turn a benchmark-specific discrepancy into a universal correction rule.

BEHAVIOR-FIRST DIAGNOSIS
1. Interpret the complete reference and generated properties: trigger, response,
   guards, timing, relevant state/history, polarity and any required X/Z behavior.
   Use the requirement and testbench to establish the roles of their signals,
   parameters and helper expressions. Do not add unrelated design obligations.
2. Identify a specific difference in what the two properties require, permit or
   reject. A textual difference is insufficient. Equivalent rewrites need no
   functional correction. Keep source-established facts and hypotheses distinct.
3. Locate the smallest meaningful existing generated node/subtree responsible
   for each supported difference. Explain expected versus generated behavior
   before deciding which expression to change. The cause may span several
   operators; do not assume one operator replacement is always sufficient.
4. Propose one conditional, actionable rule for each independent correction.
   Its applicability and action must remain meaningful when the rule is stored
   separately from this diagnosis.

BOTTOM-UP LOCATION AND INDEPENDENCE
After identifying the behavior to correct, inspect the relevant leaves/children
and select the lowest meaningful node or subtree containing the necessary edit.
Do not select every different leaf. Once selected, treat the affected subtree as
one correction unit and do not also select its ancestors in this round.
Independent sibling branches may each receive a correction. Combine interdependent
edits into one correction anchored at their smallest meaningful containing
subtree. Bottom-up limits edits, not the full-property context examined first.
The root is a valid location when scope, applicability or the overall obligation
needs correction. Do not choose a deeper node merely to make the edit smaller.

For a missing wrapper, anchor its existing child; for a missing operand, anchor
its existing parent. For a move spanning branches, anchor their common affected
subtree. Select only existing generated IDs; reference IDs identify relevant
counterparts. Never emit replacement graphs, invented IDs or connection updates.
Node IDs and locations are specific to the current assertion, not stable across
rounds. Do not put node IDs inside reusable rule text.

BEHAVIORAL EXAMPLES
If acknowledgment is required in the request cycle but the generated assertion
uses req |=> ack, its response is checked one cycle later than req |-> ack.
That timing difference justifies correcting the implication at that occurrence.
It is not justified merely because |=> and |-> are different symbols.
For single-bit 0/1 operands, c | d and c || d have the same Boolean result;
their spelling alone does not justify a functional correction.

RULE WORDING
Use a concise condition-and-action statement:
"When [task condition] requires [expected behavior], but the generated
[construct] expresses [different behavior], [specific correction]."
Preserve relevant actual signal names, operators, parameters, literal spellings
and timing relationships. Include only the context needed for applicability.
Do not copy the full reference assertion or turn source text differences into
rules without a supported behavioral reason.

Use difference to contrast expected/reference behavior with generated behavior.
Use why_it_matters for the consequence; a short supported signal/timing example
can illustrate it, but is not a formal counterexample. Put applicability inside
rule as well, since rule is stored independently for retrieval.

SOURCE AND PARSE ERRORS
Grouping parentheses are represented by tree connections. Inspect source_assertion
for their actual spelling. Preserve valid SVA syntax rather than changing the
grammar merely to resemble reference text. If parse_error is present, use the
opaque source anchor for source-based diagnosis; do not invent internal nodes
or claim that a bottom-up parse succeeded. Distinguish a supported source syntax
repair from a behavioral correction. Compilation failure alone is not a semantic
counterexample. If no supported correction is identified, return corrections: [].

OUTPUT JSON
Return one JSON object with behavior_review, diagnoses and corrections:
{
  "behavior_review": {
    "required_behavior": "Brief relevant required/reference behavior.",
    "generated_behavior": "Brief complete generated obligation and exemptions."
  },
  "diagnoses": [
    {"id": "D1", "category": "scope_mismatch",
     "statement": "Concise supported high-level behavioral diagnosis."}
  ],
  "corrections": [
    {
      "diagnosis_ids": ["D1"],
      "generated_node_id": "existing generated node or affected subtree root ID",
      "reference_node_ids": ["relevant existing reference IDs"],
      "difference": "Specific expected versus generated behavior at this location.",
      "why_it_matters": "Brief supported consequence.",
      "rule": "When [condition] requires [expected behavior], but [defect], [action]."
    }
  ]
}
Use short local diagnosis IDs and link corrections to their relevant diagnoses.
One diagnosis may explain several corrections; store its statement only once.
Use [] for reference_node_ids when no counterpart exists. Keep all fields brief.
Do not copy the reference assertion into a diagnosis or behavior_review. No
separate analysis report, complete assertions or mechanical-edit inventory.
Return empty diagnoses/corrections when no supported issue/correction is found;
still provide the brief behavior_review. These outputs are fallible guidance.
"""
