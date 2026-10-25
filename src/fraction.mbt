// Exact rationals, kept in lowest terms with a positive denominator.

///|
/// A rational number. `den` is always positive and `gcd(num, den)` is always 1,
/// so `num` and `den` can be read directly.
///
/// Adds, subtracts, multiplies, negates, compares with `==` and an ordering;
/// division is `Fraction::divide` because it can refuse a zero divisor.
pub(all) struct Fraction {
  num : @bigint.BigInt
  den : @bigint.BigInt
}

///|
/// Build from a known non-zero denominator, reducing and fixing the sign.
fn make(num : @bigint.BigInt, den : @bigint.BigInt) -> Fraction {
  let mut n = num
  let mut d = den
  if d < 0N {
    n = -n
    d = -d
  }
  let common = gcd(n, d)
  if common > 1N {
    n = n / common
    d = d / common
  }
  { num: n, den: d, }
}

///|
/// Skip whitespace from `i`, returning where it stopped.
fn skip_spaces(s : String, i : Int32) -> Int32 {
  let mut j = i
  while j < s.length() && is_space(s.get_char(j).unwrap()) {
    j += 1
  }
  j
}

///|
/// `Fraction(num, den)`.
pub fn Fraction::new(
  num : @bigint.BigInt,
  den : @bigint.BigInt,
) -> Fraction raise Refused {
  if den == 0N {
    raise ZeroDivision
  }
  make(num, den)
}

///|
/// The integer `n` as a fraction.
pub fn Fraction::of_int(n : @bigint.BigInt) -> Fraction {
  { num: n, den: 1N, }
}

///|
/// The exact value of a float, as a fraction. `0.1` is not `1/10` here; it is
/// `3602879701896397/36028797018963968`, which is what the double holds.
pub fn Fraction::of_float(d : Double) -> Fraction raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot convert NaN to a fraction")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot convert an infinity to a fraction")
  }
  let (neg, num, den) = double_ratio(d)
  make(if neg { -num } else { num }, den)
}

///|
/// `Fraction(text)`: `"3/4"`, `"-1.25"`, `"1e-3"`, `"7"`.
///
/// Whitespace is allowed around the sign, the slash and the ends; digits may be
/// separated by single underscores. The decimal and exponent forms are read as
/// exact powers of ten, never through a float.
pub fn parse_fraction(text : StringView) -> Fraction raise Refused {
  let s = text.to_owned()
  let n = s.length()
  let mut i = skip_spaces(s, 0)
  let mut neg = false
  if i < n {
    match s.get_char(i).unwrap() {
      '-' => {
        neg = true
        i += 1
      }
      '+' => i += 1
      _ => ()
    }
  }
  let int_digits = StringBuilder()
  let mut digits_count = 0
  let mut underscore_ok = false
  while i < n {
    let c = s.get_char(i).unwrap()
    if is_digit(c) {
      int_digits.write_char(c)
      digits_count += 1
      underscore_ok = true
      i += 1
    } else if c == '_' {
      if !underscore_ok {
        malformed(i, "underscore must sit between two digits")
      }
      underscore_ok = false
      i += 1
    } else {
      break
    }
  }
  let int_text = int_digits.to_string()
  let slash_at = skip_spaces(s, i)
  if slash_at < n && s.get_char(slash_at) == Some('/') {
    if digits_count == 0 {
      malformed(slash_at, "expected a numerator")
    }
    let mut j = skip_spaces(s, slash_at + 1)
    let den_digits = StringBuilder()
    let mut den_count = 0
    let mut den_underscore_ok = false
    while j < n {
      let c = s.get_char(j).unwrap()
      if is_digit(c) {
        den_digits.write_char(c)
        den_count += 1
        den_underscore_ok = true
        j += 1
      } else if c == '_' {
        if !den_underscore_ok {
          malformed(j, "underscore must sit between two digits")
        }
        den_underscore_ok = false
        j += 1
      } else {
        break
      }
    }
    if den_count == 0 {
      malformed(j, "expected a denominator")
    }
    let tail = skip_spaces(s, j)
    if tail < n {
      malformed(tail, "unexpected trailing character")
    }
    let denominator = @bigint.BigInt::from_string(den_digits.to_string())
    if denominator == 0N {
      raise ZeroDivision
    }
    let numerator = @bigint.BigInt::from_string(int_text)
    make(if neg { -numerator } else { numerator }, denominator)
  } else {
    let frac_digits = StringBuilder()
    if i < n && s.get_char(i) == Some('.') {
      i += 1
      let mut point_underscore_ok = false
      while i < n {
        let c = s.get_char(i).unwrap()
        if is_digit(c) {
          frac_digits.write_char(c)
          digits_count += 1
          point_underscore_ok = true
          i += 1
        } else if c == '_' {
          if !point_underscore_ok {
            malformed(i, "underscore must sit between two digits")
          }
          point_underscore_ok = false
          i += 1
        } else {
          break
        }
      }
    }
    if digits_count == 0 {
      malformed(i, "expected a digit")
    }
    let mut exp = 0
    if i < n && (s.get_char(i) == Some('e') || s.get_char(i) == Some('E')) {
      i += 1
      let mut exp_neg = false
      if i < n {
        match s.get_char(i).unwrap() {
          '-' => {
            exp_neg = true
            i += 1
          }
          '+' => i += 1
          _ => ()
        }
      }
      let exp_digits = StringBuilder()
      let mut exp_count = 0
      while i < n && is_digit(s.get_char(i).unwrap()) {
        if exp_count < 6 {
          exp_digits.write_char(s.get_char(i).unwrap())
          exp_count += 1
        }
        i += 1
      }
      if exp_count == 0 {
        malformed(i, "expected an exponent digit")
      }
      let magnitude = parse_exp(exp_digits.to_string())
      exp = if exp_neg { -magnitude } else { magnitude }
    }
    let tail = skip_spaces(s, i)
    if tail < n {
      malformed(tail, "unexpected trailing character")
    }
    let fraction_text = frac_digits.to_string()
    let numerator = @bigint.BigInt::from_string(int_text + fraction_text)
    let signed = if neg { -numerator } else { numerator }
    let scale = exp - fraction_text.length()
    if scale >= 0 {
      make(signed * pow10(scale), 1N)
    } else {
      make(signed, pow10(-scale))
    }
  }
}

