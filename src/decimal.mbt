// Exact decimal arithmetic on rationals.
//
// Python prints the digits of the exact binary value, rounded once. Everything
// here exists to do that with integers, so no step of the conversion is itself
// rounded.

///|
/// Ten raised to a non-negative power.
fn pow10(e : Int32) -> @bigint.BigInt {
  if e <= 0 {
    return 1N
  }
  @bigint.BigInt::from_int(10).pow(@bigint.BigInt::from_int(e))
}

///|
/// Compare `num/den` with `10^e`, for `num`, `den` positive.
fn cmp_pow10(num : @bigint.BigInt, den : @bigint.BigInt, e : Int32) -> Int32 {
  if e >= 0 {
    (num - den * pow10(e)).compare(0N)
  } else {
    (num * pow10(-e) - den).compare(0N)
  }
}

///|
/// Compare `num/den` with `2^e`, for `num`, `den` positive.
fn cmp_pow2(num : @bigint.BigInt, den : @bigint.BigInt, e : Int32) -> Int32 {
  if e >= 0 {
    (num - (den << e)).compare(0N)
  } else {
    ((num << -e) - den).compare(0N)
  }
}

///|
/// The unique `e` with `10^e <= num/den < 10^(e+1)`.
fn floor_log10(num : @bigint.BigInt, den : @bigint.BigInt) -> Int32 {
  let bn = num.bit_length()
  let bd = den.bit_length()
  let mut e = ((bn - bd).to_double() * 0.301029995663981_2).to_int()
  while cmp_pow10(num, den, e) < 0 {
    e -= 1
  }
  while cmp_pow10(num, den, e + 1) >= 0 {
    e += 1
  }
  e
}

///|
/// The unique `e` with `2^e <= num/den < 2^(e+1)`.
fn floor_log2(num : @bigint.BigInt, den : @bigint.BigInt) -> Int32 {
  let mut e = num.bit_length() - den.bit_length()
  if cmp_pow2(num, den, e) < 0 {
    e -= 1
  }
  if cmp_pow2(num, den, e + 1) >= 0 {
    e += 1
  }
  e
}

///|
/// `num/den` rounded to an integer, ties to even. Both operands are positive.
fn div_round(num : @bigint.BigInt, den : @bigint.BigInt) -> @bigint.BigInt {
  let q = num / den
  let twice = num % den * 2N
  let order = twice.compare(den)
  if order > 0 || (order == 0 && q % 2N != 0N) {
    q + 1N
  } else {
    q
  }
}

///|
/// `num/den` rounded to an integer, ties to even, for a signed numerator.
fn div_round_signed(
  num : @bigint.BigInt,
  den : @bigint.BigInt,
) -> @bigint.BigInt {
  if num < 0N {
    -div_round(-num, den)
  } else {
    div_round(num, den)
  }
}

///|
/// Round `num/den` to `n` significant decimal digits, ties to even.
///
/// Returns the digits without a point and `decpt`, so that the value is
/// `0.<digits> * 10^decpt`. `digits` always has exactly `n` characters.
fn sig_digits(
  num : @bigint.BigInt,
  den : @bigint.BigInt,
  n : Int32,
) -> (String, Int32) {
  let e = floor_log10(num, den)
  let place = n - 1 - e
  let q = if place >= 0 {
    div_round(num * pow10(place), den)
  } else {
    div_round(num, den * pow10(-place))
  }
  let mut text = q.to_string()
  let mut decpt = e + 1
  if text.length() > n {
    // All nines rounded up; keep n digits and move the point.
    decpt += 1
    text = slice(text, 0, n)
  } else {
    while text.length() < n {
      text = text + "0"
    }
  }
  (text, decpt)
}

///|
/// Round `num/den` to a multiple of `10^place`, ties to even.
///
/// Returns the integer digits and `decpt`, so that the value is
/// `0.<digits> * 10^decpt`.
fn place_digits(
  num : @bigint.BigInt,
  den : @bigint.BigInt,
  place : Int32,
) -> (String, Int32) {
  let q = if place >= 0 {
    div_round(num * pow10(place), den)
  } else {
    div_round(num, den * pow10(-place))
  }
  let text = q.to_string()
  (text, text.length() - place)
}

///|
/// The exact value of a finite double: sign, numerator, denominator.
fn double_ratio(d : Double) -> (Bool, @bigint.BigInt, @bigint.BigInt) {
  let bits = d.reinterpret_as_uint64()
  let neg = bits >> 63 == 1UL
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & 0xF_FFFF_FFFF_FFFFUL
  let (mantissa, exp) = if biased == 0 {
    (frac, -1074)
  } else {
    (frac | 0x10_0000_0000_0000UL, biased - 1075)
  }
  let m = @bigint.BigInt::from_uint64(mantissa)
  if exp >= 0 {
    (neg, m << exp, 1N)
  } else {
    (neg, m, 1N << -exp)
  }
}

///|
/// The double nearest to `num/den`, ties to even.
fn ratio_to_double(
  neg : Bool,
  num : @bigint.BigInt,
  den : @bigint.BigInt,
) -> Double {
  if num == 0N {
    return if neg { -0.0 } else { 0.0 }
  }
  let e = floor_log2(num, den)
  let precision = if e >= -1022 { 53 } else { 53 + (e + 1022) }
  if precision <= 0 {
    return if neg { -0.0 } else { 0.0 }
  }
  let shift = precision - 1 - e
  let q0 = if shift >= 0 {
    div_round(num << shift, den)
  } else {
    div_round(num, den << -shift)
  }
  let mut q = q0
  let mut e2 = e
  if q.bit_length() > precision {
    q = q >> 1
    e2 += 1
  }
  if e2 > 1023 {
    return if neg { -@double.infinity } else { @double.infinity }
  }
  let mantissa = q.to_int64().to_double()
  let scale = if e2 >= -1022 { e2 - 52 } else { -1074 }
  let magnitude = @math.scalbn(mantissa, scale)
  if neg {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// Whether `c` is an ASCII decimal digit.
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// `count` copies of `c`.
fn repeat_char(c : Char, count : Int32) -> String {
  if count <= 0 {
    return ""
  }
  c.to_string().repeat(count)
}

///|
/// `text` split into groups of `size` from the right, joined by `sep`.
fn group_digits(text : String, sep : Char, size : Int32) -> String {
  let n = text.length()
  if n == 0 || size <= 0 {
    return text
  }
  let first = n % size
  let sb = StringBuilder()
  let mut i = 0
  if first > 0 {
    sb.write_string(slice(text, 0, first))
    i = first
  }
  while i < n {
    if i > 0 {
      sb.write_char(sep)
    }
    sb.write_string(slice(text, i, i + size))
    i += size
  }
  sb.to_string()
}

///|
/// `text[start:end]` as an owned string.
fn slice(text : String, start : Int32, end : Int32) -> String {
  text[start:end].to_owned()
}
