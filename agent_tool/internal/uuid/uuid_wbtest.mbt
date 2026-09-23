///|
test "UUID allocation reports entropy failure and timestamp exhaustion" {
  for
    (now, previous, entropy) in [
      (1UL, None, None),
      (1UL, None, Some(b"short")),
      (0x1000000000000UL, None, Some(b"0123456789")),
      (1UL, Some(0xffffffffffffUL), Some(b"0123456789")),
    ] {
    try mint(now, previous, entropy) catch {
      UuidError(_) => ()
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("invalid allocation must fail explicitly")
    }
  }
}
