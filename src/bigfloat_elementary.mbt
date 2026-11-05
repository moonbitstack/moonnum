// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The square root, the exponential, the logarithm and the power: the four that
// the rest of the transcendental functions are written in terms of.

///|
/// `value` with another exponent and another width, which is a change of how the
/// same significand is read and not a rounding.
fn rescaled(value : BigFloat, exponent : Int32, precision : Int32) -> BigFloat {
  { kind: Finite, mantissa: value.mantissa, exponent, precision, }
}

///|
/// Compute at the context's width to nearest even, or one guard word wider and
/// then round in the direction the context asks for.
///
/// A direction other than nearest is a statement about the last bit, and the last
/// bit of a series is the one that depends on where the series stopped; carrying
/// sixteen more bits makes the direction the caller's and not the guard's.
fn directed(compute : (Int32) -> BigFloat, context : Context) -> BigFloat {
  match context.rounding {
    Nearest => compute(context.precision)
    _ => compute(context.precision + 16).round(context~)
  }
}

///|
/// The square root, correctly rounded in every direction.
fn sqrt_at(
  value : BigFloat,
  precision : Int32,
  rounding : Rounding,
) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return infinity_at(false, precision)
    NegativeInfinity => return nan_at(precision)
    Finite => ()
  }
  if value.mantissa < 0N {
    return nan_at(precision)
  }
  if value.mantissa.is_zero() {
    return finite_at(0N, 0, precision)
  }
  let mut top = value.mantissa
  let mut place = value.exponent
  // An even exponent is what makes the halving of the logarithm of two an
  // integer; an odd one moves into the significand, where it is exact.
  if place % 2 != 0 {
    top = top << 1
    place = place - 1
  }
  let mut room = 2 * (precision + 2) - top.bit_length()
  if room < 0 {
    room = 0
  }
  if room % 2 != 0 {
    room = room + 1
  }
  let scaled = top << room
  let root = floor_sqrt(scaled)
  let exact = root * root == scaled
  rounded_at(root, (place - room) / 2, precision, rounding, !exact)
}

///|
/// The square root, rounded at the context's width and direction.
pub fn BigFloat::sqrt(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  sqrt_at(self, c.precision, c.rounding)
}

///|
/// The largest argument whose exponential still fits an `Int32` exponent, near
/// enough: `2^31 / ln 2`.
const EXP_ARGUMENT_LIMIT : Double = 1.0e9

///|
/// `e^x` by scaling and squaring: halve the argument until the series needs a
/// few hundred terms, then square the answer back. The alternative — reducing by
/// `ln 2` — would need `ln 2` before `exp` could be written at all, and would
/// carry the error of two constants into every exponential.
fn exp_at(value : BigFloat, precision : Int32) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return infinity_at(false, precision)
    NegativeInfinity => return finite_at(0N, 0, precision)
    Finite => ()
  }
  if value.mantissa.is_zero() {
    return finite_at(1N, 0, precision)
  }
  let rough = value.to_double()
  if rough > EXP_ARGUMENT_LIMIT {
    return infinity_at(false, precision)
  }
  if rough < -EXP_ARGUMENT_LIMIT {
    return finite_at(0N, 0, precision)
  }
  let lead = value.exponent + magnitude(value.mantissa).bit_length()
  let halvings = if lead > 0 { lead } else { 0 }
  // Each squaring doubles the error that went before it, so the halvings are
  // paid for in guard bits.
  let width = working(precision) + halvings
  let c = Context::new(width)
  let reduced = rescaled(value, value.exponent - halvings, width)
  let mut sum = exp_series(reduced, width)
  let mut i = 0
  while i < halvings {
    sum = c.mul(sum, sum)
    i = i + 1
  }
  sum.round(context=Context::new(precision))
}

///|
/// The exponential at the context's width and direction.
pub fn BigFloat::exp(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => exp_at(self, precision), c)
}

