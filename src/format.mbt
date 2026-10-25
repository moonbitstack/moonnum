// Python's format-specification mini-language: parse the spec, then lay the
// number out in six parts.

///|
/// A parsed format specifier.
priv struct Spec {
  mut fill : Char
  mut align : Char
  mut sign : Char
  mut neg0 : Bool
  mut alt : Bool
  mut zero : Bool
  mut width : Int32
  mut group : Char
  mut precision : Int32
  mut ty : Char
  mut ty_at : Int32
}

///|
/// Whether `c` is one of the four alignment characters.
fn is_align(c : Char) -> Bool {
  c == '<' || c == '>' || c == '^' || c == '='
}

///|
/// Whether `c` is a presentation type this library knows.
fn is_type(c : Char) -> Bool {
  match c {
    'b'
    | 'c'
    | 'd'
    | 'e'
    | 'E'
    | 'f'
    | 'F'
    | 'g'
    | 'G'
    | 'n'
    | 'o'
    | 'x'
    | 'X'
    | '%' => true
    _ => false
  }
}

///|
/// Parse a format specifier, in CPython's order and with CPython's refusals.
fn parse_spec(text : StringView) -> Spec raise Refused {
  let s = text.to_owned()
  let n = s.length()
  let mut i = 0
  let spec : Spec = {
    fill: ' ',
    align: '>',
    sign: '\u{0}',
    neg0: false,
    alt: false,
    zero: false,
    width: -1,
    group: '\u{0}',
    precision: -1,
    ty: '\u{0}',
    ty_at: 0,
  }
  let mut align_given = false
  let mut fill_given = false
  if n >= 2 && is_align(s.get_char(1).unwrap()) {
    spec.fill = s.get_char(0).unwrap()
    spec.align = s.get_char(1).unwrap()
    fill_given = true
    align_given = true
    i = 2
    if spec.fill == '{' || spec.fill == '}' {
      malformed(0, "invalid fill character")
    }
  } else if n >= 1 && is_align(s.get_char(0).unwrap()) {
    spec.align = s.get_char(0).unwrap()
    align_given = true
    i = 1
  }
  if i < n {
    match s.get_char(i).unwrap() {
      '+' | '-' | ' ' => {
        spec.sign = s.get_char(i).unwrap()
        i += 1
      }
      _ => ()
    }
  }
  if i < n && s.get_char(i) == Some('z') {
    spec.neg0 = true
    i += 1
  }
  if i < n && s.get_char(i) == Some('#') {
    spec.alt = true
    i += 1
  }
  if !fill_given && i < n && s.get_char(i) == Some('0') {
    spec.fill = '0'
    if !align_given {
      spec.align = '='
    }
    i += 1
  }
  let mut width = 0
  let mut width_seen = false
  while i < n && is_digit(s.get_char(i).unwrap()) {
    width = width * 10 + s.get_char(i).unwrap().to_int() - '0'.to_int()
    width_seen = true
    i += 1
  }
  if width_seen {
    spec.width = width
  }
  spec.zero = spec.fill == '0' && spec.align == '='
  if i < n && s.get_char(i) == Some(',') {
    spec.group = ','
    i += 1
  }
  if i < n && s.get_char(i) == Some('_') {
    if spec.group != '\u{0}' {
      malformed(i, "cannot specify both ',' and '_'")
    }
    spec.group = '_'
    i += 1
  }
  if i < n && s.get_char(i) == Some('.') {
    let dot = i
    i += 1
    let mut precision = 0
    let mut seen = false
    while i < n && is_digit(s.get_char(i).unwrap()) {
      precision = precision * 10 +
        s.get_char(i).unwrap().to_int() -
        '0'.to_int()
      seen = true
      i += 1
    }
    if !seen {
      malformed(dot, "format specifier missing precision")
    }
    spec.precision = precision
  }
  if n - i > 1 {
    malformed(i, "invalid format specifier")
  }
  if n - i == 1 {
    let c = s.get_char(i).unwrap()
    if !is_type(c) {
      malformed(i, "unknown presentation type")
    }
    spec.ty = c
    spec.ty_at = i
    i += 1
  }
  let _ = i
  spec
}

