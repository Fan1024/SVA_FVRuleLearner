"""Mask copies of retrieved training requirements, rules and revision traces.

Names come from training source context, quoted requirement identifiers and
parsed training assertions. This lexical helper is not a full SV elaborator.
Operators, function names, numeric literals and temporal bounds are preserved.
"""
import re
from new_agent import assertion_tree
from new_agent.infer_training_traces import compact_rounds

# Exclude language words, including declaration/control words, from name masking.
KEYWORDS = set('''accept_on alias always always_comb always_ff always_latch and assert
assign assume automatic before begin bind bins binsof bit break buf byte case casex
casez cell chandle checker clocking config const constraint context continue cover
covergroup coverpoint cross deassign default defparam design disable dist do edge
else end endcase endchecker endclass endclocking endconfig endfunction endgenerate
endgroup endinterface endmodule endpackage endprimitive endprogram endproperty
endsequence endspecify endtable endtask enum event eventually expect export extends
extern final first_match for force foreach forever fork forkjoin function generate
genvar global highz0 highz1 if iff ifnone ignore_bins illegal_bins implements implies
import incdir include initial inout input inside int integer interconnect interface
intersect join join_any join_none large let liblist library local localparam logic
longint macromodule matches medium modport module nand negedge nettype new nexttime
nmos nor noshowcancelled not notif0 notif1 null or output package packed parameter
pmos posedge primitive priority program property protected pull0 pull1 pulldown
pullup pulsestyle_ondetect pulsestyle_onevent pure rand randc randcase randsequence
rcmos real realtime ref reg reject_on release repeat restrict return rnmos rpmos
rtran rtranif0 rtranif1 s_always s_eventually s_nexttime s_until s_until_with scalared
sequence shortint shortreal showcancelled signed small soft solve specify specparam
static string strong strong0 strong1 struct super supply0 supply1 sync_accept_on
sync_reject_on table tagged task this throughout time timeprecision timeunit tran
tranif0 tranif1 tri tri0 tri1 triand trior trireg type typedef union unique unique0
unsigned until until_with untyped use uwire var vectored virtual void wait wait_order
wand weak weak0 weak1 while wildcard wire with within wor xnor xor'''.split())
IDENTIFIER = r'\\[^\s`]+|[A-Za-z_][A-Za-z0-9_$]*'
LITERAL = r"(?:\d+\s*)?'[sS]?[bBoOdDhH]\s*[0-9a-fA-F_xXzZ?]+|'[01xXzZ]|\b\d+(?:\.\d+)?\b"
TOKENS = re.compile(r'<[a-z_]+\d*>|(?:' + LITERAL + r")(?![A-Za-z0-9_$'])" + r'|\$[A-Za-z_][\w$]*|' + IDENTIFIER)


DECLARATIONS = set('input output inout ref wire reg logic bit tri tri0 tri1 uwire wand wor trireg byte shortint int longint integer time real shortreal realtime parameter localparam genvar'.split())
QUALIFIERS = DECLARATIONS | set('signed unsigned var const automatic static type'.split())


def declaration_names(source):
    """Read common signal/parameter declarations, including comma lists and ports.

    Keep module/type/instance names out of the mask. Unsupported declarations
    can still get names from the parsed assertion or quoted requirement list.
    """
    tokens = re.findall(r"\\[^\s]+|[A-Za-z_][\w$]*|[^\s]", source)
    names = set()
    for start, token in enumerate(tokens):
        if token not in DECLARATIONS or (start and tokens[start-1] == 'typedef'):
            continue
        index = start + 1
        while index < len(tokens) and tokens[index] in QUALIFIERS:
            index += 1
        while index < len(tokens) and tokens[index] == '[':
            depth = 1; index += 1
            while index < len(tokens) and depth:
                depth += (tokens[index] == '[') - (tokens[index] == ']')
                index += 1
        # A user-defined data type may precede the declared name.
        if (index + 1 < len(tokens) and re.fullmatch(IDENTIFIER, tokens[index])
                and re.fullmatch(IDENTIFIER, tokens[index+1])
                and tokens[index+1] not in KEYWORDS):
            index += 1
        while index < len(tokens):
            name = tokens[index]
            if not re.fullmatch(IDENTIFIER, name) or name in KEYWORDS:
                break
            names.add(name); index += 1
            nesting = 0
            while index < len(tokens):
                current = tokens[index]
                if nesting == 0 and current in {',', ';', ')'}:
                    break
                if current in {'(', '[', '{'}:nesting += 1
                elif current in {')', ']', '}'}:nesting -= 1
                index += 1
            if index >= len(tokens) or tokens[index] != ',':
                break
            index += 1
    return names


