// Source-derived behaviors transcribed from
// `vscode/src/vs/editor/common/config/fontInfo.ts` at checked-in vscode submodule.

///|
/// White-box font geometry coverage.
fn bare(line_height : Double, font_size : Double) -> BareFontInfo {
  BareFontInfo::create(
    font_family="Menlo",
    font_weight="normal",
    font_size~,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_off,
    line_height~,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
}

///|
fn bare_variant(
  base : BareFontInfo,
  pixel_ratio~ : Double = base.pixel_ratio,
  font_family~ : String = base.font_family,
  font_weight~ : String = base.font_weight,
  font_size~ : Double = base.font_size,
  font_feature_settings~ : String = base.font_feature_settings,
  font_variation_settings~ : String = base.font_variation_settings,
  line_height~ : Double = base.line_height.to_double(),
  letter_spacing~ : Double = base.letter_spacing,
) -> BareFontInfo {
  BareFontInfo::create(
    font_family~,
    font_weight~,
    font_size~,
    font_feature_settings~,
    font_variation_settings~,
    line_height~,
    letter_spacing~,
    pixel_ratio~,
  )
}

///|
test "lineHeight 0 derives the golden-ratio line height from the font size" {
  let expected = (golden_line_height_ratio * 12.0 + 0.5).to_int()
  assert_eq(bare(0.0, 12.0).line_height, expected)
}

///|
test "lineHeight below the minimum is an em multiplier" {
  // 1.5em of a 12px font: 18px.
  assert_eq(bare(1.5, 12.0).line_height, 18)
  // 1.35em of a 14px font: round(18.9) = 19px.
  assert_eq(bare(1.35, 14.0).line_height, 19)
}

///|
test "lineHeight in pixels is rounded and floored at the minimum" {
  assert_eq(bare(8.0, 12.0).line_height, 8)
  assert_eq(bare(18.0, 12.0).line_height, 18)
  assert_eq(bare(18.4, 12.0).line_height, 18)
  assert_eq(bare(18.5, 12.0).line_height, 19)
  // 0.5em of an 8px font resolves to 4px, below MINIMUM_LINE_HEIGHT.
  assert_eq(bare(0.5, 8.0).line_height, 8)
}

///|
test "fontVariationSettings translate maps numeric weights to wght" {
  let translated = BareFontInfo::create(
    font_family="Menlo",
    font_weight="500",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(translated.font_weight, "normal")
  assert_eq(translated.font_variation_settings, "'wght' 500")
  let unicode_space = BareFontInfo::create(
    font_family="Menlo",
    font_weight="\u{00a0}600tail",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(unicode_space.font_variation_settings, "'wght' 600")
  let kept = BareFontInfo::create(
    font_family="Menlo",
    font_weight="bold",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(kept.font_weight, "bold")
  assert_eq(kept.font_variation_settings, font_variation_off)
  let normal = BareFontInfo::create(
    font_family="Menlo",
    font_weight="normal",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(normal.font_weight, "normal")
  assert_eq(normal.font_variation_settings, font_variation_off)
  let untranslated = BareFontInfo::create(
    font_family="Menlo",
    font_weight="500",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings="'wght' 450",
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(untranslated.font_weight, "500")
  assert_eq(untranslated.font_variation_settings, "'wght' 450")
}

///|
test "fontVariationSettings translate uses parseInt decimal-prefix semantics" {
  let translated = BareFontInfo::create(
    font_family="Menlo",
    font_weight="  +0500suffix",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(translated.font_weight, "normal")
  assert_eq(translated.font_variation_settings, "'wght' 500")
  let negative = BareFontInfo::create(
    font_family="Menlo",
    font_weight="-25rest",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(negative.font_variation_settings, "'wght' -25")
  let invalid = BareFontInfo::create(
    font_family="Menlo",
    font_weight="weight",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_translate,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(invalid.font_variation_settings, "'wght' NaN")
  for boundary in ["1", "1000"] {
    let info = BareFontInfo::create(
      font_family="Menlo",
      font_weight=boundary,
      font_size=12.0,
      font_feature_settings=editor_font_ligatures_off,
      font_variation_settings=font_variation_translate,
      line_height=0.0,
      letter_spacing=0.0,
      pixel_ratio=1.0,
    )
    assert_eq(info.font_variation_settings, "'wght' \{boundary}")
  }
}

///|
test "massaged font family appends the platform fallback and quotes spaces" {
  let custom = BareFontInfo::create(
    font_family="Fira Code",
    font_weight="normal",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_off,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(
    custom.get_massaged_font_family(),
    "\"Fira Code\", \{editor_font_defaults.font_family}",
  )
  let default_family = bare(0.0, 12.0)
  // bare() uses "Menlo", not the full default stack, so the fallback appends.
  assert_true(default_family.get_massaged_font_family().contains("Menlo"))
}

///|
test "massaged font family preserves escaped punctuation and quotes plus" {
  let fallback = editor_font_defaults.font_family
  for family in ["A,B", "A\"B", "A'B"] {
    let info = BareFontInfo::create(
      font_family=family,
      font_weight="normal",
      font_size=12.0,
      font_feature_settings=editor_font_ligatures_off,
      font_variation_settings=font_variation_off,
      line_height=0.0,
      letter_spacing=0.0,
      pixel_ratio=1.0,
    )
    assert_eq(info.get_massaged_font_family(), "\{family}, \{fallback}")
  }
  let plus = BareFontInfo::create(
    font_family="Fira+Code",
    font_weight="normal",
    font_size=12.0,
    font_feature_settings=editor_font_ligatures_off,
    font_variation_settings=font_variation_off,
    line_height=0.0,
    letter_spacing=0.0,
    pixel_ratio=1.0,
  )
  assert_eq(plus.get_massaged_font_family(), "\"Fira+Code\", \{fallback}")
}

///|
test "BareFontInfo getId joins all eight identity axes in fixed order" {
  let base = BareFontInfo::create(
    font_family="Fira",
    font_weight="500",
    font_size=13.5,
    font_feature_settings="features",
    font_variation_settings="variations",
    line_height=18.0,
    letter_spacing=1.25,
    pixel_ratio=2.0,
  )
  assert_eq(base.get_id(), "2-Fira-500-13.5-features-variations-18-1.25")
  let variants : Array[BareFontInfo] = [
    bare_variant(base, pixel_ratio=3.0),
    bare_variant(base, font_family="Other"),
    bare_variant(base, font_weight="600"),
    bare_variant(base, font_size=14.5),
    bare_variant(base, font_feature_settings="other-features"),
    bare_variant(base, font_variation_settings="other-variations"),
    bare_variant(base, line_height=19.0),
    bare_variant(base, letter_spacing=2.25),
  ]
  for variant in variants {
    assert_false(base.get_id() == variant.get_id())
  }
}

///|
test "FontInfo equals includes measured identity and omits three source axes" {
  let base = FontInfo::estimated(
    BareFontInfo::create(
      font_family="Fira",
      font_weight="normal",
      font_size=12.0,
      font_feature_settings=editor_font_ligatures_off,
      font_variation_settings=font_variation_off,
      line_height=18.0,
      letter_spacing=0.0,
      pixel_ratio=1.0,
    ),
  )
  let included : Array[FontInfo] = [
    { ..base, font_family: "Other", },
    { ..base, font_weight: "bold", },
    { ..base, font_size: 13.0, },
    { ..base, font_feature_settings: "features", },
    { ..base, font_variation_settings: "variations", },
    { ..base, line_height: 19, },
    { ..base, letter_spacing: 1.0, },
    {
      ..base,
      typical_halfwidth_character_width: base.typical_halfwidth_character_width +
      1.0,
    },
    {
      ..base,
      typical_fullwidth_character_width: base.typical_fullwidth_character_width +
      1.0,
    },
    {
      ..base,
      can_use_halfwidth_rightwards_arrow: !base.can_use_halfwidth_rightwards_arrow,
    },
    { ..base, space_width: base.space_width + 1.0, },
    { ..base, middot_width: base.middot_width + 1.0, },
    { ..base, wsmiddot_width: base.wsmiddot_width + 1.0, },
    { ..base, max_digit_width: base.max_digit_width + 1.0, },
  ]
  for variant in included {
    assert_false(base.equals(variant))
  }
  assert_true(base.equals({ ..base, pixel_ratio: 2.0, }))
  assert_true(base.equals({ ..base, is_trusted: !base.is_trusted, }))
  assert_true(base.equals({ ..base, is_monospace: !base.is_monospace, }))
}
