// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The transcendental core against fifty-digit references from `mpmath`, so a
// passing test means the fixed-point series agree with an independent
// implementation to forty-five places rather than with themselves.

///|
test "exp, ln, sqrt and pi agree to fifty digits" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::of_scaled("1", 45, bits)

  let exp_one = BigFloat::one(bits).exp()
  let want_exp_one = BigFloat::of_scaled(
    "271828182845904523536028747135266249775724709369995", 50, bits,
  )
  assert_true(exp_one.approx(want_exp_one, tolerance))

  let ln_two = BigFloat::of_int(2, bits).ln()
  let want_ln_two = BigFloat::of_scaled(
    "69314718055994530941723212145817656807550013436025", 50, bits,
  )
  assert_true(ln_two.approx(want_ln_two, tolerance))

  let sqrt_two = BigFloat::of_int(2, bits).sqrt()
  let want_sqrt_two = BigFloat::of_scaled(
    "141421356237309504880168872420969807856967187537694", 50, bits,
  )
  assert_true(sqrt_two.approx(want_sqrt_two, tolerance))

  let pi = BigFloat::pi(bits)
  let want_pi = BigFloat::of_scaled(
    "314159265358979323846264338327950288419716939937510", 50, bits,
  )
  assert_true(pi.approx(want_pi, tolerance))
}

///|
test "sine, cosine and arctangent agree to fifty digits" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::of_scaled("1", 45, bits)
  let one = BigFloat::one(bits)

  let sine = one.sin()
  let want_sine = BigFloat::of_scaled(
    "84147098480789650665250232163029899962256306079837", 50, bits,
  )
  assert_true(sine.approx(want_sine, tolerance))

  let cosine = one.cos()
  let want_cosine = BigFloat::of_scaled(
    "54030230586813971740093660744297660373231042061792", 50, bits,
  )
  assert_true(cosine.approx(want_cosine, tolerance))

  let quarter_turn = one.atan()
  let want_quarter_turn = BigFloat::of_scaled(
    "78539816339744830961566084581987572104929234984377", 50, bits,
  )
  assert_true(quarter_turn.approx(want_quarter_turn, tolerance))

  // `atan(10)` is past one, where the halving has to run before the series will.
  let steep = BigFloat::of_int(10, bits).atan()
  let want_steep = BigFloat::of_scaled(
    "147112767430373459185287557176173085185530637718323", 50, bits,
  )
  assert_true(steep.approx(want_steep, tolerance))
}

///|
test "the square of the sine and the cosine is one" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::of_scaled("1", 45, bits)
  let value = BigFloat::of_scaled("13", 1, bits)
  let sine = value.sin()
  let cosine = value.cos()
  let squares = sine.mul(sine).add(cosine.mul(cosine))
  assert_true(squares.approx(BigFloat::one(bits), tolerance))
}

///|
test "a real power is the exponential of the logarithm" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::of_scaled("1", 45, bits)
  let two = BigFloat::of_int(2, bits)
  let half = BigFloat::of_scaled("5", 1, bits)
  let root = two.pow(half)
  let want = BigFloat::of_scaled(
    "141421356237309504880168872420969807856967187537694", 50, bits,
  )
  assert_true(root.approx(want, tolerance))
}

///|
test "a decimal literal is read at the width it is asked for" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::of_scaled("1", 45, bits)
  let gamma = BigFloat::of_decimal(
    "0.57721566490153286060651209008240243104215933593992", bits,
  )
  let want = BigFloat::of_scaled(
    "57721566490153286060651209008240243104215933593992", 50, bits,
  )
  assert_true(gamma.approx(want, tolerance))
  // The exponent form, which is how a reference for a small tail is written.
  let tiny = BigFloat::of_decimal("1.5e-12", bits)
  assert_true(tiny.approx(BigFloat::of_scaled("15", 13, bits), tolerance))
  assert_true(BigFloat::of_decimal("-0.5", bits).to_double() == -0.5)
}

///|
test "exp and ln invert each other" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::of_scaled("1", 45, bits)
  let value = BigFloat::of_scaled("15", 1, bits)
  assert_true(value.ln().exp().approx(value, tolerance))
  assert_true(value.exp().ln().approx(value, tolerance))
}

///|
test "the arithmetic is the arithmetic of the value it stands for" {
  let bits = BigFloat::bits_for_digits(30)
  let three = BigFloat::of_int(3, bits)
  let four = BigFloat::of_int(4, bits)
  let sum = three.add(four)
  let product = three.mul(four)
  let quotient = three.div(four)
  assert_eq(sum.to_double(), 7.0)
  assert_eq(product.to_double(), 12.0)
  assert_eq(quotient.to_double(), 0.75)
  assert_eq(BigFloat::zero(bits).to_double(), 0.0)
  assert_eq(BigFloat::of_int(-5, bits).abs().to_double(), 5.0)
  assert_true(three.lt(four))
  assert_true(BigFloat::of_int(-5, bits).lt(three))
}
