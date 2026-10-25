// Turning doubles into text, the way CPython's `format_float_short` does.

///|
/// Decimal digits of a finite double: `0.<digits> * 10^decpt`.
priv struct Dec {
  neg : Bool
  digits : String
  decpt : Int32
}

///|
/// Drop trailing zeros from a digit string, keeping one digit.
fn strip_zeros(text : String) -> String {
  let mut n = text.length()
  while n > 1 && text.get_char(n - 1) == Some('0') {
    n -= 1
  }
  if n == text.length() {
    text
  } else {
    slice(text, 0, n)
  }
}

///|
/// Small signed decimal exponent, as written by `Double::to_string`.
fn parse_exp(text : String) -> Int32 {
  let mut i = 0
  let mut sign = 1
  if text.get_char(0) == Some('-') {
    sign = -1
    i = 1
  } else if text.get_char(0) == Some('+') {
    i = 1
  }
  let mut value = 0
  while i < text.length() {
    match text.get_char(i) {
      Some(c) => value = value * 10 + c.to_int() - '0'.to_int()
      None => break
    }
    i += 1
  }
  sign * value
}

///|
/// The shortest digit string that reads back as `d`, as `(digits, decpt)`.
///
/// The platform already has one: `Double::to_string` is Ryū, which is shortest
/// and correctly rounded. Only the spelling is thrown away here, so that the
/// same digits can be laid out Python's way.
fn ryu_parts(d : Double) -> (String, Int32) {
  let text = d.to_string()
  let start = if text.get_char(0) == Some('-') { 1 } else { 0 }
  let mut i = start
  let mut mantissa_end = text.length()
  let mut exp = 0
  while i < text.length() {
    match text.get_char(i) {
      Some(c) =>
        if c == 'e' || c == 'E' {
          mantissa_end = i
          exp = parse_exp(slice(text, i + 1, text.length()))
          break
        }
      None => break
    }
    i += 1
  }
  let mantissa = slice(text, start, mantissa_end)
  let mut int_len = mantissa.length()
  let mut digits = mantissa
  match mantissa.find(".") {
    Some(dot) => {
      int_len = dot
      digits = slice(mantissa, 0, dot) +
        slice(mantissa, dot + 1, mantissa.length())
    }
    None => ()
  }
  let mut decpt = int_len + exp
  let mut first = 0
  while first < digits.length() - 1 && digits.get_char(first) == Some('0') {
    first += 1
  }
  if first > 0 {
    digits = slice(digits, first, digits.length())
    decpt -= first
  }
  let stripped = strip_zeros(digits)
  if stripped == "0" {
    ("0", 1)
  } else {
    (stripped, decpt)
  }
}

///|
/// `d` as decimal digits, in one of three modes.
///
/// Mode 0 is the shortest round-tripping string, mode 2 has `precision`
/// significant digits with trailing zeros stripped, mode 3 has `precision`
/// digits after the point. Modes 2 and 3 round half to even on the exact value.
fn dtoa(d : Double, mode : Int32, precision : Int32) -> Dec {
  let neg = d.reinterpret_as_uint64() >> 63 == 1UL
  if d == 0.0 {
    return { neg, digits: "0", decpt: 1, }
  }
  let (_, num, den) = double_ratio(d)
  if mode == 0 {
    let (digits, decpt) = ryu_parts(d)
    { neg, digits, decpt, }
  } else if mode == 2 {
    let wanted = if precision < 1 { 1 } else { precision }
    let (digits, decpt) = sig_digits(num, den, wanted)
    { neg, digits: strip_zeros(digits), decpt, }
  } else {
    let (digits, decpt) = place_digits(num, den, precision)
    { neg, digits, decpt, }
  }
}

