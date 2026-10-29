"""Run training or inference using the settings in new_agent/config.py."""

from functools import partial
from math import isfinite
import os
from pathlib import Path
import sys
from time import perf_counter
from tempfile import TemporaryDirectory

# Support both python new_agent/main.py and python -m new_agent.main.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from new_agent import config, dataset_loader, formal_check, run_io
from new_agent.pipeline import run_pipeline


def select_workflow():
    """Keep inference on the original pipeline; route training to tree rules."""
    if config.MODE == "train":
        from new_agent.train_tree_pipeline import run_training_pipeline
        return run_training_pipeline
    return run_pipeline


def validate_config() -> None:
    """Check active settings once, before creating a run or making API calls."""
    if config.MODE not in {"train", "inference"}:
        raise ValueError('MODE must be "train" or "inference".')
    if config.MODE == "inference":
        if type(config.TOP_K_CASES) is not int or config.TOP_K_CASES < 1:
            raise ValueError("TOP_K_CASES must be a positive integer.")
        if not isinstance(config.EMBEDDING_MODEL, str) or not config.EMBEDDING_MODEL.strip():
            raise ValueError("EMBEDDING_MODEL must be a nonempty model name.")
    if not isinstance(config.DATASET, str) or not config.DATASET.strip():
        raise ValueError("DATASET must be a nonempty dataset name.")
    if config.DATASET not in {"nl2sva_human", "nl2sva_machine", "nl2sva_opencore"}:
        raise ValueError("DATASET must be 'nl2sva_human', 'nl2sva_machine', or 'nl2sva_opencore'.")
    if type(config.MAX_ROUNDS) is not int or config.MAX_ROUNDS < 1:
        raise ValueError("MAX_ROUNDS must be a positive integer.")
    for name in ("ASSERTION_MODEL", "RULE_MODEL"):
        value = getattr(config, name)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{name} must be a nonempty model name.")
    timeout = config.JASPER_TIMEOUT_SECONDS
    if type(timeout) not in (int, float) or not isfinite(timeout) or timeout <= 0:
        raise ValueError("JASPER_TIMEOUT_SECONDS must be a finite positive number.")
    confidence = config.CONFIDENCE_THRESHOLD
    if (
        type(confidence) not in (int, float)
        or not isfinite(confidence)
        or not 0 <= confidence <= 1
    ):
        raise ValueError("CONFIDENCE_THRESHOLD must be a number between 0 and 1.")
    if type(config.SAVE_DEBUG_TRACES) is not bool:
        raise ValueError("SAVE_DEBUG_TRACES must be True or False.")
    formal_check.validate_backend()


def validate_credentials() -> None:
    """Reject absent credentials before paying for assertion-generation calls."""
    required = ["OPENAI_API_KEY"]
    if config.MODE == "inference" and config.MAX_ROUNDS > 1:
        required.append("TYPESAFE_API_KEY")
    missing = [name for name in required if not os.environ.get(name, "").strip()]
    if missing:
        raise ValueError("Missing environment variables: " + ", ".join(missing)
                         + ". Set them in this shell before starting the experiment.")


