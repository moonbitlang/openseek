// OS cryptographic entropy, read through a small C stub because
// moonbitlang/async's fs cannot open /dev/urandom (see entropy_native.c).

///|
extern "C" fn os_entropy(n : Int) -> Bytes = "openseek_os_entropy"

///|
/// `byte_count` bytes of OS entropy, or `None` when the platform's random
/// source could not be read. Never invents weak randomness — callers that
/// need a value fail loudly and ask the operator for an explicit one.
pub fn random_bytes(byte_count : Int) -> Bytes? {
  let bytes = os_entropy(byte_count)
  if bytes.length() < byte_count {
    None
  } else {
    Some(bytes)
  }
}

///|
/// A lowercase-hex string of `byte_count` random bytes (so its length is
/// `2 * byte_count`), or `None` when no OS entropy is available.
pub fn random_hex(byte_count : Int) -> String? {
  guard random_bytes(byte_count) is Some(bytes) else { return None }
  let builder = StringBuilder()
  for byte in bytes {
    let value = byte.to_int()
    if value < 16 {
      builder <+ "0"
    }
    builder <+ "\{value.to_string(radix=16)}"
  }
  Some(builder.to_string())
}
