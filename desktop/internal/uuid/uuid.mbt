///|
/// Mint a lowercase RFC 9562 UUID version 4 from 128 bits supplied by the
/// platform entropy source. `None` means the current runtime cannot provide
/// cryptographically secure randomness; callers decide how their boundary
/// reports that failure.
pub fn mint() -> String? {
  guard @env.rand(16) is Some(bytes) else { return None }
  // env.rand(16) supplies exactly 16 bytes; from_bytes only rejects other
  // lengths. Entropy unavailability is handled above, before this invariant.
  let id = try! @x_uuid.from_bytes(bytes)
  Some(id.as_version(V4).to_string())
}
