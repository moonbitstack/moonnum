// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The interop run: every value here is computed twice, once by this library and
// once by CPython from the same expression, and the two texts have to agree.
//
// The program also reads every text it prints back, so the exchange is both
// directions: what we write, Python has to read as the same value, and what we
// read is the text Python writes. `scripts/check_interop.py` runs this program,
// evaluates the expressions on the left, and compares.

///|
/// A row of the exchange: which kind of value it is, the expression CPython
/// evaluates, and the text this library printed for it.
fn emit(kind : String, expression : String, text : String) -> Unit {
  println(kind + "\t" + expression + "\t" + text)
}

///|
fn emit_int(expression : String, value : @bigint.BigInt) -> Unit raise {
  let text = value.to_string()
  // The other direction: the text we just wrote, read back by us, is the value.
  let back = @moonnum.parse_int(text) catch {
    _ => fail("cannot read back \{text}")
  }
  if back != value {
    fail("\{text} reads back as \{back}")
  }
  emit("int", expression, text)
}

///|
fn emit_radix(
  expression : String,
  radix : Int32,
  value : @bigint.BigInt,
) -> Unit raise {
  let text = @moonnum.to_radix(value, radix~) catch {
    _ => fail("to_radix refused")
  }
  let back = @moonnum.parse_int(text, base=radix) catch {
    _ => fail("cannot read back \{text}")
  }
  if back != value {
    fail("\{text} in base \{radix} reads back as \{back}")
  }
  emit("radix" + radix.to_string(), expression, text)
}

///|
fn emit_float(expression : String, value : Double) -> Unit raise {
  let text = @moonnum.repr_float(value)
  let back = @moonnum.parse_float(text) catch {
    _ => fail("cannot read back \{text}")
  }
  if @moonnum.repr_float(back) != text {
    fail("\{text} reads back as \{@moonnum.repr_float(back)}")
  }
  emit("float", expression, text)
}

///|
fn emit_complex(expression : String, value : @moonnum.Complex) -> Unit raise {
  let text = value.to_string()
  let back = @moonnum.parse_complex(text) catch {
    _ => fail("cannot read back \{text}")
  }
  if back != value {
    fail("\{text} reads back as \{back}")
  }
  emit("complex", expression, text)
}

///|
fn emit_fraction(expression : String, value : @moonnum.Fraction) -> Unit raise {
  let text = value.to_string()
  let back = @moonnum.parse_fraction(text) catch {
    _ => fail("cannot read back \{text}")
  }
  if back != value {
    fail("\{text} reads back as \{back}")
  }
  emit("fraction", expression, text)
}

///|
fn emit_ratio(expression : String, value : @moonnum.Fraction) -> Unit {
  let (numerator, denominator) = value.as_integer_ratio()
  emit(
    "ratio",
    expression,
    numerator.to_string() + "/" + denominator.to_string(),
  )
}

///|
fn emit_bool(expression : String, value : Bool) -> Unit {
  emit("bool", expression, if value { "true" } else { "false" })
}

///|
fn emit_text(kind : String, expression : String, text : String) -> Unit {
  emit(kind, expression, text)
}

///|
fn hex_of(bytes : Bytes) -> String {
  let alphabet = "0123456789abcdef"
  let out = StringBuilder()
  for i = 0; i < bytes.length(); i = i + 1 {
    let byte = bytes[i].to_int()
    out.write_char(alphabet.get_char(byte / 16).unwrap())
    out.write_char(alphabet.get_char(byte % 16).unwrap())
  }
  out.to_string()
}

