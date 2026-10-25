// The format-specification mini-language, one flag at a time.
//
//     moon run src/examples/05-format

///|
fn main raise {
  let n = @moonnum.parse_int("1234567")

  // Width, fill and alignment.
  println("width and alignment")
  println("|" + @moonnum.format_int(n, "15d") + "|")
  println("|" + @moonnum.format_int(n, "<15d") + "|")
  println("|" + @moonnum.format_int(n, "^15d") + "|")
  println("|" + @moonnum.format_int(n, "*^15d") + "|")
  println("|" + @moonnum.format_int(n, "0>15d") + "|")

  // Sign, and the zero flag, which pads after the sign and before the digits.
  println("")
  println("sign and zero padding")
  println("|" + @moonnum.format_int(n, "+15d") + "|")
  println("|" + @moonnum.format_int(-n, "+15d") + "|")
  println("|" + @moonnum.format_int(n, "015d") + "|")
  println("|" + @moonnum.format_int(-n, "015d") + "|")
  println("|" + @moonnum.format_int(n, " 15d") + "|")

  // Thousands separators, and what happens when zero padding meets them.
  println("")
  println("grouping")
  println(@moonnum.format_int(n, ",d"))
  println(@moonnum.format_int(n, "_d"))
  println(@moonnum.format_int(n, "015,d"))
  println(@moonnum.format_int(@moonnum.parse_int("255"), "_b"))
  println(@moonnum.format_int(@moonnum.parse_int("255"), "#010_x"))

  // Every presentation type for integers.
  println("")
  println("types")
  for type_char in ["b", "o", "d", "x", "X", "n", "c"] {
    let spec = if type_char == "c" {
      @moonnum.format_int(@moonnum.parse_int("65"), type_char)
    } else {
      @moonnum.format_int(@moonnum.parse_int("255"), type_char)
    }
    println("  \{type_char}: \{spec}")
  }

  // Floats: precision means digits after the point for `f`, significant digits
  // for `g`, and always an exponent for `e`.
  println("")
  println("float types")
  let x = 1234.5678
  println("  value: \{x}")
  for spec in ["f", ".2f", "e", ".3e", "g", ".3g", "%", ".1%", ",.2f"] {
    println("  \{spec}: \{@moonnum.format_float(x, spec)}")
  }

  println("  .2% of 0.25: \{@moonnum.format_float(0.25, ".2%")}")

  // The alternate form keeps zeros that `g` would drop, and always keeps the
  // decimal point.
  println("")
  println("alternate form")
  println("  g   of 1.5: " + @moonnum.format_float(1.5, "g"))
  println("  #g  of 1.5: " + @moonnum.format_float(1.5, "#g"))
  println("  g   of 2.0: " + @moonnum.format_float(2.0, "g"))
  println("  #g  of 2.0: " + @moonnum.format_float(2.0, "#g"))
  println("  #.0f of 2.0: " + @moonnum.format_float(2.0, "#.0f"))

  // `z` turns a negative zero into a zero, which is what a fixed-point table
  // wants when the value rounds away.
  println("")
  println("negative zero")
  println("  -0.0     -> " + @moonnum.format_float(-0.0, ""))
  println("  -0.0  z  -> " + @moonnum.format_float(-0.0, "z"))
  println("  -.0001 z.2f -> " + @moonnum.format_float(-0.0001, "z.2f"))

  // One entry point, whatever the number happens to be.
  println("")
  println("one entry point")
  for text in ["42", "-0.5", "22/7", "3+4j"] {
    let value = @moonnum.parse(text)
    println("  \{text} -> " + @moonnum.format(value, ".3f"))
  }
}
