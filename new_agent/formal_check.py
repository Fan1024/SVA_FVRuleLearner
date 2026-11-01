"""Call this repository's native evaluation.py directly, in the current process.

The native evaluator invokes its original Jasper launcher/Tcl/PEC. Immediately
before launch, our source-boundary adapter replaces the two property-expression
arguments, binds TB integral parameters, and supplies a prepared signal-name list. Native PEC files and Tcl
remain untouched; there is no analyze-command interception or Tcl overlay.
Human/Machine SYN checking includes the full candidate in the TB. Missing PEC
verdicts remain unavailable and cannot be accepted through text similarity.
"""

from dataclasses import asdict
from contextlib import contextmanager, redirect_stdout, redirect_stderr
import hashlib
import importlib
import inspect
import json
import math
from pathlib import Path
import re
import shutil
import sys
import tempfile
from time import perf_counter
import traceback
from types import SimpleNamespace
from new_agent.pec_input_adapter import ExtractionError, prepare_pec_inputs
from new_agent.pec_context_adapter import prepare_signal_list, bind_parameter_constants


REPO_ROOT = Path(__file__).resolve().parents[1]
COMPARISON_SCOPE = (
    "Use the supplied dataset-specific FVRuleLearner comparison_scope. Generate "
    "a complete assertion using the original testbench. Do not infer that "
    "excluded clock/reset wrappers were compared by PEC."
)
SEMANTIC_STATUSES = frozenset({"FULL_EQUIVALENCE", "IMPLIES", "NO_EQUIVALENCE"})
_SESSION = None


def apply_acceptance_policy(result: dict) -> dict:
    """Apply FVRuleLearner's PEC-or-BLEU reporting rule; retain raw scores."""
    raw = result.setdefault("raw_scores", {
        name: result.get(name) for name in ("syntax", "pec", "relax_pec")
    })
    completed = result.get('status') in SEMANTIC_STATUSES
    bleu_match = completed and result.get("bleu") == 1.0
    native_pass = completed and raw.get("pec") == 1.0
    result["accepted"] = native_pass or bleu_match
    result["acceptance_reason"] = "pec" if native_pass else "bleu_match" if bleu_match else None
    if bleu_match:
        result["pec"] = result["relax_pec"] = 1.0
    return result


def get_evaluation_policy(dataset: str) -> dict:
    if dataset not in {"nl2sva_human", "nl2sva_machine", "nl2sva_opencore"}:
        raise ValueError("DATASET must be 'nl2sva_human', 'nl2sva_machine', or 'nl2sva_opencore'.")
    if dataset == "nl2sva_opencore":
        return {
            "scope": (
                "Use the native NL2SVA-OpenCore evaluator and run_jg_nl2sva_opencore.tcl. "
                "The provided context is a module interface, not a complete testbench. "
                "Use the actual clock signal and edge required by the requirement/interface; "
                "do not invent a signal named clk or tb_reset. Replace EDGE and CLOCK_SIGNAL "
                "in the statement template with the required edge and actual clock. "
                "Our PEC input adapter removes the leading clock event from a wrapped "
                "assertion; remaining reset/disable iff logic stays in the formula. "
                "Do not add reset disabling absent from the requirement. "
                "The native Tcl checks candidate against itself, then candidate against reference; "
                "the native OpenCore scorer requires two full-equivalence reports. "
                "Do not edit an assertion solely to repair PEC declaration/compilation issues."
            ),
            "include_reset": True,
            "tcl_file": "run_jg_nl2sva_opencore.tcl",
            "assertion_template": "asrt: assert property (@(EDGE CLOCK_SIGNAL) BODY);",
        }
    human = dataset == "nl2sva_human"
    scope = (
        "Use the native NL2SVA-Human evaluator with source-boundary extraction. "
        "It compares the property body, excluding the standard clock and disable "
        "iff wrapper. Use @(posedge clk) disable iff (tb_reset), as required by "
        "this benchmark. Do not edit an excluded wrapper solely to fix a PEC "
        "mismatch. Reset-related logic inside the body remains in scope."
        if human else
        "Use the native NL2SVA-Machine evaluator with source-boundary extraction. "
        "It compares the expression after the leading clock event. Remaining disable "
        "iff text is included. Use @(posedge clk); do not introduce reset "
        "conditions absent from the requirement/testbench."
    )
    return {"scope": scope + " Keep the complete assertion syntactically valid. "
            "Native Human/Machine SYN checking compiles the full generated assertion "
            "inserted into the supplied testbench before running PEC.",
            "include_reset": not human, "tcl_file": f"run_jg_{dataset}.tcl",
            "assertion_template": (
                "asrt: assert property (@(posedge clk) BODY);" if human else
                "assert property (@(posedge clk) BODY);"
            )}


