// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A binary floating-point number whose significand is as wide as the caller asks
// for: `mantissa * 2^exponent`, with the width the value was rounded to kept
// beside it.
//
// The difference from `Fixed` is where the width is spent. A fixed-point value
// spends it on the distance from the decimal point, so one far from one holds
// few significant digits; here it is spent on the significand, so every value
// keeps the same count of digits wherever it sits on the number line, which is
// what lets one product of two values round to the width a caller asked for
// rather than to the width the first operand happened to have.
//
// The three values a significand cannot spell — an infinity above and below, and
// the answer to `0/0` — are kinds of their own rather than numbers with a flag,
// because every operation would otherwise have to check the flag before it could
// trust the digits. Only `Finite` reaches the arithmetic.

///|
/// What a `BigFloat` is.
///
/// A caller who matches on this has seen every value the type can hold, which is
/// the reason it is one enum and not three predicates.
#derive(Eq)
pub(all) enum Kind {
  /// A number, held as a signed significand and a binary exponent.
  Finite
  /// Past every number the exponent can name, above zero.
  PositiveInfinity
  /// The same, below zero.
  NegativeInfinity
  /// The answer to a question with none: `0/0`, `inf - inf`, `sqrt(-1)`, `ln(-1)`.
  NotANumber
}

///|
pub extend Kind with Eq::{not_equal, equal}

///|
/// How a result that does not fit the width it is rounded to is rounded.
///
/// The five are the reference's `n`, `f`, `c`, `d` and `u`. `Nearest` breaks a
/// tie toward the even digit, so a sequence of roundings does not drift upward
/// the way ties-away-from-zero does.
#derive(Eq)
pub(all) enum Rounding {
  /// To the nearest, and to the even one when two are equally near.
  Nearest
  /// Toward minus infinity.
  Floor
  /// Toward plus infinity.
  Ceiling
  /// Toward zero, which is what dropping the low bits does by itself.
  Down
  /// Away from zero.
  Up
}

///|
pub extend Rounding with Eq::{not_equal, equal}

///|
/// A width in bits and the direction a result that does not fit is rounded in.
///
/// The two travel together because a rounding mode without a width has nothing
/// to round, and a width without a mode leaves the last bit to chance.
pub struct Context {
  /// How many bits of significand a result keeps.
  precision : Int32
  /// Which way the last bit goes when it cannot be kept.
  rounding : Rounding
}

///|
/// A context of `precision` bits, rounding to nearest even unless told otherwise.
///
/// A width below one is raised to one: a significand of no bits holds nothing but
/// zero, and silently answering zero for every operation is worse than answering
/// the one bit that was asked for.
pub fn Context::new(
  precision : Int32,
  rounding~ : Rounding = Rounding::Nearest,
) -> Context {
  { precision: if precision < 1 { 1 } else { precision }, rounding, }
}

///|
/// What an operation uses when the caller names no context: 53 bits to nearest
/// even, which is the width and the mode of a double. A `BigFloat` computed with
/// it and a `Double` computed by the host agree to the bit, so the two can be
/// compared without a tolerance.
pub let context_default : Context = {
  precision: 53,
  rounding: Rounding::Nearest,
}

///|
/// A real number carried to a precision of its own.
///
/// The value is `mantissa * 2^exponent` while it is finite, with the significand
/// an integer of no more bits than `precision` says. The exponent is binary
/// because the arithmetic underneath is binary: multiplying by ten would round
/// where multiplying by two does not.
///
/// Every operation rounds its result to a width — the wider of its operands, or
/// the one a `Context` names — and keeps that width on the answer, so the next
/// operation inherits it without the caller having to repeat it.
pub struct BigFloat {
  /// Which of the four kinds this is.
  kind : Kind
  /// The significand, signed, so that the value is `mantissa * 2^exponent`.
  mantissa : @bigint.BigInt
  /// The binary exponent the significand is scaled by.
  exponent : Int32
  /// The width the significand was rounded to, in bits.
  precision : Int32
}

///|
/// `value` without its sign.
fn magnitude(value : @bigint.BigInt) -> @bigint.BigInt {
  if value < 0N {
    -value
  } else {
    value
  }
}

