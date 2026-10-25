#!/usr/bin/env python3
"""Check the site against the library it documents.

Three things go wrong in a hand-written site and none of them are visible in a
browser: a page names a function that was renamed, a link points at a page that
moved, and a block quotes text the code does not print. This checks all three
and exits non-zero, so the same drift that a reviewer would miss fails the build.

The last check is the interesting one: with `--examples`, every number printed
in a tutorial's output block must appear in that page's example program. That is
what catches a value that was right when it was written and is not any more,
which is the failure a reader trusts and cannot see.

    python scripts/check_docs.py               # fast: names and links
    python scripts/check_docs.py --examples    # also runs the five programs
"""

from __future__ import annotations

import html
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MBTI = ROOT / "src" / "pkg.generated.mbti"
DOCS = ROOT / "docs"
REPO = "https://github.com/moonbitstack/moonnum"

# `Refused` has a `Show` implementation that prints the reason alone; the pages
# used to print `Refused::Malformed at offset 2: ...`, which the library never
# produces. Keeping the string out of the site is the cheapest way to keep it
# that way.
FORBIDDEN = ["Refused::", "format_complex(", "repr_float_of"]

# Each tutorial page is backed by one runnable example. The numbers in the
# page's output blocks have to come out of that program.
TUTORIALS = {
    "01-integers.html": "src/examples/01-integers",
    "02-floats.html": "src/examples/02-floats",
    "03-complex.html": "src/examples/03-complex",
    "04-fractions.html": "src/examples/04-fractions",
    "05-format.html": "src/examples/05-format",
}

NUMBER = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?")


def public_names() -> set[str]:
    """Every name a caller can write after `@moonnum.`."""
    text = MBTI.read_text(encoding="utf-8")
    names: set[str] = set()
    for match in re.finditer(r"^pub fn ([\w:]+)", text, re.M):
        name = match.group(1)
        names.add(name)
        names.add(name.split("::")[-1])
    for match in re.finditer(r"^pub\(all\) (?:struct|enum|suberror) (\w+)", text, re.M):
        names.add(match.group(1))
    # A suberror's cases are named by the caller in a `catch` pattern:
    # `@moonnum.ZeroDivision => ...`, so they count as public names too.
    for match in re.finditer(r"^pub\(all\) suberror \w+ \{\n((?:  .*\n)+)\}", text, re.M):
        for line in match.group(1).splitlines():
            case = re.match(r"\s+(\w+)", line)
            if case:
                names.add(case.group(1))
    return names


def anchors(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'\bid="([^"]+)"', text))


def output_blocks(text: str) -> list[str]:
    """The bodies of the `<pre><code>` blocks labelled `output`."""
    return re.findall(
        r'<div class="label">output</div>\s*<pre><code>(.*?)</code></pre>',
        text, re.S)


def run_example(directory: str) -> str:
    result = subprocess.run(
        ["moon", "run", directory, "--target", "wasm-gc"],
        cwd=ROOT, capture_output=True, text=True)
    return result.stdout


def check_examples(pages: list[Path]) -> list[str]:
    problems = []
    for page in pages:
        directory = TUTORIALS.get(page.name)
        if directory is None:
            continue
        # Compare tokens, not substrings: `28` is a substring of `282475249`,
        # and a check that passes on the digits of a different number is worse
        # than no check.
        produced = set(NUMBER.findall(run_example(directory)))
        text = page.read_text(encoding="utf-8")
        for block in output_blocks(text):
            for token in NUMBER.findall(html.unescape(block)):
                if token not in produced:
                    problems.append(
                        f"{page.name}: prints {token}, which "
                        f"{directory} never produces")
    return problems


def main() -> int:
    with_examples = "--examples" in sys.argv[1:]
    if not MBTI.exists():
        print(f"missing {MBTI}; run `moon info --target all` first", file=sys.stderr)
        return 1

    names = public_names()
    pages = sorted(DOCS.glob("*.html"))
    if not pages:
        print("no pages in docs/", file=sys.stderr)
        return 1

    problems: list[str] = []
    for page in pages:
        text = page.read_text(encoding="utf-8")
        where = page.relative_to(ROOT)

        for mention in sorted(set(re.findall(r"@moonnum\.(\w+)", text))):
            if mention not in names:
                problems.append(f"{where}: @moonnum.{mention} is not in the interface")

        for needle in FORBIDDEN:
            if needle in text:
                problems.append(f"{where}: quotes `{needle}`, which the library does not print")

        if REPO not in text:
            problems.append(f"{where}: no link back to {REPO}")

        for target in re.findall(r'href="([^"]+)"', text):
            target = html.unescape(target)
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path_text, _, fragment = target.partition("#")
            linked = (page.parent / path_text).resolve() if path_text else page
            if not linked.exists():
                problems.append(f"{where}: link to {target} has no page")
            elif fragment and fragment not in anchors(linked):
                problems.append(f"{where}: link to {target} has no anchor")

    if with_examples:
        problems.extend(check_examples(pages))

    for problem in problems:
        print(problem, file=sys.stderr)
    extra = ", examples run" if with_examples else ""
    print(f"checked {len(pages)} pages against {len(names)} public names{extra}: "
          f"{'ok' if not problems else str(len(problems)) + ' problem(s)'}")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
