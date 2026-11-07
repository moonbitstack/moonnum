// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A fixed-point real: `mantissa / 2^bits`. Every constructor takes the width, so a
// whole computation is carried at one width and the rounding of each step is the
// one truncation below. Fixed rather than floating: a value far below one keeps
// fewer significant digits than one near it, which a caller picks `bits` to allow.
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
/// `bits * 0.301` decimal digits after the point. An operation keeps the left
/// operand's width and brings the right one to it, so two widths give the answer
/// the left width can hold rather than a wrong one.
///
/// A value outside an operation's domain, such as the square root of a negative
/// number, stops the program with the reason, as a division of integers by zero
/// does: these operations are written with `+` and `*` and cannot raise. Text from
/// outside goes through `parse_fixed`, which does.
pub struct Fixed {
  /// The integer the value is scaled from.
  mantissa : @bigint.BigInt
  /// The number of fractional bits.
  bits : Int32
}

///|
/// The fractional bits for a requested count of decimal digits, with guard bits
/// left for the truncation each operation drops.
pub fn Fixed::bits_for_digits(digits : Int32) -> Int32 {
  digits * 10 / 3 + 48
}

///|
/// The decimal digits a width can represent, guard bits included.
pub fn Fixed::digits_for_bits(bits : Int32) -> Int32 {
  bits * 3 / 10
}

///|
/// The same value at another width: exact when it widens, truncated when it
/// narrows.
pub fn Fixed::at(self : Fixed, bits : Int32) -> Fixed {
  let shift = bits - self.bits
  {
    mantissa: if shift >= 0 {
      self.mantissa << shift
    } else {
      self.mantissa >> (0 - shift)
    },
    bits,
  }
}

///|
/// Zero at the given width.
pub fn Fixed::zero(bits : Int32) -> Fixed {
  { mantissa: @bigint.BigInt::from_int(0), bits, }
}

///|
/// One at the given width.
pub fn Fixed::one(bits : Int32) -> Fixed {
  { mantissa: @bigint.BigInt::from_int(1) << bits, bits, }
}

///|
/// An integer at the given width.
pub fn Fixed::of_int(value : Int32, bits : Int32) -> Fixed {
  { mantissa: @bigint.BigInt::from_int(value) << bits, bits, }
}

///|
/// `integer / 10^places` at the given width: how a decimal constant such as pi
/// is seeded without a parser.
pub fn Fixed::of_scaled(
  integer : String,
  places : Int32,
  bits : Int32,
) -> Fixed {
  let numerator = @bigint.BigInt::from_string(integer) << bits
  { mantissa: numerator / pow10(places), bits, }
}

///|
/// The absolute value.
pub fn Fixed::abs(self : Fixed) -> Fixed {
  if self.mantissa < 0N {
    -self
  } else {
    self
  }
}

///|
/// Whether the value is exactly zero.
pub fn Fixed::is_zero(self : Fixed) -> Bool {
  self.mantissa.is_zero()
}

///|
/// Whether the two are within `tolerance` of each other.
pub fn Fixed::approx(self : Fixed, other : Fixed, tolerance : Fixed) -> Bool {
  (self - other).abs() <= tolerance
}

///|
/// The square root, rounded down to the width.
pub fn Fixed::sqrt(self : Fixed) -> Fixed {
  if self.mantissa < 0N {
    abort("Fixed::sqrt: the argument is negative")
  }
  { mantissa: floor_sqrt(self.mantissa << self.bits), bits: self.bits, }
}

