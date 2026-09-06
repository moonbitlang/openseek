// Source-derived white-box platform matrix for
// `vscode/src/vs/editor/common/config/fontInfo.ts` at checked-in vscode submodule.

///|
test "EDITOR_FONT_DEFAULTS platform matrix" {
  let cases : Array[(String, FontPlatform, String, Double, Double)] = [
    ("MacOS", MacOS, default_mac_font_family, 12.0, 1.5),
    ("Windows", Windows, default_windows_font_family, 14.0, 1.35),
    ("Other", Other, default_linux_font_family, 14.0, 1.35),
  ]
  for case in cases {
    let (name, platform, font_family, font_size, ratio) = case
    let defaults = editor_font_defaults_for_platform(platform)
    assert_eq(defaults.font_family, font_family, msg=name)
    assert_eq(defaults.font_weight, "normal", msg=name)
    assert_eq(defaults.font_size, font_size, msg=name)
    assert_eq(defaults.line_height, 0.0, msg=name)
    assert_eq(defaults.letter_spacing, 0.0, msg=name)
    assert_eq(golden_line_height_ratio_for_platform(platform), ratio, msg=name)
  }
}

///|
test "massaged family omits an empty or identical fallback" {
  assert_eq(massage_font_family("Fira Code", ""), "\"Fira Code\"")
  assert_eq(massage_font_family("Fira", "Fallback"), "Fira, Fallback")
  assert_eq(
    massage_font_family(default_mac_font_family, default_mac_font_family),
    default_mac_font_family,
  )
}
