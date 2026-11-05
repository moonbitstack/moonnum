// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A complex number of `BigFloat`s: the second type the real functions needed,
// and the promotion `to_complex` that makes it reachable from a real value.

///|
/// A complex number: `z.real + z.imag * j`, both parts carried at whatever width
/// they were given.
///
/// The two parts are independent `BigFloat`s, so a width is a property of each
/// part rather than of the pair; an operation rounds both to the width it is
/// told, which for the operators is the wider of the two operands.
///
/// This is not `Complex` generalised. `Complex` is fifty-three bits with C11
/// Annex G's signed zeros and infinity recovery; this one has no signed zero at
/// all — `BigFloat` cannot spell one — so it reads a branch cut from the upper
/// side and follows the principal branches `mpmath` uses.
pub(all) struct BigComplex {
  real : BigFloat
  imag : BigFloat
}

///|
/// `BigComplex(real, imag)`, with both parts exactly as given.
pub fn BigComplex::new(real : BigFloat, imag : BigFloat) -> BigComplex {
  { real, imag, }
}

///|
/// The promotion: the same value with an imaginary part of zero at the same
/// width.
///
/// Exact — a real number is a complex number already, and nothing is rounded by
/// saying so. This is how a caller reaches the principal square root of a
/// negative, or the logarithm of one:
///
/// ```moonbit nocheck
/// let c = @moonnum.Context::new(200)
/// (-@moonnum.BigFloat::one(context=c)).to_complex().sqrt(context=c)  // 0 + 1j
/// ```
pub fn BigFloat::to_complex(self : BigFloat) -> BigComplex {
  { real: self, imag: BigFloat::zero(context=Context::new(self.precision())), }
}

///|
/// The way back, for a caller who knows the imaginary part is zero.
///
/// Refuses rather than dropping a part that is not zero: `2 + 3j` is not a real
/// number, and a `to_real` that answered `2` would be the kind of quiet answer
/// this library does not give.
pub fn BigComplex::to_real(
  self : BigComplex,
  context? : Context,
) -> BigFloat raise Refused {
  if !self.imag.is_zero() {
    raise Domain(reason="the imaginary part is not zero")
  }
  match context {
    None => self.real
    Some(c) => self.real.round(context=c)
  }
}

///|
/// The width an operation inherits when the caller does not name one: the wider
/// of the two parts.
pub fn BigComplex::precision(self : BigComplex) -> Int32 {
  if self.real.precision() >= self.imag.precision() {
    self.real.precision()
  } else {
    self.imag.precision()
  }
}

///|
/// The wider of two widths.
fn wider(a : Int32, b : Int32) -> Int32 {
  if a >= b {
    a
  } else {
    b
  }
}

///|
/// The context an operation inherits: the value's own width, rounded to nearest
/// even.
fn inherited_of(value : BigComplex) -> Context {
  Context::new(value.precision())
}

///|
/// Both parts rounded to one width and one direction.
fn both_rounded(
  value : BigComplex,
  precision : Int32,
  rounding : Rounding,
) -> BigComplex {
  let c = Context::new(precision, rounding~)
  { real: value.real.round(context=c), imag: value.imag.round(context=c), }
}

///|
/// The width the parts of a complex operation are computed at: the width asked
/// for, plus the guard the rounding of each part and the error of the other one
/// take.
fn complex_width(precision : Int32) -> Int32 {
  working(precision)
}

///|
/// `z + w` at the given width.
fn sum_of(a : BigComplex, b : BigComplex, c : Context) -> BigComplex {
  let w = Context::new(complex_width(c.precision))
  {
    real: w.add(a.real, b.real).round(context=c),
    imag: w.add(a.imag, b.imag).round(context=c),
  }
}

///|
/// `z - w` at the given width.
fn difference_of(a : BigComplex, b : BigComplex, c : Context) -> BigComplex {
  let w = Context::new(complex_width(c.precision))
  {
    real: w.sub(a.real, b.real).round(context=c),
    imag: w.sub(a.imag, b.imag).round(context=c),
  }
}

