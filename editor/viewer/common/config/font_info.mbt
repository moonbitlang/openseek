// Ported from `vscode/src/vs/editor/common/config/fontInfo.ts` at
// checked-in source. Monaco's
// `FontInfo extends BareFontInfo` inheritance flattens into two structs (a
// `FontInfo` repeats the bare fields and exposes `bare()` for consumers of
// the base shape). The `EditorZoom` multiplier is not ported — the readonly
// viewer has no zoom UI, so the factor is constantly `1` — and neither is
// the `serializeFontInfo`/`restoreFontInfo` persistence channel.

///|
/// Monaco `GOLDEN_LINE_HEIGHT_RATIO`: determined from empirical observations.
let golden_line_height_ratio : Double = golden_line_height_ratio_for_platform(
  current_font_platform(),
)

///|
/// Monaco `MINIMUM_LINE_HEIGHT`.
let minimum_line_height = 8

///|
/// Monaco `EditorFontLigatures.OFF` (`editorOptions.ts`): the
/// `font-feature-settings` value when font ligatures are disabled — the
/// editor default, and the value `FontMeasurements`' monospace check keys on.
pub let editor_font_ligatures_off = "\"liga\" off, \"calt\" off"

///|
/// Monaco `FONT_VARIATION_OFF`.
pub let font_variation_off = "normal"

///|
/// Monaco `FONT_VARIATION_TRANSLATE`.
let font_variation_translate = "translate"

///|
priv enum FontPlatform {
  MacOS
  Windows
  Other
}

///|
fn current_font_platform() -> FontPlatform {
  if @base_common.is_macintosh {
    MacOS
  } else if @base_common.is_windows {
    Windows
  } else {
    Other
  }
}

///|
fn golden_line_height_ratio_for_platform(platform : FontPlatform) -> Double {
  match platform {
    MacOS => 1.5
    Windows | Other => 1.35
  }
}

///|
/// Monaco `EDITOR_FONT_DEFAULTS` (with `DEFAULT_MAC_FONT_FAMILY` /
/// `DEFAULT_WINDOWS_FONT_FAMILY` / `DEFAULT_LINUX_FONT_FAMILY`).
pub struct EditorFontDefaults {
  font_family : String
  font_weight : String
  font_size : Double
  line_height : Double
  letter_spacing : Double
} derive(Eq, Debug)

///|
pub let editor_font_defaults : EditorFontDefaults = editor_font_defaults_for_platform(
  current_font_platform(),
)

///|
fn editor_font_defaults_for_platform(
  platform : FontPlatform,
) -> EditorFontDefaults {
  {
    font_family: match platform {
      MacOS => default_mac_font_family
      Windows => default_windows_font_family
      Other => default_linux_font_family
    },
    font_weight: "normal",
    font_size: match platform {
      MacOS => 12.0
      Windows | Other => 14.0
    },
    line_height: 0.0,
    letter_spacing: 0.0,
  }
}

///|
/// Monaco `BareFontInfo`: the requested font settings, with the line height
/// already resolved through the golden-ratio/em/minimum rules.
pub struct BareFontInfo {
  pixel_ratio : Double
  font_family : String
  font_weight : String
  font_size : Double
  font_feature_settings : String
  font_variation_settings : String
  line_height : Int
  letter_spacing : Double
} derive(Eq, Debug)

///|
/// Monaco `BareFontInfo._create`: `lineHeight == 0` derives the golden-ratio
/// line height from the font size, values below `MINIMUM_LINE_HEIGHT` are
/// treated as em multipliers, and the result is rounded and floored at the
/// minimum. `fontVariationSettings === 'translate'` translates a numeric
/// font weight into a `'wght'` variation.
pub fn BareFontInfo::create(
  font_family~ : String,
  font_weight~ : String,
  font_size~ : Double,
  font_feature_settings~ : String,
  font_variation_settings~ : String,
  line_height~ : Double,
  letter_spacing~ : Double,
  pixel_ratio~ : Double,
) -> BareFontInfo {
  let mut line_height = line_height
  if line_height == 0.0 {
    line_height = golden_line_height_ratio * font_size
  } else if line_height < minimum_line_height.to_double() {
    // Values too small to be line heights in pixels are in ems.
    line_height = line_height * font_size
  }
  // Enforce integer, minimum constraints (`Math.round` of a non-negative
  // ratio is `floor(x + 0.5)`).
  let mut rounded_line_height = (line_height + 0.5).to_int()
  if rounded_line_height < minimum_line_height {
    rounded_line_height = minimum_line_height
  }
  let mut font_weight = font_weight
  let mut font_variation_settings = font_variation_settings
  if font_variation_settings == font_variation_translate {
    if font_weight == "normal" || font_weight == "bold" {
      font_variation_settings = font_variation_off
    } else {
      font_variation_settings = "'wght' \{parse_decimal_prefix(font_weight)}"
      font_weight = "normal"
    }
  }
  {
    pixel_ratio,
    font_family,
    font_weight,
    font_size,
    font_feature_settings,
    font_variation_settings,
    line_height: rounded_line_height,
    letter_spacing,
  }
}