///|
/// The width a digit string occupies once `sep` is inserted every `size`.
fn grouped_len(digits : Int32, size : Int32) -> Int32 {
  if digits <= 0 || size <= 0 {
    digits
  } else {
    digits + (digits - 1) / size
  }
}

///|
/// Split text into its sign and the rest.
fn split_sign(text : String) -> (Char, String) {
  if text.length() > 0 {
    match text.get_char(0).unwrap() {
      '-' => return ('-', slice(text, 1, text.length()))
      '+' => return ('+', slice(text, 1, text.length()))
      _ => ()
    }
  }
  ('\u{0}', text)
}

///|
/// Lay a formatted number out in a field: padding, sign, prefix, digits,
/// point and fraction, exponent.
///
/// Zero padding goes inside the sign and participates in grouping, which is why
/// this is not a call to `pad`.
fn layout_number(
  sign : Char,
  prefix : String,
  int_digits : String,
  tail : String,
  spec : Spec,
  sep : Char,
  size : Int32,
) -> String {
  let sign_text = if sign == '\u{0}' { "" } else { sign.to_string() }
  let fixed = sign_text.length() + prefix.length() + tail.length()
  let mut digits = int_digits
  let mut grouped = if sep == '\u{0}' || digits == "" {
    digits
  } else {
    group_digits(digits, sep, size)
  }
  if spec.zero && spec.width > 0 && digits != "" {
    let target = spec.width - fixed
    if grouped_len(digits.length(), if sep == '\u{0}' { 1 } else { size }) <
      target &&
      target > digits.length() {
      // Grow the digit run until the grouped width reaches the field.
      let wanted = target * size / (size + 1) + 1
      let mut estimate = wanted
      if estimate < digits.length() {
        estimate = digits.length()
      }
      let mut d = estimate
      while grouped_len(d, size) < target {
        d += 1
      }
      while d > digits.length() && grouped_len(d - 1, size) >= target {
        d -= 1
      }
      digits = repeat_char('0', d - digits.length()) + digits
      grouped = if sep == '\u{0}' {
        digits
      } else {
        group_digits(digits, sep, size)
      }
    }
  }
  let content = prefix + grouped + tail
  let padding = spec.width - sign_text.length() - content.length()
  if padding <= 0 {
    return sign_text + content
  }
  match spec.align {
    '<' => sign_text + content + repeat_char(spec.fill, padding)
    '^' => {
      let left = padding / 2
      repeat_char(spec.fill, left) +
      sign_text +
      content +
      repeat_char(spec.fill, padding - left)
    }
    // `=` pads inside the sign and the base prefix, not before them.
    '=' => sign_text + prefix + repeat_char(spec.fill, padding) + grouped + tail
    _ => repeat_char(spec.fill, padding) + sign_text + content
  }
}

///|
/// Fill an already-composed string to `spec.width`.
fn layout_text(text : String, spec : Spec) -> String {
  let padding = spec.width - text.length()
  if padding <= 0 {
    return text
  }
  match spec.align {
    '<' => text + repeat_char(spec.fill, padding)
    '^' => {
      let left = padding / 2
      repeat_char(spec.fill, left) +
      text +
      repeat_char(spec.fill, padding - left)
    }
    _ => repeat_char(spec.fill, padding) + text
  }
}

///|
/// The `sep` and group size for a presentation type: four for binary, octal and
/// hexadecimal digits, three everywhere else.
fn grouping_for(spec : Spec, ty : Char) -> (Char, Int32) {
  match spec.group {
    ',' => (',', 3)
    '_' =>
      match ty {
        'b' | 'o' | 'x' | 'X' => ('_', 4)
        _ => ('_', 3)
      }
    _ => ('\u{0}', 3)
  }
}

///|
/// The digits of `n` in `base`, uppercase when `upper`.
fn digits_in_base(n : @bigint.BigInt, base : Int32, upper : Bool) -> String {
  let text = n.to_string(radix=base)
  if upper {
    let sb = StringBuilder()
    let mut i = 0
    while i < text.length() {
      sb.write_char(text.get_char(i).unwrap().to_ascii_uppercase())
      i += 1
    }
    sb.to_string()
  } else {
    text
  }
}

