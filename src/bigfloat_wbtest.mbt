// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The behaviour the generated vectors cannot state: the shape a value keeps, the
// order of two of them, and the text that comes back out.

///|
/// Whether `got` is `want` to `bits` bits, which is how an answer that came from
/// a series is compared with one that came from a formula.
fn assert_close(got : BigFloat, want : BigFloat, bits : Int32) -> Unit raise {
  let gap = (got - want).abs()
  if !gap.is_zero() && !negligible(gap, want.abs(), bits) {
    fail("want \{want}, got \{got}")
  }
}

///|
/// Where a parse stopped, or `-1` when it did not stop at all.
fn stopped_at(text : String) -> Int32 {
  let mut stop = -1
  let attempt : Unit = try {
    let _ = BigFloat::parse(text)
    ()
  } catch {
    (err : Refused) =>
      stop = match err {
        Malformed(at~, ..) => at
        _ => -2
      }
  }
  let _ = attempt
  stop
}

///|
test "a decimal reads back as the value it writes" {
  for text in ["0.5", "0.1", "-0.1", "1e-40", "1e+40", "3.14159", "-2.5"] {
    let value = BigFloat::parse(text)
    assert_eq(value.to_string(), text)
  }
}

///|
test "the width a value keeps is the width it was rounded to" {
  for width in [1, 2, 24, 53, 100, 1000] {
    let c = Context::new(width)
    let value = c.div(BigFloat::one(context=c), BigFloat::of_int(3, context=c))
    assert_eq(value.precision(), width)
    assert_true(magnitude(value.mantissa).bit_length() <= width)
  }
}

///|
test "zero has no exponent and no sign" {
  let zero = BigFloat::zero()
  assert_eq(zero.to_string(), "0.0")
  assert_eq(zero.sign(), 0)
  assert_eq(zero.exponent, 0)
  assert_true(zero.is_zero())
  assert_true(-zero == zero)
  assert_eq(BigFloat::parse("-0.0").to_string(), "0.0")
}

///|
test "one third at three widths" {
  let one = BigFloat::one()
  let three = BigFloat::of_int(3)
  assert_eq((one / three).to_string(), "0.3333333333333333")
  let wide = Context::new(200)
  assert_eq(
    wide.div(one, three).to_significant(60),
    "0.333333333333333333333333333333333333333333333333333333333333",
  )
  // Two bits: the neighbours are a quarter and three eighths, and a third is
  // nearer the second — which the shortest spelling of calls four tenths, since
  // that reads back to it.
  let two_bits = Context::new(2).div(one, three)
  assert_eq(two_bits.to_significant(3), "0.375")
  assert_eq(two_bits.to_string(), "0.4")
}

///|
test "an operation keeps the wider of its two operands" {
  let narrow = BigFloat::one()
  let wide = BigFloat::one(context=Context::new(200))
  assert_eq((narrow + wide).precision(), 200)
  assert_eq((narrow + narrow).precision(), 53)
  assert_eq((wide * narrow).precision(), 200)
  assert_eq(narrow.sqrt().precision(), 53)
}

///|
test "every rounding direction on one tie" {
  // 1 + 2^-53 is exactly halfway between one and the next value at 53 bits.
  let one = BigFloat::one()
  let tiny = BigFloat::parse("1.1102230246251565404236316680908203125e-16")
  let at = (rounding : Rounding) => Context::new(53, rounding~)
  let above = BigFloat::parse("1.0000000000000002")
  assert_true(at(Nearest).add(one, tiny) == one)
  assert_true(at(Down).add(one, tiny) == one)
  assert_true(at(Up).add(one, tiny) == above)
  assert_true(at(Floor).add(one, tiny) == one)
  assert_true(at(Ceiling).add(one, tiny) == above)
}

///|
test "the direction of a negative sum is the other way round" {
  let minus_one = -BigFloat::one()
  let tiny = BigFloat::parse("1.1102230246251565404236316680908203125e-16")
  let below = BigFloat::parse("-1.0000000000000002")
  let at = (rounding : Rounding) => Context::new(53, rounding~)
  assert_true(at(Nearest).add(minus_one, -tiny) == minus_one)
  assert_true(at(Floor).add(minus_one, -tiny) == below)
  assert_true(at(Ceiling).add(minus_one, -tiny) == minus_one)
  assert_true(at(Up).add(minus_one, -tiny) == below)
  assert_true(at(Down).add(minus_one, -tiny) == minus_one)
}

///|
test "an operand too small to reach the last place still decides the direction" {
  let one = BigFloat::one()
  let dust = BigFloat::parse("1e-100")
  let above = BigFloat::parse("1.0000000000000002")
  assert_true(one + dust == one)
  assert_true(one - dust == one)
  let below = BigFloat::parse("0.9999999999999999")
  let lower = BigFloat::parse("-1.0000000000000002")
  assert_true(Context::new(53, rounding=Up).add(one, dust) == above)
  // Just above one, away from zero is the next value up; just below it, toward
  // zero is the value below and away from zero is one itself.
  assert_true(Context::new(53, rounding=Up).sub(one, dust) == one)
  assert_true(Context::new(53, rounding=Down).sub(one, dust) == below)
  assert_true(Context::new(53, rounding=Floor).sub(one, dust) == below)
  assert_true(Context::new(53, rounding=Down).add(-one, -dust) == -one)
  assert_true(Context::new(53, rounding=Floor).add(-one, -dust) == lower)
  assert_true(Context::new(53, rounding=Up).add(-one, -dust) == lower)
}

