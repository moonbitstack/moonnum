// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The elementary functions on a complex number.
//
// Every one of them is written on the real functions in `bigfloat_elementary`,
// `bigfloat_trig` and `bigfloat_hyperbolic`, at a width that carries the guard
// bits the composition costs. The branches are the principal ones, and the cut
// is read from above, because a `BigFloat` has no signed zero to say otherwise.

///|
/// Whether either part is infinite or a NaN, the case these functions answer
/// with a NaN in both parts.
///
/// There is no Annex G recovery here. Recovering an infinity out of a product of
/// infinities needs a signed zero to say which side of a branch the argument was
/// on, and this type cannot spell one; `Complex` at fifty-three bits does that
/// job and does it well.
fn has_special(value : BigComplex) -> Bool {
  !value.real.is_finite() || !value.imag.is_finite()
}

///|
/// A value whose two parts are both NaN, at a width.
fn nan_pair(precision : Int32) -> BigComplex {
  { real: nan_at(precision), imag: nan_at(precision), }
}

///|
/// A zero pair at a width.
fn zero_pair(precision : Int32) -> BigComplex {
  let c = Context::new(precision)
  { real: BigFloat::zero(context=c), imag: BigFloat::zero(context=c), }
}

///|
/// `1 + 0j` at a width.
fn unit_pair(precision : Int32) -> BigComplex {
  let c = Context::new(precision)
  { real: BigFloat::one(context=c), imag: BigFloat::zero(context=c), }
}

///|
/// Compute at the context's width to nearest even, or one guard word wider and
/// then round both parts in the direction the context asks for.
fn directed_pair(compute : (Int32) -> BigComplex, c : Context) -> BigComplex {
  match c.rounding {
    Nearest => compute(c.precision)
    _ => both_rounded(compute(c.precision + 16), c.precision, c.rounding)
  }
}

///|
/// `e^z = e^x (cos y + j sin y)`, both parts at `precision`.
fn exp_of(value : BigComplex, precision : Int32) -> BigComplex {
  if value.real.kind() == NegativeInfinity && value.imag.is_finite() {
    // The answer is a value of the real line, the one exception to the rule
    // below: a real part that runs away to minus infinity takes the exponential
    // to zero whatever the imaginary part was doing.
    return zero_pair(precision)
  }
  if has_special(value) {
    return nan_pair(precision)
  }
  let width = complex_width(precision)
  let w = Context::new(width)
  let scale = value.real.exp(context=w)
  let (sine, cosine) = sin_cos_at(value.imag, width)
  both_rounded(
    { real: w.mul(scale, cosine), imag: w.mul(scale, sine), },
    precision,
    Nearest,
  )
}

