///|
test "encode_uri_component matches JS encodeURIComponent" {
  // Unreserved chars pass through unchanged (incl. JS's extra `! ~ * ' ( )`).
  assert_eq(encode_uri_component("abcXYZ019-_.!~*'()"), "abcXYZ019-_.!~*'()")
  // Everything else is %XX (uppercase hex).
  assert_eq(encode_uri_component("#eeeeeeb3"), "%23eeeeeeb3")
  assert_eq(encode_uri_component("<svg xmlns='"), "%3Csvg%20xmlns%3D'")
  assert_eq(encode_uri_component(","), "%2C")
  assert_eq(encode_uri_component("/"), "%2F")
}

///|
test "squiggly_svg_data_uri matches codeEditorWidget.ts getSquigglySVGData" {
  // Cross-checked against `encodeURIComponent` in Node for color "#f14c4c"
  // (VS Code Dark Modern's editorError.foreground default).
  assert_eq(
    squiggly_svg_data_uri("#f14c4c"),
    "%3Csvg%20xmlns%3D'http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg'%20viewBox%3D'0%200%206%203'%20enable-background%3D'new%200%200%206%203'%20height%3D'3'%20width%3D'6'%3E%3Cg%20fill%3D'%23f14c4c'%3E%3Cpolygon%20points%3D'5.5%2C0%202.5%2C3%201.1%2C3%204.1%2C0'%2F%3E%3Cpolygon%20points%3D'4%2C0%206%2C2%206%2C0.6%205.4%2C0'%2F%3E%3Cpolygon%20points%3D'0%2C2%201%2C3%202.4%2C3%200%2C0.6'%2F%3E%3C%2Fg%3E%3C%2Fsvg%3E",
  )
}

///|
test "dotdotdot_svg_data_uri matches codeEditorWidget.ts getDotDotDotSVGData" {
  // Cross-checked against `encodeURIComponent` in Node for color "#eeeeeeb3"
  // (VS Code Dark Modern's editorHint.foreground default, dark #eeeeee @ 0.7).
  assert_eq(
    dotdotdot_svg_data_uri("#eeeeeeb3"),
    "%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20height%3D%223%22%20width%3D%2212%22%3E%3Cg%20fill%3D%22%23eeeeeeb3%22%3E%3Ccircle%20cx%3D%221%22%20cy%3D%221%22%20r%3D%221%22%2F%3E%3Ccircle%20cx%3D%225%22%20cy%3D%221%22%20r%3D%221%22%2F%3E%3Ccircle%20cx%3D%229%22%20cy%3D%221%22%20r%3D%221%22%2F%3E%3C%2Fg%3E%3C%2Fsvg%3E",
  )
}

///|
test "squiggly_theme_css emits one rule per present color, in severity order" {
  let css = squiggly_theme_css({
    error: Some("#f14c4c"),
    warning: Some("#cca700"),
    info: Some("#59a4f9"),
    hint: Some("#eeeeeeb3"),
  })
  for severity in ["error", "warning", "info", "hint"] {
    assert_true(
      css.contains(
        ".moonbit-viewer .squiggly-\{severity} { background: url(\"data:image/svg+xml,",
      ),
      msg="squiggly-\{severity} rule",
    )
  }
  // wavy severities repeat horizontally; hint is a single no-repeat dot cluster.
  assert_true(css.contains("\") repeat-x bottom left; }"))
  assert_true(css.contains("\") no-repeat bottom left; }"))
  // error rule appears before warning, which appears before info (severity
  // order, matching the source's declaration order).
  let error_at = css.find(".squiggly-error").unwrap()
  let warning_at = css.find(".squiggly-warning").unwrap()
  let info_at = css.find(".squiggly-info").unwrap()
  assert_true(error_at < warning_at)
  assert_true(warning_at < info_at)
}

///|
test "squiggly_theme_css omits a rule when its color is absent (theme.getColor undefined)" {
  let css = squiggly_theme_css({
    error: Some("#f14c4c"),
    warning: None,
    info: None,
    hint: None,
  })
  assert_true(css.contains(".squiggly-error"))
  assert_false(css.contains(".squiggly-warning"))
  assert_false(css.contains(".squiggly-info"))
  assert_false(css.contains(".squiggly-hint"))
}

///|
test "squiggly_theme_css with no colors is empty" {
  assert_eq(
    squiggly_theme_css({ error: None, warning: None, info: None, hint: None, }),
    "",
  )
}