def validate_backend() -> Path:
    """Check this checkout's native files, without running a tool or importing ML."""
    required = ("src/config.py", "src/saver.py", "src/utils.py",
                "FVEval/fv_eval/evaluation.py", "FVEval/fv_eval/data.py",
                "FVEval/fv_eval/utils.py", "FVEval/fv_eval/fv_tool_execution.py",
                "FVEval/tool_scripts/pec/pec.tcle",
                "FVEval/tool_scripts/run_jg_nl2sva_human.tcl",
                "FVEval/tool_scripts/run_jg_nl2sva_machine.tcl")
    missing = [name for name in required if not (REPO_ROOT / name).is_file()]
    if missing:
        raise FileNotFoundError(f"Incomplete evaluator in {REPO_ROOT}: {', '.join(missing)}")
    return REPO_ROOT


def _write_json(path: Path, value) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


@contextmanager
def _capture_native_console(path: Path):
    """Keep native import/tool chatter in a file during serial evaluation."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        with redirect_stdout(stream), redirect_stderr(stream):
            yield


def initialize_evaluator(log_dir, dataset: str, timeout_seconds: float = 300):
    """Initialize native evaluation quietly, preserving its console output."""
    log_dir = Path(log_dir).resolve()
    with _capture_native_console(log_dir / "native_console.log"):
        return _initialize_evaluator(log_dir, dataset, timeout_seconds)


def _initialize_evaluator(log_dir, dataset: str, timeout_seconds: float = 300):
    """Initialize native modules/metrics once, before the first model request.

    Our settings are new_agent.config. The original modules retain their normal
    top-level imports of src/config.py, saver.py and utils.py. No fake modules,
    function extraction, separate checkout, process, or environment are used.
    """
    global _SESSION
    get_evaluation_policy(dataset)
    repo = validate_backend()
    active_tcl = "FVEval/tool_scripts/" + get_evaluation_policy(dataset)["tcl_file"]
    if not (repo / active_tcl).is_file():
        raise FileNotFoundError(f"Missing native evaluator script: {repo / active_tcl}")
    if type(timeout_seconds) not in (int, float) or not math.isfinite(timeout_seconds) or timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be finite and positive.")
    started = perf_counter()
    if _SESSION is None:
        # Protect normal imports from stale legacy top-level config/utils modules.
        for name in ("config", "utils", "saver"):
            module = sys.modules.get(name)
            if module is not None and Path(getattr(module, "__file__", "")).resolve() != repo / "src" / f"{name}.py":
                raise RuntimeError(f"Top-level {name} came from another module. Start with python new_agent/main.py.")
        src = repo / "src"
        our_dir = Path(__file__).resolve().parent
        sys.path[:] = [str(src), str(repo)] + [p for p in sys.path if p and
            Path(p).resolve() not in {src, repo, our_dir}]
        log_dir = Path(log_dir).resolve()
        log_dir.mkdir(parents=True, exist_ok=True)
        old_argv = sys.argv[:]
        try:
            # The original Saver parses argv at import. Give it only its own option.
            sys.argv[:] = [str(src / "main.py"), "--logdir", str(log_dir)]
            native_config = importlib.import_module("config")
            flags = native_config.FLAGS
            flags.global_task = "train"
            flags.task = dataset
            flags.tcl_eval_file_path = str(repo / "FVEval" / "tool_scripts" / f"run_jg_{dataset}.tcl")
            flags.jg_timeout_seconds = timeout_seconds
            flags.debug = False
            evaluation = importlib.import_module("FVEval.fv_eval.evaluation")
            data = importlib.import_module("FVEval.fv_eval.data")
            execution = importlib.import_module("FVEval.fv_eval.fv_tool_execution")
        finally:
            sys.argv[:] = old_argv
        if Path(evaluation.__file__).resolve() != repo / "FVEval" / "fv_eval" / "evaluation.py":
            raise RuntimeError("Imported evaluation.py from the wrong checkout.")
        source = {"repo_dir": str(repo), "commit": getattr(flags, "commit_sha", None),
                  "python": sys.executable, "input_policy": "native_per_round_training",
                  "sha256": {name: hashlib.sha256((repo / name).read_bytes()).hexdigest()
                    for name in ("FVEval/fv_eval/evaluation.py", "FVEval/fv_eval/data.py",
                                 "FVEval/fv_eval/fv_tool_execution.py", "FVEval/fv_eval/utils.py",
                                 "FVEval/tool_scripts/run_jg_nl2sva_human.tcl",
                                 "FVEval/tool_scripts/run_jg_nl2sva_machine.tcl",
                                 "FVEval/tool_scripts/pec/pec.tcle")}}
        _SESSION = SimpleNamespace(evaluation=evaluation, data=data, execution=execution,
                                   flags=flags, evaluators={}, log_dir=log_dir, source=source)
    session = _SESSION
    session.source["sha256"][active_tcl] = hashlib.sha256((repo / active_tcl).read_bytes()).hexdigest()
    session.flags.global_task = "train"
    session.flags.task = dataset
    session.flags.jg_timeout_seconds = timeout_seconds
    session.flags.tcl_eval_file_path = str(repo / "FVEval" / "tool_scripts" / f"run_jg_{dataset}.tcl")
    if dataset not in session.evaluators:
        kwargs = {"llm_output_dir": "", "model_name": "experiment",
                  "temp_dir": str(session.log_dir), "save_dir": str(session.log_dir),
                  "parallel_jobs": 1, "cleanup_temp_files": False, "debug": False}
        evaluator = (session.evaluation.NL2SVAHumanEvaluator(**kwargs) if dataset == "nl2sva_human"
                     else session.evaluation.NL2SVAMachineEvaluator(task=dataset, **kwargs))
        session.evaluators[dataset] = evaluator
        session.source.setdefault("initialization_seconds", {})[dataset] = perf_counter() - started
        _write_json(session.log_dir / "source.json", session.source)
    return session.evaluators[dataset]


def _execution_status(output: str) -> str:
    """Label execution health; numerical scores still come only from evaluation.py."""
    lines = [line for line in output.splitlines() if not re.match(r"^\s*(?:%\s*)?#", line)]
    text = "\n".join(lines)
    lower = text.lower()
    if "jasper_timeout:" in lower or "timeout: jaspergold" in lower:
        return "TIMEOUT"
    if any(word in lower for word in ("license checkout failed", "failed to checkout license",
                                      "failed to contact license server", "no license available",
                                      "flexnet licensing error", "license server machine is down")):
        return "TOOL_ERROR"
    errors = [line for line in lines if re.match(r"^\s*\[?\s*(?:ERROR|FATAL)\b", line, re.I)]
    if any(re.search(r"(?:^|[/\\])pec\.sve(?:\(|:)", line, re.I) for line in errors):
        return "PEC_COMPILE_ERROR"
    if any(re.search(r"VERI-|ENL\d+|syntax error|previous errors", line, re.I) for line in errors):
        return "SYNTAX_ERROR"
    if re.search(r"^\s*Full equivalence between\b", text, re.M):
        verdict = "FULL_EQUIVALENCE"
    elif re.search(r"^\s*implies\s*$", text, re.M):
        verdict = "IMPLIES"
    elif re.search(r"^\s*(?:No equivalence between\b|conflict with each other\b)", text, re.M):
        verdict = "NO_EQUIVALENCE"
    else:
        verdict = "INCONCLUSIVE"
    if errors:
        codes = [re.search(r"\b(?:ERROR|FATAL)\s*\(([^)]+)\)", line, re.I) for line in errors]
        if not (verdict == "NO_EQUIVALENCE" and all(m and m[1] in {"EAS001", "ERS035", "ERS055"} for m in codes)):
            return "TOOL_ERROR"
    if verdict == "INCONCLUSIVE" and re.search(r"\bsyntax error\b", text, re.I):
        return "SYNTAX_ERROR"
    return verdict


def _candidate_testbench(testbench, assertion, module_name=None):
    """Insert the candidate into the plaintext TB for existing native SYN checking."""
    import pyslang
    tree = pyslang.syntax.SyntaxTree.fromText(testbench)
    root = tree.root
    modules = [root] if root.kind.name == 'ModuleDeclaration' else [
        item for item in root.members if item.kind.name == 'ModuleDeclaration']
    if module_name:
        modules = [item for item in modules if item.header.name.valueText == module_name]
    if len(modules) != 1:
        raise ValueError('Candidate SYN checking requires one TB module; set PEC_CONTEXT_MODULE.')
    position = modules[0].endmodule.location.offset
    raw = testbench.encode('utf-8')
    return raw[:position].decode() + '\n// Candidate for native SYN checking\n' + assertion + '\n' + raw[position:].decode()


def evaluate_assertion(generated_assertion: str, reference_assertion: str, testbench: str,
                       requirement: str, run_dir=None, timeout_seconds: float = 300,
                       task_id: str = "case", dataset: str = "nl2sva_human", *,
                       model_name: str = "experiment") -> dict:
    """Use native evaluation, replacing only property extraction before launch."""
    started = perf_counter()
    policy = get_evaluation_policy(dataset)
    for name, value in (("generated_assertion", generated_assertion), ("reference_assertion", reference_assertion),
                        ("testbench", testbench), ("requirement", requirement),
                        ("task_id", task_id), ("model_name", model_name)):
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{name} must be a nonempty string.")
    directory = (Path(tempfile.mkdtemp(prefix="native_eval_")) if run_dir is None
                 else Path(run_dir).expanduser().resolve())
    directory.mkdir(parents=True, exist_ok=True)
    work = directory / "_work"
    work.mkdir(exist_ok=False)
    (work / "checker_owned.marker").write_text(str(directory), encoding="utf-8")
    evaluator = initialize_evaluator(directory / "native_logs", dataset, timeout_seconds)
    evaluator.temp_dir = evaluator.save_dir = str(work)
    tool_id = "case_" + hashlib.sha256(task_id.encode()).hexdigest()[:16]
    result = {"status": "TOOL_ERROR", "syntax": None, "pec": None, "relax_pec": None,
              "bleu": None, "rouge": None, "exact_match": None,
              "comparison_scope": policy["scope"], "returncode": None,
              "source_task_id": task_id, "tool_task_id": tool_id,
              "run_dir": str(directory), "work_dir": str(work),
              "log_path": str(directory / "jasper.log"), "input_path": str(directory / "formal_input.sva"),
              "backend": "same_repo_fvrulelearner", "native_source": _SESSION.source,
              "native_metrics": {}, "native_similarity": {}, "native_timing": {}, "tool_output": ""}
    similarity_started = perf_counter()
    try:
        with _capture_native_console(directory / "native_console.log"):
            similarity = evaluator.calculate_similiarty_metric(generated_assertion, reference_assertion, original_setting=False)
        result["native_similarity"] = similarity
        for name in ("bleu", "rouge", "exact_match"):
            value = similarity.get(name)
            result[name] = float(value) if value is not None else None
    except Exception as error:
        result["similarity_error"] = f"{type(error).__name__}: {error}"
    result["native_timing"]["similarity_seconds"] = perf_counter() - similarity_started
    from new_agent import config
    packaged_tb = testbench
    if dataset in {'nl2sva_human', 'nl2sva_machine'}:
        packaged_tb = _candidate_testbench(testbench, generated_assertion,
                                         getattr(config, 'PEC_CONTEXT_MODULE', None))
    lm_result = _SESSION.data.LMResult(experiment_id=dataset, task_id=tool_id, model_name=model_name,
        response=generated_assertion, ref_solution=reference_assertion,
        user_prompt=requirement, output_tb="\n" if dataset == "nl2sva_opencore" else packaged_tb,
        design_rtl="\n", cot_response="\n")
    original_launcher = _SESSION.execution.launch_jg_custom_equiv_check
    outputs = []

    def observed_launcher(*args, **kwargs):
        # Keep native preparation, replace intact source expressions, and expand
        # names immediately before the unchanged native Jasper launcher runs.
        bound = inspect.signature(original_launcher).bind(*args, **kwargs)
        native_formulas = {name: bound.arguments.get(name) for name in
                           ("lm_assertion_text", "ref_assertion_text")}
        try:
            preparation = prepare_pec_inputs(generated_assertion, reference_assertion, dataset)
        except ExtractionError as error:
            result["pec_input_preparation"] = {
                "dataset": dataset, "error": str(error),
                "generated_source": generated_assertion,
                "reference_source": reference_assertion,
                "native_formulas": native_formulas,
            }
            raise
        from new_agent import config
        effective_names, context_preparation = prepare_signal_list(
            testbench, bound.arguments.get("signal_list_text", ""),
            module_name=getattr(config, "PEC_CONTEXT_MODULE", None))
        bound.arguments["signal_list_text"] = effective_names
        result["pec_context_preparation"] = context_preparation
        preparation["native_formulas"] = native_formulas
        result["pec_input_preparation"] = preparation
        parameter_bindings = {}
        for side, argument in (('generated', 'lm_assertion_text'), ('reference', 'ref_assertion_text')):
            formula = preparation[side]['formula']
            bindings = {}
            if context_preparation['mode'] == 'expanded_names':
                formula, bindings = bind_parameter_constants(
                    formula, testbench, getattr(config, 'PEC_CONTEXT_MODULE', None))
            preparation[side]['native_formula'] = formula
            preparation[side]['parameter_bindings'] = bindings
            parameter_bindings.update(bindings)
            bound.arguments[argument] = formula
        context_preparation['parameter_bindings'] = parameter_bindings
        _write_json(directory / "native_pec_inputs.json", {
            "args": list(bound.args), "kwargs": bound.kwargs,
            "preparation": preparation,
        })
        try:
            output = original_launcher(*bound.args, **bound.kwargs)
        except Exception as error:
            outputs.append(str(error))
            raise
        outputs.append(output)
        return output

    _SESSION.execution.launch_jg_custom_equiv_check = observed_launcher
    jg_started = perf_counter()
    try:
        with _capture_native_console(directory / "native_console.log"):
            native_results = evaluator.evaluate_jg([lm_result], with_rtl_design=True)
        if len(native_results) != 1:
            raise RuntimeError(f"Expected one native result, got {len(native_results)}")
        scores = asdict(native_results[0])
        result["native_metrics"] = scores
        result["tool_output"] = "\n".join(outputs)
        result["status"] = _execution_status(result["tool_output"])
        if result["status"] in SEMANTIC_STATUSES | {"SYNTAX_ERROR", "PEC_COMPILE_ERROR"}:
            for target, source in (("syntax", "syntax"), ("pec", "functionality"), ("relax_pec", "func_relaxed")):
                result[target] = scores[source]
            if dataset == "nl2sva_opencore" and result["status"] in SEMANTIC_STATUSES:
                # One of OpenCore's two checks may say Full equivalence. The
                # supplied native scorer, not that first message, is authoritative.
                result["status"] = ("FULL_EQUIVALENCE" if scores["functionality"] == 1.0 else
                                    "IMPLIES" if scores["func_relaxed"] == 1.0 else "NO_EQUIVALENCE")
        if result['status'] not in SEMANTIC_STATUSES:
            result['pec'] = result['relax_pec'] = None
    except Exception as error:
        result["tool_output"] = "\n".join(outputs) or str(error)
        observed = _execution_status(result["tool_output"])
        result["status"] = observed if observed in {"TIMEOUT", "PEC_COMPILE_ERROR", "SYNTAX_ERROR"} else "TOOL_ERROR"
        if isinstance(error, ExtractionError):
            result["status"] = "INPUT_ERROR"
            result["error_origin"] = "pec_extraction"
        result["evaluation_error"] = f"{type(error).__name__}: {error}"
        (directory / "evaluation_error.log").write_text(traceback.format_exc(), encoding="utf-8")
    finally:
        _SESSION.execution.launch_jg_custom_equiv_check = original_launcher
        result["native_timing"]["jg_seconds"] = perf_counter() - jg_started
        native_input = work / f"{dataset}_{tool_id}.sva"
        if dataset == "nl2sva_opencore":
            # Native OpenCore Tcl does not compile/package a dataset testbench.
            result["input_path"] = str(directory / "native_pec_inputs.json")
        if native_input.is_file():
            shutil.copyfile(native_input, result["input_path"])
        Path(result["log_path"]).write_text(result["tool_output"] + "\n", encoding="utf-8")
    apply_acceptance_policy(result)
    result["native_timing"]["total_seconds"] = perf_counter() - started
    result["feedback"] = (f"Formal status: {result['status']}\nSyntax: {result['syntax']}; strict PEC: {result['pec']}; "
                          f"relaxed PEC: {result['relax_pec']}\nNative BLEU: {result['bleu']}\n"
                          f"Comparison scope: {policy['scope']}\nTool details:\n{result['tool_output'][-6000:]}")
    if result["status"] == "PEC_COMPILE_ERROR":
        result["feedback"] = (
            "PEC compilation failed; no formal equivalence verdict was obtained. "
            "Inspect the retained native/adapted PEC declarations; do not infer a mismatch. "
            "Do not infer a candidate syntax or semantic defect from this tool failure. "
            "Do not rewrite assertions to repair the PEC implementation.\n"
            + result["feedback"]
        )
    if result.get("error_origin") == "pec_extraction":
        result["feedback"] = (
            "PEC input extraction failed before Jasper was launched. No SYN or PEC "
            "verdict was obtained; do not treat this as a measured syntax failure.\n"
            + result["feedback"]
        )
    _write_json(directory / "result.json", result)
    return result


def cleanup_work(result: dict, keep_work=False, *, preserve_unresolved=True) -> dict:
    work = Path(result["work_dir"])
    if not work.exists():
        return {"retained": False, "reason": "No work directory remains."}
    if keep_work or (preserve_unresolved and result["status"] not in SEMANTIC_STATUSES | {"SYNTAX_ERROR"}):
        return {"retained": True, "reason": "Work retained for requested diagnostics."}
    directory = Path(result["run_dir"]).resolve()
    marker = work / "checker_owned.marker"
    if (work.is_symlink() or work.name != "_work" or work.resolve().parent != directory
            or not marker.is_file() or marker.read_text(encoding="utf-8") != str(directory)):
        return {"retained": True, "reason": "Ownership check failed; no files deleted."}
    shutil.rmtree(work)
    return {"retained": False, "reason": "Removed owned native evaluation work."}




