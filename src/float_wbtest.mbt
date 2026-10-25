// Float vectors: reading, writing, hex, and rounding.

///|
test "parse_float matches Python, and repr_float agrees with repr" {
  for row in vec_parse_float {
    let (text, want) = row
    let got = attempt(() => repr_float(parse_float(text)))
    check("parse_float(\{text})", got, want)
  }
}

///|
test "repr_float is the shortest round-trip, as Python spells it" {
  for row in vec_repr {
    let (text, want) = row
    let got = attempt(() => repr_float(from_vector(text)))
    check("repr_float(\{text})", got, want)
  }
}

///|
test "float_hex matches float.hex" {
  for row in vec_hex_out {
    let (text, want) = row
    let got = float_hex(
      from_vector(text) catch {
        (err : Refused) => {
          fail("parse_float(\{text}) raised \{refused_key(err)}")
          0.0
        }
      },
    )
    check("float_hex(\{text})", got, want)
  }
}

///|
test "float_of_hex matches float.fromhex, including what it refuses" {
  for row in vec_hex_in {
    let (text, want) = row
    let got = attempt(() => repr_float(float_of_hex(text)))
    check("float_of_hex(\{text})", got, want)
  }
}

///|
test "round matches Python for every recorded half-way case" {
  for row in vec_round {
    let (kind, text, ndigits, want) = row
    let value = from_vector(text) catch {
      (err : Refused) => {
        fail("parse_float(\{text}) raised \{refused_key(err)}")
        0.0
      }
    }
    let got = if kind == "int" {
      attempt(() => round_big(value).to_string())
    } else {
      attempt(() => repr_float(round_float(value, ndigits~)))
    }
    check("round(\{text}, \{ndigits}) as \{kind}", got, want)
  }
}

///|
test "floor, ceil and trunc agree with Python's math module" {
  for row in vec_floor {
    let (text, want_floor, want_ceil, want_trunc) = row
    let value = from_vector(text) catch {
      (err : Refused) => {
        fail("parse_float(\{text}) raised \{refused_key(err)}")
        0.0
      }
    }
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
test "as_integer_ratio reduces the way Python does" {
  let cases : Array[Double] = [1.5, 0.1, 0.0, -0.0, 3.0, 5.0e-324, 1.0e300]
  for value in cases {
    let (num, den) = as_integer_ratio(value) catch {
      (err : Refused) => {
        fail(
          "as_integer_ratio(\{repr_float(value)}) raised \{refused_key(err)}",
        )
        (0N, 1N)
      }
    }
    let ratio = as_ratio(value) catch {
      (err : Refused) => {
        fail("as_ratio raised \{refused_key(err)}")
        Fraction::default()
      }
    }
    if ratio.num != num || ratio.den != den {
      fail("as_ratio and as_integer_ratio disagree for \{repr_float(value)}")
    }
  }
}
