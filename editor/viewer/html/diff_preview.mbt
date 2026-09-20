///|
/// One physical source line in a recorded patch. Coordinates belong to the
/// caller and may be absent. Gap separates excerpts whose lexical context is
/// unknown; it resets both tokenizers without inventing source or coordinates.
pub(all) enum DiffLine {
  Context(String, old_line~ : Int?, new_line~ : Int?)
  Added(String, line~ : Int?)
  Removed(String, line~ : Int?)
  Gap
}

///|
priv struct DiffSyntax {
  tokenizer : &@syntax.LineTokenizer
  mut original : @syntax.TokenizerState
  mut modified : @syntax.TokenizerState
}

///|
/// Each side advances independently: a removed multiline comment must not
/// color its replacement. Context is displayed using the modified-side state.
fn DiffSyntax::render(
  self : DiffSyntax,
  line : DiffLine,
  source : String,
) -> @rhtml.Html {
  if line is Gap {
    self.original = self.tokenizer.initial_state()
    self.modified = self.tokenizer.initial_state()
    return @rhtml.text(source)
  }
  let state = if line is Removed(_, ..) { self.original } else { self.modified }
  if !(line is Added(_, ..)) {
    let (_, next) = self.tokenizer.tokenize_line(source, self.original)
    self.original = next
  }
  if !(line is Removed(_, ..)) {
    let (_, next) = self.tokenizer.tokenize_line(source, self.modified)
    self.modified = next
  }
  let (lexed, _) = self.tokenizer.tokenize_line(source, state)
  let tokens = @model.line_tokens_from_lexer_tokens(
    source, lexed, @services.language_id_codec,
  ).inflate()
  let spans : Array[@rhtml.Html] = []
  let mut start = 0
  for index in 0..<tokens.get_count() {
    let end = tokens.get_end_offset(index)
    if start < end {
      spans.push(
        @rhtml.span(
          class=tokens.get_class_name(index),
          source[start:end].to_owned(),
        ),
      )
    }
    start = end
  }
  @rhtml.fragment(spans)
}

///|
/// Accepts already ordered patch rows, not files to compare. A caller-supplied
/// editor tokenizer enables highlighting; omission preserves escaped plain
/// text. Rows must contain one line each. Callers bound large previews and use
/// Gap for omitted source; this component never silently truncates a snapshot.
///
/// Reuse the returned HTML during unrelated host renders to avoid repeating
/// tokenization. Load `viewer/html/diff_preview.css` and the editor token
/// stylesheet inside the host's editor theme. Titlebars and file actions stay
/// outside this scroll surface and remain the caller's responsibility.
/// The required label names the focusable region; hosts localize it and include
/// file/range context so multiple previews can be distinguished.
pub fn diff_preview(
  lines : Array[DiffLine],
  label~ : String,
  tokenizer? : &@syntax.LineTokenizer,
) -> @rhtml.Html {
  let syntax = tokenizer.map(tokenizer => DiffSyntax::{
    tokenizer,
    original: tokenizer.initial_state(),
    modified: tokenizer.initial_state(),
  })
  let rows : Array[@rhtml.Html] = []
  for line in lines {
    // One coordinate column leaves more room for source. Context follows the
    // modified file, falling back to its original coordinate when unknown.
    let (source, number, sign, kind) = match line {
      Context(source, old_line~, new_line~) =>
        (
          source,
          if new_line is Some(_) {
            new_line
          } else {
            old_line
          },
          " ",
          "context",
        )
      Added(source, line~) => (source, line, "+", "added")
      Removed(source, line~) => (source, line, "−", "removed")
      Gap => ("…", None, " ", "gap")
    }
    let code = if syntax is Some(syntax) {
      syntax.render(line, source)
    } else {
      @rhtml.text(source)
    }
    rows.push(
      @rhtml.div(class="editor-diff-row \{kind}", [
        // One sticky element owns all gutter cells and an opaque background.
        // Their shared grid tracks stay aligned even across absent coordinates.
        @rhtml.span(class="editor-diff-gutter", [
          @rhtml.span(
            class="editor-diff-number",
            number.map(n => n.to_string()).unwrap_or(""),
          ),
          @rhtml.span(class="editor-diff-sign", sign),
        ]),
        @rhtml.code(class="editor-diff-source", [code]),
      ]),
    )
  }
  @rhtml.div(
    class="editor-diff-preview",
    attrs=@rhtml.Attrs::build().role("region").aria_label(label).tabindex(0),
    rows,
  )
}
