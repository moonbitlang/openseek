///|
priv suberror UuidError {
  UuidError(String)
}

///|
/// Generate a UUIDv7 without retaining state between calls.
pub fn v7() -> String raise {
  let (id, _) = mint(@env.now(), None, @env.rand(10))
  id
}

///|
/// Generate a UUIDv7, optionally advancing beyond a caller-owned timestamp.
/// Raises on unavailable entropy or exhausted 48-bit timestamps.
pub fn mint(
  now : UInt64,
  previous : UInt64?,
  entropy : Bytes?,
) -> (String, UInt64) raise {
  guard entropy is Some(bytes) && bytes.length() == 10 else {
    raise UuidError("Cannot allocate UUID: secure entropy unavailable")
  }
  let max_stamp = 0xffffffffffffUL
  guard now <= max_stamp &&
    previous.map(last => last < max_stamp).unwrap_or(true) else {
    raise UuidError("Cannot allocate UUID: UUID timestamp exhausted")
  }
  let stamp = match previous {
    Some(last) => if now > last { now } else { last + 1 }
    None => now
  }
  let payload = Bytes::makei(16, index => {
    if index < 6 {
      (stamp >> ((5 - index) * 8)).to_byte()
    } else {
      bytes[index - 6]
    }
  })
  // x/uuid owns the UUID representation, version/variant bits and formatting.
  // Its Version enum names V1–V5; Unknown(7) selects the RFC 9562 v7 bits.
  let id = @x_uuid.from_bytes(payload).as_version(Unknown(7)).to_string()
  (id, stamp)
}