///|
/// Monaco `BareFontInfo.getId`: the `FontMeasurements` cache key.
pub fn BareFontInfo::get_id(self : BareFontInfo) -> String {
  "\{self.pixel_ratio}-\{self.font_family}-\{self.font_weight}-\{self.font_size}-\{self.font_feature_settings}-\{self.font_variation_settings}-\{self.line_height}-\{self.letter_spacing}"
}

///|
/// Monaco `BareFontInfo.getMassagedFontFamily`: the configured family with
/// the platform default appended as a fallback, quoting families that use
/// `+` or spaces.
pub fn BareFontInfo::get_massaged_font_family(self : BareFontInfo) -> String {
  massage_font_family(self.font_family, editor_font_defaults.font_family)
}

///|
fn massage_font_family(
  font_family : String,
  fallback_font_family : String,
) -> String {
  let massaged = wrap_in_quotes(font_family)
  if fallback_font_family != "" && font_family != fallback_font_family {
    "\{massaged}, \{fallback_font_family}"
  } else {
    massaged
  }
}

///|
fn wrap_in_quotes(font_family : String) -> String {
  if font_family.contains(",") ||
    font_family.contains("\"") ||
    font_family.contains("'") {
    // Looks like the font family might be already escaped.
    return font_family
  }
  if font_family.contains("+") || font_family.contains(" ") {
    // Wrap a font family using + or <space> with quotes.
    return "\"\{font_family}\""
  }
  font_family
}

///|
/// The decimal-prefix behavior of JavaScript `parseInt(value, 10)` used by
/// BareFontInfo's variation translation. Editor validation supplies canonical
/// weights, but retaining prefix/sign handling prevents raw strings such as
/// `0500` or `500suffix` from leaking into CSS variation syntax.
fn parse_decimal_prefix(value : String) -> String {
  let view = value.view()
  let index = for index = 0; index < value.length(); {
    let code = view.unsafe_get(index).to_int()
    if is_ecmascript_whitespace(code) {
      continue index + 1
    } else {
      break index
    }
  } nobreak {
    index
  }
  let (sign, index) = if index < value.length() {
    let code = view.unsafe_get(index).to_int()
    if code == 0x2D {
      (-1, index + 1)
    } else if code == 0x2B {
      (1, index + 1)
    } else {
      (1, index)
    }
  } else {
    (1, index)
  }
  let digit_start = index
  let (index, result) = for index = index, result = 0.0; index < value.length(); {
    let code = view.unsafe_get(index).to_int()
    if code < 0x30 || code > 0x39 {
      break (index, result)
    }
    continue index + 1, result * 10.0 + (code - 0x30).to_double()
  } nobreak {
    (index, result)
  }
  if index == digit_start {
    "NaN"
  } else {
    (sign.to_double() * result).to_string()
  }
}

///|
/// Leading whitespace accepted by ECMAScript `StringNumericLiteral`, which is
/// what `parseInt` trims before reading its optional sign and decimal prefix.
fn is_ecmascript_whitespace(code : Int) -> Bool {
  (code >= 0x0009 && code <= 0x000D) ||
  code == 0x0020 ||
  code == 0x00A0 ||
  code == 0x1680 ||
  (code >= 0x2000 && code <= 0x200A) ||
  code == 0x2028 ||
  code == 0x2029 ||
  code == 0x202F ||
  code == 0x205F ||
  code == 0x3000 ||
  code == 0xFEFF
}

