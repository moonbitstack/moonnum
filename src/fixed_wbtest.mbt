// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The transcendental core against fifty-digit references from `mpmath`, so a
// passing test means the fixed-point series agree with an independent
// implementation to forty-five places rather than with themselves.

///|
test "exp, ln, sqrt and pi agree to fifty digits" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)

  let exp_one = Fixed::one(bits).exp()
  let want_exp_one = Fixed::of_scaled(
    "271828182845904523536028747135266249775724709369995", 50, bits,
  )
  assert_true(exp_one.approx(want_exp_one, tolerance))

  let ln_two = Fixed::of_int(2, bits).ln()
  let want_ln_two = Fixed::of_scaled(
    "69314718055994530941723212145817656807550013436025", 50, bits,
  )
  assert_true(ln_two.approx(want_ln_two, tolerance))

  let sqrt_two = Fixed::of_int(2, bits).sqrt()
  let want_sqrt_two = Fixed::of_scaled(
    "141421356237309504880168872420969807856967187537694", 50, bits,
  )
  assert_true(sqrt_two.approx(want_sqrt_two, tolerance))

  let pi = Fixed::pi(bits)
  let want_pi = Fixed::of_scaled(
    "314159265358979323846264338327950288419716939937510", 50, bits,
  )
  assert_true(pi.approx(want_pi, tolerance))
}

///|
test "sine, cosine and arctangent agree to fifty digits" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  let one = Fixed::one(bits)

  let sine = one.sin()
  let want_sine = Fixed::of_scaled(
    "84147098480789650665250232163029899962256306079837", 50, bits,
  )
  assert_true(sine.approx(want_sine, tolerance))

  let cosine = one.cos()
  let want_cosine = Fixed::of_scaled(
    "54030230586813971740093660744297660373231042061792", 50, bits,
  )
  assert_true(cosine.approx(want_cosine, tolerance))

  let quarter_turn = one.atan()
  let want_quarter_turn = Fixed::of_scaled(
    "78539816339744830961566084581987572104929234984377", 50, bits,
  )
  assert_true(quarter_turn.approx(want_quarter_turn, tolerance))

  // `atan(10)` is past one, where the halving has to run before the series will.
  let steep = Fixed::of_int(10, bits).atan()
  let want_steep = Fixed::of_scaled(
    "147112767430373459185287557176173085185530637718323", 50, bits,
  )
  assert_true(steep.approx(want_steep, tolerance))
}

///|
test "the square of the sine and the cosine is one" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  let value = Fixed::of_scaled("13", 1, bits)
  let sine = value.sin()
  let cosine = value.cos()
  let squares = sine.mul(sine).add(cosine.mul(cosine))
  assert_true(squares.approx(Fixed::one(bits), tolerance))
}

///|
test "a real power is the exponential of the logarithm" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  let two = Fixed::of_int(2, bits)
  let half = Fixed::of_scaled("5", 1, bits)
  let root = two.pow(half)
  let want = Fixed::of_scaled(
    "141421356237309504880168872420969807856967187537694", 50, bits,
  )
  assert_true(root.approx(want, tolerance))
}

///|
test "a decimal literal is read at the width it is asked for" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  let gamma = Fixed::of_decimal(
    "0.57721566490153286060651209008240243104215933593992", bits,
  )
  let want = Fixed::of_scaled(
    "57721566490153286060651209008240243104215933593992", 50, bits,
  )
  assert_true(gamma.approx(want, tolerance))
  // The exponent form, which is how a reference for a small tail is written.
  let tiny = Fixed::of_decimal("1.5e-12", bits)
  assert_true(tiny.approx(Fixed::of_scaled("15", 13, bits), tolerance))
  assert_true(Fixed::of_decimal("-0.5", bits).to_double() == -0.5)
  // A positive exponent too: `Double::to_string` writes one as `e+21`, and a
  // round trip through a string is how a caller hands a double to this type.
  assert_true(Fixed::of_decimal("1.5e+3", bits).to_double() == 1500.0)
  assert_true(Fixed::of_decimal("2.5E+2", bits).to_double() == 250.0)
  assert_true(Fixed::of_decimal("-1e+2", bits).to_double() == -100.0)
}

///|
test "exp and ln invert each other" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  let value = Fixed::of_scaled("15", 1, bits)
  assert_true(value.ln().exp().approx(value, tolerance))
  assert_true(value.exp().ln().approx(value, tolerance))
}

