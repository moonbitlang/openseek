///| Faithful conformance port of vscode's `textToHtmlTokenizer.test.ts` (pinned
/// `vscode/` checked-in submodule) — the suite `Editor Modes -
/// textToHtmlTokenizer`. All 5 cases are in scope and ported here against the
/// `tokenize_line_to_html` / `tokenize_to_string` ports.
///
/// `_tokenizeToString` is fed by `tth_mode`, the local stand-in for the suite's
/// `Mode.tokenizeEncoded` (colors `.` as foreground 7, everything else 9),
/// returning raw start-offset token pairs — the adapted stateless tokenization
/// seam (see the port's file header).

///|
const TEST_FONT_STYLE_ITALIC : Int32 = 1

///|
const TEST_FONT_STYLE_BOLD : Int32 = 2

///|
const TEST_FONT_STYLE_UNDERLINE : Int32 = 4

///|
/// Builds a metadata word from a foreground color id and a font-style mask, as
/// the suite does with `<<` against `MetadataConsts.*_OFFSET`.
fn make_meta(foreground : Int32, font_style : Int32) -> UInt32 {
  ((foreground << @tokens.METADATA_FOREGROUND_OFFSET) |
  (font_style << @tokens.METADATA_FONT_STYLE_OFFSET)).reinterpret_as_uint()
}

///|
/// Inflated `ViewLineTokens` over `text` with explicit end-offset/metadata
/// tokens (mirrors the suite's `TestLineTokens`).
fn view_tokens(text : String, tokens : Array[UInt32]) -> @tokens.ViewLineTokens {
  @tokens.LineTokens(tokens, text, @services.language_id_codec).inflate()
}

///|
/// The suite's `Mode.tokenizeEncoded`: `.` → foreground 7, else 9; emits raw
/// start-offset token pairs.
fn tth_mode(line : String) -> Array[UInt32] {
  let arr : Array[UInt32] = []
  let mut prev = -1
  for i in 0..<line.length() {
    let color = if line[i].to_int() == 46 { 7 } else { 9 } // '.' == 46
    if prev != color {
      arr.push(i.reinterpret_as_uint())
      arr.push(
        (color << @tokens.METADATA_FOREGROUND_OFFSET).reinterpret_as_uint(),
      )
    }
    prev = color
  }
  arr
}

///|
test "TextToHtmlTokenizer 1" {
  let actual = tokenize_to_string(
    ".abc..def...gh", @services.language_id_codec, tth_mode,
  )
  assert_eq(
    actual, "<div class=\"monaco-tokenized-source\"><span class=\"mtk7\">.</span><span class=\"mtk9\">abc</span><span class=\"mtk7\">..</span><span class=\"mtk9\">def</span><span class=\"mtk7\">...</span><span class=\"mtk9\">gh</span></div>",
  )
}

///|
test "TextToHtmlTokenizer 2" {
  let actual = tokenize_to_string(
    ".abc..def...gh\n.abc..def...gh", @services.language_id_codec, tth_mode,
  )
  let one = "<span class=\"mtk7\">.</span><span class=\"mtk9\">abc</span><span class=\"mtk7\">..</span><span class=\"mtk9\">def</span><span class=\"mtk7\">...</span><span class=\"mtk9\">gh</span>"
  assert_eq(
    actual,
    "<div class=\"monaco-tokenized-source\">\{one}<br/>\{one}</div>",
  )
}

