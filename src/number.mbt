// The numeric tower: one value that can be any of the four kinds.

///|
/// A number of any kind, as the tower arranges them.
///
/// Promotion goes `Int` → `Fraction` → `Float` → `Complex`. Comparison is
/// exact across the tower: an integer is never rounded to a float to be
/// compared with one.
pub(all) enum Number {
  Int(@bigint.BigInt)
  Float(Double)
  Fraction(Fraction)
  Complex(Complex)
}

///|
/// The value as a complex number.
fn as_complex(n : Number) -> Complex {
  match n {
    Int(v) => { re: big_to_double(v), im: 0.0, }
    Float(f) => { re: f, im: 0.0, }
    Fraction(f) => { re: fraction_to_double_or_inf(f), im: 0.0, }
    Complex(z) => z
  }
}

///|
/// The value as a double, saturating to an infinity when it does not fit.
fn big_to_double(v : @bigint.BigInt) -> Double {
  let neg = v < 0N
  let magnitude = if neg { -v } else { v }
  ratio_to_double(neg, magnitude, 1N)
}

///|
/// The value as a fraction, `None` for a complex number with an imaginary part.
fn as_fraction(n : Number) -> Fraction? {
  match n {
    Int(v) => Some(Fraction::of_int(v))
    Float(f) =>
      if f.is_nan() || f.is_inf() {
        None
      } else {
        let (neg, num, den) = double_ratio(f)
        Some(make(if neg { -num } else { num }, den))
      }
    Fraction(f) => Some(f)
    Complex(_) => None
  }
}

///|
/// A fraction as a double, without raising: used only where the caller has
/// already accepted the saturation.
fn fraction_to_double_or_inf(f : Fraction) -> Double {
  let neg = f.num < 0N
  ratio_to_double(neg, if neg { -f.num } else { f.num }, f.den)
}

///|
/// `parse(text)`: read a Python number literal and keep the kind it spelled.
///
/// A `/` makes a fraction, a trailing `j` or `i` makes a complex number, a
/// point or an exponent or `inf`/`nan` makes a float, and anything else is an
/// integer in whatever base its prefix names.
pub fn parse(text : StringView) -> Number raise Refused {
  let s = text.to_owned()
  let n = s.length()
  let mut start = 0
  while start < n && is_space(s.get_char(start).unwrap()) {
    start += 1
  }
  let mut end = n
  while end > start && is_space(s.get_char(end - 1).unwrap()) {
    end -= 1
  }
  if start == end {
    malformed(start, "expected a number")
  }
  let body = slice(s, start, end)
  let word = lowercase_ascii(body)
  let kind = if word == "inf" ||
    word == "infinity" ||
    word == "nan" ||
    word == "+inf" ||
    word == "-inf" ||
    word == "+infinity" ||
    word == "-infinity" ||
    word == "+nan" ||
    word == "-nan" {
    'f'
  } else if is_prefixed_int(body) {
    // A base prefix settles it: `0x1e` is thirty, not a float in disguise.
    'i'
  } else if ends_with_imaginary(body) || body.get_char(0) == Some('(') {
    // A bracketed literal is complex, as `(1+2j)` is: nothing else is wrapped.
    'c'
  } else if body.contains_char('/') {
    'r'
  } else if body.contains_char('.') || has_exponent(body) {
    'f'
  } else {
    'i'
  }
  match kind {
    'c' =>
      Number::Complex(
        parse_complex(text) catch {
          (err : Refused) => raise err
        },
      )
    'r' =>
      Number::Fraction(
        parse_fraction(text) catch {
          (err : Refused) => raise err
        },
      )
    'f' =>
      Number::Float(parse_float(text) catch { (err : Refused) => raise err })
    _ =>
      Number::Int(
        parse_int(text, base=0) catch {
          (err : Refused) => raise err
        },
      )
  }
}

///|
/// Whether the literal starts with a base prefix, after an optional sign.
fn is_prefixed_int(body : String) -> Bool {
  let mut i = 0
  if body.get_char(0) == Some('+') || body.get_char(0) == Some('-') {
    i = 1
  }
  if i + 1 >= body.length() || body.get_char(i) != Some('0') {
    return false
  }
  match body.get_char(i + 1).unwrap().to_ascii_lowercase() {
    'x' | 'o' | 'b' => true
    _ => false
  }
}

