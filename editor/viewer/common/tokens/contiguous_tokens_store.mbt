///| Source-shaped readonly port of Monaco's `ContiguousTokensStore`.
///
/// Source: `vscode/src/vs/editor/common/tokens/contiguousTokensStore.ts` at
/// checked-in oracle.
///
/// The local representation keeps Monaco's three observable store states:
/// `Missing` is an uninitialized sparse slot, `Empty` is the compact empty-line
/// sentinel, and `Words` holds encoded `[endOffset, metadata]` pairs. MoonBit
/// has one owned `Array[UInt]` representation, so the source's typed-array
/// versus ArrayBuffer identity branches do not exist. Incremental editing and
/// sparse semantic-token application remain outside this readonly package.

///|
/// One initialized or uninitialized syntactic-token slot.
/// Source: `contiguousTokensStore.ts:20` and `contiguousTokensEditing.ts:8`.
priv enum SyntacticLineTokens {
  Missing
  Empty
  Words(Array[UInt])
}

///|
/// Inclusive changed-line interval produced by one contiguous batch.
/// Source: `contiguousTokensStore.ts:213-244`.
pub struct ContiguousTokensStoreChange {
  from_line_number : Int
  to_line_number : Int
}

///|
/// Ordered changed intervals from `set_multiline_tokens`.
/// Source: `contiguousTokensStore.ts:213-244`.
pub struct ContiguousTokensStoreUpdate {
  changes : Array[ContiguousTokensStoreChange]
}

///|
/// Per-model contiguous syntactic token storage.
/// Source: `contiguousTokensStore.ts:19-22`.
struct ContiguousTokensStore {
  line_tokens : Array[SyntacticLineTokens]
  mut len : Int
  language_id_codec : @services.LanguageIdCodec
}

///|
/// Creates an empty store retaining the shared language-id codec.
/// Source: `contiguousTokensStore.ts:24-28`.
pub fn ContiguousTokensStore::ContiguousTokensStore(
  language_id_codec : @services.LanguageIdCodec,
) -> ContiguousTokensStore {
  { line_tokens: [], len: 0, language_id_codec, }
}

///|
/// Drops every initialized slot and resets the logical initialized prefix.
/// Source: `contiguousTokensStore.ts:30-33`.
pub fn ContiguousTokensStore::flush(self : ContiguousTokensStore) -> Unit {
  self.line_tokens.clear()
  self.len = 0
}

///|
/// True when the physical per-line array is nonempty.
/// Source: `contiguousTokensStore.ts:35-37`.
#warnings("-unused_value")
fn ContiguousTokensStore::has_tokens(self : ContiguousTokensStore) -> Bool {
  self.line_tokens.length() > 0
}

///|
/// Passively reads stored words or returns one top-level-language fallback
/// token. This operation never invokes a tokenizer.
/// Source: `contiguousTokensStore.ts:39-53`.
pub fn ContiguousTokensStore::get_tokens(
  self : ContiguousTokensStore,
  top_level_language_id : String,
  line_index : Int,
  line_text : String,
) -> LineTokens {
  let raw_line_tokens = if line_index < self.len {
    self.line_tokens[line_index]
  } else {
    Missing
  }
  match raw_line_tokens {
    Words(tokens) => LineTokens(tokens, line_text, self.language_id_codec)
    Missing | Empty => {
      let line_tokens : Array[UInt] = [
        line_text.length().reinterpret_as_uint(),
        self.default_metadata(top_level_language_id),
      ]
      LineTokens(line_tokens, line_text, self.language_id_codec)
    }
  }
}

///|
/// Builds Monaco's exact fallback metadata, including its no-grammar balanced
/// brackets guess.
/// Source: `contiguousTokensStore.ts:247-257`.
fn ContiguousTokensStore::default_metadata(
  self : ContiguousTokensStore,
  top_level_language_id : String,
) -> UInt {
  let language_id = self.language_id_codec.encode_language_id(
    top_level_language_id,
  )
  ((language_id << METADATA_LANGUAGEID_OFFSET) |
  (STANDARD_TOKEN_TYPE_OTHER << METADATA_TOKEN_TYPE_OFFSET) |
  (FONT_STYLE_NONE << METADATA_FONT_STYLE_OFFSET) |
  (COLOR_ID_DEFAULT_FOREGROUND << METADATA_FOREGROUND_OFFSET) |
  (COLOR_ID_DEFAULT_BACKGROUND << METADATA_BACKGROUND_OFFSET) |
  (1 << METADATA_BALANCED_BRACKETS_OFFSET)).reinterpret_as_uint()
}

