// Floats: the assertions behind the generated vectors.

///|
fn check_parse_float(rows : Array[(String, String)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    check(
      "parse_float(\{text})",
      attempt(() => repr_float(parse_float(text))),
      want,
    )
  }
}

///|
fn check_repr(rows : Array[(String, String)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    check(
      "repr_float(\{text})",
      attempt(() => repr_float(from_vector(text))),
      want,
    )
  }
}

///|
fn check_hex_out(rows : Array[(String, String)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    let value = from_vector(text) catch { _ => continue }
    check("float_hex(\{text})", float_hex(value), want)
  }
}

///|
fn check_hex_in(rows : Array[(String, String)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    check(
      "float_of_hex(\{text})",
      attempt(() => repr_float(float_of_hex(text))),
      want,
    )
  }
}

///|
fn check_round(rows : Array[(String, String, Int32, String)]) -> Unit raise {
  for row in rows {
    let (kind, text, ndigits, want) = row
    let value = from_vector(text) catch { _ => continue }
    let got = if kind == "int" {
      attempt(() => round_big(value).to_string())
    } else {
      repr_float(round_float(value, ndigits~))
    }
    check("round(\{text}, \{ndigits}) as \{kind}", got, want)
  }
}

///|
fn check_floor(rows : Array[(String, String, String, String)]) -> Unit raise {
  for row in rows {
    let (text, want_floor, want_ceil, want_trunc) = row
    let value = from_vector(text) catch { _ => continue }
    check(
      "floor(\{text})",
      attempt(() => floor_big(value).to_string()),
      want_floor,
    )
    check(
      "ceil(\{text})",
      attempt(() => ceil_big(value).to_string()),
      want_ceil,
    )
    check(
      "trunc(\{text})",
      attempt(() => trunc_big(value).to_string()),
      want_trunc,
    )
  }
}

///|
test "as_integer_ratio and as_ratio agree, and reduce" {
  let cases : Array[Double] = [1.5, 0.1, 0.0, -0.0, 3.0, 5.0e-324, 1.0e300]
  for value in cases {
    let (num, den) = as_integer_ratio(value) catch { _ => continue }
    let ratio = as_ratio(value) catch { _ => continue }
    if ratio.num != num || ratio.den != den {
      fail("as_ratio and as_integer_ratio disagree for \{repr_float(value)}")
    }
    if gcd(num, den) != 1N {
      fail("\{repr_float(value)} is not in lowest terms")
    }
  }
}

///|
test "a float round-trips through its own text" {
  for
    text in [
      "0.1", "1e-300", "1.7976931348623157e308", "5e-324", "-0.0", "3.141592653589793",
    ] {
    let value = parse_float(text) catch { _ => continue }
    let again = parse_float(repr_float(value)) catch { _ => continue }
    if value.reinterpret_as_uint64() != again.reinterpret_as_uint64() {
      fail("\{text} did not survive its own repr")
    }
  }
}