///|
test "tokenizeLineToHTML" {
  let text = "Ciao hello world!"
  let tokens : Array[UInt32] = [
    4U,
    make_meta(3, TEST_FONT_STYLE_BOLD | TEST_FONT_STYLE_ITALIC),
    5U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    10U,
    make_meta(4, @tokens.FONT_STYLE_NONE),
    11U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    17U,
    make_meta(5, TEST_FONT_STYLE_UNDERLINE),
  ]
  let color_map = ["", "#000000", "#ffffff", "#ff0000", "#00ff00", "#0000ff"]
  let view = view_tokens(text, tokens)
  let bold = "<span style=\"color: #ff0000;font-style: italic;font-weight: bold;\">"
  let space = "<span style=\"color: #000000;\"> </span>"
  let hello = "<span style=\"color: #00ff00;\">hello</span>"
  let world = "<span style=\"color: #0000ff;text-decoration: underline;\">"
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 17, 4, true),
    "<div>\{bold}Ciao</span>\{space}\{hello}\{space}\{world}world!</span></div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 12, 4, true),
    "<div>\{bold}Ciao</span>\{space}\{hello}\{space}\{world}w</span></div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 11, 4, true),
    "<div>\{bold}Ciao</span>\{space}\{hello}\{space}</div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 1, 11, 4, true),
    "<div>\{bold}iao</span>\{space}\{hello}\{space}</div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 4, 11, 4, true),
    "<div><span style=\"color: #000000;\">&#160;</span>\{hello}\{space}</div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 5, 11, 4, true),
    "<div>\{hello}\{space}</div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 5, 10, 4, true),
    "<div>\{hello}</div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 6, 9, 4, true),
    "<div><span style=\"color: #00ff00;\">ell</span></div>",
  )
}

///|
test "tokenizeLineToHTML handle spaces #35954" {
  let text = "  Ciao   hello world!"
  let tokens : Array[UInt32] = [
    2U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    6U,
    make_meta(3, TEST_FONT_STYLE_BOLD | TEST_FONT_STYLE_ITALIC),
    9U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    14U,
    make_meta(4, @tokens.FONT_STYLE_NONE),
    15U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    21U,
    make_meta(5, TEST_FONT_STYLE_UNDERLINE),
  ]
  let color_map = ["", "#000000", "#ffffff", "#ff0000", "#00ff00", "#0000ff"]
  let view = view_tokens(text, tokens)
  let lead = "<span style=\"color: #000000;\">&#160; </span>"
  let bold = "<span style=\"color: #ff0000;font-style: italic;font-weight: bold;\">Ciao</span>"
  let mid = "<span style=\"color: #000000;\"> &#160; </span>"
  let hello = "<span style=\"color: #00ff00;\">hello</span>"
  let space = "<span style=\"color: #000000;\"> </span>"
  let world = "<span style=\"color: #0000ff;text-decoration: underline;\">"
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 21, 4, true),
    "<div>\{lead}\{bold}\{mid}\{hello}\{space}\{world}world!</span></div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 17, 4, true),
    "<div>\{lead}\{bold}\{mid}\{hello}\{space}\{world}wo</span></div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 3, 4, true),
    "<div>\{lead}<span style=\"color: #ff0000;font-style: italic;font-weight: bold;\">C</span></div>",
  )
}

///|
test "tokenizeLineToHTML with tabs and non-zero startOffset #263387" {
  let text = "\ta\tb"
  let tokens : Array[UInt32] = [
    1U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    2U,
    make_meta(3, @tokens.FONT_STYLE_NONE),
    3U,
    make_meta(1, @tokens.FONT_STYLE_NONE),
    4U,
    make_meta(4, @tokens.FONT_STYLE_NONE),
  ]
  let color_map = ["", "#000000", "#ffffff", "#ff0000", "#00ff00"]
  let view = view_tokens(text, tokens)
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 0, 4, 4, true),
    "<div><span style=\"color: #000000;\">&#160; &#160; </span><span style=\"color: #ff0000;\">a</span><span style=\"color: #000000;\"> &#160; </span><span style=\"color: #00ff00;\">b</span></div>",
  )
  assert_eq(
    tokenize_line_to_html(text, view, color_map, 2, 4, 4, true),
    "<div><span style=\"color: #000000;\">&#160; &#160;</span><span style=\"color: #00ff00;\">b</span></div>",
  )
}