///|
/// Normalizes one tokenizer result before storage. `Missing` is never returned:
/// it is reserved for slots that have not been written.
/// Source: `contiguousTokensStore.ts:55-85`.
fn ContiguousTokensStore::massage_tokens(
  self : ContiguousTokensStore,
  top_level_language_id : String,
  line_text_length : Int,
  tokens : Array[UInt]?,
) -> SyntacticLineTokens {
  let encoded_language_id = self.language_id_codec.encode_language_id(
    top_level_language_id,
  )
  if line_text_length == 0 {
    let has_different_language_id = tokens is Some([_, second, ..]) &&
      TokenMetadata(second).get_language_id() != encoded_language_id
    if !has_different_language_id {
      return Empty
    }
  }
  match tokens {
    None | Some([]) =>
      Words([
        line_text_length.reinterpret_as_uint(),
        self.default_metadata(top_level_language_id),
      ])
    Some(words) => {
      words[words.length() - 2] = line_text_length.reinterpret_as_uint()
      Words(words)
    }
  }
}

///|
/// Grows the initialized prefix through `line_index`, filling holes with
/// `Missing` exactly as Monaco fills them with null.
/// Source: `contiguousTokensStore.ts:87-92`.
fn ContiguousTokensStore::ensure_line(
  self : ContiguousTokensStore,
  line_index : Int,
) -> Unit {
  while line_index >= self.len {
    self.line_tokens.push(Missing)
    self.len += 1
  }
}

///|
/// Stores one normalized line. Equality is checked only when requested; the
/// unchecked suffix lane always reports false.
/// Source: `contiguousTokensStore.ts:117-127`.
fn ContiguousTokensStore::set_tokens(
  self : ContiguousTokensStore,
  top_level_language_id : String,
  line_index : Int,
  line_text_length : Int,
  tokens : Array[UInt]?,
  check_equality : Bool,
) -> Bool {
  let new_tokens = self.massage_tokens(
    top_level_language_id, line_text_length, tokens,
  )
  self.ensure_line(line_index)
  let old_tokens = self.line_tokens[line_index]
  self.line_tokens[line_index] = new_tokens
  if check_equality {
    !syntactic_line_tokens_equal(old_tokens, new_tokens)
  } else {
    false
  }
}

///|
/// Preserves the source equality distinctions and compares `Words`
/// element-by-element.
/// Source: `contiguousTokensStore.ts:129-146`.
fn syntactic_line_tokens_equal(
  left : SyntacticLineTokens,
  right : SyntacticLineTokens,
) -> Bool {
  match (left, right) {
    (Missing, Missing) | (Empty, Empty) => true
    (Words(left_words), Words(right_words)) => left_words == right_words
    _ => false
  }
}

///|
/// Applies batches in order. Within each batch it checks equality only through
/// the first changed line, then writes the remaining suffix unchecked and
/// returns one inclusive min/max interval.
/// Source: `contiguousTokensStore.ts:213-244`.
pub fn ContiguousTokensStore::set_multiline_tokens(
  self : ContiguousTokensStore,
  tokens : Array[ContiguousMultilineTokens],
  top_level_language_id : String,
  get_line_length : (Int) -> Int,
) -> ContiguousTokensStoreUpdate {
  if tokens.length() == 0 {
    return { changes: [], }
  }
  let ranges : Array[ContiguousTokensStoreChange] = []
  for element in tokens {
    let mut min_changed_line_number = 0
    let mut max_changed_line_number = 0
    let mut has_change = false
    for line_number in element.start_line_number()..<=element.end_line_number() {
      if has_change {
        ignore(
          self.set_tokens(
            top_level_language_id,
            line_number - 1,
            get_line_length(line_number),
            Some(element.get_line_tokens(line_number)),
            false,
          ),
        )
        max_changed_line_number = line_number
      } else {
        let line_has_change = self.set_tokens(
          top_level_language_id,
          line_number - 1,
          get_line_length(line_number),
          Some(element.get_line_tokens(line_number)),
          true,
        )
        if line_has_change {
          has_change = true
          min_changed_line_number = line_number
          max_changed_line_number = line_number
        }
      }
    }
    if has_change {
      ranges.push({
        from_line_number: min_changed_line_number,
        to_line_number: max_changed_line_number,
      })
    }
  }
  { changes: ranges, }
}
