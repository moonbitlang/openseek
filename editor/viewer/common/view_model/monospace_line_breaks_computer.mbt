// Ported from `vscode/src/vs/editor/common/viewModel/monospaceLineBreaksComputer.ts`
// (`MonospaceLineBreaksComputerFactory`, `createLineBreaks`,
// `computeCharWidth`, `canBreak`, `computeWrappedTextIndentLength`).
// Deviations:
//   - The incremental `createLineBreaksFromPreviousLineBreaks` path is not
//     ported — the readonly viewer reconstructs projections wholesale
//     (`construct_lines`), so every request takes the `createLineBreaks`
//     path (Monaco's own path whenever there is no previous break data).
//   - The experimental `wrapOnEscapedLineFeeds` option (and its
//     `isEscapedLineBreakAtPosition` scan) is not ported — no option surface.
//   - `add_request` receives the line's text and injected text directly
//     instead of Monaco's `ILineBreaksComputerContext` lookups, and the
//     result materializes the viewer's segment-based
//     `ModelLineProjectionData` from Monaco's
//     `breakOffsets`/`breakOffsetsVisibleColumn` pair.

///|
/// Monaco's `wordBreak` editor option (`'normal' | 'keepAll'`): `KeepAll`
/// disables the ideographic (CJK) break points.
pub(all) enum WordBreak {
  Normal
  KeepAll
} derive(Eq, Debug)

///|
/// Monaco `CharacterClass` (`monospaceLineBreaksComputer.ts`), as the small
/// integers the shared `CharacterClassifier` stores.
const CHARACTER_CLASS_NONE : Int = 0

///|
const CHARACTER_CLASS_BREAK_BEFORE : Int = 1

///|
const CHARACTER_CLASS_BREAK_AFTER : Int = 2

///|
const CHARACTER_CLASS_BREAK_IDEOGRAPHIC : Int = 3

///|
/// The defaults of Monaco's `wordWrapBreakAfterCharacters` editor option —
/// the viewer has no option surface for them.
let word_wrap_break_after_characters = " \t})]?|/&.,;¢°′″‰℃、。｡､￠，．：；？！％・･ゝゞヽヾーァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ々〻ｧｨｩｪｫｬｭｮｯｰ”〉》」』】〕）］｝｣"

///|
/// The defaults of Monaco's `wordWrapBreakBeforeCharacters` editor option.
let word_wrap_break_before_characters = "([{‘“〈《「『【〔（［｛｢£¥＄￡￥+＋"

///|
/// Monaco `WrappingCharacterClassifier`: the shared `CharacterClassifier`
/// seeded from the break-before/break-after strings, with the ideographic
/// ranges (CJK Unified Ideographs, Extension A, Hiragana and Katakana)
/// overriding the sparse map for non-ASCII lookups.
priv struct WrappingCharacterClassifier {
  classifier : @base_common.CharacterClassifier
}

///|
fn WrappingCharacterClassifier::new(
  break_before : String,
  break_after : String,
) -> WrappingCharacterClassifier {
  let classifier = @base_common.CharacterClassifier(CHARACTER_CLASS_NONE)
  for unit in break_before.code_units() {
    classifier.set(unit.to_int(), CHARACTER_CLASS_BREAK_BEFORE)
  }
  for unit in break_after.code_units() {
    classifier.set(unit.to_int(), CHARACTER_CLASS_BREAK_AFTER)
  }
  { classifier, }
}

///|
fn WrappingCharacterClassifier::get(
  self : WrappingCharacterClassifier,
  char_code : Int,
) -> Int {
  if char_code >= 0 && char_code < 256 {
    self.classifier.get(char_code)
  } else if (char_code >= 0x3040 && char_code <= 0x30ff) ||
    (char_code >= 0x3400 && char_code <= 0x4dbf) ||
    (char_code >= 0x4e00 && char_code <= 0x9fff) {
    CHARACTER_CLASS_BREAK_IDEOGRAPHIC
  } else {
    self.classifier.get(char_code)
  }
}

///|
/// Monaco `MonospaceLineBreaksComputerFactory`.
struct MonospaceLineBreaksComputerFactory {
  classifier : WrappingCharacterClassifier
}

///|
pub fn MonospaceLineBreaksComputerFactory::MonospaceLineBreaksComputerFactory(
  break_before_chars : String,
  break_after_chars : String,
) -> MonospaceLineBreaksComputerFactory {
  {
    classifier: WrappingCharacterClassifier::new(
      break_before_chars, break_after_chars,
    ),
  }
}

