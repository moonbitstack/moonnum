---
name: moonnum
description: Numbers in MoonBit with moonbitstack/moonnum — arbitrary-precision integers, doubles read and written honestly, complex numbers written 3+4j, exact fractions, a real carried to any width, and Python's format-specification language. Use when a MoonBit program needs exact decimal output, a ratio that must not round, an integer past 64 bits, a real to more digits than a double holds, or text read and written the way Python reads and writes it.
---

# moonnum

Add the module and import it in `moon.pkg`:

```bash
moon add moonbitstack/moonnum
```

```moonbit
import {
  "moonbitstack/moonnum",
}
```

One package, one error type (`@moonnum.Refused`), one formatting language.

## Pick the kind

| Need | Type | Cost |
|:--|:--|:--|
| Any size integer | `@bigint.BigInt` plus the functions here | exact |
| Exact ratio | `@moonnum.Fraction` | exact, always in lowest terms |
| A double, honestly printed | `Double` plus `repr_float` | 53 bits |
| Complex | `@moonnum.Complex` | two doubles |
| More digits than a double holds | `@moonnum.BigFloat` | a width you choose |
| A complex number at that width | `@moonnum.BigComplex` | two widths you choose |

`@moonnum.Number` holds the middle four and does the mixing, promoting along
integer → fraction → float → complex and comparing exactly.

## Print a number the way Python prints it

```moonbit
test "print a number the way Python prints it" {
  assert_eq(@moonnum.repr_float(0.1 + 0.2), "0.30000000000000004")
  assert_eq(@moonnum.parse_float("1_000.5e-2"), 10.005)
  assert_eq(@moonnum.format(@moonnum.parse("22/7"), ".6f"), "3.142857")
  assert_eq(@moonnum.format_int(255N, "#010_x"), "0x000_00ff")
}
```

`format` is Python's mini-language whole — fill, alignment, sign, `z`, `#`, `0`,
width, grouping, precision and the types `b c d e E f F g G n o x X %` — and it
works on every kind. `repr_float` is the shortest text that reads back as the
same double.

## Keep a ratio exact

```moonbit
test "keep a ratio exact" {
  let third = @moonnum.parse("1/3")
  let total = @moonnum.parse("1") + third + @moonnum.parse("0.5")
  assert_eq(total.to_string(), "1.8333333333333333")
  assert_eq(@moonnum.parse_fraction("0.1").to_string(), "1/10")     // exactly
}
```

`Fraction`'s `+ - *` are operators and never round. Division is
`Fraction::divide`, a function, because a divisor of zero has no answer and an
operator cannot say so.

## More digits than a double holds

```moonbit
test "more digits than a double holds" {
  let c = @moonnum.Context::new(200)
  let two = @moonnum.BigFloat::of_int(2, context=c)
  assert_eq(
    two.sqrt(context=c).to_significant(50),
    "1.4142135623730950488016887242096980785696718753769",
  )
  assert_eq(
    @moonnum.BigFloat::pi(context=c).to_significant(50),
    "3.1415926535897932384626433832795028841971693993751",
  )
  assert_eq(
    two.pow(@moonnum.BigFloat::of_double(0.5), context=c).to_significant(50),
    "1.4142135623730950488016887242096980785696718753769",
  )
}
```

A `Context` is a width in bits and a rounding direction. An operator keeps the
wider of its two operands and rounds to nearest even; `Context::add`, `sub`,
`mul`, `div` and `divide` take both from the context:

```moonbit
test "a context takes the width and the direction" {
  let up = @moonnum.Context::new(53, rounding=@moonnum.Rounding::Up)
  assert_eq(
    up.add(@moonnum.BigFloat::one(), @moonnum.BigFloat::parse("1e-100")).to_string(),
    "1.0",
  )
}
```

`@moonnum.Rounding` has `Nearest`, `Floor`, `Ceiling`, `Down` and `Up`.

## Two answers the obvious spelling loses

`expm1` and `log1p`, on `BigFloat` and `Fixed`, are `e^x - 1` and `ln(1 + x)`
summed without forming the one that would swallow a small argument:

```moonbit
test "expm1 and log1p, at a width a double cannot hold" {
  let c = @moonnum.Context::new(200)
  let one = @moonnum.BigFloat::of_int(1, context=c)
  assert_eq(one.expm1(context=c).to_significant(50), "1.7182818284590452353602874713526624977572470937")
  assert_eq(one.log1p(context=c).to_significant(50), "0.69314718055994530941723212145817656807550013436026")
}
```

`BigFloat` answers `nan` where the value is complex and `±inf` at the edges;
`Fixed` stops the program there, as `Fixed::sqrt` and `Fixed::ln` do.

## Rules that bite

- **Division is a function where it can fail.** `Fraction::divide`,
  `Complex::divide` and `BigFloat::divide` raise `@moonnum.Refused`;
  `/` on `BigFloat` answers `±inf` and `nan` instead, and `Fixed::div` stops the
  program, because those operators have nowhere to put a refusal.
- **`Refused` carries where and what.** `Malformed(at~, reason~)` gives the
  offset in UTF-16 code units, which is what `StringView` indexes by.
- **A `BigFloat` is only as good as its width.** `Context::new(200)` is 200 bits,
  about sixty digits; a digit costs three and a third bits.
- **`Fixed` is not a `BigFloat`.** `Fixed` is `mantissa / 2^bits`: its width is
  fractional bits, so a value far from one keeps few significant digits. Reach
  for `BigFloat` unless a whole computation is meant to carry one width.
- **`Number` has no `BigFloat` in it.** The four kinds are widthless; a value
  with a width stands beside the tower.
- **A real function answers `nan` where the value is complex.** `BigFloat::sqrt`
  of a negative, `ln` of a negative, `asin` past one: those are the answers the
  real type owes an IEEE 754 consumer. The value is one promotion away —
  `x.to_complex().sqrt(context=c)` — and `BigComplex` carries the principal
  branches, with the cut read from above because nothing here can spell a signed
  zero.
