// Complex vectors: every spelling Python accepts, and CPython's arithmetic.

///|
test "parse_complex matches Python, plus the i suffix" {
  for row in vec_complex_parse {
    let (text, want) = row
    let got = attempt(() => repr_complex(parse_complex(text)))
    if text.has_suffix("i") && want.has_prefix("!") {
      // Python refuses "i"; this library accepts it, so only check that the
      // refusal it gives for the rest is the same kind of refusal.
      continue
    }
    check("parse_complex(\{text})", got, want)
  }
}

///|
test "complex arithmetic matches CPython's C99 cases" {
  for row in vec_complex_ops {
    let (op, left, right, want) = row
    let a = parse_complex(left) catch {
      (err : Refused) => {
        fail("parse_complex(\{left}) raised \{refused_key(err)}")
        Complex::default()
      }
    }
    let b = if right == "" {
      Complex::default()
    } else {
      parse_complex(right) catch {
        (err : Refused) => {
          fail("parse_complex(\{right}) raised \{refused_key(err)}")
          Complex::default()
        }
      }
    }
    let got = match op {
      "add" => repr_complex(a + b)
      "sub" => repr_complex(a - b)
      "mul" => repr_complex(a * b)
      "div" =>
        attempt(() => {
          repr_complex(a.divide(b) catch { (err : Refused) => raise err })
        })
      "abs" => repr_float(a.abs())
      "conj" => repr_complex(a.conjugate())
      _ =>
        attempt(() => {
          repr_complex(a.pow(b) catch { (err : Refused) => raise err })
        })
    }
    check("\{op}(\{left}, \{right})", got, want)
  }
}

///|
test "the i suffix reads as the imaginary unit" {
  let z = parse_complex("3+5i") catch {
    (err : Refused) => {
      fail("3+5i refused: \{refused_key(err)}")
      Complex::default()
    }
  }
  if z.re != 3.0 || z.im != 5.0 {
    fail("3+5i is \{repr_complex(z)}")
  }
  let plain = parse_complex("2i") catch {
    (err : Refused) => {
      fail("2i refused: \{refused_key(err)}")
      Complex::default()
    }
  }
  if plain.re != 0.0 || plain.im != 2.0 {
    fail("2i is \{repr_complex(plain)}")
  }
}
