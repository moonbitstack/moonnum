// A real number carried to a width you choose, and the functions that need one.
//
//     moon run src/examples/06-bigfloat

///|
fn main raise {
  let c = @moonnum.Context::new(200)

  // A double is a value of 53 bits; the same decimal at 200 bits is the decimal,
  // to 200 bits, and says where it stops.
  println("the same text at two widths")
  println("  as a double: \{@moonnum.BigFloat::of_double(0.1)}")
  println(
    "  at 200 bits: \{@moonnum.BigFloat::parse("0.1", context=c).to_decimal(60)}",
  )

  // An operator keeps the wider of its two operands, so a third is as long a
  // decimal as the wider operand can answer for.
  println("")
  println("width of a third")
  let narrow = @moonnum.BigFloat::one()
  let wide = @moonnum.BigFloat::one(context=c)
  let three = @moonnum.BigFloat::of_int(3)
  println("  at 53 bits:  \{narrow / three}")
  println("  and a 200-bit operand in the sum: \{(wide + wide) / three}")

  // A context decides the width and the direction both. One plus a half of the
  // last place is the case where the two directions disagree.
  println("")
  println("one tie, five directions")
  let one = @moonnum.BigFloat::one(context=c)
  let half_place = @moonnum.BigFloat::parse(
    "1.1102230246251565404236316680908203125e-16",
    context=c,
  )
  for
    rounding in [
      @moonnum.Rounding::Nearest,
      @moonnum.Rounding::Floor,
      @moonnum.Rounding::Ceiling,
      @moonnum.Rounding::Down,
      @moonnum.Rounding::Up,
    ] {
    let context = @moonnum.Context::new(53, rounding~)
    let sum = context.add(one, half_place)
    println("  \{rounding}: \{sum.to_significant(17)}")
  }

  // The functions, at a width a double cannot hold.
  println("")
  println("the functions at 200 bits")
  let two = @moonnum.BigFloat::of_int(2, context=c)
  println("  sqrt 2 = \{two.sqrt(context=c).to_significant(60)}")
  println("  e      = \{@moonnum.BigFloat::e(context=c).to_significant(60)}")
  println("  pi     = \{@moonnum.BigFloat::pi(context=c).to_significant(60)}")
  println("  ln 2   = \{@moonnum.BigFloat::ln2(context=c).to_significant(60)}")
  println(
    "  2^0.5  = \{two.pow(@moonnum.BigFloat::of_double(0.5), context=c).to_significant(60)}",
  )

  // A thousand digits is a width, not a special case; nothing here is read from
  // a table of digits someone typed in.
  println("")
  println("a thousand digits of pi")
  let thousand = @moonnum.Context::new(3322)
  println("  \{@moonnum.BigFloat::pi(context=thousand).to_decimal(80)}")

  // The circular functions reduce the argument against a turn carried to as many
  // bits as the argument has before its point.
  println("")
  println("the circular functions")
  let one_radian = @moonnum.BigFloat::one(context=c)
  println("  sin 1 = \{one_radian.sin(context=c).to_significant(40)}")
  println("  cos 1 = \{one_radian.cos(context=c).to_significant(40)}")
  println("  atan 1 = \{one_radian.atan(context=c).to_significant(40)}")
  println(
    "  sin 1e30 = \{@moonnum.BigFloat::parse("1e30", context=c).sin(context=c).to_significant(20)}",
  )
  println("  sinh 1 = \{one_radian.sinh(context=c).to_significant(40)}")
  println("  asinh 1 = \{one_radian.asinh(context=c).to_significant(40)}")

  // Where a real value does not exist, the answer says so.
  println("")
  println("where there is no value")
  println("  sqrt(-1) = \{(-one).sqrt(context=c)}")
  println("  ln(0)    = \{@moonnum.BigFloat::zero(context=c).ln(context=c)}")
  println("  1/0      = \{one / @moonnum.BigFloat::zero(context=c)}")
  let refused = one.divide(@moonnum.BigFloat::zero(context=c)).to_string() catch {
      @moonnum.ZeroDivision => "division by zero"
      _ => "answered"
    }
  println("  divide() says: \{refused}")

  // The other shapes the library and the host already speak.
  println("")
  println("in and out of the other shapes")
  println("  to a double:  \{two.sqrt(context=c).to_double()}")
  println(
    "  to an integer: \{@moonnum.BigFloat::parse("2.5", context=c).to_bigint()}",
  )
  let fixed = two.sqrt(context=c).to_fixed(@moonnum.Fixed::bits_for_digits(20))
  println("  to a fixed point: \{fixed}")
  println(
    "  from a whole: \{@moonnum.BigFloat::of_bigint(@moonnum.parse_int("123456789012345678901234567890"), context=c)}",
  )
}
