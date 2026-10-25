// Fractions: the assertions behind the generated vectors.

///|
fn check_fraction_parse(rows : Array[(String, String)]) -> Unit raise {
  for row in rows {
    let (text, want) = row
    let got = attempt(() => {
      let f = parse_fraction(text) catch { (err : Refused) => raise err }
      f.num.to_string() + "/" + f.den.to_string()
    })
    check("parse_fraction(\{text})", got, want)
  }
}

///|
fn check_fraction_ops(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  for row in rows {
    let (op, left, right, want) = row
    let a = parse_fraction(left) catch { _ => continue }
    let b = if right == "" {
      Fraction::default()
    } else {
      parse_fraction(right) catch {
        _ => continue
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
      _ => attempt(() => a.limit_denominator(max=bigint_of(right)).to_string())
    }
    check("\{op}(\{left}, \{right})", got, want)
  }
}

///|
test "a fraction always has a positive denominator and no common factor" {
  for
    text in [
      "-3/-4", "0/5", "6/4", "-1.25", "1e-3", "123456789012345678901234567890/7",
    ] {
    let f = parse_fraction(text) catch { _ => continue }
    if f.den <= 0N {
      fail("\{text} has a non-positive denominator")
    }
    if gcd(f.num, f.den) > 1N {
      fail("\{text} is not in lowest terms")
    }
  }
}

///|
test "of_float is exact" {
  let tenth = Fraction::of_float(0.1) catch { _ => Fraction::default() }
  if tenth.num.to_string() != "3602879701896397" ||
    tenth.den.to_string() != "36028797018963968" {
    fail("0.1 is not the double's exact value: \{tenth}")
  }
}

///|
test "a decimal literal is a power of ten, not a float" {
  let tenth = parse_fraction("0.1") catch { _ => Fraction::default() }
  if tenth.num != 1N || tenth.den != 10N {
    fail("0.1 parsed as \{tenth}")
  }
}