///|
/// A finite value that has already been rounded — the only way one is built, so
/// the invariant `bit_length(mantissa) <= precision` holds everywhere below.
fn finite_at(
  mantissa : @bigint.BigInt,
  exponent : Int32,
  precision : Int32,
) -> BigFloat {
  { kind: Finite, mantissa, exponent, precision, }
}

///|
fn nan_at(precision : Int32) -> BigFloat {
  { kind: NotANumber, mantissa: 0N, exponent: 0, precision, }
}

///|
fn infinity_at(negative : Bool, precision : Int32) -> BigFloat {
  {
    kind: if negative {
      NegativeInfinity
    } else {
      PositiveInfinity
    },
    mantissa: 0N,
    exponent: 0,
    precision,
  }
}

///|
/// `mantissa * 2^exponent` cut to `precision` bits, as a signed significand and
/// the exponent it now sits at.
///
/// `sticky` says the true value is above `mantissa * 2^exponent` but below the
/// next multiple of the last bit — what a division leaves behind when the
/// remainder is not zero. Without it the rounding of a quotient would read a
/// remainder smaller than the last place as an exact value and break the tie the
/// wrong way.
fn rounded(
  mantissa : @bigint.BigInt,
  exponent : Int32,
  precision : Int32,
  rounding : Rounding,
  sticky : Bool,
) -> (@bigint.BigInt, Int32) {
  if mantissa.is_zero() {
    return (mantissa, 0)
  }
  let negative = mantissa < 0N
  let magnitude = magnitude(mantissa)
  let length = magnitude.bit_length()
  let shift = length - precision
  if shift < 0 && !sticky {
    return (mantissa, exponent)
  }
  let mut kept = magnitude
  let mut place = exponent
  let mut dropped = 0N
  let mut inexact = sticky
  let mut half = 1N
  if shift > 0 {
    kept = magnitude >> shift
    dropped = magnitude - (kept << shift)
    place = exponent + shift
    half = 1N << (shift - 1)
    inexact = inexact || !dropped.is_zero()
  } else if shift < 0 {
    // The value fits and is still not exact: the grid it must land on has
    // `-shift` bits more room than the significand uses, so one step of that grid
    // is the next value up, and the remainder decides whether it is taken.
    kept = magnitude << -shift
    place = exponent + shift
  }
  let order = dropped.compare(half)
  let bump = match rounding {
    Nearest => {
      // Above the halfway point, or on it with the sticky bit below the halfway
      // point's reach; on it exactly, the even digit wins.
      let above = order > 0 || (order == 0 && sticky)
      let tie = order == 0 && !sticky && kept.ctz() == 0
      above || tie
    }
    Floor => negative && inexact
    Ceiling => !negative && inexact
    Down => false
    Up => inexact
  }
  let mut kept = if bump { kept + 1N } else { kept }
  let mut place = place
  // A carry out of the top bit leaves one bit too many: the significand halves
  // and the exponent takes the bit, which is the same value written in the one
  // shape the invariant allows.
  if kept.bit_length() > precision {
    kept = kept >> 1
    place = place + 1
  }
  (if negative { -kept } else { kept }, place)
}

///|
/// A value from a magnitude that still has to be rounded.
fn rounded_at(
  mantissa : @bigint.BigInt,
  exponent : Int32,
  precision : Int32,
  rounding : Rounding,
  sticky : Bool,
) -> BigFloat {
  let (m, e) = rounded(mantissa, exponent, precision, rounding, sticky)
  finite_at(m, e, precision)
}

///|
/// The context two operands imply: the wider of the two, to nearest even.
fn inherited(a : BigFloat, b : BigFloat) -> Context {
  {
    precision: if a.precision >= b.precision {
      a.precision
    } else {
      b.precision
    },
    rounding: Rounding::Nearest,
  }
}

///|
/// The context one operand implies: its own width, to nearest even.
fn inherited_unary(a : BigFloat) -> Context {
  { precision: a.precision, rounding: Rounding::Nearest, }
}