///|
/// Whether the literal ends in `j` or `i`, which makes it a complex number even
/// if it also contains an exponent: `1e5j` is one hundred thousand j.
fn ends_with_imaginary(body : String) -> Bool {
  if body.length() == 0 {
    return false
  }
  match body.get_char(body.length() - 1).unwrap().to_ascii_lowercase() {
    'j' | 'i' => true
    _ => false
  }
}

///|
/// Whether the literal has a decimal exponent, which makes it a float.
fn has_exponent(body : String) -> Bool {
  let mut i = 0
  while i < body.length() {
    match body.get_char(i).unwrap().to_ascii_lowercase() {
      'e' => {
        // `e` needs a digit on either side to be an exponent.
        let before = i > 0 && is_digit(body.get_char(i - 1).unwrap())
        let mut after = i + 1 < body.length() &&
          (
            is_digit(body.get_char(i + 1).unwrap()) ||
            body.get_char(i + 1) == Some('+') ||
            body.get_char(i + 1) == Some('-')
          )
        if after {
          let mut j = i + 1
          if body.get_char(j) == Some('+') || body.get_char(j) == Some('-') {
            j += 1
          }
          after = j < body.length() && is_digit(body.get_char(j).unwrap())
        }
        if before && after {
          return true
        }
      }
      _ => ()
    }
    i += 1
  }
  false
}

///|
/// Promote two numbers to a common kind: 0 for integers, 1 for fractions,
/// 2 for floats, 3 for complex numbers.
fn rank(n : Number) -> Int32 {
  match n {
    Int(_) => 0
    Fraction(_) => 1
    Float(_) => 2
    Complex(_) => 3
  }
}

///|
/// `a + b`.

///|
/// The value as a double, saturating at infinities.
fn number_to_double(n : Number) -> Double {
  match n {
    Int(v) => big_to_double(v)
    Float(f) => f
    Fraction(f) => fraction_to_double_or_inf(f)
    Complex(z) => z.re
  }
}

///|
/// `a - b`.
///
/// Subtraction is not addition of a negation: `-0.0 - 0` is `-0.0`, while
/// `-0.0 + -0.0` is also `-0.0` but `-0.0 + 0.0` is `0.0`.

///|
/// `a * b`.

///|
/// `a / b`, with Python's result kinds: two integers divide to a float, a
/// fraction stays exact, and a complex number is complex.
pub fn Number::divide(self : Number, other : Number) -> Number raise Refused {
  let level = if rank(self) > rank(other) { rank(self) } else { rank(other) }
  match level {
    0 =>
      match (self, other) {
        (Int(a), Int(b)) => {
          if b == 0N {
            raise ZeroDivision
          }
          let neg = (a < 0N) != (b < 0N)
          let an = if a < 0N { -a } else { a }
          let bn = if b < 0N { -b } else { b }
          Number::Float(ratio_to_double(neg, an, bn))
        }
        _ => Number::Int(0N)
      }
    1 =>
      match (as_fraction(self), as_fraction(other)) {
        (Some(a), Some(b)) =>
          Number::Fraction(a.divide(b) catch { (err : Refused) => raise err })
        _ => Number::Int(0N)
      }
    2 => {
      if number_to_double(other) == 0.0 {
        raise ZeroDivision
      }
      Number::Float(number_to_double(self) / number_to_double(other))
    }
    _ =>
      Number::Complex(
        as_complex(self).divide(as_complex(other)) catch {
          (err : Refused) => raise err
        },
      )
  }
}

///|
/// `a // b`.
pub fn Number::floordiv(self : Number, other : Number) -> Number raise Refused {
  match (self, other) {
    (Int(a), Int(b)) =>
      Number::Int(floordiv(a, b) catch { (err : Refused) => raise err })
    (Complex(_), _) | (_, Complex(_)) =>
      raise Domain(reason="complex numbers have no floor division")
    _ => {
      let divisor = number_to_double(other)
      if divisor == 0.0 {
        raise ZeroDivision
      }
      match (as_fraction(self), as_fraction(other)) {
        (Some(a), Some(b)) => Number::Int(a.floor_divide_big(b))
        _ => Number::Float(@math.floor(number_to_double(self) / divisor))
      }
    }
  }
}

