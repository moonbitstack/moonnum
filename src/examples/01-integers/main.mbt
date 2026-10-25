// Integers without a width.
//
//     moon run src/examples/01-integers

///|
fn main raise {
  // Nothing here overflows: the digits grow until memory runs out.
  let hundred = @moonnum.parse_int("100")
  println("50! = \{@moonnum.factorial(50N)}")
  println("2^200 = \{@moonnum.power(2N, 200N)}")
  println("C(100, 50) = \{@moonnum.comb(hundred, 50N)}")
  println("isqrt(10^40) = \{@moonnum.isqrt(@moonnum.power(10N, 40N))}")

  // Floor division and modulo agree, whatever the signs are.
  println("")
  println("  a     b   a//b   a%b")
  for (a, b) in [(7N, 2N), (-7N, 2N), (7N, -2N), (-7N, -2N)] {
    let (q, r) = @moonnum.divmod(a, b)
    println("  \{a}   \{b}    \{q}    \{r}")
  }

  // A negative exponent with a modulus is a modular inverse, not a fraction.
  println("")
  println("3^-1 mod 7 = \{@moonnum.power(3N, -1N, modulus=7N)}")
  println("2^1000 mod 97 = \{@moonnum.power(2N, 1000N, modulus=97N)}")

  // Reading and writing other bases, with the spellings Python accepts.
  println("")
  let value = @moonnum.parse_int("0xff_ec", base=0)
  println("0xff_ec = \{value}")
  println("base 2:  \{value.to_string(radix=2)}")
  println("base 36: \{value.to_string(radix=36)}")

  // Bytes are two's complement when asked, big-endian unless told otherwise.
  println("")
  let bytes = @moonnum.to_bytes(-2N, length=4, signed=true)
  println("(-2).to_bytes(4, signed=True) = \{hex_of(bytes)}")
  println("read back: \{@moonnum.of_bytes(bytes, signed=true)}")

  // Refusals are values, so a bad literal is a branch and not a crash.
  println("")
  let broken : String = @moonnum.parse_int("12x", base=0).to_string() catch {
    @moonnum.Malformed(at~, reason~) => "refused at \{at}: \{reason}"
    _ => "refused"
  }
  println("\"12x\" -> \{broken}")
}

///|
/// Hex, for printing byte arrays.
fn hex_of(bytes : Bytes) -> String {
  let alphabet = "0123456789abcdef"
  let sb = StringBuilder()
  for byte in bytes {
    let value = byte.to_int()
    sb.write_char(alphabet.get_char(value / 16).unwrap())
    sb.write_char(alphabet.get_char(value % 16).unwrap())
  }
  sb.to_string()
}
