"""Evaluate assertions with FVRuleLearner's supplied FVEval/PEC checker.

Both complete assertions are compiled in the testbench first. The original
PEC helper then compares Human property bodies or Machine expressions after
the clock event. This module prepares inputs and parses the helper's verdict;
it does not implement an alternative equivalence proof.
"""

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


COMPARISON_SCOPE = (
    "Use FVRuleLearner's supplied PEC checker and the dataset's comparison scope. "
    "Complete assertions must compile in the testbench. Only recommend changes "
    "that correct syntax or behavior within the supplied scope; harmless "
    "formatting differences do not require correction."
)


def get_evaluation_policy(dataset: str) -> dict:
    """Match the expression scope used by the original dataset evaluators."""
    if dataset == "nl2sva_human":
        scope = (
            "Human PEC compares property bodies only. Clock events and disable iff "
            "wrappers are excluded from equivalence comparison, but the complete "
            "assertions must compile. Do not recommend wrapper edits solely to "
            "resolve a PEC mismatch. Reset-related conditions inside the body "
            "remain in scope."
        )
    elif dataset == "nl2sva_machine":
        scope = (
            "Machine PEC compares the property expression after the clock event, "
            "including any disable iff condition. Clock events are excluded from "
            "equivalence comparison, but the complete assertions must compile. "
            "Do not recommend clock edits solely to resolve a PEC mismatch. "
            "Do not invent reset conditions when the task does not require them."
        )
    else:
        raise ValueError("DATASET must be 'nl2sva_human' or 'nl2sva_machine'.")
    return {
        "scope": scope,
        "include_reset": dataset == "nl2sva_machine",
        "tcl_file": f"run_jg_{dataset}.tcl",
    }


def _without_comments(text: str) -> str:
    """Remove comments while preserving strings and character positions."""
    return re.sub(
        r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
        lambda match: match[0] if match[0].startswith('"') else " " * len(match[0]),
        text,
        flags=re.DOTALL,
    )


def _parenthesized(text: str) -> tuple[str, str]:
    """Read one balanced (...) group, returning its content and remaining text."""
    text = text.lstrip()
    if not text.startswith("("):
        raise ValueError("Expected a parenthesized expression.")
    depth = 0
    in_string = False
    escaped = False
    for index, character in enumerate(text):
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return text[1:index].strip(), text[index + 1:].strip()
    raise ValueError("Unbalanced parentheses in the assertion.")


def _assertion_parts(text: str) -> tuple[str, str, str, str]:
    """Return the assertion, expression after clock, body, and reset text.

    Balanced parentheses allow reset expressions such as !reset_ or a || b.
    The complete assertion is preserved for compilation.
    """
    assertion = re.sub(
        r"^\s*[A-Za-z_]\w*\s*:\s*", "", _without_comments(text).strip(),
    )
    header = re.match(r"assert\s+property\b", assertion)
    if header is None:
        raise ValueError("Expected exactly one assert property (...) statement.")
    specification, trailing = _parenthesized(assertion[header.end():])
    if not specification or trailing != ";":
        raise ValueError("Expected exactly one assert property (...) statement.")

    expression = specification
    if expression.startswith("@"):
        _, expression = _parenthesized(expression[1:])
    body = expression
    disable = re.match(r"disable\s+iff\b", expression)
    reset = ""
    if disable:
        reset, body = _parenthesized(expression[disable.end():])
        if not reset or not body:
            raise ValueError("Expected a disable iff condition followed by a property body.")
    if not body:
        raise ValueError("Expected a nonempty property body.")
    return assertion, expression, body, reset


class _PecAdapterUnsupported(ValueError):
    """The scalar adapter cannot safely preserve a construct's type semantics."""


