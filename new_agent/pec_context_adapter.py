"""Prepare only the signal_list_text argument for FVRuleLearner's native PEC.

Never open, parse or rewrite PEC artifacts, declarations or Tcl scripts.
"""
from copy import deepcopy
from functools import lru_cache
import os
import re

VERSION = 'native_signal_list_v5'


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
    signals, parameters = [], []
    for symbol in instances[0].body:
        if not symbol.name:
            continue
        kind = symbol.kind.name
        target = signals if kind in {'Port', 'Net', 'Variable'} else parameters if kind == 'Parameter' else None
        if target is not None and symbol.name not in target:
            target.append(symbol.name)
    return {'module': instances[0].name, 'parser_version': pyslang.__version__,
            'signals': signals, 'parameters': parameters}


def collect_signal_names(testbench, module_name=None):
    return deepcopy(_collect(testbench, module_name))


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
             'note': 'Names only. Original native Tcl/PEC files and launcher path are unchanged.'}
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
