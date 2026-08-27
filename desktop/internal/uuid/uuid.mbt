///|
/// Mint a lowercase RFC 9562 UUID version 4 from 128 bits supplied by the
/// platform entropy source. `None` means the current runtime cannot provide
/// cryptographically secure randomness; callers decide how their boundary
/// reports that failure.
pub fn mint() -> String? {
  guard @env.rand(16) is Some(bytes) else { return None }
  let text = StringBuilder()
  for index, byte in bytes {
    if index == 4 || index == 6 || index == 8 || index == 10 {
      text.write_char('-')
    }
    let raw = byte.to_int()
    let value = if index == 6 {
      (raw & 0x0f) | 0x40
    } else if index == 8 {
      (raw & 0x3f) | 0x80
    } else {
      raw
    }
    if value < 0x10 {
      text.write_char('0')
    }
    text.write_string(value.to_string(radix=16))
  }
  Some(text.to_string())
}