///|
/// Monaco `MonospaceLineBreaksComputerFactory.create`, over the
/// `wordWrapBreakBeforeCharacters`/`wordWrapBreakAfterCharacters` defaults.
pub fn MonospaceLineBreaksComputerFactory::create() -> MonospaceLineBreaksComputerFactory {
  MonospaceLineBreaksComputerFactory(
    word_wrap_break_before_characters, word_wrap_break_after_characters,
  )
}

///|
/// The factory singleton the view-model line collection uses (Monaco creates
/// one factory per code editor widget and hands it to the view model).
pub let monospace_line_breaks_computer_factory : MonospaceLineBreaksComputerFactory = MonospaceLineBreaksComputerFactory::create()

///|
/// One batched line-break request: the model line's text plus its injected
/// text (Monaco reads both back through `ILineBreaksComputerContext`).
priv struct LineBreaksRequest {
  model_line_number : Int
  line_text : String
  injected_text : Array[InjectedText]
}

///|
/// Monaco `ILineBreaksComputer`: requests batch up through `add_request` and
/// `finalize` computes them in one pass.
struct LineBreaksComputer {
  classifier : WrappingCharacterClassifier
  font_info : @config.FontInfo
  tab_size : Int
  wrapping_column : Int
  wrapping_indent : @editor_api.WrappingIndent
  word_break : WordBreak
  requests : Array[LineBreaksRequest]
}

///|
/// Monaco `createLineBreaksComputer` (`wrapping_column <= 0` is the viewer's
/// form of Monaco's `wrappingColumn === -1`, wrapping off).
pub fn MonospaceLineBreaksComputerFactory::create_line_breaks_computer(
  self : MonospaceLineBreaksComputerFactory,
  font_info~ : @config.FontInfo,
  tab_size~ : Int,
  wrapping_column~ : Int,
  wrapping_indent~ : @editor_api.WrappingIndent,
  word_break? : WordBreak = Normal,
) -> LineBreaksComputer {
  {
    classifier: self.classifier,
    font_info,
    tab_size: tab_size.max(1),
    wrapping_column,
    wrapping_indent,
    word_break,
    requests: [],
  }
}

///|
pub fn LineBreaksComputer::add_request(
  self : LineBreaksComputer,
  model_line_number : Int,
  line_text : String,
  injected_text : Array[InjectedText],
) -> Unit {
  self.requests.push({ model_line_number, line_text, injected_text })
}

///|
/// Computes every batched request. `None` is Monaco's `null` result: a line
/// with no injected text that needs no wrapping projects as `Identity`.
pub fn LineBreaksComputer::finalize(
  self : LineBreaksComputer,
) -> Array[ModelLineProjectionData?] {
  let columns_for_full_width_char = self.font_info.typical_fullwidth_character_width /
    self.font_info.typical_halfwidth_character_width
  let result : Array[ModelLineProjectionData?] = []
  for request in self.requests {
    let has_injections = request.injected_text.length() > 0
    if !has_injections && self.wrapping_column <= 0 {
      // No wrapping and nothing injected: `createLineBreaks` would return
      // null before doing any work.
      result.push(None)
      continue
    }
    let projected_line = ProjectedTextLine::from_injected_text(
      request.line_text,
      request.injected_text,
    )
    result.push(
      create_line_breaks(
        self.classifier,
        request.model_line_number,
        projected_line,
        has_injections,
        self.tab_size,
        self.wrapping_column,
        columns_for_full_width_char,
        self.wrapping_indent,
        self.word_break == KeepAll,
      ),
    )
  }
  result
}

