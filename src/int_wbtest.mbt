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
