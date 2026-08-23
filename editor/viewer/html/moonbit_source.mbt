///|
/// Tokenizes MoonBit source into one escaped Rabbita fragment per source line.
///
/// Each fragment carries the editor's production `mtk<n>` classes but no line
/// break or wrapper. Lexer state flows across the whole input before the array
/// is returned, so callers that add gutters or other line chrome do not lose
/// multiline comments and strings by tokenizing each line independently.
pub fn moonbit_source_lines(source : String) -> Array[@rhtml.Html] {
  let tokenizer : &@syntax.LineTokenizer = @lang_moonbit.MoonBitTokenizer()
  let lines : Array[@rhtml.Html] = []
  let mut state = tokenizer.initial_state()
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    let children : Array[@rhtml.Html] = []
    let (syntax_tokens, next_state) = tokenizer.tokenize_line(line, state)
    state = next_state
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
