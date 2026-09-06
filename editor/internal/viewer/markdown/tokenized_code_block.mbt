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
  let code = code_block.code
  let codec = @services.language_id_codec
  let encoded_language_id = codec.register(language_id)
  let tokenizer = @syntax.tokenization_registry.get(language_id)
  let mut state = tokenizer.map(tokenizer => tokenizer.initial_state())
  @languages.tokenize_to_string(code, codec, line => {
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
  })
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
