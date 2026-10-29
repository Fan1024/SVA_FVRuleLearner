"""Raw SVA trees for training: names, literals and original source are retained.

Grouping parentheses determine ordered child links, not extra nodes. This is
our checked prototype subset, not a full SV compiler. Unsupported syntax is
reported explicitly; the caller can send original source with that error.
Rendered expression strings are diagnostic, not lossless source text.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
import json
import re
import sys

class ParseError(ValueError):
    pass

@dataclass
class Token:
    text: str
    start: int

@dataclass
class Node:
    kind: str
    value: str = ''
    category: str = ''
    children: list['Node'] = field(default_factory=list)
    attributes: dict = field(default_factory=dict)

TOKEN = re.compile(
    r"(?P<space>\s+)|(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)|"
    r"(?P<literal>\d*\s*'[sS]?[bBoOdDhH]\s*[0-9a-fA-F_xXzZ?]+|'[01xXzZ]|\d+(?:\.\d+)?)|"
    r"(?P<identifier>\$?[A-Za-z_][\w$]*|\\[^\s]+)|"
    r"(?P<operator>\|->|\|=>|===|!==|==\?|!=\?|>>>|<<<|&&|\|\||==|!=|<=|>=|<<|>>|\*\*|##|->|~&|~\||~\^|\^~|\+:|-:|[(){}\[\],:;?.@!~+*/%<>&|^=$-])"
)

BINDING = {
    '|->': (20, 'right', 'implication'), '|=>': (20, 'right', 'implication'),
    '##': (60, 'left', 'temporal'),
    '||': (90, 'left', 'logical'), '&&': (100, 'left', 'logical'),
    '|': (110, 'left', 'bitwise'), '^': (120, 'left', 'bitwise'),
    '~^': (120, 'left', 'bitwise'), '^~': (120, 'left', 'bitwise'),
    '&': (130, 'left', 'bitwise'),
    '==': (140, 'left', 'comparison'), '!=': (140, 'left', 'comparison'),
    '===': (140, 'left', 'comparison'), '!==': (140, 'left', 'comparison'),
    '==?': (140, 'left', 'comparison'), '!=?': (140, 'left', 'comparison'),
    '<': (150, 'left', 'comparison'), '<=': (150, 'left', 'comparison'),
    '>': (150, 'left', 'comparison'), '>=': (150, 'left', 'comparison'),
    '<<': (160, 'left', 'bitwise'), '>>': (160, 'left', 'bitwise'),
    '<<<': (160, 'left', 'bitwise'), '>>>': (160, 'left', 'bitwise'),
    '+': (170, 'left', 'arithmetic'), '-': (170, 'left', 'arithmetic'),
    '*': (180, 'left', 'arithmetic'), '/': (180, 'left', 'arithmetic'), '%': (180, 'left', 'arithmetic'),
    '**': (190, 'left', 'arithmetic'),
}

UNARY = {'!': 'logical', '~': 'bitwise', '+': 'arithmetic', '-': 'arithmetic',
         '&': 'reduction', '~&': 'reduction', '|': 'reduction', '~|': 'reduction',
         '^': 'reduction', '~^': 'reduction', '^~': 'reduction'}

TEMPORAL_CALLS = {'strong', 'weak'}

SAMPLED_CALLS = {'$past', '$stable', '$rose', '$fell', '$changed', '$sampled'}

UNSUPPORTED_WORDS = {'and','or','not','iff','until','s_until','until_with','s_until_with',
                     'throughout','intersect','within','first_match','eventually',
                     's_always','always','nexttime','s_nexttime','accept_on','reject_on','disable'}

def tokenize(text: str) -> list[Token]:
    result, pos = [], 0
    while pos < len(text):
        match = TOKEN.match(text, pos)
        if not match:
            raise ParseError(f'Unsupported syntax near character {pos}: {text[pos:pos+35]!r}')
        if match.lastgroup not in {'space','comment'}:
            result.append(Token(match.group(), pos))
        pos = match.end()
    return result

class Parser:
    def __init__(self, tokens: list[Token]):
        self.tokens, self.pos = tokens, 0

    def peek(self):
        return self.tokens[self.pos].text if self.pos < len(self.tokens) else ''

    def pop(self, expected=None):
        value = self.peek()
        if not value or (expected is not None and value != expected):
            raise ParseError(f'Expected {expected or "expression"!r}, got {value or "end of input"!r} at token {self.pos}')
        self.pos += 1
        return value

    def parse(self):
        root = self.expr()
        if self.pos != len(self.tokens):
            raise ParseError(f'Unsupported trailing syntax: {self.peek()!r} at token {self.pos}')
        return root

    def bounds(self):
        if self.peek() != '[':
            value = self.pop()
            if not re.fullmatch(r'\d+|[A-Za-z_]\w*', value):
                raise ParseError('Delay bound must be an integer or a constant name')
            return value
        self.pop('[')
        parts = []
        while self.peek() and self.peek() != ']':
            part = self.pop()
            if not re.fullmatch(r'\d+|[A-Za-z_]\w*|\$|:', part):
                raise ParseError('Unsupported delay range expression')
            parts.append(part)
        self.pop(']')
        value = ''.join(parts)
        atom = r'\d+|[A-Za-z_]\w*'
        valid = (len(parts)==1 and re.fullmatch(atom,parts[0])) or (
            len(parts)==3 and parts[1]==':' and re.fullmatch(atom,parts[0]) and
            (re.fullmatch(atom,parts[2]) or parts[2]=='$'))
        if not valid:
            raise ParseError('Malformed delay range')
        return '[' + value + ']'

    def expr(self, minimum=0):
        token = self.pop()
        if token == '(':
            left = self.expr(); self.pop(')')
        elif token in UNARY:
            left = Node('unary_operator', token, UNARY[token], [self.expr(200)])
        elif token == 's_eventually':
            # Property prefix, NOT a function call: its operand can include a
            # following implication. Keep the observed parenthesized form only.
            if self.peek() != '(':
                raise ParseError('Only parenthesized s_eventually(expression) is supported')
            left = Node('temporal_operator', token, 'temporal', [self.expr(10)])
        elif token == '##':
            bound = self.bounds()
            left = Node('sequence_delay', '##', 'temporal', [self.expr(61)], {'bounds':bound, 'prefix':True})
        elif token == '{':
            first = self.expr()
            if self.peek() == '{':
                self.pop('{'); members = [self.expr()]
                while self.peek() == ',': self.pop(','); members.append(self.expr())
                self.pop('}'); self.pop('}')
                left = Node('replication', '{}', 'structural', [first, Node('concatenation','{}','structural',members)])
            else:
                members = [first]
                while self.peek() == ',': self.pop(','); members.append(self.expr())
                self.pop('}'); left = Node('concatenation','{}','structural',members)
        elif re.fullmatch(r"\d*\s*'[sS]?[bBoOdDhH]\s*[0-9a-fA-F_xXzZ?]+|'[01xXzZ]|\d+(?:\.\d+)?", token):
            left = Node('literal', token, 'literal')
        elif re.fullmatch(r'\$?[A-Za-z_][\w$]*|\\[^\s]+', token):
            if token in UNSUPPORTED_WORDS:
                raise ParseError(f'Unsupported SVA construct: {token}')
            name = token
            while self.peek() == '.':
                self.pop('.')
                member = self.pop()
                if not re.fullmatch(r'[A-Za-z_][\w$]*', member): raise ParseError('Unsupported hierarchical name')
                name += '.' + member
            if self.peek() == '(':
                self.pop('('); args = []
                if self.peek() != ')':
                    args.append(self.expr())
                    while self.peek() == ',': self.pop(','); args.append(self.expr())
                self.pop(')')
                if name in TEMPORAL_CALLS:
                    if len(args) != 1: raise ParseError('Supported temporal constructs require one argument')
                    left = Node('temporal_operator', name, 'temporal', args)
                else:
                    category = 'sampled_value_function' if name in SAMPLED_CALLS else ('system_function' if name.startswith('$') else 'function')
                    left = Node('function_call', name, category, args)
            else:
                if name in TEMPORAL_CALLS:
                    raise ParseError(f'{name} requires a parenthesized argument in this prototype')
                if name.startswith('$'): raise ParseError('Unsupported bare system identifier')
                left = Node('identifier', name, 'unresolved_identifier')
        else:
            raise ParseError(f'Unsupported expression prefix: {token!r}')
        while True:
            token = self.peek()
            if token == '[':
                # Sequence repetition is different from an array/bit select.
                marker = self.tokens[self.pos + 1].text if self.pos + 1 < len(self.tokens) else ''
                if marker in {'*', '->', '='}:
                    self.pop('['); self.pop(marker)
                    parts = []
                    while self.peek() and self.peek() != ']':
                        parts.append(self.pop())
                    self.pop(']')
                    bound = ''.join(parts)
                    atom = r'(?:\d+|[A-Za-z_]\w*)'
                    valid = (len(parts)==1 and re.fullmatch(atom,parts[0])) or (
                        len(parts)==3 and parts[1]==':' and re.fullmatch(atom,parts[0]) and
                        (re.fullmatch(atom,parts[2]) or (marker=='*' and parts[2]=='$')))
                    if not valid and not (marker == '*' and not parts):
                        raise ParseError('Unsupported repetition bound; expected a simple constant/range')
                    left = Node('sequence_repetition', '[' + marker + ']', 'temporal', [left], {'mode':marker, 'bounds':bound})
                    continue
                self.pop('['); indices = [self.expr()]; mode='index'
                if self.peek() in {':','+:','-:'}:
                    mode=self.pop(); indices.append(self.expr())
                self.pop(']'); left = Node('select','[]','structural',[left]+indices,{'mode':mode})
                continue
            if token == '?' and 80 >= minimum:
                self.pop('?'); yes=self.expr(); self.pop(':'); no=self.expr(80)
                left=Node('conditional_operator','?:','conditional',[left,yes,no]); continue
            binding=BINDING.get(token)
            if binding is None or binding[0] < minimum: break
            power,assoc,category=binding; self.pop()
            if token == '##':
                bound=self.bounds(); right=self.expr(power+1)
                left=Node('sequence_delay','##','temporal',[left,right],{'bounds':bound,'prefix':False})
            else:
                right=self.expr(power if assoc=='right' else power+1)
                left=Node('binary_operator',token,category,[left,right])
        return left

def unwrap(assertion: str):
    tokens=tokenize(assertion); context={}
    # Optional assertion label followed by assert property(...).
    if len(tokens)>2 and tokens[1].text==':' and tokens[2].text=='assert': tokens=tokens[2:]
    if tokens and tokens[0].text=='assert':
        p=Parser(tokens);p.pop('assert');p.pop('property');p.pop('(')
        if p.peek()=='@':
            p.pop('@');p.pop('(')
            edge=p.pop()
            if edge not in {'posedge','negedge'}: raise ParseError('Only a simple edge clock is supported')
            clock_tokens=[]
            while p.peek() and p.peek()!=')': clock_tokens.append(Token(p.pop(),0))
            p.pop(')');context['clock']={'edge':edge,'expression':Parser(clock_tokens).parse()}
        if p.peek()=='disable':
            p.pop('disable');p.pop('iff');p.pop('(');reset=p.expr();p.pop(')');context['disable_iff']=reset
        root=p.expr();p.pop(')')
        if p.peek()==';':p.pop(';')
        if p.pos != len(tokens):raise ParseError('Expected exactly one assertion')
        return root,context
    return Parser(tokens).parse(),context


def render(node: Node) -> str:
    """Render exact names/values with explicit grouping. Never substitute leaves."""
    args = [render(child) for child in node.children]
    if node.kind in {'signal', 'parameter', 'literal', 'identifier'}:
        return node.value
    if node.kind == 'unary_operator':
        return f'{node.value}({args[0]})'
    if node.kind == 'binary_operator':
        return f'({args[0]} {node.value} {args[1]})'
    if node.kind == 'conditional_operator':
        return f'({args[0]} ? {args[1]} : {args[2]})'
    if node.kind in {'function_call', 'temporal_operator'}:
        return f'{node.value}(' + ', '.join(args) + ')'
    if node.kind == 'concatenation':
        return '{' + ', '.join(args) + '}'
    if node.kind == 'replication':
        return '{' + args[0] + args[1] + '}'
    if node.kind == 'select':
        index = args[1] if len(args) == 2 else args[1] + node.attributes['mode'] + args[2]
        return args[0] + '[' + index + ']'
    if node.kind == 'sequence_delay':
        delay = '##' + node.attributes['bounds']
        return f'{delay} {args[0]}' if node.attributes['prefix'] else f'({args[0]} {delay} {args[1]})'
    if node.kind == 'sequence_repetition':
        return f"({args[0]})[{node.attributes['mode']}{node.attributes['bounds']}]"
    raise ParseError(f'Cannot render node kind {node.kind!r}')


def child_role(node: Node, index: int) -> str:
    """An ordered edge label: distinguishes left/right, trigger/response, arguments."""
    if node.kind == 'binary_operator':
        return ('antecedent', 'consequent')[index] if node.category == 'implication' else ('left', 'right')[index]
    if node.kind == 'conditional_operator':
        return ('condition', 'if_true', 'if_false')[index]
    if node.kind == 'function_call':
        return f'argument_{index}'
    if node.kind in {'unary_operator', 'temporal_operator', 'sequence_repetition'}:
        return 'operand'
    if node.kind == 'sequence_delay':
        return 'delayed_sequence' if node.attributes['prefix'] else ('before_delay', 'after_delay')[index]
    if node.kind == 'select':
        return 'base' if index == 0 else f'index_{index-1}'
    if node.kind == 'replication':
        return ('repeat_count', 'members')[index]
    return f'member_{index}'


OPERATION_KINDS = {
    'binary_operator', 'unary_operator', 'conditional_operator',
    'function_call', 'temporal_operator', 'sequence_delay', 'sequence_repetition',
}


def flatten(root: dict) -> list[dict]:
    """Preorder walk; the saved root itself retains all nested branch relationships."""
    return [root] + [node for child in root['children'] for node in flatten(child)]


def build_tree(assertion: str, prefix: str, parameters=()) -> dict:
    """Parse a body/full assertion and export an in-memory, completely unmasked tree."""
    root, raw_context = unwrap(assertion)
    parameters = set(parameters)

    def classify(node):
        if node.kind == 'identifier':
            node.kind = 'parameter' if node.value in parameters else 'signal'
            node.category = node.kind
        for child in node.children:
            classify(child)

    classify(root)
    if 'clock' in raw_context:
        classify(raw_context['clock']['expression'])
    if 'disable_iff' in raw_context:
        classify(raw_context['disable_iff'])

    def export_tree(tree_root, tree_prefix):
        serial = 0

        def export(node, depth=0, parent_id=None, index=None, role='root'):
            nonlocal serial
            node_id = f'{tree_prefix}_n{serial}'
            serial += 1
            result = {
                'id': node_id,
                'kind': node.kind,
                'category': node.category,
                'value': node.value,
                'depth': depth,
                'parent_id': parent_id,
                'child_index': index,
                'operand_role': role,
                'expression': render(node),
            }
            if node.attributes:
                result['attributes'] = dict(node.attributes)
            result['children'] = [
                export(child, depth+1, node_id, i, child_role(node, i))
                for i, child in enumerate(node.children)
            ]
            result['child_ids'] = [child['id'] for child in result['children']]
            return result

        return export(tree_root)

    tree = export_tree(root, prefix)
    body_nodes = flatten(tree)
    context = {}
    context_nodes = []
    if 'clock' in raw_context:
        raw_clock = raw_context['clock']
        clock_tree = export_tree(raw_clock['expression'], prefix + '_clock')
        context['clock'] = {'edge': raw_clock['edge'], 'expression': render(raw_clock['expression']), 'root': clock_tree}
        context_nodes.extend(flatten(clock_tree))
    if 'disable_iff' in raw_context:
        reset_tree = export_tree(raw_context['disable_iff'], prefix + '_disable')
        context['disable_iff'] = {'expression': render(raw_context['disable_iff']), 'root': reset_tree}
        context_nodes.extend(flatten(reset_tree))

    def values(nodes, kind):
        return list(dict.fromkeys(node['value'] for node in nodes if node['kind'] == kind))

    operations = [node for node in body_nodes if node['kind'] in OPERATION_KINDS]
    calls = [node for node in operations if node['kind'] == 'function_call']
    return {
        'source_assertion': assertion,
        'body_expression': render(root),
        'root': tree,
        'context': context,
        'body_signal_names': values(body_nodes, 'signal'),
        'context_signal_names': values(context_nodes, 'signal'),
        'all_signal_names': values(body_nodes + context_nodes, 'signal'),
        'exact_literal_values': values(body_nodes + context_nodes, 'literal'),
        'parameter_names': values(body_nodes + context_nodes, 'parameter'),
        'summary': {
            'body_nodes': len(body_nodes),
            'operations_total': len(operations),
            'symbolic_operators': len(operations) - len(calls),
            'function_calls': len(calls),
            'max_node_depth': max(node['depth'] for node in body_nodes),
            'operation_categories': dict(Counter(node['category'] for node in operations)),
        },
    }


def build_pair(reference: str, generated: str, requirement: str = '', parameters=()) -> dict:
    """Return the full payload in memory, ready for a later JEV adapter."""
    return {
        'schema_version': 'raw-tree-toy-1.2',
        'normalization': 'none',
        'requirement': requirement,
        'depth_convention': 'Body root is depth 0; each child edge adds 1. Clock/reset have separate context roots.',
        'reference': build_tree(reference, 'R', parameters),
        'generated': build_tree(generated, 'G', parameters),
    }
