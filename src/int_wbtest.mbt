// Integers: the assertions behind the generated vectors.

///|
fn check_parse_int(rows : Array[(String, Int32, String)]) -> Unit raise {
  for row in rows {
    let (text, base, want) = row
    let got = attempt(() => parse_int(text, base~).to_string())
    check("parse_int(\{text}, base=\{base})", got, want)
  }
}

///|
fn check_int_div(rows : Array[(String, String, String, String)]) -> Unit raise {
  for row in rows {
    let (a, b, want_q, want_r) = row
    let left = bigint_of(a)
    let right = bigint_of(b)
    check(
      "floordiv(\{a}, \{b})",
      attempt(() => floordiv(left, right).to_string()),
      want_q,
    )
    check(
      "floor_mod(\{a}, \{b})",
      attempt(() => floor_mod(left, right).to_string()),
      want_r,
    )
  }
}

///|
fn check_pow(rows : Array[(String, String, String, String)]) -> Unit raise {
  for row in rows {
    let (base, exp, modulus, want) = row
    let b = bigint_of(base)
    let e = bigint_of(exp)
    let got = if modulus == "" {
      attempt(() => power(b, e).to_string())
    } else {
      let m = bigint_of(modulus)
      attempt(() => power(b, e, modulus=m).to_string())
    }
    check("pow(\{base}, \{exp}, \{modulus})", got, want)
  }
}

///|
fn check_int_math(rows : Array[(String, String, String, String)]) -> Unit raise {
  for row in rows {
    let (name, a, b, want) = row
    let x = bigint_of(a)
    let y = bigint_of(b)
    let got = match name {
      "gcd" => gcd(x, y).to_string()
      "lcm" => lcm(x, y).to_string()
      "isqrt" => attempt(() => isqrt(x).to_string())
      "factorial" => attempt(() => factorial(x).to_string())
      "comb" => attempt(() => comb(x, y).to_string())
      _ => attempt(() => perm(x, y).to_string())
    }
    check("\{name}(\{a}, \{b})", got, want)
  }
}

///|
fn check_bytes(rows : Array[(String, Int32, Bool, Bool, String)]) -> Unit raise {
  for row in rows {
    let (text, length, big, signed, want) = row
    let value = bigint_of(text)
    let got = attempt(() => {
      hex_of_bytes(to_bytes(value, length~, big~, signed~))
    })
    check(
      "to_bytes(\{text}, \{length}, big=\{big}, signed=\{signed})",
      got,
      want,
    )
  }
}

///|
fn check_bit_count(rows : Array[(String, Int32)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    check(
      "bit_count(\{text})",
      bit_count(bigint_of(text)).to_string(),
      want.to_string(),
    )
  }
}

///|
/// Lowercase hex of every byte, for byte-vector comparisons.
fn hex_of_bytes(bytes : Bytes) -> String {
  let alphabet = "0123456789abcdef"
  let sb = StringBuilder()
  let mut i = 0
  while i < bytes.length() {
    let byte = bytes[i].to_int()
    sb.write_char(alphabet.get_char(byte / 16).unwrap())
    sb.write_char(alphabet.get_char(byte % 16).unwrap())
    i += 1
  }
  sb.to_string()
}

///|
test "divmod agrees with floordiv and floor_mod" {
  for (a, b) in [(7N, 2N), (-7N, 2N), (7N, -2N), (-7N, -2N), (0N, 5N)] {
    let (q, r) = divmod(a, b)
    if q * b + r != a {
      fail("divmod(\{a}, \{b}) does not reconstruct")
    }
    if r != 0N && (r < 0N) != (b < 0N) {
      fail("remainder of \{a} % \{b} has the wrong sign")
    }
  }
}

///|
test "of_bytes is the inverse of to_bytes" {
  for text in ["0", "255", "-1", "-128", "65535", "12345678901234567890"] {
    for
      (big, signed) in [
        (true, false),
        (false, false),
        (true, true),
        (false, true),
      ] {
      let value = bigint_of(text)
      let bytes = to_bytes(value, length=8, big~, signed~) catch {
        _ => continue
      }
      let back = of_bytes(bytes, big~, signed~)
      if back != value {
        fail("of_bytes(to_bytes(\{text})) is \{back}")
      }
    }
  }
}

