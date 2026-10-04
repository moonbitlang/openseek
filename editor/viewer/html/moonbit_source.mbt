///|
/// Tokenizes MoonBit source into one escaped Rabbita fragment per source line.
///
/// Each fragment carries the editor's production `mtk<n>` classes but no line
/// break or wrapper. Lexer state flows across the whole input before the array
/// is returned, so callers that add gutters or other line chrome do not lose
/// multiline comments and strings by tokenizing each line independently.
pub fn moonbit_source_lines(source : String) -> Array[@rhtml.Html] {
  tokenized_lines(source, Some(@lang_moonbit.MoonBitTokenizer()), _ => true)
}

///|
/// The tokenization behind `moonbit_source_lines`, materializing fragments
/// only for the lines `keep` admits — in order, without placeholders for the
/// rest. Every line is still lexed so state keeps flowing across a skipped
/// region; what a dropped line saves is its token inflation and span nodes,
/// which is what lets the numbered clamp decide before building instead of
/// building tens of thousands of rows to discard. Without a tokenizer every
/// kept line is one plain escaped text node.
fn tokenized_lines(
  source : String,
  tokenizer : &@syntax.LineTokenizer?,
  keep : (Int) -> Bool,
) -> Array[@rhtml.Html] {
  let lines : Array[@rhtml.Html] = []
  guard tokenizer is Some(tokenizer) else {
    for index, line in source.split("\n") {
      if keep(index) {
        lines.push(@rhtml.text(line.to_owned()))
      }
    }
    return lines
  }
  let mut state = tokenizer.initial_state()
  let mut index = -1
  for line_view in source.split("\n") {
    index += 1
    let line = line_view.to_owned()
    let (syntax_tokens, next_state) = tokenizer.tokenize_line(line, state)
    state = next_state
    if !keep(index) {
      continue
    }
    let children : Array[@rhtml.Html] = []
    let tokens = @model.line_tokens_from_lexer_tokens(
      line, syntax_tokens, @services.language_id_codec,
    ).inflate()
    let mut offset = 0
    for token_index in 0..<tokens.get_count() {
      let end_offset = tokens.get_end_offset(token_index)
      if offset < end_offset {
        children.push(
          @rhtml.span(
            class=tokens.get_class_name(token_index),
            line[offset:end_offset].to_owned(),
          ),
        )
      }
      offset = end_offset
    }
    lines.push(@rhtml.fragment(children))
  }
  lines
}

///|
/// Numbered rendering keeps every row of a real program: the bound exists only
/// for a degenerate payload (a transcript's argument ceiling still admits tens
/// of thousands of two-character lines), where it caps the DOM at head + tail
/// rows around one unnumbered skip marker. Recorded programs top out near 40
/// lines, so an honest clamp this generous is display-invisible in practice.
const NUMBERED_HEAD_LINES = 400

///|
const NUMBERED_TAIL_LINES = 100

///|
/// Renders MoonBit source as escaped Rabbita text nodes carrying the editor's
/// `mtk<n>` token classes. The lexer and the token-to-theme projection both use
/// the editor's production pipeline, so lightweight HTML hosts render the same
/// syntax classes as the full viewer without installing source as raw HTML.
pub fn moonbit_source_code(source : String) -> @rhtml.Html {
  let children : Array[@rhtml.Html] = []
  for line_number, line in moonbit_source_lines(source) {
    if line_number > 0 {
      children.push(@rhtml.text("\n"))
    }
    children.push(line)
  }
  @rhtml.code(class="language-moonbit", children)
}

///|
/// Renders MoonBit source as numbered lines: each line becomes a
/// `moonbit-line` row pairing a right-aligned 1-based line number with that
/// line's source, highlighted by the same token pipeline as
/// `moonbit_source_code`. Numbers are space-padded to the width of the last
/// line's number so rows align without the gutter cells sharing a measured
/// column — each row is its own `moonbit-line` grid, and `white-space: pre`
/// on the gutter keeps the padding. The numbers are display chrome for
/// matching diagnostics that cite `line:column` positions, not part of the
/// program: hosts mark the gutter `user-select: none` so copied text is the
/// source alone.
///
/// A numbered render never lies about a line's position: past the degenerate
/// line-count bound it keeps the head and tail rows under their true numbers
/// with an unnumbered `moonbit-skip` row stating what was elided, rather than
/// renumbering or growing the DOM without bound.
pub fn moonbit_numbered_source(source : String) -> @rhtml.Html {
  numbered_rows(
    source,
    Some(@lang_moonbit.MoonBitTokenizer()),
    "language-moonbit moonbit-code",
  )
}

///|
/// Renders any source as the same numbered rows as `moonbit_numbered_source`,
/// highlighted by the caller's editor tokenizer. File-extension policy belongs
/// to the caller; without a tokenizer each line is plain escaped text, still
/// numbered and clamped the same way. Rows share the `moonbit-line`,
/// `moonbit-gutter` and `moonbit-code` classes so hosts style every numbered
/// listing with one rule set.
pub fn numbered_source(
  source : String,
  tokenizer? : &@syntax.LineTokenizer,
) -> @rhtml.Html {
  numbered_rows(source, tokenizer, "moonbit-code")
}

///|
fn numbered_rows(
  source : String,
  tokenizer : &@syntax.LineTokenizer?,
  code_class : String,
) -> @rhtml.Html {
  // Decide what to keep before anything is built: past the bound, only the
  // head and tail lines ever materialize spans — a degenerate line count must
  // not construct tens of thousands of rows just to discard the middle.
  let total = source.split("\n").count()
  let clamped = total > NUMBERED_HEAD_LINES + NUMBERED_TAIL_LINES + 1
  let keep = (index : Int) => {
    !clamped ||
    index < NUMBERED_HEAD_LINES ||
    index >= total - NUMBERED_TAIL_LINES
  }
  let lines = tokenized_lines(source, tokenizer, keep)
  let width = total.to_string().length()
  let rows : Array[@rhtml.Html] = []
  for position, line in lines {
    if clamped && position == NUMBERED_HEAD_LINES {
      let skipped = total - NUMBERED_HEAD_LINES - NUMBERED_TAIL_LINES
      rows.push(
        @rhtml.span(class="moonbit-line", [
          // Padded to the shared gutter width: each row is its own grid, so
          // an empty cell would collapse its `max-content` column and shove
          // the marker out from under the code column.
          @rhtml.span(class="moonbit-gutter", " ".repeat(width)),
          @rhtml.span(
            class="moonbit-code moonbit-skip",
            "⋯ \{skipped} lines skipped ⋯",
          ),
        ]),
      )
    }
    // A kept position past the head belongs to the tail, whose true numbers
    // resume after the skipped middle.
    let number = if clamped && position >= NUMBERED_HEAD_LINES {
      total - NUMBERED_TAIL_LINES + position - NUMBERED_HEAD_LINES + 1
    } else {
      position + 1
    }
    let text = number.to_string()
    rows.push(
      @rhtml.span(class="moonbit-line", [
        @rhtml.span(
          class="moonbit-gutter",
          " ".repeat(width - text.length()) + text,
        ),
        @rhtml.code(class=code_class, [line]),
      ]),
    )
  }
  @rhtml.fragment(rows)
}