///|
test "the arithmetic is the arithmetic of the value it stands for" {
  let bits = Fixed::bits_for_digits(30)
  let three = Fixed::of_int(3, bits)
  let four = Fixed::of_int(4, bits)
  let sum = three.add(four)
  let product = three.mul(four)
  let quotient = three.div(four)
  assert_eq(sum.to_double(), 7.0)
  assert_eq(product.to_double(), 12.0)
  assert_eq(quotient.to_double(), 0.75)
  assert_eq(Fixed::zero(bits).to_double(), 0.0)
  assert_eq(Fixed::of_int(-5, bits).abs().to_double(), 5.0)
  assert_true(three < four)
  assert_true(Fixed::of_int(-5, bits) < three)
}

///|
test "pi, ln 2 and e keep their digits past the 120 the constants hold" {
  // From mpmath at 330 digits. A width that the old constants could not fill would
  // be right for the first 120 digits and wrong from there on.
  let bits = Fixed::bits_for_digits(300)
  let tolerance = Fixed::of_scaled("1", 295, bits)
  let pi = "3141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067982148086513282306647093844609550582231725359408128481117450284102701938521105559644622948954930381964428810975665933446128475648233786783165271201909145648566923460348610454326648213393607260249141274"
  let ln2 = "0693147180559945309417232121458176568075500134360255254120680009493393621969694715605863326996418687542001481020570685733685520235758130557032670751635075961930727570828371435190307038623891673471123350115364497955239120475172681574932065155524734139525882950453007095326366642654104239157814952043740"
  let e = "2718281828459045235360287471352662497757247093699959574966967627724076630353547594571382178525166427427466391932003059921817413596629043572900334295260595630738132328627943490763233829880753195251019011573834187930702154089149934884167509244761460668082264800168477411853742345442437107539077744992070"
  assert_true(
    Fixed::pi(bits).approx(Fixed::of_scaled(pi, 300, bits), tolerance),
  )
  assert_true(
    Fixed::ln2(bits).approx(Fixed::of_scaled(ln2, 300, bits), tolerance),
  )
  // Reaching these goes through the series the old loops capped at 400 terms.
  assert_true(
    Fixed::one(bits).exp().approx(Fixed::of_scaled(e, 300, bits), tolerance),
  )
  assert_true(
    Fixed::of_scaled(e, 300, bits).ln().approx(Fixed::one(bits), tolerance),
  )
  assert_true(
    Fixed::of_int(2, bits)
    .ln()
    .approx(Fixed::of_scaled(ln2, 300, bits), tolerance),
  )
}

///|
test "the operators read the way the methods did, and the two widths meet" {
  let wide = Fixed::bits_for_digits(50)
  let narrow = Fixed::bits_for_digits(20)
  let two = Fixed::of_int(2, wide)
  let three = Fixed::of_int(3, narrow)
  // The right operand comes to the left's width; it used to be read at the wrong one.
  assert_eq((two * three).to_double(), 6.0)
  assert_eq((two + three).to_double(), 5.0)
  assert_eq((three - two).to_double(), 1.0)
  assert_eq((Fixed::of_int(6, wide) / three).to_double(), 2.0)
  assert_eq((two * three).bits, wide)
  assert_eq((three * two).bits, narrow)
  assert_eq((-two).to_double(), -2.0)
  assert_true(two < three)
  assert_true(three > two)
  assert_true(Fixed::of_int(3, wide) == three)
  assert_true(Fixed::of_int(3, wide) != two)
}

///|
test "at widens exactly and narrows by truncation" {
  let value = Fixed::of_decimal("1.5", 64)
  assert_true(value.at(128) == value)
  assert_eq(value.at(128).bits, 128)
  let third = Fixed::of_int(1, 128) / Fixed::of_int(3, 128)
  assert_true(third.at(16) < third)
}

///|
test "to_decimal rounds, pads and carries the sign" {
  let bits = Fixed::bits_for_digits(30)
  assert_eq(Fixed::of_decimal("1.5", bits).to_decimal(3), "1.500")
  assert_eq(Fixed::of_decimal("0.125", bits).to_decimal(2), "0.13")
  assert_eq(Fixed::of_decimal("-0.125", bits).to_decimal(2), "-0.13")
  assert_eq(Fixed::of_decimal("0.04", bits).to_decimal(4), "0.0400")
  assert_eq(Fixed::of_decimal("2.5", bits).to_decimal(0), "3")
  assert_eq(Fixed::of_decimal("-0.001", bits).to_decimal(1), "0.0")
  assert_eq(Fixed::of_int(-7, bits).to_decimal(1), "-7.0")
  assert_eq(
    Fixed::pi(Fixed::bits_for_digits(60)).to_decimal(50),
    "3.14159265358979323846264338327950288419716939937511",
  )
}

