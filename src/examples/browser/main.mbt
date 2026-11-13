// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The engine behind `docs/playground.html`: four functions, each one a call into
// the library and a string back. The page formats nothing of its own — a number
// on that page is a number this package computed.
//
// It is built for the browser only, from the docs workflow, into `docs/engine/`.

///|
/// The digits of `numerator / denominator` after the point, exactly rounded.
pub fn expand(numerator : Int, denominator : Int, places : Int) -> String {
  if denominator == 0 {
    return "a fraction needs a denominator that is not zero"
  }
  let count = if places < 0 { 0 } else if places > 2000 { 2000 } else { places }
  let value = @moonnum.Fraction::new(
    @bigint.BigInt::from_int(numerator),
    @bigint.BigInt::from_int(denominator),
  ) catch {
    (err : @moonnum.Refused) => return err.to_string()
  }
  let spec = "." + count.to_string() + "f"
  @moonnum.format(@moonnum.Number::Fraction(value), spec) catch {
    (err : @moonnum.Refused) => err.to_string()
  }
}

///|
/// Pi, to the number of places asked for, computed at a width that holds them.
pub fn pi(places : Int) -> String {
  let count = if places < 1 { 1 } else if places > 2000 { 2000 } else { places }
  let bits = count * 3322 / 1000 + 64
  @moonnum.BigFloat::pi(context=@moonnum.Context::new(bits)).to_decimal(count)
}

///|
/// `text` under the format specification `spec`, or the reason it was refused.
pub fn format(text : String, spec : String) -> String {
  let value = @moonnum.parse(text) catch {
    (err : @moonnum.Refused) => return err.to_string()
  }
  @moonnum.format(value, spec) catch {
    (err : @moonnum.Refused) => err.to_string()
  }
}

///|
/// What a double is: the shortest text that reads back, its exact value, and its
/// bits written as a hexadecimal float.
pub fn dissect(text : String) -> String {
  let value = @moonnum.parse_float(text) catch {
    (err : @moonnum.Refused) => return err.to_string()
  }
  let (numerator, denominator) = @moonnum.as_integer_ratio(value) catch {
    (err : @moonnum.Refused) => return err.to_string()
  }
  let whole = if @moonnum.is_integer(value) { "yes" } else { "no" }
  let out = StringBuilder()
  out.write_string("shortest text   " + @moonnum.repr_float(value) + "\n")
  out.write_string(
    "exact value     " + numerator.to_string() + " / " + denominator.to_string() +
    "\n",
  )
  out.write_string("hexadecimal     " + @moonnum.float_hex(value) + "\n")
  out.write_string("whole number    " + whole)
  out.to_string()
}
