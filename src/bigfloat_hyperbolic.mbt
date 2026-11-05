// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The hyperbolic functions: one exponential for the large arguments, one series
// for the small ones, where the difference of two exponentials would cancel.

///|
/// `sinh(x)`, `cosh(x)` and their ratio, from one argument.
///
/// The subtraction in `sinh` loses every digit of a small argument, so below one
/// the two are summed as the series that has no subtraction in it.
fn hyperbolic_at(value : BigFloat, width : Int32) -> (BigFloat, BigFloat) {
  let c = Context::new(width)
  let unit = BigFloat::one(context=c)
  if value.abs() < unit {
    let square = c.mul(value, value)
    let mut odd = value
    let mut even = unit
    let mut sinh = value
    let mut cosh = unit
    let mut n = 0
    while true {
      n = n + 1
      odd = c.div(
        c.mul(odd, square),
        BigFloat::of_int(2 * n * (2 * n + 1), context=c),
      )
      even = c.div(
        c.mul(even, square),
        BigFloat::of_int((2 * n - 1) * (2 * n), context=c),
      )
      sinh = c.add(sinh, odd)
      cosh = c.add(cosh, even)
      if negligible(odd, sinh, width) && negligible(even, cosh, width) {
        break
      }
    }
    return (sinh, cosh)
  }
  let forward = exp_at(value, width)
  let backward = exp_at(-value, width)
  (
    c.div(c.sub(forward, backward), BigFloat::of_int(2, context=c)),
    c.div(c.add(forward, backward), BigFloat::of_int(2, context=c)),
  )
}

///|
/// The hyperbolic sine, at the context's width and direction.
pub fn BigFloat::sinh(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() || self.is_infinite() {
    return if self.is_nan() {
      nan_at(c.precision)
    } else {
      infinity_at(self.sign() < 0, c.precision)
    }
  }
  if self.is_zero() {
    return finite_at(0N, 0, c.precision)
  }
  directed(
    precision => {
      let (sinh, _) = hyperbolic_at(self, working(precision))
      sinh.round(context=Context::new(precision))
    },
    c,
  )
}

///|
/// The hyperbolic cosine, at the context's width and direction.
pub fn BigFloat::cosh(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() {
    return nan_at(c.precision)
  }
  if self.is_infinite() {
    return infinity_at(false, c.precision)
  }
  if self.is_zero() {
    return finite_at(1N, 0, c.precision)
  }
  directed(
    precision => {
      let (_, cosh) = hyperbolic_at(self, working(precision))
      cosh.round(context=Context::new(precision))
    },
    c,
  )
}

///|
/// The hyperbolic tangent, as the sine over the cosine.
pub fn BigFloat::tanh(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() {
    return nan_at(c.precision)
  }
  if self.is_infinite() {
    return finite_at(if self.sign() < 0 { -1N } else { 1N }, 0, c.precision)
  }
  if self.is_zero() {
    return finite_at(0N, 0, c.precision)
  }
  directed(
    precision => {
      let width = working(precision)
      let (sinh, cosh) = hyperbolic_at(self, width)
      quotient(sinh, cosh, Context::new(precision))
    },
    c,
  )
}

///|
/// The inverse hyperbolic sine, as `ln(1 + u)` with `u = x + x^2 / (sqrt(1 + x^2) + 1)`.
///
/// The `1 +` that would swallow a small argument never gets formed: the rational
/// form of the square root keeps the small part, and `ln_one_plus` is the
/// logarithm that can take it.
pub fn BigFloat::asinh(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() || self.is_infinite() {
    return if self.is_nan() {
      nan_at(c.precision)
    } else {
      infinity_at(self.sign() < 0, c.precision)
    }
  }
  if self.is_zero() {
    return finite_at(0N, 0, c.precision)
  }
  let width = working(c.precision)
  let w = Context::new(width)
  let unit = BigFloat::one(context=w)
  let negative = self.mantissa < 0N
  let size = self.abs()
  let root = w.add(unit, w.mul(size, size)).sqrt(context=w)
  let middle = w.add(size, w.div(w.mul(size, size), w.add(root, unit)))
  let answer = ln_one_plus(middle, width)
  let signed = if negative { -answer } else { answer }
  signed.round(context=Context::new(c.precision, rounding=c.rounding))
}

///|
/// The inverse hyperbolic cosine, as `asinh(sqrt(x^2 - 1))`, which is real from
/// one upwards and holds its digits there where `ln(x + sqrt(x^2 - 1))` would not.
pub fn BigFloat::acosh(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() {
    return nan_at(c.precision)
  }
  if self.is_infinite() {
    return if self.sign() > 0 {
      infinity_at(false, c.precision)
    } else {
      nan_at(c.precision)
    }
  }
  let width = working(c.precision)
  let w = Context::new(width)
  let unit = BigFloat::one(context=w)
  if self < unit {
    return nan_at(c.precision)
  }
  if self == unit {
    return finite_at(0N, 0, c.precision)
  }
  let inside = w.sub(w.mul(self, self), unit)
  inside
  .sqrt(context=w)
  .asinh(context=w)
  .round(context=Context::new(c.precision, rounding=c.rounding))
}

///|
/// The inverse hyperbolic tangent, as half the log of `(1 + x) / (1 - x)`.
///
/// At one the answer is unbounded and the two infinities are the answer; past it
/// there is no real value.
pub fn BigFloat::atanh(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  if self.is_nan() {
    return nan_at(c.precision)
  }
  if self.is_zero() {
    return finite_at(0N, 0, c.precision)
  }
  let width = working(c.precision)
  let w = Context::new(width)
  let unit = BigFloat::one(context=w)
  let size = self.abs()
  if size > unit {
    return nan_at(c.precision)
  }
  if size == unit {
    return infinity_at(self.sign() < 0, c.precision)
  }
  let ratio = w.div(w.add(unit, self), w.sub(unit, self))
  let answer = ln_at(ratio, width)
  w
  .div(answer, BigFloat::of_int(2, context=w))
  .round(context=Context::new(c.precision, rounding=c.rounding))
}
