// OS cryptographic entropy via moonbitlang/core/env's @env.rand, which reads
// the platform entropy source (the runtime on native, WASI random_get on wasm)
// and returns `None` where no such source exists.

///|
/// `byte_count` bytes of OS entropy, or `None` when the platform's random
/// source could not be read. Never invents weak randomness — callers that
/// need a value fail loudly and ask the operator for an explicit one.
pub fn random_bytes(byte_count : Int) -> Bytes? {
  @env.rand(byte_count)
}

///|
/// A lowercase-hex string of `byte_count` random bytes (so its length is
/// `2 * byte_count`), or `None` when no OS entropy is available.
pub fn random_hex(byte_count : Int) -> String? {
  guard random_bytes(byte_count) is Some(bytes) else { return None }
  let builder = StringBuilder()
  for byte in bytes {
    builder <+ "\{byte.to_int().to_string(radix=16).pad_start(2, '0')}"
  }
  Some(builder.to_string())
}
