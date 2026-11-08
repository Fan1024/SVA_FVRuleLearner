"""Extract PEC inputs without parsing or repairing the property grammar.

Human excludes the leading clock and standard disable iff (tb_reset).
Machine/OpenCore exclude the leading clock and retain disable iff. All body
text comes from the source, never from a rendered tree. No pyslang dependency.
"""
from dataclasses import asdict, dataclass
import re


ADAPTER_VERSION = "source_boundaries_v1"
DATASETS = frozenset({"nl2sva_human", "nl2sva_machine", "nl2sva_opencore"})
SAMPLED_VALUE_FUNCTIONS = frozenset({"$past", "$rose", "$fell", "$stable", "$changed"})

_ARBITER_PROPERTY = "(|tb_gnt && (tb_gnt[gnt_id] != 1'b1)) !== 1'b1"
_FIFO_PROPERTY = (
    "(((input_fsm == 2'd2) && (output_fsm == 2'd1) && rd_pop && "
    "(rd_data[rand_bit_sel] != colour_1bit)) || "
    "((input_fsm == 2'd2) && (output_fsm == 2'd2) && rd_pop && "
    "(rd_data[rand_bit_sel] == colour_1bit))) !== 1'b1"
)


class ExtractionError(ValueError):
    """Input boundaries could not be identified safely; no SYN verdict implied."""


@dataclass(frozen=True)
class _Token:
    text: str
    start: int
    end: int


@dataclass(frozen=True)
class ExtractedProperty:
    source: str
    formula: str
    clock_event: str
    excluded_disable: str
    wrapped: bool
    formula_start: int
    formula_end: int

    def to_dict(self):
        """Offsets are Python Unicode-character offsets, end exclusive."""
        return asdict(self)


def _source(text):
    if not isinstance(text, str) or not text.strip():
        raise ExtractionError("Expected nonempty assertion text.")
    text = text.strip()
    if text.startswith("```"):
        match = re.fullmatch(r"```(?:systemverilog|verilog|sv)?[^\S\n]*\n(.*?)\n?```", text, re.S)
        if not match:
            raise ExtractionError("Expected one complete code fence.")
        text = match.group(1).strip()
    if "\x00" in text:
        raise ExtractionError("NUL in assertion input.")
    return text