///|
/// Layout a finite double's digits as text, mirroring CPython's
/// `format_float_short`.
///
/// `code` is `e`, `f`, `g` or `r`. `precision` is the digit count that code
/// wants: significant digits for `e` and `g`, digits after the point for `f`.
fn float_short(
  d : Double,
  code : Char,
  precision : Int32,
  always_sign : Bool,
  add_dot0 : Bool,
  alt : Bool,
  neg0 : Bool,
  upper : Bool,
) -> String {
  if d.is_nan() {
    // CPython drops a NaN's sign but keeps a forced plus.
    let text = if upper { "NAN" } else { "nan" }
    return (if always_sign { "+" } else { "" }) + text
  }
  if d.is_inf() {
    let text = if upper { "INF" } else { "inf" }
    let sign = if d < 0.0 { "-" } else if always_sign { "+" } else { "" }
    return sign + text
  }
  let mode = if code == 'f' { 3 } else if code == 'r' { 0 } else { 2 }
  let dec = dtoa(d, mode, precision)
  let digits = dec.digits
  let mut decpt = dec.decpt
  let mut sign = if dec.neg { "-" } else { "" }
  if neg0 && dec.neg && digits == "0" {
    sign = ""
  }
  if sign == "" && always_sign {
    sign = "+"
  }
  let digits_len = digits.length()
  let mut use_exp = false
  let mut vdigits_end = digits_len
  match code {
    'e' => {
      use_exp = true
      vdigits_end = precision
    }
    'f' => vdigits_end = decpt + precision
    'g' => {
      if decpt <= -4 ||
        decpt > (if add_dot0 { precision - 1 } else { precision }) {
        use_exp = true
      }
      if alt {
        vdigits_end = precision
      }
    }
    _ => if decpt <= -4 || decpt > 16 { use_exp = true }
  }
  let mut exp = 0
  if use_exp {
    exp = decpt - 1
    decpt = 1
  }
  let vdigits_start = if decpt <= 0 { decpt - 1 } else { 0 }
  if !use_exp && add_dot0 {
    if vdigits_end < decpt + 1 {
      vdigits_end = decpt + 1
    }
  } else if vdigits_end < decpt {
    vdigits_end = decpt
  }
  let out = StringBuilder()
  out.write_string(sign)
  let mut p = vdigits_start
  while p < vdigits_end {
    if p == decpt {
      out.write_char('.')
    }
    if p >= 0 && p < digits_len {
      out.write_char(digits.get_char(p).unwrap())
    } else {
      out.write_char('0')
    }
    p += 1
  }
  if vdigits_end == decpt {
    out.write_char('.')
  }
  let mut text = out.to_string()
  if !alt && text.get_char(text.length() - 1) == Some('.') {
    text = slice(text, 0, text.length() - 1)
  }
  if use_exp {
    let e_text = if upper { "E" } else { "e" }
    let sign_text = if exp < 0 { "-" } else { "+" }
    let magnitude = if exp < 0 { -exp } else { exp }
    let pad = if magnitude < 10 { "0" } else { "" }
    text + e_text + sign_text + pad + magnitude.to_string()
  } else {
    text
  }
}

///|
/// Thirteen lowercase hexadecimal digits, zero padded: the mantissa fraction of
/// a double, which `float.hex` always writes out in full.
fn hex13(frac : UInt64) -> String {
  let alphabet = "0123456789abcdef"
  let sb = StringBuilder()
  let mut i = 12
  while i >= 0 {
    let nibble = ((frac >> (i * 4)) & 0xFUL).to_int()
    sb.write_char(alphabet.get_char(nibble).unwrap())
    i -= 1
  }
  sb.to_string()
}

///|
/// The hexadecimal form of a double: `float.hex`.
pub fn float_hex(d : Double) -> String {
  if d.is_nan() {
    return "nan"
  }
  if d.is_inf() {
    return if d < 0.0 { "-inf" } else { "inf" }
  }
  let bits = d.reinterpret_as_uint64()
  let sign = if bits >> 63 == 1UL { "-" } else { "" }
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & 0xF_FFFF_FFFF_FFFFUL
  if d == 0.0 {
    return sign + "0x0.0p+0"
  }
  let lead = if biased == 0 { "0x0." } else { "0x1." }
  let exp = if biased == 0 { -1022 } else { biased - 1023 }
  let sign_text = if exp < 0 { "-" } else { "+" }
  let magnitude = if exp < 0 { -exp } else { exp }
  sign + lead + hex13(frac) + "p" + sign_text + magnitude.to_string()
}
