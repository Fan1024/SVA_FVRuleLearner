"""Apply TB types/constants to the native generated PEC module before analysis.

The native encrypted checker, assertions and scoring are unchanged. Only its
generated declarations are adapted. TB assignments/assumptions are not copied.
"""
from pathlib import Path
import json
import re
import sys

MARKER = '// FVRULE_TYPED_CONTEXT_v2_fixed_arrays'


class ContextPreparationError(ValueError):
    pass


def sv_type(item):
    from new_agent.pec_context_adapter import supported_context_type
    if not supported_context_type(item):
        raise ContextPreparationError(f"Unsupported PEC type for {item['name']}: {item['type']}")
    base = 'logic' if item.get('element_four_state', item.get('four_state', True)) else 'bit'
    if item.get('element_signed', item.get('signed')):
        base += ' signed'
    dimensions = [d for d in item.get('dimensions', []) if d['kind'] == 'packed']
    if dimensions:
        base += ' ' + ''.join(d['range'] for d in dimensions)
    elif item.get('packed_bit_width', item.get('bit_width', 1)) > 1:
        width = item.get('packed_bit_width', item.get('bit_width', 1))
        base += f" [{width - 1}:0]"
    return base


def sv_name(item):
    ranges = ''.join(d['range'] for d in item.get('dimensions', []) if d['kind'] == 'unpacked')
    return item['name'] + (' ' + ranges if ranges else '')


def _module(source):
    import pyslang
    tree = pyslang.syntax.SyntaxTree.fromText(source)
    if len(tree.diagnostics):
        raise ContextPreparationError('Native PEC source has syntax diagnostics before declaration adaptation.')
    root = tree.root
    modules = [root] if root.kind.name == 'ModuleDeclaration' else [
        item for item in root.members if item.kind.name == 'ModuleDeclaration']
    if len(modules) != 1:
        raise ContextPreparationError('Expected one native PEC module.')
    compilation = pyslang.ast.Compilation()
    compilation.addSyntaxTree(tree)
    instances = list(compilation.getRoot().topInstances)
    if len(instances) != 1:
        raise ContextPreparationError('Cannot identify the native PEC top module.')
    return modules[0], instances[0]


def rewrite_checker(source, context):
    """Support ANSI/non-ANSI ports and grouped net/data declarations.

    Preserve native checker control logic and property source verbatim. Resolve
    packed dimensions and constants from the elaborated TB default instance.
    """
    if MARKER in source:
        return source
    from new_agent.pec_context_adapter import _type_info, supported_context_type
    module, instance = _module(source)
    signals = {item['name']: item for item in context['signals'] if supported_context_type(item)}
    constants = {item['name']: item for item in context['parameters']}
    for item in constants.values():
        if item.get('unpacked_array'):
            raise ContextPreparationError(f"Array parameter needs a constant initializer adapter: {item['name']}")
        sv_type(item)
        if not re.fullmatch(r"[-+0-9a-fA-F_xXzZ?'sSbBoOdDhH\s]+", item['value']):
            raise ContextPreparationError(f"Unresolved constant {item['name']}: {item['value']}")
    ports = []
    port_seen = set()
    for symbol in instance.body:
        if symbol.kind.name != 'Port' or symbol.name in constants:
            continue
        if symbol.name in port_seen:
            continue
        port_seen.add(symbol.name)
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_$]*', symbol.name):
            raise ContextPreparationError('Unsupported native port name.')
        direction = {'In': 'input', 'Out': 'output', 'InOut': 'inout'}.get(symbol.direction.name)
        if direction is None:
            raise ContextPreparationError('Unsupported native port direction.')
        item = signals.get(symbol.name) or {'name': symbol.name, **_type_info(symbol.type)}
        ports.append((symbol.name, direction, item))
    port_names = {p[0] for p in ports}
    declarations = [f"localparam {sv_type(item)} {name} = {item['value']};"
                    for name, item in constants.items()]
    declarations += [f'{direction} {sv_type(item)} {sv_name(item)};' for name, direction, item in ports]
    seen = set(port_names)
    members = []
    for member in module.members:
        kind = member.kind.name
        if kind == 'PortDeclaration':
            continue
        target = member.parameter if kind == 'ParameterDeclarationStatement' else member
        if kind not in {'DataDeclaration', 'NetDeclaration', 'ParameterDeclarationStatement'}:
            members.append(str(member))
            continue
        declarators = [d for d in target.declarators if getattr(d, 'kind', None).name == 'Declarator']
        if not declarators:
            members.append(str(member))
            continue
        # A declaration prefix can contain dimensions/qualifiers; retain it for
        # native names not supplied by the TB. Never reconstruct property text.
        first = declarators[0]
        prefix = source.encode('utf-8')[target.sourceRange.start.offset:first.sourceRange.start.offset].decode()
        for declaration in declarators:
            name = declaration.name.valueText
            if name in constants or name in port_names:
                continue
            seen.add(name)
            if name in signals:
                net = (str(member.netType).strip() + ' ') if kind == 'NetDeclaration' else ''
                initializer = str(declaration.initializer) if declaration.initializer else ''
                members.append(f'{net}{sv_type(signals[name])} {sv_name(signals[name])}{initializer};')
            else:
                members.append(prefix + str(declaration).strip() + ';')
    declarations += [f'{sv_type(item)} {sv_name(item)};' for name, item in signals.items() if name not in seen]
    name = module.header.name.valueText
    params = str(module.header.parameters) if module.header.parameters else ''
    header = f"module {name}{params} ({', '.join(p[0] for p in ports)});"
    ending = str(module.endmodule) + (str(module.blockName) if module.blockName else '')
    adapted = '\n'.join([header, *declarations, *members, ending])
    # pyslang offsets are byte offsets; generated sources normally are ASCII.
    # Decode the slices to avoid corrupting comments containing Unicode.
    raw = source.encode('utf-8')
    start, end = module.sourceRange.start.offset, module.sourceRange.end.offset
    return raw[:start].decode() + MARKER + '\n' + adapted + raw[end:].decode()


