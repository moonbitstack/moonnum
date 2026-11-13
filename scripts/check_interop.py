#!/usr/bin/env python3
"""Check the library against CPython through the text they exchange.

`src/examples/07-interop` computes a fixed list of values with `moonnum` and
prints one line per value: the kind, the expression CPython can evaluate, and the
text the library wrote for it. This script evaluates the same expression with
CPython and compares the two texts. The program on the other side reads every
text it writes back through the library's own parsers, so the exchange runs both
ways: what we write, CPython must read as the same value, and the text CPython
writes is the text the library reads.

A `radixN` row has no CPython spelling — `int(text, N)` is the reader, so the
comparison is by value rather than by text, which is the stronger check anyway.

    python scripts/check_interop.py [--moon moon]
"""

from __future__ import annotations

import argparse
import math
import subprocess
import sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROGRAM = "src/examples/07-interop"

NAMESPACE = {
    "int": int,
    "float": float,
    "complex": complex,
    "Fraction": Fraction,
    "format": format,
    "abs": abs,
    "pow": pow,
    "math": math,
    "len": len,
    "round": round,
    "str": str,
}


def run(moon: str) -> list[tuple[str, str, str]]:
    result = subprocess.run(
        [moon, "run", PROGRAM, "--target", "wasm-gc"],
        cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise SystemExit("the interop program did not run")
    rows = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != 3:
            raise SystemExit(f"a line with {len(fields)} fields: {line!r}")
        rows.append((fields[0], fields[1], fields[2]))
    return rows


def python_text(kind: str, expression: str) -> str:
    value = eval(expression, {"__builtins__": {}}, dict(NAMESPACE))
    if kind == "int":
        return str(value)
    if kind in ("float", "complex"):
        return repr(value)
    if kind == "fraction":
        return str(value)
    if kind == "ratio":
        number, denominator = value
        return f"{number}/{denominator}"
    if kind == "bool":
        return "true" if value else "false"
    if kind == "text":
        return str(value)
    raise ValueError(f"unknown kind {kind}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--moon", default="moon")
    args = parser.parse_args()

    rows = run(args.moon)
    problems = []
    for kind, expression, text in rows:
        if kind.startswith("radix"):
            base = int(kind[len("radix"):])
            value = eval(expression, {"__builtins__": {}}, dict(NAMESPACE))
            try:
                read = int(text, base)
            except ValueError as err:
                problems.append(
                    f"{expression}: {text!r} is not a base-{base} number ({err})")
                continue
            if read != value:
                problems.append(
                    f"{expression}: base {base} {text!r} reads as {read}, "
                    f"want {value}")
            continue
        try:
            want = python_text(kind, expression)
        except ValueError as err:
            problems.append(f"{expression}: {err}")
            continue
        if want != text:
            problems.append(f"{expression}: CPython says {want!r}, we say {text!r}")

    for problem in problems:
        print(problem, file=sys.stderr)
    print(f"checked {len(rows)} values against CPython "
          f"{sys.version_info.major}.{sys.version_info.minor}: "
          f"{'ok' if not problems else str(len(problems)) + ' problem(s)'}")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
