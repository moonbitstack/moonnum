// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Reading a decimal and writing one back.
//
// The digits a value prints are rounded once, on the exact binary value, so a
// double's `0.1` still prints as `0.1`, and `0.1` at a thousand bits prints the
// thousand digits that are really there.

///|
/// The largest decimal exponent a literal may carry.
///
/// The exponent of a `BigFloat` is an `Int32`, so a decimal exponent past a
/// hundred thousand is a number this type could hold but not arrive at: the
/// ten-to-that-power the reading needs would be an integer of a hundred thousand
/// digits. Refusing says so; answering zero or an infinity would be a number the
/// caller did not write.
const MAX_DECIMAL_POWER : Int32 = 100000

///|
/// How many significant decimal digits a binary width can speak for.
fn decimal_digits(precision : Int32) -> Int32 {
  let count = precision * 30103 / 100000
  if count < 1 {
    1
  } else {
    count
  }
}

///|
/// The exact value of a number as a positive numerator over a denominator.
fn ratio_of(value : BigFloat) -> (Bool, @bigint.BigInt, @bigint.BigInt) {
  let negative = value.mantissa < 0N
  let top = magnitude(value.mantissa)
  if value.exponent >= 0 {
    (negative, top << value.exponent, 1N)
  } else {
    (negative, top, 1N << (0 - value.exponent))
  }
}

///|
/// `digits` with the point `decpt` characters in, so that the value is
/// `0.<digits> * 10^decpt`.
///
/// The exponent takes over where the plain form would spend more characters on
/// zeros than on the number, at the same places a double's `repr` switches: below
/// `1e-4` and from `1e16` up.
fn placed(negative : Bool, digits : String, decpt : Int32) -> String {
  let sign = if negative { "-" } else { "" }
  let count = digits.length()
  if decpt <= -4 || decpt > 16 {
    let head = digits[:1].to_owned()
    let tail = if count > 1 { "." + digits[1:].to_owned() } else { "" }
    let power = decpt - 1
    let marker = if power < 0 {
      "-" +
      repeat_char('0', if power > -10 { 1 } else { 0 }) +
      (0 - power).to_string()
    } else {
      "+" + repeat_char('0', if power < 10 { 1 } else { 0 }) + power.to_string()
    }
    return sign + head + tail + "e" + marker
  }
  if decpt <= 0 {
    return sign + "0." + repeat_char('0', 0 - decpt) + digits
  }
  if decpt >= count {
    return sign + digits + repeat_char('0', decpt - count) + ".0"
  }
  sign + digits[:decpt].to_owned() + "." + digits[decpt:].to_owned()
}

///|
/// The fewest significant digits that read back as this value, and where the
/// point sits.
///
/// A width of `p` bits is told apart from its neighbours by about `p * 0.301`
/// digits, and a value in the middle of its neighbours needs fewer; printing all
/// of them would show the digits a rounding left behind rather than the number
/// the caller wrote. The count is found by halving the range and reading each
/// candidate back, so the search costs eight parses and not three hundred.
fn shortest_of(value : BigFloat) -> (String, Int32) {
  let (negative, top, bottom) = ratio_of(value)
  let most = decimal_digits(value.precision) + 3
  let reads_back = (count : Int32) => {
    let (text, decpt) = sig_digits(top, bottom, count)
    let written = placed(negative, strip_zeros(text), decpt)
    let back = BigFloat::parse(written, context=Context::new(value.precision)) catch {
      _ => return false
    }
    back == value
  }
  let mut low = 1
  let mut high = most
  while low < high {
    let mid = (low + high) / 2
    if reads_back(mid) {
      high = mid
    } else {
      low = mid + 1
    }
  }
  sig_digits(top, bottom, low)
}

///|
/// This is the spelling for a table or a printed constant, so the count is a
/// promise rather than a maximum: `to_decimal(2)` of one half is `0.50`.
pub fn BigFloat::to_decimal(self : BigFloat, places : Int32) -> String {
  match self.kind {
    NotANumber => return "nan"
    PositiveInfinity => return "inf"
    NegativeInfinity => return "-inf"
    Finite => ()
  }
  let places = if places < 0 { 0 } else { places }
  let (negative, top, bottom) = ratio_of(self)
  let (digits, decpt) = place_digits(top, bottom, places)
  let body = if places == 0 {
    if decpt <= 0 {
      "0"
    } else if decpt >= digits.length() {
      digits + repeat_char('0', decpt - digits.length())
    } else {
      digits[:decpt].to_owned()
    }
  } else if decpt <= 0 {
    "0." + repeat_char('0', 0 - decpt) + digits
  } else if decpt >= digits.length() {
    digits + "." + repeat_char('0', decpt - digits.length())
  } else {
    digits[:decpt].to_owned() + "." + digits[decpt:].to_owned()
  }
  let zero = digits.trim_start(chars="0") == ""
  if negative && !zero {
    "-" + body
  } else {
    body
  }
}

///|
/// The value with `digits` significant decimal digits, trailing zeros dropped
/// and the point placed where the plain form keeps it.
pub fn BigFloat::to_significant(self : BigFloat, digits : Int32) -> String {
  match self.kind {
    NotANumber => return "nan"
    PositiveInfinity => return "inf"
    NegativeInfinity => return "-inf"
    Finite => ()
  }
  if self.mantissa.is_zero() {
    return "0.0"
  }
  let (negative, top, bottom) = ratio_of(self)
  let wanted = if digits < 1 { 1 } else { digits }
  let (text, decpt) = sig_digits(top, bottom, wanted)
  placed(negative, strip_zeros(text), decpt)
}

