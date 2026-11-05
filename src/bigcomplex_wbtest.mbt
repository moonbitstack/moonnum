// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What a vector cannot state: that the promotion is exact, that the cut is read
// from the side the type can spell, and that the functions invert each other.

///|
/// A point at a width, from two decimals.
fn bc_of(
  re : String,
  im : String,
  context? : Context,
) -> BigComplex raise Refused {
  let c = match context {
    None => Context::new(53)
    Some(c) => c
  }
  {
    real: BigFloat::parse(re[:], context=c),
    imag: BigFloat::parse(im[:], context=c),
  }
}

///|
/// Whether two parts agree to `bits` bits of the larger one.
fn bc_close(got : BigComplex, want : BigComplex, bits : Int32) -> Bool {
  let scale = if want.real.abs() >= want.imag.abs() {
    want.real.abs()
  } else {
    want.imag.abs()
  }
  let check = fn(part : BigFloat, target : BigFloat) {
    if part.is_nan() || target.is_nan() {
      return part.is_nan() && target.is_nan()
    }
    let gap = (part - target).abs()
    gap.is_zero() || scale.is_zero() || negligible(gap, scale, bits)
  }
  check(got.real, want.real) && check(got.imag, want.imag)
}

///|
test "a real is a complex whose imaginary part is exactly zero" {
  let c = Context::new(200)
  let third = BigFloat::one(context=c) / BigFloat::of_int(3, context=c)
  let lifted = third.to_complex()
  assert_true(lifted.real == third)
  assert_true(lifted.imag.is_zero())
  assert_eq(lifted.precision(), 200)
  // And the way back keeps every digit, because nothing was rounded.
  let back = lifted.to_real() catch { _ => BigFloat::zero() }
  assert_true(back == third)
}

///|
test "a real value with an imaginary part is not a real value" {
  let z = bc_of("2", "3")
  let refused = try {
    let _ = z.to_real()
    false
  } catch {
    (err : Refused) => err.to_string().contains("imaginary")
  }
  let _ = refused
  assert_true(refused)
  // A zero imaginary part, even a negative zero that the type cannot spell, is
  // admitted.
  let real = bc_of("-2.5", "0").to_real() catch { _ => BigFloat::zero() }
  assert_true(real == BigFloat::parse("-2.5"))
}

///|
test "the square root of a negative, which the real type cannot answer" {
  let c = Context::new(200)
  let minus_one = BigFloat::one(context=c).neg()
  assert_true(minus_one.sqrt(context=c).is_nan())
  let root = minus_one.to_complex().sqrt(context=c)
  // Exactly one, not nearly: the real part of the answer is a zero, and the
  // imaginary part is the square root of one.
  assert_eq(root.real.to_string(), "0.0")
  assert_eq(root.imag.to_string(), "1.0")
  assert_eq(root.imag.precision(), 200)
  let four = BigFloat::of_int(4, context=c).neg().to_complex().sqrt(context=c)
  assert_eq(four.real.to_string(), "0.0")
  assert_eq(four.imag.to_string(), "2.0")
}

///|
test "the logarithm of a negative is a logarithm and a half turn" {
  let c = Context::new(200)
  let value = bc_of("-2", "0", context=c).ln(context=c)
  let want_real = BigFloat::of_int(2, context=c).ln(context=c)
  assert_true(
    bc_close(value, BigComplex::new(want_real, BigFloat::pi(context=c)), 190),
  )
  // The same from below the axis is not reachable: the cut is the upper side,
  // which is the only side a type without a signed zero can name.
  let zero = bc_of("0", "0", context=c).ln(context=c)
  assert_true(zero.real.is_infinite())
  assert_true(zero.imag.is_zero())
}

///|
test "the inverse functions sit on the principal branch" {
  let c = Context::new(120)
  let quarter = BigFloat::pi(context=c) / BigFloat::of_int(2, context=c)
  // asin(2) is a quarter turn less an imaginary part, and acos(2) is purely
  // imaginary: the two the reference gives, not their negatives.
  let arc = bc_of("2", "0", context=c).asin(context=c)
  assert_true(near(arc.real, quarter, 100))
  assert_true(arc.imag < BigFloat::zero(context=c))
  let arccos = bc_of("2", "0", context=c).acos(context=c)
  assert_true(arccos.real.is_zero())
  assert_true(arccos.imag > BigFloat::zero(context=c))
  // atanh(2) has a negative imaginary part, and acosh of a value below one is
  // purely imaginary.
  let area = bc_of("2", "0", context=c).atanh(context=c)
  assert_true(area.imag < BigFloat::zero(context=c))
  let hyp = bc_of("0.5", "0", context=c).acosh(context=c)
  assert_true(hyp.imag > BigFloat::zero(context=c))
  assert_true(hyp.real.abs() < BigFloat::parse("1e-30", context=c))
}