def _tokens(source):
    """Locate punctuation, ignoring delimiters inside comments/strings/names."""
    result = []
    i, length = 0, len(source)
    while i < length:
        if source[i].isspace():
            i += 1
            continue
        if source.startswith("//", i):
            newline = source.find("\n", i + 2)
            i = length if newline < 0 else newline + 1
            continue
        if source.startswith("/*", i):
            close = source.find("*/", i + 2)
            if close < 0:
                raise ExtractionError("Unterminated block comment.")
            i = close + 2
            continue
        start = i
        if source[i] == '"':
            i += 1
            while i < length:
                if source[i] == "\\":
                    i += 2
                elif source[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            else:
                raise ExtractionError("Unterminated string literal.")
        elif source[i] == "\\":
            # SystemVerilog escaped identifiers end at whitespace.
            i += 1
            while i < length and not source[i].isspace():
                i += 1
        elif source[i].isalpha() or source[i] in "_$":
            i += 1
            while i < length and (source[i].isalnum() or source[i] in "_$"):
                i += 1
        else:
            i += 1
        result.append(_Token(source[start:i], start, i))
    return result


def _close(tokens, opening):
    """Match delimiters only. This deliberately does not validate SVA grammar."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    for i in range(opening, len(tokens)):
        text = tokens[i].text
        if text in pairs:
            stack.append(pairs[text])
        elif text in pairs.values():
            if not stack or text != stack.pop():
                raise ExtractionError("Mismatched delimiters; cannot locate property boundary.")
            if not stack:
                return i
    raise ExtractionError("Unclosed delimiter; cannot locate property boundary.")


def extract_property(text, dataset):
    """Extract one wrapped assertion or bare property, preserving body text.

    The standard Human reset clause is excluded only at the beginning of the
    property specification. Other reset conditions are retained and reported;
    inner uses of tb_reset are never treated as extraction boundaries.
    Balanced but grammatically invalid bodies are deliberately accepted here.
    """
    if dataset not in DATASETS:
        raise ValueError("Unsupported PEC dataset: " + str(dataset))
    source = _source(text)
    tokens = _tokens(source)
    if not tokens:
        raise ExtractionError("No property tokens found.")
    i = 0
    # Optional assertion label, including an escaped identifier.
    if len(tokens) > 2 and tokens[1].text == ":":
        i = 2
    wrapped = tokens[i].text == "assert"
    end = len(source)
    if wrapped:
        i += 1
        if i < len(tokens) and tokens[i].text == "property":
            i += 1
        if i >= len(tokens) or tokens[i].text != "(":
            raise ExtractionError("Expected assertion opening parenthesis.")
        # The final ')' is the statement wrapper boundary. Do not require the
        # body itself to balance: malformed source must still reach Jasper.
        closing = len(tokens) - (2 if tokens[-1].text == ";" else 1)
        if closing <= i or tokens[closing].text != ")":
            raise ExtractionError("Cannot locate the final assertion wrapper parenthesis.")
        if any(token.text in {";", "assert"} for token in tokens[i + 1:closing]):
            raise ExtractionError("Expected one assertion, without extra statements.")
        try:
            first_close = _close(tokens, i)
        except ExtractionError:
            first_close = closing
        if first_close < closing and any(token.text != ")" for token in tokens[first_close + 1:closing]):
            raise ExtractionError("Assertion action blocks or trailing statements are not supported.")
        end = tokens[closing].start
        i += 1
        limit = closing
    else:
        if any(token.text == "assert" for token in tokens):
            raise ExtractionError("Assertion wrapper not recognized at the beginning of input.")
        limit = len(tokens)
        if any(token.text == ";" for token in tokens):
            raise ExtractionError("Unexpected statement terminator in bare property input.")
    if i >= limit:
        raise ExtractionError("Empty property specification.")
    start = tokens[i].start
    clock = ""
    if tokens[i].text == "@":
        clock_start = tokens[i].start
        i += 1
        if i >= limit:
            raise ExtractionError("Missing clock event after '@'.")
        if tokens[i].text == "(":
            i = _close(tokens, i) + 1
        else:
            # Named/non-parenthesized clocking needs explicit support rather
            # than silently stripping the wrong amount of source text.
            raise ExtractionError("Expected a parenthesized leading clock event.")
        clock = source[clock_start:tokens[i - 1].end]
        start = tokens[i - 1].end
    excluded_disable = ""
    if (dataset == "nl2sva_human" and i + 2 < limit
            and [token.text for token in tokens[i:i + 3]] == ["disable", "iff", "("]):
        closing = _close(tokens, i + 2)
        condition = [token.text for token in tokens[i + 3:closing]]
        if condition == ["tb_reset"]:
            excluded_disable = source[tokens[i].start:tokens[closing].end]
            start = tokens[closing].end
            i = closing + 1
    while start < end and source[start].isspace():
        start += 1
    # Retain a final newline: a trailing // comment must not comment out the
    # closing syntax added by the PEC checker. All returned text is a slice.
    while end > start and source[end - 1] in " \t\r":
        end -= 1
    if i >= limit or not source[start:end].strip():
        raise ExtractionError("Empty property body after wrapper extraction.")
    return ExtractedProperty(source, source[start:end], clock, excluded_disable,
                             wrapped, start, end)


def prepare_pec_inputs(generated_assertion, reference_assertion, dataset):
    """Prepare both expressions; no declarations, scores, or source repairs."""
    properties = {}
    for side, source in (('generated', generated_assertion), ('reference', reference_assertion)):
        try:
            properties[side] = extract_property(source, dataset).to_dict()
        except ExtractionError as error:
            error.side = side
            raise
    return {
        "adapter_version": ADAPTER_VERSION,
        "dataset": dataset,
        "offset_units": "unicode_characters_end_exclusive",
        **properties,
    }


def normalize_human_selects(formula, declarations):
    """Rewrite the known Human bit-select properties under their declared types.

    The outer case inequality fails only when its inner Boolean is exactly 1.
    Constant selects and case equality preserve that condition for X/Z and
    out-of-range indices, without assuming valid indices or changing the TB.
    """
    tokens = [token.text for token in _tokens(formula)]
    if tokens == [token.text for token in _tokens(_ARBITER_PROPERTY)] and (
            declarations.get('tb_gnt') == '[5:0] tb_gnt'
            and declarations.get('gnt_id') == '[2:0] gnt_id'):
        bad_grants = [
            f"((gnt_id === 3'd{index}) && (tb_gnt[{index}] === 1'b0))"
            for index in range(6)
        ]
        return ("!(((|tb_gnt) === 1'b1) && (" + " || ".join(bad_grants) + "))",
                "human_arbiter_constant_indices")
    if tokens == [token.text for token in _tokens(_FIFO_PROPERTY)] and (
            declarations.get('rd_data') == '[0:0] rd_data'
            and declarations.get('rand_bit_sel') == '[-1:0] rand_bit_sel'
            and declarations.get('colour_1bit') == 'colour_1bit'):
        # Logical equality/inequality is exactly true only for two known bits.
        # Within the positive AND/OR expression, replacing unknown by false
        # preserves whether the whole expression is exactly true.
        known_equal = (
            "((rand_bit_sel === 2'd0) && "
            "(((rd_data[0] === 1'b0) && (colour_1bit === 1'b0)) || "
            "((rd_data[0] === 1'b1) && (colour_1bit === 1'b1))))"
        )
        known_different = (
            "((rand_bit_sel === 2'd0) && "
            "(((rd_data[0] === 1'b0) && (colour_1bit === 1'b1)) || "
            "((rd_data[0] === 1'b1) && (colour_1bit === 1'b0))))"
        )
        return (_FIFO_PROPERTY.replace("(rd_data[rand_bit_sel] != colour_1bit)", known_different)
                .replace("(rd_data[rand_bit_sel] == colour_1bit)", known_equal),
                "human_fifo_constant_index")
    return formula, None


def compound_sampled_calls(formula):
    """Record sampled expressions for diagnosis without changing Machine SVA."""
    import pyslang

    tree = pyslang.syntax.SyntaxTree.fromText(
        'module __pec_input; assert property (' + formula + '\n); endmodule')
    if any(diagnostic.isError() for diagnostic in tree.diagnostics):
        return []
    calls = []

    def visit(node):
        if node.kind.name != 'InvocationExpression' or node.left.kind.name != 'SystemName':
            return
        name = str(node.left).strip()
        if name not in SAMPLED_VALUE_FUNCTIONS:
            return
        arguments = list(node.arguments.parameters)
        if not arguments or arguments[0].kind.name != 'OrderedArgument':
            return
        operand = arguments[0].expr
        while operand.kind.name in {'SimplePropertyExpr', 'SimpleSequenceExpr', 'ParenthesizedExpression'}:
            operand = operand.expression if operand.kind.name == 'ParenthesizedExpression' else operand.expr
        if operand.kind.name not in {'IdentifierName', 'IdentifierSelectName', 'ScopedName'}:
            calls.append(str(node).strip())

    tree.root.visit(visit)
    return calls
