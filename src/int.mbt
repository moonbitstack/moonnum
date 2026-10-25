// Integer semantics, on core's `BigInt`. This library adds functions; it does
// not wrap the type.

///|
/// Whether `c` is whitespace as Python's `int()` and `float()` understand it:
/// Unicode whitespace, which is what `str.strip` removes.
fn is_space(c : Char) -> Bool {
  c.is_whitespace()
}

///|
/// The value of `c` as a digit in `base`, or `-1` when it is not one.
fn digit_value(c : Char, base : Int32) -> Int32 {
  let v = if is_digit(c) {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'z' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'Z' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
  if v >= 0 && v < base {
    v
  } else {
    -1
  }
}

///|
/// `int(text, base)`: an integer in any base from 2 to 36, with Python's
/// spelling rules.
///
/// Surrounding whitespace is allowed, the sign is optional, digits may be
/// separated by single underscores, and `base = 0` means "read the prefix":
/// `0x` for hexadecimal, `0o` for octal, `0b` for binary, decimal otherwise —
/// and, as in Python, leading zeros are then not allowed.
pub fn parse_int(
  text : StringView,
  base~ : Int32 = 10,
) -> @bigint.BigInt raise Refused {
  if base != 0 && (base < 2 || base > 36) {
    raise Domain(reason="int() base must be 0, or between 2 and 36")
  }
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
  let mut radix = if base == 0 { 10 } else { base }
  if i + 1 < n && s.get_char(i) == Some('0') {
    let marker = s.get_char(i + 1).unwrap().to_ascii_lowercase()
    let prefixed = match marker {
      'x' => 16
      'o' => 8
      'b' => 2
      _ => 0
    }
    if prefixed != 0 && (base == 0 || base == prefixed) {
      radix = prefixed
      i += 2
    }
  }
  let digits = StringBuilder()
  let mut seen_digit = false
  let mut underscore_ok = false
  while i < n {
    let c = s.get_char(i).unwrap()
    if c == '_' {
      if !underscore_ok {
        malformed(i, "underscore must sit between two digits")
      }
      underscore_ok = false
      i += 1
      continue
    }
    let v = digit_value(c, radix)
    if v < 0 {
      break
    }
    if v != 0 &&
      seen_digit &&
      radix == 10 &&
      base == 0 &&
      digits.to_string().has_prefix("0") {
      // Base 0 reads no leading zeros, as Python refuses "010" but allows "000".
      malformed(i, "leading zeros are not allowed with base 0")
    }
    digits.write_char(c.to_ascii_lowercase())
    seen_digit = true
    underscore_ok = true
    i += 1
  }
  if !seen_digit {
    malformed(i, "expected a digit")
  }
  if !underscore_ok {
    malformed(i - 1, "underscore must sit between two digits")
  }
  while i < n && is_space(s.get_char(i).unwrap()) {
    i += 1
  }
  if i < n {
    malformed(i, "unexpected trailing character")
  }
  let magnitude = @bigint.BigInt::from_string(digits.to_string(), radix~)
  if neg {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// Floor division for any non-zero divisor.
fn floor_div_signed(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let q = a / b
  let r = a % b
  if r != 0N && (r < 0N) != (b < 0N) {
    q - 1N
  } else {
    q
  }
}

///|
/// Floor division when the divisor is already known to be positive.
fn floor_div_raw(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let q = a / b
  if a % b != 0N && a < 0N {
    q - 1N
  } else {
    q
  }
}

///|
/// `a // b`: the quotient rounded towards negative infinity.
pub fn floordiv(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> @bigint.BigInt raise Refused {
  if b == 0N {
    raise ZeroDivision
  }
  let q = a / b
  let r = a % b
  if r != 0N && (r < 0N) != (b < 0N) {
    q - 1N
  } else {
    q
  }
}

///|
/// `a % b`: the remainder that takes the sign of the divisor.
pub fn floor_mod(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> @bigint.BigInt raise Refused {
  if b == 0N {
    raise ZeroDivision
  }
  let r = a % b
  if r != 0N && (r < 0N) != (b < 0N) {
    r + b
  } else {
    r
  }
}

///|
/// `divmod(a, b)`: the floor quotient and the matching remainder.
pub fn divmod(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt) raise Refused {
  if b == 0N {
    raise ZeroDivision
  }
  let q = floordiv(a, b) catch { (err : Refused) => raise err }
  let r = a - q * b
  (q, r)
}

///|
/// The modular inverse of `a` modulo `m`, for `m > 0` and `gcd(a, m) = 1`.
fn inverse_mod(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt? {
  let mut old_r = a
  let mut r = m
  let mut old_s = 1N
  let mut s = 0N
  while r != 0N {
    let q = old_r / r
    let next_r = old_r - q * r
    old_r = r
    r = next_r
    let next_s = old_s - q * s
    old_s = s
    s = next_s
  }
  if old_r != 1N && old_r != -1N {
    return None
  }
  let result = if old_r < 0N { -old_s } else { old_s }
  let normalized = result % m
  Some(if normalized < 0N { normalized + m } else { normalized })
}

///|
/// `pow(base, exp, modulus)`, and `pow(base, exp)` when `modulus` is absent.
///
/// With a modulus and a negative exponent the result is the modular inverse
/// raised to `-exp`, which is Python's behaviour since 3.8. Without a modulus a
/// negative exponent has no integer answer and is refused.
pub fn power(
  base : @bigint.BigInt,
  exp : @bigint.BigInt,
  modulus? : @bigint.BigInt,
) -> @bigint.BigInt raise Refused {
  match modulus {
    None =>
      if exp < 0N {
        raise Domain(reason="negative exponent has no integer result")
      } else {
        base.pow(exp)
      }
    Some(m) => {
      if m == 0N {
        raise Domain(reason="pow() third argument cannot be 0")
      }
      let magnitude = if m < 0N { -m } else { m }
      let start = if exp < 0N {
        match inverse_mod(base, magnitude) {
          Some(inverse) => inverse
          None =>
            raise Domain(reason="base is not invertible for the given modulus")
        }
      } else {
        base
      }
      let exponent = if exp < 0N { -exp } else { exp }
      let result = start.pow(exponent, modulus=magnitude)
      if m < 0N && result != 0N {
        result + m
      } else {
        result
      }
    }
  }
}

///|
/// The greatest common divisor, always non-negative.
pub fn gcd(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let mut x = if a < 0N { -a } else { a }
  let mut y = if b < 0N { -b } else { b }
  while y != 0N {
    let next = x % y
    x = y
    y = next
  }
  x
}

///|
/// The least common multiple, always non-negative; zero when either side is.
pub fn lcm(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  if a == 0N || b == 0N {
    return 0N
  }
  let product = (if a < 0N { -a } else { a }) * (if b < 0N { -b } else { b })
  product / gcd(a, b)
}

///|
/// `math.isqrt(n)`: the floor of the square root.
pub fn isqrt(n : @bigint.BigInt) -> @bigint.BigInt raise Refused {
  if n < 0N {
    raise Domain(reason="isqrt() of a negative number")
  }
  if n < 2N {
    return n
  }
  // Newton's method from above converges in a handful of steps.
  let mut x = 1N << ((n.bit_length() + 1) / 2)
  while true {
    let y = (x + n / x) >> 1
    if y >= x {
      break
    }
    x = y
  }
  x
}

///|
/// `math.factorial(n)`.
pub fn factorial(n : @bigint.BigInt) -> @bigint.BigInt raise Refused {
  if n < 0N {
    raise Domain(reason="factorial() of a negative number")
  }
  let mut result = 1N
  let mut i = 2N
  while i <= n {
    result = result * i
    i += 1N
  }
  result
}

///|
/// `math.comb(n, k)`: the number of ways to choose `k` from `n` without
/// repetition.
pub fn comb(
  n : @bigint.BigInt,
  k : @bigint.BigInt,
) -> @bigint.BigInt raise Refused {
  if n < 0N || k < 0N {
    raise Domain(reason="comb() requires non-negative arguments")
  }
  if k > n {
    return 0N
  }
  let smaller = if k > n - k { n - k } else { k }
  let mut result = 1N
  let mut i = 1N
  while i <= smaller {
    result = result * (n - smaller + i) / i
    i += 1N
  }
  result
}

///|
/// `math.perm(n, k)`: the number of ways to choose `k` from `n` in order.
pub fn perm(
  n : @bigint.BigInt,
  k : @bigint.BigInt,
) -> @bigint.BigInt raise Refused {
  if n < 0N || k < 0N {
    raise Domain(reason="perm() requires non-negative arguments")
  }
  if k > n {
    return 0N
  }
  let mut result = 1N
  let mut i = n - k + 1N
  while i <= n {
    result = result * i
    i += 1N
  }
  result
}

///|
/// The number of bits needed to represent `n`, sign excluded: `int.bit_length`.
pub fn bit_length(n : @bigint.BigInt) -> Int32 {
  n.bit_length()
}

///|
/// `int.to_bytes`: `length` bytes holding `n`, big-endian unless `big~ = false`.
///
/// A signed result is two's complement; an unsigned one refuses negatives.
pub fn to_bytes(
  n : @bigint.BigInt,
  length~ : Int32,
  big~ : Bool = true,
  signed~ : Bool = false,
) -> Bytes raise Refused {
  if length < 0 {
    raise Domain(reason="byte length cannot be negative")
  }
  let width = 8 * length
  if signed {
    let limit = 1N << (width - 1)
    if n < -limit || n >= limit {
      raise Overflow(reason="int does not fit in the requested byte length")
    }
  } else if n < 0N {
    raise Overflow(reason="can't convert negative int to unsigned")
  } else if n >= 1N << width {
    raise Overflow(reason="int does not fit in the requested byte length")
  }
  let encoded = if n < 0N { n + (1N << width) } else { n }
  let mut cursor = encoded
  let out = Array::make(length, b'\x00')
  let mut i = length - 1
  while i >= 0 {
    out[i] = (cursor % 256N).to_int().to_byte()
    cursor = cursor >> 8
    i -= 1
  }
  let bytes = Bytes::from_array(out)
  if big {
    bytes
  } else {
    reverse_bytes(bytes)
  }
}

///|
/// A copy of `bytes` with the order of its bytes reversed.
fn reverse_bytes(bytes : Bytes) -> Bytes {
  let n = bytes.length()
  let out = Array::make(n, b'\x00')
  let mut i = 0
  while i < n {
    out[i] = bytes[i]
    i += 1
  }
  let reversed = Array::make(n, b'\x00')
  let mut j = 0
  while j < n {
    reversed[j] = out[n - 1 - j]
    j += 1
  }
  Bytes::from_array(reversed)
}

///|
/// `int.from_bytes`: the integer held by `bytes`, big-endian unless
/// `big~ = false`, two's complement when `signed~ = true`.
pub fn of_bytes(
  bytes : BytesView,
  big~ : Bool = true,
  signed~ : Bool = false,
) -> @bigint.BigInt {
  let n = bytes.length()
  let mut value = 0N
  let mut i = 0
  while i < n {
    let byte = if big { bytes[i] } else { bytes[n - 1 - i] }
    value = (value << 8) + @bigint.BigInt::from_int(byte.to_int())
    i += 1
  }
  if signed && n > 0 {
    let top = if big { bytes[0] } else { bytes[n - 1] }
    if top.to_int() >= 128 {
      return value - (1N << (8 * n))
    }
  }
  value
}
