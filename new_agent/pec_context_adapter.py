"""Prepare only the signal_list_text argument for FVRuleLearner's native PEC.

Never open, parse or rewrite PEC artifacts, declarations or Tcl scripts.
"""
from copy import deepcopy
from functools import lru_cache
import os
import re

VERSION = 'native_signal_list_v6_constant_bindings'


def context_mode(value=None):
    from new_agent import config
    value = value or os.environ.get('FVRULE_PEC_CONTEXT_MODE',
                                   getattr(config, 'PEC_CONTEXT_MODE', 'expanded_names'))
    # An old user config/environment must not reactivate the removed adapter.
    if value == 'typed':
        value = 'expanded_names'
    if value not in {'legacy', 'expanded_names'}:
        raise ValueError('PEC_CONTEXT_MODE must be legacy or expanded_names')
    return value


@lru_cache(maxsize=128)
def _collect(source, module_name):
    import pyslang
    tree = pyslang.syntax.SyntaxTree.fromText(source)
    compilation = pyslang.ast.Compilation()
    compilation.addSyntaxTree(tree)
    instances = list(compilation.getRoot().topInstances)
    if module_name:
        instances = [item for item in instances if item.name == module_name]
    if len(instances) != 1:
        raise ValueError('Expected one TB top module; set PEC_CONTEXT_MODULE for multiple tops.')
    signals, parameters, literals = [], [], {}
    for symbol in instances[0].body:
        if not symbol.name:
            continue
        kind = symbol.kind.name
        target = signals if kind in {'Port', 'Net', 'Variable'} else parameters if kind == 'Parameter' else None
        if target is not None and symbol.name not in target:
            target.append(symbol.name)
        if kind == 'Parameter':
            literal = None
            try:
                if symbol.type.isIntegral and not symbol.type.isError:
                    value = symbol.value.value
                    if not value.hasUnknown:
                        bits = int(symbol.type.bitWidth)
                        unsigned_value = int(value) & ((1 << bits) - 1)
                        literal = f"{bits}'{'s' if symbol.type.isSigned else ''}h{unsigned_value:x}"
            except (AttributeError, TypeError, ValueError, OverflowError):
                pass
            literals[symbol.name] = literal
    return {'module': instances[0].name, 'parser_version': pyslang.__version__,
            'signals': signals, 'parameters': parameters, 'parameter_literals': literals}


def collect_signal_names(testbench, module_name=None):
    return deepcopy(_collect(testbench, module_name))


def bind_parameter_constants(formula, testbench, module_name=None):
    """Bind bare TB parameter identifiers in a PEC argument, never a checker file.

    Use the same elaborated default TB instance as name collection. Sized signed
    or unsigned literals preserve integral value, width and signedness. Original
    assertions stay unchanged; both comparison arguments get identical bindings.
    """
    from new_agent.pec_input_adapter import _tokens, ExtractionError
    literals = collect_signal_names(testbench, module_name)['parameter_literals']
    tokens = _tokens(formula)
    replacements, bindings = [], {}
    for index, token in enumerate(tokens):
        name = token.text
        if name not in literals:
            continue
        previous = tokens[index - 1].text if index else ''
        # Keep literal digits, member names, scoped names and macros untouched.
        scoped_left = index >= 2 and previous == ':' and tokens[index - 2].text == ':'
        scoped_right = [item.text for item in tokens[index + 1:index + 3]] == [':', ':']
        if previous in {"'", '.', '`'} or scoped_left or scoped_right:
            continue
        literal = literals[name]
        if literal is None:
            raise ExtractionError(f'TB parameter {name} cannot be represented by a known integral literal.')
        replacements.append((token.start, token.end, literal))
        bindings[name] = literal
    result = formula
    for start, end, literal in reversed(replacements):
        result = result[:start] + literal + result[end:]
    return result, bindings


def prepare_signal_list(testbench, native_signal_list, *, mode=None, module_name=None):
    """Replace a quoted-name list with its union with declared TB signal names.

    Known parameters/localparams are excluded: they are constants, not signals.
    Widths and declarations remain entirely under the native PEC implementation.
    """
    mode = context_mode(mode)
    original = list(dict.fromkeys(name.strip() for name in native_signal_list.split(',') if name.strip()))
    audit = {'adapter_version': VERSION, 'mode': mode, 'native_signal_list': original,
             'effective_signal_list': list(original), 'added_names': [],
             'removed_parameters': [], 'not_added': [],
             'note': 'Signal names only; TB constants are bound in the property arguments. Native Tcl/PEC files stay unchanged.'}
    if mode == 'legacy':
        audit['status'] = 'native_names_unchanged'
        return native_signal_list, audit
    collected = collect_signal_names(testbench, module_name)
    parameters = set(collected['parameters'])
    names = [name for name in original if name not in parameters]
    audit.update(module=collected['module'], parser_version=collected['parser_version'],
                 removed_parameters=[name for name in original if name in parameters])
    for name in collected['signals']:
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_$]*', name):
            audit['not_added'].append({'name': name, 'reason': 'unsupported_native_identifier'})
        elif name not in names:
            names.append(name)
            audit['added_names'].append(name)
    audit.update(status='signal_names_expanded', effective_signal_list=names)
    return ','.join(names), audit
