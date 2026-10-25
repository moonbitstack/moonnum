// Complex numbers, written `3+4j` and read `3+5i`.
//
//     moon run src/examples/03-complex

///|
fn main raise {
  // Every spelling Python accepts, plus the `i` suffix this library adds.
  println("spellings")
  for text in ["1+2j", "(1+2j)", "2j", "j", "-j", "1e3j", "3+5i", "+2j"] {
    let z = @moonnum.parse_complex(text)
    println("  \{text} -> \{z}")
  }

  // The repr is Python's: no parentheses when the real part is a positive zero,
  // and a forced sign on the imaginary part otherwise.
  println("")
  let z = @moonnum.parse_complex("3+4j")
  println("z       = \{z}")
  println("z + 1   = \{z + @moonnum.Complex::new(1.0, 0.0)}")
  println("z * z   = \{z * z}")
  println("z / z   = \{z.divide(z)}")
  println("|z|     = \{@moonnum.repr_float(z.abs())}")
  println("conj z  = \{z.conjugate()}")

  // Mixing kinds is the tower's job, and `Number` is where the tower lives.
  let mixed = @moonnum.parse("1") + @moonnum.parse("3+4j")
  println("1 + (3+4j) = \{mixed}")

  // Division by zero has no answer, and says so.
  println("")
  let zero = @moonnum.parse_complex("0j")
  let divided : String = z.divide(zero).to_string() catch {
      @moonnum.ZeroDivision => "ZeroDivision"
      _ => "refused"
    }
  println("z / 0j: \{divided}")

  // An integer exponent uses repeated squaring, so 2j squared is exactly -4+0j
  // instead of a polar-form approximation.
  println("")
  let one_plus_i = @moonnum.parse_complex("1+1j")
  let two = @moonnum.parse_complex("2")
  let two_point_zero = @moonnum.parse_complex("2.0")
  println("(1+1j) ** 2   = \{one_plus_i.pow(two)}")
  println("(1+1j) ** 2.0 = \{one_plus_i.pow(two_point_zero)}")

  // Formatting applies the specifier to both halves and keeps Python's sign
  // rules: the imaginary part always gets a sign, the real part follows you.
  println("")
  println("default:  \{z.format("")}")
  println(".2f:      \{z.format(".2f")}")
  println("+9.2f:    \{z.format("+9.2f")}")
  println("<14.1e:   \{z.format("<14.1e")}")
}
