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
from new_agent import model_gateway
from new_agent.runtime_support import stage_progress


def select_workflow():
    """Select the independent training, retrieval-inference or inference-only loop."""
    if config.MODE == "train":
        from new_agent.train_tree_pipeline import run_training_pipeline
        return run_training_pipeline
    if config.MODE == "inference_only":
        from new_agent.inference_only_pipeline import run_inference_only_pipeline
        return run_inference_only_pipeline
    from new_agent.infer_tree_pipeline import run_inference_pipeline
    return run_inference_pipeline


def validate_config() -> None:
    """Check active settings once, before creating a run or making API calls."""
    if config.MODE not in {"train", "inference", "inference_only"}:
        raise ValueError('MODE must be "train", "inference" or "inference_only".')
    ids = config.CASE_IDS
    if not isinstance(ids, list) or any(type(n) is not int or n < 1 for n in ids) or len(set(ids)) != len(ids):
        raise ValueError("CASE_IDS must be a list of unique positive integers.")
    if config.MODE == "inference":
        if type(config.TOP_K_CASES) is not int or config.TOP_K_CASES < 1:
            raise ValueError("TOP_K_CASES must be a positive integer.")
        if not isinstance(config.EMBEDDING_MODEL, str) or not config.EMBEDDING_MODEL.strip():
            raise ValueError("EMBEDDING_MODEL must be a nonempty model name.")
        for name in ('TOP_K_DIAGNOSES','TOP_K_RULES'):
            if type(getattr(config,name)) is not int or getattr(config,name)<1:
                raise ValueError(name+' must be a positive integer.')
    if config.MODE == "inference_only":
        from new_agent.inference_only_examples import get_examples
        get_examples(config.DATASET)
    if not isinstance(config.DATASET, str) or not config.DATASET.strip():
        raise ValueError("DATASET must be a nonempty dataset name.")
    if config.DATASET not in {"nl2sva_human", "nl2sva_machine", "nl2sva_opencore"}:
        raise ValueError("DATASET must be 'nl2sva_human', 'nl2sva_machine', or 'nl2sva_opencore'.")
    if type(config.MAX_ROUNDS) is not int or config.MAX_ROUNDS < 1:
        raise ValueError("MAX_ROUNDS must be a positive integer.")
    if not isinstance(config.MODEL, str) or not config.MODEL.strip():
        raise ValueError("MODEL must be a nonempty model name.")
    model_gateway.model_settings(config.MODEL)
    model_gateway.validate_runtime((config.MODEL,))
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
    try:
        import pyslang
    except ImportError as error:
        raise RuntimeError('pyslang is required; run python -m pip install -r requirements_new_agent.txt') from error
    formal_check.validate_backend()


