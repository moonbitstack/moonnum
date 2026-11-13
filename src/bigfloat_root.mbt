// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The roots and the two named logarithms. A cube root and an n-th root are the
// power of the reciprocal exponent, taken with the sign the value had; a
// logarithm in another base is the ratio of two natural logarithms, both of
// which are already here.

///|
/// The n-th root of `value` at `precision`, exact in its signs: an odd root of a
/// negative number is negative, an even root of one is not a real number.
fn root_at(value : BigFloat, n : Int32, precision : Int32) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return infinity_at(false, precision)
    NegativeInfinity =>
      return if n % 2 == 0 {
        nan_at(precision)
      } else {
        infinity_at(true, precision)
      }
    Finite => ()
  }
  if n < 1 {
    return nan_at(precision)
  }
  if n == 1 {
    return value.round(context=Context::new(precision))
  }
  let negative = value.mantissa < 0N
  if value.mantissa.is_zero() {
    return finite_at(0N, 0, precision)
  }
  if negative && n % 2 == 0 {
    return nan_at(precision)
  }
  let width = working(precision)
  let c = Context::new(width)
  let root = exp_at(
    c.div(ln_at(value.abs(), width), BigFloat::of_int(n, context=c)),
    width,
  )
  let signed = if negative { -root } else { root }
  signed.round(context=Context::new(precision))
}

///|
/// The square root of the sum of the squares, without the overflow an
/// intermediate square would carry: `math.hypot`.
///
/// An infinity on either side answers an infinity even when the other is a NaN,
/// which is the one place where the two wrong values do not stay wrong.
pub fn BigFloat::hypot(
  self : BigFloat,
  other : BigFloat,
  context? : Context,
) -> BigFloat {
  let c = context_of(context, inherited(self, other))
  if self.is_infinite() || other.is_infinite() {
    return infinity_at(false, c.precision)
  }
  if self.is_nan() || other.is_nan() {
    return nan_at(c.precision)
  }
  directed(
    precision => {
      let width = working(precision)
      let at = Context::new(width)
      let squared = at.add(at.mul(self, self), at.mul(other, other))
      sqrt_at(squared, precision, Rounding::Nearest)
    },
    c,
  )
}

///|
/// The cube root: `cbrt`, and `nth_root` with an exponent of three.
pub fn BigFloat::cbrt(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => root_at(self, 3, precision), c)
}

///|
/// The `n`-th root, for `n >= 1`.
///
/// A zero or negative `n` has no root and answers NaN; so does an even root of a
/// negative number, which is the same answer `sqrt` gives.
pub fn BigFloat::nth_root(
  self : BigFloat,
  n : Int32,
  context? : Context,
) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => root_at(self, n, precision), c)
}

///|
/// `log2`: the logarithm in base two.
///
/// The ratio of two logarithms, each at the working width, so the quotient is
/// wrong only in the last place its own width speaks for.
pub fn BigFloat::log2(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(
    precision => {
      let width = working(precision)
      let at = Context::new(width)
      at.div(ln_at(self, width), ln2_at(width))
    },
    c,
  )
}

///|
/// `log10`: the logarithm in base ten.
pub fn BigFloat::log10(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(
    precision => {
      let width = working(precision)
      let at = Context::new(width)
      at.div(ln_at(self, width), ln10_at(width))
    },
    c,
  )
}

///|
/// `ln(10)` at the context's width and direction.
pub fn BigFloat::ln10(context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  ln10_at(c.precision + 32).round(context=c)
}
