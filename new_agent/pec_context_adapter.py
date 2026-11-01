"""Collect TB signals and constants for native PEC declaration adaptation.

Typed mode applies evaluated packed ranges, signedness and constants through
new_agent.typed_pec. Legacy modes remain available for baseline comparisons.
"""
from copy import deepcopy
from functools import lru_cache
from pathlib import Path
import os
import re

VERSION = "typed_tb_context_v2"


def context_mode():
    from new_agent import config
    return os.environ.get("FVRULE_PEC_CONTEXT_MODE",
                          getattr(config, "PEC_CONTEXT_MODE", "typed"))


def _type_info(typ):
    result = {"type": str(typ), "signed": bool(typ.isSigned),
              "four_state": bool(typ.isFourState),
              "unpacked_array": bool(typ.isUnpackedArray),
              "integral": bool(typ.isIntegral), "type_error": bool(typ.isError)}
    if typ.isIntegral and not typ.isError:
        result["bit_width"] = int(typ.bitWidth)
    dimensions = []
    current = typ.canonicalType
    while current.isPackedArray or current.isUnpackedArray:
        dimensions.append({"kind": "unpacked" if current.isUnpackedArray else "packed",
                           "range": str(getattr(current, "range", "dynamic_or_associative"))})
        current = current.elementType.canonicalType
    if dimensions:
        result["dimensions"] = dimensions
    return result


@lru_cache(maxsize=128)
def _collect(source, module_name):
    import pyslang
    from pyslang import syntax
    tree = syntax.SyntaxTree.fromText(source)
    compilation = pyslang.ast.Compilation()
    compilation.addSyntaxTree(tree)
    instances = list(compilation.getRoot().topInstances)
    if module_name:
        instances = [item for item in instances if item.name == module_name]
    if len(instances) != 1:
        raise ValueError("Expected one top module; set PEC_CONTEXT_MODULE for a multi-top context.")
    instance = instances[0]
    signals, constants = {}, {}
    for symbol in instance.body:
        kind = symbol.kind.name
        if kind not in {"Port", "Net", "Variable", "Parameter"} or not symbol.name:
            continue
        entry = {"name": symbol.name, "kind": kind, **_type_info(symbol.type)}
        if kind == "Parameter":
            entry.update(value=str(symbol.value), declaration=str(symbol.syntax).strip(),
                         localparam=bool(symbol.isLocalParam))
            constants[symbol.name] = entry
        else:
            signals[symbol.name] = entry
    return {"module": instance.name, "parser": "pyslang",
            "parser_version": pyslang.__version__,
            "signals": list(signals.values()), "parameters": list(constants.values()),
            "syntax_diagnostic_count": len(tree.diagnostics)}


def collect_context(source, module_name=None):
    return deepcopy(_collect(source, module_name))


def prepare_signal_list(testbench, native_signal_list, *, mode=None, module_name=None):
    """Keep legacy names; add module-scope integral signal/parameter names.

    Arrays, hierarchical scopes and unsupported native identifier spellings are
    reported, not flattened or injected as declaration strings. Failure to read
    context is recorded and leaves native evaluation available.
    """
    mode = mode or context_mode()
    if mode not in {"legacy", "expanded_names", "typed"}:
        raise ValueError("PEC_CONTEXT_MODE must be legacy, expanded_names or typed")
    original = list(dict.fromkeys(x.strip() for x in native_signal_list.split(",") if x.strip()))
    result = {"adapter_version": VERSION, "mode": mode,
              "native_signal_list": original, "effective_signal_list": list(original),
              "added_names": [], "not_added": [],
              "typed_context_applied": False,
              "note": "Only names are passed to native PEC; source types/constants are audit metadata."}
    if mode == "legacy":
        result["status"] = "legacy"
        return native_signal_list, result
    try:
        result["source_context"] = collect_context(testbench, module_name)
    except Exception as error:
        result.update(status="context_unavailable_native_names_retained",
                      error=f"{type(error).__name__}: {error}")
        return native_signal_list, result
    constants = {item['name'] for item in result['source_context']['parameters']}
    names = [name for name in original if mode != 'typed' or name not in constants]
    items = result["source_context"]["signals"]
    if mode != 'typed':
        items = items + result["source_context"]["parameters"]
    for item in items:
        name = item["name"]
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", name):
            reason = "unsupported_native_identifier"
        elif item["unpacked_array"] or not item["integral"] or item["type_error"]:
            reason = "unsupported_or_unresolved_native_type"
        else:
            reason = None
        if reason:
            result["not_added"].append({"name": name, "reason": reason})
        elif name not in names:
            names.append(name)
            result["added_names"].append(name)
    result.update(status="expanded", effective_signal_list=names)
    if mode == 'typed':
        result.update(status='typed_context_prepared',
                      constant_names=sorted(constants),
                      note='TB signals retain types; parameters become evaluated localparams. '
                           'No TB assignments, assumptions or state updates are copied.')
    return ",".join(names), result


def inspect_checker_context(sv_dir):
    """Read generated declarations when native PEC leaves a readable module."""
    paths = sorted((Path(sv_dir) / "jg").glob("*/pec/pec.sve"))
    if not paths:
        return {"status": "unavailable"}
    try:
        return {"status": "available", "context": collect_context(paths[-1].read_text())}
    except Exception as error:
        return {"status": "unavailable", "error": f"{type(error).__name__}: {error}"}

