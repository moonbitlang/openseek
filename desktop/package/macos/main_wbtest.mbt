///|
test "macos package args default to ad-hoc signing" {
  let config = parse_sign_config(argv=[])
  assert_true(config.identity is None)
  assert_true(config.notary_profile is None)
}

///|
test "macos helper plist describes cef helper app" {
  let helper = cef_helper_variants()[0]
  let plist = helper_info_plist_source(helper)
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>\{HelperExecutableBaseName}</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>\{HelperBundleIdentifier}</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>LSMinimumSystemVersion</key><string>\{MinMacOSVersion}</string>",
    ),
  )
  assert_true(plist.contains("<key>LSUIElement</key><true/>"))
}

///|
test "macos renderer helper plist uses cef helper variant name" {
  let helper = cef_helper_variants()[4]
  let plist = helper_info_plist_source(helper)
  assert_eq(helper.executable_name(), "OpenSeek Desktop Helper (Renderer)")
  assert_eq(
    helper.executable_path(),
    "dist/OpenSeek Desktop.app/Contents/Frameworks/OpenSeek Desktop Helper (Renderer).app/Contents/MacOS/OpenSeek Desktop Helper (Renderer)",
  )
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>OpenSeek Desktop Helper (Renderer)</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>community.moonbit.proton.openseek-desktop.helper.renderer</string>",
    ),
  )
}

///|
test "macos base helper path points at chromium helper executable name" {
  let helper = cef_helper_variants()[0]
  assert_eq(
    helper.executable_path(),
    "dist/OpenSeek Desktop.app/Contents/Frameworks/OpenSeek Desktop Helper.app/Contents/MacOS/OpenSeek Desktop Helper",
  )
}

///|
test "macos helper executable rpath points back to bundled proton runtime" {
  assert_eq(HelperProtonRPath, "@loader_path/../../../../Resources/proton/lib")
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