///|
/// Format an integer, including the float types Python allows on integers by
/// converting them.
pub fn format_int(
  n : @bigint.BigInt,
  spec_text : StringView,
) -> String raise Refused {
  let spec = parse_spec(spec_text)
  let ty = if spec.ty == '\u{0}' { 'd' } else { spec.ty }
  match ty {
    'e' | 'E' | 'f' | 'F' | 'g' | 'G' | '%' => {
      let value = big_to_double(n)
      if value.is_inf() {
        raise Overflow(reason="int too large to convert to float")
      }
      format_float_with(value, spec, false)
    }
    'c' => {
      if spec.sign != '\u{0}' {
        malformed(spec.ty_at, "sign is not allowed with 'c'")
      }
      if spec.alt {
        malformed(spec.ty_at, "alternate form is not allowed with 'c'")
      }
      if spec.precision >= 0 {
        malformed(spec.ty_at, "precision is not allowed with 'c'")
      }
      if n < 0N || n > 0x10FFFFN {
        raise Overflow(reason="character argument not in range(0x110000)")
      }
      let code = n.to_int()
      let body = match code.to_char() {
        Some(c) => c.to_string()
        None =>
          raise Overflow(reason="character argument not in range(0x110000)")
      }
      // A width counts characters, and an astral character is still one of
      // them even though it occupies two UTF-16 units.
      let padding = spec.width - 1
      if padding <= 0 {
        body
      } else {
        match spec.align {
          '<' => body + repeat_char(spec.fill, padding)
          '^' => {
            let left = padding / 2
            repeat_char(spec.fill, left) +
            body +
            repeat_char(spec.fill, padding - left)
          }
          _ => repeat_char(spec.fill, padding) + body
        }
      }
    }
    _ => {
      if spec.precision >= 0 {
        malformed(spec.ty_at, "precision is not allowed for integers")
      }
      if spec.group == ',' && (ty == 'b' || ty == 'o' || ty == 'x' || ty == 'X') {
        malformed(spec.ty_at, "cannot specify ',' with this presentation type")
      }
      if spec.group != '\u{0}' && ty == 'n' {
        malformed(spec.ty_at, "cannot specify a grouping separator with 'n'")
      }
      if spec.neg0 {
        malformed(
          spec.ty_at,
          "negative-zero coercion is not allowed for integers",
        )
      }
      let negative = n < 0N
      let magnitude = if negative { -n } else { n }
      let (prefix, body) = match ty {
        'b' =>
          (
            if spec.alt {
              "0b"
            } else {
              ""
            },
            digits_in_base(magnitude, 2, false),
          )
        'o' =>
          (
            if spec.alt {
              "0o"
            } else {
              ""
            },
            digits_in_base(magnitude, 8, false),
          )
        'x' =>
          (
            if spec.alt {
              "0x"
            } else {
              ""
            },
            digits_in_base(magnitude, 16, false),
          )
        'X' =>
          (
            if spec.alt {
              "0X"
            } else {
              ""
            },
            digits_in_base(magnitude, 16, true),
          )
        _ => ("", magnitude.to_string())
      }
      let sign = if negative {
        '-'
      } else {
        match spec.sign {
          '+' => '+'
          ' ' => ' '
          _ => '\u{0}'
        }
      }
      let (sep, size) = grouping_for(spec, ty)
      layout_number(sign, prefix, body, "", spec, sep, size)
    }
  }
}