///|
test "the specials propagate the way IEEE 754 says" {
  let inf = BigFloat::infinity()
  let nan = BigFloat::nan()
  assert_true((inf + inf).is_infinite())
  assert_true((inf - inf).is_nan())
  assert_true((BigFloat::zero() * inf).is_nan())
  assert_true((inf / inf).is_nan())
  assert_true((BigFloat::one() / BigFloat::zero()).is_infinite())
  assert_true((BigFloat::zero() / BigFloat::zero()).is_nan())
  assert_true((nan + BigFloat::one()).is_nan())
  assert_true((-inf).is_infinite())
  assert_true((-inf).sign() < 0)
  assert_false(nan == nan)
  assert_true(nan != nan)
}

///|
test "dividing by zero can be caught instead" {
  let outcome = BigFloat::one().divide(BigFloat::zero()).to_string() catch {
      ZeroDivision => "refused"
      _ => "answered"
    }
  assert_eq(outcome, "refused")
}

///|
test "the order of two values, and of the specials" {
  let one = BigFloat::one()
  assert_true(one < BigFloat::of_int(2))
  assert_true(BigFloat::of_int(-2) < one)
  assert_true(
    BigFloat::infinity() > BigFloat::of_int(1000000, context=Context::new(200)),
  )
  assert_true(BigFloat::negative_infinity() < BigFloat::of_int(-1000000))
  assert_true(BigFloat::nan() > BigFloat::infinity())
  assert_eq(BigFloat::nan().compare(BigFloat::nan()), 0)
  // A value a double cannot tell from its neighbour: the comparison is exact, so
  // the integer one above 2^53 is still the greater.
  let big = BigFloat::of_bigint(
    @bigint.BigInt::from_string("9007199254740993"),
    context=Context::new(200),
  )
  let as_double = BigFloat::of_double(9007199254740992.0)
  assert_true(big > as_double)
  assert_false(big == as_double)
}

///|
test "a double in and out, exactly" {
  let values : Array[Double] = [
    0.1, -0.0, 1.5, 1.0e300, 5.0e-324, -2.2250738585072014e-308,
  ]
  for value in values {
    let back = BigFloat::of_double(value).to_double()
    assert_true(back == value)
  }
  assert_true(BigFloat::of_double(0.0).is_zero())
  assert_true(BigFloat::of_double(@double.infinity).is_infinite())
  assert_true(BigFloat::of_double(@double.not_a_number).is_nan())
}

///|
test "a value past a double is an infinity or a zero on the way back" {
  assert_true(BigFloat::parse("1e400").to_double() == @double.infinity)
  assert_eq(BigFloat::parse("1e-400").to_double(), 0.0)
  let largest = BigFloat::parse("1.7976931348623157e308")
  assert_true(largest.to_double() == 1.7976931348623157e308)
}

///|
test "an integer out of a value, with a direction" {
  let half = BigFloat::parse("2.5")
  assert_eq(half.to_bigint(), 2N)
  assert_eq(half.to_bigint(rounding=Up), 3N)
  assert_eq(BigFloat::parse("3.5").to_bigint(), 4N)
  assert_eq(BigFloat::parse("-2.5").to_bigint(rounding=Floor), -3N)
  assert_eq(BigFloat::parse("-2.5").to_bigint(), -2N)
  let outcome = BigFloat::nan().to_bigint().to_string() catch {
      Domain(_) => "refused"
      _ => "answered"
    }
  assert_eq(outcome, "refused")
}

///|
test "a fixed-point value in both directions" {
  let bits = Fixed::bits_for_digits(30)
  let fixed = Fixed::one(bits) / Fixed::of_int(3, bits)
  let value = BigFloat::of_fixed(fixed, context=Context::new(200))
  assert_eq(value.to_significant(20), "0.33333333333333333333")
  assert_true(value.to_fixed(bits) == fixed)
}

///|
test "the way a value is written out" {
  assert_eq(BigFloat::nan().to_string(), "nan")
  assert_eq(BigFloat::infinity().to_string(), "inf")
  assert_eq(BigFloat::negative_infinity().to_string(), "-inf")
  assert_eq(BigFloat::of_int(2).to_string(), "2.0")
  assert_eq(BigFloat::parse("1e15").to_string(), "1000000000000000.0")
  assert_eq(BigFloat::parse("1e16").to_string(), "1e+16")
  assert_eq(BigFloat::parse("1e-4").to_string(), "0.0001")
  assert_eq(BigFloat::parse("1e-5").to_string(), "1e-05")
  assert_eq(BigFloat::parse("-0.5").to_string(), "-0.5")
}

