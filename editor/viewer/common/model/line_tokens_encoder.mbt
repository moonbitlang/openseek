///| Encodes the MoonBit lexers' per-line output into Monaco's faithful
/// `LineTokens`, the `TokenizerSyntaxTokenBackend` role of turning
/// `ITokenizationSupport` output into the binary token store. The `syntax`
/// layer keeps producing line-local `@syntax.LineToken`s and never learns
/// about the store.
///
/// A token segment is emitted per lexer token (clamped to the line), with
/// inter-token gaps and trailing text filled by a default-metadata token
/// (Monaco tokens cover the whole line). A tag's color/type becomes a packed
/// metadata word (`tag_to_metadata`).

///|
/// Builds the faithful `LineTokens` for one model line from the lexer's
/// line-local tokens. `language_id` is the model's numeric language id (from
/// the codec); it is packed into every token's metadata word — including the
/// plain gap/trailing fills — so each token reports the model's language.
pub fn line_tokens_from_lexer_tokens(
  line_text : String,
  tokens : Array[@syntax.LineToken],
  decoder : @services.LanguageIdCodec,
  language_id~ : Int32 = 0,
) -> @common_tokens.LineTokens {
  let words = encode_raw_start_offsets(tokens, line_text.length(), language_id~)
  start_offsets_to_end_offsets(words, line_text.length())
  LineTokens(words, line_text, decoder)
}

///|
/// Encodes lexer spans as Monaco's raw start-offset word pairs. Gaps, trailing
/// text, and blank lines receive the language-tagged plain metadata. This is
/// the production registry adapter path; it deliberately does not construct
/// an end-offset `LineTokens` value before `safe_tokenize` performs the single
/// conversion.
fn encode_raw_start_offsets(
  tokens : Array[@syntax.LineToken],
  line_length : Int32,
  language_id~ : Int32 = 0,
) -> Array[UInt32] {
  let words : Array[UInt32] = []
  let cursor = for token in tokens; cursor = 0 {
    let start = token.start.max(cursor).min(line_length)
    let end = token.end.max(start).min(line_length)
    if cursor < start {
      words.push(cursor.reinterpret_as_uint())
      words.push(gap_metadata(language_id))
    }
    if start < end {
      words.push(start.reinterpret_as_uint())
      words.push(tag_to_metadata(token.tag, language_id~))
      continue end
    }
  } nobreak {
    cursor
  }
  if cursor < line_length || words.is_empty() {
    words.push(cursor.reinterpret_as_uint())
    words.push(gap_metadata(language_id))
  }
  words
}

///|
/// Converts even slots from token starts to exclusive token ends exactly once.
/// The final token ends at the raw UTF-16 line length.
fn start_offsets_to_end_offsets(
  words : Array[UInt32],
  line_length : Int32,
) -> Unit {
  if words.length() < 2 {
    return
  }
  let count = words.length() >> 1
  for i in 0..<count {
    let end_offset = if i + 1 < count {
      words[(i + 1) << 1]
    } else {
      line_length.reinterpret_as_uint()
    }
    words[i << 1] = end_offset
  }
}

///|
/// The metadata word for gap / trailing / blank segments: a `Plain` tag tagged
/// with the model's `language_id`. Equals `LineTokens::default_token_metadata`
/// for the fields the renderer reads (foreground + font style) and, at
/// `language_id = 0`, in the language field too.
fn gap_metadata(language_id : Int32) -> UInt32 {
  tag_to_metadata(Plain, language_id~)
}