///|
/// Monaco `createLineBreaks`: one line's break offsets and their visible
/// columns, walked with Monaco's exact width and break rules (surrogate
/// pairs are unbreakable width-2 units; tab widths depend on the visible
/// column; full-width and control characters advance by
/// `columns_for_full_width_char`).
fn create_line_breaks(
  classifier : WrappingCharacterClassifier,
  model_line_number : Int,
  projected_line : ProjectedTextLine,
  has_injections : Bool,
  tab_size : Int,
  first_line_break_column : Int,
  columns_for_full_width_char : Double,
  wrapping_indent : @editor_api.WrappingIndent,
  is_keep_all : Bool,
) -> ModelLineProjectionData? {
  let line_text = projected_line.text
  let len = line_text.length()
  if first_line_break_column <= 0 || len <= 1 {
    if !has_injections {
      return None
    }
    // A `LineBreakData` with no real break: injected text still needs the
    // projection (Monaco builds it with `breakOffsets = [lineText.length]`).
    return Some(
      materialize_projection_data(
        model_line_number,
        projected_line,
        [len],
        [0.0],
        0,
      ),
    )
  }
  let wrapped_text_indent_length = compute_wrapped_text_indent_length(
    line_text, tab_size, first_line_break_column, columns_for_full_width_char, wrapping_indent,
  )
  let wrapped_line_break_column = first_line_break_column.to_double() -
    wrapped_text_indent_length.to_double()
  let breaking_offsets : Array[Int] = []
  let breaking_offsets_visible_column : Array[Double] = []
  let mut break_offset = 0
  let mut break_offset_visible_column = 0.0
  let mut breaking_column = first_line_break_column.to_double()
  let mut prev_char_code = line_text[0].to_int()
  let mut prev_char_code_class = classifier.get(prev_char_code)
  let mut visible_column = compute_char_width(
    prev_char_code, 0.0, tab_size, columns_for_full_width_char,
  )
  let mut start_offset = 1
  if @base_common.is_high_surrogate(prev_char_code) {
    // A surrogate pair must always be considered as a single unit, so it is
    // never to be broken.
    visible_column = visible_column + 1.0
    prev_char_code = line_text[1].to_int()
    prev_char_code_class = classifier.get(prev_char_code)
    start_offset = start_offset + 1
  }
  let mut i = start_offset
  while i < len {
    let char_start_offset = i
    let char_code = line_text[i].to_int()
    let mut char_code_class = CHARACTER_CLASS_NONE
    let mut char_width = 0.0
    if @base_common.is_high_surrogate(char_code) {
      // A surrogate pair must always be considered as a single unit, so it
      // is never to be broken.
      i = i + 1
      char_code_class = CHARACTER_CLASS_NONE
      char_width = 2.0
    } else {
      char_code_class = classifier.get(char_code)
      char_width = compute_char_width(
        char_code, visible_column, tab_size, columns_for_full_width_char,
      )
    }
    if can_break(
        prev_char_code, prev_char_code_class, char_code, char_code_class, is_keep_all,
      ) {
      break_offset = char_start_offset
      break_offset_visible_column = visible_column
    }
    visible_column = visible_column + char_width
    // Check if adding character at `i` will go over the breaking column.
    if visible_column > breaking_column {
      // We need to break at least before character at `i`:
      if break_offset == 0 ||
        visible_column - break_offset_visible_column > wrapped_line_break_column {
        // Cannot break at `break_offset`, must break at `i`.
        break_offset = char_start_offset
        break_offset_visible_column = visible_column - char_width
      }
      breaking_offsets.push(break_offset)
      breaking_offsets_visible_column.push(break_offset_visible_column)
      breaking_column = break_offset_visible_column + wrapped_line_break_column
      break_offset = 0
    }
    prev_char_code = char_code
    prev_char_code_class = char_code_class
    i = i + 1
  }
  if breaking_offsets.length() == 0 && !has_injections {
    return None
  }
  // Add last segment.
  breaking_offsets.push(len)
  breaking_offsets_visible_column.push(visible_column)
  Some(
    materialize_projection_data(
      model_line_number, projected_line, breaking_offsets, breaking_offsets_visible_column,
      wrapped_text_indent_length,
    ),
  )
}

///|
/// Materializes the viewer's per-segment `ModelLineProjectionData` from
/// Monaco's `breakOffsets`/`breakOffsetsVisibleColumn` pair. Segment `k`
/// covers `[breakOffsets[k-1], breakOffsets[k])`;
/// `continues_with_wrapped_line` is Monaco's
/// `outputLineIndex + 1 < viewLineCount` (`modelLineProjection.ts`), and the
/// continuation indent applies to every segment but the first
/// (`getMinOutputOffset`).
fn materialize_projection_data(
  model_line_number : Int,
  projected_line : ProjectedTextLine,
  breaking_offsets : Array[Int],
  breaking_offsets_visible_column : Array[Double],
  wrapped_text_indent_length : Int,
) -> ModelLineProjectionData {
  let segments : Array[ModelLineProjectionSegment] = []
  for k in 0..<breaking_offsets.length() {
    segments.push(
      model_line_projection_segment(
        model_line_number,
        if k == 0 {
          0
        } else {
          breaking_offsets[k - 1]
        },
        breaking_offsets[k],
        if k == 0 {
          0.0
        } else {
          breaking_offsets_visible_column[k - 1]
        },
        k + 1 < breaking_offsets.length(),
        if k > 0 {
          wrapped_text_indent_length
        } else {
          0
        },
      ),
    )
  }
  ModelLineProjectionData(
    model_line_number,
    projected_line.model_line_length,
    projected_line,
    segments,
  )
}

