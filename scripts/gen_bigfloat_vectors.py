#!/usr/bin/env python3
"""Generate `src/bigfloat_vectors_wbtest.mbt` from mpmath.

The tests in this repository only read what this script writes; no test runs
Python. Regenerate with `python scripts/gen_bigfloat_vectors.py` after changing
the reference, and expect to review the diff: every changed line is a behaviour
change.

The reference is mpmath 1.4. Every expected value is printed as the exact decimal
of the reference's answer, so a test reads the same number back and compares it
without a tolerance — except for the transcendental functions, where the two
implementations carry a different number of guard bits and the comparison is
stated in ulps instead.
"""

from __future__ import annotations

import random
import sys

import mpmath as mp

# A value's exact decimal runs to a digit for every three and a third bits, and
# the vectors carry values of thousands of bits.
sys.set_int_max_str_digits(0)

OUT = "src/bigfloat_vectors_wbtest.mbt"

WIDTHS = [50, 100, 1000]

NEAREST = "n"
MODES = ["n", "f", "c", "d", "u"]


# ---------------------------------------------------------------- formatting

def esc(text: str) -> str:
    """A MoonBit string literal holding `text`."""
    out = ['"']
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def exact_decimal(value: mp.mpf) -> str:
    """The exact decimal of a value: no exponent, no rounding, no trailing zeros lost."""
    sign, man, exp, bc = value._mpf_
    if bc == -1:
        return "nan"
    if bc == -3:
        return "-inf"
    if bc == -2:
        return "-inf" if sign else "inf"
    if bc == 0:
        return "0.0"
    if exp >= 0:
        return ("-" if sign else "") + str(man << exp) + ".0"
    places = -exp
    scaled = str(man * 5 ** places)
    if len(scaled) <= places:
        scaled = "0" * (places - len(scaled) + 1) + scaled
    return ("-" if sign else "") + scaled[:-places] + "." + scaled[-places:]


def narrow(value, width: int):
    """The value as a vector carries it: a window above the width under test."""
    with mp.workprec(width + 320):
        return +value


def at(width: int, rounding: str, compute):
    """Run `compute` in a context of `width` bits."""
    with mp.workprec(width):
        mp.mp.rounding = rounding
        answer = +compute()
    mp.mp.rounding = NEAREST
    return answer


def fixed(value: mp.mpf, places: int) -> str:
    """`value` with `places` digits after the point, ties to even."""
    with mp.workprec(mp.mp.prec + 4 * places + 128):
        scaled = mp.nint(value * mp.mpf(10) ** places)
    text = str(int(scaled))
    sign = ""
    if text.startswith("-"):
        sign, text = "-", text[1:]
    if places == 0:
        return sign + text
    text = text.rjust(places + 1, "0")
    return sign + text[:-places] + "." + text[-places:]


# ---------------------------------------------------------------- groups

def rows_arithmetic(width: int) -> list[str]:
    """Exact four-function results, printed exactly and compared exactly."""
    rng = random.Random(width)
    pairs = []
    for _ in range(6):
        a = mp.mpf(rng.randint(-10 ** 6, 10 ** 6)) / mp.mpf(2) ** rng.randint(0, 40)
        b = mp.mpf(rng.randint(-10 ** 6, 10 ** 6)) / mp.mpf(2) ** rng.randint(0, 40)
        if b != 0:
            pairs.append((a, b))
    # A difference that cancels to a handful of bits, operands whose leading bits
    # sit hundreds of places apart, and a product of two decimals that are not
    # decimals in binary.
    pairs.append((mp.mpf(2) ** 60 + 1, -(mp.mpf(2) ** 60)))
    pairs.append((mp.mpf(1), mp.mpf(2) ** -200))
    pairs.append((mp.mpf("-0.1"), mp.mpf("0.30000000000000004")))
    pairs.append((mp.mpf("123456789012345678901234567890"), mp.mpf("0.0000000000001")))
    lines = []
    for a, b in pairs:
        a, b = narrow(a, width), narrow(b, width)
        lines.append("    (%s, %s, %s, %s, %s, %s)," % (
            esc(exact_decimal(a)),
            esc(exact_decimal(b)),
            esc(exact_decimal(at(width, NEAREST, lambda: a + b))),
            esc(exact_decimal(at(width, NEAREST, lambda: a - b))),
            esc(exact_decimal(at(width, NEAREST, lambda: a * b))),
            esc(exact_decimal(at(width, NEAREST, lambda: a / b))),
        ))
    return lines