///|
test "a value prints the digits its width was asked for" {
  let bits = Fixed::bits_for_digits(50)
  assert_eq(Fixed::of_decimal("1.5", bits).to_string(), "1.5")
  assert_eq(Fixed::of_int(2, bits).to_string(), "2.0")
  assert_eq(
    Fixed::of_int(2, bits).sqrt().to_string(),
    "1.41421356237309504880168872420969807856967187537695",
  )
  assert_eq(Fixed::of_int(2, 48).to_string(), "2")
}

///|
test "parse_fixed reads a literal and refuses the rest with where it stopped" {
  let bits = Fixed::bits_for_digits(20)
  assert_true(parse_fixed("1.5", bits) == Fixed::of_decimal("1.5", bits))
  assert_true(parse_fixed("+1.5", bits) == Fixed::of_decimal("1.5", bits))
  assert_true(parse_fixed("-.5", bits) == Fixed::of_decimal("-0.5", bits))
  assert_true(parse_fixed("5.", bits) == Fixed::of_int(5, bits))
  assert_true(parse_fixed("1e+2", bits) == Fixed::of_int(100, bits))
  assert_true(parse_fixed("25E-1", bits) == Fixed::of_decimal("2.5", bits))
  for
    bad in [
      ("", 0),
      ("-", 1),
      (".", 1),
      ("1x", 1),
      ("1e", 2),
      ("1e+", 3),
      ("1.2.3", 3),
      ("abc", 0),
    ] {
    assert_eq(refused_at(bad.0, bits), Some(bad.1))
  }
}

///|
/// Where `parse_fixed` stopped, or `None` when it read the text.
fn refused_at(text : String, bits : Int32) -> Int32? {
  try {
    ignore(parse_fixed(text, bits))
    None
  } catch {
    Malformed(at~, ..) => Some(at)
    _ => None
  }
}

///|
test "panic the square root of a negative number stops" {
  ignore(Fixed::of_int(-1, 64).sqrt())
}

///|
test "expm1 is exp minus one, and log1p is ln of one plus, away from zero" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  // Far from zero, where the answer is the ordinary function with one taken
  // off or added, the two spellings agree to the width.
  let ten = Fixed::of_int(10, bits)
  let expm1 = ten.expm1()
  assert_true(expm1.approx(ten.exp() - Fixed::one(bits), tolerance))
  let log1p = ten.log1p()
  assert_true(log1p.approx((Fixed::one(bits) + ten).ln(), tolerance))
  // And the identities that hold everywhere: `expm1(x) + 1` is `exp(x)` and
  // `log1p(e^x - 1)` is `x`.
  let small = Fixed::of_decimal("0.3", bits)
  assert_true((small.expm1() + Fixed::one(bits)).approx(small.exp(), tolerance))
  assert_true(small.expm1().log1p().approx(small, tolerance))
}

///|
test "expm1 of a small argument is the argument to the width" {
  let bits = Fixed::bits_for_digits(50)
  let tolerance = Fixed::of_scaled("1", 45, bits)
  let tiny = Fixed::of_decimal("1e-40", bits)
  // The series summed from `x` is a few terms, and the answer is `x` to the
  // width; it is not swallowed to zero.
  assert_true(tiny.expm1().approx(tiny, tolerance))
  // And it agrees with the long spelling at this width.
  assert_true(tiny.expm1().approx(tiny.exp() - Fixed::one(bits), tolerance))
}

///|
test "expm1 of zero is zero and log1p of zero is zero" {
  let bits = Fixed::bits_for_digits(50)
  assert_true(Fixed::zero(bits).expm1() == Fixed::zero(bits))
  assert_true(Fixed::zero(bits).log1p() == Fixed::zero(bits))
}

///|
test "panic the logarithm of one plus minus one stops" {
  ignore(Fixed::of_int(-1, 64).log1p())
}

///|
test "panic the logarithm of one plus below minus one stops" {
  ignore(Fixed::of_int(-2, 64).log1p())
}

///|
test "panic the logarithm of zero stops" {
  ignore(Fixed::zero(64).ln())
}

///|
test "panic the logarithm of a negative number stops" {
  ignore(Fixed::of_int(-1, 64).ln())
}

///|
test "panic a division by zero stops" {
  ignore(Fixed::one(64) / Fixed::zero(64))
}

///|
test "panic a literal with no digits stops" {
  ignore(Fixed::of_decimal("", 64))
}