///|
/// The body of a float in `ty`, without any field padding.
fn float_component(
  d : Double,
  ty : Char,
  precision : Int32,
  alt : Bool,
  neg0 : Bool,
  always_sign : Bool,
) -> String {
  let mut code = 'r'
  let mut digits = 0
  let mut add_dot0 = false
  let mut upper = false
  let mut value = d
  let mut percent = false
  let given = if precision < 0 { 6 } else { precision }
  match ty {
    'r' => {
      code = 'r'
      add_dot0 = false
    }
    '\u{0}' =>
      if precision < 0 {
        code = 'r'
        add_dot0 = true
      } else {
        // A precision without a type keeps the "at least one digit after the
        // point" rule, and reads as `g` for everything else. `g` with a
        // precision of zero means one significant digit.
        code = 'g'
        digits = if given < 1 { 1 } else { given }
        add_dot0 = true
      }
    'e' => {
      code = 'e'
      digits = given + 1
    }
    'E' => {
      code = 'e'
      digits = given + 1
      upper = true
    }
    'f' => {
      code = 'f'
      digits = given
    }
    'F' => {
      code = 'f'
      digits = given
      upper = true
    }
    'g' => {
      code = 'g'
      digits = if given < 1 { 1 } else { given }
    }
    'G' => {
      code = 'g'
      digits = if given < 1 { 1 } else { given }
      upper = true
    }
    'n' => {
      code = 'g'
      digits = if given < 1 { 1 } else { given }
    }
    _ => {
      code = 'f'
      digits = given
      value = d * 100.0
      percent = true
    }
  }
  let text = float_short(
    value, code, digits, always_sign, add_dot0, alt, neg0, upper,
  )
  if percent {
    text + "%"
  } else {
    text
  }
}

///|
/// Format a double with an already parsed spec.
fn format_float_with(
  d : Double,
  spec : Spec,
  always_sign : Bool,
) -> String raise Refused {
  let ty = spec.ty
  if ty == 'b' || ty == 'c' || ty == 'd' || ty == 'o' || ty == 'x' || ty == 'X' {
    malformed(spec.ty_at, "unknown format code for a float")
  }
  if ty == 'n' && spec.group != '\u{0}' {
    malformed(spec.ty_at, "cannot specify a grouping separator with 'n'")
  }
  let text = float_component(
    d,
    ty,
    spec.precision,
    spec.alt,
    spec.neg0,
    always_sign,
  )
  let (sign_char, body) = split_sign(text)
  let mut sign = sign_char
  if sign == '\u{0}' && !always_sign {
    match spec.sign {
      '+' => sign = '+'
      ' ' => sign = ' '
      _ => ()
    }
  }
  let (sep, size) = grouping_for(spec, if ty == '\u{0}' { 'g' } else { ty })
  let mut int_len = 0
  while int_len < body.length() && is_digit(body.get_char(int_len).unwrap()) {
    int_len += 1
  }
  layout_number(
    sign,
    "",
    slice(body, 0, int_len),
    slice(body, int_len, body.length()),
    spec,
    sep,
    size,
  )
}

///|
/// Format a double the way Python's `format()` does.
pub fn format_float(d : Double, spec_text : StringView) -> String raise Refused {
  let spec = parse_spec(spec_text)
  format_float_with(d, spec, false)
}

///|
/// `format(value, spec)`, for any number.
pub fn format(value : Number, spec_text : StringView) -> String raise Refused {
  match value {
    Int(n) => format_int(n, spec_text)
    Float(d) => format_float(d, spec_text)
    Fraction(f) => f.format(spec_text)
    Complex(z) => z.format(spec_text)
  }
}