def source_names(requirement, rules, context=None):
    context = context or {}
    source = context.get('testbench', '')
    source = re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"', ' ', source)
    names = declaration_names(source)
    # User-written function names are operations, not signals.
    # Named port connections such as .data(data) are not function calls.
    functions = set(re.findall(r'(?<![.$\w])([A-Za-z_]\w*)\s*\(', source)) - KEYWORDS
    names -= functions
    declared_signals = set(names)
    explicit_names = set()
    for fragment in re.findall(r"['\"]([A-Za-z_][\w$]*)['\"]", requirement):
        if fragment not in KEYWORDS:
            names.add(fragment)
            explicit_names.add(fragment)
    sources = [context.get('reference_assertion', '')] + context.get('_source_assertions', [])
    for rule in rules.values():
        sources.extend(re.findall(r'`([^`]+)`', rule))
    for expression in sources:
        if not expression:
            continue
        expression_functions = (set(re.findall(r'\b([A-Za-z_]\w*)\s*\(', expression))
                                - KEYWORDS - declared_signals)
        functions.update(expression_functions)
        try:
            tree = assertion_tree.build_tree(expression, 'H')
        except assertion_tree.ParseError:
            # Lexical fallback remains explicit: only names in source expressions,
            # never every English word in the rule description.
            for token in TOKENS.finditer(expression):
                value = token.group()
                if (re.fullmatch(IDENTIFIER, value) and value not in KEYWORDS
                        and not value.startswith('$') and value not in functions):
                    names.add(value)
                    explicit_names.add(value)
            continue
        def walk(node):
            if node['kind'] in {'signal', 'parameter'}:
                names.add(node['value'])
                explicit_names.add(node['value'])
            for child in node.get('children', []):
                walk(child)
        walk(tree['root'])
        for item in tree.get('context', {}).values():
            walk(item['root'])
    # Discover familiar signal spellings even if a declaration is unavailable.
    # Avoid treating arbitrary English words as undeclared signals.
    descriptions = [requirement] + list(rules.values())
    signal_pattern = re.compile(
        r'\b(?:tb_[A-Za-z0-9_$]+|sig_[A-Za-z0-9_$]+|'
        r'[A-Za-z_][\w$]*_(?:req|ack|vld|rdy|en|rst|cnt|count|value|d\d+))\b')
    for text in descriptions:
        names.update(signal_pattern.findall(text))
    # Unused loop declarations a/i must not turn English articles or i.e. into
    # signal placeholders. Retain short names explicitly used in SVA/quotes.
    names -= {name for name in declared_signals if len(name) == 1 and name not in explicit_names}
    return names - KEYWORDS - functions


