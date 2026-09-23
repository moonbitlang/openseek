///|
test "UUIDv7 layout matches the RFC 9562 A.6 test vector" {
  let (id, stamp) = @uuid.mint(
    0x017f22e279b0UL,
    None,
    Some(b"\xcc\xc3\x18\xc4\xdc\x0c\x0c\x07\x39\x8f"),
  )
  assert_eq(id.to_string(), "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
  assert_eq(stamp, 0x017f22e279b0UL)
}

///|
test "UUID job order survives same-millisecond allocation and clock rollback" {
  let entropy = Some(b"0123456789")
  let (first, stamp) = @uuid.mint(100UL, None, entropy)
  let (second, stamp) = @uuid.mint(100UL, Some(stamp), entropy)
  let (third, stamp) = @uuid.mint(50UL, Some(stamp), entropy)
  assert_true(first < second && second < third)
  assert_eq(stamp, 102UL)
}