def validate_credentials() -> None:
    """Reject absent credentials before paying for assertion-generation calls."""
    required = model_gateway.required_api_keys((config.MODEL,))
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
    phase = {"train": "train", "inference": "infer", "inference_only": "inference_only"}[config.MODE]
    source_dir = source_metadata = retriever = None
    dataset_split = None
    if phase == "train":
        cases, dataset_split = dataset_loader.load_training_cases(
            config.DATASET_PATH, config.CASE_IDS,
            train_fraction=config.TRAIN_FRACTION, split_seed=config.SPLIT_SEED,
        )
    elif phase == "inference_only":
        cases = dataset_loader.load_cases(config.DATASET_PATH, config.CASE_IDS)
    else:
        dataset_path = dataset_loader.resolve_dataset_path(config.DATASET_PATH)
        source_dir, source_metadata = run_io.select_training_run(
            dataset=config.DATASET, dataset_path=dataset_path,
            runs_root=config.RUNS_DIR, training_run_dir=config.TRAINING_RUN_DIR,
        )
        cases = dataset_loader.load_inference_cases(
            dataset_path, source_metadata, config.CASE_IDS,
        )
        from new_agent.infer_retrieval import RuleRetriever, RETRIEVAL_REQUIREMENT_POLICY
        training_ids = {c["case_number"] for c in source_metadata["selected_cases"]}
        retriever = RuleRetriever(
            source_dir, training_case_ids=training_ids,
            training_cases=dataset_loader.load_cases(dataset_path, sorted(training_ids)),
            top_k=config.TOP_K_CASES, model_name=config.EMBEDDING_MODEL,
        )
    dataset_path = Path(cases[0]["dataset_path"])
    models = {"model": config.MODEL}
    from new_agent.pec_context_adapter import context_mode, VERSION as PEC_CONTEXT_VERSION
    from new_agent.diagnosis_context import DIAGNOSIS_CATEGORIES
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
        "pec_context_mode": context_mode(),
        "pec_context_adapter_version": PEC_CONTEXT_VERSION,
        "pec_parameter_policy": "bind_known_integral_tb_parameters_in_both_arguments",
        "comparison_scope": policy["scope"],
        "revision_rules": "previous_round_only",
        "round_policy": "pec_or_bleu_or_max_rounds",
        "pec_compile_error_policy": "block_on_native_pec_compile_failure",
        "case_ids": [case["case_number"] for case in cases],
        "requested_case_ids": list(config.CASE_IDS),
        "dataset_split": dataset_split,
        "max_rounds": config.MAX_ROUNDS,
        "timeout_seconds": config.JASPER_TIMEOUT_SECONDS,
        "confidence_threshold": config.CONFIDENCE_THRESHOLD,
        "runs_dir": str(config.RUNS_DIR),
        "save_debug_traces": config.SAVE_DEBUG_TRACES,
        "diagnosis_categories": list(DIAGNOSIS_CATEGORIES),
        "tree_parser": config.ASSERTION_TREE_PARSER,
        "candidate_syn_policy": "insert_full_candidate_into_native_human_machine_tb",
        "model_gateway_version": model_gateway.VERSION,
        "model_gateway": model_gateway.model_settings(config.MODEL),
    }

    if phase == "train":
        settings.update(training_workflow="assertion_pec_tree_llm_rules",
                        flat_training_output=False,
                        tree_parser=config.ASSERTION_TREE_PARSER,
                        tree_parse_failure_policy="explicit_opaque_source_anchor",
                        training_rule_schema="whole_assertion_diagnoses_v8",
                        training_feedback="latest_high_level_diagnoses_located_rules")

    if phase == "infer":
        settings.update(
            inference_workflow="existing_diagnosis_and_rule_selection",
            inference_selector_applicability_reasons=False,
            inference_feedback="latest_ranked_masked_diagnoses_and_rules",
            inference_rule_stages='rank_existing_diagnoses_and_rules_only',
            inference_rule_context='masked_diagnoses_and_rules_only',
            inference_rule_generation_enabled=False,
            inference_max_selected_rules=config.TOP_K_RULES,
            inference_max_selected_diagnoses=config.TOP_K_DIAGNOSES,
            training_evidence_masking="after_unmasked_cosine; requirements_rules_revision_traces; role_based_unique_per_case",
            source_training_run=str(source_dir),
            inference_case_selection=("explicit_case_ids" if config.CASE_IDS else
                                      "all_dataset_cases_minus_source_selected_cases"),
            training_case_ids=[c["case_number"] for c in source_metadata["selected_cases"]],
            source_training_case_overlap=[case['case_number'] for case in cases
                                          if case['case_number'] in training_ids],
            retrieval_top_k=config.TOP_K_CASES, embedding_model=config.EMBEDDING_MODEL,
            retrieval_requirement_text=RETRIEVAL_REQUIREMENT_POLICY,
            retrieval_eligible_cases=len(retriever.cases),
            retrieval_passed_cases_only=True,
            retrieval_requires_diagnoses_and_rules=True,
            excluded_missing_guidance_case_ids=list(retriever.excluded_missing_guidance_case_ids),
            example_retrieval="top_three_distinct_accepted_generated_training_pairs_by_requirement_cosine",
            example_diversity="unique_behavior_text_assertion_tokens_and_similarity_abs_tol_1e-8",
            missing_generated_example_case_ids=list(retriever.missing_generated_example_case_ids),
            example_pool_size=len(retriever.examples),
            source_rules_sha256=retriever.sha256,
        )

    if phase == "inference_only":
        from new_agent.inference_only_examples import get_examples, VERSION as EXAMPLES_VERSION
        fixed_examples = get_examples(config.DATASET)
        settings.update(
            inference_workflow="fixed_examples_generation_only",
            inference_feedback="no_separate_diagnosis",
            inference_retrieval="disabled", example_source="fixed_handwritten",
            fixed_examples_version=EXAMPLES_VERSION,
            fixed_example_ids=[example["id"] for example in fixed_examples],
            inference_case_selection="explicit_ids_or_entire_dataset_no_split",
            tree_reference_enabled=False,
        )

    # 2. Create one experiment containing shared summaries and separate case folders.
    experiment_dir = run_io.create_experiment(
        dataset=config.DATASET, dataset_path=dataset_path, cases=cases,
        models=models, settings=settings, runs_root=config.RUNS_DIR,
        phase=phase, source_training_run=source_dir,
    )
    if phase == "inference_only":
        import json
        run_io._atomic_write(experiment_dir / "fixed_examples.json",
                             json.dumps(fixed_examples, ensure_ascii=False, indent=2) + "\n")
    print(f"Mode={config.MODE} | Dataset={config.DATASET} | Model={config.MODEL} | "
          f"Cases={len(cases)} | Max rounds={config.MAX_ROUNDS}", flush=True)
    if phase == "infer":
        print("Training source:", source_dir, flush=True)
    print("Experiment:", experiment_dir)

    # 3. Run each selected case with its own revision loop and rule registry.
    # Native initialization files are temporary; experiment results stay separate.
    with TemporaryDirectory(prefix="fv_native_logs_", ignore_cleanup_errors=True) as native_log_dir:
        exit_code = 0
        try:
            with stage_progress("Formal evaluator initialization"):
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
                    case_dir=experiment_dir / "cases" / f"case_{case['case_number']:04d}",
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









