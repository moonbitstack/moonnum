// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The program behind `docs/guide.html`: every block on that page is a run of
// this program, printed here in the order the page reads. `scripts/check_docs.py
// --examples` compares the numbers the page prints with what this prints, so a
// page that has drifted from the code fails the build.

///|
fn main raise {
  // 1. Reading a number, and what it is.
  let count = @moonnum.parse_int("0xff_ec", base=0)
  println("\{count} and \{count.bit_length()} bits wide")

  // 2. Four kinds from one parser, and the tower between them.
  for text in ["7", "1/3", "0.5", "3+4j"] {
    let value = @moonnum.parse(text)
    println("\{text} -> \{value}")
  }
  let mixed = @moonnum.parse("1") +
    @moonnum.parse("1/3") +
    @moonnum.parse("0.5")
  println("1 + 1/3 + 0.5 = \{mixed}")
  let bigger = @moonnum.parse("9007199254740993").compare_numeric(
      @moonnum.parse("9007199254740992.0"),
    ) >
    0
  println("9007199254740993 > 9007199254740992.0 is \{bigger}")

  // 3. Integer division that agrees with itself.
  let (quotient, remainder) = @moonnum.divmod(-7N, 2N)
  println("-7 // 2 = \{quotient}, -7 % 2 = \{remainder}")
  println("-7 // 2 * 2 + -7 % 2 = \{quotient * 2N + remainder}")

  // 4. Powers, roots and counts.
  println(@moonnum.power(3N, -1N, modulus=7N).to_string())
  println(@moonnum.power(2N, 1000N, modulus=97N).to_string())
  println(@moonnum.isqrt(@moonnum.power(10N, 40N)).to_string())
  println(@moonnum.comb(@moonnum.parse_int("100"), 50N).to_string())
  println(@moonnum.bit_count(255N).to_string())

  // 5. Writing an integer in another base.
  println(@moonnum.to_radix(0x1a2b3cN, radix=32))
  println(@moonnum.to_radix(-255N, radix=16))
  println(
    @moonnum.ilog(
      @moonnum.parse_int("10000000000000000000000000000000000000007"),
    ).to_string(),
  )

  // 6. A float, read and written honestly.
  println(@moonnum.repr_float(0.1))
  println(@moonnum.repr_float(0.1 + 0.2))
  println(@moonnum.float_hex(0.1))
  let (numerator, denominator) = @moonnum.as_integer_ratio(0.1)
  println("\{numerator}/\{denominator}")
  println(@moonnum.is_integer(2.5).to_string())

  // 7. Rounding, which is not the same as printing.
  println(@moonnum.round_float(2.675, ndigits=2).to_string())
  println(@moonnum.round_float(0.5, ndigits=0).to_string())
  println(@moonnum.round_float(1.5, ndigits=0).to_string())

  // 8. Complex numbers, written the way people write them.
  let z = @moonnum.parse_complex("3+4j")
  println(z.to_string())
  println((z * z).to_string())
  println(z.abs().to_string())
  println(@moonnum.repr_complex(@moonnum.parse_complex("-0-1j")))

  // 9. Fractions that stay exact.
  let third = @moonnum.parse_fraction("1/3")
  println((third + third + third).to_string())
  println(@moonnum.parse_fraction("0.1").to_string())
  println(third.limit_denominator(max=100N).to_string())
  println(@moonnum.format(@moonnum.parse("22/7"), ".6f"))

  // 10. The format language.
  println(@moonnum.format_int(1234567N, "015,d"))
  println(@moonnum.format_int(255N, "#010_x"))
  println(@moonnum.format_float(0.25, ".2%"))
  println(@moonnum.format_float(-0.0, "z"))
  println(@moonnum.format_float(1234.5678, ">12.2f"))

  // 11. A real at a width the caller chooses.
  let bits = @moonnum.Fixed::bits_for_digits(50)
  let two = @moonnum.Fixed::of_int(2, bits)
  println(two.sqrt().to_string())
  println((two * @moonnum.Fixed::pi(bits)).to_decimal(10))

  // 12. A real at any width, and its wider field.
  let c = @moonnum.Context::new(200)
  let big = @moonnum.BigFloat::of_int(2, context=c)
  println(big.sqrt(context=c).to_significant(40))
  println(@moonnum.BigFloat::pi(context=c).to_significant(40))
  println(big.cbrt(context=c).to_significant(40))
  println(@moonnum.BigFloat::ln10(context=c).to_significant(40))
  println(big.powi(10N, context=c).to_significant(40))

  // 13. When the answer is complex, the complex type says so.
  let minus_one = -@moonnum.BigFloat::one(context=c)
  println(minus_one.sqrt(context=c).to_string())
  println(minus_one.to_complex().sqrt(context=c).to_string())

  // 14. A refusal says no, and says why.
  let refused = @moonnum.parse_int("12x", base=0).to_string() catch {
    @moonnum.Malformed(at~, reason~) => "\{reason} at \{at}"
    _ => "refused"
  }
  println(refused)
}
