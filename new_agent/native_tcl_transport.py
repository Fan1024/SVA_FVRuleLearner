"""Transfer native launcher defines literally; source unchanged native Tcl.

Only the subprocess reference in the serial native execution module is scoped.
The standard-library subprocess module and native launcher stay intact.
"""
from contextlib import contextmanager
from pathlib import Path
import re
import tempfile
from new_agent.runtime_support import run_jasper

COMPLETED_MARKER = "FVRULE_NATIVE_TCL_COMPLETED"


def literal(value):
    """A Tcl expression that round-trips newlines, comments and substitutions."""
    return "[encoding convertfrom utf-8 [binary format H* {" + str(value).encode("utf-8").hex() + "}]]"


def prepare_command(command, directory):
    """Move every -define value into a bootstrap; preserve other options."""
    command = list(command)
    if not command or Path(str(command[0])).name not in {"jg", "jaspergold"}:
        return command
    if "-define" not in command:
        return command
    rewritten, definitions, script = [], [], None
    index = 0
    while index < len(command):
        option = command[index]
        if option == "-define":
            if index + 2 >= len(command):
                raise ValueError("Incomplete native Jasper -define argument.")
            name, value = command[index + 1:index + 3]
            if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", name):
                raise ValueError("Unsupported native Tcl variable name.")
            definitions.append("set " + name + " " + literal(value))
            index += 3
        elif option == "-tcl":
            if index + 1 >= len(command):
                raise ValueError("Missing native Tcl script path.")
            script = str(Path(command[index + 1]).resolve())
            rewritten.extend([option, None])
            index += 2
        else:
            rewritten.append(option)
            index += 1
    if script is None:
        raise ValueError("Native Jasper invocation requires -tcl.")
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".tcl",
                                     prefix="native_transport_", dir=directory,
                                     delete=False) as stream:
        stream.write("# Literal inputs; source the unchanged native checker.\n")
        stream.write("\n".join(definitions) + "\n")
        stream.write("source " + literal(script) + "\n")
        stream.write("puts {" + COMPLETED_MARKER + "}\n")
        stream.write("exit\n")
        path = stream.name
    rewritten[rewritten.index("-tcl") + 1] = path
    return rewritten


@contextmanager
def literal_define_transport(execution, directory):
    """Keep native Tcl/cwd/scoring; supervise the serial Jasper subprocess."""
    original = execution.subprocess

    class Transport:
        def __getattr__(self, name):
            return getattr(original, name)

        def run(self, command, *args, **kwargs):
            return run_jasper(prepare_command(command, directory), directory,
                              original, *args, **kwargs)

    execution.subprocess = Transport()
    try:
        yield
    finally:
        execution.subprocess = original