def rows_rounding(width: int) -> list[str]:
    """One exact tie and two near-ties under each of the five directions."""
    one = mp.mpf(1)
    third = narrow(mp.mpf(1) / 3, width)
    half = mp.mpf(2) ** -width
    cases = [
        (one, half),
        (one, half + mp.mpf(2) ** (-width - 30)),
        (third, mp.mpf(2) ** (-width - 2)),
        (third, -(mp.mpf(2) ** (-width - 2))),
        (-one, half),
    ]
    lines = []
    for a, b in cases:
        for mode in MODES:
            answer = at(width, mode, lambda: a + b)
            lines.append("    (%s, %s, %s, %s)," % (
                esc(exact_decimal(a)),
                esc(exact_decimal(b)),
                esc(mode),
                esc(exact_decimal(answer)),
            ))
    return lines


TRANSCENDENTAL = {
    "exp": ["1", "-1", "0.5", "10", "-10", "0.0000000001"],
    "ln": ["2", "10", "0.5", "1.000001", "1e10", "3"],
    "expm1": ["1", "-1", "0.5", "-0.5", "1e-16", "100", "-100"],
    "log1p": ["1", "0.5", "-0.5", "9.99999999999e-1", "1e10", "-1e-16"],
    "sqrt": ["2", "10", "0.5", "3e-30", "1e100"],
    "sin": ["1", "-2.5", "0.001", "100", "3"],
    "cos": ["1", "-2.5", "0.001", "100", "3"],
    "tan": ["1", "-2.5", "0.001", "100"],
    "asin": ["0.5", "-0.25", "0.999", "0.0001"],
    "acos": ["0.5", "-0.25", "0.999", "0.0001"],
    "atan": ["1", "10", "-0.5", "0.00001", "1000"],
    "sinh": ["1", "-0.5", "5", "0.001"],
    "cosh": ["1", "-0.5", "5", "0.001"],
    "tanh": ["1", "-0.5", "5", "0.001"],
    "asinh": ["1", "-3", "0.001", "10"],
    "acosh": ["2", "1.5", "1000000"],
    "atanh": ["0.5", "-0.9", "0.001", "0.9999"],
}

APPLY = {
    "exp": mp.exp,
    "ln": mp.log,
    "expm1": mp.expm1,
    "log1p": mp.log1p,
    "sqrt": mp.sqrt,
    "sin": mp.sin,
    "cos": mp.cos,
    "tan": mp.tan,
    "asin": mp.asin,
    "acos": mp.acos,
    "atan": mp.atan,
    "sinh": mp.sinh,
    "cosh": mp.cosh,
    "tanh": mp.tanh,
    "asinh": mp.asinh,
    "acosh": mp.acosh,
    "atanh": mp.atanh,
}

POWERS = [("2", "0.5"), ("10", "3.3"), ("2", "-0.5"), ("7", "2"), ("1.5", "-7.25")]

TEXTS = [
    "1", "0.1", "-0.1", "1e-40", "1e40", "3.14159265358979323846",
    "2.718281828459045235360287471352662497757247093699959574966967627724076630353",
    "1_000.5", "  42  ", "1E5", ".5", "5.", "0.000000000000000000001",
    "123456789012345678901234567890.123456789",
]

DECIMALS = ["1", "0.1", "1/3", "-2.5", "1e-10", "123.456789", "1e20"]

WHOLES = [
    "0", "1", "-1", "255", "-65536",
    "123456789012345678901234567890",
    "340282366920938463463374607431768211456",
    "-7" + "0" * 30,
]

DOMAIN = [
    ("sqrt", "-1", "", "nan"),
    ("sqrt", "-0.5", "", "nan"),
    ("ln", "0", "", "-inf"),
    ("ln", "-1", "", "nan"),
    ("asin", "2", "", "nan"),
    ("acos", "-2", "", "nan"),
    ("acosh", "0.5", "", "nan"),
    ("atanh", "1", "", "inf"),
    ("atanh", "-1", "", "-inf"),
    ("atanh", "2", "", "nan"),
    ("pow", "-2", "0.5", "nan"),
    ("pow", "-2", "3", "-8.0"),
    ("pow", "-2", "2", "4.0"),
    ("pow", "-2", "-3", "-0.125"),
    ("pow", "0", "-1", "inf"),
    ("divide", "1", "0", "!div0"),
    ("div", "1", "0", "inf"),
    ("div", "-1", "0", "-inf"),
    ("div", "0", "0", "nan"),
    ("div", "1", "inf", "0.0"),
    ("mul", "0", "inf", "nan"),
    ("add", "inf", "-inf", "nan"),
    ("add", "inf", "1", "inf"),
    ("sin", "inf", "", "nan"),
    ("exp", "-inf", "", "0.0"),
    ("exp", "inf", "", "inf"),
    ("ln", "inf", "", "inf"),
]


