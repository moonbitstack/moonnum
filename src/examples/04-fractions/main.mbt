// Exact rationals. Nothing here rounds unless you ask it to.
//
//     moon run src/examples/04-fractions

///|
fn main raise {
  // Arithmetic stays exact, so a third plus a sixth is a half and not
  // 0.49999999999999994.
  let third = @moonnum.parse_fraction("1/3")
  let sixth = @moonnum.parse_fraction("1/6")
  println("1/3 + 1/6 = \{(third + sixth)}")
  println("1/3 * 3   = \{(third * @moonnum.parse_fraction("3"))}")
  println("1/3 + 0.5 = \{(third + @moonnum.parse_fraction("0.5"))}")

  // A decimal literal is read as a power of ten, not through a float, so 0.1
  // is exactly one tenth here.
  println("")
  let tenth = @moonnum.parse_fraction("0.1")
  println("0.1 as a fraction: \{tenth}")
  println("0.1 + 0.2 = \{(tenth + @moonnum.parse_fraction("0.2"))}")
  println("as a double, 0.1 is: \{@moonnum.repr_float(0.1)}")
  println("and its exact value: \{@moonnum.as_ratio(0.1)}")

  // Converting a float keeps every bit; converting a fraction can overflow.
  println("")
  println("of_float(1.5) = \{@moonnum.Fraction::of_float(1.5)}")
  println("to_double(1/3) = \{@moonnum.repr_float(third.to_double())}")

  // Rounding is half to even, and it returns a fraction.
  println("")
  println("round(7/2) = \{@moonnum.parse_fraction("7/2").round_big()}")
  println("round(5/2) = \{@moonnum.parse_fraction("5/2").round_big()}")
  println("round(1/3, 3) = \{third.round(ndigits=3)}")
  println("floor(-7/2) = \{@moonnum.parse_fraction("-7/2").floor_big()}")
  println("ceil(-7/2)  = \{@moonnum.parse_fraction("-7/2").ceil_big()}")

  // A power keeps the value a ratio: the exponent goes to the numerator and
  // the denominator separately, so nothing is rounded on the way.
  println("")
  let two_thirds = @moonnum.parse_fraction("2/3")
  println("(2/3) ** 3  = \{two_thirds.pow(3N)}")
  println("(2/3) ** -1 = \{two_thirds.pow(-1N)}")
  println("(7/2) ** 10 = \{@moonnum.parse_fraction("7/2").pow(10N)}")
  let zero_power : String = @moonnum.parse_fraction("0").pow(-1N).to_string() catch {
      @moonnum.ZeroDivision => "division by zero"
      _ => "refused"
    }
  println("0 ** -1     = \{zero_power}")

  // The best rational approximation with a small denominator: the way to turn
  // 3.141592653589793 into 355/113.
  println("")
  let pi = @moonnum.as_ratio(3.141592653589793)
  println("pi as a fraction: \{pi}")
  println("with denominator <= 10:   \{pi.limit_denominator(max=10N)}")
  println("with denominator <= 1000: \{pi.limit_denominator(max=1000N)}")

  // Formatting either prints the ratio or rounds it like a float.
  println("")
  println("default:  \{third.format("")}")
  println(".6f:      \{third.format(".6f")}")
  println(">12.4f:   |\{third.format(">12.4f")}|")
  println(".3%:      \{third.format(".3%")}")
  println("#:        \{@moonnum.parse_fraction("5/2").format("#")}")
}
