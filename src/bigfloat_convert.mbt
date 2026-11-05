// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The value in the other shapes this library and the host already speak: an
// integer, a fixed-point number, a double.

///|
/// A double as a value, exactly.
///
/// Every finite double is a binary fraction, so this is not a round trip through
/// text and loses nothing: the significand and the exponent of the double are the
/// significand and the exponent of the `BigFloat`, at 53 bits.
pub fn BigFloat::of_double(value : Double) -> BigFloat {
  if value.is_nan() {
    return nan_at(53)
  }
  if value.is_inf() {
    return infinity_at(value < 0.0, 53)
  }
  let bits = value.reinterpret_as_uint64()
  let negative = bits >> 63 == 1UL
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xF_FFFF_FFFF_FFFFUL
  let (mantissa, exponent) = if biased == 0 {
    (fraction, -1074)
  } else {
    (fraction | 0x10_0000_0000_0000UL, biased - 1075)
  }
  let significand = @bigint.BigInt::from_uint64(mantissa)
  if significand.is_zero() {
    return finite_at(0N, 0, 53)
  }
  finite_at(if negative { -significand } else { significand }, exponent, 53)
}

///|
/// A fixed-point value as a value, exactly when the width allows and rounded
/// half to even when it does not.
pub fn BigFloat::of_fixed(value : Fixed, context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  rounded_at(value.mantissa, 0 - value.bits, c.precision, c.rounding, false)
}

///|
/// The value as a fixed-point number with `bits` fractional bits, rounded half
/// to even on the exact value.
///
/// The width is the caller's because a `Fixed` has no precision of its own: the
/// count of fractional bits decides how finely it can sit, and a value far from
/// one needs more of them for the same count of digits.
pub fn BigFloat::to_fixed(self : BigFloat, bits : Int32) -> Fixed raise Refused {
  match self.kind {
    NotANumber => raise Domain(reason="a NaN is not a fixed-point number")
    PositiveInfinity | NegativeInfinity =>
      raise Overflow(reason="an infinity is not a fixed-point number")
    Finite => ()
  }
  let place = self.exponent + bits
  if place >= 0 {
    return { mantissa: self.mantissa << place, bits, }
  }
  let q = div_round(magnitude(self.mantissa), 1N << (0 - place))
  { mantissa: if self.mantissa < 0N { -q } else { q }, bits, }
}

///|
/// The value rounded to an integer, `Nearest` being ties to even.
///
/// An infinity and a NaN have no integer, and saying so is the point: a caller
/// handed zero instead would not know it had not been given one.
pub fn BigFloat::to_bigint(
  self : BigFloat,
  rounding~ : Rounding = Rounding::Nearest,
) -> @bigint.BigInt raise Refused {
  match self.kind {
    NotANumber => raise Domain(reason="a NaN has no integer")
    PositiveInfinity | NegativeInfinity =>
      raise Overflow(reason="an infinity has no integer")
    Finite => ()
  }
  if self.exponent >= 0 {
    self.mantissa << self.exponent
  } else {
    round_to_integer(self.mantissa, 0 - self.exponent, rounding)
  }
}

///|
/// `mantissa / 2^places` rounded to an integer in the given direction.
fn round_to_integer(
  mantissa : @bigint.BigInt,
  places : Int32,
  rounding : Rounding,
) -> @bigint.BigInt {
  if places <= 0 {
    return mantissa << (0 - places)
  }
  let negative = mantissa < 0N
  let top = magnitude(mantissa)
  let q = top >> places
  let dropped = top - (q << places)
  if dropped.is_zero() {
    return mantissa
  }
  let half = 1N << (places - 1)
  let order = dropped.compare(half)
  let bump = match rounding {
    Nearest => order > 0 || (order == 0 && q.ctz() == 0)
    Floor => negative
    Ceiling => !negative
    Down => false
    Up => true
  }
  let kept = if bump { q + 1N } else { q }
  if negative {
    -kept
  } else {
    kept
  }
}

///|
/// The nearest double, ties to even.
///
/// A value above the largest double is an infinity and one below the smallest is
/// a zero, which is what the host does with the same value; inside that range the
/// answer is the correctly rounded double of the exact value.
pub fn BigFloat::to_double(self : BigFloat) -> Double {
  match self.kind {
    NotANumber => return @double.not_a_number
    PositiveInfinity => return @double.infinity
    NegativeInfinity => return -@double.infinity
    Finite => ()
  }
  if self.mantissa.is_zero() {
    return 0.0
  }
  let lead = self.exponent.to_int64() +
    magnitude(self.mantissa).bit_length().to_int64()
  // Outside this window no double is anywhere near the value: above it every
  // finite double is smaller, and below it every one that is not zero is larger.
  if lead > 1025 {
    return if self.mantissa < 0N { -@double.infinity } else { @double.infinity }
  }
  if lead < -1080 {
    return 0.0
  }
  let (negative, top, bottom) = ratio_of(self)
  ratio_to_double(negative, top, bottom)
}
