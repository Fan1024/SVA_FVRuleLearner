"""Visible stage progress and supervised native Jasper execution."""
from contextlib import contextmanager
import json
import locale
import os
from pathlib import Path
import signal
import subprocess
import sys
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
def formal_round_directory(directory, round_number):
    """Keep round logs through errors and Ctrl+C; work cleanup is separate."""
    path = Path(directory) / "formal_rounds" / f"round_{round_number:04d}"
    path.mkdir(parents=True, exist_ok=False)
    yield path


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
    number = len(list(directory.glob("jasper_*.stdout.log"))) + 1
    prefix = directory / f"jasper_{number:04d}"
    stdout_path = prefix.with_suffix(".stdout.log")
    stderr_path = prefix.with_suffix(".stderr.log")
    state_path = prefix.with_suffix(".process.json")
    started = monotonic()
    state = {"status": "starting", "timeout_seconds": timeout,
             "stdout_log": str(stdout_path), "stderr_log": str(stderr_path)}

    def save_state():
        state["elapsed_seconds"] = monotonic() - started
        state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

    with stdout_path.open("wb") as out, stderr_path.open("wb") as err:
        process = subprocess.Popen(command, stdout=out, stderr=err,
                                   start_new_session=(os.name == "posix"), **options)
        timed_out = False
        try:
            state.update(pid=process.pid, status="running")
            save_state()
            console_status(f"JasperGold: PID {process.pid}; timeout {timeout}s; live log: {stdout_path}")
            process.wait(timeout=timeout)
            state["status"] = "exited"
        except subprocess.TimeoutExpired:
            timed_out = True
            state["status"] = "timeout"
        except BaseException as error:
            state["status"] = "interrupted" if isinstance(error, KeyboardInterrupt) else "failed"
            raise
        finally:
            # Also remove inherited workers left behind by an exited launcher.
            _stop_process_group(process)
            state["returncode"] = process.returncode
            save_state()

    stdout, stderr = stdout_path.read_bytes(), stderr_path.read_bytes()
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
