#!/usr/bin/env python3
"""Prepare FVRuleLearner for a reproducible GPT-4o experiment.

The script is intentionally conservative: every edit is guarded by an exact
source-pattern check, and a second invocation is a no-op. Run it from anywhere
inside the repository with:

    python3 scripts/prepare_gpt4o_reproduction.py

The resulting runtime defaults target the full NL2SVA-Machine training run.
They can be overridden without editing config.py; see the environment variables
printed at the end of the script.
"""

from __future__ import annotations

import argparse
import py_compile
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def replace_guarded(path: Path, old: str, new: str, label: str) -> str:
    text = path.read_text(encoding="utf-8")
    if new in text:
        print(f"[skip] {label}")
        return text
    if old not in text:
        raise RuntimeError(
            f"Cannot apply '{label}': expected source pattern was not found in {path}"
        )
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print(f"[done] {label}")
    return text


def patch_config() -> None:
    path = REPO_ROOT / "src" / "config.py"

    replace_guarded(
        path,
        """# Select one execution stage: train / inference / eval.
# global_task = 'inference'
global_task = 'train'
# global_task = 'eval'
""",
        """# Select one execution stage: train / inference / eval.
# Override without editing this file: FVRULELEARNER_STAGE=train|inference|eval
global_task = os.environ.get("FVRULELEARNER_STAGE", "train").strip().lower()
if global_task not in {"train", "inference", "eval"}:
    raise ValueError(f"Unsupported FVRULELEARNER_STAGE: {global_task}")
""",
        "environment-selectable execution stage",
    )
    replace_guarded(
        path,
        """# debug = False
debug = True
""",
        """# Full reproduction defaults to non-debug mode.
# Set FVRULELEARNER_DEBUG=1 for a one-case smoke test.
debug = os.environ.get("FVRULELEARNER_DEBUG", "0").strip().lower() in {
    "1", "true", "yes", "on"
}
""",
        "production debug default",
    )
    replace_guarded(
        path,
        "training_cases = [0,1,2,3]",
        "training_cases = []",
        "remove debug-only training case restriction",
    )
    replace_guarded(
        path,
        """# Supported release tasks:
# task = "nl2sva_human"
task = "nl2sva_machine"
# task = "nl2sva_opencore"
""",
        """# Supported release tasks. Override with FVRULELEARNER_TASK.
task = os.environ.get("FVRULELEARNER_TASK", "nl2sva_machine").strip()
""",
        "environment-selectable benchmark task",
    )
    replace_guarded(
        path,
        "llm_model = 'gpt-4o'",
        "llm_model = os.environ.get(\n    \"FVRULELEARNER_MODEL\", \"gpt-4o-2024-11-20\"\n).strip()",
        "fixed GPT-4o snapshot default",
    )
    replace_guarded(
        path,
        """    max_token = 20000
    # Optional dataset partitioning for batched local runs.
    group_id = 0
    num_group = 1
    start_num = 0
""",
        """    max_token = min(
        int(os.environ.get("FVRULELEARNER_MAX_TOKENS", "16384")),
        16384,
    )
    # Optional dataset partitioning for batched local runs.
    group_id = int(os.environ.get("FVRULELEARNER_GROUP_ID", "0"))
    num_group = int(os.environ.get("FVRULELEARNER_NUM_GROUPS", "1"))
    start_num = int(os.environ.get("FVRULELEARNER_START_NUM", "0"))
""",
        "reproducible token and partition settings",
    )
    replace_guarded(
        path,
        "    random_seed = 100",
        "    random_seed = int(os.environ.get(\"FVRULELEARNER_SEED\", \"100\"))",
        "environment-selectable random seed",
    )
    replace_guarded(
        path,
        """        # Number of self-improvement iterations per training sample.
        num_iter = 2
""",
        """        # Maximum number of fixing iterations after the initial SVA.
        num_iter = int(os.environ.get("FVRULELEARNER_NUM_ITER", "25"))
""",
        "25-round full training default",
    )
    replace_guarded(
        path,
        """        if debug == True:
            num_iter = 2
""",
        """        if debug == True:
            num_iter = min(num_iter, 2)
""",
        "debug iteration cap",
    )
    replace_guarded(
        path,
        """    nparallel = 1
    if debug == True:
        nparallel = 1
""",
        """    nparallel = int(os.environ.get("FVRULELEARNER_NPARALLEL", "1"))
    jg_timeout_seconds = int(
        os.environ.get("FVRULELEARNER_JG_TIMEOUT_SECONDS", "300")
    )
    if debug == True:
        nparallel = 1
""",
        "configurable JasperGold timeout",
    )


