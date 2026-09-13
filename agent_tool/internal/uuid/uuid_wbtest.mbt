///|
test "UUIDv7 layout matches the RFC 9562 A.6 test vector" {
  let (id, stamp) = mint(
    0x017f22e279b0UL,
    None,
    Some(b"\xcc\xc3\x18\xc4\xdc\x0c\x0c\x07\x39\x8f"),
  )
  assert_eq(id, "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
  assert_eq(stamp, 0x017f22e279b0UL)
}

///|
test "UUID job order survives same-millisecond allocation and clock rollback" {
  let entropy = Some(b"0123456789")
  let (first, stamp) = mint(100UL, None, entropy)
  let (second, stamp) = mint(100UL, Some(stamp), entropy)
  let (third, stamp) = mint(50UL, Some(stamp), entropy)
  assert_true(first < second && second < third)
  assert_eq(stamp, 102UL)
}

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