///|
/// `a % b`: the remainder that takes the sign of the divisor.
pub fn Number::floor_mod(self : Number, other : Number) -> Number raise Refused {
  match (self, other) {
    (Int(a), Int(b)) =>
      Number::Int(floor_mod(a, b) catch { (err : Refused) => raise err })
    (Complex(_), _) | (_, Complex(_)) =>
      raise Domain(reason="complex numbers have no modulo")
    _ => {
      let divisor = number_to_double(other)
      if divisor == 0.0 {
        raise ZeroDivision
      }
      match (as_fraction(self), as_fraction(other)) {
        (Some(a), Some(b)) => Number::Fraction(a.modulo(b))
        _ => {
          let dividend = number_to_double(self)
          let mut r = dividend % divisor
          if r != 0.0 && (r < 0.0) != (divisor < 0.0) {
            r += divisor
          }
          Number::Float(r)
        }
      }
    }
  }
}

///|
/// `a ** b`.
pub fn Number::pow(self : Number, exponent : Number) -> Number raise Refused {
  match (self, exponent) {
    (Int(base), Int(e)) =>
      if e >= 0N {
        Number::Int(power(base, e) catch { (err : Refused) => raise err })
      } else {
        let den = base.pow(-e)
        if den == 0N {
          raise ZeroDivision
        }
        let neg = den < 0N
        Number::Float(ratio_to_double(neg, if neg { -den } else { den }, 1N))
      }
    (Fraction(base), Int(e)) =>
      Number::Fraction(base.pow(e) catch { (err : Refused) => raise err })
    (Complex(base), _) =>
      Number::Complex(
        base.pow(as_complex(exponent)) catch {
          (err : Refused) => raise err
        },
      )
    (_, Complex(exp)) =>
      Number::Complex(
        as_complex(self).pow(exp) catch {
          (err : Refused) => raise err
        },
      )
    _ =>
      Number::Float(
        @math.pow(number_to_double(self), number_to_double(exponent)),
      )
  }
}

///|
/// `-a`.

///|
/// Compare two real numbers, exactly.
///
/// Raises `Domain` for a NaN operand and for a complex number with a non-zero
/// imaginary part, which Python refuses to order.
pub fn Number::compare_numeric(
  self : Number,
  other : Number,
) -> Int32 raise Refused {
  match (self, other) {
    (Complex(_), _) | (_, Complex(_)) =>
      raise Domain(reason="complex numbers are not ordered")
    (Int(a), Int(b)) => a.compare(b)
    (Float(a), Float(b)) => compare_floats(a, b)
    (Fraction(a), Fraction(b)) => a.compare(b)
    (Int(a), Float(b)) => compare_int_float(a, b)
    (Float(a), Int(b)) => -compare_int_float(b, a)
    (Fraction(a), Float(b)) => compare_fraction_float(a, b)
    (Float(a), Fraction(b)) => -compare_fraction_float(b, a)
    _ => {
      let left = as_exact_real(self)
      let right = as_exact_real(other)
      match (left, right) {
        (Some(a), Some(b)) => a.compare(b)
        _ => raise Domain(reason="these numbers are not ordered")
      }
    }
  }
}

///|
/// A number as an exact fraction, `None` for a complex number that is not real.
fn as_exact_real(n : Number) -> Fraction? {
  match n {
    Complex(z) =>
      if z.im == 0.0 && !z.re.is_nan() {
        as_fraction(Number::Float(z.re))
      } else {
        None
      }
    _ => as_fraction(n)
  }
}