///|
/// Two real parts agree to `bits` bits.
fn near(value : BigFloat, target : BigFloat, bits : Int32) -> Bool {
  let gap = (value - target).abs()
  gap.is_zero() || negligible(gap, target.abs(), bits)
}

///|

///|
/// `f(g(z))` for one inverse inside the strip where it is the inverse, at a
/// width of two hundred bits.
fn strip_check(
  name : String,
  points : Array[(String, String)],
  c : Context,
) -> Unit raise {
  for point in points {
    let (re_text, im_text) = point
    let z = bc_of(re_text, im_text, context=c)
    let back = match name {
      "sin" => z.sin(context=c).asin(context=c)
      "cos" => z.cos(context=c).acos(context=c)
      "tan" => z.tan(context=c).atan(context=c)
      "sinh" => z.sinh(context=c).asinh(context=c)
      _ => z.tanh(context=c).atanh(context=c)
    }
    let ok = bc_close(back, z, 170)
    if !ok {
      println(
        "FAIL \{name} \{re_text}+\{im_text}j: \{back.real.to_significant(10)} \{back.imag.to_significant(10)} vs \{z.real.to_significant(10)} \{z.imag.to_significant(10)}",
      )
    }
    assert_true(ok)
  }
}

///|
test "the functions invert each other, inside the range each inverse has" {
  let c = Context::new(200)
  // The logarithm is the one inverse with no strip to respect: it takes
  // everything but zero, and its answer is a value rather than a branch of one.
  for point in [("1", "1"), ("-2", "0.5"), ("0", "-3")] {
    let (re_text, im_text) = point
    let z = bc_of(re_text, im_text, context=c)
    assert_true(bc_close(z.exp(context=c).ln(context=c), z, 180))
  }
  // A value that is itself small costs the round trip more, and not because of
  // a defect: its logarithm is eighteen, so the last bit of that logarithm is
  // worth eighteen units of two to the minus two hundred, and the exponential
  // hands the error back scaled by the value, which is a ten-millionth. That is
  // the arithmetic, and it leaves about a hundred and sixty bits of the two
  // hundred rather than a hundred and eighty.
  let dust = bc_of("1e-8", "1e-8", context=c)
  assert_true(bc_close(dust.exp(context=c).ln(context=c), dust, 160))
  // The others invert only where the inverse says it lives. `asin` answers with
  // a real part inside a quarter turn, `acos` with a real part between nought
  // and a half turn, `atan` inside a quarter turn, `asinh` and `atanh` with an
  // imaginary part inside a quarter turn. Outside, the composition still lands
  // on a value of the function — sine is not one-to-one there, and the principal
  // branch picks the one inverse that is allowed.
  strip_check(
    "sin",
    [("1", "1"), ("-1.4", "0.5"), ("0", "-3"), ("1e-8", "1e-8")],
    c,
  )
  strip_check("cos", [("1", "1"), ("2.5", "0.5"), ("0.25", "2")], c)
  strip_check("tan", [("1", "1"), ("-1.4", "0.5"), ("0", "-3")], c)
  strip_check("tanh", [("1", "1"), ("-2", "0.5"), ("3", "-1.2")], c)
  strip_check(
    "sinh",
    [("1", "1"), ("-2", "0.5"), ("0", "-1.4"), ("1e-8", "1e-8")],
    c,
  )
}

///|
test "the square of the sine and the square of the cosine make one" {
  let c = Context::new(200)
  let z = bc_of("0.5", "-1.25", context=c)
  let sine = z.sin(context=c)
  let cosine = z.cos(context=c)
  let sum = c.add_complex(
    c.mul_complex(sine, sine),
    c.mul_complex(cosine, cosine),
  )
  assert_true(bc_close(sum, bc_of("1", "0", context=c), 180))
}

///|
test "a whole power is exact, and a fractional one is not" {
  let c = Context::new(200)
  let minus_two = bc_of("-2", "0", context=c)
  let three = bc_of("3", "0", context=c)
  let cube = minus_two.pow(three, context=c)
  assert_eq(cube.real.to_string(), "-8.0")
  assert_eq(cube.imag.to_string(), "0.0")
  // (1 + j)^2 = 2j, exactly.
  let diagonal = bc_of("1", "1", context=c)
  let square = diagonal.pow(bc_of("2", "0", context=c), context=c)
  assert_eq(square.real.to_string(), "0.0")
  assert_eq(square.imag.to_string(), "2.0")
  // A negative power is the reciprocal of the positive one.
  let inverse = minus_two.pow(bc_of("-3", "0", context=c), context=c)
  assert_true(near(inverse.real, BigFloat::parse("-0.125", context=c), 190))
  // The half power of a negative base is the root the real type refuses.
  let half = minus_two.pow(bc_of("0.5", "0", context=c), context=c)
  assert_true(half.real.abs() < BigFloat::parse("1e-40", context=c))
  assert_true(half.imag > BigFloat::zero(context=c))
  assert_true(
    near(half.imag, BigFloat::of_int(2, context=c).sqrt(context=c), 180),
  )
}

