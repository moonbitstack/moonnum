<div align="center">

# moonnum

**Numbers in MoonBit that behave the way you expect them to.**

Arbitrary-precision integers, IEEE-754 floats with honest text, complex
numbers written `3+4j`, exact fractions, and a real carried to any width —
one package, one error type, one formatting language.

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

## A real with a width

The four kinds above are exact where they can be and binary where they must be.
There is a fifth type for the case in between — a real carried at a precision
the caller chooses, for the series and the expansions that a double cannot
finish:

```moonbit
let bits = @moonnum.Fixed::bits_for_digits(50)
let two = @moonnum.Fixed::of_int(2, bits)
two.sqrt().to_string()                       // 1.41421356237309504880168872420969807856967187537695
two.sqrt() * two.sqrt() < two                // true: each step truncates
(two * @moonnum.Fixed::pi(bits)).to_decimal(10)   // 6.2831853072
@moonnum.parse_fixed("1e-3", bits) catch { _ => two }   // text from outside, refused with where it stopped
```

`Fixed` is `mantissa / 2^bits`: fixed point, so the rounding of every step is one
truncation and a whole computation carries one width. It has `+ - * /`, comparison,
`sqrt`, `exp`, `ln`, a real `pow`, `sin`, `cos`, `atan`, and `pi`/`ln2` to as many
digits as the width holds. An operation keeps the left operand's width and brings the
right one to it; `at` changes a value's width. `of_scaled(digits, places)` seeds it
from a decimal constant, `of_decimal` reads a literal a program carries, `parse_fixed`
reads one from outside, and `to_decimal(places)` writes it back.

A value outside an operation's domain, such as the square root of a negative number,
stops the program with the reason, as an integer division by zero does: these are
written with operators, which cannot raise.

It is not one of the `Number` kinds, and that is deliberate: those are widthless, and
a value here is only as good as the width a caller chose for it.

## A real carried to any width

The four kinds are widthless: an integer has as many digits as it needs, a float
has exactly fifty-three, a fraction is exact or is not. `BigFloat` is the case in
between — `mantissa * 2^exponent`, with the width the value was rounded to kept
beside it, so every value keeps the same count of digits wherever it sits on the
line.

```moonbit
let c = @moonnum.Context::new(200)
let two = @moonnum.BigFloat::of_int(2, context=c)

two.sqrt(context=c).to_significant(60)      // 1.41421356237309504880168872420969807856967187537694807317668
@moonnum.BigFloat::pi(context=c).to_significant(60)
                                            // 3.14159265358979323846264338327950288419716939937510582097494
two.pow(@moonnum.BigFloat::of_double(0.5), context=c)   // the same as sqrt
```

An operator keeps the wider of its two operands and rounds to nearest even:
the answer is as good as what went into it and no better. A `Context` is a width
and a direction together, and the five directions are the ones `mpmath` names —
nearest even, floor, ceiling, toward zero, away from zero.

```moonbit
@moonnum.Rounding::Nearest     // ties to the even digit
@moonnum.Rounding::Floor       // toward minus infinity
@moonnum.Rounding::Ceiling     // toward plus infinity
@moonnum.Rounding::Down        // toward zero
@moonnum.Rounding::Up          // away from zero

let flinch = @moonnum.Context::new(53, rounding=@moonnum.Rounding::Up)
flinch.add(@moonnum.BigFloat::one(), @moonnum.BigFloat::parse("1e-100"))   // 1.0000000000000002
```

`sqrt`, `exp`, `ln`, `pow` — and `expm1` and `log1p`, which are the same two
answers taken without ever forming the one that would swallow a small argument —
the circular and the hyperbolic functions are all there, computed at the width
asked for from series and formulas — `pi` is
Machin's, `ln 2` is two arctangents of a third, `e` is the exponential of one.
Nothing in the source is a table of digits that could go stale, and a thousand
digits costs a few thousand terms and nothing else.

