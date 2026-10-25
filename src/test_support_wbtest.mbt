// Shared machinery for the generated-vector tests.
//
// Every test here reads from `vectors.mbt` and compares. Nothing computes an
// expected value with the code under test.

///|
/// The name of a refusal, in the spelling the generator writes.
fn refused_key(err : Refused) -> String {
  match err {
    Malformed(..) => "!malformed"
    ZeroDivision => "!div0"
    Overflow(_) => "!overflow"
    Domain(_) => "!domain"
  }
}

///|
/// Run `body` and return its text, or the name of the refusal it raised.
fn attempt(body : () -> String raise Refused) -> String {
  body() catch {
    (err : Refused) => refused_key(err)
  }
}

///|
/// Compare one observed result against the generated expectation.
fn check(what : StringView, got : String, want : String) -> Unit raise {
  if got != want {
    fail("for \{what}: want \{want}, got \{got}")
  }
}

///|
/// A big integer from a signed decimal string.
fn bigint_of(text : String) -> @bigint.BigInt {
  if text == "" {
    return 0N
  }
  if text.has_prefix("-") {
    -@bigint.BigInt::from_string(slice(text, 1, text.length()))
  } else {
    @bigint.BigInt::from_string(text)
  }
}

///|
/// A small integer from its decimal spelling.
fn int_of(text : String) -> Int32 {
  let mut value = 0
  let mut i = 0
  let mut sign = 1
  if text.get_char(0) == Some('-') {
    sign = -1
    i = 1
  }
  while i < text.length() {
    match text.get_char(i) {
      Some(c) => value = value * 10 + c.to_int() - '0'.to_int()
      None => break
    }
    i += 1
  }
  sign * value
}

///|
/// Parse a double from the generator's exact spelling.
fn from_vector(text : String) -> Double raise Refused {
  parse_float(text)
}