def patch_model_routing() -> None:
    path = REPO_ROOT / "FVEval" / "fv_eval" / "benchmark_launcher.py"
    replace_guarded(
        path,
        """                elif model_name == "gpt-4o-20241120":
                    full_model_name = 'gpt-4o-20241120'
                    model_name = "gpt-4o"
                elif model_name == "gpt-4o":
                    full_model_name = 'gpt-4o-20241120'
                    model_name = "gpt-4o"
""",
        """                elif model_name == "gpt-4o-2024-11-20":
                    full_model_name = "gpt-4o-2024-11-20"
                elif model_name == "gpt-4o":
                    full_model_name = "gpt-4o"
""",
        "correct GPT-4o snapshot routing",
    )


def patch_openai_output_limit() -> None:
    path = REPO_ROOT / "src" / "utils_agent.py"
    replace_guarded(
        path,
        """    create_kwargs = {
        "model": effective_model,
        "messages": messages,
    }
""",
        """    create_kwargs = {
        "model": effective_model,
        "messages": messages,
        "max_tokens": min(getattr(FLAGS, "max_token", 16384), 16384),
    }
""",
        "apply configured OpenAI output limit",
    )


def patch_jaspergold_execution() -> None:
    path = REPO_ROOT / "FVEval" / "fv_eval" / "fv_tool_execution.py"
    replace_guarded(
        path,
        """    # Lily0921: Setting the time limit to 60 seconds
    try:
        # Add 300 second (5 minute) timeout for JasperGold execution
        result = subprocess.run(jg_command, cwd=FVEval_dir, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print(f"ERROR: JasperGold timed out after 300 seconds for task {task_id}")
        return "TIMEOUT: JasperGold execution exceeded 300 second limit"

    # DEBUG: Print JasperGold execution details, 1019, to debug the JasperGold output
""",
        """    timeout_seconds = getattr(FLAGS, "jg_timeout_seconds", 300)
    try:
        result = subprocess.run(
            jg_command,
            cwd=FVEval_dir,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"JasperGold timed out after {timeout_seconds} seconds "
            f"for task {task_id}"
        ) from exc

    jasper_output = "\\n".join(
        part
        for part in (result.stdout.strip(), result.stderr.strip())
        if part
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"JasperGold failed for task {task_id}; "
            f"return code={result.returncode}\\n{jasper_output}"
        )

    # DEBUG: Print JasperGold execution details, 1019, to debug the JasperGold output
""",
        "honest JasperGold timeout and error handling",
    )
    replace_guarded(
        path,
        """    # result = subprocess.run(jg_command, capture_output=True, text=True)
    return result.stdout.strip()
""",
        """    # result = subprocess.run(jg_command, capture_output=True, text=True)
    return jasper_output
""",
        "return JasperGold stdout and stderr",
    )


def patch_training_traces() -> None:
    saver_path = REPO_ROOT / "src" / "saver.py"
    replace_guarded(
        saver_path,
        """    def save_stats(self, stat_name, value):
        self.stats[stat_name].append(value)
""",
        """    def save_training_trace(self, trace):
        \"\"\"Append one case's full self-learning trajectory as JSONL.\"\"\"
        trace_path = join(self.logdir, "training_traces.jsonl")
        with open(trace_path, "a", encoding="utf-8") as trace_file:
            json.dump(trace, trace_file, ensure_ascii=False)
            trace_file.write("\\n")

    def save_stats(self, stat_name, value):
        self.stats[stat_name].append(value)
""",
        "structured per-case training trace writer",
    )

    learning_path = REPO_ROOT / "src" / "self_learning.py"
    replace_guarded(
        learning_path,
        """    record_statistics(iter_cnt, initial_pec, unfixable_indicator, fixable_indicator, final_bleu - initial_bleu, bleu_scores, functionality_scores, syntax_scores)

    # Print the total times for GPT and JasperGold
""",
        """    record_statistics(iter_cnt, initial_pec, unfixable_indicator, fixable_indicator, final_bleu - initial_bleu, bleu_scores, functionality_scores, syntax_scores)

    saver.save_training_trace({
        "task_id": str(getattr(row, "task_id", "")),
        "design_name": str(getattr(row, "design_name", "")),
        "bleu": [float(value) for value in bleu_scores],
        "functionality": [float(value) for value in functionality_scores],
        "relaxed_functionality": [
            float(value) for value in relaxed_functionality_scores
        ],
        "syntax": [float(value) for value in syntax_scores],
        "iterations": max(len(functionality_scores) - 1, 0),
        "initial_functionality": float(initial_pec),
        "final_functionality": float(pec),
        "fixed": bool(fixable_indicator),
    })

    # Print the total times for GPT and JasperGold
""",
        "record each case's 25-round trajectory",
    )


