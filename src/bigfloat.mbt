// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A fixed-point real: `mantissa / 2^bits`. Two values that meet in an operation
// must share `bits`; every constructor here takes it, so a whole computation is
// carried at one width and the rounding of each step is the one truncation below.
//
// It carries a width, which is why it is a type here rather than a fifth kind in
// `Number`: the tower's kinds are widthless, and a binary operation between two
// real numbers would have no rule for which width the answer keeps. A caller
// chooses the width once and passes it, which is also what makes the rounding of
// a whole computation statable in one sentence.

///|
/// A real number carried as `mantissa / 2^bits`.
///
/// `bits` is the number of fractional bits, so the value has about
/// `bits * 0.301` decimal digits. All the values in one computation share it:
/// `add`, `sub`, `mul` and `div` keep the left operand's width, and mixing two
/// widths is a mistake the caller avoids by constructing everything from one
/// `bits`.
pub struct BigFloat {
  /// The integer the value is scaled from.
  mantissa : @bigint.BigInt
  /// The number of fractional bits.
  bits : Int32
}

///|
/// The fractional bits for a requested count of decimal digits, with guard bits
/// left for the truncation each operation drops.
pub fn BigFloat::bits_for_digits(digits : Int32) -> Int32 {
  digits * 10 / 3 + 48
}

///|
/// The decimal digits a width is worth, the inverse of `bits_for_digits`.
pub fn BigFloat::digits_for_bits(bits : Int32) -> Int32 {
  bits * 3 / 10
}

///|
/// Zero at the given width.
pub fn BigFloat::zero(bits : Int32) -> BigFloat {
  { mantissa: @bigint.BigInt::from_int(0), bits, }
}

///|
/// One at the given width.
pub fn BigFloat::one(bits : Int32) -> BigFloat {
  { mantissa: @bigint.BigInt::from_int(1) << bits, bits, }
}

///|
/// An integer at the given width.
pub fn BigFloat::of_int(value : Int32, bits : Int32) -> BigFloat {
  { mantissa: @bigint.BigInt::from_int(value) << bits, bits, }
}

///|
/// `integer / 10^places` at the given width: how a decimal constant such as pi
/// is seeded without a parser.
pub fn BigFloat::of_scaled(
  integer : String,
  places : Int32,
  bits : Int32,
) -> BigFloat {
  let numerator = @bigint.BigInt::from_string(integer) << bits
  { mantissa: numerator / pow10(places), bits, }
}

///|
/// The sum.
pub fn BigFloat::add(self : BigFloat, other : BigFloat) -> BigFloat {
  { mantissa: self.mantissa + other.mantissa, bits: self.bits, }
}

///|
/// The difference.
pub fn BigFloat::sub(self : BigFloat, other : BigFloat) -> BigFloat {
  { mantissa: self.mantissa - other.mantissa, bits: self.bits, }
}

///|
/// The product, truncated back to the width.
pub fn BigFloat::mul(self : BigFloat, other : BigFloat) -> BigFloat {
  { mantissa: (self.mantissa * other.mantissa) >> self.bits, bits: self.bits, }
}

///|
/// The quotient, truncated to the width.
pub fn BigFloat::div(self : BigFloat, other : BigFloat) -> BigFloat {
  { mantissa: (self.mantissa << self.bits) / other.mantissa, bits: self.bits, }
}

///|
/// The negation.
pub fn BigFloat::neg(self : BigFloat) -> BigFloat {
  { mantissa: -self.mantissa, bits: self.bits, }
}

///|
/// The absolute value.
pub fn BigFloat::abs(self : BigFloat) -> BigFloat {
  if self.mantissa < @bigint.BigInt::from_int(0) {
    self.neg()
  } else {
    self
  }
}

///|
/// Whether the value is exactly zero.
pub fn BigFloat::is_zero(self : BigFloat) -> Bool {
  self.mantissa.is_zero()
}

///|
/// The sign of the comparison: negative, zero or positive.
pub fn BigFloat::compare(self : BigFloat, other : BigFloat) -> Int32 {
  self.mantissa.compare(other.mantissa)
}