///|
/// Order two doubles, refusing NaN.
fn compare_floats(a : Double, b : Double) -> Int32 raise Refused {
  if a.is_nan() || b.is_nan() {
    raise Domain(reason="NaN is not ordered")
  }
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// Order an integer against a double without rounding the integer.
fn compare_int_float(a : @bigint.BigInt, b : Double) -> Int32 raise Refused {
  if b.is_nan() {
    raise Domain(reason="NaN is not ordered")
  }
  if b.is_inf() {
    return if b > 0.0 { -1 } else { 1 }
  }
  let (neg, num, den) = double_ratio(b)
  let scaled = if neg { -(a * den) } else { a * den }
  scaled.compare(num)
}

///|
/// Order a fraction against a double without rounding either one.
fn compare_fraction_float(a : Fraction, b : Double) -> Int32 raise Refused {
  if b.is_nan() {
    raise Domain(reason="NaN is not ordered")
  }
  if b.is_inf() {
    return if b > 0.0 { -1 } else { 1 }
  }
  let (neg, num, den) = double_ratio(b)
  let other = if neg { -(num * a.den) } else { num * a.den }
  (a.num * den).compare(other)
}

///|
/// `a == b`, across the tower: `1 == 1.0 == Fraction(1) == 1 + 0j`.
pub fn Number::equal_numeric(self : Number, other : Number) -> Bool {
  match (self, other) {
    (Int(a), Int(b)) => a == b
    (Float(a), Float(b)) => a == b
    (Fraction(a), Fraction(b)) => a == b
    (Complex(a), Complex(b)) => a == b
    (Complex(z), _) =>
      z.im == 0.0 && Number::equal_numeric(Number::Float(z.re), other)
    (_, Complex(z)) =>
      z.im == 0.0 && Number::equal_numeric(self, Number::Float(z.re))
    _ =>
      match (as_exact_real(self), as_exact_real(other)) {
        (Some(a), Some(b)) => a == b
        _ => false
      }
  }
}

///|
/// The value as a double, or `Overflow` when it is infinite or not real.
pub fn Number::to_double(self : Number) -> Double raise Refused {
  match self {
    Complex(z) =>
      if z.im != 0.0 {
        raise Domain(
          reason="cannot convert a non-real complex number to a float",
        )
      } else {
        z.re
      }
    _ => {
      let value = number_to_double(self)
      if value.is_inf() {
        raise Overflow(reason="number too large to convert to float")
      }
      value
    }
  }
}

///|
pub impl Show for Number with fn to_string(self) {
  match self {
    Int(v) => v.to_string()
    Float(f) => repr_float(f)
    Fraction(f) => f.to_string()
    Complex(z) => repr_complex(z)
  }
}

///|
pub impl Eq for Number with fn equal(self, other) {
  self.equal_numeric(other)
}

///|
pub fn Number::add(self : Number, other : Number) -> Number {
  self + other
}

///|
pub fn Number::sub(self : Number, other : Number) -> Number {
  self - other
}

///|
pub fn Number::mul(self : Number, other : Number) -> Number {
  self * other
}

///|
pub fn Number::neg(self : Number) -> Number {
  -self
}

///|
/// Addition stays inside the higher of the two kinds, which is what Python's
/// tower does: an integer plus a fraction is a fraction, never a float.
pub impl Add for Number with fn add(self, other) {
  let level = if rank(self) > rank(other) { rank(self) } else { rank(other) }
  match level {
    0 =>
      match (self, other) {
        (Int(a), Int(b)) => Number::Int(a + b)
        _ => Number::Int(0N)
      }
    1 =>
      match (as_fraction(self), as_fraction(other)) {
        (Some(a), Some(b)) => Number::Fraction(a + b)
        _ => Number::Int(0N)
      }
    2 => Number::Float(number_to_double(self) + number_to_double(other))
    _ => Number::Complex(as_complex(self) + as_complex(other))
  }
}

///|
/// Subtraction, spelled out instead of adding a negation: `-0.0 - 0` is
/// `-0.0` and `-0.0 + 0.0` is not.
pub impl Sub for Number with fn sub(self, other) {
  let level = if rank(self) > rank(other) { rank(self) } else { rank(other) }
  match level {
    0 =>
      match (self, other) {
        (Int(a), Int(b)) => Number::Int(a - b)
        _ => Number::Int(0N)
      }
    1 =>
      match (as_fraction(self), as_fraction(other)) {
        (Some(a), Some(b)) => Number::Fraction(a - b)
        _ => Number::Int(0N)
      }
    2 => Number::Float(number_to_double(self) - number_to_double(other))
    _ => Number::Complex(as_complex(self) - as_complex(other))
  }
}

///|
pub impl Mul for Number with fn mul(self, other) {
  let level = if rank(self) > rank(other) { rank(self) } else { rank(other) }
  match level {
    0 =>
      match (self, other) {
        (Int(a), Int(b)) => Number::Int(a * b)
        _ => Number::Int(0N)
      }
    1 =>
      match (as_fraction(self), as_fraction(other)) {
        (Some(a), Some(b)) => Number::Fraction(a * b)
        _ => Number::Int(0N)
      }
    2 => Number::Float(number_to_double(self) * number_to_double(other))
    _ => Number::Complex(as_complex(self) * as_complex(other))
  }
}

///|
pub impl Neg for Number with fn neg(self) {
  match self {
    Int(v) => Number::Int(-v)
    Float(f) => Number::Float(-f)
    Fraction(f) => Number::Fraction(-f)
    Complex(z) => Number::Complex(-z)
  }
}

///|
pub extend Number with Show::{to_string, output}

///|
pub extend Number with Eq::{equal, not_equal}
