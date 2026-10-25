// Floats: reading them, writing them, and rounding them the way Python does.

///|
/// `float(text)`: Python's float literal syntax.
///
/// Accepts `inf`, `infinity` and `nan` in any case with an optional sign,
/// decimal forms with or without a fractional part or an exponent, single
/// underscores between digits, and surrounding whitespace. Hexadecimal literals
/// are not float syntax; `float_of_hex` reads those.
pub fn parse_float(text : StringView) -> Double raise Refused {
  let s = text.to_owned()
  let n = s.length()
  let mut i = 0
  while i < n && is_space(s.get_char(i).unwrap()) {
    i += 1
  }
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
  let rest = slice(s, i, n)
  let word = lowercase_ascii(rest)
  if word.has_prefix("infinity") && i + 8 <= n {
    let after = i + 8
    if only_space_after(s, after) {
      return if neg { -@double.infinity } else { @double.infinity }
    }
  }
  if word.has_prefix("inf") && i + 3 <= n {
    if only_space_after(s, i + 3) {
      return if neg { -@double.infinity } else { @double.infinity }
    }
  }
  if word.has_prefix("nan") && i + 3 <= n {
    if only_space_after(s, i + 3) {
      return @double.not_a_number
    }
  }
  let int_part = StringBuilder()
  let frac_part = StringBuilder()
  let mut seen_digit = false
  let mut underscore_ok = false
  while i < n {
    match s.get_char(i).unwrap() {
      c =>
        if is_digit(c) {
          int_part.write_char(c)
          seen_digit = true
          underscore_ok = true
        } else if c == '_' {
          if !underscore_ok {
            malformed(i, "underscore must sit between two digits")
          }
          underscore_ok = false
        } else {
          break
        }
    }
    i += 1
  }
  if seen_digit && !underscore_ok {
    malformed(i - 1, "underscore must sit between two digits")
  }
  if i < n && s.get_char(i) == Some('.') {
    i += 1
    underscore_ok = false
    let mut frac_seen = false
    while i < n {
      match s.get_char(i).unwrap() {
        c =>
          if is_digit(c) {
            frac_part.write_char(c)
            seen_digit = true
            frac_seen = true
            underscore_ok = true
          } else if c == '_' {
            if !underscore_ok {
              malformed(i, "underscore must sit between two digits")
            }
            underscore_ok = false
          } else {
            break
          }
      }
      i += 1
    }
    if frac_seen && !underscore_ok {
      malformed(i - 1, "underscore must sit between two digits")
    }
  }
  if !seen_digit {
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
    let mut exp_seen = false
    let mut exp_underscore_ok = false
    while i < n {
      match s.get_char(i).unwrap() {
        c =>
          if is_digit(c) {
            if exp_count < 6 {
              exp_digits.write_char(c)
              exp_count += 1
            }
            exp_seen = true
            exp_underscore_ok = true
          } else if c == '_' {
            if !exp_underscore_ok {
              malformed(i, "underscore must sit between two digits")
            }
            exp_underscore_ok = false
          } else {
            break
          }
      }
      i += 1
    }
    if !exp_seen {
      malformed(i, "expected an exponent digit")
    }
    if !exp_underscore_ok {
      malformed(i - 1, "underscore must sit between two digits")
    }
    let magnitude = parse_exp(exp_digits.to_string())
    exp = if exp_neg { -magnitude } else { magnitude }
  }
  let mut tail = i
  while tail < n && is_space(s.get_char(tail).unwrap()) {
    tail += 1
  }
  if tail < n {
    malformed(tail, "unexpected trailing character")
  }
  let digits = int_part.to_string() + frac_part.to_string()
  let decpt = int_part.to_string().length() + exp
  signed_decimal_to_double(neg, digits, decpt)
}

///|
/// Whether everything from `start` to the end of `s` is whitespace.
fn only_space_after(s : String, start : Int32) -> Bool {
  let mut i = start
  while i < s.length() {
    if !is_space(s.get_char(i).unwrap()) {
      return false
    }
    i += 1
  }
  true
}

///|
/// ASCII-only lowercasing, for keyword recognition.
fn lowercase_ascii(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    sb.write_char(s.get_char(i).unwrap().to_ascii_lowercase())
    i += 1
  }
  sb.to_string()
}

///|
/// `0.<digits> * 10^decpt` as the nearest double.
fn signed_decimal_to_double(
  neg : Bool,
  digits : String,
  decpt : Int32,
) -> Double {
  let mut first = 0
  while first < digits.length() - 1 && digits.get_char(first) == Some('0') {
    first += 1
  }
  let body = strip_zeros(slice(digits, first, digits.length()))
  if body == "0" {
    return if neg { -0.0 } else { 0.0 }
  }
  let point = decpt - first
  if point > 320 {
    return if neg { -@double.infinity } else { @double.infinity }
  }
  if point < -400 {
    return if neg { -0.0 } else { 0.0 }
  }
  let mantissa = @bigint.BigInt::from_string(body)
  let shift = point - body.length()
  if shift >= 0 {
    ratio_to_double(neg, mantissa * pow10(shift), 1N)
  } else {
    ratio_to_double(neg, mantissa, pow10(-shift))
  }
}

///|
/// `repr(float)`: the shortest string that reads back as the same double.
pub fn repr_float(d : Double) -> String {
  float_short(d, 'r', 0, false, true, false, false, false)
}