def rows_transcendental(name: str, width: int) -> list[str]:
    lines = []
    for argument in TRANSCENDENTAL[name]:
        value = narrow(mp.mpf(argument), width)
        answer = at(width + 64, NEAREST, lambda: APPLY[name](value))
        lines.append("    (%s, %s)," % (esc(argument), esc(exact_decimal(answer))))
    return lines


def rows_pow(width: int) -> list[str]:
    lines = []
    for base, exponent in POWERS:
        b, e = narrow(mp.mpf(base), width), narrow(mp.mpf(exponent), width)
        answer = at(width + 64, NEAREST, lambda: mp.power(b, e))
        lines.append("    (%s, %s, %s)," % (
            esc(base), esc(exponent), esc(exact_decimal(answer))))
    return lines


def rows_constants(width: int) -> list[str]:
    lines = []
    for name, value in [("pi", mp.pi), ("e", mp.e), ("ln2", mp.log(2))]:
        with mp.workprec(width + 64):
            answer = +value
        lines.append("    (%s, %s)," % (esc(name), esc(exact_decimal(answer))))
    return lines


def rows_text(width: int) -> list[str]:
    lines = []
    for text in TEXTS:
        answer = at(width, NEAREST, lambda: mp.mpf(text))
        lines.append("    (%s, %s)," % (esc(text), esc(exact_decimal(answer))))
    return lines


def rows_decimal(width: int) -> list[str]:
    lines = []
    for text in DECIMALS:
        if "/" in text:
            whole, part = text.split("/")
            value = at(width, NEAREST, lambda: mp.mpf(whole) / mp.mpf(part))
        else:
            value = at(width, NEAREST, lambda: mp.mpf(text))
        for places in [0, 2, 10, 60]:
            lines.append("    (%s, %d, %s)," % (
                esc(exact_decimal(value)), places, esc(fixed(value, places))))
    return lines


def rows_whole(width: int) -> list[str]:
    lines = []
    for text in WHOLES:
        answer = at(width, NEAREST, lambda: mp.mpf(int(text)))
        lines.append("    (%s, %s)," % (esc(text), esc(exact_decimal(answer))))
    return lines


# ---------------------------------------------------------------- assembly

def main() -> int:
    # Every literal below is built here and narrowed inside the width under test;
    # a value built at the default 53 bits would carry that rounding into the
    # reference answer and the vectors would agree with a wrong number.
    mp.mp.prec = 12000
    out: list[str] = [
        "// Generated by scripts/gen_bigfloat_vectors.py from mpmath. Do not edit.",
        "// Every row is an argument and what the reference answers for it at that width.",
        "",
    ]

    def block(title: str, call: str, rows: list[str]) -> None:
        out.append("///|")
        out.append('test "%s" {' % title)
        out.append("  " + call)
        out.extend(rows)
        out.append("  ])")
        out.append("}")
        out.append("")

    for width in WIDTHS:
        block("vec_bf_arithmetic at %d bits: 1 of 1" % width,
              "check_bf_arithmetic(%d, [" % width, rows_arithmetic(width))

    for width in WIDTHS:
        rows = rows_rounding(width)
        for start in range(0, len(rows), 50):
            block("vec_bf_rounding at %d bits: %d of 1" % (width, start // 50 + 1),
                  "check_bf_rounding(%d, [" % width, rows[start:start + 50])

    for width in WIDTHS:
        for name in TRANSCENDENTAL:
            block("vec_bf_%s at %d bits: 1 of 1" % (name, width),
                  "check_bf_function(%s, %d, [" % (esc(name), width),
                  rows_transcendental(name, width))
        block("vec_bf_pow at %d bits: 1 of 1" % width,
              "check_bf_pow(%d, [" % width, rows_pow(width))
        block("vec_bf_constants at %d bits: 1 of 1" % width,
              "check_bf_constants(%d, [" % width, rows_constants(width))
        block("vec_bf_text at %d bits: 1 of 1" % width,
              "check_bf_text(%d, [" % width, rows_text(width))
        block("vec_bf_decimal at %d bits: 1 of 1" % width,
              "check_bf_decimal(%d, [" % width, rows_decimal(width))
        block("vec_bf_whole at %d bits: 1 of 1" % width,
              "check_bf_whole(%d, [" % width, rows_whole(width))

    block("vec_bf_domain: 1 of 1", "check_bf_domain([", [
        "    (%s, %s, %s, %s)," % (esc(a), esc(b), esc(c), esc(d))
        for a, b, c, d in DOMAIN
    ])

    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))
    print(f"wrote {OUT}: {len(out)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
