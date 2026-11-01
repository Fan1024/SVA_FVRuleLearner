"""Translate pyslang's SVA syntax structure into localization nodes.

Unsupported translations fail explicitly; the caller retains original source.
No custom precedence parser is used as a silent fallback.
"""
import re


def parse_assertion(assertion):
    from new_agent.assertion_tree import Node, ParseError, BINDING, UNARY, SAMPLED_CALLS
    try:
        import pyslang
    except ImportError as error:
        raise ParseError('pyslang is required; install requirements_new_agent.txt') from error
    text = assertion.strip()
    wrapped = bool(re.search(r'\bassert\s+property\s*\(', text))
    statement = text if wrapped else 'assert property (' + text + ');'
    source = 'module __fvrule_tree;\n' + statement + '\nendmodule'
    raw = source.encode('utf-8')
    tree = pyslang.syntax.SyntaxTree.fromText(source)
    if len(tree.diagnostics):
        raise ParseError('pyslang reported assertion syntax diagnostics; use original source.')
    members = list(tree.root.members)
    if len(members) != 1 or members[0].kind.name != 'ConcurrentAssertionMember':
        raise ParseError('Expected exactly one concurrent property assertion.')
    action = members[0].statement
    if action.kind.name != 'AssertPropertyStatement':
        raise ParseError('Expected assert property.')
    spec = action.propertySpec

    def exact(node):
        return raw[node.sourceRange.start.offset:node.sourceRange.end.offset].decode()

    def token(value):
        return value.valueText

    def make(node, kind, value='', category='', children=None, attributes=None):
        return Node(kind, value, category, children or [], attributes or {}, exact(node))

    def bound(node):
        value = exact(node).strip()
        if node.kind.name.endswith('RangeSelect') and not value.startswith('['):
            value = '[' + value + ']'
        return value

    def translate(node):
        kind = node.kind.name
        if kind in {'SimplePropertyExpr', 'ParenthesizedPropertyExpr', 'ParenthesizedSequenceExpr'}:
            return translate(node.expr)
        if kind == 'ParenthesizedExpression':
            return translate(node.expression)
        if kind == 'SimpleSequenceExpr':
            result = translate(node.expr)
            repetition = node.repetition
            if repetition:
                selector = repetition.selector
                value = exact(selector).strip() if selector else ''
                value = value.removeprefix('[').removesuffix(']')
                mode = token(repetition.op)
                result = make(node, 'sequence_repetition', '[' + mode + ']', 'temporal', [result],
                              {'mode': mode, 'bounds': value})
            return result
        if kind in {'IdentifierName', 'SystemName'}:
            return make(node, 'identifier', exact(node), 'unresolved_identifier')
        if kind == 'IdentifierSelectName':
            result = Node('identifier', token(node.identifier), 'unresolved_identifier',
                          source_expression=token(node.identifier))
            for element in node.selectors:
                selection = element.selector
                if selection.kind.name == 'BitSelect':
                    children, mode = [translate(selection.expr)], 'index'
                elif selection.kind.name.endswith('RangeSelect'):
                    children, mode = [translate(selection.left), translate(selection.right)], token(selection.range)
                else:
                    raise ParseError('Unsupported pyslang selector: ' + selection.kind.name)
                result = make(node, 'select', '[]', 'structural', [result, *children], {'mode': mode})
            return result
        if kind.endswith('LiteralExpression') or kind == 'IntegerVectorExpression':
            return make(node, 'literal', exact(node), 'literal')
        if kind == 'InvocationExpression':
            arguments = []
            if node.arguments:
                for argument in node.arguments.parameters:
                    if argument.kind.name == 'Comma':
                        continue
                    if argument.kind.name != 'OrderedArgument' or argument.expr is None:
                        raise ParseError('Named/empty call arguments use source-only localization.')
                    arguments.append(translate(argument.expr))
            name = exact(node.left).strip()
            if name in {'strong', 'weak'}:
                return make(node, 'temporal_operator', name, 'temporal', arguments)
            category = ('sampled_value_function' if name in SAMPLED_CALLS else
                        'system_function' if name.startswith('$') else 'function')
            return make(node, 'function_call', name, category, arguments)
        if kind == 'ConcatenationExpression':
            return make(node, 'concatenation', '{}', 'structural',
                        [translate(item) for item in node.expressions if item.kind.name != 'Comma'])
        if kind == 'MultipleConcatenationExpression':
            return make(node, 'replication', '{}', 'structural',
                        [translate(node.expression), translate(node.concatenation)])
        if kind == 'ConditionalExpression':
            conditions = list(node.predicate.conditions)
            if len(conditions) != 1 or conditions[0].kind.name != 'ConditionalPattern':
                raise ParseError('Unsupported conditional pattern.')
            return make(node, 'conditional_operator', '?:', 'conditional',
                        [translate(conditions[0].expr), translate(node.left), translate(node.right)])
        if kind == 'DelayedSequenceExpr':
            result = translate(node.first) if node.first else None
            for item in node.elements:
                rhs = translate(item.expr)
                result = make(node, 'sequence_delay', '##', 'temporal',
                              [result, rhs] if result else [rhs],
                              {'bounds': bound(item.range or item.delayVal), 'prefix': result is None})
            return result
        if hasattr(node, 'operand') and hasattr(node, 'operatorToken'):
            op = token(node.operatorToken)
            return make(node, 'unary_operator', op, UNARY.get(op, 'arithmetic'), [translate(node.operand)])
        if kind == 'UnaryPropertyExpr':
            return make(node, 'temporal_operator', token(node.op), 'temporal', [translate(node.expr)])
        if kind == 'StrongWeakPropertyExpr':
            return make(node, 'temporal_operator', token(node.keyword), 'temporal', [translate(node.expr)])
        if hasattr(node, 'left') and hasattr(node, 'right'):
            operator = getattr(node, 'operatorToken', None) or getattr(node, 'op', None)
            if operator is not None:
                op = token(operator)
                category = BINDING.get(op, (0, '', 'temporal'))[2]
                return make(node, 'binary_operator', op, category, [translate(node.left), translate(node.right)])
        raise ParseError('Unsupported pyslang localization node: ' + kind)

    try:
        context = {}
        if spec.clocking:
            event = spec.clocking.expr
            if event.kind.name == 'ParenthesizedEventExpression':
                event = event.expr
            if event.kind.name != 'SignalEventExpression' or not event.edge or event.iffClause:
                raise ParseError('Complex clock event uses source-only localization.')
            context['clock'] = {'edge': token(event.edge), 'expression': translate(event.expr)}
        if spec.disable:
            context['disable_iff'] = translate(spec.disable.expr)
        return translate(spec.expr), context
    except ParseError:
        raise
    except (AttributeError, TypeError, ValueError) as error:
        raise ParseError('Unsupported pyslang localization structure: ' + str(error)) from error