///|
/// Monaco `FontInfo`: the bare settings plus the widths measured from the
/// DOM (`FontMeasurements`). `is_trusted` is `false` for estimated readings
/// (never measured, or measured while the web font was still loading).
pub(all) struct FontInfo {
  pixel_ratio : Double
  font_family : String
  font_weight : String
  font_size : Double
  font_feature_settings : String
  font_variation_settings : String
  line_height : Int
  letter_spacing : Double
  is_trusted : Bool
  is_monospace : Bool
  typical_halfwidth_character_width : Double
  typical_fullwidth_character_width : Double
  can_use_halfwidth_rightwards_arrow : Bool
  space_width : Double
  middot_width : Double
  wsmiddot_width : Double
  max_digit_width : Double
} derive(Eq, Debug)

///|
/// An estimated `FontInfo` for a `BareFontInfo` that has not been measured
/// yet (no DOM) — untrusted, like Monaco's `restoreFontInfo` readings, so a
/// real measurement replaces it. `0.6` per code unit is the advance ratio
/// of the default monospace stacks.
pub fn FontInfo::estimated(bare : BareFontInfo) -> FontInfo {
  let estimated_advance = bare.font_size * 0.6
  {
    pixel_ratio: bare.pixel_ratio,
    font_family: bare.font_family,
    font_weight: bare.font_weight,
    font_size: bare.font_size,
    font_feature_settings: bare.font_feature_settings,
    font_variation_settings: bare.font_variation_settings,
    line_height: bare.line_height,
    letter_spacing: bare.letter_spacing,
    is_trusted: false,
    is_monospace: true,
    typical_halfwidth_character_width: estimated_advance,
    typical_fullwidth_character_width: estimated_advance * 2.0,
    can_use_halfwidth_rightwards_arrow: true,
    space_width: estimated_advance,
    middot_width: estimated_advance,
    wsmiddot_width: estimated_advance,
    max_digit_width: estimated_advance,
  }
}

///|
/// The estimated `FontInfo` of the `EDITOR_FONT_DEFAULTS` — the headless
/// stand-in used before any DOM measurement.
pub fn FontInfo::default() -> FontInfo {
  FontInfo::estimated(
    BareFontInfo::create(
      font_family=editor_font_defaults.font_family,
      font_weight=editor_font_defaults.font_weight,
      font_size=editor_font_defaults.font_size,
      font_feature_settings=editor_font_ligatures_off,
      font_variation_settings=font_variation_off,
      line_height=editor_font_defaults.line_height,
      letter_spacing=editor_font_defaults.letter_spacing,
      pixel_ratio=1.0,
    ),
  )
}

///|
/// The `BareFontInfo` slice of this `FontInfo` (Monaco's upcast).
pub fn FontInfo::bare(self : FontInfo) -> BareFontInfo {
  {
    pixel_ratio: self.pixel_ratio,
    font_family: self.font_family,
    font_weight: self.font_weight,
    font_size: self.font_size,
    font_feature_settings: self.font_feature_settings,
    font_variation_settings: self.font_variation_settings,
    line_height: self.line_height,
    letter_spacing: self.letter_spacing,
  }
}

///|
pub fn FontInfo::get_id(self : FontInfo) -> String {
  self.bare().get_id()
}

///|
/// Monaco `FontInfo.equals` — deliberately ignores `pixelRatio`,
/// `isTrusted`, and `isMonospace`, exactly like the reference.
pub fn FontInfo::equals(self : FontInfo, other : FontInfo) -> Bool {
  self.font_family == other.font_family &&
  self.font_weight == other.font_weight &&
  self.font_size == other.font_size &&
  self.font_feature_settings == other.font_feature_settings &&
  self.font_variation_settings == other.font_variation_settings &&
  self.line_height == other.line_height &&
  self.letter_spacing == other.letter_spacing &&
  self.typical_halfwidth_character_width ==
  other.typical_halfwidth_character_width &&
  self.typical_fullwidth_character_width ==
  other.typical_fullwidth_character_width &&
  self.can_use_halfwidth_rightwards_arrow ==
  other.can_use_halfwidth_rightwards_arrow &&
  self.space_width == other.space_width &&
  self.middot_width == other.middot_width &&
  self.wsmiddot_width == other.wsmiddot_width &&
  self.max_digit_width == other.max_digit_width
}

///|
#deprecated
pub extend BareFontInfo with Debug::{to_repr}

///|
pub extend BareFontInfo with Eq::{equal, not_equal}

///|
#deprecated
pub extend EditorFontDefaults with Debug::{to_repr}

///|
pub extend EditorFontDefaults with Eq::{equal, not_equal}

///|
#deprecated
pub extend FontInfo with Debug::{to_repr}

///|
pub extend FontInfo with Eq::{equal, not_equal}
