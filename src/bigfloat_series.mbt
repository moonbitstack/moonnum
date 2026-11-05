// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The series every transcendental here is built from, carried in the same
// arithmetic the caller sees rather than in a separate fixed-point world.
//
// Working in `BigFloat` and not in integers scaled by 2^s is what keeps a value
// near one from losing its digits: a scaled integer has a grid that is absolute,
// so a `ln(1 + 2^-900)` computed on a grid of a thousand fractional bits keeps
// a hundred digits of the nine hundred it is worth, while the same value as a
// `BigFloat` keeps its width wherever it sits.

///|
/// The width a series is carried at: what the caller asked for, plus what the
/// series' own rounding and the range reduction take before the answer is there.
fn working(precision : Int32) -> Int32 {
  precision + 48
}

///|
/// Whether `part` is below the last place of `whole` at width `width`, which is
/// where a series stops.
fn negligible(part : BigFloat, whole : BigFloat, width : Int32) -> Bool {
  if part.is_zero() {
    return true
  }
  let lead_part = part.exponent.to_int64() +
    magnitude(part.mantissa).bit_length().to_int64()
  let lead_whole = whole.exponent.to_int64() +
    magnitude(whole.mantissa).bit_length().to_int64()
  lead_part <= lead_whole - width.to_int64()
}

///|
/// `atanh(z)` by its series, for `|z|` below a third: `z + z^3/3 + z^5/5 + ...`.
///
/// The odd powers are kept in one running product and divided by the small
/// integer of the term, so the cost of a term is one multiplication and one
/// short division rather than a power and a long one.
fn atanh_series(z : BigFloat, width : Int32) -> BigFloat {
  let c = Context::new(width)
  if z.is_zero() {
    return BigFloat::zero(context=c)
  }
  let square = c.mul(z, z)
  let mut term = z
  let mut sum = z
  let mut k = 0
  while true {
    k = k + 1
    term = c.mul(term, square)
    let added = c.div(term, BigFloat::of_int(2 * k + 1, context=c))
    sum = c.add(sum, added)
    if negligible(added, sum, width) {
      break
    }
  }
  sum
}

///|
/// `ln(1 + u)` without ever forming `1 + u`.
///
/// The addition is the whole difficulty: `1 + 2^-900` at a thousand bits is one,
/// and the log of one is nothing. Halving the argument through
/// `sqrt(1 + u) - 1 = u / (sqrt(1 + u) + 1)` keeps every digit of `u` and brings
/// it down to where the `atanh` series needs a handful of terms.
fn ln_one_plus(u : BigFloat, width : Int32) -> BigFloat {
  let c = Context::new(width)
  if u.is_zero() {
    return BigFloat::zero(context=c)
  }
  let one = BigFloat::one(context=c)
  let mut v = u
  let mut halvings = 0
  let small = BigFloat::of_double(0.0625)
  while v.abs() > small {
    let root = c.add(one, v).sqrt(context=c)
    v = c.div(v, c.add(root, one))
    halvings = halvings + 1
    if halvings > 64 {
      break
    }
  }
  let z = c.div(v, c.add(BigFloat::of_int(2, context=c), v))
  let tail = atanh_series(z, width)
  let mut result = c.mul(BigFloat::of_int(2, context=c), tail)
  let mut i = 0
  while i < halvings {
    result = c.mul(BigFloat::of_int(2, context=c), result)
    i = i + 1
  }
  result
}

///|
/// `e^x` by its series, for an argument small enough that the terms fall.
fn exp_series(y : BigFloat, width : Int32) -> BigFloat {
  let c = Context::new(width)
  let mut term = BigFloat::one(context=c)
  let mut sum = BigFloat::one(context=c)
  let mut n = 0
  while true {
    n = n + 1
    term = c.div(c.mul(term, y), BigFloat::of_int(n, context=c))
    sum = c.add(sum, term)
    if negligible(term, sum, width) {
      break
    }
  }
  sum
}

///|
/// `sin(r)` by its series, for `|r|` below a quarter turn.
fn sin_series(r : BigFloat, width : Int32) -> BigFloat {
  let c = Context::new(width)
  let square = c.mul(r, r)
  let mut term = r
  let mut sum = r
  let mut n = 0
  while true {
    n = n + 1
    term = c.div(
      c.mul(term, square),
      BigFloat::of_int(0 - 2 * n * (2 * n + 1), context=c),
    )
    sum = c.add(sum, term)
    if negligible(term, sum, width) {
      break
    }
  }
  sum
}

///|
/// `cos(r)` by its series, for `|r|` below a quarter turn.
fn cos_series(r : BigFloat, width : Int32) -> BigFloat {
  let c = Context::new(width)
  let square = c.mul(r, r)
  let mut term = BigFloat::one(context=c)
  let mut sum = BigFloat::one(context=c)
  let mut n = 0
  while true {
    n = n + 1
    term = c.div(
      c.mul(term, square),
      BigFloat::of_int(0 - (2 * n - 1) * (2 * n), context=c),
    )
    sum = c.add(sum, term)
    if negligible(term, sum, width) {
      break
    }
  }
  sum
}

///|
/// `atan(x)` by its series, for `|x|` below a sixty-fourth.
fn atan_series(x : BigFloat, width : Int32) -> BigFloat {
  let c = Context::new(width)
  let square = c.mul(x, x)
  let mut term = x
  let mut sum = x
  let mut n = 0
  while true {
    n = n + 1
    term = -c.mul(term, square)
    let added = c.div(term, BigFloat::of_int(2 * n + 1, context=c))
    sum = c.add(sum, added)
    if negligible(added, sum, width) {
      break
    }
  }
  sum
}