///|
/// Monaco `computeCharWidth`: tab widths fill to the next tab stop;
/// full-width characters and control characters (whose
/// `renderControlCharacters` substitutions are often wide) advance by
/// `columns_for_full_width_char`.
fn compute_char_width(
  char_code : Int,
  visible_column : Double,
  tab_size : Int,
  columns_for_full_width_char : Double,
) -> Double {
  if char_code == 9 {
    return tab_size.to_double() - visible_column % tab_size.to_double()
  }
  if @base_common.is_full_width_character(char_code) {
    return columns_for_full_width_char
  }
  if char_code < 32 {
    // When using `editor.renderControlCharacters`, the substitutions are
    // often wide.
    return columns_for_full_width_char
  }
  1.0
}

///|
fn tab_character_width(visible_column : Int, tab_size : Int) -> Int {
  tab_size - visible_column % tab_size
}

///|
/// Monaco `canBreak` — Kinsoku Shori: don't break after a leading character
/// (like an open bracket) and don't break before a trailing character (like
/// a period). `is_keep_all` (`wordBreak: 'keepAll'`) disables the
/// ideographic break points.
fn can_break(
  _prev_char_code : Int,
  prev_char_code_class : Int,
  char_code : Int,
  char_code_class : Int,
  is_keep_all : Bool,
) -> Bool {
  char_code != 32 &&
  (
    (
      prev_char_code_class == CHARACTER_CLASS_BREAK_AFTER &&
      char_code_class != CHARACTER_CLASS_BREAK_AFTER
    ) ||
    (
      prev_char_code_class != CHARACTER_CLASS_BREAK_BEFORE &&
      char_code_class == CHARACTER_CLASS_BREAK_BEFORE
    ) ||
    (
      !is_keep_all &&
      prev_char_code_class == CHARACTER_CLASS_BREAK_IDEOGRAPHIC &&
      char_code_class != CHARACTER_CLASS_BREAK_AFTER
    ) ||
    (
      !is_keep_all &&
      char_code_class == CHARACTER_CLASS_BREAK_IDEOGRAPHIC &&
      prev_char_code_class != CHARACTER_CLASS_BREAK_BEFORE
    )
  )
}

///|
/// Monaco `computeWrappedTextIndentLength`: the model line's own leading
/// whitespace width, plus one/two extra tab stops for `Indent`/`DeepIndent`;
/// forced back to `0` when no character would fit except for the
/// indentation.
fn compute_wrapped_text_indent_length(
  line_text : String,
  tab_size : Int,
  first_line_break_column : Int,
  columns_for_full_width_char : Double,
  wrapping_indent : @editor_api.WrappingIndent,
) -> Int {
  let mut wrapped_text_indent_length = 0
  if wrapping_indent != None {
    let first_non_whitespace_index = @base_common.first_non_whitespace_index(
      line_text,
    )
    if first_non_whitespace_index != -1 {
      // Track existing indent.
      for i in 0..<first_non_whitespace_index {
        let char_width = if line_text[i].to_int() == 9 {
          tab_character_width(wrapped_text_indent_length, tab_size)
        } else {
          1
        }
        wrapped_text_indent_length = wrapped_text_indent_length + char_width
      }
      // Increase indent of continuation lines, if desired.
      let number_of_additional_tabs = match wrapping_indent {
        DeepIndent => 2
        Indent => 1
        _ => 0
      }
      for _ in 0..<number_of_additional_tabs {
        wrapped_text_indent_length = wrapped_text_indent_length +
          tab_character_width(wrapped_text_indent_length, tab_size)
      }
      // Force sticking to beginning of line if no character would fit except
      // for the indentation.
      if wrapped_text_indent_length.to_double() + columns_for_full_width_char >
        first_line_break_column.to_double() {
        wrapped_text_indent_length = 0
      }
    }
  }
  wrapped_text_indent_length
}

///|
pub extend WordBreak with Debug::{to_repr}

///|
pub extend WordBreak with Eq::{equal, not_equal}