///|
test "a refusal names where the text stopped making sense" {
  let at : String = parse_int("12x", base=0).to_string() catch {
    Malformed(at~, reason~) => {
      if reason == "" {
        fail("a refusal should explain itself")
      }
      at.to_string()
    }
    _ => "-1"
  }
  if at != "2" {
    fail("12x should be refused at offset 2, not \{at}")
  }
}

///|
test "to_radix reads back through parse_int" {
  let values = [
    0N,
    1N,
    -1N,
    255N,
    -255N,
    4096N,
    123456789012345678901234567890N,
    -123456789012345678901234567890N,
  ]
  for radix in ([2, 3, 8, 10, 16, 32, 36] : Array[Int32]) {
    for value in values {
      let text = to_radix(value, radix~) catch { _ => fail("to_radix refused") }
      let back = parse_int(text, base=radix) catch {
        _ => fail("parse_int refused \{text} in base \{radix}")
      }
      if back != value {
        fail(
          "to_radix(\{value}, \{radix}) is \{text}, which reads back as \{back}",
        )
      }
    }
  }
  // A value another arbitrary-precision library prints the same way.
  if to_radix(0x1a2b3cN, radix=32) != "1kaps" {
    fail("0x1a2b3c in base 32 should be 1kaps")
  }
  if to_radix(-255N, radix=16) != "-ff" {
    fail("the sign belongs in front of the digits")
  }
}

///|
test "a radix outside two to thirty-six is refused" {
  for radix in ([0, 1, -2, 37] : Array[Int32]) {
    let refused = to_radix(10N, radix~).to_string() catch { _ => "refused" }
    if refused != "refused" {
      fail("radix \{radix} should be refused")
    }
  }
}

///|
test "ilog is the greatest exponent whose power does not pass n" {
  let cases = [
    (1N, 10N, 0),
    (9N, 10N, 0),
    (10N, 10N, 1),
    (1000N, 10N, 3),
    (-1024N, 2N, 10),
    (1023N, 2N, 9),
    (80N, 3N, 3),
  ]
  for (value, base, want) in cases {
    let got = ilog(value, base~) catch { _ => fail("ilog refused \{value}") }
    if got != want {
      fail("ilog(\{value}, base=\{base}) is \{got}, want \{want}")
    }
  }
  for value in [2N, 7N, 123456789012345678901234567890N] {
    for base in [2N, 5N, 10N, 36N] {
      let k = ilog(value, base~)
      let below = power(base, scanned(k.to_string()))
      let above = below * base
      if !(below <= value && value < above) {
        fail("ilog(\{value}, \{base}) = \{k} does not bracket the value")
      }
    }
  }
}

///|
test "a logarithm of zero and a base below two are refused" {
  let zero = ilog(0N).to_string() catch { _ => "refused" }
  if zero != "refused" {
    fail("zero has no logarithm")
  }
  let base = ilog(10N, base=1N).to_string() catch { _ => "refused" }
  if base != "refused" {
    fail("a base of one has no logarithm")
  }
}

///|
test "gcd_ext returns a gcd and the coefficients that spell it" {
  let cases = [
    (240N, 46N),
    (-240N, 46N),
    (240N, -46N),
    (-240N, -46N),
    (0N, 5N),
    (5N, 0N),
    (0N, 0N),
    (97N, 89N),
  ]
  for (a, b) in cases {
    let (g, x, y) = gcd_ext(a, b)
    if g != gcd(a, b) {
      fail("gcd_ext(\{a}, \{b}) gave \{g}, want \{gcd(a, b)}")
    }
    if a * x + b * y != g {
      fail("gcd_ext(\{a}, \{b}) does not reconstruct the gcd")
    }
  }
  let (g, x, y) = gcd_ext(240N, 46N)
  if (g, x, y) != (2N, -9N, 47N) {
    fail("the coefficients for 240 and 46 are not the ones Euclid gives")
  }
}