///|
pub impl Show for BigFloat with fn to_string(self) {
  match self.kind {
    NotANumber => "nan"
    PositiveInfinity => "inf"
    NegativeInfinity => "-inf"
    Finite =>
      if self.mantissa.is_zero() {
        "0.0"
      } else {
        let (negative, _, _) = ratio_of(self)
        let (text, decpt) = shortest_of(self)
        placed(negative, strip_zeros(text), decpt)
      }
  }
}

///|
pub impl Show for BigFloat with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Whether `text` at `at` starts with `word`.
fn has_word(text : String, at : Int32, word : String) -> Bool {
  if at < 0 || at + word.length() > text.length() {
    return false
  }
  text[at:at + word.length()] == word
}

///|
/// Whether `c` is one of the six characters Python's `float` strips.
fn is_blank(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\n' ||
  c == '\r' ||
  c == '\u{b}' ||
  c == '\u{c}'
}

///|
/// The first index from `start` that is not a blank.
fn after_blanks(text : String, start : Int32) -> Int32 {
  let n = text.length()
  let mut i = start
  while i < n && is_blank(text.get_char(i).unwrap()) {
    i = i + 1
  }
  i
}

///|
/// A decimal from outside, rounded once at the end to `context`'s width and
/// direction.
///
/// Reads what `float()` reads: an optional sign, digits with an optional point
/// and exponent, a single underscore between digits, surrounding whitespace, and
/// `inf`, `infinity` and `nan` in any case. A decimal exponent past a hundred
/// thousand is refused rather than answered with a zero or an infinity that was
/// not written.
pub fn BigFloat::parse(
  text : StringView,
  context? : Context,
) -> BigFloat raise Refused {
  let c = context_of(context, context_default)
  let s = text.to_owned()
  let n = s.length()
  let mut i = after_blanks(s, 0)
  let mut negative = false
  if i < n && (s.get_char(i).unwrap() == '+' || s.get_char(i).unwrap() == '-') {
    negative = s.get_char(i).unwrap() == '-'
    i = i + 1
  }
  let word = lowercase_ascii(s[i:].to_owned())
  let end = if has_word(word, 0, "infinity") {
    i + 8
  } else if has_word(word, 0, "inf") {
    i + 3
  } else if has_word(word, 0, "nan") {
    let stop = after_blanks(s, i + 3)
    if stop != n {
      raise Malformed(at=stop, reason="this is not part of a number")
    }
    return nan_at(c.precision)
  } else {
    return parse_digits(s, i, negative, c)
  }
  let stop = after_blanks(s, end)
  if stop != n {
    raise Malformed(at=stop, reason="this is not part of a number")
  }
  infinity_at(negative, c.precision)
}

///|
/// The digits, point and exponent of a decimal, from `start`.
fn parse_digits(
  text : String,
  start : Int32,
  negative : Bool,
  c : Context,
) -> BigFloat raise Refused {
  let n = text.length()
  let mut i = start
  let digit = (at : Int32) => {
    at < n &&
    text.get_char(at).unwrap() >= '0' &&
    text.get_char(at).unwrap() <= '9'
  }
  let digits = StringBuilder()
  let mut seen = 0
  let mut after = 0
  while i < n &&
        (
          digit(i) ||
          (text.get_char(i) == Some('_') && seen > 0 && digit(i + 1))
        ) {
    if text.get_char(i) == Some('_') {
      i = i + 1
    } else {
      digits.write_char(text.get_char(i).unwrap())
      seen = seen + 1
      i = i + 1
    }
  }
  if i < n && text.get_char(i) == Some('.') {
    i = i + 1
    while i < n &&
          (
            digit(i) ||
            (text.get_char(i) == Some('_') && seen > 0 && digit(i + 1))
          ) {
      if text.get_char(i) == Some('_') {
        i = i + 1
      } else {
        digits.write_char(text.get_char(i).unwrap())
        seen = seen + 1
        after = after + 1
        i = i + 1
      }
    }
  }
  if seen == 0 {
    raise Malformed(at=i, reason="a number needs a digit")
  }
  let mut power = 0
  if i < n && (text.get_char(i) == Some('e') || text.get_char(i) == Some('E')) {
    i = i + 1
    let mut power_negative = false
    if i < n && (text.get_char(i) == Some('+') || text.get_char(i) == Some('-')) {
      power_negative = text.get_char(i) == Some('-')
      i = i + 1
    }
    if !digit(i) {
      raise Malformed(at=i, reason="an exponent needs a digit")
    }
    while digit(i) {
      if power < MAX_DECIMAL_POWER + 1 {
        power = power * 10 + (text.get_char(i).unwrap().to_int() - 48)
      }
      i = i + 1
    }
    if power_negative {
      power = 0 - power
    }
  }
  i = after_blanks(text, i)
  if i != n {
    raise Malformed(at=i, reason="this is not part of a number")
  }
  let scale = power - after
  if scale > MAX_DECIMAL_POWER || scale < 0 - MAX_DECIMAL_POWER {
    raise Overflow(
      reason="the decimal exponent is past what this width carries",
    )
  }
  let whole = @bigint.BigInt::from_string(digits.to_string())
  let value = if scale >= 0 {
    rounded_at(whole * pow10(scale), 0, c.precision, c.rounding, false)
  } else {
    ratio_at(whole, pow10(0 - scale), 0, c.precision, c.rounding)
  }
  if negative {
    neg_special(value)
  } else {
    value
  }
}