def main() -> int:
    """Resolve the source/selection once, then run independent case loops."""
    experiment_started = perf_counter()
    # 1. Validate the configuration, CSV, and complete selection before any API call.
    validate_config()
    validate_credentials()
    policy = formal_check.get_evaluation_policy(config.DATASET)
    phase = "train" if config.MODE == "train" else "infer"
    source_dir = source_metadata = retriever = None
    dataset_split = None
    if phase == "train":
        cases, dataset_split = dataset_loader.load_training_cases(
            config.DATASET_PATH, config.TRAIN_CASE_IDS,
            train_fraction=config.TRAIN_FRACTION, split_seed=config.SPLIT_SEED,
        )
    else:
        dataset_path = dataset_loader.resolve_dataset_path(config.DATASET_PATH)
        source_dir, source_metadata = run_io.select_training_run(
            dataset=config.DATASET, dataset_path=dataset_path,
            runs_root=config.RUNS_DIR, training_run_dir=config.TRAINING_RUN_DIR,
        )
        cases = dataset_loader.load_inference_cases(
            dataset_path, source_metadata,
        )
        print("Training source:", source_dir, flush=True)
        print("Inference selection: all dataset cases excluding the source training selection.", flush=True)
        print("Training case IDs excluded:", [c["case_number"] for c in source_metadata["selected_cases"]], flush=True)
        print(f"Automatically selected inference case IDs ({len(cases)}):",
              [case["case_number"] for case in cases], flush=True)
        from new_agent.infer_retrieval import RuleRetriever
        training_ids = {c["case_number"] for c in source_metadata["selected_cases"]}
        retriever = RuleRetriever(
            source_dir, training_case_ids=training_ids,
            training_cases=dataset_loader.load_cases(dataset_path, sorted(training_ids)),
            top_k=config.TOP_K_CASES, model_name=config.EMBEDDING_MODEL,
        )
    dataset_path = Path(cases[0]["dataset_path"])
    models = {"assertion": config.ASSERTION_MODEL, "rule": config.RULE_MODEL}
    settings = {
        "phase": phase,
        "mode": config.MODE,
        "dataset": config.DATASET,
        "dataset_path": str(dataset_path),
        "checker": "same_repo_fvrulelearner_evaluation",
        "evaluator_repo_dir": str(formal_check.REPO_ROOT),
        "evaluator_python": sys.executable,
        "metric_source": "native evaluation.py; original_setting=False",
        "checker_input_policy": "native_per_round",
        "comparison_scope": policy["scope"],
        "revision_rules": "previous_round_only",
        "round_policy": "pec_or_bleu_or_max_rounds",
        "pec_compile_error_policy": "continue_retrieved_rule_diagnosis_and_guidance" if phase == "infer" else "continue_reference_diagnosis_and_rule_generation",
        "case_ids": ([case["case_number"] for case in cases]
                     if phase == "infer" else list(config.TRAIN_CASE_IDS)),
        "dataset_split": dataset_split,
        "max_rounds": config.MAX_ROUNDS,
        "timeout_seconds": config.JASPER_TIMEOUT_SECONDS,
        "confidence_threshold": config.CONFIDENCE_THRESHOLD,
        "runs_dir": str(config.RUNS_DIR),
        "save_debug_traces": config.SAVE_DEBUG_TRACES,
    }

    if phase == "train":
        settings.update(training_workflow="assertion_pec_tree_llm_rules",
                        flat_training_output=True,
                        tree_parser="raw-tree-prototype-1.2",
                        tree_parse_failure_policy="explicit_opaque_source_anchor",
                        training_diagnosis_model=config.RULE_MODEL,
                        training_rule_schema="bottom_up_corrections_v2",
                        training_feedback="complete_latest_response_only")

    if phase == "infer":
        settings.update(
            source_training_run=str(source_dir),
            inference_case_selection="all_dataset_cases_minus_source_selected_cases",
            training_case_ids=[c["case_number"] for c in source_metadata["selected_cases"]],
            retrieval_top_k=config.TOP_K_CASES, embedding_model=config.EMBEDDING_MODEL,
            retrieval_eligible_cases=len(retriever.cases),
            example_retrieval="top_three_training_requirements_by_cosine",
            example_pool_size=len(retriever.examples),
            source_rules_sha256=retriever.sha256,
        )

    # 2. Create one experiment containing shared summaries and separate case folders.
    experiment_dir = run_io.create_experiment(
        dataset=config.DATASET, dataset_path=dataset_path, cases=cases,
        models=models, settings=settings, runs_root=config.RUNS_DIR,
        phase=phase, source_training_run=source_dir,
    )
    print("Dataset:", dataset_path)
    print("Evaluation scope:", policy["scope"])
    if phase == "infer":
        print("Retrieval cases with rules:", len(retriever.cases) if retriever is not None else 0)
    elif dataset_split is not None:
        print(
            f"Random split: {len(cases)} training | "
            f"{len(dataset_split['inference_case_ids'])} reserved for inference | "
            f"seed {dataset_split['seed']}"
        )
    else:
        print("Explicit case selection: random splitting is not applied.")
    if phase == "train":
        print("Selected case IDs:", [case["case_number"] for case in cases])
    print("Experiment:", experiment_dir)

    # 3. Run each selected case with its own revision loop and rule registry.
    # Native Saver/metrics initialization requires a writable directory at
    # runtime. Keep it outside the experiment and discard it after this batch.
    # To restore persistent native_logs, import nullcontext from contextlib and
    # replace TemporaryDirectory with nullcontext(str(experiment_dir / "native_logs")).
    with TemporaryDirectory(prefix="fv_native_logs_", ignore_cleanup_errors=True) as native_log_dir:
        exit_code = 0
        try:
            # Import native dependencies and load metrics before making model calls.
            # Persistent initializer diagnostics disabled:
            # formal_check.initialize_evaluator(experiment_dir / "native_logs", config.DATASET, config.JASPER_TIMEOUT_SECONDS)
            formal_check.initialize_evaluator(
                Path(native_log_dir), config.DATASET, config.JASPER_TIMEOUT_SECONDS,
            )
            for position, case in enumerate(cases, start=1):
                print(
                    f"\nRunning {position}/{len(cases)}: case {case['case_number']} | "
                    f"{case['design_name']} / {case['task_id']}"
                )
                case_exit = run_io.run_experiment(
                    workflow=partial(select_workflow(), retriever=retriever),
                    cleanup_work=formal_check.cleanup_work,
                    case_id=case["task_id"],
                    case_dir=(experiment_dir if phase == "train" else
                              experiment_dir / "cases" / f"case_{case['case_number']:04d}"),
                    summary_dir=experiment_dir,
                    models=models,
                    inputs={**case, "dataset": config.DATASET},
                    prompts={},
                    settings=settings,
                )
                if case_exit == 130:
                    exit_code = 130
                    break
                if case_exit != 0:
                    exit_code = 1  # Record the case error; continue to the next selected case.
        except KeyboardInterrupt:
            exit_code = 130
        except Exception:
            exit_code = 1
            raise
        finally:
            exit_code = run_io.finish_experiment(
                experiment_dir, exit_code,
                elapsed_seconds=perf_counter() - experiment_started,
            )

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