///|
/// The natural logarithm: the exponent taken out as a whole number of doublings,
/// and `ln(1 + u)` for what is left.
///
/// Taking the exponent out first is what keeps the answer accurate for a value of
/// any size: `ln` of a thousand-digit number and `ln` of its reciprocal differ by
/// a whole multiple of `ln 2`, and only the second part needs the series.
fn ln_at(value : BigFloat, precision : Int32) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return infinity_at(false, precision)
    NegativeInfinity => return nan_at(precision)
    Finite => ()
  }
  if value.mantissa == 0N {
    return infinity_at(true, precision)
  }
  if value.mantissa < 0N {
    return nan_at(precision)
  }
  let width = working(precision)
  let c = Context::new(width)
  let lead = value.exponent + value.mantissa.bit_length() - 1
  let mantissa = rescaled(value, value.exponent - lead, width)
  let unit = BigFloat::one(context=c)
  // `mantissa` is in one to two, so this subtraction is exact: the two operands
  // are within a factor of two of each other and the low bits have nowhere to go.
  let tail = ln_one_plus(c.sub(mantissa, unit), width)
  if lead == 0 {
    return tail.round(context=Context::new(precision))
  }
  let scale = BigFloat::of_int(lead, context=c)
  c
  .add(tail, c.mul(scale, ln2_at(width)))
  .round(context=Context::new(precision))
}

///|
/// The logarithm at the context's width and direction.
pub fn BigFloat::ln(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => ln_at(self, precision), c)
}

///|
/// The smallest argument whose exponential minus one is formed by subtraction.
///
/// Below it, `e^x` is so nearly one that taking one away keeps only the bits
/// where the two agree; above it the exponential has grown enough that the
/// subtraction costs a bit and a half, which the guard bits pay for.
const EXPM1_SERIES_LIMIT : Double = 0.5

///|
/// `e^x - 1`, without subtracting one from an exponential that is nearly one.
///
/// By the time `e^x` is written down, the answer to `e^x - 1` for a small `x` is
/// gone: at two hundred bits `e^1e-40` and one differ nowhere the width can see.
/// The series that starts at `x` never forms the one, so it keeps the digits the
/// subtraction would have thrown away.
fn expm1_at(value : BigFloat, precision : Int32) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return infinity_at(false, precision)
    NegativeInfinity => return finite_at(-1N, 0, precision)
    Finite => ()
  }
  if value.mantissa.is_zero() {
    return finite_at(0N, 0, precision)
  }
  let width = working(precision)
  let c = Context::new(width)
  if value.to_double().abs() > EXPM1_SERIES_LIMIT {
    return c
      .sub(exp_at(value, width), BigFloat::one(context=c))
      .round(context=Context::new(precision))
  }
  // `term` starts at the first term of the series, `x/1!`, so the division that
  // turns it into the second one is by two.
  let mut term = value
  let mut sum = value
  let mut n = 1
  while true {
    n = n + 1
    term = c.div(c.mul(term, value), BigFloat::of_int(n, context=c))
    sum = c.add(sum, term)
    if negligible(term, sum, width) {
      break
    }
  }
  sum.round(context=Context::new(precision))
}

///|
/// `e^x - 1` at the context's width and direction.
pub fn BigFloat::expm1(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => expm1_at(self, precision), c)
}

///|
/// `ln(1 + x)`, without ever forming `1 + x`.
///
/// The argument is not added to one at all: `ln_one_plus` halves it through
/// `sqrt(1 + x) - 1 = x / (sqrt(1 + x) + 1)`, which keeps every digit of `x`
/// however small, and the series then answers for a value near zero instead of a
/// value near one. Past a half, one is added — and there the addition is exact,
/// because the two are within a factor of two and the low bits have nowhere to
/// go.
fn log1p_at(value : BigFloat, precision : Int32) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return infinity_at(false, precision)
    NegativeInfinity => return nan_at(precision)
    Finite => ()
  }
  let width = working(precision)
  let c = Context::new(width)
  let unit = BigFloat::one(context=c)
  if value == -unit {
    return infinity_at(true, precision)
  }
  if value < -unit {
    return nan_at(precision)
  }
  if value.mantissa.is_zero() {
    return finite_at(0N, 0, precision)
  }
  if value.abs() > BigFloat::of_double(0.5) {
    return ln_at(c.add(unit, value), precision)
  }
  ln_one_plus(value, width).round(context=Context::new(precision))
}