///|
/// The numerator, with the sign.
pub fn Fraction::numerator(self : Fraction) -> @bigint.BigInt {
  self.num
}

///|
/// The denominator, always positive.
pub fn Fraction::denominator(self : Fraction) -> @bigint.BigInt {
  self.den
}

///|
/// The same value without its sign.
pub fn Fraction::abs(self : Fraction) -> Fraction {
  if self.num < 0N {
    { num: -self.num, den: self.den, }
  } else {
    self
  }
}

///|
/// `self ** exp` for an integer exponent.
///
/// The exponent is applied to the numerator and the denominator separately, so
/// `(2/3) ** 100` is one exact ratio and not a double that nearly is. A negative
/// exponent reciprocates, which is why `0 ** -1` is `ZeroDivision` and
/// `0 ** 0` is `1`, as in Python.
pub fn Fraction::pow(
  self : Fraction,
  exp : @bigint.BigInt,
) -> Fraction raise Refused {
  let magnitude = if exp < 0N { -exp } else { exp }
  let powered = make(self.num.pow(magnitude), self.den.pow(magnitude))
  if exp < 0N {
    powered.reciprocal()
  } else {
    powered
  }
}

///|
/// `1/self`.
pub fn Fraction::reciprocal(self : Fraction) -> Fraction raise Refused {
  if self.num == 0N {
    raise ZeroDivision
  }
  make(self.den, self.num)
}

///|
/// Whether the value is a whole number.
pub fn Fraction::is_integer(self : Fraction) -> Bool {
  self.den == 1N
}

///|
/// The nearest double, or `Overflow` when the value does not fit.
pub fn Fraction::to_double(self : Fraction) -> Double raise Refused {
  let neg = self.num < 0N
  let magnitude = if neg { -self.num } else { self.num }
  let value = ratio_to_double(neg, magnitude, self.den)
  if value.is_inf() {
    raise Overflow(reason="fraction too large to convert to float")
  }
  value
}

///|
/// `math.floor`, as an integer.
pub fn Fraction::floor_big(self : Fraction) -> @bigint.BigInt {
  floor_div_raw(self.num, self.den)
}

///|
/// `math.ceil`, as an integer.
pub fn Fraction::ceil_big(self : Fraction) -> @bigint.BigInt {
  let floor = self.floor_big()
  if floor * self.den == self.num {
    floor
  } else {
    floor + 1N
  }
}

///|
/// `self // other` as an integer: Python's floor division of two fractions.
pub fn Fraction::floor_divide_big(
  self : Fraction,
  other : Fraction,
) -> @bigint.BigInt raise Refused {
  if other.num == 0N {
    raise ZeroDivision
  }
  floor_div_signed(self.num * other.den, self.den * other.num)
}

