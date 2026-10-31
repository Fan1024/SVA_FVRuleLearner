"""Extract PEC inputs without parsing or repairing the property grammar.

Human excludes the leading clock and standard disable iff (tb_reset).
Machine/OpenCore exclude the leading clock and retain disable iff. All body
text comes from the source, never from a rendered tree. No pyslang dependency.
"""
from dataclasses import asdict, dataclass
import re


ADAPTER_VERSION = "source_boundaries_v1"
DATASETS = frozenset({"nl2sva_human", "nl2sva_machine", "nl2sva_opencore"})


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
    return {
        "adapter_version": ADAPTER_VERSION,
        "dataset": dataset,
        "offset_units": "unicode_characters_end_exclusive",
        "generated": extract_property(generated_assertion, dataset).to_dict(),
        "reference": extract_property(reference_assertion, dataset).to_dict(),
    }
