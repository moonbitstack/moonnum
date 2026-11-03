// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The transcendental core against fifty-digit references from a high-precision
// `decimal` computation, so a passing test means the fixed-point series agree
// with an independent implementation to forty-five places.

///|
test "exp, ln, sqrt and pi agree to fifty digits" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::from_scaled("1", 45, bits)

  let exp_one = BigFloat::one(bits).exp()
  let want_exp_one = BigFloat::from_scaled(
    "271828182845904523536028747135266249775724709369996", 50, bits,
  )
  assert_true(exp_one.approx(want_exp_one, tolerance))

  let ln_two = BigFloat::from_int(2, bits).ln()
  let want_ln_two = BigFloat::from_scaled(
    "69314718055994530941723212145817656807550013436026", 50, bits,
  )
  assert_true(ln_two.approx(want_ln_two, tolerance))

  let sqrt_two = BigFloat::from_int(2, bits).sqrt()
  let want_sqrt_two = BigFloat::from_scaled(
    "141421356237309504880168872420969807856967187537695", 50, bits,
  )
  assert_true(sqrt_two.approx(want_sqrt_two, tolerance))

  let pi = BigFloat::pi(bits)
  let want_pi = BigFloat::from_scaled(
    "314159265358979323846264338327950288419716939937511", 50, bits,
  )
  assert_true(pi.approx(want_pi, tolerance))
}

///|
test "exp and ln invert each other" {
  let bits = BigFloat::bits_for_digits(50)
  let tolerance = BigFloat::from_scaled("1", 45, bits)
  let value = BigFloat::from_scaled("15", 1, bits)
  assert_true(value.ln().exp().approx(value, tolerance))
  assert_true(value.exp().ln().approx(value, tolerance))
}

///|
test "the arithmetic is the arithmetic of the value it stands for" {
  let bits = BigFloat::bits_for_digits(30)
  let three = BigFloat::from_int(3, bits)
  let four = BigFloat::from_int(4, bits)
  let sum = three.add(four)
  let product = three.mul(four)
  let quotient = three.div(four)
  assert_eq(sum.to_double(), 7.0)
  assert_eq(product.to_double(), 12.0)
  assert_eq(quotient.to_double(), 0.75)
  assert_eq(BigFloat::zero(bits).to_double(), 0.0)
  assert_eq(BigFloat::from_int(-5, bits).abs().to_double(), 5.0)
}
