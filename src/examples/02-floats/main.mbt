// Floats, written the way Python writes them.
//
//     moon run src/examples/02-floats

///|
fn main raise {
  // repr_float is the shortest string that reads back as the same double, and
  // it switches to an exponent exactly where Python does.
  println("shortest round trip")
  for value in [42.0, 0.1, 1.0 / 3.0, 1.0e15, 1.0e16, 1.0e-4, 1.0e-5, -0.0] {
    println("  \{@moonnum.repr_float(value)}")
  }

  // The same text goes back in, bit for bit.
  println("")
  println(
    "round trip of 0.1: \{@moonnum.parse_float(@moonnum.repr_float(0.1)) == 0.1}",
  )

  // Infinities and NaN have names, and they survive the trip.
  println("")
  println("inf  = \{@moonnum.repr_float(@moonnum.parse_float("infinity"))}")
  println("-inf = \{@moonnum.repr_float(@moonnum.parse_float("-inf"))}")
  println("nan  = \{@moonnum.repr_float(@moonnum.parse_float("nan"))}")
  println(
    "nan == nan: \{@moonnum.parse_float("nan") == @moonnum.parse_float("nan")}",
  )

  // The hexadecimal form is exact and short.
  println("")
  println("0.1 in hex: \{@moonnum.float_hex(0.1)}")
  println(
    "read back:  \{@moonnum.repr_float(@moonnum.float_of_hex("0x1.999999999999ap-4"))}",
  )

  // Rounding is half to even on the exact value, not on the printed one.
  println("")
  println(
    "round(2.675, 2) = \{@moonnum.repr_float(@moonnum.round_float(2.675, ndigits=2))}",
  )
  println("round(0.5)      = \{@moonnum.round_big(0.5)}")
  println("round(1.5)      = \{@moonnum.round_big(1.5)}")
  println("round(-2.5)     = \{@moonnum.round_big(-2.5)}")

  // Floor, ceiling and truncation give integers, and they are exact.
  println("")
  println("floor(-1.2) = \{@moonnum.floor_big(-1.2)}")
  println("ceil(-1.2)  = \{@moonnum.ceil_big(-1.2)}")
  println("trunc(-1.2) = \{@moonnum.trunc_big(-1.2)}")
  // 1.0e30 is not ten to the thirtieth, and the integer says by how much.
  println("floor(1.0e30) = \{@moonnum.floor_big(1.0e30)}")

  // A float is a rational whose denominator is a power of two. This is where
  // 0.1 + 0.2 comes from.
  println("")
  let ratio = @moonnum.as_ratio(0.1)
  println("0.1 = \{ratio.num}/\{ratio.den}")
  println("0.1 + 0.2 = \{@moonnum.repr_float(0.1 + 0.2)}")
}
