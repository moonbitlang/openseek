///|
/// Mint a lowercase RFC 9562 UUID version 4 from 128 bits supplied by the
/// platform entropy source. `None` means the current runtime cannot provide
/// cryptographically secure randomness; callers decide how their boundary
/// reports that failure.
pub fn mint() -> String? {
  guard @env.rand(16) is Some(bytes) else { return None }
  // from_bytes only rejects lengths other than the 16 bytes requested above.
  let uuid = try! @x_uuid.from_bytes(bytes)
  Some(uuid.as_version(V4).to_string())
}