///|
/// A context, or the one the operands imply.
fn context_of(context : Context?, implied : Context) -> Context {
  match context {
    Some(given) => given
    None => implied
  }
}

///|
/// The number zero.
pub fn BigFloat::zero(context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  finite_at(0N, 0, c.precision)
}

///|
/// The number one.
pub fn BigFloat::one(context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  finite_at(1N, 0, c.precision)
}

///|
/// Not a number.
pub fn BigFloat::nan() -> BigFloat {
  nan_at(context_default.precision)
}

///|
/// Past every number the exponent can name, above zero.
pub fn BigFloat::infinity() -> BigFloat {
  infinity_at(false, context_default.precision)
}

///|
/// The same, below zero.
pub fn BigFloat::negative_infinity() -> BigFloat {
  infinity_at(true, context_default.precision)
}

///|
/// An integer as a value, rounded when the context is narrower than the integer.
pub fn BigFloat::of_int(value : Int32, context? : Context) -> BigFloat {
  let c = context_of(context, context_default)
  rounded_at(@bigint.BigInt::from_int(value), 0, c.precision, c.rounding, false)
}

///|
/// An arbitrary-precision integer as a value, rounded when the context is
/// narrower than the integer.
pub fn BigFloat::of_bigint(
  value : @bigint.BigInt,
  context? : Context,
) -> BigFloat {
  let c = context_of(context, context_default)
  rounded_at(value, 0, c.precision, c.rounding, false)
}

///|
/// The kind of value this is.
pub fn BigFloat::kind(self : BigFloat) -> Kind {
  self.kind
}

///|
/// The width the value was rounded to, in bits.
pub fn BigFloat::precision(self : BigFloat) -> Int32 {
  self.precision
}

///|
/// Whether the value is the answer to a question with none.
pub fn BigFloat::is_nan(self : BigFloat) -> Bool {
  self.kind == NotANumber
}

///|
/// Whether the value is past every number the exponent can name.
pub fn BigFloat::is_infinite(self : BigFloat) -> Bool {
  self.kind == PositiveInfinity || self.kind == NegativeInfinity
}

///|
/// Whether the value is a number.
pub fn BigFloat::is_finite(self : BigFloat) -> Bool {
  self.kind == Finite
}

///|
/// Whether the value is zero. A zero is a number; an infinity is not one.
pub fn BigFloat::is_zero(self : BigFloat) -> Bool {
  self.kind == Finite && self.mantissa.is_zero()
}

///|
/// `-1`, `0` or `1`: the sign of the value, and `0` where there is no sign to
/// give, as for a NaN.
pub fn BigFloat::sign(self : BigFloat) -> Int32 {
  match self.kind {
    Finite =>
      if self.mantissa.is_zero() {
        0
      } else if self.mantissa < 0N {
        -1
      } else {
        1
      }
    NegativeInfinity => -1
    PositiveInfinity => 1
    NotANumber => 0
  }
}

///|
/// The absolute value, at the same width.
pub fn BigFloat::abs(self : BigFloat) -> BigFloat {
  match self.kind {
    Finite => finite_at(magnitude(self.mantissa), self.exponent, self.precision)
    PositiveInfinity => self
    NegativeInfinity => infinity_at(false, self.precision)
    NotANumber => self
  }
}

///|
/// The value at another width and rounding, which is what `Context` is for at
/// the point where a caller wants to fix a width once and pass values through it.
pub fn BigFloat::round(self : BigFloat, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_unary(self))
  match self.kind {
    Finite =>
      rounded_at(self.mantissa, self.exponent, c.precision, c.rounding, false)
    _ => { ..self, precision: c.precision, }
  }
}

///|
/// The sum, at the given width and rounding.
fn add_rounded(a : BigFloat, b : BigFloat, context : Context) -> BigFloat {
  let precision = context.precision
  let rounding = context.rounding
  match (a.kind, b.kind) {
    (NotANumber, _) | (_, NotANumber) => nan_at(precision)
    (PositiveInfinity, NegativeInfinity)
    | (NegativeInfinity, PositiveInfinity) => nan_at(precision)
    (PositiveInfinity, _) | (_, PositiveInfinity) =>
      infinity_at(false, precision)
    (NegativeInfinity, _) | (_, NegativeInfinity) =>
      infinity_at(true, precision)
    (Finite, Finite) => add_finite(a, b, precision, rounding)
  }
}