def patch_fixing_loop_correctness() -> None:
    learning_path = REPO_ROOT / "src" / "self_learning.py"
    replace_guarded(
        learning_path,
        """        response_str = initiate_chat_with_retry(agents["user"], agents["Coding"], message=enriched_prompt)
""",
        """        response_str = initiate_chat_with_retry(
            agents["user"],
            agents["Coding"],
            message=enriched_prompt,
            temperature=temperature,
        )
""",
        "apply the configured fixing temperature",
    )
    replace_guarded(
        learning_path,
        """    if last_metrics and (only_bleu or last_bleu == similarity_metrics.get("bleu", 0)):
        return last_metrics
""",
        """    if last_metrics and only_bleu:
        return last_metrics
""",
        "evaluate every generated SVA with JasperGold",
    )

    qtree_path = REPO_ROOT / "src" / "qtree_builder.py"
    replace_guarded(
        qtree_path,
        """            fallback_questions = [
                f"Considering {selected_keyword}, which specific operators are different between the generated and reference assertions?",
                f"Considering {selected_keyword}, are the operators used correctly for the intended behavior?",
                f"Considering {selected_keyword}, what operator changes would fix the assertion?"
            ]
""",
        """            fallback_keyword = (
                selected_keywords[0] if selected_keywords else "operators"
            )
            fallback_questions = [
                f"Considering {fallback_keyword}, which specific operators are different between the generated and reference assertions?",
                f"Considering {fallback_keyword}, are the operators used correctly for the intended behavior?",
                f"Considering {fallback_keyword}, what operator changes would fix the assertion?"
            ]
""",
        "safe Op-Tree fallback questions",
    )


def validate_python() -> None:
    paths = [
        REPO_ROOT / "src" / "config.py",
        REPO_ROOT / "src" / "utils_agent.py",
        REPO_ROOT / "src" / "saver.py",
        REPO_ROOT / "src" / "self_learning.py",
        REPO_ROOT / "src" / "qtree_builder.py",
        REPO_ROOT / "FVEval" / "fv_eval" / "benchmark_launcher.py",
        REPO_ROOT / "FVEval" / "fv_eval" / "fv_tool_execution.py",
    ]
    for path in paths:
        py_compile.compile(str(path), doraise=True)
    print(f"[ok] Python syntax validated for {len(paths)} modified modules")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="validate the already-patched files without modifying them",
    )
    args = parser.parse_args()

    if not args.check_only:
        patch_config()
        patch_model_routing()
        patch_openai_output_limit()
        patch_jaspergold_execution()
        patch_training_traces()
        patch_fixing_loop_correctness()

    validate_python()
    print(
        """
Ready. Full Machine training is now the default.

Smoke test:
  FVRULELEARNER_DEBUG=1 FVRULELEARNER_NUM_ITER=2 python3 src/main.py

Full training:
  FVRULELEARNER_STAGE=train python3 -u src/main.py

Inference after training:
  FVRULELEARNER_STAGE=inference \\
  FVRULELEARNER_TRAIN_LOGDIR=/absolute/path/to/train_log \\
  python3 -u src/main.py

Useful overrides:
  FVRULELEARNER_TASK=nl2sva_machine|nl2sva_human|nl2sva_opencore
  FVRULELEARNER_MODEL=gpt-4o-2024-11-20
  FVRULELEARNER_SEED=100
  FVRULELEARNER_NUM_ITER=25
  FVRULELEARNER_JG_TIMEOUT_SECONDS=300
""".strip()
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
