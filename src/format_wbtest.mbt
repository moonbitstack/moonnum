// Formatting: the assertions behind the generated vectors.

///|
fn check_format_int(rows : Array[(String, String, String)]) -> Unit raise {
  for row in rows {
    let (value, spec, want) = row
    check(
      "format(\{value}, \"\{spec}\")",
      attempt(() => format_int(bigint_of(value), spec)),
      want,
    )
  }
}

///|
fn check_format_float(rows : Array[(String, String, String)]) -> Unit raise {
  for row in rows {
    let (value, spec, want) = row
    let parsed = from_vector(value) catch { _ => continue }
    check(
      "format(\{value}, \"\{spec}\")",
      attempt(() => format_float(parsed, spec)),
      want,
    )
  }
}

///|
fn check_format_complex(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  for row in rows {
    let (re_text, im_text, spec, want) = row
    let re = from_vector(re_text) catch { _ => continue }
    let im = from_vector(im_text) catch { _ => continue }
    let z : Complex = { re, im, }
    check(
      "format(\{re_text}+\{im_text}j, \"\{spec}\")",
      attempt(() => z.format(spec)),
      want,
    )
  }
}

///|
fn check_format_fraction(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  for row in rows {
    let (num_text, den_text, spec, want) = row
    let f = Fraction::new(bigint_of(num_text), bigint_of(den_text)) catch {
      _ => continue
    }
    check(
      "format(\{num_text}/\{den_text}, \"\{spec}\")",
      attempt(() => f.format(spec)),
      want,
    )
  }
}

///|
fn check_format_sweep_int(rows : Array[(String, String, String)]) -> Unit raise {
  check_format_int(rows)
}

///|
fn check_format_sweep_float(
  rows : Array[(String, String, String)],
) -> Unit raise {
  check_format_float(rows)
}

///|
fn check_format_fraction_sweep(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  check_format_fraction(rows)
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
    check(
      "format(Number::Int(\{value}), \"\{spec}\")",
      attempt(() => format(Number::Int(bigint_of(value)), spec)),
      direct,
    )
  }
  for
    row in [
      ("1.5", ".3e"),
      ("0.25", "%"),
      ("-0.0", "z"),
      ("1234.5678", "012,.2f"),
    ] {
    let (value, spec) = row
    let parsed = from_vector(value) catch { _ => continue }
    let direct = attempt(() => format_float(parsed, spec))
    check(
      "format(Number::Float(\{value}), \"\{spec}\")",
      attempt(() => format(Number::Float(parsed), spec)),
      direct,
    )
  }
}

///|
test "a specifier that cannot mean anything is refused, not approximated" {
  let cases : Array[(String, String)] = [
    (".2d", "precision"),
    (",x", "','"),
    ("z", "negative-zero"),
  ]
  for (spec, _) in cases {
    let refused = format_int(255N, spec) catch { _ => "refused" }
    if refused != "refused" {
      fail("\{spec} should have been refused, got \{refused}")
    }
  }
}
