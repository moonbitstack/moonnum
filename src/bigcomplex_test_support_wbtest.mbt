// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Shared machinery for the generated `BigComplex` vectors.
//
// The complex functions are compositions of the real ones, so the comparison is
// in ulps of the larger part rather than the exact one: a component that is
// small next to its partner is small because the answer is nearly real, and an
// absolute test there would fail an answer that is right to the last bit that
// can be asked for.

///|
/// A vector's complex argument at the width the vector is read at.
fn bc_value(
  re_text : String,
  im_text : String,
  width : Int32,
) -> BigComplex raise {
  { real: vector_value(re_text, width), imag: vector_value(im_text, width), }
}

///|
/// One component of an answer, against the reference's, in ulps of `scale`.
fn expect_part(
  what : String,
  got : BigFloat,
  wanted : BigFloat,
  scale : BigFloat,
  width : Int32,
) -> Unit raise {
  if got.is_nan() {
    fail("for \{what}: want \{wanted}, got nan")
  }
  if scale.is_zero() {
    if got != wanted {
      fail("for \{what}: want \{wanted}, got \{got}")
    }
    return
  }
  let gap = (got - wanted).abs()
  if !gap.is_zero() && !negligible(gap, scale, width - 2) {
    fail("for \{what}: want \{wanted}, got \{got}")
  }
}

///|
/// Both components of an answer against the reference's.
fn expect_pair(
  what : String,
  got : BigComplex,
  wanted_re : String,
  wanted_im : String,
  width : Int32,
) -> Unit raise {
  let want_re = vector_value(wanted_re, width)
  let want_im = vector_value(wanted_im, width)
  let scale = if want_re.abs() >= want_im.abs() {
    want_re.abs()
  } else {
    want_im.abs()
  }
  expect_part("\{what}.real", got.real, want_re, scale, width)
  expect_part("\{what}.imag", got.imag, want_im, scale, width)
}

///|
/// One complex operation, named as the generator names it.
fn bc_operation(
  name : String,
  a : BigComplex,
  b : BigComplex,
  c : Context,
) -> BigComplex raise {
  match name {
    "add" => c.add_complex(a, b)
    "sub" => c.sub_complex(a, b)
    "mul" => c.mul_complex(a, b)
    "div" => c.divide_complex(a, b)
    "pow" => a.pow(b, context=c)
    _ => {
      fail("unknown complex operation \{name}")
      a
    }
  }
}

///|
fn check_bc_operation(
  name : String,
  width : Int32,
  rows : Array[(String, String, String, String, String, String)],
) -> Unit raise {
  let c = Context::new(width)
  for row in rows {
    let (a_re, a_im, b_re, b_im, sum_re, sum_im) = row
    let a = bc_value(a_re, a_im, width)
    let b = bc_value(b_re, b_im, width)
    let got = bc_operation(name, a, b, c) catch {
      err => {
        fail("for \{name}(\{a_re}+\{a_im}j, \{b_re}+\{b_im}j): refused \{err}")
        return
      }
    }
    expect_pair(
      "\{name}(\{a_re}+\{a_im}j, \{b_re}+\{b_im}j)",
      got,
      sum_re,
      sum_im,
      width,
    )
  }
}

///|
/// The complex operation a vector names, on one argument.
fn bc_unary(name : String, value : BigComplex, c : Context) -> BigComplex raise {
  match name {
    "exp" => value.exp(context=c)
    "ln" => value.ln(context=c)
    "sqrt" => value.sqrt(context=c)
    "sin" => value.sin(context=c)
    "cos" => value.cos(context=c)
    "tan" => value.tan(context=c)
    "asin" => value.asin(context=c)
    "acos" => value.acos(context=c)
    "atan" => value.atan(context=c)
    "sinh" => value.sinh(context=c)
    "cosh" => value.cosh(context=c)
    "tanh" => value.tanh(context=c)
    "asinh" => value.asinh(context=c)
    "acosh" => value.acosh(context=c)
    "atanh" => value.atanh(context=c)
    _ => {
      fail("unknown complex function \{name}")
      value
    }
  }
}

///|
fn check_bc_function(
  name : String,
  width : Int32,
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  let c = Context::new(width)
  for row in rows {
    let (re_text, im_text, wanted_re, wanted_im) = row
    let value = bc_value(re_text, im_text, width)
    let got = bc_unary(name, value, c) catch {
      err => {
        fail("for \{name}(\{re_text}+\{im_text}j): refused \{err}")
        return
      }
    }
    expect_pair(
      "\{name}(\{re_text}+\{im_text}j)",
      got,
      wanted_re,
      wanted_im,
      width,
    )
  }
}

///|
/// Where the reference has a value the type cannot hold: a division by zero, and
/// a zero raised to a power that has no answer on this branch.
fn check_bc_domain(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  let width = 100
  let c = Context::new(width)
  for row in rows {
    let (name, a_text, b_text, wanted) = row
    let a = bc_value(a_text, "0", width)
    let b = bc_value(b_text, "0", width)
    let key = match name {
      "divide" =>
        c.divide_complex(a, b).to_string() catch {
          (err : Refused) => refused_key(err)
        }
      _ =>
        a.pow(b, context=c).to_string() catch {
          (err : Refused) => refused_key(err)
        }
    }
    check("the refusal of \{name}(\{a_text}, \{b_text})", key, wanted)
  }
}
