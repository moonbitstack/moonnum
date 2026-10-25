// Integer vectors: parsing, division, exponentiation, number theory, bytes.

///|
test "parse_int matches Python for every recorded spelling" {
  for row in vec_parse_int {
    let (text, base, want) = row
    let got = attempt(() => parse_int(text, base~).to_string())
    check("parse_int(\{text}, base=\{base})", got, want)
  }
}

///|
test "floordiv and floor_mod match Python over all sign combinations" {
  for row in vec_int_div {
    let (a, b, want_q, want_r) = row
    let left = bigint_of(a)
    let right = bigint_of(b)
    let q = attempt(() => floordiv(left, right).to_string())
    let r = attempt(() => floor_mod(left, right).to_string())
    check("floordiv(\{a}, \{b})", q, want_q)
    check("floor_mod(\{a}, \{b})", r, want_r)
  }
}

///|
test "divmod agrees with floordiv and floor_mod" {
  for row in vec_int_div {
    let (a, b, want_q, want_r) = row
    let left = bigint_of(a)
    let right = bigint_of(b)
    let got = attempt(() => {
      let (q, r) = divmod(left, right)
      q.to_string() + "/" + r.to_string()
    })
    let want = if want_q.has_prefix("!") {
      want_q
    } else {
      want_q + "/" + want_r
    }
    check("divmod(\{a}, \{b})", got, want)
  }
}

///|
test "pow matches Python, including the modular inverse" {
  for row in vec_pow {
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
test "number theory matches Python's math module" {
  for row in vec_int_math {
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
test "to_bytes matches Python, and of_bytes reads it back" {
  for row in vec_bytes {
    let (text, length, big, signed, want) = row
    let value = bigint_of(text)
    let got = attempt(() => {
      let bytes = to_bytes(value, length~, big~, signed~)
      hex_of_bytes(bytes)
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
test "of_bytes is the inverse of to_bytes" {
  for row in vec_bytes {
    let (text, length, big, signed, want) = row
    if want.has_prefix("!") {
      continue
    }
    let value = bigint_of(text)
    let bytes = to_bytes(value, length~, big~, signed~) catch {
      (err : Refused) => {
        fail("to_bytes(\{text}) raised \{refused_key(err)}")
        b""
      }
    }
    let back = of_bytes(bytes, big~, signed~)
    check("of_bytes(to_bytes(\{text}))", back.to_string(), text)
  }
}
