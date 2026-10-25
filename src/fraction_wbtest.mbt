// Fraction vectors: reading, arithmetic, rounding and approximation.

///|
test "parse_fraction matches Fraction(str)" {
  for row in vec_fraction_parse {
    let (text, want) = row
    let got = attempt(() => {
      let f = parse_fraction(text) catch { (err : Refused) => raise err }
      f.num.to_string() + "/" + f.den.to_string()
    })
    check("parse_fraction(\{text})", got, want)
  }
}

///|
test "fraction arithmetic matches Python's fractions module" {
  for row in vec_fraction_ops {
    let (op, left, right, want) = row
    let a = parse_fraction(left) catch {
      (err : Refused) => {
        fail("parse_fraction(\{left}) raised \{refused_key(err)}")
        Fraction::default()
      }
    }
    let b = if right == "" {
      Fraction::default()
    } else {
      parse_fraction(right) catch {
        (err : Refused) => {
          fail("parse_fraction(\{right}) raised \{refused_key(err)}")
          Fraction::default()
        }
      }
    }
    let got = match op {
      "add" => (a + b).to_string()
      "sub" => (a - b).to_string()
      "mul" => (a * b).to_string()
      "div" => attempt(() => a.divide(b).to_string())
      "cmp" => a.compare(b).to_string()
      "floordiv" => attempt(() => a.floor_divide_big(b).to_string())
      "mod" => attempt(() => a.modulo(b).to_string())
      "floor" => a.floor_big().to_string()
      "ceil" => a.ceil_big().to_string()
      "round" => a.round_big().to_string()
      "roundn" => a.round(ndigits=int_of(right)).to_string()
      "double" => attempt(() => repr_float(a.to_double()))
      _ =>
        attempt(() => {
          let limit = parse_int(right)
          a.limit_denominator(max=limit).to_string()
        })
    }
    check("\{op}(\{left}, \{right})", got, want)
  }
}

///|
test "a fraction always has a positive denominator and no common factor" {
  for row in vec_fraction_parse {
    let (text, want) = row
    if want.has_prefix("!") {
      continue
    }
    let f = parse_fraction(text) catch {
      (err : Refused) => {
        fail("parse_fraction(\{text}) raised \{refused_key(err)}")
        Fraction::default()
      }
    }
    if f.den <= 0N {
      fail("\{text} has a non-positive denominator")
    }
    if gcd(f.num, f.den) > 1N {
      fail("\{text} is not in lowest terms")
    }
  }
}

///|
test "of_float is exact, and as_ratio agrees with it" {
  let cases : Array[Double] = [0.1, 0.5, -2.25, 1.0, 0.0, 5.0e-324]
  for value in cases {
    let from_float = Fraction::of_float(value) catch {
      (err : Refused) => {
        fail("of_float raised \{refused_key(err)}")
        Fraction::default()
      }
    }
    let from_ratio = as_ratio(value) catch {
      (err : Refused) => {
        fail("as_ratio raised \{refused_key(err)}")
        Fraction::default()
      }
    }
    if from_float.num != from_ratio.num || from_float.den != from_ratio.den {
      fail("of_float and as_ratio disagree for \{repr_float(value)}")
    }
  }
  let tenth = Fraction::of_float(0.1) catch { _ => Fraction::default() }
  if tenth.num.to_string() != "3602879701896397" ||
    tenth.den.to_string() != "36028797018963968" {
    fail("0.1 is not the double's exact value: \{tenth}")
  }
}