///|
/// Whether this is less than `other`.
pub fn BigFloat::lt(self : BigFloat, other : BigFloat) -> Bool {
  self.compare(other) < 0
}

///|
/// Whether this is at most `other`.
pub fn BigFloat::le(self : BigFloat, other : BigFloat) -> Bool {
  self.compare(other) <= 0
}

///|
/// Whether the two are within `tolerance` of each other.
pub fn BigFloat::approx(
  self : BigFloat,
  other : BigFloat,
  tolerance : BigFloat,
) -> Bool {
  self.sub(other).abs().le(tolerance)
}

///|
/// The square root, rounded down to the width.
pub fn BigFloat::sqrt(self : BigFloat) -> BigFloat {
  { mantissa: bigfloat_isqrt(self.mantissa << self.bits), bits: self.bits, }
}

///|
/// Integer square root, by Newton's method: the largest `r` with `r * r <= n`.
fn bigfloat_isqrt(n : @bigint.BigInt) -> @bigint.BigInt {
  let zero = @bigint.BigInt::from_int(0)
  if n.compare(zero) <= 0 {
    return zero
  }
  let length = n.bit_length()
  let mut guess = @bigint.BigInt::from_int(1) << (length / 2 + 1)
  while true {
    let next = (guess + n / guess) >> 1
    if next.compare(guess) >= 0 {
      break
    }
    guess = next
  }
  guess
}

///|
/// `ln(2)` at the given width.
pub fn BigFloat::ln2(bits : Int32) -> BigFloat {
  BigFloat::of_scaled(
    "0693147180559945309417232121458176568075500134360255254120680009493393621969694715605863326996418687542001481020570685733",
    120, bits,
  )
}

///|
/// Pi at the given width.
pub fn BigFloat::pi(bits : Int32) -> BigFloat {
  BigFloat::of_scaled(
    "3141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067982148086513282306647",
    120, bits,
  )
}

///|
/// `e^x`, by range reduction to `-ln(2)/2 .. ln(2)/2` and a Taylor series.
pub fn BigFloat::exp(self : BigFloat) -> BigFloat {
  let bits = self.bits
  if self.is_zero() {
    return BigFloat::one(bits)
  }
  let base = BigFloat::ln2(bits)
  let steps = self.div(base).truncate_to_int()
  // `exp` is a shift by `steps` bits, so a large argument is a value no fixed
  // point can hold; say so rather than build an astronomically long integer.
  if steps > 100000 || steps < -100000 {
    abort("BigFloat::exp: the exponent is beyond the fixed-point range")
  }
  let rest = self.sub(BigFloat::of_int(steps, bits).mul(base))
  let mut term = BigFloat::one(bits)
  let mut sum = BigFloat::one(bits)
  let mut n : Int32 = 0
  while n < 400 {
    n = n + 1
    term = term.mul(rest).div(BigFloat::of_int(n, bits))
    sum = sum.add(term)
    if term.is_zero() {
      break
    }
  }
  if steps >= 0 {
    { mantissa: sum.mantissa << steps, bits, }
  } else {
    { mantissa: sum.mantissa >> (0 - steps), bits, }
  }
}

///|
/// The natural logarithm, by `ln(m) + k ln(2)` with `m` in `1..2` and the
/// `atanh` series for `ln(m)`.
pub fn BigFloat::ln(self : BigFloat) -> BigFloat {
  let bits = self.bits
  let length = self.mantissa.bit_length()
  let exponent : Int32 = length - 1 - bits
  let scaled = if exponent >= 0 {
    self.mantissa >> exponent
  } else {
    self.mantissa << (0 - exponent)
  }
  let mantissa = { mantissa: scaled, bits, }
  let one = BigFloat::one(bits)
  let z = mantissa.sub(one).div(mantissa.add(one))
  let squared = z.mul(z)
  let mut term = z
  let mut sum = z
  let mut i : Int32 = 0
  while i < 400 {
    i = i + 1
    term = term.mul(squared)
    let add = term.div(BigFloat::of_int(2 * i + 1, bits))
    sum = sum.add(add)
    if add.is_zero() {
      break
    }
  }
  let ln_mantissa = sum.mul(BigFloat::of_int(2, bits))
  ln_mantissa.add(BigFloat::ln2(bits).mul(BigFloat::of_int(exponent, bits)))
}

