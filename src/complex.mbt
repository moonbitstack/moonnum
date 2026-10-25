// Complex numbers, with CPython's handling of infinities and signed zeros.

///|
/// A complex number: `z.re + z.im * j`.
pub(all) struct Complex {
  re : Double
  im : Double
}

///|
/// `Complex(re, im)`.
pub fn Complex::new(re : Double, im : Double) -> Complex {
  { re, im, }
}

///|
/// The imaginary unit.
pub fn Complex::j() -> Complex {
  { re: 0.0, im: 1.0, }
}

///|
/// `-1.0` when `x` has its sign bit set, `1.0` otherwise: `copysign(1, x)`
/// without the call.
fn sign_of(x : Double) -> Double {
  if x.reinterpret_as_uint64() >> 63 == 1UL {
    -1.0
  } else {
    1.0
  }
}

///|
/// Box an infinity to `±1`, and a NaN to a signed zero, the way C11's Annex G
/// recovery step does.
fn box(x : Double) -> Double {
  if x.is_inf() {
    sign_of(x)
  } else if x.is_nan() {
    sign_of(x) * 0.0
  } else {
    x
  }
}

///|
/// `z * w`, recovering infinities that would otherwise come out as `nan+nanj`.
fn mul_complex(z : Complex, w : Complex) -> Complex {
  let a = z.re
  let b = z.im
  let mut c = w.re
  let mut d = w.im
  let ac = a * c
  let bd = b * d
  let ad = a * d
  let bc = b * c
  let mut re = ac - bd
  let mut im = ad + bc
  if re.is_nan() && im.is_nan() {
    let mut recalc = false
    let mut a2 = a
    let mut b2 = b
    if a.is_inf() || b.is_inf() {
      a2 = box(a)
      b2 = box(b)
      c = box(c)
      d = box(d)
      recalc = true
    }
    if c.is_inf() || d.is_inf() {
      c = box(c)
      d = box(d)
      a2 = box(a2)
      b2 = box(b2)
      recalc = true
    }
    if !recalc && (ac.is_inf() || bd.is_inf() || ad.is_inf() || bc.is_inf()) {
      a2 = box(a2)
      b2 = box(b2)
      c = box(c)
      d = box(d)
      recalc = true
    }
    if recalc {
      re = @double.infinity * (a2 * c - b2 * d)
      im = @double.infinity * (a2 * d + b2 * c)
    }
  }
  { re, im, }
}

///|
/// `z / w`, by Smith's algorithm, with the same recovery as `mul_complex`.
fn divide_complex(z : Complex, w : Complex) -> Complex raise Refused {
  if w.re == 0.0 && w.im == 0.0 {
    raise ZeroDivision
  }
  let a = z.re
  let b = z.im
  let c = w.re
  let d = w.im
  let abs_c = c.abs()
  let abs_d = d.abs()
  let mut re = 0.0
  let mut im = 0.0
  if abs_c >= abs_d {
    let ratio = d / c
    let denom = c + d * ratio
    re = (a + b * ratio) / denom
    im = (b - a * ratio) / denom
  } else {
    let ratio = c / d
    let denom = c * ratio + d
    re = (a * ratio + b) / denom
    im = (b * ratio - a) / denom
  }
  if re.is_nan() && im.is_nan() {
    if (a.is_inf() || b.is_inf()) && is_finite_num(c) && is_finite_num(d) {
      let x = box(a)
      let y = box(b)
      re = @double.infinity * (x * c + y * d)
      im = @double.infinity * (y * c - x * d)
    } else if (abs_c.is_inf() || abs_d.is_inf()) &&
      is_finite_num(a) &&
      is_finite_num(b) {
      let x = box(c)
      let y = box(d)
      re = 0.0 * (a * x + b * y)
      im = 0.0 * (a * y - b * x)
    }
  }
  { re, im, }
}

