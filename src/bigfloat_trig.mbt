// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The circular functions. Every one of them comes back to one reduction to a
// quarter turn and one of two series.

///|
/// How many bits of an argument the turn is reduced against.
///
/// Reducing `x` needs `pi/2` to as many bits as `x` has before its point, or the
/// quotient is noise; a hundred thousand is far past any argument someone
/// computes a sine of, and refusing past it is better than answering a remainder
/// of nothing.
const MAX_REDUCTION_BITS : Int32 = 100000

///|
/// `x` as a whole number of quarter turns plus a remainder in `[-pi/4, pi/4]`.
fn reduce_quadrant(value : BigFloat, width : Int32) -> (Int32, BigFloat) {
  let lead = value.exponent + magnitude(value.mantissa).bit_length()
  let extra = if lead > 0 { lead } else { 0 }
  if extra > MAX_REDUCTION_BITS {
    abort(
      "BigFloat: the argument is past the range this library reduces faithfully",
    )
  }
  let place = width + extra + 8
  let c = Context::new(place)
  let full_turn = pi_at(place)
  let half_turn = rescaled(full_turn, full_turn.exponent - 1, place)
  let turned = c.div(rescaled(value, value.exponent, place), half_turn)
  let count = turned.to_bigint(rounding=Nearest) catch { _ => 0N }
  let rest = c.sub(
    rescaled(value, value.exponent, place),
    c.mul(BigFloat::of_bigint(count, context=c), half_turn),
  )
  let quadrant = (count % 4N + 4N) % 4N
  (quadrant.to_int(), rest)
}

///|
/// The sine and the cosine together, from one reduction: they are the same
/// remainder turned by a quarter, and computing both costs little more than one.
fn sin_cos_at(value : BigFloat, width : Int32) -> (BigFloat, BigFloat) {
  let (quadrant, rest) = reduce_quadrant(value, width)
  let sine = sin_series(rest, width)
  let cosine = cos_series(rest, width)
  match quadrant {
    0 => (sine, cosine)
    1 => (cosine, -sine)
    2 => (-sine, -cosine)
    _ => (-cosine, sine)
  }
}

///|
/// The sine, at the context's width and direction.
pub fn BigFloat::sin(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() || self.is_infinite() {
    return nan_at(c.precision)
  }
  if self.is_zero() {
    return finite_at(0N, 0, c.precision)
  }
  directed(
    precision => {
      let (sine, _) = sin_cos_at(self, working(precision))
      sine.round(context=Context::new(precision))
    },
    c,
  )
}

///|
/// The cosine, at the context's width and direction.
pub fn BigFloat::cos(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() || self.is_infinite() {
    return nan_at(c.precision)
  }
  if self.is_zero() {
    return finite_at(1N, 0, c.precision)
  }
  directed(
    precision => {
      let (_, cosine) = sin_cos_at(self, working(precision))
      cosine.round(context=Context::new(precision))
    },
    c,
  )
}

///|
/// The tangent, as the sine over the cosine.
///
/// A remainder at a quarter turn gives a cosine of zero and so an infinity, which
/// is what the tangent of a quarter turn is.
pub fn BigFloat::tan(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() || self.is_infinite() {
    return nan_at(c.precision)
  }
  if self.is_zero() {
    return finite_at(0N, 0, c.precision)
  }
  directed(
    precision => {
      let width = working(precision)
      let (sine, cosine) = sin_cos_at(self, width)
      quotient(sine, cosine, Context::new(precision))
    },
    c,
  )
}

///|
/// The arctangent, at the context's width and direction.
///
/// Past one the argument is turned over and the answer taken off a quarter turn;
/// below that it is halved through `atan x = 2 atan (x / (1 + sqrt(1 + x^2)))`
/// until the series has something to converge on.
fn atan_at(value : BigFloat, precision : Int32) -> BigFloat {
  match value.kind {
    NotANumber => return nan_at(precision)
    PositiveInfinity => return half_pi(precision)
    NegativeInfinity => return -half_pi(precision)
    Finite => ()
  }
  if value.mantissa.is_zero() {
    return finite_at(0N, 0, precision)
  }
  let negative = value.mantissa < 0N
  let width = working(precision)
  let c = Context::new(width)
  let unit = BigFloat::one(context=c)
  let mut argument = value.abs().round(context=c)
  let turned = argument > unit
  if turned {
    argument = c.div(unit, argument)
  }
  let small = BigFloat::of_double(0.015625)
  let mut halvings = 0
  while argument > small {
    argument = c.div(
      argument,
      c.add(unit, c.add(unit, c.mul(argument, argument)).sqrt(context=c)),
    )
    halvings = halvings + 1
    if halvings > 64 {
      break
    }
  }
  let mut answer = atan_series(argument, width)
  let mut i = 0
  while i < halvings {
    answer = c.add(answer, answer)
    i = i + 1
  }
  if turned {
    answer = c.sub(half_pi(width), answer)
  }
  let signed = if negative { -answer } else { answer }
  signed.round(context=Context::new(precision))
}

///|
/// `pi/2` to `width` bits.
fn half_pi(width : Int32) -> BigFloat {
  let full = pi_at(width + 8)
  rescaled(full, full.exponent - 1, width)
}

///|
/// The arctangent, at the context's width and direction.
pub fn BigFloat::atan(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  directed(precision => atan_at(self, precision), c)
}

///|
/// The arcsine, through `atan(x / sqrt(1 - x^2))`, which is real only inside the
/// unit interval.
pub fn BigFloat::asin(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() {
    return nan_at(c.precision)
  }
  let width = working(c.precision)
  let w = Context::new(width)
  let unit = BigFloat::one(context=w)
  let size = self.abs()
  if size > unit {
    return nan_at(c.precision)
  }
  let answer = if size == unit {
    if self.sign() < 0 {
      -half_pi(width)
    } else {
      half_pi(width)
    }
  } else {
    let root = w.sub(unit, w.mul(self, self)).sqrt(context=w)
    atan_at(w.div(self, root), width)
  }
  answer.round(context=Context::new(c.precision, rounding=c.rounding))
}

///|
/// The arccosine, as a quarter turn less the arcsine.
pub fn BigFloat::acos(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() {
    return nan_at(c.precision)
  }
  let width = working(c.precision)
  let w = Context::new(width)
  let unit = BigFloat::one(context=w)
  if self.abs() > unit {
    return nan_at(c.precision)
  }
  w
  .sub(half_pi(width), self.asin(context=w))
  .round(context=Context::new(c.precision, rounding=c.rounding))
}