///|
/// The integer part of the value, truncated towards zero.
fn BigFloat::truncate_to_int(self : BigFloat) -> Int32 {
  (self.mantissa >> self.bits).to_int()
}

///|
/// A decimal literal at the given width: `"0.5772156649"`, `"-3.14"`, `"1e-40"`.
///
/// This is how a constant that is known to more digits than a double holds gets
/// into a computation without a caller having to hand-count the places. The
/// digits are read as an integer and divided by the matching power of ten once,
/// so the only rounding is that single division.
pub fn BigFloat::of_decimal(text : String, bits : Int32) -> BigFloat {
  let length = text.length()
  let mut index = 0
  let mut negative = false
  if length > 0 && text.get_char(0) == Some('-') {
    negative = true
    index = 1
  }
  // The exponent, if any, is the tail after `e`, and it is read as an integer.
  let mut exponent = 0
  let mut exponent_negative = false
  let mut mantissa_end = length
  let mut probe = index
  while probe < length {
    let c = text.get_char(probe).unwrap()
    if c == 'e' || c == 'E' {
      mantissa_end = probe
      let mut e = probe + 1
      // Both signs are accepted: `Double::to_string` writes a positive exponent
      // as `e+21`, and a literal read back from one has to survive the trip.
      if e < length &&
        (text.get_char(e) == Some('-') || text.get_char(e) == Some('+')) {
        exponent_negative = text.get_char(e) == Some('-')
        e = e + 1
      }
      while e < length {
        exponent = exponent * 10 + (text.get_char(e).unwrap().to_int() - 48)
        e = e + 1
      }
      break
    }
    probe = probe + 1
  }
  // The point, if any, splits the mantissa into a whole part and a fraction. The
  // two are sliced rather than assembled a character at a time: a hundred-digit
  // constant is parsed once per Bernoulli term of a Stirling expansion, and
  // growing a string one character at a time there is quadratic in its length.
  let mut point = mantissa_end
  let mut probe = index
  while probe < mantissa_end {
    if text.get_char(probe).unwrap() == '.' {
      point = probe
      break
    }
    probe = probe + 1
  }
  let whole = if point > index { text[index:point].to_owned() } else { "" }
  let fraction = if point < mantissa_end {
    text[point + 1:mantissa_end].to_owned()
  } else {
    ""
  }
  let digits = whole + fraction
  let places = fraction.length() -
    (if exponent_negative { 0 - exponent } else { exponent })
  let one = BigFloat::one(bits)
  let mut value = one
  if digits != "" {
    let numerator = {
      mantissa: @bigint.BigInt::from_string(digits) << bits,
      bits,
    }
    let magnitude = if places >= 0 { places } else { 0 - places }
    let scale = { mantissa: pow10(magnitude) << bits, bits, }
    value = if places >= 0 {
      numerator.div(scale)
    } else {
      numerator.mul(scale)
    }
  }
  if negative {
    value.neg()
  } else {
    value
  }
}

///|
/// `x^y`, through `exp(y ln x)`. The base must be positive: a fixed-point value
/// has no branch for a negative base and a fractional exponent.
pub fn BigFloat::pow(self : BigFloat, exponent : BigFloat) -> BigFloat {
  let bits = self.bits
  if self.is_zero() {
    return BigFloat::zero(bits)
  }
  if self.mantissa.compare(@bigint.BigInt::from_int(0)) < 0 {
    abort("BigFloat::pow: the base must be positive")
  }
  exponent.mul(self.ln()).exp()
}