///|
/// `e^z` at the context's width and direction.
pub fn BigComplex::exp(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => exp_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `ln z = ln|z| + j arg z`, on the principal branch: the cut is the negative
/// real axis, and a point on it has argument `pi`.
fn ln_of(value : BigComplex, precision : Int32) -> BigComplex {
  if has_special(value) {
    return nan_pair(precision)
  }
  if value.real.is_zero() && value.imag.is_zero() {
    let c = Context::new(precision)
    return {
      real: infinity_at(true, precision),
      imag: BigFloat::zero(context=c),
    }
  }
  let width = complex_width(precision)
  let w = Context::new(width)
  let square = w.add(
    w.mul(value.real, value.real),
    w.mul(value.imag, value.imag),
  )
  let modulus = square.sqrt(context=w)
  both_rounded(
    {
      real: modulus.ln(context=w),
      imag: atan2_at(value.imag, value.real, width),
    },
    precision,
    Nearest,
  )
}

///|
/// `ln z` at the context's width and direction.
pub fn BigComplex::ln(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => ln_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `sqrt z`, on the principal branch.
///
/// On the real axis it is written out rather than computed: a positive real has
/// a real square root and a negative one has an imaginary square root, and
/// either way the part that is zero is exactly zero instead of a rounding of
/// `sin(pi)`.
fn sqrt_of(value : BigComplex, precision : Int32) -> BigComplex {
  if has_special(value) {
    return nan_pair(precision)
  }
  let c = Context::new(precision)
  let zero = BigFloat::zero(context=c)
  if value.imag.is_zero() {
    if value.real.is_zero() {
      return { real: zero, imag: zero, }
    }
    if value.real.sign() >= 0 {
      return { real: value.real.sqrt(context=c), imag: zero, }
    }
    return { real: zero, imag: value.real.neg().sqrt(context=c), }
  }
  let width = complex_width(precision)
  let w = Context::new(width)
  let square = w.add(
    w.mul(value.real, value.real),
    w.mul(value.imag, value.imag),
  )
  let radius = square.sqrt(context=w)
  let two = BigFloat::of_int(2, context=w)
  if value.real.sign() >= 0 {
    // The real part is the larger one, so it is computed first and the
    // imaginary part follows from `2 re im = y`: no cancellation anywhere.
    let real = w.div(w.add(radius, value.real), two).sqrt(context=w)
    both_rounded(
      { real, imag: w.div(value.imag, w.mul(two, real)), },
      precision,
      Nearest,
    )
  } else {
    // The imaginary part is the larger one, and follows the sign of `y` so that
    // the cut is read from above.
    let size = w.div(w.sub(radius, value.real), two).sqrt(context=w)
    let signed = if value.imag.sign() < 0 { size.neg() } else { size }
    both_rounded(
      { real: w.div(value.imag, w.mul(two, signed)), imag: signed, },
      precision,
      Nearest,
    )
  }
}

///|
/// `sqrt z` at the context's width and direction.
pub fn BigComplex::sqrt(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => sqrt_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// A whole real value as an integer, or nothing when it is not one or is too
/// large to raise something to by squaring.
fn whole_of(value : BigFloat) -> @bigint.BigInt? {
  if !is_whole(value) {
    return None
  }
  let whole = value.to_bigint() catch { _ => return None }
  if whole.bit_length() > 31 {
    return None
  }
  Some(whole)
}

///|
/// `z^n` for a whole `n`, by squaring: an integer power of a complex number is
/// exact in a way `exp(n ln z)` is not — `(-2)^3` is `-8`, and not `-8` plus a
/// residue where the imaginary part should have cancelled.
fn integer_power(
  base : BigComplex,
  exponent : @bigint.BigInt,
  precision : Int32,
) -> BigComplex raise Refused {
  let width = complex_width(precision)
  let c = Context::new(width)
  let negative = exponent < 0N
  let mut left = if negative { -exponent } else { exponent }
  let mut answer = unit_pair(width)
  let mut square = base
  while left > 0N {
    if (left & 1N) == 1N {
      answer = product_of(answer, square, c)
    }
    left = left >> 1
    if left > 0N {
      square = product_of(square, square, c)
    }
  }
  let raised = both_rounded(answer, precision, Nearest)
  if !negative {
    return raised
  }
  // `1 / z` is `conj(z) / |z|^2`, and the denominator is a sum of squares of a
  // value that is not zero: a zero base was answered before this was reached.
  let denominator = c.add(
    c.mul(raised.real, raised.real),
    c.mul(raised.imag, raised.imag),
  )
  if denominator.is_zero() {
    raise ZeroDivision
  }
  both_rounded(
    {
      real: c.div(raised.real, denominator),
      imag: c.div(raised.imag.neg(), denominator),
    },
    precision,
    Nearest,
  )
}

///|
/// `z^w`, on the principal branch: `exp(w ln z)`, with a whole real exponent
/// taken by squaring instead.
///
/// Refuses `0` raised to a negative or a non-real power, the one place a complex
/// power has no answer at all rather than an infinity: `ln 0` is not a number on
/// the branch this type follows.
pub fn BigComplex::pow(
  self : BigComplex,
  exponent : BigComplex,
  context? : Context,
) -> BigComplex raise Refused {
  let c = context_of(
    context,
    Context::new(wider(self.precision(), exponent.precision())),
  )
  if has_special(self) || has_special(exponent) {
    return nan_pair(c.precision)
  }
  if self.real.is_zero() && self.imag.is_zero() {
    if exponent.real.is_zero() && exponent.imag.is_zero() {
      return unit_pair(c.precision)
    }
    if exponent.imag.is_zero() && exponent.real.sign() > 0 {
      return zero_pair(c.precision)
    }
    raise ZeroDivision
  }
  if exponent.imag.is_zero() {
    match whole_of(exponent.real) {
      Some(whole) => return integer_power(self, whole, c.precision)
      None => ()
    }
  }
  directed_pair(
    precision => {
      let width = complex_width(precision)
      let log = ln_of(self, width)
      let scaled = product_of(exponent, log, Context::new(width))
      exp_of(scaled, precision)
    },
    c,
  )
}

///|
/// `sin z = sin x cosh y + j cos x sinh y`.
fn sin_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let (sine, cosine) = sin_cos_at(value.real, width)
  let (hyperbolic, cosh_y) = hyperbolic_at(value.imag, width)
  both_rounded(
    { real: w.mul(sine, cosh_y), imag: w.mul(cosine, hyperbolic), },
    precision,
    Nearest,
  )
}

///|
/// `sin z` at the context's width and direction.
pub fn BigComplex::sin(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => sin_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `cos z = cos x cosh y - j sin x sinh y`.
fn cos_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let (sine, cosine) = sin_cos_at(value.real, width)
  let (hyperbolic, cosh_y) = hyperbolic_at(value.imag, width)
  both_rounded(
    { real: w.mul(cosine, cosh_y), imag: w.mul(sine, hyperbolic).neg(), },
    precision,
    Nearest,
  )
}

///|
/// `cos z` at the context's width and direction.
pub fn BigComplex::cos(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => cos_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `tan z = (sin 2x + j sinh 2y) / (cos 2x + cosh 2y)`.
///
/// The quotient form is used rather than `sin z / cos z` because it divides once
/// by a real number that is never small unless both parts are: `cosh 2y >= 1`
/// keeps the divisor away from zero for any imaginary part at all.
pub fn BigComplex::tan(self : BigComplex, context? : Context) -> BigComplex {
  let c = context_of(context, inherited_of(self))
  if has_special(self) {
    return nan_pair(c.precision)
  }
  directed_pair(
    precision => {
      let width = complex_width(precision)
      let w = Context::new(width)
      let two = BigFloat::of_int(2, context=w)
      let (twice_sine, twice_cosine) = sin_cos_at(w.mul(two, self.real), width)
      let (twice_hyperbolic, twice_cosh) = hyperbolic_at(
        w.mul(two, self.imag),
        width,
      )
      let denominator = w.add(twice_cosine, twice_cosh)
      both_rounded(
        {
          real: w.div(twice_sine, denominator),
          imag: w.div(twice_hyperbolic, denominator),
        },
        precision,
        Nearest,
      )
    },
    c,
  )
}

///|
/// `sinh z = sinh x cos y + j cosh x sin y`.
fn sinh_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let (hyperbolic, cosh_x) = hyperbolic_at(value.real, width)
  let (sine, cosine) = sin_cos_at(value.imag, width)
  both_rounded(
    { real: w.mul(hyperbolic, cosine), imag: w.mul(cosh_x, sine), },
    precision,
    Nearest,
  )
}

///|
/// `sinh z` at the context's width and direction.
pub fn BigComplex::sinh(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => sinh_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `cosh z = cosh x cos y + j sinh x sin y`.
fn cosh_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let (hyperbolic, cosh_x) = hyperbolic_at(value.real, width)
  let (sine, cosine) = sin_cos_at(value.imag, width)
  both_rounded(
    { real: w.mul(cosh_x, cosine), imag: w.mul(hyperbolic, sine), },
    precision,
    Nearest,
  )
}

///|
/// `cosh z` at the context's width and direction.
pub fn BigComplex::cosh(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => cosh_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `tanh z = (sinh 2x + j sin 2y) / (cosh 2x + cos 2y)`, the hyperbolic twin of
/// the tangent's quotient form: `cosh 2x >= 1` keeps the divisor away from zero.
pub fn BigComplex::tanh(self : BigComplex, context? : Context) -> BigComplex {
  let c = context_of(context, inherited_of(self))
  if has_special(self) {
    return nan_pair(c.precision)
  }
  directed_pair(
    precision => {
      let width = complex_width(precision)
      let w = Context::new(width)
      let two = BigFloat::of_int(2, context=w)
      let (twice_hyperbolic, twice_cosh) = hyperbolic_at(
        w.mul(two, self.real),
        width,
      )
      let (twice_sine, twice_cosine) = sin_cos_at(w.mul(two, self.imag), width)
      let denominator = w.add(twice_cosh, twice_cosine)
      both_rounded(
        {
          real: w.div(twice_hyperbolic, denominator),
          imag: w.div(twice_sine, denominator),
        },
        precision,
        Nearest,
      )
    },
    c,
  )
}

///|
/// `asin z = -j ln(jz + sqrt(1 - z^2))`, principal branch: the cut is the real
/// axis outside `[-1, 1]`, and `asin(2)` has a negative imaginary part.
fn asin_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let one = unit_pair(width)
  let swept : BigComplex = { real: value.imag.neg(), imag: value.real, }
  let squared = product_of(value, value, w)
  let inside = difference_of(one, squared, w)
  let root = sqrt_of(inside, width)
  let sum = sum_of(swept, root, w)
  let log = ln_of(sum, width)
  both_rounded({ real: log.imag, imag: log.real.neg(), }, precision, Nearest)
}

///|
/// `asin z` at the context's width and direction.
pub fn BigComplex::asin(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => asin_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `acos z = -j ln(z + j sqrt(1 - z^2))`, principal branch.
///
/// Written this way rather than as `pi/2 - asin z` for the neighbourhood of
/// `1`: there the answer is `sqrt(2(1-z))`, which subtracting from `pi/2` would
/// leave with none of its digits.
fn acos_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let one = unit_pair(width)
  let squared = product_of(value, value, w)
  let inside = difference_of(one, squared, w)
  let root = sqrt_of(inside, width)
  let turned : BigComplex = { real: root.imag.neg(), imag: root.real, }
  let sum = sum_of(value, turned, w)
  let log = ln_of(sum, width)
  both_rounded({ real: log.imag, imag: log.real.neg(), }, precision, Nearest)
}

///|
/// `acos z` at the context's width and direction.
pub fn BigComplex::acos(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => acos_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `atan z = (j/2)(ln(1 - jz) - ln(1 + jz))`, principal branch: the cut is the
/// imaginary axis outside `[-j, j]`.
fn atan_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let one = unit_pair(width)
  let swept : BigComplex = { real: value.imag.neg(), imag: value.real, }
  let lower = difference_of(one, swept, w)
  let upper = sum_of(one, swept, w)
  let below = ln_of(lower, width)
  let above = ln_of(upper, width)
  let difference = difference_of(below, above, w)
  let two = BigFloat::of_int(2, context=w)
  both_rounded(
    {
      real: w.div(difference.imag.neg(), two),
      imag: w.div(difference.real, two),
    },
    precision,
    Nearest,
  )
}

///|
/// `atan z` at the context's width and direction.
pub fn BigComplex::atan(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => atan_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `asinh z = ln(z + sqrt(z^2 + 1))`, principal branch.
fn asinh_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let one = unit_pair(width)
  let squared = product_of(value, value, w)
  let inside = sum_of(squared, one, w)
  let root = sqrt_of(inside, width)
  let sum = sum_of(value, root, w)
  both_rounded(ln_of(sum, width), precision, Nearest)
}

///|
/// `asinh z` at the context's width and direction.
pub fn BigComplex::asinh(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => asinh_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `acosh z = ln(z + sqrt(z - 1) sqrt(z + 1))`, principal branch: the cut is the
/// real axis below one, and `acosh(0.5)` is `+j pi/3`.
///
/// The product of two roots is used rather than `sqrt(z^2 - 1)` so that the
/// sign of each side is decided before they are multiplied: the product form is
/// the one that stays on the principal branch for a real argument below one.
fn acosh_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let one = unit_pair(width)
  let below = difference_of(value, one, w)
  let above = sum_of(value, one, w)
  let left = sqrt_of(below, width)
  let right = sqrt_of(above, width)
  let root = product_of(left, right, w)
  let sum = sum_of(value, root, w)
  both_rounded(ln_of(sum, width), precision, Nearest)
}

///|
/// `acosh z` at the context's width and direction.
pub fn BigComplex::acosh(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => acosh_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}

///|
/// `atanh z = (ln(1 + z) - ln(1 - z)) / 2`, principal branch: the cut is the
/// real axis outside `[-1, 1]`, and `atanh(2)` has a negative imaginary part.
fn atanh_of(value : BigComplex, precision : Int32) -> BigComplex {
  let width = complex_width(precision)
  let w = Context::new(width)
  let one = unit_pair(width)
  let upper = sum_of(one, value, w)
  let lower = difference_of(one, value, w)
  let above = ln_of(upper, width)
  let below = ln_of(lower, width)
  let difference = difference_of(above, below, w)
  let two = BigFloat::of_int(2, context=w)
  both_rounded(
    { real: w.div(difference.real, two), imag: w.div(difference.imag, two), },
    precision,
    Nearest,
  )
}

///|
/// `atanh z` at the context's width and direction.
pub fn BigComplex::atanh(self : BigComplex, context? : Context) -> BigComplex {
  directed_pair(
    precision => atanh_of(self, precision),
    context_of(context, inherited_of(self)),
  )
}