///|
test "a fixed count of places is a promise" {
  let half = BigFloat::parse("0.5")
  assert_eq(half.to_decimal(0), "0")
  assert_eq(half.to_decimal(1), "0.5")
  assert_eq(half.to_decimal(4), "0.5000")
  assert_eq(BigFloat::parse("-0.5").to_decimal(2), "-0.50")
  assert_eq(BigFloat::zero().to_decimal(3), "0.000")
  assert_eq(BigFloat::parse("1e20").to_decimal(2), "100000000000000000000.00")
  assert_eq(BigFloat::nan().to_decimal(2), "nan")
}

///|
test "text from outside, and where it stops" {
  assert_true(BigFloat::parse("  inf  ").is_infinite())
  assert_true(BigFloat::parse("-Infinity").sign() < 0)
  assert_true(BigFloat::parse("NaN").is_nan())
  assert_eq(BigFloat::parse("1_000.5").to_string(), "1000.5")
  assert_eq(BigFloat::parse(".5").to_string(), "0.5")
  assert_eq(BigFloat::parse("5.").to_string(), "5.0")
  assert_eq(stopped_at("12x"), 2)
  assert_eq(stopped_at(""), 0)
  assert_eq(stopped_at("1e"), 2)
  assert_eq(stopped_at("1.2.3"), 3)
  assert_eq(stopped_at("nanish"), 3)
}

///|
test "a difference of two nearby values keeps what cancels" {
  let c = Context::new(200)
  let big = BigFloat::parse(
    "1.0000000000000000000000000000000000001",
    context=c,
  )
  let difference = big - BigFloat::one(context=c)
  assert_eq(difference.to_significant(8), "1e-37")
  assert_eq((big - big).to_string(), "0.0")
  assert_eq((big + -big).sign(), 0)
}

///|
test "the functions are inverses of each other" {
  let c = Context::new(200)
  let value = BigFloat::parse("3.25", context=c)
  let three = BigFloat::of_int(3, context=c)
  assert_close(value.exp(context=c).ln(context=c), value, 190)
  assert_close(value.ln(context=c).exp(context=c), value, 190)
  assert_close(value.sqrt(context=c) * value.sqrt(context=c), value, 190)
  assert_close(value.pow(three, context=c), value * value * value, 190)
  assert_close(value.sinh(context=c).asinh(context=c), value, 185)
  assert_close(value.tanh(context=c).atanh(context=c), value, 185)
  let two = BigFloat::of_int(2, context=c)
  assert_close(two.acosh(context=c).cosh(context=c), two, 185)
  let quarter = value.atan(context=c)
  assert_close(quarter.tan(context=c), value, 185)
  assert_close(
    value.sin(context=c).pow(two, context=c) +
    value.cos(context=c).pow(two, context=c),
    BigFloat::one(context=c),
    190,
  )
}

///|
test "a power of a negative base keeps the sign of an odd exponent" {
  let c = Context::new(120)
  let minus_two = BigFloat::of_int(-2, context=c)
  let three = BigFloat::of_int(3, context=c)
  assert_true(
    minus_two.pow(three, context=c) == BigFloat::of_int(-8, context=c),
  )
  assert_true(
    minus_two.pow(BigFloat::of_int(2, context=c), context=c) ==
    BigFloat::of_int(4, context=c),
  )
  assert_true(minus_two.pow(BigFloat::of_double(0.5), context=c).is_nan())
  assert_eq(
    minus_two.pow(BigFloat::of_int(-3, context=c), context=c).to_string(),
    "-0.125",
  )
}

///|
test "the constants are the ones every table agrees on" {
  let c = Context::new(200)
  assert_eq(
    BigFloat::pi(context=c).to_significant(30),
    "3.14159265358979323846264338328",
  )
  assert_eq(
    BigFloat::e(context=c).to_significant(30),
    "2.71828182845904523536028747135",
  )
  assert_eq(
    BigFloat::ln2(context=c).to_significant(30),
    "0.693147180559945309417232121458",
  )
  assert_close(
    BigFloat::pi(context=c).sin(context=c),
    BigFloat::zero(context=c),
    190,
  )
  assert_close(
    BigFloat::pi(context=c).cos(context=c),
    -BigFloat::one(context=c),
    190,
  )
  assert_eq(BigFloat::e(context=c).ln(context=c).to_string(), "1.0")
}

///|
test "a value that is not a number is not a number" {
  let nan = BigFloat::nan()
  assert_true(nan.is_nan())
  assert_false(nan.is_finite())
  assert_false(nan.is_infinite())
  assert_false(nan.is_zero())
  assert_eq(nan.sign(), 0)
  assert_true(nan.exp().is_nan())
  assert_true(nan.ln().is_nan())
  assert_true(nan.sqrt().is_nan())
  assert_true((-nan).is_nan())
}

///|
test "a very large argument of a trigonometric function is reduced, not refused" {
  let c = Context::new(120)
  // The sine of ten to the thirtieth needs the turn to thirty digits past the
  // point, and the answer is still a number.
  let value = BigFloat::parse("1e30", context=c).sin(context=c)
  assert_true(value.abs() < BigFloat::one(context=c))
  assert_eq(value.to_significant(15), "-0.0901169019121381")
}