///|
/// The sine, by range reduction to `-pi .. pi` and the Taylor series.
pub fn BigFloat::sin(self : BigFloat) -> BigFloat {
  let bits = self.bits
  if self.abs().to_double() > 1.0e6 {
    abort(
      "BigFloat::sin: the argument is beyond the range a fixed point reduces",
    )
  }
  let pi = BigFloat::pi(bits)
  let turn = pi.mul(BigFloat::of_int(2, bits))
  let turns = self.div(turn).truncate_to_int()
  let mut r = self.sub(turn.mul(BigFloat::of_int(turns, bits)))
  if pi.lt(r) {
    r = r.sub(turn)
  }
  if r.lt(pi.neg()) {
    r = r.add(turn)
  }
  let squared = r.mul(r)
  let mut term = r
  let mut sum = r
  let mut n : Int32 = 0
  while n < 400 {
    n = n + 1
    let denominator = BigFloat::of_int(2 * n * (2 * n + 1), bits)
    term = term.mul(squared).div(denominator).neg()
    sum = sum.add(term)
    if term.is_zero() {
      break
    }
  }
  sum
}

///|
/// The cosine, by the same reduction and the Taylor series that starts at one.
pub fn BigFloat::cos(self : BigFloat) -> BigFloat {
  let bits = self.bits
  if self.abs().to_double() > 1.0e6 {
    abort(
      "BigFloat::cos: the argument is beyond the range a fixed point reduces",
    )
  }
  let pi = BigFloat::pi(bits)
  let turn = pi.mul(BigFloat::of_int(2, bits))
  let turns = self.div(turn).truncate_to_int()
  let mut r = self.sub(turn.mul(BigFloat::of_int(turns, bits)))
  if pi.lt(r) {
    r = r.sub(turn)
  }
  if r.lt(pi.neg()) {
    r = r.add(turn)
  }
  let squared = r.mul(r)
  let mut term = BigFloat::one(bits)
  let mut sum = BigFloat::one(bits)
  let mut n : Int32 = 0
  while n < 400 {
    n = n + 1
    let denominator = BigFloat::of_int((2 * n - 1) * (2 * n), bits)
    term = term.mul(squared).div(denominator).neg()
    sum = sum.add(term)
    if term.is_zero() {
      break
    }
  }
  sum
}

///|
/// The arctangent, by halving the angle until the series converges and doubling
/// the result back. `atan x = 2 atan (x / (1 + sqrt(1 + x^2)))` holds for every
/// `x`, and each halving quarters the argument, so the Taylor series is reached
/// after a handful of steps from anywhere.
pub fn BigFloat::atan(self : BigFloat) -> BigFloat {
  let bits = self.bits
  let one = BigFloat::one(bits)
  let negative = self.mantissa.compare(@bigint.BigInt::from_int(0)) < 0
  let mut x = self.abs()
  let mut halvings : Int32 = 0
  while 0.1 < x.to_double() && halvings < 40 {
    let root = one.add(x.mul(x)).sqrt()
    x = x.div(one.add(root))
    halvings = halvings + 1
  }
  let squared = x.mul(x)
  let mut term = x
  let mut sum = x
  let mut n : Int32 = 0
  while n < 400 {
    n = n + 1
    term = term.mul(squared).neg()
    let add = term.div(BigFloat::of_int(2 * n + 1, bits))
    sum = sum.add(add)
    if add.is_zero() {
      break
    }
  }
  let mut scaled = sum
  let mut i : Int32 = 0
  while i < halvings {
    scaled = scaled.mul(BigFloat::of_int(2, bits))
    i = i + 1
  }
  if negative {
    scaled.neg()
  } else {
    scaled
  }
}

///|
/// The value as a double, to the precision a double holds.
pub fn BigFloat::to_double(self : BigFloat) -> Double {
  let zero = @bigint.BigInt::from_int(0)
  let negative = self.mantissa.compare(zero) < 0
  let magnitude = if negative { -self.mantissa } else { self.mantissa }
  let length = magnitude.bit_length()
  if length == 0 {
    return 0.0
  }
  let keep = 62
  let shift = if length > keep { length - keep } else { 0 }
  let top = (magnitude >> shift).to_int64().to_double()
  let exponent : Int32 = shift - self.bits
  let scaled = top * @math.pow(2.0, exponent.to_double())
  if negative {
    -scaled
  } else {
    scaled
  }
}
