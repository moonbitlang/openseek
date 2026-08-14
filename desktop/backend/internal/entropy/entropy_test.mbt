///|
test "random_bytes returns OS entropy on native" {
  guard @entropy.random_bytes(32) is Some(bytes) else { fail("no OS entropy") }
  assert_eq(bytes.length(), 32)
}

///|
test "random_hex returns lowercase hex of the requested size" {
  guard @entropy.random_hex(16) is Some(hex) else { fail("no OS entropy") }
  assert_eq(hex.length(), 32)
  assert_true(hex.iter().all(c => c is ('0'..='9' | 'a'..='f')))
}

///|
test "random_hex calls differ" {
  guard @entropy.random_hex(16) is Some(a) else { fail("no OS entropy") }
  guard @entropy.random_hex(16) is Some(b) else { fail("no OS entropy") }
  assert_not_eq(a, b)
}
