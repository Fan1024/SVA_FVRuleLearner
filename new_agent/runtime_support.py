"""Visible stage progress and supervised native Jasper execution."""
from contextlib import contextmanager
import locale
import os
from pathlib import Path
import signal
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Event, Lock, Thread
from time import monotonic


_CONSOLE_LOCK = Lock()


def console_status(message):
    """Reach the terminal even while native evaluator output is redirected."""
    stream = sys.__stdout__ if sys.__stdout__ is not None else sys.stdout
    try:
        with _CONSOLE_LOCK:
            print(message, file=stream, flush=True)
    except (OSError, ValueError):
        pass  # A closed terminal must not discard experiment results.


@contextmanager
def stage_progress(label, interval=15.0):
    """Report a synchronous stage without changing its result or exceptions."""
    started = monotonic()
    finished = Event()

    def heartbeat():
        while not finished.wait(interval):
            console_status(f"{label}: still running ({monotonic() - started:.0f}s elapsed).")

    console_status(f"{label}: started.")
    worker = Thread(target=heartbeat, daemon=True)
    worker.start()
    outcome = "completed"
    try:
        yield
    except BaseException as error:
        outcome = "interrupted" if isinstance(error, KeyboardInterrupt) else "failed"
        raise
    finally:
        finished.set()
        worker.join(timeout=1)
        console_status(f"{label}: {outcome} ({monotonic() - started:.1f}s).")


@contextmanager
def formal_round_directory(directory, round_number, record=None):
    """Discard routine tool files; preserve one failure log before interruption."""
    with TemporaryDirectory(prefix="fv_formal_round_", ignore_cleanup_errors=True) as temporary:
        path = Path(temporary)
        try:
            yield path
        except BaseException as error:
            if record is not None and record.get("stage") == "formal_check":
                status = "INTERRUPTED" if isinstance(error, KeyboardInterrupt) else "TOOL_ERROR"
                persist_failure_log(directory, record, round_number, path, status)
            raise


def persist_failure_log(directory, record, round_number, source, status, output=None):
    """Save one useful error log; ordinary semantic mismatches need no tool files."""
    failures = {"PEC_COMPILE_ERROR", "TOOL_ERROR", "INPUT_ERROR", "SYNTAX_ERROR", "TIMEOUT", "INTERRUPTED"}
    if not record.get("settings", {}).get("save_debug_traces") or status not in failures:
        return None
    source = Path(source)
    parts = [f"Formal status: {status}"]
    if output:
        parts.append(output)
    elif (source / "jasper.log").is_file():
        parts.append((source / "jasper.log").read_text(encoding="utf-8", errors="replace"))
    else:
        parts.extend(path.read_text(encoding="utf-8", errors="replace")
                     for path in sorted(source.glob("jasper_[0-9]*.log")))
        if len(parts) == 1 and (source / "native_console.log").is_file():
            parts.append((source / "native_console.log").read_text(encoding="utf-8", errors="replace"))
    for name in ("candidate_syn.log", "evaluation_error.log"):
        path = source / name
        if path.is_file():
            parts.append(f"\n{name}\n" + path.read_text(encoding="utf-8", errors="replace"))
    # PEC/extraction failures benefit from their actual adapted expressions.
    path = source / "native_pec_inputs.json"
    if status in {"PEC_COMPILE_ERROR", "INPUT_ERROR"} and path.is_file():
        parts.append("\nPEC inputs\n" + path.read_text(encoding="utf-8", errors="replace"))
    target = Path(directory) / "diagnostics" / f"round_{round_number:04d}.log"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n\n".join(parts).rstrip() + "\n", encoding="utf-8")
    record["formal_failure_log"] = str(target)
    return str(target)


class JasperExecutionTimeout(TimeoutError):
    """Retain partial output without the native launcher's lossy timeout branch."""

    def __init__(self, timeout, stdout, stderr):
        self.timeout = timeout
        self.stdout = self.output = stdout
        self.stderr = stderr
        super().__init__(f"JASPER_TIMEOUT: exceeded {timeout} seconds\n{stdout}\n{stderr}".rstrip())


def _stop_process_group(process):
    """Jasper and its inherited workers belong to this invocation's own group."""
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        elif process.poll() is None:
            process.kill()
    except ProcessLookupError:
        pass
    process.wait(timeout=5)


def run_jasper(command, directory, original, *args, **kwargs):
    """Preserve native run semantics while recording output directly to disk.

    File descriptors replace pipes, so inherited pipe handles cannot delay EOF.
    A separate process group lets timeout and Ctrl+C stop the launched workers.
    Only the serial native launcher's capture_output call is intercepted.
    """
    if (args or not command or Path(str(command[0])).name not in {"jg", "jaspergold"}
            or not kwargs.get("capture_output")):
        return original.run(command, *args, **kwargs)
    options = dict(kwargs)
    options.pop("capture_output")
    timeout = options.pop("timeout", None)
    check = options.pop("check", False)
    text = options.pop("text", False)
    text = options.pop("universal_newlines", False) or text
    encoding = options.pop("encoding", None)
    errors = options.pop("errors", None)
    text = text or encoding is not None or errors is not None
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    number = len(list(directory.glob("jasper_[0-9]*.log"))) + 1
    log_path = directory / f"jasper_{number:04d}.log"
    with log_path.open("wb") as out:
        process = subprocess.Popen(command, stdout=out, stderr=subprocess.STDOUT,
                                   start_new_session=(os.name == "posix"), **options)
        timed_out = False
        try:
            console_status(f"JasperGold: PID {process.pid}; timeout {timeout}s.")
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            # Also remove inherited workers left behind by an exited launcher.
            _stop_process_group(process)

    stdout, stderr = log_path.read_bytes(), b""
    if text:
        codec = encoding or locale.getpreferredencoding(False)
        stdout = stdout.decode(codec, errors or "replace")
        stderr = stderr.decode(codec, errors or "replace")
    if timed_out:
        # Keep TIMEOUT ahead of any partial verdict when formal_check classifies it.
        def to_text(value):
            return value if isinstance(value, str) else value.decode("utf-8", "replace")
        raise JasperExecutionTimeout(timeout, to_text(stdout), to_text(stderr))
    result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    if check:
        result.check_returncode()
    return result
