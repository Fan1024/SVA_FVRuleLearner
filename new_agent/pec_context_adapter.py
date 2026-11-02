"""Prepare only the signal_list_text argument for FVRuleLearner's native PEC.

Never open, parse or rewrite PEC artifacts, declarations or Tcl scripts.
"""
from copy import deepcopy
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import re

VERSION = 'native_signal_list_v9_in_range_probe'


def declaration_entry(typ, name, profile):
    """Format a signal-list entry only for a server-verified declaration profile."""
    unpacked, packed = [], []
    current = typ.canonicalType
    while current.isUnpackedArray:
        dimension = str(getattr(current, 'range', ''))
        if not re.fullmatch(r'\[-?\d+:-?\d+\]', dimension):
            raise ValueError('Only fixed unpacked dimensions are supported')
        unpacked.append(dimension)
        current = current.elementType.canonicalType
    element = current
    while current.isPackedArray:
        packed.append(str(current.range))
        current = current.elementType.canonicalType
    structured = any(bool(getattr(current, field, False)) for field in ('isStruct', 'isUnion', 'isEnum'))
    if not element.isIntegral or element.isError or structured:
        raise ValueError('Only integral scalar/packed elements are supported')
    if not packed and element.bitWidth > 1:
        packed = [f'[{int(element.bitWidth)-1}:0]']
    base = 'logic' if element.isFourState else 'bit'
    if profile == 'range_fragments':
        if base != 'logic':
            raise ValueError('The range-fragment profile cannot specify a two-state base type')
        base = ''
    elif profile != 'full_declarations':
        raise ValueError('Unknown verified declaration profile')
    prefix = ' '.join(part for part in (base, 'signed' if element.isSigned else '', ''.join(packed)) if part)
    return ((prefix + ' ') if prefix else '') + name + (' ' + ''.join(unpacked) if unpacked else '')


def verified_interface_profile():
    """Use only a passing report tied to this exact native checker binary."""
    from new_agent import config
    location = getattr(config, 'PEC_TYPED_INTERFACE_REPORT', Path(__file__).with_name('pec_interface_probe.json'))
    if not location:
        return None, 'Typed-interface report disabled; using names only.'
    path = Path(location)
    if not path.is_file():
        return None, 'No verified interface report; using names only.'
    try:
        report = json.loads(path.read_text())
        checker = Path(__file__).resolve().parents[1] / 'FVEval' / 'tool_scripts' / 'pec' / 'pec.tcle'
        profile = report.get('verified_profile')
        if (report.get('schema_version') == 1 and report.get('verified') is True and
                profile in {'range_fragments', 'full_declarations'} and
                report.get('checker_sha256') == hashlib.sha256(checker.read_bytes()).hexdigest()):
            return profile, 'Using a declaration profile verified by server controls.'
        return None, 'Report is unverified or belongs to another checker; using names only.'
    except (OSError, ValueError, TypeError) as error:
        return None, f'Interface report unavailable ({type(error).__name__}); using names only.'


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
    declarations = {profile: {} for profile in ('range_fragments', 'full_declarations')}
    for symbol in instances[0].body:
        if not symbol.name:
            continue
        kind = symbol.kind.name
        target = signals if kind in {'Port', 'Net', 'Variable'} else parameters if kind == 'Parameter' else None
        if target is not None and symbol.name not in target:
            target.append(symbol.name)
        if kind in {'Port', 'Net', 'Variable'}:
            for profile, entries in declarations.items():
                try:
                    entries[symbol.name] = declaration_entry(symbol.type, symbol.name, profile)
                except ValueError:
                    entries[symbol.name] = None
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
            'signals': signals, 'parameters': parameters, 'parameter_literals': literals,
            'declarations': declarations}


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
    A verified profile supplies TB declarations through the original argument.
    The native PEC implementation continues to create its own checker files.
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
    profile, note = verified_interface_profile()
    audit.update(typed_interface_profile=None, typed_interface_note=note)
    entries = names
    if profile:
        declarations = collected['declarations'][profile]
        unsupported = [name for name in names if name not in declarations or declarations[name] is None]
        if unsupported:
            audit['typed_interface_note'] = 'Unsupported declarations in this case; using names only: ' + ', '.join(unsupported)
        else:
            entries = [declarations[name] for name in names]
            audit['typed_interface_profile'] = profile
    audit['effective_signal_entries'] = entries
    return ','.join(entries), audit
