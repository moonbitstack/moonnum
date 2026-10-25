// The tower: reading a literal into a kind, comparing across kinds, and the
// results of mixing them.

///|
test "parse keeps the kind the literal spelled" {
  for row in vec_number_parse {
    let (text, want) = row
    let got = attempt(() => parse(text).to_string())
    check("parse(\{text})", got, want)
  }
}

///|
test "comparison across the tower is exact" {
  for row in vec_numbers {
    let (left, right, op, want) = row
    let a = parse(left) catch {
      (err : Refused) => {
        fail("parse(\{left}) raised \{refused_key(err)}")
        Number::Int(0N)
      }
    }
    let b = parse(right) catch {
      (err : Refused) => {
        fail("parse(\{right}) raised \{refused_key(err)}")
        Number::Int(0N)
      }
    }
    if op == "eq" {
      let got = if a == b { "True" } else { "False" }
      check("\{left} == \{right}", got, want)
    } else if op == "cmp" {
      let got = attempt(() => a.compare_numeric(b).to_string())
      check("compare(\{left}, \{right})", got, want)
    } else {
      let got = match op {
        "add" => (a + b).to_string()
        "sub" => (a - b).to_string()
        "mul" => (a * b).to_string()
        _ => attempt(() => a.divide(b).to_string())
      }
      check("\{left} \{op} \{right}", got, want)
    }
  }
}

///|
test "one equals one equals one equals one" {
  let one = parse("1") catch { _ => Number::Int(0N) }
  for text in ["1.0", "3/3", "1+0j", "0x1", "1.000"] {
    let other = parse(text) catch { _ => Number::Int(0N) }
    if !(one == other) {
      fail("1 is not equal to \{text}")
    }
  }
}

///|
test "an integer beyond 2^53 is not rounded to compare with a float" {
  let big = parse("9007199254740993") catch { _ => Number::Int(0N) }
  let near = parse("9007199254740992.0") catch { _ => Number::Int(0N) }
  let order = big.compare_numeric(near) catch { _ => 0 }
  if order != 1 {
    fail("9007199254740993 should be greater than 9007199254740992.0")
  }
}

///|
test "promotion follows the tower" {
  let integer = parse("2") catch { _ => Number::Int(0N) }
  let fraction = parse("1/3") catch { _ => Number::Int(0N) }
  let float = parse("0.5") catch { _ => Number::Int(0N) }
  let complex = parse("1+1j") catch { _ => Number::Int(0N) }
  check("2 + 1/3", integer.add(fraction).to_string(), "7/3")
  check("2 + 0.5", integer.add(float).to_string(), "2.5")
  check("2 + (1+1j)", integer.add(complex).to_string(), "(3+1j)")
  check(
    "2 / 4",
    integer.divide(parse("4") catch { _ => Number::Int(0N) }).to_string(),
    "0.5",
  )
}