///|
/// Format a complex number: the real part with the specifier's sign, the
/// imaginary part forced positive, then `j`, in parentheses unless the real
/// part is a positive zero.
pub fn Complex::format(
  self : Complex,
  spec_text : StringView,
) -> String raise Refused {
  let spec = parse_spec(spec_text)
  if spec.zero {
    malformed(spec.ty_at, "zero padding is not allowed for complex numbers")
  }
  if spec.align == '=' {
    malformed(spec.ty_at, "'=' alignment is not allowed for complex numbers")
  }
  let mut ty = spec.ty
  let mut skip_real = false
  let mut parens = false
  if ty == '\u{0}' {
    ty = 'r'
    skip_real = self.re == 0.0 && sign_of(self.re) > 0.0
    parens = !skip_real
  }
  let mut precision = spec.precision
  if ty == 'r' && precision >= 0 {
    ty = 'g'
  }
  if ty == 'n' {
    ty = 'g'
  }
  if ty != 'r' {
    match ty {
      'e' | 'E' | 'f' | 'F' | 'g' | 'G' => ()
      _ => malformed(spec.ty_at, "unknown format code for a complex number")
    }
  }
  if precision < 0 {
    precision = if ty == 'r' { 0 } else { 6 }
  }
  let mut re_text = if skip_real && !parens {
    ""
  } else {
    float_component(
      self.re,
      ty,
      precision,
      spec.alt,
      spec.neg0,
      spec.sign == '+',
    )
  }
  if re_text.length() > 0 &&
    spec.sign == ' ' &&
    re_text.get_char(0) != Some('-') &&
    re_text.get_char(0) != Some('+') {
    re_text = " " + re_text
  }
  let mut im_text = float_component(
    self.im,
    ty,
    precision,
    spec.alt,
    spec.neg0,
    if skip_real {
      spec.sign == '+'
    } else {
      true
    },
  )
  if skip_real &&
    spec.sign == ' ' &&
    im_text.get_char(0) != Some('-') &&
    im_text.get_char(0) != Some('+') {
    im_text = " " + im_text
  }
  let mut text = if skip_real { "" } else { re_text }
  if parens {
    text = "(" + text + im_text + "j)"
  } else {
    text = text + im_text + "j"
  }
  if spec.width > text.length() {
    layout_text(text, spec)
  } else {
    text
  }
}

///|
/// Format a fraction. Without a presentation type it is a ratio, with a digit
/// grouping separator allowed in both halves; with a float type it is the exact
/// rational rounded to the requested digits.
pub fn Fraction::format(
  self : Fraction,
  spec_text : StringView,
) -> String raise Refused {
  let spec = parse_spec(spec_text)
  match spec.ty {
    '\u{0}' => fraction_as_ratio(self, spec)
    'e' | 'E' | 'f' | 'F' | 'g' | 'G' | '%' => fraction_as_float(self, spec)
    'n' => fraction_as_float(self, spec)
    _ => malformed(spec.ty_at, "unknown format code for a fraction")
  }
}

///|
/// The no-type form: `3/4`, with grouping in both halves when asked.
fn fraction_as_ratio(f : Fraction, spec : Spec) -> String raise Refused {
  if spec.zero {
    malformed(spec.ty_at, "zero padding is not supported for fractions")
  }
  if spec.neg0 {
    malformed(
      spec.ty_at,
      "negative-zero coercion is not supported for fractions",
    )
  }
  if spec.precision >= 0 {
    malformed(
      spec.ty_at,
      "precision is not supported without a presentation type",
    )
  }
  let negative = f.num < 0N
  let magnitude = if negative { -f.num } else { f.num }
  let sep = match spec.group {
    ',' => ","
    '_' => "_"
    _ => ""
  }
  let top = if sep == "" {
    magnitude.to_string()
  } else {
    group_digits(magnitude.to_string(), sep.get_char(0).unwrap(), 3)
  }
  let body = if f.den > 1N || spec.alt {
    let bottom = if sep == "" {
      f.den.to_string()
    } else {
      group_digits(f.den.to_string(), sep.get_char(0).unwrap(), 3)
    }
    top + "/" + bottom
  } else {
    top
  }
  let sign = if negative {
    '-'
  } else {
    match spec.sign {
      '+' => '+'
      ' ' => ' '
      _ => '\u{0}'
    }
  }
  let sign_text = if sign == '\u{0}' { "" } else { sign.to_string() }
  let padding = spec.width - sign_text.length() - body.length()
  if padding <= 0 {
    return sign_text + body
  }
  match spec.align {
    '<' => sign_text + body + repeat_char(spec.fill, padding)
    '^' => {
      let left = padding / 2
      repeat_char(spec.fill, left) +
      sign_text +
      body +
      repeat_char(spec.fill, padding - left)
    }
    '=' => sign_text + repeat_char(spec.fill, padding) + body
    _ => repeat_char(spec.fill, padding) + sign_text + body
  }
}

