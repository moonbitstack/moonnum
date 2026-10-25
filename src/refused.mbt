// What goes wrong, and why the library has one error type instead of five.

///|
/// Everything this library refuses, in one type.
///
/// `Malformed` carries the offset where the input stopped making sense, in
/// UTF-16 code units — the unit `StringView` indexes by — so a caller can point
/// at the character instead of at the string.
pub(all) suberror Refused {
  Malformed(at~ : Int32, reason~ : String)
  ZeroDivision
  Overflow(reason~ : String)
  Domain(reason~ : String)
}

///|
/// Raise `Malformed` at `at` with `reason`.
fn[T] malformed(at : Int32, reason : StringView) -> T raise Refused {
  raise Malformed(at~, reason=reason.to_owned())
}

///|
/// The message a refusal carries, phrased for a person rather than a parser.
pub impl Show for Refused with fn to_string(self) {
  match self {
    Malformed(at~, reason~) => reason + " at offset " + at.to_string()
    ZeroDivision => "division by zero"
    Overflow(reason~) => reason
    Domain(reason~) => reason
  }
}

///|
pub extend Refused with Show::{to_string, output}
