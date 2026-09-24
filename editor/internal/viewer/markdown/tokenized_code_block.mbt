///|
/// Shared synchronous fenced-code override for editor-owned Markdown
/// consumers. Language selection follows the fenced info token first and the
/// caller's active model language second; output uses the existing editor
/// token classes and falls back to default-metadata spans when no tokenizer is
/// registered.
pub fn render_tokenized_code_block(
  code_block : MarkdownCodeBlock,
  active_language_id : String?,
) -> String {
  let language_id = markdown_code_language(code_block, active_language_id)
  let codec = @services.language_id_codec
  @languages.tokenize_to_string(
    code_block.code,
    codec,
    markdown_code_tokenizer(language_id, codec),
  )
}

///|
/// Renders exactly the projected code lines, retaining tokenization state
/// between lines. The callback wraps each line's escaped token HTML together
/// with its source facts; no synthetic trailing line is produced.
pub fn render_tokenized_code_lines(
  code_block : MarkdownCodeBlock,
  active_language_id : String?,
  render_line : (Int, MarkdownCodeLine, String) -> String,
) -> String {
  let language_id = markdown_code_language(code_block, active_language_id)
  let codec = @services.language_id_codec
  let tokenize = markdown_code_tokenizer(language_id, codec)
  let result = StringBuilder()
  result.write_string("<div class=\"monaco-tokenized-source\">")
  for line_index, line in code_block.code_lines {
    if line_index > 0 {
      result.write_string("<br/>")
    }
    let html = @languages.tokenize_line_to_string(
      line.displayed_text,
      codec,
      tokenize(line.displayed_text),
    )
    result.write_string(render_line(line_index, line, html))
  }
  result.write_string("</div>")
  result.to_string()
}

///|
fn markdown_code_tokenizer(
  language_id : String,
  codec : @services.LanguageIdCodec,
) -> (String) -> Array[UInt] {
  let encoded_language_id = codec.register(language_id)
  let tokenizer = @syntax.tokenization_registry.get(language_id)
  let mut state = tokenizer.map(tokenizer => tokenizer.initial_state())
  line => {
    let lexer_tokens = match (tokenizer, state) {
      (Some(tokenizer), Some(current)) => {
        let (tokens, next) = tokenizer.tokenize_line(line, current)
        state = Some(next)
        tokens
      }
      _ => []
    }
    let line_tokens = @model.line_tokens_from_lexer_tokens(
      line,
      lexer_tokens,
      codec,
      language_id=encoded_language_id,
    )
    let pairs : Array[UInt] = []
    for index in 0..<line_tokens.get_count() {
      pairs.push(line_tokens.get_start_offset(index).reinterpret_as_uint())
      pairs.push(line_tokens.get_metadata(index).to_uint())
    }
    pairs
  }
}

///|
fn markdown_code_language(
  code_block : MarkdownCodeBlock,
  active_language_id : String?,
) -> String {
  match code_block.language_id.unwrap_or(active_language_id.unwrap_or("")) {
    "mbt" | "mbtx" => "moonbit"
    "js" => "javascript"
    "ts" => "typescript"
    language => language
  }
}