///|
fn main raise {
  // Integers: reading, division, powers with and without a modulus, the
  // number-theoretic functions, and the two counts.
  emit_int("int('0xff_ec', 0)", @moonnum.parse_int("0xff_ec", base=0))
  emit_int("int(' 1_000 ', 0)", @moonnum.parse_int(" 1_000 ", base=0))
  emit_int("int('-0b1010', 2)", @moonnum.parse_int("-0b1010", base=2))
  emit_int("int('1kaps', 32)", @moonnum.parse_int("1kaps", base=32))
  emit_int(
    "(10**40 + 7) // 3",
    @moonnum.floordiv(
      @moonnum.parse_int("10000000000000000000000000000000000000007"),
      @moonnum.parse_int("3"),
    ),
  )
  emit_int(
    "-10**40 % 7",
    @moonnum.floor_mod(
      @moonnum.parse_int("-10000000000000000000000000000000000000000"),
      @moonnum.parse_int("7"),
    ),
  )
  emit_int(
    "pow(3, -1, 7)",
    @moonnum.power(
      @moonnum.parse_int("3"),
      @moonnum.parse_int("-1"),
      modulus=@moonnum.parse_int("7"),
    ),
  )
  emit_int(
    "pow(2, 1000, 97)",
    @moonnum.power(
      @moonnum.parse_int("2"),
      @moonnum.parse_int("1000"),
      modulus=@moonnum.parse_int("97"),
    ),
  )
  emit_int(
    "math.isqrt(10**40)",
    @moonnum.isqrt(@moonnum.parse_int("1" + "0".repeat(40))),
  )
  emit_int("math.factorial(30)", @moonnum.factorial(@moonnum.parse_int("30")))
  emit_int(
    "math.comb(100, 50)",
    @moonnum.comb(@moonnum.parse_int("100"), @moonnum.parse_int("50")),
  )
  emit_int(
    "math.gcd(2**100, 6**50)",
    @moonnum.gcd(
      @moonnum.power(@moonnum.parse_int("2"), @moonnum.parse_int("100")),
      @moonnum.power(@moonnum.parse_int("6"), @moonnum.parse_int("50")),
    ),
  )
  emit_int(
    "math.lcm(2**100, 6**50)",
    @moonnum.lcm(
      @moonnum.power(@moonnum.parse_int("2"), @moonnum.parse_int("100")),
      @moonnum.power(@moonnum.parse_int("6"), @moonnum.parse_int("50")),
    ),
  )
  emit_int(
    "(2**256 - 1).bit_count()",
    @bigint.BigInt::from_int(
      @moonnum.bit_count(
        @moonnum.parse_int(
          "115792089237316195423570985008687907853269984665640564039457584007913129639935",
        ),
      ),
    ),
  )
  emit_int(
    "(10**40 + 7).bit_length()",
    @bigint.BigInt::from_int(
      @moonnum.bit_length(
        @moonnum.parse_int("10000000000000000000000000000000000000007"),
      ),
    ),
  )
  emit_text(
    "text",
    "(12345678901234567890).to_bytes(9, 'big').hex()",
    hex_of(
      @moonnum.to_bytes(@moonnum.parse_int("12345678901234567890"), length=9),
    ),
  )
  emit_int(
    "len(str(10**40 + 7)) - 1",
    @bigint.BigInt::from_int(
      @moonnum.ilog(
        @moonnum.parse_int("10000000000000000000000000000000000000007"),
        base=@moonnum.parse_int("10"),
      ),
    ),
  )
  // A whole base for every digit Python's `int(s, base)` reads.
  emit_radix("0x1a2b3c", 32, @moonnum.parse_int("0x1a2b3c", base=0))
  emit_radix("-255", 16, @moonnum.parse_int("-255"))
  emit_radix(
    "10**30",
    36,
    @moonnum.power(@moonnum.parse_int("10"), @moonnum.parse_int("30")),
  )
  emit_radix("12345", 7, @moonnum.parse_int("12345"))
  emit_radix(
    "2**64",
    2,
    @moonnum.power(@moonnum.parse_int("2"), @moonnum.parse_int("64")),
  )

  // Floats: the shortest text that reads back, the exact form, and the two
  // directions through a ratio.
  emit_float("0.1 + 0.2", 0.1 + 0.2)
  emit_float("0.1", 0.1)
  emit_float("1e16", 1.0e16)
  emit_float("1e-5", 1.0e-5)
  emit_float("1.7976931348623157e308", 1.7976931348623157e308)
  emit_float("5e-324", 5.0e-324)
  emit_float("float('1e-320')", @moonnum.parse_float("1e-320"))
  emit_float("1/3", 1.0 / 3.0)
  emit_float("-0.0", -0.0)
  emit_float("float('inf')", @moonnum.parse_float("inf"))
  emit_float("round(2.675, 2)", @moonnum.round_float(2.675, ndigits=2))
  emit_text("text", "(0.1).hex()", @moonnum.float_hex(0.1))
  emit_ratio("(0.1).as_integer_ratio()", @moonnum.as_ratio(0.1))
  emit_bool("(2.0).is_integer()", @moonnum.is_integer(2.0))
  emit_bool("(2.5).is_integer()", @moonnum.is_integer(2.5))

  // Complex numbers: reading, the arithmetic, and the signed zeros.
  emit_complex("complex('3+4j')", @moonnum.parse_complex("3+4j"))
  emit_complex("complex('1e3j')", @moonnum.parse_complex("1e3j"))
  emit_complex("complex('-0-1j')", @moonnum.parse_complex("-0-1j"))
  emit_complex(
    "complex(3, 4) ** 2",
    @moonnum.parse_complex("3+4j").pow(@moonnum.parse_complex("2")),
  )
  emit_text(
    "text",
    "abs(complex(3, 4))",
    @moonnum.repr_float(@moonnum.parse_complex("3+4j").abs()),
  )

  // Fractions: the canonical spelling, the power that stays exact, and the
  // truncation towards zero.
  emit_fraction("Fraction('22/7')", @moonnum.parse_fraction("22/7"))
  emit_fraction(
    "Fraction(2, 3) ** 100",
    @moonnum.parse_fraction("2/3").pow(@moonnum.parse_int("100")),
  )
  emit_fraction("Fraction('1.5')", @moonnum.parse_fraction("1.5"))
  emit_fraction("Fraction(-7, 2)", @moonnum.parse_fraction("-7/2"))
  emit_ratio(
    "Fraction(-7, 2).as_integer_ratio()",
    @moonnum.parse_fraction("-7/2"),
  )
  emit_int(
    "math.trunc(Fraction(-7, 2))",
    @moonnum.parse_fraction("-7/2").trunc_big(),
  )

  // The format language, on numbers CPython also formats.
  emit_text(
    "text",
    "format(1234567, '015,d')",
    @moonnum.format_int(@moonnum.parse_int("1234567"), "015,d"),
  )
  emit_text(
    "text",
    "format(255, '#010_x')",
    @moonnum.format_int(@moonnum.parse_int("255"), "#010_x"),
  )
  emit_text("text", "format(-0.0, 'z')", @moonnum.format_float(-0.0, "z"))
  emit_text(
    "text",
    "format(complex(3, 4), '.2f')",
    @moonnum.parse_complex("3+4j").format(".2f"),
  )
  emit_text(
    "text",
    "format(0.1, '.3%')",
    @moonnum.format(@moonnum.parse("0.1"), ".3%"),
  )
  emit_text(
    "text",
    "format(Fraction(22, 7), '.6f')",
    @moonnum.parse_fraction("22/7").format(".6f"),
  )
}
