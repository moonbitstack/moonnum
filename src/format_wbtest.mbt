// Format-specification vectors: every recorded combination of flags.

///|
test "format_int matches Python's int formatting" {
  for row in vec_format_int {
    let (value, spec, want) = row
    let got = attempt(() => format_int(bigint_of(value), spec))
    check("format(\{value}, \"\{spec}\")", got, want)
  }
}

///|
test "format_float matches Python's float formatting" {
  for row in vec_format_float {
    let (value, spec, want) = row
    let parsed = from_vector(value) catch {
      (err : Refused) => {
        fail("parse_float(\{value}) raised \{refused_key(err)}")
        0.0
      }
    }
    let got = attempt(() => format_float(parsed, spec))
    check("format(\{value}, \"\{spec}\")", got, want)
  }
}

///|
test "complex formatting matches Python, including the parentheses rule" {
  for row in vec_format_complex {
    let (re_text, im_text, spec, want) = row
    let re = from_vector(re_text) catch { _ => 0.0 }
    let im = from_vector(im_text) catch { _ => 0.0 }
    let z : Complex = { re, im, }
    let got = attempt(() => z.format(spec))
    check("format(\{re_text}+\{im_text}j, \"\{spec}\")", got, want)
  }
}

///|
test "fraction formatting matches Python, ratio and float styles" {
  for row in vec_format_fraction {
    let (num_text, den_text, spec, want) = row
    let f = Fraction::new(bigint_of(num_text), bigint_of(den_text)) catch {
      (err : Refused) => {
        fail("Fraction(\{num_text}, \{den_text}) raised \{refused_key(err)}")
        Fraction::default()
      }
    }
    let got = attempt(() => f.format(spec))
    check("format(\{num_text}/\{den_text}, \"\{spec}\")", got, want)
  }
}

///|
test "the unified entry point dispatches to the same answer" {
  let int_cases : Array[(String, String)] = [
    ("42", "08,d"),
    ("255", "#x"),
    ("7", "<5"),
    ("65", "c"),
  ]
  for row in int_cases {
    let (value, spec) = row
    let direct = attempt(() => format_int(bigint_of(value), spec))
    let unified = attempt(() => format(Number::Int(bigint_of(value)), spec))
    check("format(Number::Int(\{value}), \"\{spec}\")", unified, direct)
  }
  let float_cases : Array[(String, String)] = [
    ("1.5", ".3e"),
    ("0.25", "%"),
    ("-0.0", "z"),
    ("1234.5678", "012,.2f"),
  ]
  for row in float_cases {
    let (value, spec) = row
    let parsed = from_vector(value) catch { _ => 0.0 }
    let direct = attempt(() => format_float(parsed, spec))
    let unified = attempt(() => format(Number::Float(parsed), spec))
    check("format(Number::Float(\{value}), \"\{spec}\")", unified, direct)
  }
}