///|
/// The float-type form: the exact rational, rounded half to even.
fn fraction_as_float(f : Fraction, spec : Spec) -> String {
  let ty = if spec.ty == 'n' { 'g' } else { spec.ty }
  let precision = if spec.precision < 0 { 6 } else { spec.precision }
  let negative = f.num < 0N
  let magnitude = if negative { -f.num } else { f.num }
  let mut digits = "0"
  let mut point_pos = precision
  let mut exponent = 0
  let mut scientific = false
  if ty == 'f' || ty == 'F' || ty == '%' {
    let place = if ty == '%' { precision + 2 } else { precision }
    let q = if magnitude == 0N {
      0N
    } else {
      div_round(magnitude * pow10(place), f.den)
    }
    digits = q.to_string()
    point_pos = precision
  } else {
    let figures = if ty == 'g' || ty == 'G' {
      if precision < 1 {
        1
      } else {
        precision
      }
    } else {
      precision + 1
    }
    let (sig, decpt) = if magnitude == 0N {
      ("0", 1)
    } else {
      sig_digits(magnitude, f.den, figures)
    }
    digits = sig
    exponent = decpt - figures
    scientific = ty == 'e' || ty == 'E' || exponent > 0 || decpt <= -4
    point_pos = if scientific { figures - 1 } else { figures - decpt }
  }
  if point_pos + 1 > digits.length() {
    digits = repeat_char('0', point_pos + 1 - digits.length()) + digits
  }
  let split_at = digits.length() - point_pos
  let leading = slice(digits, 0, split_at)
  let mut frac = slice(digits, split_at, digits.length())
  let trim_zeros = (ty == 'g' || ty == 'G') && !spec.alt
  if trim_zeros {
    frac = strip_zeros_or_empty(frac)
  }
  let mut suffix = ""
  if ty == '%' {
    suffix = "%"
  } else if scientific {
    let letter = if ty == 'E' || ty == 'F' || ty == 'G' { "E" } else { "e" }
    suffix = letter + signed_exponent(exponent + point_pos)
  }
  let separator = if !spec.alt && frac == "" { "" } else { "." }
  let trailing = separator + frac + suffix
  let sign = if negative {
    '-'
  } else {
    match spec.sign {
      '+' => '+'
      ' ' => ' '
      _ => '\u{0}'
    }
  }
  let sign_text = if sign == '\u{0}' { "" } else { sign.to_string() }
  let (sep, size) = grouping_for(spec, 'g')
  let mut body = leading
  if spec.zero && spec.width > 0 {
    let target = spec.width - sign_text.length() - trailing.length()
    if grouped_len(body.length(), if sep == '\u{0}' { 1 } else { size }) <
      target &&
      target > body.length() {
      let mut d = body.length()
      while grouped_len(d, size) < target {
        d += 1
      }
      body = repeat_char('0', d - body.length()) + body
    }
  }
  if sep != '\u{0}' {
    body = group_digits(body, sep, size)
  }
  let text = body + trailing
  let padded = spec.width - sign_text.length() - text.length()
  if padded <= 0 {
    return sign_text + text
  }
  match spec.align {
    '<' => sign_text + text + repeat_char(spec.fill, padded)
    '^' => {
      let left = padded / 2
      repeat_char(spec.fill, left) +
      sign_text +
      text +
      repeat_char(spec.fill, padded - left)
    }
    '=' => sign_text + repeat_char(spec.fill, padded) + text
    _ => repeat_char(spec.fill, padded) + sign_text + text
  }
}

///|
/// A decimal exponent written with a sign and at least two digits: `+02`,
/// `-01`, `+123`.
fn signed_exponent(exp : Int32) -> String {
  let sign = if exp < 0 { "-" } else { "+" }
  let magnitude = if exp < 0 { -exp } else { exp }
  if magnitude < 10 {
    sign + "0" + magnitude.to_string()
  } else {
    sign + magnitude.to_string()
  }
}

///|
/// Strip trailing zeros, allowing an empty result.
fn strip_zeros_or_empty(text : String) -> String {
  let mut n = text.length()
  while n > 0 && text.get_char(n - 1) == Some('0') {
    n -= 1
  }
  slice(text, 0, n)
}