///|
/// `z * w` at the given width, from the four products rather than from a
/// polar form: polar needs two arctangents and two square roots, and the
/// four products need nothing that can pick the wrong branch.
fn product_of(a : BigComplex, b : BigComplex, c : Context) -> BigComplex {
  let w = Context::new(complex_width(c.precision))
  let ac = w.mul(a.real, b.real)
  let bd = w.mul(a.imag, b.imag)
  let ad = w.mul(a.real, b.imag)
  let bc = w.mul(a.imag, b.real)
  {
    real: w.sub(ac, bd).round(context=c),
    imag: w.add(ad, bc).round(context=c),
  }
}

///|
/// `z / w` at the given width.
///
/// Refuses a zero divisor, as `Fraction::divide` and `Complex::divide` do:
/// `Div` cannot raise, so the operator is not offered for this type and the
/// division that can fail is a function.
pub fn BigComplex::divide(
  self : BigComplex,
  other : BigComplex,
  context? : Context,
) -> BigComplex raise Refused {
  let c = context_of(context, inherited_of(self))
  let w = Context::new(complex_width(c.precision))
  let denominator = w.add(
    w.mul(other.real, other.real),
    w.mul(other.imag, other.imag),
  )
  if denominator.is_zero() {
    raise ZeroDivision
  }
  {
    real: w
    .div(
      w.add(w.mul(self.real, other.real), w.mul(self.imag, other.imag)),
      denominator,
    )
    .round(context=c),
    imag: w
    .div(
      w.sub(w.mul(self.imag, other.real), w.mul(self.real, other.imag)),
      denominator,
    )
    .round(context=c),
  }
}

///|
/// The modulus, `sqrt(re^2 + im^2)`, rounded at the context's width.
///
/// An infinite part makes it infinite: a modulus is a distance, and a distance
/// to a point at infinity is not a question without an answer.
pub fn BigComplex::abs(self : BigComplex, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_of(self))
  if self.real.is_nan() || self.imag.is_nan() {
    return nan_at(c.precision)
  }
  if self.real.is_infinite() || self.imag.is_infinite() {
    return infinity_at(false, c.precision)
  }
  let w = Context::new(complex_width(c.precision))
  let square = w.add(w.mul(self.real, self.real), w.mul(self.imag, self.imag))
  square.sqrt(context=w).round(context=c)
}

///|
/// The argument in `(-pi, pi]`, the principal value `atan2(im, re)`.
///
/// A point on the negative real axis has argument `pi` and not `-pi`: the cut is
/// read from the side approaching from above, which is the only side this type
/// can spell.
pub fn BigComplex::arg(self : BigComplex, context? : Context) -> BigFloat {
  let c = context_of(context, inherited_of(self))
  atan2_at(self.imag, self.real, complex_width(c.precision)).round(context=c)
}

///|
/// `atan2(y, x)` at a width: the angle of the point `(x, y)`.
///
/// Written with the half-angle identity rather than with `asin` and a case
/// analysis, so that the argument of the arctangent series is always the small
/// side: for `x > 0` the ratio is `y / (r + x)` and for `x < 0` it is
/// `|y| / (r - x)`, both below one in magnitude, and neither divides by
/// something that has cancelled.
fn atan2_at(y : BigFloat, x : BigFloat, width : Int32) -> BigFloat {
  let w = Context::new(width)
  if x.is_zero() {
    return if y.is_zero() {
      BigFloat::zero(context=w)
    } else if y < BigFloat::zero(context=w) {
      let half = half_pi(width)
      half.neg()
    } else {
      half_pi(width)
    }
  }
  let product = w.add(w.mul(x, x), w.mul(y, y))
  let radius = product.sqrt(context=w)
  let two = BigFloat::of_int(2, context=w)
  if x > BigFloat::zero(context=w) {
    let ratio = w.div(y, w.add(radius, x))
    w.mul(two, ratio.atan(context=w))
  } else {
    let ratio = w.div(y.abs(), w.sub(radius, x))
    let swing = w.mul(two, ratio.atan(context=w))
    if y >= BigFloat::zero(context=w) {
      // Above the axis the answer is `pi` less the swing back toward the
      // origin; below it, the same with `-pi` as the starting point.
      w.sub(pi_at(width), swing)
    } else {
      w.sub(swing, pi_at(width))
    }
  }
}

