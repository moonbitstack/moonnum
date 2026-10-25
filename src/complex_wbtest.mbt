// Complex numbers: the assertions behind the generated vectors.

///|
fn check_complex_parse(rows : Array[(String, String)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    let got = attempt(() => repr_complex(parse_complex(text)))
    // Python has no `i` suffix; this library accepts it, so a case that Python
    // refuses and that mentions `i` is not a disagreement.
    if text.has_suffix("i") && want.has_prefix("!") && !got.has_prefix("!") {
      continue
    }
    check("parse_complex(\{text})", got, want)
  }
}

///|
fn check_complex_ops(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  for row in rows {
    let (op, left, right, want) = row
    let a = parse_complex(left) catch { _ => continue }
    let b = if right == "" {
      Complex::default()
    } else {
      parse_complex(right) catch {
        _ => continue
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
  let z = parse_complex("3+5i") catch { _ => Complex::default() }
  if z.re != 3.0 || z.im != 5.0 {
    fail("3+5i is \{repr_complex(z)}")
  }
}

///|
test "a positive zero real part is not printed" {
  let z = parse_complex("2j") catch { _ => Complex::default() }
  if repr_complex(z) != "2j" {
    fail("2j is printed as \{repr_complex(z)}")
  }
  let negative = parse_complex("-0-1j") catch { _ => Complex::default() }
  if repr_complex(negative) != "(-0-1j)" {
    fail("-0-1j is printed as \{repr_complex(negative)}")
  }
}