///|
/// The sum of two numbers.
fn add_finite(
  a : BigFloat,
  b : BigFloat,
  precision : Int32,
  rounding : Rounding,
) -> BigFloat {
  if a.mantissa.is_zero() {
    return rounded_at(b.mantissa, b.exponent, precision, rounding, false)
  }
  if b.mantissa.is_zero() {
    return rounded_at(a.mantissa, a.exponent, precision, rounding, false)
  }
  let la = magnitude(a.mantissa).bit_length()
  let lb = magnitude(b.mantissa).bit_length()
  let lead_a = a.exponent.to_int64() + la.to_int64()
  let lead_b = b.exponent.to_int64() + lb.to_int64()
  // When one operand's leading bit sits more than `precision` places above the
  // other's, the smaller one cannot reach the last bit of the sum. It can still
  // decide which side of a tie the sum falls on, and a single unit in the lowest
  // guard place says exactly that, so the shift stops there instead of running
  // for as long as the exponent difference does.
  if la <= precision && lead_a - lead_b >= (precision + 3).to_int64() {
    return nudged(
      a,
      (a.mantissa < 0N) == (b.mantissa < 0N),
      precision,
      rounding,
    )
  }
  if lb <= precision && lead_b - lead_a >= (precision + 3).to_int64() {
    return nudged(
      b,
      (a.mantissa < 0N) == (b.mantissa < 0N),
      precision,
      rounding,
    )
  }
  let common = if a.exponent <= b.exponent { a.exponent } else { b.exponent }
  let left = a.mantissa << (a.exponent - common)
  let right = b.mantissa << (b.exponent - common)
  rounded_at(left + right, common, precision, rounding, false)
}

///|
/// `a` plus a magnitude too small to reach its last place, in the direction
/// `same_sign` says the small magnitude points.
fn nudged(
  a : BigFloat,
  same_sign : Bool,
  precision : Int32,
  rounding : Rounding,
) -> BigFloat {
  let length = magnitude(a.mantissa).bit_length()
  let shift = precision + 2 - length
  let wide = magnitude(a.mantissa) << shift
  let value = if same_sign { wide + 1N } else { wide - 1N }
  let signed = if a.mantissa < 0N { -value } else { value }
  rounded_at(signed, a.exponent - shift, precision, rounding, false)
}

///|
/// The difference, at the given width and rounding.
fn sub_rounded(a : BigFloat, b : BigFloat, context : Context) -> BigFloat {
  add_rounded(a, neg_special(b), context)
}

///|
/// A value negated without rounding: the sign of the significand, or of the
/// infinity. A NaN keeps its kind.
fn neg_special(value : BigFloat) -> BigFloat {
  match value.kind {
    Finite => { ..value, mantissa: -value.mantissa, }
    PositiveInfinity => infinity_at(true, value.precision)
    NegativeInfinity => infinity_at(false, value.precision)
    NotANumber => value
  }
}

///|
/// The product, at the given width and rounding.
fn mul_rounded(a : BigFloat, b : BigFloat, context : Context) -> BigFloat {
  let precision = context.precision
  match (a.kind, b.kind) {
    (NotANumber, _) | (_, NotANumber) => nan_at(precision)
    (Finite, Finite) =>
      if a.mantissa.is_zero() || b.mantissa.is_zero() {
        finite_at(0N, 0, precision)
      } else {
        rounded_at(
          a.mantissa * b.mantissa,
          a.exponent + b.exponent,
          precision,
          context.rounding,
          false,
        )
      }
    (Finite, _) =>
      if a.mantissa.is_zero() {
        nan_at(precision)
      } else {
        infinity_at(is_negative(a) != is_negative(b), precision)
      }
    (_, Finite) =>
      if b.mantissa.is_zero() {
        nan_at(precision)
      } else {
        infinity_at(is_negative(a) != is_negative(b), precision)
      }
    _ => infinity_at(is_negative(a) != is_negative(b), precision)
  }
}

