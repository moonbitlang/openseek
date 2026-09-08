// Runtime squiggle theming, ported from
// vscode/src/vs/editor/browser/widget/codeEditor/codeEditorWidget.ts:2519-2558
// (`getSquigglySVGData`/`getDotDotDotSVGData` + the `registerThemingParticipant`
// CSS-rule injection). Monaco's visible wavy underline is not the static
// `border-bottom` rule in `editor.css` (that's a high-contrast-only fallback,
// dead in normal themes) — it's this inline-SVG background image, recomputed
// whenever the active theme's `editor{Error,Warning,Info,Hint}.foreground`
// colors change. There is no theme-registry object model here (Deviation: the
// caller passes plain color strings already resolved from CSS custom
// properties, in place of Monaco's `theme.getColor(...)` → `Color`).

///|
/// `encodeURIComponent`'s unreserved set (`A-Z a-z 0-9 - _ . ! ~ * ' ( )`).
/// Inputs here are always ASCII (hex colors and the fixed SVG markup below),
/// so a full UTF-8 byte encoder is not needed (deviation).
fn encode_uri_component(text : String) -> String {
  let sb = StringBuilder()
  for ch in text {
    if is_unreserved(ch) {
      sb.write_char(ch)
    } else {
      let code = ch.to_int()
      sb.write_char('%')
      sb.write_char(hex_digit_char((code >> 4) & 0xF))
      sb.write_char(hex_digit_char(code & 0xF))
    }
  }
  sb.to_string()
}

///|
fn is_unreserved(ch : Char) -> Bool {
  match ch {
    '0'..='9' | 'A'..='Z' | 'a'..='z' => true
    '-' | '_' | '.' | '!' | '~' | '*' | '\'' | '(' | ')' => true
    _ => false
  }
}

///|
fn hex_digit_char(value : Int) -> Char {
  if value < 10 {
    (0x30 + value).unsafe_to_char()
  } else {
    (0x41 + value - 10).unsafe_to_char()
  }
}

///|
/// `getSquigglySVGData` (`codeEditorWidget.ts:2519-2523`): the triangle-wave
/// pattern used for error/warning/info squiggles. Monaco pre-encodes the
/// surrounding markup once and only encodes `color` per call; encoding the
/// whole string in one pass here produces byte-identical output (`encodeURI-
/// Component` has no cross-boundary state) while staying a single function.
fn squiggly_svg_data_uri(color : String) -> String {
  encode_uri_component(
    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 6 3' enable-background='new 0 0 6 3' height='3' width='6'><g fill='\{color}'><polygon points='5.5,0 2.5,3 1.1,3 4.1,0'/><polygon points='4,0 6,2 6,0.6 5.4,0'/><polygon points='0,2 1,3 2.4,3 0,0.6'/></g></svg>",
  )
}

///|
/// `getDotDotDotSVGData` (`codeEditorWidget.ts:2525-2529`): the three-dot
/// pattern used for hint squiggles.
fn dotdotdot_svg_data_uri(color : String) -> String {
  encode_uri_component(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" height=\"3\" width=\"12\"><g fill=\"\{color}\"><circle cx=\"1\" cy=\"1\" r=\"1\"/><circle cx=\"5\" cy=\"1\" r=\"1\"/><circle cx=\"9\" cy=\"1\" r=\"1\"/></g></svg>",
  )
}

///|
/// One optional foreground color per severity, mirroring `theme.getColor(...)`
/// returning `undefined` when a theme leaves a token unset.
pub(all) struct SquigglyThemeColors {
  error : String?
  warning : String?
  info : String?
  hint : String?
} derive(Eq, Debug)

///|
/// The `registerThemingParticipant` callback body (`codeEditorWidget.ts:2532-
/// 2554`), ported as a pure CSS-text builder: one `background: url(...)` rule
/// per present color, omitted entirely when a color is absent (Monaco's `if
/// (color)` gate). Selector prefix is `.moonbit-viewer` (this viewer's
/// convention, matching `markers.css`), not `.monaco-editor`. The `:root
/// { --monaco-editor-*-decoration: ... }` mirror rules are omitted — nothing
/// in this viewer consumes those custom properties (deviation, no dead state).
pub fn squiggly_theme_css(colors : SquigglyThemeColors) -> String {
  let sb = StringBuilder()
  if colors.error is Some(color) {
    write_squiggly_rule(sb, "error", squiggly_svg_data_uri(color))
  }
  if colors.warning is Some(color) {
    write_squiggly_rule(sb, "warning", squiggly_svg_data_uri(color))
  }
  if colors.info is Some(color) {
    write_squiggly_rule(sb, "info", squiggly_svg_data_uri(color))
  }
  if colors.hint is Some(color) {
    write_dotdotdot_rule(sb, dotdotdot_svg_data_uri(color))
  }
  sb.to_string()
}

///|
fn write_squiggly_rule(
  sb : StringBuilder,
  severity : String,
  svg_data : String,
) -> Unit {
  sb <+
    $|.moonbit-viewer .squiggly-\{severity} { background: url("data:image/svg+xml,\{svg_data}") repeat-x bottom left; }
}

///|
fn write_dotdotdot_rule(sb : StringBuilder, svg_data : String) -> Unit {
  sb <+
    $|.moonbit-viewer .squiggly-hint { background: url("data:image/svg+xml,\{svg_data}") no-repeat bottom left; }
}

///|
pub extend SquigglyThemeColors with Debug::{to_repr}

///|
pub extend SquigglyThemeColors with Eq::{equal, not_equal}
