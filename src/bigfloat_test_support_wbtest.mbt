// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Shared machinery for the generated `BigFloat` vectors.
//
// Every test here reads from `bigfloat_vectors_wbtest.mbt` and compares. Nothing
// computes an expected value with the code under test.

///|
/// The widest argument a vector is read at: enough that a value needing more bits
/// than the width under test arrives unrounded, so the operation rounds once and
/// the comparison is about the operation and not about the reading.
fn vector_width(width : Int32) -> Int32 {
  width + 320
}

///|
/// `text` as a value, at the width a vector is read at.
fn vector_value(text : String, width : Int32) -> BigFloat raise {
  BigFloat::parse(text, context=Context::new(vector_width(width)))
}

///|
/// Compare an exact answer against the reference's, printed exactly.
fn expect_same(
  what : String,
  got : BigFloat,
  wanted : String,
  width : Int32,
) -> Unit raise {
  if wanted == "nan" || wanted == "inf" || wanted == "-inf" {
    let same = match (got.kind(), wanted) {
      (NotANumber, "nan") => true
      (PositiveInfinity, "inf") => true
      (NegativeInfinity, "-inf") => true
      _ => false
    }
    if !same {
      fail("for \{what}: want \{wanted}, got \{got}")
    }
    return
  }
  let want = vector_value(wanted, width)
  if got != want {
    fail("for \{what}: want \{want}, got \{got}")
  }
}

///|
/// Compare an approximate answer against the reference's, within a few ulps.
///
/// The two implementations stop their series at different places and round a
/// different number of guard bits, so a transcendental answer is stated to
/// `width - 6` bits rather than to the last one.
fn expect_close(
  what : String,
  got : BigFloat,
  wanted : String,
  width : Int32,
) -> Unit raise {
  if wanted == "nan" || wanted == "inf" || wanted == "-inf" {
    expect_same(what, got, wanted, width)
    return
  }
  let want = vector_value(wanted, width)
  if got.is_nan() {
    fail("for \{what}: want \{want}, got nan")
  }
  let gap = (got - want).abs()
  if !gap.is_zero() && !negligible(gap, want.abs(), width - 2) {
    fail("for \{what}: want \{want}, got \{got}")
  }
}

///|
fn check_bf_arithmetic(
  width : Int32,
  rows : Array[(String, String, String, String, String, String)],
) -> Unit raise {
  let c = Context::new(width)
  for row in rows {
    let (a_text, b_text, sum, difference, product, quotient) = row
    let a = vector_value(a_text, width)
    let b = vector_value(b_text, width)
    expect_same("\{a_text} + \{b_text}", c.add(a, b), sum, width)
    expect_same("\{a_text} - \{b_text}", c.sub(a, b), difference, width)
    expect_same("\{a_text} * \{b_text}", c.mul(a, b), product, width)
    expect_same("\{a_text} / \{b_text}", c.div(a, b), quotient, width)
  }
}

///|
/// The name of a rounding direction, in the spelling the generator writes.
fn rounding_of(text : String) -> Rounding raise {
  match text {
    "n" => Nearest
    "f" => Floor
    "c" => Ceiling
    "d" => Down
    "u" => Up
    _ => fail("unknown rounding \{text}")
  }
}

///|
fn check_bf_rounding(
  width : Int32,
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  for row in rows {
    let (a_text, b_text, mode, sum) = row
    let a = vector_value(a_text, width)
    let b = vector_value(b_text, width)
    let c = Context::new(width, rounding=rounding_of(mode))
    expect_same(
      "\{a_text} + \{b_text} rounded \{mode}",
      c.add(a, b),
      sum,
      width,
    )
  }
}

///|
/// The operation a transcendental vector names.
fn unary_of(name : String, value : BigFloat, c : Context) -> BigFloat raise {
  match name {
    "exp" => value.exp(context=c)
    "ln" => value.ln(context=c)
    "expm1" => value.expm1(context=c)
    "log1p" => value.log1p(context=c)
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
    _ => fail("unknown operation \{name}")
  }
}

///|
fn check_bf_function(
  name : String,
  width : Int32,
  rows : Array[(String, String)],
) -> Unit raise {
  let c = Context::new(width)
  for (argument, wanted) in rows {
    let value = vector_value(argument, width)
    expect_close(
      "\{name}(\{argument})",
      unary_of(name, value, c),
      wanted,
      width,
    )
  }
}

///|
fn check_bf_pow(
  width : Int32,
  rows : Array[(String, String, String)],
) -> Unit raise {
  let c = Context::new(width)
  for (base, exponent, wanted) in rows {
    let a = vector_value(base, width)
    let b = vector_value(exponent, width)
    expect_close("\{base} ^ \{exponent}", a.pow(b, context=c), wanted, width)
  }
}

///|
fn check_bf_constants(
  width : Int32,
  rows : Array[(String, String)],
) -> Unit raise {
  let c = Context::new(width)
  for (name, wanted) in rows {
    let got = match name {
      "pi" => BigFloat::pi(context=c)
      "e" => BigFloat::e(context=c)
      _ => BigFloat::ln2(context=c)
    }
    expect_close(name, got, wanted, width)
  }
}

///|
/// A decimal read at a width: the answer is the correctly rounded value, so this
/// one is exact and not a tolerance.
fn check_bf_text(width : Int32, rows : Array[(String, String)]) -> Unit raise {
  let c = Context::new(width)
  for (text, wanted) in rows {
    let got = BigFloat::parse(text, context=c) catch {
      _ => {
        fail("for \{text}: refused at \{width} bits")
        return
      }
    }
    expect_same("read \{text}", got, wanted, width)
  }
}

///|
fn check_bf_decimal(
  width : Int32,
  rows : Array[(String, Int32, String)],
) -> Unit raise {
  for (text, places, wanted) in rows {
    let value = vector_value(text, width)
    check("write \{text} to \{places} places", value.to_decimal(places), wanted)
  }
}

///|
fn check_bf_whole(width : Int32, rows : Array[(String, String)]) -> Unit raise {
  let c = Context::new(width)
  for (text, wanted) in rows {
    expect_same(
      "whole \{text}",
      BigFloat::of_bigint(bigint_of(text), context=c),
      wanted,
      width,
    )
  }
}

///|
/// The answer a domain vector asks for, as a value.
fn domain_answer(
  name : String,
  first : BigFloat,
  second : BigFloat,
  c : Context,
) -> BigFloat raise {
  match name {
    "add" => c.add(first, second)
    "mul" => c.mul(first, second)
    "div" => c.div(first, second)
    "divide" => c.divide(first, second)
    "pow" => first.pow(second, context=c)
    _ => unary_of(name, first, c)
  }
}

///|
/// Where a real value does not exist: the answer has to be the one the reference
/// gives, and a refusal has to be the refusal the generator recorded.
fn check_bf_domain(
  rows : Array[(String, String, String, String)],
) -> Unit raise {
  let width = 100
  let c = Context::new(width)
  for (name, first, second, wanted) in rows {
    let a = vector_value(first, width)
    let b = if second == "" {
      BigFloat::zero(context=c)
    } else {
      vector_value(second, width)
    }
    let call = "\{name}(\{first}, \{second})"
    if wanted.has_prefix("!") {
      // The one operation that refuses instead of answering an infinity: a
      // quotient by zero, for a caller who asked to be told rather than to read
      // an infinity.
      let key = c.divide(a, b).to_string() catch {
          (err : Refused) => refused_key(err)
        }
      check("the refusal of \{call}", key, wanted)
      continue
    }
    let got = domain_answer(name, a, b, c)
    expect_same(call, got, wanted, width)
  }
}