///|
/// The quotient, at the given width and rounding, answering an infinity or a NaN
/// where the divisor is zero — the operator's behaviour, which cannot raise.
fn quotient(a : BigFloat, b : BigFloat, context : Context) -> BigFloat {
  let precision = context.precision
  match (a.kind, b.kind) {
    (NotANumber, _) | (_, NotANumber) => nan_at(precision)
    (_, Finite) =>
      if b.mantissa.is_zero() {
        if a.kind == Finite && a.mantissa.is_zero() {
          nan_at(precision)
        } else {
          infinity_at(is_negative(a) != is_negative(b), precision)
        }
      } else if a.kind == Finite {
        if a.mantissa.is_zero() {
          finite_at(0N, 0, precision)
        } else {
          quotient_finite(a, b, precision, context.rounding)
        }
      } else {
        infinity_at(a.kind == NegativeInfinity, precision)
      }
    (_, _) =>
      // The divisor is an infinity: a number over it is zero, and an infinity
      // over it is the one quotient with no answer.
      if a.kind == Finite {
        finite_at(0N, 0, precision)
      } else {
        nan_at(precision)
      }
  }
}

///|
/// `top / bottom * 2^exponent` at a width, `top` and `bottom` positive.
///
/// The integer division keeps two bits past the width asked for and hands the
/// remainder to `rounded` as the sticky bit, so the last place of the quotient is
/// decided by the whole of the remainder rather than by the bits that fit.
fn ratio_at(
  top : @bigint.BigInt,
  bottom : @bigint.BigInt,
  exponent : Int32,
  precision : Int32,
  rounding : Rounding,
) -> BigFloat {
  let room = precision + 2 + bottom.bit_length() - top.bit_length()
  let shift = if room > 0 { room } else { 0 }
  let scaled = top << shift
  let q = scaled / bottom
  let remainder = scaled - q * bottom
  rounded_at(q, exponent - shift, precision, rounding, !remainder.is_zero())
}

///|
/// The quotient of two numbers, by one integer division that carries the
/// remainder as the sticky bit rather than throwing it away.
fn quotient_finite(
  a : BigFloat,
  b : BigFloat,
  precision : Int32,
  rounding : Rounding,
) -> BigFloat {
  let q = ratio_at(
    magnitude(a.mantissa),
    magnitude(b.mantissa),
    a.exponent - b.exponent,
    precision,
    rounding,
  )
  if (a.mantissa < 0N) == (b.mantissa < 0N) {
    q
  } else {
    neg_special(q)
  }
}

///|
/// The quotient, raising `ZeroDivision` instead of answering an infinity.
///
/// The operator cannot raise, so it answers `±inf` and `nan` the way IEEE 754
/// does; a caller who would rather be told calls this.
pub fn BigFloat::divide(
  self : BigFloat,
  other : BigFloat,
  context? : Context,
) -> BigFloat raise Refused {
  if other.is_zero() {
    raise ZeroDivision
  }
  quotient(self, other, context_of(context, inherited(self, other)))
}

///|
/// Two values with the same sign, or neither with one.
fn same_side(a : BigFloat, b : BigFloat) -> Bool {
  (a.mantissa < 0N) == (b.mantissa < 0N)
}

///|
/// Whether the value is below zero, which for an infinity is the only thing its
/// kind has to say.
fn is_negative(value : BigFloat) -> Bool {
  match value.kind {
    Finite => value.mantissa < 0N
    NegativeInfinity => true
    _ => false
  }
}

///|
/// The order of two magnitudes whose leading bits sit at the same place.
fn compare_magnitude(a : BigFloat, b : BigFloat) -> Int32 {
  let common = if a.exponent <= b.exponent { a.exponent } else { b.exponent }
  let left = magnitude(a.mantissa) << (a.exponent - common)
  let right = magnitude(b.mantissa) << (b.exponent - common)
  left.compare(right)
}

