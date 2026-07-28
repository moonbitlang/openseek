///|
/// (Intentionally empty)
///
/// Note: helper functions shared between MoonBit test files must live inside a
/// `*_test.mbt` file so they are available to the blackbox test package.
pub fn bytes_concat(parts : Array[Bytes]) -> Bytes {
  let mut total = 0
  for part in parts {
    total += part.length()
  }
  let buf = Buffer(size_hint=total)
  for part in parts {
    for b in part {
      buf.write_byte(b)
    }
  }
  buf.contents()
}