`Kind` is what a value is: `Finite`, `PositiveInfinity`, `NegativeInfinity`,
`NotANumber`. A square root of a negative, a logarithm of a negative and a
quotient of zero by zero answer the NaN; a quotient by zero answers an infinity,
and `divide` is the same quotient for a caller who would rather be told.

A value goes into and out of the other shapes the library already has —
`@bigint.BigInt`, `Fixed`, `Double`, decimal text — and a double makes the round
trip unchanged, since every finite double is a binary fraction already.

## Arithmetic

| On | Functions |
|:--|:--|
| integers | `floordiv`, `floor_mod`, `divmod`, `power` (with `modulus~`), `gcd`, `lcm`, `isqrt`, `factorial`, `comb`, `perm`, `bit_length`, `to_bytes`, `of_bytes` |
| floats | `round_float(d, ndigits~)`, `round_big`, `floor_big`, `ceil_big`, `trunc_big`, `as_ratio`, `as_integer_ratio` |
| complex | `+ - *`, `Complex::divide`, `Complex::pow`, `abs`, `conjugate` |
| fractions | `+ - *`, `Fraction::divide`, `Fraction::pow`, `compare`, `floor_big`, `ceil_big`, `round`, `round_big`, `to_double`, `limit_denominator` |
| any of them | `Number::add`, `Number::sub`, `Number::mul`, `Number::divide`, `Number::pow`, `compare_numeric`, `equal_numeric` |
| `BigFloat` | `+ - * /`, `divide`, `abs`, `sqrt`, `exp`, `expm1`, `ln`, `log1p`, `pow`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `round`, `pi`, `e`, `ln2` |

`Fraction::pow` takes an integer exponent and stays a ratio — `(2/3) ** 100` is
an exact numerator over an exact denominator — while `Number::pow` follows the
tower and gives a float when an exponent is one.

## Reading

| Function | Reads |
|:--|:--|
| `parse_int(text, base~ = 10)` | `int(s, base)`: prefixes when `base` is 0, single underscores between digits, surrounding whitespace |
| `parse_float(text)` | `float(s)`: `inf`, `infinity`, `nan` in any case, decimal and exponent forms, underscores |
| `parse_complex(text)` | `complex(s)`: `1+2j`, `(1+2j)`, `j`, `-j`, `1e3j` — and `3+5i` |
| `parse_fraction(text)` | `Fraction(s)`: `3/4`, `-1.25`, `1e-3`, `7` |
| `parse(text)` | a `Number` of whichever kind the literal spells |
| `BigFloat::parse(text, context?)` | a decimal at a width: `inf`, `infinity`, `nan`, exponents, underscores, surrounding whitespace |

## Writing

| Function | Writes |
|:--|:--|
| `repr_float(d)` | the shortest string that reads back, switching to an exponent at `1e16` and `1e-5` |
| `float_hex(d)` / `float_of_hex(s)` | the exact hexadecimal form, and back |
| `repr_complex(z)`, `repr_fraction(f)` | `(1+2j)`, `2j`, `Fraction(3, 4)` |
| `format(value, spec)` | the format-specification mini-language, for any kind |
| `to_string` | as many digits as the width speaks for — fifteen at 53 bits, sixty at 200 — trailing zeros dropped |
| `to_decimal(places)`, `to_significant(digits)` | an exact count of places, or of significant digits |

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
- **Not a fifth kind in `Number`.** The tower's kinds are widthless, and a
  `BigFloat` is only as good as the width it carries, so it stands beside the
  tower rather than in it.

## Documentation

- [Tutorial](https://moonbitstack.github.io/moonnum/01-integers.html) — six
  pages, one per kind plus formatting and the real of any width. Every output
  block on them was produced by running the code above it, including the
  refusals.
- [API reference](https://moonbitstack.github.io/moonnum/api.html) — every
  public item.
- [Design notes](https://moonbitstack.github.io/moonnum/algorithms.html) — how
  the digits are produced, and why the tower compares exactly.
- `src/examples/` — `moon run src/examples/01-integers` and friends.

## Licence

Apache-2.0.
