///| Behavior port of vscode's encoded token metadata helpers.
///
/// Source: `src/vs/editor/common/encodedTokenAttributes.ts` (pinned `vscode/`
/// submodule). Ports the `MetadataConsts` bit layout, the `FontStyle`/`ColorId`/
/// `StandardTokenType` enums, and the `TokenMetadata` decoders. The 32-bit
/// metadata word is stored as `UInt` (Monaco packs it into a `Uint32Array`) and
/// exposed through a MoonBit-native `TokenMetadata` newtype. The background
/// field occupies the top byte, so an `Int` cannot hold a fully populated word.
///
/// Placement: Monaco keeps this file at the `editor/common/` root. The
/// `viewer/common` root package imports `view_model`, which sits above this
/// code in the import graph, so a root placement would cycle; it lives one
/// directory down with its primary consumer (`lineTokens.ts` is in
/// `common/tokens/` in Monaco too).

///|
/// `FontStyle` — values are 2^x so a bit mask can be used.
pub const FONT_STYLE_NONE : Int = 0

///|
const FONT_STYLE_ITALIC : Int = 1

///|
const FONT_STYLE_BOLD : Int = 2

///|
const FONT_STYLE_UNDERLINE : Int = 4

///|
const FONT_STYLE_STRIKETHROUGH : Int = 8

///|
/// `ColorId` — open ended at runtime.
pub const COLOR_ID_DEFAULT_FOREGROUND : Int = 1

///|
pub const COLOR_ID_DEFAULT_BACKGROUND : Int = 2

///|
/// `StandardTokenType`.
pub const STANDARD_TOKEN_TYPE_OTHER : Int = 0

///|
pub const STANDARD_TOKEN_TYPE_COMMENT : Int = 1

///|
pub const STANDARD_TOKEN_TYPE_STRING : Int = 2

///|
pub const STANDARD_TOKEN_TYPE_REGEX : Int = 3

// The binary metadata format (see encodedTokenAttributes.ts):
//   bbbb bbbb ffff ffff fFFF FBTT LLLL LLLL
//   L = LanguageId (8), T = StandardTokenType (2), B = Balanced bracket (1),
//   F = FontStyle (4), f = foreground (9), b = background (8)

///|
const METADATA_LANGUAGEID_MASK : UInt = 0x0000_00FFU

///|
const METADATA_TOKEN_TYPE_MASK : UInt = 0x0000_0300U

///|
const METADATA_BALANCED_BRACKETS_MASK : UInt = 0x0000_0400U

///|
const METADATA_FONT_STYLE_MASK : UInt = 0x0000_7800U

///|
const METADATA_FOREGROUND_MASK : UInt = 0x00FF_8000U

///|
const METADATA_BACKGROUND_MASK : UInt = 0xFF00_0000U

// The shift offsets are exposed (Monaco's public `MetadataConsts.*_OFFSET`) so
// callers can build metadata words as `field << OFFSET`, as the suite does.

///|
pub const METADATA_LANGUAGEID_OFFSET : Int = 0

///|
pub const METADATA_TOKEN_TYPE_OFFSET : Int = 8

///|
const METADATA_BALANCED_BRACKETS_OFFSET : Int = 10

///|
pub const METADATA_FONT_STYLE_OFFSET : Int = 11

///|
pub const METADATA_FOREGROUND_OFFSET : Int = 15

///|
pub const METADATA_BACKGROUND_OFFSET : Int = 24

///|
/// One packed 32-bit token metadata word. The distinct type keeps semantic APIs
/// from accidentally accepting offsets or unrelated `UInt` values while its
/// public scalar representation remains available at raw storage seams.
pub(all) struct TokenMetadata(UInt) derive(Eq)

///|
/// Returns the raw word for flat encoded-token storage or transport.
pub fn TokenMetadata::to_uint(self : TokenMetadata) -> UInt {
  let TokenMetadata(raw) = self
  raw
}

///|
/// Returns the encoded language id.
fn TokenMetadata::get_language_id(self : TokenMetadata) -> Int {
  ((self.to_uint() & METADATA_LANGUAGEID_MASK) >> METADATA_LANGUAGEID_OFFSET).reinterpret_as_int()
}

///|
/// Returns the encoded standard token type.
#warnings("-unused_value")
fn TokenMetadata::get_token_type(self : TokenMetadata) -> Int {
  ((self.to_uint() & METADATA_TOKEN_TYPE_MASK) >> METADATA_TOKEN_TYPE_OFFSET).reinterpret_as_int()
}

///|
/// Whether the token can contain balanced brackets.
#warnings("-unused_value")
fn TokenMetadata::contains_balanced_brackets(self : TokenMetadata) -> Bool {
  (self.to_uint() & METADATA_BALANCED_BRACKETS_MASK) != 0
}

///|
/// Returns the encoded font-style bitset.
fn TokenMetadata::get_font_style(self : TokenMetadata) -> Int {
  ((self.to_uint() & METADATA_FONT_STYLE_MASK) >> METADATA_FONT_STYLE_OFFSET).reinterpret_as_int()
}

///|
/// Returns the foreground color id.
fn TokenMetadata::get_foreground(self : TokenMetadata) -> Int {
  ((self.to_uint() & METADATA_FOREGROUND_MASK) >> METADATA_FOREGROUND_OFFSET).reinterpret_as_int()
}

///|
/// Returns the background color id.
#warnings("-unused_value")
fn TokenMetadata::get_background(self : TokenMetadata) -> Int {
  ((self.to_uint() & METADATA_BACKGROUND_MASK) >> METADATA_BACKGROUND_OFFSET).reinterpret_as_int()
}

///|
/// Returns the Monaco-compatible token CSS class list.
pub fn TokenMetadata::get_class_name(self : TokenMetadata) -> String {
  let foreground = self.get_foreground()
  let mut class_name = "mtk\{foreground.to_string()}"
  let font_style = self.get_font_style()
  if (font_style & FONT_STYLE_ITALIC) != 0 {
    class_name = "\{class_name} mtki"
  }
  if (font_style & FONT_STYLE_BOLD) != 0 {
    class_name = "\{class_name} mtkb"
  }
  if (font_style & FONT_STYLE_UNDERLINE) != 0 {
    class_name = "\{class_name} mtku"
  }
  if (font_style & FONT_STYLE_STRIKETHROUGH) != 0 {
    class_name = "\{class_name} mtks"
  }
  class_name
}

///|
/// Returns the inline CSS presentation for the supplied color map.
fn TokenMetadata::get_inline_style(
  self : TokenMetadata,
  color_map : Array[String],
) -> String {
  let foreground = self.get_foreground()
  let font_style = self.get_font_style()
  let mut result = "color: \{color_map[foreground]};"
  if (font_style & FONT_STYLE_ITALIC) != 0 {
    result = "\{result}font-style: italic;"
  }
  if (font_style & FONT_STYLE_BOLD) != 0 {
    result = "\{result}font-weight: bold;"
  }
  let mut text_decoration = ""
  if (font_style & FONT_STYLE_UNDERLINE) != 0 {
    text_decoration = "\{text_decoration} underline"
  }
  if (font_style & FONT_STYLE_STRIKETHROUGH) != 0 {
    text_decoration = "\{text_decoration} line-through"
  }
  if text_decoration != "" {
    result = "\{result}text-decoration:\{text_decoration};"
  }
  result
}

///|
pub extend TokenMetadata with Eq::{equal, not_equal}