///|
/// Whether a double is neither infinite nor NaN.
fn is_finite_num(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
/// `abs(z)`: the Euclidean norm, infinity when either part is infinite.
pub fn Complex::abs(self : Complex) -> Double {
  if !is_finite_num(self.re) || !is_finite_num(self.im) {
    if self.re.is_inf() {
      return self.re.abs()
    }
    if self.im.is_inf() {
      return self.im.abs()
    }
    return @double.not_a_number
  }
  @math.hypot(self.re, self.im)
}

///|
/// `z.conjugate()`.
pub fn Complex::conjugate(self : Complex) -> Complex {
  { re: self.re, im: -self.im, }
}

///|
/// `x` raised to a non-negative integer power by repeated squaring, which is
/// exact where the polar form is not.
fn pow_unsigned(x : Complex, n : Int32) -> Complex {
  let mut result = { re: 1.0, im: 0.0, }
  let mut base = x
  let mut mask = 1
  while mask <= n {
    if n.land(mask) != 0 {
      result = mul_complex(result, base)
    }
    base = mul_complex(base, base)
    mask = mask << 1
  }
  result
}

///|
/// `x ** n` for a small integer `n`, negative allowed.
fn pow_int(x : Complex, n : Int32) -> Complex raise Refused {
  if n > 0 {
    pow_unsigned(x, n)
  } else {
    divide_complex({ re: 1.0, im: 0.0, }, pow_unsigned(x, -n))
  }
}

///|
/// `z ** w`, including Python's special cases.
///
/// An exponent that is a small integer is applied by repeated squaring, as
/// CPython does; anything else goes through the polar form, which is why
/// `(1+1j) ** 2` is exactly `2j` and `(1+1j) ** 2.0` is not.
pub fn Complex::pow(self : Complex, w : Complex) -> Complex raise Refused {
  if w.im == 0.0 && w.re == @double.floor(w.re) && w.re.abs() <= 100.0 {
    return pow_int(self, w.re.to_int())
  }
  if w.re == 0.0 && w.im == 0.0 {
    return { re: 1.0, im: 0.0, }
  }
  if self.re == 0.0 && self.im == 0.0 {
    if w.im != 0.0 || w.re < 0.0 {
      raise ZeroDivision
    }
    return { re: 0.0, im: 0.0, }
  }
  let magnitude = @math.hypot(self.re, self.im)
  let mut length = @math.pow(magnitude, w.re)
  let angle = @math.atan2(self.im, self.re)
  let mut phase = angle * w.re
  if w.im != 0.0 {
    length *= @math.exp(-angle * w.im)
    phase += w.im * @math.ln(magnitude)
  }
  { re: length * @math.cos(phase), im: length * @math.sin(phase), }
}

///|
/// `repr(z)`: `(1+2j)`, `2j`, `(-0-1j)`, `(nan+infj)`.
pub fn repr_complex(z : Complex) -> String {
  if z.re == 0.0 && sign_of(z.re) > 0.0 {
    return repr_bare(z.im) + "j"
  }
  "(" +
  repr_bare(z.re) +
  float_short(z.im, 'r', 0, true, false, false, false, false) +
  "j)"
}

///|
/// `repr` without the trailing `.0` that a bare float gets: complex parts print
/// as `1` and not `1.0`, which is what CPython's `complex_repr` does.
fn repr_bare(d : Double) -> String {
  float_short(d, 'r', 0, false, false, false, false, false)
}

///|
/// Read the float prefix of `s` starting at `i`, returning the value and the
/// index just past it, or `None` when nothing was consumed.
fn scan_float_prefix(s : String, i : Int32) -> (Double, Int32)? {
  let n = s.length()
  let mut j = i
  let mut seen = false
  if j < n {
    match s.get_char(j).unwrap() {
      '-' => j += 1
      '+' => j += 1
      _ => ()
    }
  }
  // inf / infinity / nan
  let word = lowercase_ascii(slice(s, j, n))
  if word.has_prefix("infinity") {
    return Some(
      (
        if s.get_char(i) == Some('-') {
          -@double.infinity
        } else {
          @double.infinity
        },
        j + 8,
      ),
    )
  }
  if word.has_prefix("inf") {
    return Some(
      (
        if s.get_char(i) == Some('-') {
          -@double.infinity
        } else {
          @double.infinity
        },
        j + 3,
      ),
    )
  }
  if word.has_prefix("nan") {
    return Some((@double.not_a_number, j + 3))
  }
  while j < n {
    let c = s.get_char(j).unwrap()
    if is_digit(c) || c == '_' {
      if is_digit(c) {
        seen = true
      }
      j += 1
    } else {
      break
    }
  }
  let mut has_point = false
  if j < n && s.get_char(j) == Some('.') {
    has_point = true
    j += 1
    while j < n {
      let c = s.get_char(j).unwrap()
      if is_digit(c) || c == '_' {
        if is_digit(c) {
          seen = true
        }
        j += 1
      } else {
        break
      }
    }
  }
  let _ = has_point
  if !seen {
    return None
  }
  if j < n && (s.get_char(j) == Some('e') || s.get_char(j) == Some('E')) {
    let mut k = j + 1
    if k < n {
      match s.get_char(k).unwrap() {
        '-' => k += 1
        '+' => k += 1
        _ => ()
      }
    }
    let mut exp_digits = false
    while k < n && is_digit(s.get_char(k).unwrap()) {
      exp_digits = true
      k += 1
    }
    if exp_digits {
      j = k
    }
  }
  match try_parse_float(slice(s, i, j)) {
    Some(value) => Some((value, j))
    None => None
  }
}

///|
/// `parse_float` as an option, for the scanners that need to look ahead.
fn try_parse_float(text : String) -> Double? {
  Some(parse_float(text)) catch {
    _ => None
  }
}

///|
/// `complex(text)`: `1+2j`, `(1+2j)`, `j`, `-j`, `1e3j`, and `3+5i`.
///
/// The `i` suffix is this library's addition; Python only reads `j`.
pub fn parse_complex(text : StringView) -> Complex raise Refused {
  let s = text.to_owned()
  let n = s.length()
  let mut i = 0
  while i < n && is_space(s.get_char(i).unwrap()) {
    i += 1
  }
  let mut bracketed = false
  if i < n && s.get_char(i) == Some('(') {
    bracketed = true
    i += 1
    while i < n && is_space(s.get_char(i).unwrap()) {
      i += 1
    }
  }
  let mut re = 0.0
  let mut im = 0.0
  match scan_float_prefix(s, i) {
    Some((value, next)) => {
      i = next
      if i < n && (s.get_char(i) == Some('+') || s.get_char(i) == Some('-')) {
        // <float><signed-float>j, or <float><sign>j
        match scan_float_prefix(s, i) {
          Some((second, next2)) => {
            re = value
            im = second
            i = next2
          }
          None => {
            re = 0.0
            im = if s.get_char(i) == Some('-') { -value } else { value }
            i += 1
          }
        }
        if !(i < n &&
          (
            s.get_char(i) == Some('j') ||
            s.get_char(i) == Some('J') ||
            s.get_char(i) == Some('i') ||
            s.get_char(i) == Some('I')
          )) {
          malformed(i, "expected j after the imaginary part")
        }
        i += 1
      } else if i < n &&
        (
          s.get_char(i) == Some('j') ||
          s.get_char(i) == Some('J') ||
          s.get_char(i) == Some('i') ||
          s.get_char(i) == Some('I')
        ) {
        im = value
        i += 1
      } else {
        re = value
      }
    }
    None => {
      // <sign>j or j
      if i < n && (s.get_char(i) == Some('+') || s.get_char(i) == Some('-')) {
        im = if s.get_char(i) == Some('-') { -1.0 } else { 1.0 }
        i += 1
      } else {
        im = 1.0
      }
      if !(i < n &&
        (
          s.get_char(i) == Some('j') ||
          s.get_char(i) == Some('J') ||
          s.get_char(i) == Some('i') ||
          s.get_char(i) == Some('I')
        )) {
        malformed(i, "expected j")
      }
      i += 1
    }
  }
  while i < n && is_space(s.get_char(i).unwrap()) {
    i += 1
  }
  if bracketed {
    if !(i < n && s.get_char(i) == Some(')')) {
      malformed(i, "expected ')'")
    }
    i += 1
    while i < n && is_space(s.get_char(i).unwrap()) {
      i += 1
    }
  }
  if i < n {
    malformed(i, "unexpected trailing character")
  }
  { re, im, }
}

///|
impl Show for Complex with fn to_string(self) {
  repr_complex(self)
}

///|
pub extend Complex with Show::{to_string}

///|
pub extend Complex with Default::{default}

///|
pub extend Complex with Eq::{equal, not_equal}

///|
pub extend Complex with Add::{add}

///|
pub extend Complex with Sub::{sub}

///|
pub extend Complex with Mul::{mul}

///|
pub extend Complex with Neg::{neg}

///|
impl Default for Complex with fn default() {
  { re: 0.0, im: 0.0, }
}

///|
impl Eq for Complex with fn equal(self, other) {
  self.re == other.re && self.im == other.im
}

///|
impl Add for Complex with fn add(self, other) {
  { re: self.re + other.re, im: self.im + other.im, }
}

///|
impl Sub for Complex with fn sub(self, other) {
  { re: self.re - other.re, im: self.im - other.im, }
}

///|
impl Mul for Complex with fn mul(self, other) {
  mul_complex(self, other)
}

///|
impl Neg for Complex with fn neg(self) {
  { re: -self.re, im: -self.im, }
}

///|
/// `self / other`.
///
/// A function rather than an operator, for the same reason as
/// `Fraction::divide`: division by zero has to be reported, and `Div` cannot.
pub fn Complex::divide(
  self : Complex,
  other : Complex,
) -> Complex raise Refused {
  divide_complex(self, other)
}
