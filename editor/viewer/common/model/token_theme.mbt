///| Maps the syntax layer's `@syntax.HighlightTag` onto Monaco's packed token
/// metadata word and the matching `mtk<colorId>` theme color map.
///
/// Monaco decouples *what* a token is (a `HighlightTag`, Monarch/TextMate scope,
/// …) from *how* it is encoded for rendering: the renderer only ever sees a
/// 32-bit metadata word (`encoded_token_attributes.mbt`) and resolves its class
/// (`mtk<foregroundColorId>`) against a theme color map. This module is that
/// bridge for the production lexers. It assigns each tag a stable foreground
/// `ColorId` (and, for comments / strings / regexps, a `StandardTokenType`),
/// then packs it via the `MetadataConsts` offsets.
///
/// The richness of `HighlightTag` (Keyword vs Type vs Function …) lives in the
/// 9-bit foreground field, not the 2-bit `StandardTokenType`, so the whole tag
/// set fits the word with no information loss.

///|
/// Theme foreground `ColorId`s. `1`/`2` are Monaco's reserved default
/// foreground/background (`encoded_token_attributes.mbt`); token colors start at
/// `3`. Indices are the positions into `default_token_color_map`.
const COLOR_ID_KEYWORD : Int = 3

///|
const COLOR_ID_VARIABLE : Int = 4

///|
const COLOR_ID_STRING : Int = 5

///|
const COLOR_ID_NUMBER : Int = 6

///|
const COLOR_ID_COMMENT : Int = 7

///|
const COLOR_ID_PUNCTUATION : Int = 8

///|
const COLOR_ID_TYPE : Int = 9

///|
const COLOR_ID_FUNCTION : Int = 10

///|
const COLOR_ID_STRING_ESCAPE : Int = 11

///|
const COLOR_ID_REGEXP : Int = 12

///|
const COLOR_ID_INVALID : Int = 13

///|
/// The foreground `ColorId` assigned to a tag. Groupings mirror the legacy
/// `tokens.css` palette (e.g. punctuation/operator/delimiter share one color,
/// constant/tag track the keyword color) so the post-flip output is the same
/// colors under different class names.
fn tag_foreground_color_id(tag : @syntax.HighlightTag) -> Int {
  match tag {
    Keyword | Constant | Tag => COLOR_ID_KEYWORD
    Identifier | Variable | Attribute => COLOR_ID_VARIABLE
    String => COLOR_ID_STRING
    Number => COLOR_ID_NUMBER
    Comment | CommentDoc => COLOR_ID_COMMENT
    Punctuation | Operator | Delimiter => COLOR_ID_PUNCTUATION
    Plain => @common_tokens.COLOR_ID_DEFAULT_FOREGROUND
    Type => COLOR_ID_TYPE
    Function => COLOR_ID_FUNCTION
    StringEscape => COLOR_ID_STRING_ESCAPE
    Regexp => COLOR_ID_REGEXP
    Invalid => COLOR_ID_INVALID
  }
}

///|
/// The 2-bit `StandardTokenType` for a tag. Only comments, strings and regexps
/// carry a non-`Other` type (Monaco uses these for bracket matching, electric
/// characters, autoclosing, …); every other tag's identity is in its color.
fn tag_standard_token_type(tag : @syntax.HighlightTag) -> Int {
  match tag {
    Comment | CommentDoc => @common_tokens.STANDARD_TOKEN_TYPE_COMMENT
    String | StringEscape => @common_tokens.STANDARD_TOKEN_TYPE_STRING
    Regexp => @common_tokens.STANDARD_TOKEN_TYPE_REGEX
    _ => @common_tokens.STANDARD_TOKEN_TYPE_OTHER
  }
}

///|
/// Packs a `HighlightTag` into a Monaco token metadata word: foreground color id
/// + font style + standard token type + language id, via the `MetadataConsts`
/// offsets. The background field is set to the default so the word matches
/// `LineTokens::default_token_metadata` for fields the renderer ignores.
fn tag_to_metadata(
  tag : @syntax.HighlightTag,
  font_style? : Int = @common_tokens.FONT_STYLE_NONE,
  language_id? : Int = 0,
) -> UInt {
  ((language_id << @common_tokens.METADATA_LANGUAGEID_OFFSET) |
  (tag_standard_token_type(tag) << @common_tokens.METADATA_TOKEN_TYPE_OFFSET) |
  (font_style << @common_tokens.METADATA_FONT_STYLE_OFFSET) |
  (tag_foreground_color_id(tag) << @common_tokens.METADATA_FOREGROUND_OFFSET) |
  (
    @common_tokens.COLOR_ID_DEFAULT_BACKGROUND <<
    @common_tokens.METADATA_BACKGROUND_OFFSET
  )).reinterpret_as_uint()
}

///|
/// The production color map: `colorId -> CSS color`, indexed by foreground
/// `ColorId`. Reuses the workbench `--vscode-token-*` custom properties so the
/// `mtk<n>` classes render in the same colors as the legacy `tok-*` classes.
/// Mirrors Monaco's `TokenizationRegistry.getColorMap()` result.
pub fn default_token_color_map() -> Array[String] {
  [
    "", // 0  ColorId.None
     "var(--vscode-editor-foreground)", // 1  default foreground
     "var(--vscode-editor-background)", // 2  default background
     "var(--vscode-token-keyword)", // 3  COLOR_ID_KEYWORD
     "var(--vscode-token-variable)", // 4  COLOR_ID_VARIABLE
     "var(--vscode-token-string)", // 5  COLOR_ID_STRING
     "var(--vscode-token-number)", // 6  COLOR_ID_NUMBER
     "var(--vscode-token-comment)", // 7  COLOR_ID_COMMENT
     "var(--vscode-token-punctuation)", // 8  COLOR_ID_PUNCTUATION
     "var(--vscode-token-type)", // 9  COLOR_ID_TYPE
     "var(--vscode-token-function)", // 10 COLOR_ID_FUNCTION
     "var(--vscode-token-string-escape)", // 11 COLOR_ID_STRING_ESCAPE
     "var(--vscode-token-regexp)", // 12 COLOR_ID_REGEXP
     "var(--vscode-token-invalid)", // 13 COLOR_ID_INVALID
  ]
}
