#!/usr/bin/env python3
"""Generate docs/api.html from the module interface and the doc comments.

The signatures come from `src/pkg.generated.mbti`, which `moon info` writes, so
they are the signatures the compiler actually sees. The prose comes from the
`///` comments next to each declaration in `src/*.mbt`. Nothing here is typed by
hand, so the reference cannot claim a function that does not exist.

Run after changing the public surface:

    moon info --target all
    python scripts/gen_api.py
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MBTI = ROOT / "src" / "pkg.generated.mbti"
SRC = ROOT / "src"
OUT = ROOT / "docs" / "api.html"

# Groups, in reading order. A name that appears in more than one group is
# rendered once, in the first group that claims it.
GROUPS = [
    ("Integers", "Arbitrary-precision integers: core's `BigInt`, plus the "
                 "operations and spellings a numeric program needs.", [
        "parse_int", "floordiv", "floor_mod", "divmod", "power", "gcd", "lcm",
        "isqrt", "factorial", "comb", "perm", "bit_length", "to_bytes",
        "of_bytes",
    ]),
    ("Floats", "Reading, writing and rounding IEEE-754 doubles.", [
        "parse_float", "repr_float", "float_hex", "float_of_hex", "round_float",
        "round_big", "floor_big", "ceil_big", "trunc_big", "as_integer_ratio",
        "as_ratio",
    ]),
    ("Complex numbers", "`Complex`, its arithmetic, and its repr.", [
        "parse_complex", "repr_complex", "Complex",
    ]),
    ("Fractions", "Exact rationals, kept in lowest terms.", [
        "parse_fraction", "repr_fraction", "Fraction",
    ]),
    ("Numbers", "The tower: one value that can be any of the four kinds.", [
        "parse", "Number",
    ]),
    ("Formatting", "The format-specification mini-language.", [
        "format", "format_int", "format_float",
    ]),
    ("Errors", "One type, four cases.", ["Refused"]),
]

# What a trait buys the reader, in the spelling they will write. The promoted
# methods (`Complex::add`, `Fraction::op_lt`, ...) are real public functions but
# rendering thirty-two entries called `add` would bury the reference; naming the
# trait and the operator is the honest summary.
TRAIT_NOTES = {
    "Add": "+",
    "Sub": "-",
    "Mul": "*",
    "Neg": "unary -",
    "Eq": "== and !=",
    "Compare": "<, <=, >, >=",
    "Show": "to_string()",
    "Default": "default()",
}

TRAIT_METHODS = {
    "add", "sub", "mul", "neg", "equal", "not_equal", "compare", "default",
    "output", "to_string", "op_lt", "op_le", "op_gt", "op_ge",
}

HEAD = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API reference — moonnum</title>
<link rel="stylesheet" href="style.css">

<script type="module" src="scrollbar.js"></script></head>
<body>

<header class="bar">
  <div class="wrap">
    <a class="wordmark" href="index.html">moonnum<span class="dot">.</span></a>
    <nav>
      <a href="01-integers.html">Tutorial</a>
      <a href="api.html" aria-current="page">API</a>
      <a href="algorithms.html">Algorithms</a>
      <a href="https://github.com/moonbitstack/moonnum">GitHub</a>
    </nav>
  </div>
</header>

<main class="wrap">

<article class="lesson">
  <div class="folio"><span>Reference</span><span>Every public item</span></div>
  <h1>API reference</h1>
  <p class="lede">
    Signatures as the compiler sees them, prose as written beside the code.
    Generated from the module interface, so nothing here is aspirational.
  </p>
"""

TAIL = """</article>

</main>

<footer>
  <div class="wrap">
    <span>moonnum · Apache-2.0</span>
    <a href="https://github.com/moonbitstack/moonnum">source</a>
    <a href="01-integers.html">tutorial</a>
    <span class="spacer">built for MoonBit</span>
  </div>
</footer>

</body>
</html>
"""


def read_mbti() -> list[tuple[str, str]]:
    """Public declarations, as (name, signature-text) pairs."""
    text = MBTI.read_text(encoding="utf-8")
    entries: list[tuple[str, str]] = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("pub fn ") or line.startswith("pub(all) "):
            chunk = [line]
            # A declaration runs until its brackets and braces balance.
            while chunk and (
                chunk[-1].count("(") != chunk[-1].count(")")
                or chunk[-1].count("{") != chunk[-1].count("}")
            ):
                index += 1
                if index >= len(lines):
                    break
                chunk.append(lines[index])
            signature = "\n".join(chunk)
            name = declaration_name(signature)
            if name:
                entries.append((name, signature))
        index += 1
    return entries


def read_traits() -> dict[str, list[str]]:
    """Which traits each type implements: `{"Complex": ["Add", ...]}`."""
    text = MBTI.read_text(encoding="utf-8")
    traits: dict[str, list[str]] = {}
    for match in re.finditer(r"^pub impl (\w+) for (\w+)$", text, re.M):
        trait, type_name = match.group(1), match.group(2)
        traits.setdefault(type_name, []).append(trait)
    return traits


def render_traits(type_name: str, traits: list[str]) -> str:
    if not traits:
        return ""
    parts = []
    for trait in traits:
        note = TRAIT_NOTES.get(trait)
        if note:
            parts.append(f"<code>{trait}</code> (<code>{html.escape(note)}</code>)")
        else:
            parts.append(f"<code>{trait}</code>")
    tail = ("the methods they promote are public on"
            if len(traits) > 1 else "the method it promotes is public on")
    return (f'<p class="traits">Implements {" · ".join(parts)} — '
            f"{tail} <code>{html.escape(type_name)}</code>.</p>")