///|
/// `ln(1 + x)` at the context's width and direction.
pub fn BigFloat::log1p(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => log1p_at(self, precision), c)
}

///|
/// Whether the value is a whole number.
fn is_whole(value : BigFloat) -> Bool {
  if !value.is_finite() {
    return false
  }
  if value.mantissa.is_zero() || value.exponent >= 0 {
    return true
  }
  let drop = 0 - value.exponent
  let top = magnitude(value.mantissa)
  if drop >= top.bit_length() {
    return false
  }
  top >> drop << drop == top
}

///|
/// Whether a whole value is odd, which is what decides the sign of a negative
/// base raised to it.
fn is_odd_whole(value : BigFloat) -> Bool {
  if !is_whole(value) || value.mantissa.is_zero() {
    return false
  }
  if value.exponent > 0 {
    // Every doubling makes it even.
    return false
  }
  let top = magnitude(value.mantissa)
  if value.exponent == 0 {
    return top.ctz() == 0
  }
  let drop = 0 - value.exponent
  if drop >= top.bit_length() {
    return false
  }
  ((top >> drop) & 1N) == 1N
}

///|
/// `base ^ exponent`, through `exp(exponent * ln base)` with the cases a real
/// power cannot take written out.
fn pow_at(base : BigFloat, exponent : BigFloat, precision : Int32) -> BigFloat {
  if base.is_nan() || exponent.is_nan() {
    return nan_at(precision)
  }
  if exponent.is_zero() {
    return finite_at(1N, 0, precision)
  }
  if base.is_zero() {
    return if exponent.sign() > 0 {
      finite_at(0N, 0, precision)
    } else {
      infinity_at(false, precision)
    }
  }
  let negative = base.sign() < 0
  if base.is_infinite() {
    if negative && !is_whole(exponent) {
      return nan_at(precision)
    }
    let odd = is_odd_whole(exponent)
    if exponent.sign() > 0 {
      return infinity_at(negative && odd, precision)
    }
    return finite_at(0N, 0, precision)
  }
  if exponent.is_infinite() {
    // A base below one in magnitude sends the answer down, above one up.
    let below = base.abs() < BigFloat::one(context=Context::new(53))
    let up = (exponent.sign() > 0) != below
    if base.abs() == BigFloat::one(context=Context::new(53)) {
      return finite_at(1N, 0, precision)
    }
    return if up {
      infinity_at(false, precision)
    } else {
      finite_at(0N, 0, precision)
    }
  }
  if negative && !is_whole(exponent) {
    return nan_at(precision)
  }
  let width = working(precision)
  let c = Context::new(width)
  let logarithm = ln_at(base.abs(), width)
  let product = c.mul(exponent, logarithm)
  let answer = exp_at(product, width)
  let signed = if negative && is_odd_whole(exponent) { -answer } else { answer }
  signed.round(context=Context::new(precision))
}

///|
/// `base` raised to `exponent`, at the context's width and direction.
///
/// A negative base with a fractional exponent has no real value and answers NaN,
/// as does anything that would need the logarithm of a negative number.
pub fn BigFloat::pow(
  self : BigFloat,
  exponent : BigFloat,
  context? : Context,
) -> BigFloat {
  let c = context_of(context, inherited(self, exponent))
  directed(precision => pow_at(self, exponent, precision), c)
}