def placeholder_role(name):
    """Naming conventions suggest roles; they never determine target semantics."""
    normalized = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', name).lower().lstrip('\\')
    words = set(re.split(r'[^a-z0-9]+', normalized))
    if re.search(r'(?:^|_)d\d+(?:_|$)', normalized):
        return 'delayed_signal'
    if 'mask' in words and words & {'req', 'request'}:
        return 'request_mask'
    if words & {'gnt', 'grant'}:
        if words & {'last', 'previous', 'prev'}:
            return 'previous_grant_signal'
        if words & {'cont', 'continued', 'continuous'}:
            return 'continued_grant_signal'
        return 'grant_signal'
    for aliases, role in (
        ({'clk', 'clock'}, 'clock'),
        ({'rst', 'reset', 'resetn', 'rstn'}, 'reset'),
        ({'req', 'request'}, 'request_signal'),
        ({'ack', 'acknowledge', 'acknowledgement', 'acknowledgment'}, 'acknowledge_signal'),
        ({'vld', 'valid'}, 'valid_signal'),
        ({'rdy', 'ready'}, 'ready_signal'),
        ({'en', 'enable'}, 'enable_signal'),
        ({'cnt', 'count', 'counter'}, 'counter_signal'),
        ({'value'}, 'value_signal'),
        ({'hold'}, 'hold_signal'),
        ({'busy'}, 'busy_signal'),
    ):
        if words & aliases:
            return role
    return 'testbench_signal' if normalized.startswith('tb_') else 'signal'


class CaseMasker:
    """One role-based, collision-free mapping shared across the complete case."""
    def __init__(self, names):
        self.names = names
        self.mapping = {}
        self.counts = {}

    def mask(self, text):
        def substitute(match):
            name = match.group()
            if name not in self.names or name.startswith('$'):
                return name
            if name not in self.mapping:
                role = placeholder_role(name)
                self.counts[role] = self.counts.get(role, 0) + 1
                self.mapping[name] = f'<{role}_{self.counts[role]}>'
            return self.mapping[name]
        return TOKENS.sub(substitute, text)


def mask_case(requirement, rules, context=None):
    """Compatibility helper for requirement/rule-only callers."""
    masker = CaseMasker(source_names(requirement, rules, context))
    masked_requirement = masker.mask(requirement)
    masked_rules = {key: masker.mask(text) for key, text in rules.items()}
    return masked_requirement, masked_rules


def prepare_candidates(cases, contexts=None):
    """Mask all selected training evidence; exclude references, trees and logs."""
    result = []
    for case in cases:
        context = dict((contexts or {}).get(case['case_number'], case))
        trace = compact_rounds(case.get('revision_trace', []))
        context['_source_assertions'] = [r['assertion'] for r in trace if r['assertion']]
        descriptions = dict(case['rules'])
        indexed_locations = case.get('rule_locations', {})
        indexed_locations = indexed_locations if isinstance(indexed_locations, dict) else {}
        for key, location in indexed_locations.items():
            if isinstance(location, str) and location.strip():
                descriptions[f'location_{key}'] = location
        for i, entry in enumerate(trace):
            for j, correction in enumerate(entry['corrections']):
                for field in ('difference', 'why_it_matters', 'rule', 'location'):
                    if correction.get(field):
                        descriptions[f'trace_{i}_{j}_{field}'] = correction[field]
        masker = CaseMasker(source_names(case['requirement'], descriptions, context))
        requirement = masker.mask(case['requirement'])
        rules = [{'id': f"C{case['case_number']:04d}:{key}", 'rule': masker.mask(text),
                  **({'location': masker.mask(indexed_locations[key])}
                     if isinstance(indexed_locations.get(key), str) and indexed_locations[key].strip() else {})}
                 for key, text in case['rules'].items()]
        for entry in trace:
            if entry['assertion']:
                entry['assertion'] = masker.mask(entry['assertion'])
            for j, correction in enumerate(entry['corrections'], 1):
                for field in ('difference', 'why_it_matters', 'rule', 'location'):
                    if field in correction:
                        correction[field] = masker.mask(correction[field])
                correction['id'] = f"C{case['case_number']:04d}:round_{entry['round']}:correction_{j}"
            # acceptance_reason can contain text; mask it using the same map.
            entry['evaluation'] = {key: masker.mask(value) if isinstance(value, str) else value
                                   for key, value in entry['evaluation'].items()}
        result.append({
            'case_number': case['case_number'],
            'similarity': case.get('similarity'),
            'requirement': requirement,
            'rules': rules,
            'revision_trace': trace,
            'trace_status': case.get('trace_status', 'available' if trace else 'unavailable_missing_trace'),
        })
    return result