///|
/// `self % other`: the remainder that takes the sign of the divisor.
pub fn Fraction::modulo(
  self : Fraction,
  other : Fraction,
) -> Fraction raise Refused {
  if other.num == 0N {
    raise ZeroDivision
  }
  let q = floor_div_signed(self.num * other.den, self.den * other.num)
  make(self.num * other.den - q * other.num * self.den, self.den * other.den)
}

///|
/// `round(self)`: the nearest integer, ties to even.
pub fn Fraction::round_big(self : Fraction) -> @bigint.BigInt {
  let floor = self.floor_big()
  let remainder = self.num - floor * self.den
  let twice = remainder * 2N
  let order = twice.compare(self.den)
  if order > 0 || (order == 0 && floor % 2N != 0N) {
    floor + 1N
  } else {
    floor
  }
}

///|
/// `round(self, ndigits)`: round to `ndigits` decimal places, ties to even.
pub fn Fraction::round(self : Fraction, ndigits~ : Int32) -> Fraction {
  let q = if ndigits >= 0 {
    div_round_signed(self.num * pow10(ndigits), self.den)
  } else {
    div_round_signed(self.num, self.den * pow10(-ndigits))
  }
  if ndigits >= 0 {
    make(q, pow10(ndigits))
  } else {
    make(q * pow10(-ndigits), 1N)
  }
}

///|
/// The closest fraction whose denominator is at most `max`.
pub fn Fraction::limit_denominator(
  self : Fraction,
  max~ : @bigint.BigInt,
) -> Fraction raise Refused {
  if max < 1N {
    raise Domain(reason="max_denominator should be at least 1")
  }
  if self.den <= max {
    return self
  }
  let mut p0 = 0N
  let mut q0 = 1N
  let mut p1 = 1N
  let mut q1 = 0N
  let mut n = self.num
  let mut d = self.den
  while true {
    let a = floor_div_signed(n, d)
    let q2 = q0 + a * q1
    if q2 > max {
      break
    }
    let next_p = p0 + a * p1
    let next_q = q2
    p0 = p1
    q0 = q1
    p1 = next_p
    q1 = next_q
    let next = n - a * d
    n = d
    d = next
    if d == 0N {
      break
    }
  }
  let k = (max - q0) / q1
  if 2N * d * (q0 + k * q1) <= self.den {
    make(p1, q1)
  } else {
    make(p0 + k * p1, q0 + k * q1)
  }
}

///|
/// `repr(Fraction(3, 4))`.
pub fn repr_fraction(f : Fraction) -> String {
  "Fraction(" + f.num.to_string() + ", " + f.den.to_string() + ")"
}

///|
/// `str(Fraction(3, 4))`: `3/4`, and `2` when the denominator is one.
pub impl Show for Fraction with fn to_string(self) {
  if self.den == 1N {
    self.num.to_string()
  } else {
    self.num.to_string() + "/" + self.den.to_string()
  }
}

///|
pub impl Default for Fraction with fn default() {
  { num: 0N, den: 1N, }
}

///|
pub impl Eq for Fraction with fn equal(self, other) {
  self.num == other.num && self.den == other.den
}

///|
pub impl Compare for Fraction with fn compare(self, other) {
  (self.num * other.den).compare(other.num * self.den)
}

///|
pub impl Add for Fraction with fn add(self, other) {
  make(self.num * other.den + other.num * self.den, self.den * other.den)
}

///|
pub impl Sub for Fraction with fn sub(self, other) {
  make(self.num * other.den - other.num * self.den, self.den * other.den)
}

///|
pub impl Mul for Fraction with fn mul(self, other) {
  make(self.num * other.num, self.den * other.den)
}

///|
/// `self / other`.
///
/// Division is a function and not an operator here: MoonBit's `Div` trait
/// cannot raise, and a fraction that silently divides by zero or panics would
/// be worse than one that says `ZeroDivision`.
pub fn Fraction::divide(
  self : Fraction,
  other : Fraction,
) -> Fraction raise Refused {
  if other.num == 0N {
    raise ZeroDivision
  }
  make(self.num * other.den, self.den * other.num)
}

///|
pub impl Neg for Fraction with fn neg(self) {
  { num: -self.num, den: self.den, }
}

///|
pub extend Fraction with Show::{to_string, output}

///|
pub extend Fraction with Default::{default}

///|
pub extend Fraction with Eq::{equal, not_equal}

///|
pub extend Fraction with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Fraction with Add::{add}

///|
pub extend Fraction with Sub::{sub}

///|
pub extend Fraction with Mul::{mul}

///|
pub extend Fraction with Neg::{neg}