def declaration_name(signature: str) -> str | None:
    first = signature.splitlines()[0]
    match = re.match(r"pub fn ([A-Za-z0-9_]+(?:::[A-Za-z0-9_]+)?)", first)
    if match:
        return match.group(1)
    match = re.match(r"pub\(all\) (?:struct|enum|suberror) ([A-Za-z0-9_]+)", first)
    if match:
        return match.group(1)
    return None


def read_docs() -> dict[str, str]:
    """Doc comments, keyed by the name they document."""
    docs: dict[str, str] = {}
    for path in sorted(SRC.glob("*.mbt")):
        if path.name.startswith("__"):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        buffer: list[str] = []
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("///"):
                content = stripped[3:]
                if content.startswith("|"):
                    buffer = []
                    continue
                buffer.append(content[1:] if content.startswith(" ") else content)
                continue
            if stripped.startswith("pub") or stripped.startswith("impl "):
                name = declared_name(stripped)
                if name and buffer:
                    docs.setdefault(name, "\n".join(buffer).strip())
                buffer = []
                continue
            if stripped == "" or stripped.startswith("//"):
                continue
            buffer = []
    return docs


def declared_name(declaration: str) -> str | None:
    match = re.match(
        r"(?:pub(?:\(all\))?\s+)?(?:fn|struct|enum|suberror)\s+([A-Za-z0-9_]+(?:::[A-Za-z0-9_]+)?)",
        declaration,
    )
    if match:
        return match.group(1)
    match = re.match(
        r"(?:pub(?:\(all\))?\s+)?(?:struct|enum|suberror)\s+([A-Za-z0-9_]+)",
        declaration,
    )
    return match.group(1) if match else None


def render_doc(text: str) -> str:
    """Doc comment text to HTML: paragraphs, inline code, code blocks."""
    if not text:
        return ""
    blocks = re.split(r"\n\s*\n", text)
    out = []
    for block in blocks:
        block = block.strip("\n")
        if not block.strip():
            continue
        fence = re.match(r"^```[a-z]*\n(.*?)\n?```$", block.strip(), re.S)
        if fence:
            out.append("<pre><code>" + html.escape(fence.group(1)) + "</code></pre>")
            continue
        paragraph = html.escape(block)
        paragraph = re.sub(r"`([^`]+)`", r"<code>\1</code>", paragraph)
        paragraph = paragraph.replace("\n", " ")
        out.append("<p>" + paragraph + "</p>")
    return "\n".join(out)


def render_signature(signature: str, name: str) -> str:
    escaped = html.escape(signature)
    # Highlight the declared name only, on its first occurrence.
    pattern = re.escape(html.escape(name))
    return re.sub(pattern, '<span class="name">' + html.escape(name) + "</span>",
                  escaped, count=1)


def main() -> int:
    if not MBTI.exists():
        print(f"missing {MBTI}; run `moon info --target all` first", file=sys.stderr)
        return 1

    entries = read_mbti()
    docs = read_docs()
    traits = read_traits()
    type_names = {
        name for name, signature in entries
        if signature.startswith("pub(all) ")
    }

    by_group: dict[str, list[tuple[str, str]]] = {name: [] for name, _, _ in GROUPS}
    claimed: set[str] = set()

    def group_of(entry_name: str) -> str | None:
        base = entry_name.split("::")[0]
        for group, _, members in GROUPS:
            if base in members:
                return group
        return None

    for name, signature in entries:
        group = group_of(name)
        if group is None or name in claimed:
            continue
        if name.split("::")[-1] in TRAIT_METHODS:
            # Promoted from a trait; the type's own note lists the operators.
            continue
        claimed.add(name)
        by_group[group].append((name, signature))

    body = [HEAD]
    jump = []
    for group, blurb, members in GROUPS:
        items = by_group[group]
        if not items:
            continue
        anchor = group.lower().replace(" ", "-")
        jump.append(f'<a href="#{anchor}">{html.escape(group)}</a>')
    body.append('<nav class="jump">' + "".join(jump) + "</nav>")
    body.append("")

    for group, blurb, members in GROUPS:
        items = by_group[group]
        if not items:
            continue
        anchor = group.lower().replace(" ", "-")
        body.append(f'<section class="api-group" id="{anchor}">')
        body.append(f"<h2>{html.escape(group)}</h2>")
        body.append(f'<p class="lede">{render_doc(blurb)}</p>')
        for name, signature in items:
            doc = docs.get(name, "")
            body.append('<div class="item">')
            body.append(
                '<p class="sig">' + render_signature(signature, name) + "</p>"
            )
            if doc:
                body.append('<div class="doc">' + render_doc(doc) + "</div>")
            if name in type_names:
                body.append(render_traits(name, traits.get(name, [])))
            body.append("</div>")
        body.append("</section>")
        body.append("")

    body.append(TAIL)
    OUT.write_text("\n".join(body), encoding="utf-8", newline="\n")

    undocumented = [
        name for name, _ in entries
        if name in claimed and name not in docs
        and name.split("::")[-1] not in TRAIT_METHODS
    ]
    print(f"wrote {OUT.relative_to(ROOT)}: "
          f"{sum(len(items) for items in by_group.values())} items")
    if undocumented:
        print("no doc comment (or not grouped): "
              + ", ".join(sorted(set(undocumented))), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