///|
/// Integer square root, by Newton's method: the largest `r` with `r * r <= n`.
fn floor_sqrt(n : @bigint.BigInt) -> @bigint.BigInt {
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
/// The widths the two constants below are known to.
const CONSTANT_BITS : Int32 = 390

///|
/// `atan(1 / n)` scaled by `2^scale`, or `atanh(1 / n)` when `hyperbolic`: the
/// Taylor series in integers, each term a division, so a width past the constants
/// costs time and not accuracy.
fn inverse_series(
  n : Int32,
  scale : Int32,
  hyperbolic~ : Bool,
) -> @bigint.BigInt {
  let divisor = @bigint.BigInt::from_int(n * n)
  let mut power = (1N << scale) / @bigint.BigInt::from_int(n)
  let mut sum = power
  let mut k : Int32 = 1
  while !power.is_zero() {
    power = power / divisor
    let term = power / @bigint.BigInt::from_int(2 * k + 1)
    sum = if hyperbolic || k % 2 == 0 { sum + term } else { sum - term }
    k = k + 1
  }
  sum
}

///|
/// `ln(2)` at the given width, `2 atanh(1/3)` past the width of the constant.
pub fn Fixed::ln2(bits : Int32) -> Fixed {
  if bits <= CONSTANT_BITS {
    return Fixed::of_scaled(
      "0693147180559945309417232121458176568075500134360255254120680009493393621969694715605863326996418687542001481020570685733",
      120, bits,
    )
  }
  let scale = bits + 32
  { mantissa: inverse_series(3, scale, hyperbolic=true) << 1 >> 32, bits, }
}

///|
/// Pi at the given width, Machin's formula past the width of the constant.
pub fn Fixed::pi(bits : Int32) -> Fixed {
  if bits <= CONSTANT_BITS {
    return Fixed::of_scaled(
      "3141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067982148086513282306647",
      120, bits,
    )
  }
  let scale = bits + 32
  let fifth = inverse_series(5, scale, hyperbolic=false)
  let far = inverse_series(239, scale, hyperbolic=false)
  { mantissa: ((fifth << 4) - (far << 2)) >> 32, bits, }
}

///|
/// `e^x`, by range reduction to `-ln(2)/2 .. ln(2)/2` and a Taylor series.
pub fn Fixed::exp(self : Fixed) -> Fixed {
  let bits = self.bits
  if self.is_zero() {
    return Fixed::one(bits)
  }
  let base = Fixed::ln2(bits)
  let steps = (self / base).floor_to_int()
  // `exp` is a shift by `steps` bits, so a large argument is a value no fixed
  // point can hold; say so rather than build an astronomically long integer.
  if steps > 100000 || steps < -100000 {
    abort("Fixed::exp: the exponent is beyond the fixed-point range")
  }
  let rest = self - Fixed::of_int(steps, bits) * base
  let mut term = Fixed::one(bits)
  let mut sum = Fixed::one(bits)
  let mut n : Int32 = 0
  while !term.is_zero() {
    n = n + 1
    term = term * rest / Fixed::of_int(n, bits)
    sum = sum + term
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
pub fn Fixed::ln(self : Fixed) -> Fixed {
  let bits = self.bits
  if self.mantissa <= 0N {
    abort("Fixed::ln: the argument is not positive")
  }
  let length = self.mantissa.bit_length()
  let exponent : Int32 = length - 1 - bits
  let scaled = if exponent >= 0 {
    self.mantissa >> exponent
  } else {
    self.mantissa << (0 - exponent)
  }
  let mantissa = { mantissa: scaled, bits, }
  let one = Fixed::one(bits)
  let z = (mantissa - one) / (mantissa + one)
  let squared = z * z
  let mut term = z
  let mut sum = z
  let mut i : Int32 = 0
  while !term.is_zero() {
    i = i + 1
    term = term * squared
    sum = sum + term / Fixed::of_int(2 * i + 1, bits)
  }
  sum * Fixed::of_int(2, bits) +
  Fixed::ln2(bits) * Fixed::of_int(exponent, bits)
}

///|
/// `e^x - 1`.
///
/// For a small argument the exponential's series, with the constant one left
/// out of the sum, is the answer: the terms fall from `x` and it is a handful
/// of them, and nothing is built that the answer does not carry. For a larger
/// argument the exponential has grown far from one, and taking one off is a
/// single truncation, so the ordinary exponential is called.
pub fn Fixed::expm1(self : Fixed) -> Fixed {
  let bits = self.bits
  if self.is_zero() {
    return Fixed::zero(bits)
  }
  if self.abs().to_double() <= 0.5 {
    let mut term = self
    let mut sum = self
    let mut n : Int32 = 1
    while !term.is_zero() {
      n = n + 1
      term = term * self / Fixed::of_int(n, bits)
      sum = sum + term
    }
    sum
  } else {
    self.exp() - Fixed::one(bits)
  }
}

///|
/// `ln(1 + x)`.
///
/// The two-argument form `ln(1 + x) = 2 atanh(x / (2 + x))` is summed from `x`
/// directly: for `x` a half or less in magnitude the argument of the series is
/// a third of `x` or less, so a few terms reach the width, and the value is
/// built from `x` rather than from `1 + x`. Past a half the ordinary logarithm
/// of `1 + x` is called instead.
///
/// An argument at or below minus one has `1 + x` at or below zero, and the
/// logarithm of that stops the program as the logarithm of a non-positive number
/// does.
pub fn Fixed::log1p(self : Fixed) -> Fixed {
  let bits = self.bits
  if self <= Fixed::of_int(-1, bits) {
    abort("Fixed::log1p: the argument is at or below minus one")
  }
  if self.is_zero() {
    return Fixed::zero(bits)
  }
  let one = Fixed::one(bits)
  if self.abs().to_double() <= 0.5 {
    // Sum the odd series on the magnitude: `|z| < 1`, so every term is
    // positive and truncates to zero, whereas a negative `z` under `>>`
    // (which floors) would settle on `-1` and never reach zero.
    let z = self / (one + one + self)
    let negative = z.mantissa < 0N
    let magnitude = z.abs()
    let squared = magnitude * magnitude
    let mut term = magnitude
    let mut sum = magnitude
    let mut i : Int32 = 0
    while !term.is_zero() {
      i = i + 1
      term = term * squared
      sum = sum + term / Fixed::of_int(2 * i + 1, bits)
    }
    let answer = sum * Fixed::of_int(2, bits)
    if negative {
      -answer
    } else {
      answer
    }
  } else {
    (one + self).ln()
  }
}

///|
/// The largest integer not above the value.
fn Fixed::floor_to_int(self : Fixed) -> Int32 {
  (self.mantissa >> self.bits).to_int()
}

///|
/// A decimal literal at the given width: `"0.5772156649"`, `"-3.14"`, `"1e-40"`.
///
/// This is how a constant that is known to more digits than a double holds gets
/// into a computation without a caller having to hand-count the places. The
/// digits are read as an integer and divided by the matching power of ten once,
/// so the only rounding is that single division. It is for constants a program
/// carries; text from outside goes through `parse_fixed`.
pub fn Fixed::of_decimal(text : String, bits : Int32) -> Fixed {
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
  if digits == "" {
    abort("Fixed::of_decimal: no digits in `\{text}`")
  }
  let numerator = {
    mantissa: @bigint.BigInt::from_string(digits) << bits,
    bits,
  }
  let magnitude = if places >= 0 { places } else { 0 - places }
  let scale = { mantissa: pow10(magnitude) << bits, bits, }
  let value = if places >= 0 { numerator / scale } else { numerator * scale }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// `x^y`, through `exp(y ln x)`. The base must be positive: a fixed-point value
/// has no branch for a negative base and a fractional exponent.
pub fn Fixed::pow(self : Fixed, exponent : Fixed) -> Fixed {
  let bits = self.bits
  if self.is_zero() {
    return Fixed::zero(bits)
  }
  if self.mantissa < 0N {
    abort("Fixed::pow: the base must be positive")
  }
  (exponent * self.ln()).exp()
}

///|
/// `x` brought into `-pi .. pi` by whole turns.
fn reduce_turn(x : Fixed) -> Fixed {
  let bits = x.bits
  let pi = Fixed::pi(bits)
  let turn = pi * Fixed::of_int(2, bits)
  let r = x - turn * Fixed::of_int((x / turn).floor_to_int(), bits)
  if r > pi {
    r - turn
  } else if r < -pi {
    r + turn
  } else {
    r
  }
}

///|
/// The sine, by range reduction to `-pi .. pi` and the Taylor series.
pub fn Fixed::sin(self : Fixed) -> Fixed {
  let bits = self.bits
  if self.abs().to_double() > 1.0e6 {
    abort("Fixed::sin: the argument is beyond the range a fixed point reduces")
  }
  let r = reduce_turn(self)
  let squared = r * r
  let mut term = r
  let mut sum = r
  let mut n : Int32 = 0
  while !term.is_zero() {
    n = n + 1
    term = -(term * squared / Fixed::of_int(2 * n * (2 * n + 1), bits))
    sum = sum + term
  }
  sum
}

///|
/// The cosine, by the same reduction and the Taylor series that starts at one.
pub fn Fixed::cos(self : Fixed) -> Fixed {
  let bits = self.bits
  if self.abs().to_double() > 1.0e6 {
    abort("Fixed::cos: the argument is beyond the range a fixed point reduces")
  }
  let r = reduce_turn(self)
  let squared = r * r
  let mut term = Fixed::one(bits)
  let mut sum = Fixed::one(bits)
  let mut n : Int32 = 0
  while !term.is_zero() {
    n = n + 1
    term = -(term * squared / Fixed::of_int((2 * n - 1) * (2 * n), bits))
    sum = sum + term
  }
  sum
}

///|
/// The arctangent, by halving the angle until the series converges and doubling
/// the result back. `atan x = 2 atan (x / (1 + sqrt(1 + x^2)))` holds for every
/// `x`, and each halving quarters the argument, so the Taylor series is reached
/// after a handful of steps from anywhere.
pub fn Fixed::atan(self : Fixed) -> Fixed {
  let bits = self.bits
  let one = Fixed::one(bits)
  let negative = self.mantissa.compare(@bigint.BigInt::from_int(0)) < 0
  let mut x = self.abs()
  let mut halvings : Int32 = 0
  while 0.1 < x.to_double() && halvings < 40 {
    x = x / (one + (one + x * x).sqrt())
    halvings = halvings + 1
  }
  let squared = x * x
  let mut term = x
  let mut sum = x
  let mut n : Int32 = 0
  while !term.is_zero() {
    n = n + 1
    term = -(term * squared)
    sum = sum + term / Fixed::of_int(2 * n + 1, bits)
  }
  let scaled = { mantissa: sum.mantissa << halvings, bits, }
  if negative {
    -scaled
  } else {
    scaled
  }
}

///|
/// The value as a double, to the precision a double holds.
pub fn Fixed::to_double(self : Fixed) -> Double {
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

///|
/// The value in decimal with `places` digits after the point, rounded half away
/// from zero.
pub fn Fixed::to_decimal(self : Fixed, places : Int32) -> String {
  let negative = self.mantissa < 0N
  let magnitude = if negative { -self.mantissa } else { self.mantissa }
  let half = if self.bits > 0 { 1N << (self.bits - 1) } else { 0N }
  let scaled = (magnitude * pow10(places) + half) >> self.bits
  let digits = scaled.to_string()
  let padded = if digits.length() <= places {
    "0".repeat(places + 1 - digits.length()) + digits
  } else {
    digits
  }
  let point = padded.length() - places
  let whole = padded[:point].to_owned()
  let fraction = padded[point:].to_owned()
  let sign = if negative && !scaled.is_zero() { "-" } else { "" }
  if places == 0 {
    sign + whole
  } else {
    sign + whole + "." + fraction
  }
}

///|
/// A decimal literal from outside: an optional sign, digits with an optional point,
/// and an optional exponent. Anything else is refused with where it stopped.
pub fn parse_fixed(text : StringView, bits : Int32) -> Fixed raise Refused {
  let n = text.length()
  let mut i = 0
  let digit = (at : Int32) => at < n && text[at] >= '0' && text[at] <= '9'
  if i < n && (text[i] == '+' || text[i] == '-') {
    i = i + 1
  }
  let start = i
  while digit(i) {
    i = i + 1
  }
  let mut seen = i - start
  if i < n && text[i] == '.' {
    i = i + 1
    let fraction = i
    while digit(i) {
      i = i + 1
    }
    seen = seen + i - fraction
  }
  if seen == 0 {
    raise Malformed(at=i, reason="a number needs a digit")
  }
  if i < n && (text[i] == 'e' || text[i] == 'E') {
    i = i + 1
    if i < n && (text[i] == '+' || text[i] == '-') {
      i = i + 1
    }
    if !digit(i) {
      raise Malformed(at=i, reason="an exponent needs a digit")
    }
    while digit(i) {
      i = i + 1
    }
  }
  if i != n {
    raise Malformed(at=i, reason="this is not part of a number")
  }
  let owned = text.to_owned()
  let literal = if owned.has_prefix("+") { owned[1:].to_owned() } else { owned }
  Fixed::of_decimal(literal, bits)
}

///|
/// The value at the digits its width was asked for, without trailing zeros: the
/// guard bits `bits_for_digits` adds are rounding margin, not digits to print.
pub impl Show for Fixed with fn to_string(self) {
  let digits = if self.bits > 48 { ((self.bits - 48) * 3 + 9) / 10 } else { 0 }
  let text = self.to_decimal(digits)
  if digits == 0 {
    return text
  }
  let mut end = text.length()
  while end > 0 && text[end - 1] == '0' {
    end = end - 1
  }
  if text[end - 1] == '.' {
    text[:end + 1].to_owned()
  } else {
    text[:end].to_owned()
  }
}

///|
pub impl Show for Fixed with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl Eq for Fixed with fn equal(self, other) {
  self.compare(other) == 0
}

///|
/// Compared at the wider of the two widths, so neither side loses a digit first.
pub impl Compare for Fixed with fn compare(self, other) {
  let bits = if self.bits >= other.bits { self.bits } else { other.bits }
  self.at(bits).mantissa.compare(other.at(bits).mantissa)
}

///|
pub impl Add for Fixed with fn add(self, other) {
  { mantissa: self.mantissa + other.at(self.bits).mantissa, bits: self.bits, }
}

///|
pub impl Sub for Fixed with fn sub(self, other) {
  { mantissa: self.mantissa - other.at(self.bits).mantissa, bits: self.bits, }
}

///|
/// Truncated back to the left width.
pub impl Mul for Fixed with fn mul(self, other) {
  {
    mantissa: (self.mantissa * other.at(self.bits).mantissa) >> self.bits,
    bits: self.bits,
  }
}

///|
/// Truncated to the left width. A zero divisor stops the program, as it does for
/// the integers underneath.
pub impl Div for Fixed with fn div(self, other) {
  let divisor = other.at(self.bits).mantissa
  if divisor.is_zero() {
    abort("Fixed::div: division by zero")
  }
  { mantissa: (self.mantissa << self.bits) / divisor, bits: self.bits, }
}

///|
pub impl Neg for Fixed with fn neg(self) {
  { mantissa: -self.mantissa, bits: self.bits, }
}

///|
pub extend Fixed with Show::{to_string, output}

///|
pub extend Fixed with Eq::{equal, not_equal}

///|
pub extend Fixed with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Fixed with Add::{add}

///|
pub extend Fixed with Sub::{sub}

///|
pub extend Fixed with Mul::{mul}

///|
pub extend Fixed with Div::{div}

///|
pub extend Fixed with Neg::{neg}
