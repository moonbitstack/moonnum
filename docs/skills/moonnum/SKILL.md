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

`@moonnum.Number` holds the middle four and does the mixing, promoting along
integer → fraction → float → complex and comparing exactly.

## Print a number the way Python prints it

```moonbit
@moonnum.repr_float(0.1 + 0.2)          // "0.30000000000000004"
@moonnum.parse_float("1_000.5e-2")      // 10.005
@moonnum.format(@moonnum.parse("22/7"), ".6f")   // "3.142857"
@moonnum.format_int(255N, "#010_x")     // "0x000_00ff"
```

`format` is Python's mini-language whole — fill, alignment, sign, `z`, `#`, `0`,
width, grouping, precision and the types `b c d e E f F g G n o x X %` — and it
works on every kind. `repr_float` is the shortest text that reads back as the
same double.

## Keep a ratio exact

```moonbit
let third = @moonnum.parse("1/3")
let total = @moonnum.parse("1") + third + @moonnum.parse("0.5")   // 11/6
@moonnum.parse_fraction("0.1")                                    // 1/10, exactly
```

`Fraction`'s `+ - *` are operators and never round. Division is
`Fraction::divide`, a function, because a divisor of zero has no answer and an
operator cannot say so.

## More digits than a double holds

```moonbit
let c = @moonnum.Context::new(200)
let two = @moonnum.BigFloat::of_int(2, context=c)

two.sqrt(context=c).to_significant(50)
@moonnum.BigFloat::pi(context=c).to_significant(50)
two.pow(@moonnum.BigFloat::of_double(0.5), context=c)
```

A `Context` is a width in bits and a rounding direction. An operator keeps the
wider of its two operands and rounds to nearest even; `Context::add`, `sub`,
`mul`, `div` and `divide` take both from the context:

```moonbit
let up = @moonnum.Context::new(53, rounding=@moonnum.Rounding::Up)
up.add(@moonnum.BigFloat::one(), @moonnum.BigFloat::parse("1e-100"))   // 1.0000000000000002
```

`@moonnum.Rounding` has `Nearest`, `Floor`, `Ceiling`, `Down` and `Up`.

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
