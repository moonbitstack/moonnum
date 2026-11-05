// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The three constants the other functions need, each from a series rather than
// from a table of digits: a table is only good to the width someone typed into
// it, and the width here is the caller's.

///|
/// `pi` to `width` bits, by Machin's formula: `16 atan(1/5) - 4 atan(1/239)`.
///
/// The two arctangents take about five and sixteen bits a term, so a thousand
/// digits costs a thousand terms of one multiplication each — the reason the
/// formula was found in the first place.
fn pi_at(width : Int32) -> BigFloat {
  let c = Context::new(width)
  let fifth = atan_series(
    c.div(BigFloat::one(context=c), BigFloat::of_int(5, context=c)),
    width,
  )
  let far = atan_series(
    c.div(BigFloat::one(context=c), BigFloat::of_int(239, context=c)),
    width,
  )
  c.sub(
    c.mul(BigFloat::of_int(16, context=c), fifth),
    c.mul(BigFloat::of_int(4, context=c), far),
  )
}

///|
/// `ln(2)`, by `2 atanh(1/3)`: the arctangent of one third takes a little over
/// three bits a term.
fn ln2_at(width : Int32) -> BigFloat {
  let c = Context::new(width)
  let third = c.div(BigFloat::one(context=c), BigFloat::of_int(3, context=c))
  c.mul(BigFloat::of_int(2, context=c), atanh_series(third, width))
}

///|
/// `pi` at the width and rounding of `context`.
pub fn BigFloat::pi(context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  pi_at(c.precision + 32).round(context=c)
}

///|
/// `e` at the width and rounding of `context`, as `exp(1)` — not a table.
pub fn BigFloat::e(context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  let width = c.precision + 32
  exp_at(BigFloat::one(context=Context::new(width)), width).round(context=c)
}

///|
/// `ln(2)` at the width and rounding of `context`.
pub fn BigFloat::ln2(context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  ln2_at(c.precision + 32).round(context=c)
}