///|
test "zero to a power, and a quotient by zero" {
  let c = Context::new(100)
  let zero = bc_of("0", "0", context=c)
  let one = zero.pow(zero, context=c)
  assert_eq(one.real.to_string(), "1.0")
  let square_root = zero.pow(bc_of("0.5", "0", context=c), context=c)
  assert_true(square_root.real.is_zero() && square_root.imag.is_zero())
  let refused = try {
    let _ = zero.pow(bc_of("-1", "0", context=c), context=c)
    false
  } catch {
    (err : Refused) => err.to_string().contains("division by zero")
  }
  let _ = refused
  assert_true(refused)
  let quotient = try {
    let _ = bc_of("1", "1", context=c).divide(zero, context=c)
    false
  } catch {
    (err : Refused) => err.to_string().contains("division by zero")
  }
  let _ = quotient
  assert_true(quotient)
}

///|
test "a modulus and an angle" {
  let c = Context::new(200)
  let z = bc_of("3", "-4", context=c)
  assert_eq(z.abs(context=c).to_string(), "5.0")
  let angle = z.arg(context=c)
  let want = c
    .div(BigFloat::of_int(4, context=c), BigFloat::of_int(3, context=c))
    .atan(context=c)
    .neg()
  assert_true(near(angle, want, 190))
  // A point on the negative real axis has argument `pi` and not `-pi`.
  let half_turn = bc_of("-5", "0", context=c).arg(context=c)
  assert_true(near(half_turn, BigFloat::pi(context=c), 190))
  // The four quadrants, at a right angle each.
  let quarter = BigFloat::pi(context=c) / BigFloat::of_int(2, context=c)
  assert_true(near(bc_of("0", "1", context=c).arg(context=c), quarter, 190))
  assert_true(
    near(bc_of("0", "-1", context=c).arg(context=c), quarter.neg(), 190),
  )
}

///|
test "an infinity in a part is not recovered" {
  let c = Context::new(100)
  let infinite = BigComplex::new(
    BigFloat::infinity(),
    BigFloat::of_int(1, context=c),
  )
  let sum = infinite.exp(context=c)
  assert_true(sum.real.is_nan() && sum.imag.is_nan())
  // Except where the answer is a value of the real line: the exponential of a
  // real part that has run to minus infinity is zero.
  let dead = BigComplex::new(
    BigFloat::negative_infinity(),
    BigFloat::of_int(1, context=c),
  ).exp(context=c)
  assert_true(dead.real.is_zero() && dead.imag.is_zero())
  // A modulus is a distance, and a distance to a point at infinity is infinite.
  assert_true(infinite.abs(context=c).is_infinite())
}

///|
test "a complex number prints both parts at their width" {
  let c = Context::new(53)
  assert_eq(bc_of("1", "2", context=c).to_string(), "(1.0+2.0j)")
  assert_eq(bc_of("1", "-2", context=c).to_string(), "(1.0-2.0j)")
  assert_eq(bc_of("0", "-0.5", context=c).to_string(), "(0.0-0.5j)")
  let none = BigComplex::default()
  assert_eq(none.to_string(), "(0.0+0.0j)")
}

///|
test "an operator keeps the wider of its two operands" {
  let narrow = bc_of("1", "2")
  let wide = bc_of("1", "2", context=Context::new(200))
  let sum = narrow + wide
  assert_eq(sum.precision(), 200)
  let product = narrow * wide
  assert_eq(product.precision(), 200)
  // The three operations agree with the ones that take a context, and the
  // difference is the width and nothing else.
  let c = Context::new(200)
  assert_true(bc_close(sum, c.add_complex(wide, wide), 190))
}

///|
test "the real type still answers nan where the complex one answers" {
  let c = Context::new(100)
  let one = BigFloat::one(context=c)
  assert_true(one.neg().ln(context=c).is_nan())
  let lift = one.neg().to_complex().ln(context=c)
  assert_true(lift.imag > BigFloat::zero(context=c))
  assert_true(near(lift.real, BigFloat::zero(context=c), 90))
  // And a division that the real type refuses by name is refused here too.
  assert_true((one / BigFloat::zero(context=c)).is_infinite())
  let refused = try {
    let _ = c.divide_complex(
      BigComplex::new(one, BigFloat::zero(context=c)),
      BigComplex::new(BigFloat::zero(context=c), BigFloat::zero(context=c)),
    )
    false
  } catch {
    (err : Refused) => err.to_string().contains("division by zero")
  }
  let _ = refused
  assert_true(refused)
}