///|
/// The conjugate: the same distance from the origin, on the other side of the
/// real axis.
pub fn BigComplex::conjugate(self : BigComplex) -> BigComplex {
  { real: self.real, imag: self.imag.neg(), }
}

///|
/// The imaginary unit at a width.
pub fn BigComplex::j(context? : Context) -> BigComplex {
  let c = context_of(context, Context::new(53))
  { real: BigFloat::zero(context=c), imag: BigFloat::one(context=c), }
}

///|
/// A real value as a complex one, without going through an instance.
pub fn BigComplex::of_real(value : BigFloat) -> BigComplex {
  value.to_complex()
}

///|
/// `z + w` at the context's width and direction — the complex twin of
/// `Context::add`, which is the only way to ask for a width other than the
/// wider of the two operands.
pub fn Context::add_complex(
  self : Context,
  a : BigComplex,
  b : BigComplex,
) -> BigComplex {
  sum_of(a, b, self)
}

///|
/// `z - w` at the context's width.
pub fn Context::sub_complex(
  self : Context,
  a : BigComplex,
  b : BigComplex,
) -> BigComplex {
  difference_of(a, b, self)
}

///|
/// `z * w` at the context's width.
pub fn Context::mul_complex(
  self : Context,
  a : BigComplex,
  b : BigComplex,
) -> BigComplex {
  product_of(a, b, self)
}

///|
/// `z / w` at the context's width, refusing a zero divisor as `divide` does.
pub fn Context::divide_complex(
  self : Context,
  a : BigComplex,
  b : BigComplex,
) -> BigComplex raise Refused {
  a.divide(b, context=self)
}

///|
/// `z + w`, at the wider of the two widths, rounded to nearest even.
pub impl Add for BigComplex with fn add(self, other) {
  sum_of(self, other, Context::new(wider(self.precision(), other.precision())))
}

///|
/// `z - w`, at the wider of the two widths.
pub impl Sub for BigComplex with fn sub(self, other) {
  difference_of(
    self,
    other,
    Context::new(wider(self.precision(), other.precision())),
  )
}

///|
/// `z * w`, at the wider of the two widths.
pub impl Mul for BigComplex with fn mul(self, other) {
  product_of(
    self,
    other,
    Context::new(wider(self.precision(), other.precision())),
  )
}

///|
/// `-z`.
pub impl Neg for BigComplex with fn neg(self) {
  { real: self.real.neg(), imag: self.imag.neg(), }
}

///|
pub impl Eq for BigComplex with fn equal(self, other) {
  self.real == other.real && self.imag == other.imag
}

///|
pub impl Default for BigComplex with fn default() {
  { real: BigFloat::default(), imag: BigFloat::default(), }
}

///|
/// `(1.0+2.0j)`: both parts printed the way a `BigFloat` prints, so a complex
/// value says as much about its width as a real one does.
pub impl Show for BigComplex with fn to_string(self) {
  let real = self.real.to_string()
  if !self.imag.is_nan() && self.imag.sign() < 0 {
    "(" + real + "-" + self.imag.neg().to_string() + "j)"
  } else {
    "(" + real + "+" + self.imag.to_string() + "j)"
  }
}

///|
pub impl Show for BigComplex with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub extend BigComplex with Show::{to_string, output}

///|
pub extend BigComplex with Eq::{equal, not_equal}

///|
pub extend BigComplex with Add::{add}

///|
pub extend BigComplex with Sub::{sub}

///|
/// The product, on the type, so that `z * w` works without importing the trait.
pub extend BigComplex with Mul::{mul}

///|
pub extend BigComplex with Neg::{neg}

///|
pub extend BigComplex with Default::{default}
