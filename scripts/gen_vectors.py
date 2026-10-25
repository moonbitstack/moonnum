#!/usr/bin/env python3
"""Generate src/vectors.mbt from CPython.

The tests in this repository only read what this script writes; no test runs
Python. Regenerate with `python scripts/gen_vectors.py` after changing the
reference, and expect to review the diff: every changed line is a behaviour
change.

The reference is CPython 3.15. The interpreter used to produce the data is
whatever `python3` is on PATH; the number semantics under test here have not
moved since 3.12, and anything that differs shows up as a failing test rather
than as a silent difference.
"""

from __future__ import annotations

import math
import random
import struct
import sys
from fractions import Fraction

OUT = "src/vectors_wbtest.mbt"

# Python refuses to render integers longer than 4300 digits by default; the
# vectors ask for factorial(1000000), which is far longer than that.
sys.set_int_max_str_digits(0)

# Errors are written as "!<kind>" and the tests translate them back.
MALFORMED = "!malformed"


def esc(text: str) -> str:
    """A MoonBit string literal holding `text`."""
    out = ['"']
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20:
            out.append("\\u{%x}" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def outcome(fn, *args, **kwargs) -> str:
    """Run `fn` and return its `str()`, or the refusal it maps to.

    A `ValueError` from a parser means the text was malformed; the same
    exception from `math` means the argument was outside the domain. The two are
    different cases in `Refused`, so the caller says which it expects.
    """
    try:
        value = fn(*args, **kwargs)
    except ZeroDivisionError:
        return "!div0"
    except OverflowError:
        return "!overflow"
    except ValueError as err:
        message = str(err)
        if message.startswith("int() base must be"):
            return "!domain"
        if kwargs.pop("_math", False):
            return "!domain"
        return MALFORMED
    return str(value)


def domain_outcome(fn, *args) -> str:
    """Run a `math` function: a bad argument is a domain refusal, not a parse one."""
    try:
        return str(fn(*args))
    except ValueError:
        return "!domain"
    except OverflowError:
        return "!overflow"


def bits_to_float(bits: int) -> float:
    return struct.unpack(">d", struct.pack(">Q", bits))[0]


def float_to_bits(value: float) -> int:
    return struct.unpack(">Q", struct.pack(">d", value))[0]


def exact17(value: float) -> str:
    """A decimal string that rounds back to exactly `value`."""
    for precision in range(1, 18):
        text = "%.*e" % (precision - 1, value)
        if float(text) == value:
            return text
    return "%.*e" % (16, value)


CHUNK = 250


def cell(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return esc(value)


def lines(name: str, rows: list[tuple], types: str) -> list[str]:
    """Emit `rows` as test blocks that call `check_<name>`.

    The data is spread over many small arrays rather than one large one: the
    WebAssembly MVP backend refuses a single function with tens of thousands of
    locals, and one array literal per chunk is one function. The assertion lives
    in a hand-written `check_<name>` next to the tests for that subject.
    """
    checker = "check_" + name.replace("vec_", "")
    out = []
    chunks = [rows[index:index + CHUNK] for index in range(0, len(rows), CHUNK)]
    for index, chunk in enumerate(chunks):
        out.append("///|")
        out.append(f'test "{name}: {index + 1} of {len(chunks)}" {{')
        out.append(f"  let rows : Array[({types})] = [")
        for row in chunk:
            out.append("    (" + ", ".join(cell(item) for item in row) + "),")
        out.append("  ]")
        out.append(f"  {checker}(rows)")
        out.append("}")
        out.append("")
    return out


def gen_parse_int() -> list[tuple]:
    rows = []
    text_cases = [
        "0", "7", "-7", "+7", " 42 ", "\t-13\n", "1_000", "1_0_0",
        "0x10", "0X1F", "0o17", "0O17", "0b101", "0B101", "-0x10", "+0b11",
        "ff", "FF", "z", "10", "0", "000", "0_0",
        "1__0", "_1", "1_", "", "  ", "-", "+", "1.5", "12a", "0x", "0b2",
        "123456789012345678901234567890", "-123456789012345678901234567890",
        "0xdeadbeefdeadbeefdeadbeef", "\u00a042",
    ]
    for base in (0, 2, 8, 10, 16, 36, 1, 37):
        for text in text_cases:
            if base in (2, 8, 16, 36) and text not in (
                "0", "7", "-7", "+7", " 42 ", "10", "ff", "FF", "z", "1_000",
                "1__0", "_1", "1_", "", "1.5", "0x10", "12a", "000", "0_0",
            ):
                continue
            if base == 2 and text in ("7", "ff", "FF", "z", "42"):
                continue
            rows.append((text, base, outcome(int, text, base)))
    return rows


def gen_int_div() -> list[tuple]:
    rows = []
    values = ["7", "-7", "2", "-2", "0", "1", "-1", "10", "3",
              "123456789012345678901234567890", "-123456789012345678901234567890"]
    for a in values:
        for b in values:
            try:
                q = str(int(a) // int(b))
            except ZeroDivisionError:
                q = "!div0"
            try:
                r = str(int(a) % int(b))
            except ZeroDivisionError:
                r = "!div0"
            rows.append((a, b, q, r))
    return rows


def gen_pow() -> list[tuple]:
    rows = []
    bases = ["2", "-2", "0", "1", "-1", "10", "3"]
    exps = ["0", "1", "2", "3", "10", "-1", "-3"]
    mods = ["", "5", "-5", "7", "2", "0", "-1"]
    for base in bases:
        for exp in exps:
            for mod in mods:
                if mod == "":
                    # `power` returns an integer, so Python's float answer for a
                    # negative exponent cannot be represented; the library
                    # refuses it and `Number::pow` is the float-valued path.
                    if int(exp) < 0:
                        value = "!domain"
                    else:
                        value = str(pow(int(base), int(exp)))
                else:
                    try:
                        value = str(pow(int(base), int(exp), int(mod)))
                    except ZeroDivisionError:
                        value = "!div0"
                    except ValueError as err:
                        value = "!domain" if "inverse" in str(err) else "!domain"
                rows.append((base, exp, mod, value))
    return rows


def gen_int_math() -> list[tuple]:
    rows = []
    for a in ("0", "1", "6", "12", "-12", "18", "-18", "97"):
        for b in ("0", "1", "6", "12", "-12", "18", "5"):
            rows.append(("gcd", a, b, str(math.gcd(int(a), int(b)))))
            rows.append(("lcm", a, b, str(math.lcm(int(a), int(b)))))
    for n in ("0", "1", "2", "3", "4", "30", "1000", "-1"):
        rows.append(("isqrt", n, "", domain_outcome(math.isqrt, int(n))))
        rows.append(("factorial", n, "", domain_outcome(math.factorial, int(n))))
    for n in ("0", "5", "10", "-1"):
        for k in ("0", "1", "5", "11", "-1"):
            rows.append(("comb", n, k, domain_outcome(math.comb, int(n), int(k))))
            rows.append(("perm", n, k, domain_outcome(math.perm, int(n), int(k))))
    return rows


def gen_bytes() -> list[tuple]:
    rows = []
    cases = [
        ("0", 1, True, False), ("0", 0, True, False), ("255", 1, True, False),
        ("256", 2, True, False), ("256", 2, False, True), ("-1", 1, True, True),
        ("-1", 1, True, False), ("-128", 1, True, True), ("-129", 1, True, True),
        ("65535", 2, True, False), ("65535", 2, False, False),
        ("-65536", 4, True, True), ("12345678901234567890", 9, True, False),
    ]
    for text, length, big, signed in cases:
        try:
            value = int(text).to_bytes(length, "big" if big else "little", signed=signed)
            rows.append((text, length, big, signed, value.hex()))
        except OverflowError:
            rows.append((text, length, big, signed, "!overflow"))
    return rows


def gen_parse_float() -> list[tuple]:
    rows = []
    cases = [
        "0", "-0", "0.0", "-0.0", "1", "1.", ".5", "-.5", "1e5", "1E5",
        "1e+5", "1e-5", "1_0.5", "1.5e1_0", " inf", "inf", "-inf", "+inf",
        "Infinity", "-INFINITY", "nan", "NaN", "-nan", " 1.5 ", "\t2\n",
        "", "  ", "1__0", "_1", "1_", "1._5", "1_.5", ".", "e5", "1e",
        "1e+", "0x1p3", "1..2", "1.2.3", "1,000",
        "1.7976931348623157e308", "5e-324", "2.2250738585072014e-308",
        "1e309", "1e-400", "123456789012345678901234567890",
        "0.1", "3.141592653589793", "1e16", "1e15",
    ]
    for text in cases:
        rows.append((text, outcome(repr, 0) if False else float_outcome(text)))
    return rows


def float_outcome(text: str) -> str:
    try:
        return repr(float(text))
    except ValueError:
        return MALFORMED


def gen_repr() -> list[tuple]:
    rows = []
    values = [
        0.0, -0.0, 1.0, -1.0, 0.1, 0.2, 0.3, 1 / 3, 2 / 3, 1e16, 1e15,
        1e17, 1e-4, 1e-5, 1e-6, 5e-324, 2.2250738585072014e-308,
        1.7976931348623157e308, -1.7976931348623157e308, 123456789012345678.0,
        2e16 + 8, 3.141592653589793, 2.718281828459045, 1.5, 100.0, 1e100,
        1e-100, 9007199254740993.0, 0.30000000000000004, 1.0000000000000002,
    ]
    rng = random.Random(20261025)
    for _ in range(1200):
        bits = rng.getrandbits(64)
        value = bits_to_float(bits)
        if math.isnan(value) or math.isinf(value):
            continue
        values.append(value)
    for value in values:
        rows.append((exact17(value), repr(value)))
    return rows


def gen_hex() -> list[tuple]:
    rows = []
    values = [
        0.0, -0.0, 1.0, -1.0, 1.5, 0.1, 5e-324, 2.2250738585072014e-308,
        1.7976931348623157e308, float("inf"), float("-inf"), float("nan"),
        3.141592653589793, 1e-5, 1e16,
    ]
    out_rows = [(exact17(value), value.hex()) for value in values]
    # And read back every spelling Python itself accepts.
    spellings = [
        "0x1.0000000000000p+0", "0x1.8p+1", "0x1.921fb54442d18p+1",
        "-0x1.999999999999ap-4", "0x0.0000000000001p-1022", "0x1p+1023",
        "0x1.fffffffffffffp+1023", "0x1p-1074", "0x1p-1075", "1.8p1",
        "0x.8p0", "0x8.p0", "inf", "-inf", "nan", "0x1p2000", "0x1p-2000",
        "", "0xg", "0x1p", "1.5",
    ]
    in_rows = []
    for text in spellings:
        try:
            in_rows.append((text, repr(float.fromhex(text))))
        except ValueError:
            in_rows.append((text, MALFORMED))
        except OverflowError:
            in_rows.append((text, "!overflow"))
    return out_rows, in_rows


def gen_round() -> list[tuple]:
    rows = []
    values = [
        0.5, -0.5, 1.5, 2.5, -1.5, -2.5, 0.4, 2.675, 1.005, 0.1, 1.0, -0.0,
        1234.5678, -1234.5678, 5e-324, 1e16, 0.05, 0.15, 0.25, 0.35,
    ]
    for value in values:
        for ndigits in (-3, -1, 0, 1, 2, 3, 6):
            rows.append(("nd", exact17(value), ndigits, repr(round(value, ndigits))))
        rows.append(("int", exact17(value), 0, outcome(round, value)))
    return rows


def gen_floor() -> list[tuple]:
    rows = []
    values = [2.5, -2.5, 0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 5e-324, -5e-324,
              1e300, -1e300, 1234.9999, -1234.9999, 1e16, -1e16]
    for value in values:
        rows.append((exact17(value), str(math.floor(value)), str(math.ceil(value)),
                     str(math.trunc(value))))
    return rows


def gen_complex_parse() -> list[tuple]:
    rows = []
    cases = [
        "1+2j", "(1+2j)", "1-2j", "2j", "j", "-j", "+j", "(2j)", "1e3j",
        "-1.5j", "1+2i", "3+5i", "1 + 2j", "  ( 1 + 2j )  ", "1j", "-0-1j",
        "nan+infj", "infj", "(nan+nanj)", "1", "-1", "1.5", "1+2", "1+",
        "j+1", "jj", "", "(", "(1+2j", "1+2j)", "1_0j", "0.1+0.2j",
    ]
    for text in cases:
        rows.append((text, outcome(complex_repr_of, text)))
    return rows


def complex_repr_of(text: str) -> str:
    return repr(complex(text))


def gen_complex_ops() -> list[tuple]:
    rows = []
    pairs = [
        ("1+2j", "3+4j"), ("1+2j", "1-2j"), ("0j", "1+1j"), ("1+0j", "0j"),
        ("-0-1j", "1j"), ("1e308+1e308j", "1e308+1e308j"),
        ("inf+infj", "1+1j"), ("inf+0j", "0+0j"), ("nan+1j", "1+0j"),
        ("1+2j", "inf+0j"), ("1+2j", "nan+nanj"), ("0j", "0j"),
    ]
    for left, right in pairs:
        a, b = complex(left), complex(right)
        rows.append(("add", left, right, repr(a + b)))
        rows.append(("sub", left, right, repr(a - b)))
        rows.append(("mul", left, right, repr(a * b)))
        rows.append(("div", left, right, outcome(lambda: repr(a / b))))
    for text in ("1+2j", "3-4j", "0j", "-0-0j", "inf+1j", "nan+1j", "1e200+1e200j"):
        z = complex(text)
        rows.append(("abs", text, "", repr(abs(z))))
        rows.append(("conj", text, "", repr(z.conjugate())))
    for base, exp in (("1+1j", "2+0j"), ("2j", "2"), ("0j", "0"), ("0j", "-1"),
                      ("1+0j", "0.5+0j"), ("-1+0j", "0.5+0j")):
        try:
            value = repr(complex(base) ** complex(exp))
        except ZeroDivisionError:
            value = "!div0"
        rows.append(("pow", base, exp, value))
    return rows


def gen_fraction_parse() -> list[tuple]:
    rows = []
    cases = [
        "3/4", "-3/4", "3/-4", "-3/-4", "0/5", "6/4", "7", "-7", "+7",
        " 3 / 4 ", "1.25", "-1.25", "1e-3", "1e3", "1_0.5", "0.1", "3.",
        ".5", "1.", "0", "-0.0", "1/0", "0/0", "abc", "", "/", "1/", "/1",
        "1.2.3", "1/2/3", "1e", "1e+", "123456789012345678901234567890/7",
    ]
    for text in cases:
        rows.append((text, fraction_outcome(text)))
    return rows


def fraction_outcome(text: str) -> str:
    try:
        f = Fraction(text)
    except ZeroDivisionError:
        return "!div0"
    except ValueError:
        return MALFORMED
    return f"{f.numerator}/{f.denominator}"


def gen_fraction_ops() -> list[tuple]:
    rows = []
    pairs = [("1/3", "2/3"), ("3/4", "-3/4"), ("1/2", "1/2"), ("5/2", "2/5"),
             ("-7/3", "2/3"), ("1/2", "0/1")]
    for left, right in pairs:
        a, b = Fraction(left), Fraction(right)
        rows.append(("add", left, right, str(a + b)))
        rows.append(("sub", left, right, str(a - b)))
        rows.append(("mul", left, right, str(a * b)))
        try:
            rows.append(("div", left, right, str(a / b)))
        except ZeroDivisionError:
            rows.append(("div", left, right, "!div0"))
        rows.append(("cmp", left, right, str((a > b) - (a < b))))
        rows.append(("floordiv", left, right, outcome(lambda: a // b)))
        rows.append(("mod", left, right, outcome(lambda: a % b)))
    for text in ("7/2", "-7/2", "5/2", "1/3", "0/1"):
        f = Fraction(text)
        rows.append(("floor", text, "", str(math.floor(f))))
        rows.append(("ceil", text, "", str(math.ceil(f))))
        rows.append(("round", text, "", str(round(f))))
        for ndigits in (-2, 0, 1, 3):
            rows.append(("roundn", text, str(ndigits), str(round(f, ndigits))))
        rows.append(("double", text, "", repr(float(f))))
        for limit in (1, 2, 10, 100):
            rows.append(("limit", text, str(limit), str(f.limit_denominator(limit))))
    return rows


def gen_format_int() -> list[tuple]:
    rows = []
    values = [0, 7, -7, 42, -42, 1234, 1234567, -1234567, 255, -255, 65,
              0x1F600, 2**70]
    specs = [
        "", "d", "b", "o", "x", "X", "n", "5d", "05d", "-5d", "+d", " d",
        "#b", "#o", "#x", "#X", ",d", "_d", "_b", "_x", "+08,d", "=+10d",
        "*<8d", "*>8d", "*^8d", "08,d", "012,d", "011,d", "09,d",
        ".2d", "10.2d", "c", "5c", "0c", "  ", "z", "#", "_", "0=10d",
        "+#012,x", "10000d",
    ]
    for value in values:
        for spec in specs:
            try:
                rows.append((str(value), spec, format(value, spec)))
            except ValueError:
                rows.append((str(value), spec, MALFORMED))
            except OverflowError:
                rows.append((str(value), spec, "!overflow"))
    return rows


def gen_format_float() -> list[tuple]:
    rows = []
    values = [0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 1.5, 3.141592653589793,
              1234.5678, 1e16, 1e-5, 0.0001, 1e300, 5e-324, float("inf"),
              float("-inf"), float("nan"), 2.675, 1e-7, 1234567.891]
    specs = [
        "", "f", "F", "e", "E", "g", "G", "n", "%", ".0f", ".2f", ".10f",
        ".0e", ".3e", ".0g", ".1g", ".3g", "#.3g", "#.0f", ".2%", ".0%",
        "+f", " f", "-f", "10.2f", "010.2f", "*^12.2f", "=+12.2f", "012,.2f",
        ",.2f", "_.2f", "z", "z.2f", "z.1f", ".0f", "#f", "#e", "+e",
        ".17g", ".100f", "0.0f", "0.0g", ".0",
    ]
    for value in values:
        for spec in specs:
            try:
                rows.append((exact17(value), spec, format(value, spec)))
            except ValueError:
                rows.append((exact17(value), spec, MALFORMED))
            except OverflowError:
                rows.append((exact17(value), spec, "!overflow"))
    return rows


def gen_format_sweep() -> list[tuple]:
    """A sampled cross-product of specifiers, on values chosen to be awkward.

    The point is not the size of the sample but that a specifier nobody would
    write by hand still has to agree: a fill character that is a digit, `=` with
    a space fill, a precision with an empty type, `#` with `%`.
    """
    rng = random.Random(424242)
    int_values = [0, 1, -1, 7, -7, 255, 1234567, -1234567, 2**64 + 1,
                  10**30, -10**30]
    float_values = [0.0, -0.0, 1.0, -1.0, 0.5, 1234.5678, -1234.5678,
                    1e16, -1e16, 1e-5, 0.0001, 3.141592653589793, 1e300,
                    5e-324, float("inf"), float("-inf"), float("nan"), 2.675]
    specs = []
    for fill in ("", "*", "0", "-", "\u00a0"):
        for align in ("", "<", ">", "^", "="):
            for sign in ("", "+", "-", " "):
                for alt in ("", "#"):
                    for zero in ("", "0"):
                        for width in ("", "3", "9", "12"):
                            for group in ("", ",", "_"):
                                for precision in ("", ".0", ".2", ".7"):
                                    for ty in ("", "d", "b", "o", "x", "X", "n",
                                               "e", "E", "f", "F", "g", "G", "%"):
                                        specs.append(
                                            fill + align + sign + alt + zero +
                                            width + group + precision + ty)
    rng.shuffle(specs)
    int_rows = []
    float_rows = []
    for spec in specs[:1200]:
        for value in int_values:
            try:
                int_rows.append((str(value), spec, format(value, spec)))
            except ValueError:
                int_rows.append((str(value), spec, MALFORMED))
            except OverflowError:
                int_rows.append((str(value), spec, "!overflow"))
        for value in float_values:
            try:
                float_rows.append((exact17(value), spec, format(value, spec)))
            except ValueError:
                float_rows.append((exact17(value), spec, MALFORMED))
            except OverflowError:
                float_rows.append((exact17(value), spec, "!overflow"))
    return int_rows, float_rows


def gen_format_fraction_sweep() -> list[tuple]:
    """The same idea for fractions, where `f`-style formatting is exact."""
    rng = random.Random(1717)
    values = [Fraction(1, 3), Fraction(1234, 7), Fraction(-22, 7), Fraction(5, 2),
              Fraction(1, 8), Fraction(0), Fraction(-1, 2), Fraction(10**20, 7)]
    specs = []
    for fill in ("", "*", "0", " "):
        for align in ("", "<", ">", "^", "="):
            for sign in ("", "+", "-", " "):
                for alt in ("", "#"):
                    for width in ("", "6", "14"):
                        for group in ("", ",", "_"):
                            for precision in ("", ".0", ".3", ".10"):
                                for ty in ("", "e", "E", "f", "F", "g", "G", "%", "d"):
                                    specs.append(fill + align + sign + alt + width +
                                                 group + precision + ty)
    rng.shuffle(specs)
    rows = []
    for spec in specs[:220]:
        for value in values:
            try:
                rows.append((str(value.numerator), str(value.denominator), spec,
                             format(value, spec)))
            except ValueError:
                rows.append((str(value.numerator), str(value.denominator), spec,
                             MALFORMED))
    return rows


def gen_format_complex() -> list[tuple]:
    rows = []
    values = [(1.0, 2.0), (0.0, 2.0), (-0.0, -1.0), (1.5, -2.5),
              (float("nan"), float("inf")), (0.0, 0.0), (-1.0, -0.0),
              (1e16, 1e-5)]
    specs = ["", "f", ".2f", "e", ".1e", "g", ".3g", "12.2f", "*<14.2f",
             "010.2f", "=10.2f", "+.1f", " .2f", "%", ".2%", "n"]
    for re_part, im_part in values:
        z = complex(re_part, im_part)
        for spec in specs:
            try:
                rows.append((repr(re_part), repr(im_part), spec, format(z, spec)))
            except ValueError:
                rows.append((repr(re_part), repr(im_part), spec, MALFORMED))
    return rows


def gen_format_fraction() -> list[tuple]:
    rows = []
    values = ["1/3", "1234/7", "-22/7", "0/1", "5/2", "1/8", "100000000000000000000/7"]
    specs = ["", "#", "12", "+", "^20", ".3f", ".0f", ".0e", ".3g", "#.3g",
             "%", ".2%", "e", "g", ".10f", ".0g", "#.0f", ".3E", "#.4g", "d",
             ",", "_", "08,.0f", "z", ".2f"]
    for text in values:
        f = Fraction(text)
        for spec in specs:
            try:
                rows.append((f.numerator.__str__(), f.denominator.__str__(), spec,
                             format(f, spec)))
            except ValueError:
                rows.append((f.numerator.__str__(), f.denominator.__str__(), spec,
                             MALFORMED))
    return rows


def gen_number_parse() -> list[tuple]:
    rows = []
    literals = ["1", "-1", "0", "1.5", "1e3", "3/4", "1+2j", "2j", "-0.0",
                "0x10", "inf", "nan", "1_000", "0.1", " 42 ", "-inf",
                "1e-3", "(1+2j)", "-3/4", "0b101", "j", "1e5j", "0x1e",
                "1E5j", "2i", "-0j", "1_0j", "1e", "0o17", "1.5e2j"]
    for text in literals:
        rows.append((text, number_repr(text)))
    return rows


def gen_numbers() -> list[tuple]:
    rows = []
    # Comparison and arithmetic across the tower.
    pairs = [("1", "1.0"), ("1", "3/4"), ("1", "1+0j"), ("1.5", "3/2"),
             ("1e20", "100000000000000000000"), ("0.1", "1/10"),
             ("nan", "nan"), ("inf", "1e308"), ("-0.0", "0"), ("2j", "2j")]
    for left, right in pairs:
        a, b = parse_number(left), parse_number(right)
        rows.append((left, right, "eq", str(a == b)))
        rows.append((left, right, "cmp", cmp_repr(a, b)))
        rows.append((left, right, "add", arith_repr(a, b, "add")))
        rows.append((left, right, "sub", arith_repr(a, b, "sub")))
        rows.append((left, right, "mul", arith_repr(a, b, "mul")))
        rows.append((left, right, "div", arith_repr(a, b, "div")))
    return rows


def parse_number(text: str):
    if text.strip().lower().lstrip("+-") in ("inf", "infinity", "nan"):
        return float(text)
    if "/" in text and "j" not in text:
        return Fraction(text)
    if "j" in text:
        return complex(text)
    if "." in text or "e" in text.lower() and not text.lower().startswith("0x"):
        return float(text)
    return int(text, 0)


def number_repr(text: str) -> str:
    try:
        value = parse_number(text)
    except ValueError:
        return MALFORMED
    return str(value)


def cmp_repr(a, b) -> str:
    if isinstance(a, complex) or isinstance(b, complex):
        return "!domain"
    if isinstance(a, float) and math.isnan(a):
        return "!domain"
    if isinstance(b, float) and math.isnan(b):
        return "!domain"
    return str((a > b) - (a < b))


def arith_repr(a, b, op: str) -> str:
    try:
        if op == "add":
            value = a + b
        elif op == "sub":
            value = a - b
        elif op == "mul":
            value = a * b
        else:
            value = a / b
    except ZeroDivisionError:
        return "!div0"
    return str(value)


def main() -> None:
    random.seed(20261025)
    out = [
        "// Generated by scripts/gen_vectors.py from CPython. Do not edit.",
        "// Every row is an input and what Python answers for it.",
        "",
    ]
    out += lines("vec_parse_int", gen_parse_int(), "String, Int32, String")
    out += lines("vec_int_div", gen_int_div(), "String, String, String, String")
    out += lines("vec_pow", gen_pow(), "String, String, String, String")
    out += lines("vec_int_math", gen_int_math(), "String, String, String, String")
    out += lines("vec_bytes", gen_bytes(), "String, Int32, Bool, Bool, String")
    out += lines("vec_parse_float", gen_parse_float(), "String, String")
    out += lines("vec_repr", gen_repr(), "String, String")
    hex_out, hex_in = gen_hex()
    out += lines("vec_hex_out", hex_out, "String, String")
    out += lines("vec_hex_in", hex_in, "String, String")
    out += lines("vec_round", gen_round(), "String, String, Int32, String")
    out += lines("vec_floor", gen_floor(), "String, String, String, String")
    out += lines("vec_complex_parse", gen_complex_parse(), "String, String")
    out += lines("vec_complex_ops", gen_complex_ops(), "String, String, String, String")
    out += lines("vec_fraction_parse", gen_fraction_parse(), "String, String")
    out += lines("vec_fraction_ops", gen_fraction_ops(), "String, String, String, String")
    sweep_int, sweep_float = gen_format_sweep()
    out += lines("vec_format_sweep_int", sweep_int, "String, String, String")
    out += lines("vec_format_sweep_float", sweep_float, "String, String, String")
    out += lines("vec_format_int", gen_format_int(), "String, String, String")
    out += lines("vec_format_float", gen_format_float(), "String, String, String")
    out += lines("vec_format_complex", gen_format_complex(), "String, String, String, String")
    out += lines("vec_format_fraction_sweep", gen_format_fraction_sweep(),
                 "String, String, String, String")
    out += lines("vec_format_fraction", gen_format_fraction(), "String, String, String, String")
    out += lines("vec_number_parse", gen_number_parse(), "String, String")
    out += lines("vec_numbers", gen_numbers(), "String, String, String, String")
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))
    print(f"wrote {OUT}: {len(out)} lines")


if __name__ == "__main__":
    sys.exit(main())