def adapt_file(checker_path, manifest_path):
    checker = Path(checker_path)
    manifest = json.loads(Path(manifest_path).read_text(encoding='utf-8'))
    source = checker.read_text(encoding='utf-8')
    adapted = rewrite_checker(source, manifest['source_context'])
    if source != adapted:
        checker.with_name('pec.native.sve').write_text(source, encoding='utf-8')
        checker.write_text(adapted, encoding='utf-8')
    audit = Path(manifest_path).with_suffix('.applied.json')
    audit.write_text(json.dumps({'typed_context_applied': True, 'checker': str(checker),
                                 'constant_names': manifest.get('constant_names', [])}, indent=2), encoding='utf-8')


def prepare_launcher(bound, preparation, directory):
    """Use a temporary Tcl entry point with the original native launcher.

    The launcher derives cwd from the Tcl path, so provide a shadow tool_scripts
    directory with links to the native dependencies. No repository files change.
    """
    if preparation['mode'] != 'typed':
        return
    if 'source_context' not in preparation:
        raise ContextPreparationError(preparation.get('error', 'TB context unavailable. Install pyslang.'))
    unsupported = preparation.get('unsupported_required_declarations', [])
    if unsupported:
        raise ContextPreparationError('Referenced TB declarations cannot be represented: ' +
                                      ', '.join(f"{x['name']} ({x['type']})" for x in unsupported))
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    manifest = directory / 'typed_context.json'
    manifest.write_text(json.dumps(preparation, indent=2), encoding='utf-8')
    original = Path(bound.arguments['tcl_file_path']).resolve()
    scripts = directory / 'native_overlay' / 'tool_scripts'
    scripts.mkdir(parents=True, exist_ok=True)
    for item in original.parent.iterdir():
        destination = scripts / item.name
        if not destination.exists():
            destination.symlink_to(item, target_is_directory=item.is_dir())
    # JSON strings are safe Python literals; JSON escapes non-ASCII paths.
    python_code = ('import sys; sys.path.insert(0, ' + repr(str(Path(__file__).resolve().parents[1])) + '); '
                   'from new_agent.typed_pec import adapt_file; adapt_file(sys.argv[1], sys.argv[2])')
    values = [sys.executable, '-c', python_code]
    # hex values avoid Tcl interpolation of paths or Python source.
    decode = lambda value: '[encoding convertfrom utf-8 [binary format H* {' + value.encode().hex() + '}]]'
    assignments = '\n'.join(f'set ::fvrule_{key} {decode(value)}' for key, value in {
        'python': values[0], 'code': python_code, 'manifest': str(manifest)}.items())
    entry = scripts / 'fvrule_typed_entry.tcl'
    entry.write_text(assignments + '''
rename ::analyze ::fvrule_native_analyze
proc ::analyze {args} {
    foreach argument $args {
        if {[file tail $argument] eq "pec.sve" && [file isfile $argument]} {
            if {[catch {exec $::fvrule_python -c $::fvrule_code $argument $::fvrule_manifest 2>@1} message]} {
                puts stderr "FVRULE_PEC_CONTEXT_ERROR: $message"
                error "FVRULE_PEC_CONTEXT_ERROR: declaration adaptation failed"
            }
        }
    }
    return [uplevel 1 [linsert $args 0 ::fvrule_native_analyze]]
}
''' + 'source ' + decode(str(original)) + '\n', encoding='utf-8')
    bound.arguments['tcl_file_path'] = str(entry)
    preparation['typed_manifest'] = str(manifest)


def read_applied(preparation):
    path = preparation.get('typed_manifest')
    if path:
        audit = Path(path).with_suffix('.applied.json')
        if audit.is_file():
            preparation.update(json.loads(audit.read_text(encoding='utf-8')))


def candidate_testbench(testbench, assertion, module_name=None):
    """Insert the complete candidate into the TB compiled by native Human/Machine Tcl."""
    import pyslang
    tree = pyslang.syntax.SyntaxTree.fromText(testbench)
    root = tree.root
    modules = [root] if root.kind.name == 'ModuleDeclaration' else [
        item for item in root.members if item.kind.name == 'ModuleDeclaration']
    if module_name:
        modules = [item for item in modules if item.header.name.valueText == module_name]
    if len(modules) != 1:
        raise ContextPreparationError('Candidate compilation requires one TB module; set PEC_CONTEXT_MODULE.')
    position = modules[0].endmodule.location.offset
    raw = testbench.encode('utf-8')
    return (raw[:position].decode() + '\n// Generated candidate for native SYN checking\n'
            + assertion + '\n' + raw[position:].decode())

