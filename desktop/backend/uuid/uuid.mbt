///|
/// Mint a lowercase RFC 9562 UUID version 4 from 128 bits supplied by the
/// platform entropy source. Raises when the current runtime cannot provide
/// cryptographically secure randomness.
pub fn mint() -> String raise {
  guard @env.rand(16) is Some(bytes) else { fail("OS entropy unavailable") }
  @x_uuid.from_bytes(bytes).as_version(V4).to_string()
}