///|
/// `float.fromhex`: the double a hexadecimal literal denotes.
///
/// The `0x` prefix is optional, the exponent is decimal and introduced by `p`,
/// and the rounding is the same half-to-even as every other conversion here.
pub fn float_of_hex(text : StringView) -> Double raise Refused {
  let s = text.to_owned()
  let n = s.length()
  let mut i = 0
  while i < n && is_space(s.get_char(i).unwrap()) {
    i += 1
  }
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
  let rest = lowercase_ascii(slice(s, i, n))
  if rest.has_prefix("infinity") && only_space_after(s, i + 8) {
    return if neg { -@double.infinity } else { @double.infinity }
  }
  if rest.has_prefix("inf") && only_space_after(s, i + 3) {
    return if neg { -@double.infinity } else { @double.infinity }
  }
  if rest.has_prefix("nan") && only_space_after(s, i + 3) {
    return @double.not_a_number
  }
  if i + 1 < n &&
    s.get_char(i) == Some('0') &&
    (s.get_char(i + 1) == Some('x') || s.get_char(i + 1) == Some('X')) {
    i += 2
  }
  let hex_digits = StringBuilder()
  let mut frac_len = 0
  let mut seen_digit = false
  let mut in_fraction = false
  while i < n {
    let c = s.get_char(i).unwrap()
    if c == '.' && !in_fraction {
      in_fraction = true
      i += 1
      continue
    }
    if c == '_' {
      i += 1
      continue
    }
    let v = if is_digit(c) {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      -1
    }
    if v < 0 {
      break
    }
    hex_digits.write_char(c.to_ascii_lowercase())
    seen_digit = true
    if in_fraction {
      frac_len += 1
    }
    i += 1
  }
  if !seen_digit {
    malformed(i, "expected a hexadecimal digit")
  }
  let mut exp = 0
  if i < n && (s.get_char(i) == Some('p') || s.get_char(i) == Some('P')) {
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
  while i < n && is_space(s.get_char(i).unwrap()) {
    i += 1
  }
  if i < n {
    malformed(i, "unexpected trailing character")
  }
  let mantissa = @bigint.BigInt::from_string(hex_digits.to_string(), radix=16)
  let scale = exp - 4 * frac_len
  if scale > 2000 {
    return if neg { -@double.infinity } else { @double.infinity }
  }
  if scale < -2000 {
    return if neg { -0.0 } else { 0.0 }
  }
  let value = if scale >= 0 {
    ratio_to_double(neg, mantissa << scale, 1N)
  } else {
    ratio_to_double(neg, mantissa, 1N << -scale)
  }
  if value.is_inf() {
    raise Overflow(reason="hexadecimal value too large to represent as a float")
  }
  value
}

///|
/// `round(d, ndigits)`: round to `ndigits` decimal places, ties to even, on the
/// exact value of `d`.
pub fn round_float(d : Double, ndigits~ : Int32) -> Double {
  if d.is_nan() {
    return d
  }
  if d.is_inf() {
    return d
  }
  let (neg, num, den) = double_ratio(d)
  let (scaled, scale) = if ndigits >= 0 {
    (div_round(num * pow10(ndigits), den), pow10(ndigits))
  } else {
    (div_round(num, den * pow10(-ndigits)), 1N)
  }
  let value = if ndigits >= 0 {
    ratio_to_double(neg, scaled, scale)
  } else {
    ratio_to_double(neg, scaled * pow10(-ndigits), 1N)
  }
  value
}

///|
/// `round(d)`: the nearest integer, ties to even.
pub fn round_big(d : Double) -> @bigint.BigInt raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot round NaN to an integer")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot round an infinity to an integer")
  }
  let (neg, num, den) = double_ratio(d)
  let q = div_round(num, den)
  if neg {
    -q
  } else {
    q
  }
}

///|
/// `math.floor(d)`, as an integer.
pub fn floor_big(d : Double) -> @bigint.BigInt raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot floor NaN")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot floor an infinity")
  }
  let (neg, num, den) = double_ratio(d)
  let q = num / den
  if neg && num % den != 0N {
    -q - 1N
  } else if neg {
    -q
  } else {
    q
  }
}

///|
/// `math.ceil(d)`, as an integer.
pub fn ceil_big(d : Double) -> @bigint.BigInt raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot ceil NaN")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot ceil an infinity")
  }
  let (neg, num, den) = double_ratio(d)
  let q = num / den
  if !neg && num % den != 0N {
    q + 1N
  } else if neg {
    -q
  } else {
    q
  }
}

///|
/// `math.trunc(d)`, as an integer.
pub fn trunc_big(d : Double) -> @bigint.BigInt raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot truncate NaN")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot truncate an infinity")
  }
  let (neg, num, den) = double_ratio(d)
  let q = num / den
  if neg {
    -q
  } else {
    q
  }
}

///|
/// `float.as_integer_ratio`: the exact numerator and denominator of `d`.
pub fn as_integer_ratio(
  d : Double,
) -> (@bigint.BigInt, @bigint.BigInt) raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot convert NaN to a ratio")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot convert an infinity to a ratio")
  }
  let (neg, num, den) = double_ratio(d)
  let common = gcd(num, den)
  let numerator = num / common
  if neg {
    (-numerator, den / common)
  } else {
    (numerator, den / common)
  }
}

///|
/// `d` as an exact fraction.
pub fn as_ratio(d : Double) -> Fraction raise Refused {
  if d.is_nan() {
    raise Domain(reason="cannot convert NaN to a fraction")
  }
  if d.is_inf() {
    raise Overflow(reason="cannot convert an infinity to a fraction")
  }
  let (neg, num, den) = double_ratio(d)
  make(if neg { -num } else { num }, den)
}
