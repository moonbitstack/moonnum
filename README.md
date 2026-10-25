<div align="center">

# moonnum

**Numbers in MoonBit that behave the way you expect them to.**

Arbitrary-precision integers, IEEE-754 floats with honest text, complex
numbers written `3+4j`, and exact fractions — one package, one error type, one
formatting language.

</div>

```moonbit
let n = @moonnum.parse_int("0xff_ec", base=0)      // 65516, any base, any size
let z = @moonnum.parse_complex("3+4j")             // (3+4j)
let f = @moonnum.parse_fraction("0.1")             // 1/10, exactly

@moonnum.repr_float(0.1 + 0.2)                     // "0.30000000000000004"
@moonnum.format(f, ".3%")                          // "10.000%"
```

Nothing in here rounds behind your back. `0.1` as a fraction is one tenth;
`0.1` as a float is the double it really is, and says so when asked:

```moonbit
@moonnum.repr_float(0.1)              // "0.1"     shortest string that reads back
@moonnum.float_hex(0.1)               // "0x1.999999999999ap-4"
@moonnum.as_ratio(0.1)                // 3602879701896397/36028797018963968
@moonnum.repr_float(0.1 + 0.2)        // "0.30000000000000004"
@moonnum.format(@moonnum.parse("22/7"), ".6f")   // "3.142857", exactly rounded
```

## Install

```bash
moon add moonbitstack/moonnum
```

```moonbit
import { "moonbitstack/moonnum" }
```

Runs on `wasm`, `wasm-gc`, `js` and `native`.

## The four kinds

<table>
<tr><th align="left">Kind</th><th align="left">Type</th><th align="left">What it is</th></tr>
<tr><td><b>Integer</b></td><td><code>@bigint.BigInt</code></td><td>core's arbitrary-precision integer, with what it is missing: floor division, a modulo that takes the divisor's sign, modular powers, <code>isqrt</code>, <code>comb</code>, <code>perm</code>, bytes.</td></tr>
<tr><td><b>Float</b></td><td><code>Double</code></td><td>IEEE-754 binary64, read and written so that the text is the shortest one that reads back.</td></tr>
<tr><td><b>Complex</b></td><td><code>Complex</code></td><td><code>{ re, im }</code> of doubles, with the signed-zero and infinity rules spelled out.</td></tr>
<tr><td><b>Fraction</b></td><td><code>Fraction</code></td><td><code>{ num, den }</code>, always in lowest terms with a positive denominator.</td></tr>
</table>

`Number` holds any of the four and does the mixing:

```moonbit
let third = @moonnum.parse("1/3")
let total = @moonnum.parse("1") + third + @moonnum.parse("0.5")   // 11/6
let judged = @moonnum.parse("1") == @moonnum.parse("1.0")         // true
```

Promotion follows the tower — integer, fraction, float, complex — and
comparison is exact: `9007199254740993` is greater than `9007199254740992.0`,
which a float-first comparison gets wrong.

## Reading

| Function | Reads |
|:--|:--|
| `parse_int(text, base~ = 10)` | `int(s, base)`: prefixes when `base` is 0, single underscores between digits, surrounding whitespace |
| `parse_float(text)` | `float(s)`: `inf`, `infinity`, `nan` in any case, decimal and exponent forms, underscores |
| `parse_complex(text)` | `complex(s)`: `1+2j`, `(1+2j)`, `j`, `-j`, `1e3j` — and `3+5i` |
| `parse_fraction(text)` | `Fraction(s)`: `3/4`, `-1.25`, `1e-3`, `7` |
| `parse(text)` | a `Number` of whichever kind the literal spells |

## Writing

| Function | Writes |
|:--|:--|
| `repr_float(d)` | the shortest string that reads back, switching to an exponent at `1e16` and `1e-5` |
| `float_hex(d)` / `float_of_hex(s)` | the exact hexadecimal form, and back |
| `repr_complex(z)`, `repr_fraction(f)` | `(1+2j)`, `2j`, `Fraction(3, 4)` |
| `format(value, spec)` | the format-specification mini-language, for any kind |

### The format language

```
[[fill]align][sign][z][#][0][width][grouping][.precision][type]
```

```moonbit
@moonnum.format_int(1234567N, "015,d")        // "000,001,234,567"
@moonnum.format_int(255N, "#010_x")           // "0x000_00ff"
@moonnum.format_float(0.25, ".2%")            // "25.00%"
@moonnum.format_float(-0.0, "z")              // "0.0"
z.format(".2f")                                // "3.00+4.00j"
```

Types `b c d e E f F g G n o x X %` and no type at all; fill and alignment
`< > ^ =`; sign `+ - space`; `#` alternate form; `0` zero padding that
participates in grouping; grouping `,` and `_`, four digits to a group for
binary, octal and hexadecimal.

## Arithmetic that can fail, fails on purpose

One error type, four cases, no panics:

```moonbit
pub(all) suberror Refused {
  Malformed(at~ : Int, reason~ : String)   // where the text stopped making sense
  ZeroDivision
  Overflow(reason~ : String)
  Domain(reason~ : String)
}
```

```moonbit
let half = @moonnum.parse_fraction("1/2")
let bad : String = half.divide(@moonnum.parse_fraction("0")).to_string() catch {
  @moonnum.ZeroDivision => "no"
  _ => "no"
}
```

`at` counts UTF-16 code units, so it can be used to slice the input directly.
Division is a function and not an operator (`Fraction::divide`,
`Complex::divide`) because MoonBit's `Div` trait cannot raise, and a numeric
library that panics on zero is worse than one that says so.

## What this is not

- **Not a decimal type.** `Decimal` has a context, signals and rounding modes;
  that is a different problem.
- **Not a bignum encoding.** Variable-length integer encodings live elsewhere.
- **Not complex math.** `cmath`'s functions are out until something needs them.

## Documentation

- [Tutorial](https://moonbitstack.github.io/moonnum/01-integers.html) — five
  pages, one per kind plus formatting. Every block on them comes from the
  example beside it, so the output printed there is the output the program
  prints.
- [API reference](https://moonbitstack.github.io/moonnum/api.html) — every
  public item.
- [Design notes](https://moonbitstack.github.io/moonnum/algorithms.html) — how
  the digits are produced, and why the tower compares exactly.
- `src/examples/` — `moon run src/examples/01-integers` and friends.

## Licence

Apache-2.0.
