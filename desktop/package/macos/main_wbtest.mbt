///|
test "macos package args default to ad-hoc signing" {
  let config = parse_sign_config(argv=[])
  assert_true(config.identity is None)
  assert_true(config.notary_profile is None)
}

///|
test "macos package args parse signing and notarization" {
  let config = parse_sign_config(argv=[
    "--sign", "Developer ID Application: Example", "--notarize", "notary",
  ])
  assert_true(config.identity is Some("Developer ID Application: Example"))
  assert_true(config.notary_profile is Some("notary"))
}

///|
test "macos notarization requires distribution signing" {
  try parse_sign_config(argv=["--notarize", "notary"]) catch {
    err =>
      assert_true(
        err
        .to_string()
        .contains(
          "required argument was not provided: 'sign' (required by 'notarize')",
        ),
      )
  } noraise {
    _ => fail("expected --notarize without --sign to fail")
  }
}