///|
/// The order of two numbers, and of the infinities, with a NaN ordered above
/// everything so that a sorted array of them still has one.
fn compare_values(a : BigFloat, b : BigFloat) -> Int32 {
  match (a.kind, b.kind) {
    (NotANumber, NotANumber) => 0
    (NotANumber, _) => 1
    (_, NotANumber) => -1
    (PositiveInfinity, PositiveInfinity) => 0
    (NegativeInfinity, NegativeInfinity) => 0
    (PositiveInfinity, _) => 1
    (_, PositiveInfinity) => -1
    (NegativeInfinity, _) => -1
    (_, NegativeInfinity) => 1
    (Finite, Finite) =>
      if a.mantissa.is_zero() && b.mantissa.is_zero() {
        0
      } else if a.mantissa.is_zero() {
        if b.mantissa < 0N {
          1
        } else {
          -1
        }
      } else if b.mantissa.is_zero() {
        if a.mantissa < 0N {
          -1
        } else {
          1
        }
      } else if same_side(a, b) {
        let order = compare_magnitude(a, b)
        if a.mantissa < 0N {
          -order
        } else {
          order
        }
      } else if a.mantissa < 0N {
        -1
      } else {
        1
      }
  }
}

// The operators take the wider of their two operands and round to nearest even:
// an answer is as good as what went into it and no better, and a caller who wants
// another width or another direction says so through a `Context`.

///|
pub impl Add for BigFloat with fn add(self, other) {
  add_rounded(self, other, inherited(self, other))
}

///|
pub impl Sub for BigFloat with fn sub(self, other) {
  sub_rounded(self, other, inherited(self, other))
}

///|
pub impl Mul for BigFloat with fn mul(self, other) {
  mul_rounded(self, other, inherited(self, other))
}

///|
pub impl Div for BigFloat with fn div(self, other) {
  quotient(self, other, inherited(self, other))
}

///|
pub impl Neg for BigFloat with fn neg(self) {
  neg_special(self)
}

///|
pub impl Eq for BigFloat with fn equal(self, other) {
  // A NaN is not equal to anything, itself included: it is the answer to a
  // question, and two answers to questions nobody can answer are not the same
  // number.
  self.kind != NotANumber &&
  other.kind != NotANumber &&
  compare_values(self, other) == 0
}

///|
pub impl Compare for BigFloat with fn compare(self, other) {
  compare_values(self, other)
}

///|
pub impl Default for BigFloat with fn default() {
  BigFloat::zero()
}

///|
pub extend BigFloat with Show::{to_string, output}

///|
pub extend BigFloat with Eq::{equal, not_equal}

///|
pub extend BigFloat with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend BigFloat with Add::{add}

///|
pub extend BigFloat with Sub::{sub}

///|
pub extend BigFloat with Mul::{mul}

///|
pub extend BigFloat with Div::{div}

///|
pub extend BigFloat with Neg::{neg}

///|
pub extend BigFloat with Default::{default}

// The context-taking form of the four operators. `add`, `sub` and `mul` are
// spelled by the traits above, so the method of that name on `BigFloat` is the
// operator's; here the context is the receiver and the operands follow it.

///|
/// The sum of `a` and `b` at this width and rounding.
pub fn Context::add(self : Context, a : BigFloat, b : BigFloat) -> BigFloat {
  add_rounded(a, b, self)
}

///|
/// The difference of `a` and `b` at this width and rounding.
pub fn Context::sub(self : Context, a : BigFloat, b : BigFloat) -> BigFloat {
  sub_rounded(a, b, self)
}

///|
/// The product of `a` and `b` at this width and rounding.
pub fn Context::mul(self : Context, a : BigFloat, b : BigFloat) -> BigFloat {
  mul_rounded(a, b, self)
}

///|
/// The quotient of `a` and `b` at this width and rounding, answering `±inf` and
/// `nan` where that is the answer.
pub fn Context::div(self : Context, a : BigFloat, b : BigFloat) -> BigFloat {
  quotient(a, b, self)
}

///|
/// The quotient of `a` and `b`, raising `ZeroDivision` for a zero divisor.
pub fn Context::divide(
  self : Context,
  a : BigFloat,
  b : BigFloat,
) -> BigFloat raise Refused {
  if b.is_zero() {
    raise ZeroDivision
  }
  quotient(a, b, self)
}