def _pec_constant(expression, constants):
    """Evaluate only a small, explicit subset of SV integer constant expressions."""
    import ast
    import operator

    def literal(match):
        width, signed, base, digits = match.groups()
        radix = {"b": 2, "o": 8, "d": 10, "h": 16}[base.lower()]
        if re.search(r"[xXzZ?]", digits):
            raise _PecAdapterUnsupported("Unknown-valued parameter or range.")
        value = int(digits.replace("_", ""), radix)
        if width:
            bits = int(width)
            value &= (1 << bits) - 1
            if signed and value & (1 << (bits - 1)):
                value -= 1 << bits
        return str(value)

    expression = re.sub(r"(\d+)?'([sS]?)([bBoOdDhH])([0-9a-fA-F_xXzZ?]+)", literal, expression)
    expression = expression.replace("$clog2", "clog2")
    binary = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
              ast.LShift: operator.lshift, ast.RShift: operator.rshift,
              ast.BitAnd: operator.and_, ast.BitOr: operator.or_, ast.BitXor: operator.xor,
              ast.Mod: operator.mod}

    def evaluate(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and node.id in constants:
            return constants[node.id]
        if isinstance(node, ast.UnaryOp):
            value = evaluate(node.operand)
            if isinstance(node.op, ast.USub):
                return -value
            if isinstance(node.op, ast.UAdd):
                return value
            if isinstance(node.op, ast.Invert):
                return ~value
        if isinstance(node, ast.BinOp):
            a, b = evaluate(node.left), evaluate(node.right)
            if isinstance(node.op, ast.Div):
                if not b:
                    raise _PecAdapterUnsupported("Division by zero in a range.")
                return (abs(a) // abs(b)) * (-1 if (a < 0) != (b < 0) else 1)
            function = binary.get(type(node.op))
            if function:
                if isinstance(node.op, (ast.LShift, ast.RShift)) and not 0 <= b <= 64:
                    raise _PecAdapterUnsupported("Unsupported range shift.")
                return function(a, b)
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "clog2" and len(node.args) == 1 and not node.keywords):
            value = evaluate(node.args[0])
            if value < 0:
                raise _PecAdapterUnsupported("Negative $clog2 argument.")
            return max(0, value - 1).bit_length()
        raise _PecAdapterUnsupported(f"Unsupported constant expression: {expression}")

    try:
        return evaluate(ast.parse(expression.strip(), mode="eval").body)
    except (SyntaxError, ValueError, ArithmeticError, KeyError) as error:
        raise _PecAdapterUnsupported(f"Cannot resolve constant expression: {expression}") from error


def _pec_symbols(testbench):
    """Read simple non-ANSI/ANSI packed declarations; retain unsupported names."""
    text = _without_comments(testbench)
    constants, constant_types, pending = {}, {}, []
    for match in re.finditer(r"\b(?:localparam|parameter)\s+([^;]+);", text):
        declaration = match[1].strip()
        assignment = re.fullmatch(r"(.*?)\b([A-Za-z_]\w*)\s*=\s*(.+)", declaration, re.S)
        if assignment:
            prefix, name, value = assignment.groups()
            pending.append((name, value))
            # Only plain unsized decimal parameters/int declarations are inlined.
            constant_types[name] = (not prefix.strip() or prefix.strip() in {"int", "integer"}) and bool(re.fullmatch(r"\d+", value.strip()))
    while pending:
        remaining = []
        for name, value in pending:
            try:
                constants[name] = _pec_constant(value, constants)
            except _PecAdapterUnsupported:
                remaining.append((name, value))
        if len(remaining) == len(pending):
            break
        pending = remaining

    symbols = {}
    # Split top-level declaration fields without splitting function arguments or ranges.
    def fields(value):
        result, start, depth = [], 0, 0
        for index, character in enumerate(value):
            if character in "([{":
                depth += 1
            elif character in ")]}":
                depth -= 1
            elif character == "," and depth == 0:
                result.append(value[start:index])
                start = index + 1
        result.append(value[start:])
        return result

    def declaration(value):
        two_state = bool(re.search(r"\bbit\b", value))
        value = re.sub(r"^(?:input|output|inout)\b\s*", "", value.strip())
        value = re.sub(r"^(?:wire|reg|logic|bit)\b\s*", "", value)
        signed = bool(re.match(r"signed\b", value))
        value = re.sub(r"^(?:signed|unsigned)\b\s*", "", value)
        indices = None
        unsupported = "Signed packed declarations require an elaborated type parser." if signed else None
        if two_state:
            unsupported = "Two-state bit declarations require an elaborated type parser."
        if value.startswith("["):
            closing = value.find("]")
            if closing < 0:
                return
            packed, value = value[1:closing], value[closing + 1:].strip()
            try:
                left, right = [_pec_constant(x, constants) for x in packed.split(":")]
                if min(left, right) < 0 or abs(left - right) >= 256:
                    raise _PecAdapterUnsupported("Packed ranges must be nonnegative and at most 256 bits.")
                indices = list(range(left, right + (-1 if left >= right else 1), -1 if left >= right else 1))
            except (ValueError, _PecAdapterUnsupported) as error:
                unsupported = str(error)
        while value.startswith("["):
            closing = value.find("]")
            if closing < 0:
                return
            unsupported = "Multiple packed dimensions require an elaborated type parser."
            value = value[closing + 1:].strip()
        for field in fields(value):
            field = field.strip()
            # An initialized wire remains an unconstrained PEC input, as in upstream.
            name = re.match(r"([A-Za-z_]\w*)\b(.*)", field, re.S)
            if not name:
                continue
            tail = name[2].lstrip()
            reason = unsupported
            if tail and not tail.startswith("="):
                reason = "Unpacked arrays, multiple packed dimensions, and complex declarations are unsupported."
            symbols[name[1]] = {"indices": indices, "unsupported": reason}

    # Dataset Human files use non-ANSI declarations.
    for match in re.finditer(r"(?:(?<=;)|^)\s*((?:input|output|inout|wire|reg|logic|bit)\b[^;]*);", text, re.M):
        declaration(match[1])
    # Handle simple ANSI port lists used by small diagnostic controls.
    header = re.search(r"\bmodule\s+[A-Za-z_]\w*\s*\((.*?)\)\s*;", text, re.S)
    if header:
        current = None
        for field in fields(header[1]):
            field = field.strip()
            if re.match(r"(?:input|output|inout)\b", field):
                current = field
                declaration(field)
            elif current:
                prefix = re.match(r"(.*?)([A-Za-z_]\w*)\s*$", current, re.S)
                if prefix:
                    declaration(prefix[1] + field)
    return symbols, constants, constant_types


def _pec_lower_comparison(candidate, reference, testbench):
    """Expand unsigned packed inputs into scalars for the unchanged PEC engine.

    This changes representation, not values: every declared input bit gets one
    shared free scalar. A dynamic bit-select becomes a case-equality mux with
    an X default, preserving unknown and out-of-range index results.
    Unsupported types/index forms are rejected rather than guessed.
    """
    symbols, constants, constant_types = _pec_symbols(testbench)
    numeric = r"(?:\d+)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|'[01xXzZ]|\d[\d_]*"
    operators = r"\|->|\|=>|<<<|>>>|===|!==|&&&|##|&&|\|\||==|!=|<=|>=|<<|>>|\*\*|->|=>|~\^|\^~|~&|~\||\+:|-:"
    lexer = re.compile(r"\s+|" + numeric + r"|\$?[A-Za-z_]\w*|" + operators + r"|.", re.S)
    def tokens(expression):
        return [m[0] for m in lexer.finditer(expression) if not m[0].isspace()]
    all_tokens = tokens(candidate) + tokens(reference)
    used_vectors = {word for word in all_tokens if word in symbols and symbols[word]["indices"] is not None}
    bad_used = {word for word in all_tokens if word in symbols and symbols[word]["unsupported"]}
    if bad_used:
        raise _PecAdapterUnsupported("Unsupported declared input: " + ", ".join(sorted(bad_used)))
    if not used_vectors:
        return None
    forbidden = {"$left", "$right", "$high", "$low", "$increment", "$dimensions", "$unpacked_dimensions"}
    if forbidden.intersection(all_tokens) or "." in all_tokens or "\\" in all_tokens:
        raise _PecAdapterUnsupported("Type queries, hierarchical names and escaped identifiers require an elaborated type parser.")
    reserved = {"disable", "iff", "and", "or", "not", "intersect", "throughout", "within",
                "until", "s_until", "until_with", "s_until_with", "strong", "weak", "first_match",
                "eventually", "s_eventually", "always", "s_always", "nexttime", "s_nexttime",
                "accept_on", "reject_on", "sync_accept_on", "sync_reject_on", "if", "else"}
    scalars, layout = set(), {}
    # Avoid collisions with any original identifier.
    prefix = "__pec_bit_"
    while any(word.startswith(prefix) for word in all_tokens if re.fullmatch(r"[A-Za-z_]\w*", word)):
        prefix = "_" + prefix

    def bit_name(name, index):
        atom = f"{prefix}{name}_{index}"
        scalars.add(atom)
        layout.setdefault(name, {})[str(index)] = atom
        return atom

    def vector(name, selected=None):
        indices = symbols[name]["indices"] if selected is None else selected
        return "{" + ",".join(bit_name(name, i) for i in indices) + "}"

    def lower(sequence):
        result, position = [], 0
        while position < len(sequence):
            word = sequence[position]
            position += 1
            if word in symbols:
                info = symbols[word]
                indices = info["indices"]
                if position < len(sequence) and sequence[position] == "[":
                    if indices is None:
                        raise _PecAdapterUnsupported(f"Cannot select a bit of scalar {word}.")
                    start, depth = position + 1, 1
                    position += 1
                    while position < len(sequence) and depth:
                        depth += (sequence[position] == "[") - (sequence[position] == "]")
                        position += 1
                    if depth:
                        raise _PecAdapterUnsupported("Unbalanced bit-select.")
                    selection = sequence[start:position - 1]
                    if any(operator in selection for operator in {"+:", "-:"}):
                        raise _PecAdapterUnsupported("Indexed part-selects require an elaborated type parser.")
                    if position < len(sequence) and sequence[position] == "[":
                        raise _PecAdapterUnsupported("Multiple selections are unsupported.")
                    if ":" in selection:
                        if selection.count(":") != 1 or "+" in selection or "-" in selection:
                            raise _PecAdapterUnsupported("Only fixed part-selects are supported.")
                        colon = selection.index(":")
                        left = _pec_constant("".join(selection[:colon]), constants)
                        right = _pec_constant("".join(selection[colon + 1:]), constants)
                        if left != right and (left > right) != (indices[0] >= indices[-1]):
                            raise _PecAdapterUnsupported("Part-select direction does not match the declaration.")
                        chosen = list(range(left, right + (-1 if left >= right else 1), -1 if left >= right else 1))
                        if any(i not in indices for i in chosen):
                            raise _PecAdapterUnsupported("Out-of-range part-select requires an elaborated type parser.")
                        result.append(vector(word, chosen))
                    else:
                        try:
                            fixed = _pec_constant("".join(selection), constants)
                        except _PecAdapterUnsupported:
                            fixed = None
                        if fixed is not None:
                            result.append(bit_name(word, fixed) if fixed in indices else "1'bx")
                        else:
                            index = lower(selection)
                            mux = "1'bx"
                            for i in reversed(indices):
                                mux = f"((({index}) === 32'd{i}) ? {bit_name(word, i)} : {mux})"
                            result.append(mux)
                elif indices is not None:
                    result.append(vector(word))
                else:
                    scalars.add(word)
                    result.append(word)
            elif word in constants:
                if not constant_types.get(word) or not 0 <= constants[word] < (1 << 31):
                    raise _PecAdapterUnsupported(f"Property parameter {word} needs an elaborated type parser.")
                result.append(f"32'sd{constants[word]}")
            elif re.fullmatch(r"\$?[A-Za-z_]\w*", word):
                if word.startswith("$") or word in reserved:
                    result.append(word)
                else:
                    raise _PecAdapterUnsupported(f"No supported declaration for signal/operator {word}.")
            else:
                result.append(word)
        # Keep complete operator tokens intact and keep adjacent distinct tokens
        # separate: binary & followed by reduction & must never become &&.
        return " ".join(result)

    lowered_candidate, lowered_reference = lower(tokens(candidate)), lower(tokens(reference))
    return {"candidate_expression": lowered_candidate, "reference_expression": lowered_reference,
            "signal_list": ",".join(sorted(scalars)), "input_adapter": "unsigned_packed_scalar_expansion_v1",
            "signal_layout": layout}


def _prepare_formal_input(
    generated_assertion: str,
    reference_assertion: str,
    testbench: str,
    requirement: str,
    destination: Path,
    *,
    dataset: str,
) -> dict:
    """Compile full assertions and select the original PEC expressions/signals."""
    policy = get_evaluation_policy(dataset)
    try:
        candidate, candidate_expression, candidate_body, candidate_reset = (
            _assertion_parts(generated_assertion)
        )
    except ValueError as error:
        raise ValueError(f"Generated assertion: {error}") from error
    try:
        reference, reference_expression, reference_body, reference_reset = (
            _assertion_parts(reference_assertion)
        )
    except ValueError as error:
        raise ValueError(f"Reference assertion: {error}") from error

    if not policy["include_reset"]:
        candidate_expression = candidate_body
        reference_expression = reference_body

    # Follow the original evaluators' signal-list construction.
    if dataset == "nl2sva_human":
        signals = set(re.findall(r"'([^'\s]+)'", requirement))
        parameters = re.findall(
            r"\b(parameter|localparam)\s+(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
            testbench,
        )
        signals.update(match[2] for match in parameters)
    else:
        signals = set(re.findall(r"\bsig_\w+", reference_assertion))

    clean_testbench = _without_comments(testbench)
    modules = re.findall(r"\bmodule\s+([A-Za-z_]\w*)\b", clean_testbench)
    endings = list(re.finditer(r"\bendmodule\b", clean_testbench))
    if len(modules) != 1 or len(endings) != 1 or clean_testbench[endings[0].end():].strip():
        raise ValueError("Expected a testbench with one module ending in endmodule.")
    insertion = endings[0].start()
    destination.write_text(
        testbench[:insertion]
        + "\nreference: " + reference
        + "\nasrt: " + candidate + "\n"
        + testbench[insertion:],
        encoding="utf-8",
    )
    prepared = {
        "candidate_expression": candidate_expression,
        "reference_expression": reference_expression,
        "signal_list": ",".join(sorted(signals)),
        "generated_reset": candidate_reset,
        "reference_reset": reference_reset,
        # Textual information only. Equivalent aliases can differ here.
        "reset_mismatch": candidate_reset != reference_reset,
    }
    # The upstream PEC interface reconstructs name-only scalar inputs. Expand
    # supported Human vectors before passing the expressions to that engine.
    if dataset == "nl2sva_human":
        lowered = _pec_lower_comparison(candidate_expression, reference_expression, testbench)
        if lowered:
            prepared["original_comparison_inputs"] = {
                name: prepared[name] for name in
                ("candidate_expression", "reference_expression", "signal_list")
            }
            prepared.update(lowered)
    return prepared



def _parse_formal_result(output: str, returncode: int) -> dict:
    """Map the supplied PEC helper's explicit verdict to the existing scores."""
    lines = [
        line for line in output.splitlines()
        if not line.lstrip().startswith("#")
        and not re.match(r"^\s*%\s*#", line)
    ]
    text = "\n".join(lines)
    lower = text.lower()
    infrastructure_markers = (
        "failed to checkout license", "license checkout failed",
        "failed to contact license server", "license server machine is down",
        "no license available", "flexnet licensing error",
        "license manager daemon", "lmc-",
    )
    if any(marker in lower for marker in infrastructure_markers):
        return {"status": "TOOL_ERROR"}
    if re.search(r"(?:^|[/\\])pec\.sve(?:\(|:)", text, re.MULTILINE | re.IGNORECASE) and re.search(
        r"VERI-\d+|ignored due to previous errors", text, re.IGNORECASE,
    ):
        return {"status": "PEC_COMPILE_ERROR", "error_origin": "pec",
                "syntax": None, "pec": None, "relax_pec": None}
    if re.search(
        r"\bERROR\s+\((?:VERI-[^)]+|ENL\d+)\)"
        r"|\bsyntax error\b|ignored due to previous errors",
        text, flags=re.IGNORECASE,
    ):
        return {
            "status": "SYNTAX_ERROR",
            "syntax": 0.0, "pec": 0.0, "relax_pec": 0.0,
        }
    if returncode != 0:
        return {"status": "TOOL_ERROR"}

    if re.search(r"^\s*Full equivalence between\b", text, re.MULTILINE):
        return {
            "status": "FULL_EQUIVALENCE",
            "syntax": 1.0, "pec": 1.0, "relax_pec": 1.0,
        }
    if re.search(r"^\s*implies\s*$", text, re.MULTILINE):
        return {"status": "IMPLIES", "syntax": 1.0, "pec": 0.0, "relax_pec": 1.0}
    if re.search(
        r"^\s*(?:No equivalence between\b|conflict with each other\b)",
        text, re.MULTILINE,
    ):
        return {
            "status": "NO_EQUIVALENCE",
            "syntax": 1.0, "pec": 0.0, "relax_pec": 0.0,
        }
    return {"status": "INCONCLUSIVE"}


def _finish_result(result: dict, output: str) -> dict:
    """Keep the full log, but send a concise report to the diagnosis model."""
    result["tool_output"] = output
    Path(result["log_path"]).write_text(output, encoding="utf-8")
    useful_lines = [
        line for line in output.splitlines()
        if not line.lstrip().startswith("#")
        and not re.match(r"^\s*%\s*#", line)
        and re.search(
            r"ERROR|syntax error|equivalence|implies|conflict|"
            r"TIMEOUT|license|not found|Expected|Missing",
            line, flags=re.IGNORECASE,
        )
    ]
    details = "\n".join(useful_lines) or output[-4000:]
    result["feedback"] = (
        f"Formal status: {result['status']}\n"
        f"Syntax: {result['syntax']}; strict PEC: {result['pec']}; "
        f"relaxed PEC: {result['relax_pec']}\n"
        f"Generated reset: {result['generated_reset'] or '(none)'}\n"
        f"Reference reset: {result['reference_reset'] or '(none)'}\n"
        f"Reset text differs: {result['reset_mismatch']} (informational only)\n"
        f"Comparison scope: {result['comparison_scope']}\n"
        f"Tool details:\n{details[:6000]}"
    )
    return result


def evaluate_assertion(
    generated_assertion: str,
    reference_assertion: str,
    testbench: str,
    requirement: str,
    run_dir=None,
    timeout_seconds: float = 300,
    fveval_dir=None,
    jg_executable: str = "jg",
    task_id: str = "case",
    dataset: str = "nl2sva_human",
) -> dict:
    """Invoke the original FVEval Tcl driver and its supplied PEC helper."""
    policy = get_evaluation_policy(dataset)
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive.")
    if not isinstance(task_id, str) or not task_id.strip():
        raise ValueError("task_id must be a nonempty string.")
    source_task_id = task_id
    task_id = re.sub(r"[^A-Za-z0-9_-]+", "_", task_id).strip("_") or "case"
    if run_dir is None:
        root = Path(__file__).resolve().parent / "runs"
        root.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix=f"{task_id}_", dir=root))
    else:
        directory = Path(run_dir).expanduser().resolve()
        directory.mkdir(parents=True, exist_ok=True)
    work = directory / "_work"
    work.mkdir()
    (work / "checker_owned.marker").write_text(str(directory), encoding="utf-8")
    sv_file = directory / "formal_input.sva"
    result = {
        "status": "INPUT_ERROR",
        "syntax": None, "pec": None, "relax_pec": None,
        "generated_reset": "", "reference_reset": "",
        "reset_mismatch": None,
        "comparison_scope": policy["scope"],
        "run_dir": str(directory),
        "work_dir": str(work),
        "log_path": str(directory / "jasper.log"),
        "input_path": str(sv_file),
        "returncode": None,
        "source_task_id": source_task_id,
        "tool_task_id": task_id,
    }
    try:
        prepared = _prepare_formal_input(
            generated_assertion, reference_assertion, testbench, requirement, sv_file,
            dataset=dataset,
        )
    except _PecAdapterUnsupported as error:
        result.update(status="UNSUPPORTED_PEC_INPUT", error_origin="input_adapter")
        return _finish_result(result, str(error))
    except ValueError as error:
        message = str(error)
        if message.startswith("Generated assertion:"):
            result.update(error_origin="candidate", syntax=0.0, pec=0.0, relax_pec=0.0)
        elif message.startswith("Reference assertion:"):
            result["error_origin"] = "reference"
        else:
            result["error_origin"] = "testbench"
        return _finish_result(result, message)
    for key in ("generated_reset", "reference_reset", "reset_mismatch"):
        result[key] = prepared[key]

    result["comparison_inputs"] = {
        name: prepared[name]
        for name in ("candidate_expression", "reference_expression", "signal_list")
    }
    if prepared.get("input_adapter"):
        result["input_adapter"] = prepared["input_adapter"]
        result["signal_layout"] = prepared["signal_layout"]
        result["comparison_scope"] += " Unsigned packed inputs expanded into shared scalar bits."
        (directory / "pec_inputs.json").write_text(
            json.dumps({key: prepared[key] for key in (
                "original_comparison_inputs", "candidate_expression", "reference_expression",
                "signal_list", "input_adapter", "signal_layout",
            )}, indent=2) + "\n", encoding="utf-8",
        )
    # FVEval's scripts resolve pec/pec.tcle relative to this working directory.
    if fveval_dir is None:
        fveval = next(
            (parent / "FVEval" for parent in Path(__file__).resolve().parents
             if (parent / "FVEval").is_dir()),
            None,
        )
    else:
        fveval = Path(fveval_dir).expanduser().resolve()
    if fveval is None:
        result["status"] = "TOOL_ERROR"
        return _finish_result(
            result,
            "FVEval not found. Keep new_agent inside the repository or supply fveval_dir.",
        )
    tcl_file = fveval / "tool_scripts" / policy["tcl_file"]
    for required in (tcl_file, fveval / "tool_scripts" / "pec" / "pec.tcle"):
        if not required.is_file():
            result["status"] = "TOOL_ERROR"
            return _finish_result(result, f"Missing required file: {required}")

    shutil.copyfile(sv_file, work / f"{dataset}_{task_id}.sva")
    project = work / "jg" / task_id
    project.parent.mkdir()
    command = [
        str(jg_executable), "-fpv", "-batch", "-tcl", str(tcl_file),
        "-define", "LM_ASSERT_TEXT", prepared["candidate_expression"],
        "-define", "REF_ASSERT_TEXT", prepared["reference_expression"],
        "-define", "SIGNAL_LIST", prepared["signal_list"],
        "-define", "EXP_ID", dataset,
        "-define", "TASK_ID", task_id,
        "-define", "SV_DIR", str(work),
        "-proj", str(project), "-allow_unsupported_OS",
    ]
    result["command"] = command
    result["working_directory"] = str(fveval)
    try:
        completed = subprocess.run(
            command, cwd=fveval, capture_output=True, text=True, timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        result["status"] = "TIMEOUT"
        partial = []
        for part in (error.stdout, error.stderr):
            if isinstance(part, bytes):
                part = part.decode(errors="replace")
            if part:
                partial.append(part)
        output = "\n".join(partial)
        output += f"\nJASPER_TIMEOUT: exceeded {timeout_seconds} seconds"
        return _finish_result(result, output)
    except OSError as error:
        result["status"] = "TOOL_ERROR"
        return _finish_result(result, str(error))

    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    result["returncode"] = completed.returncode
    result.update(_parse_formal_result(output, completed.returncode))
    return _finish_result(result, output)


def cleanup_work(
    result: dict, keep_work: bool = False, *, preserve_unresolved: bool = True,
) -> dict:
    """Delete owned work; optionally retain unresolved checks for debugging."""
    work = Path(result["work_dir"])
    if not work.exists() and not work.is_symlink():
        return {"retained": False, "reason": "No work directory remains."}
    if keep_work:
        return {"retained": True, "reason": "KEEP_WORK is enabled."}
    if (result["status"] == "PEC_COMPILE_ERROR" or result.get("error_origin") in {"reference", "testbench"}):
        return {"retained": True, "reason": "Retained checker/reference failure for inspection."}
    if preserve_unresolved and result["status"] not in {
        "FULL_EQUIVALENCE", "IMPLIES", "NO_EQUIVALENCE", "SYNTAX_ERROR",
    }:
        return {
            "retained": True,
            "reason": "Retained for an unresolved tool or input result.",
        }

    directory = Path(result["run_dir"]).resolve()
    try:
        marker = work / "checker_owned.marker"
        if (
            work.is_symlink()
            or work.name != "_work"
            or work.resolve().parent != directory
            or not marker.is_file()
            or marker.read_text(encoding="utf-8") != str(directory)
        ):
            return {
                "retained": True,
                "reason": "Ownership check failed; no files were deleted.",
            }
        shutil.rmtree(work)
    except OSError as error:
        return {"retained": True, "reason": f"Cleanup failed: {error}"}
    return {"retained": False, "reason": "Owned work files removed."}


