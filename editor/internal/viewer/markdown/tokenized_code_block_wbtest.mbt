///|
fn register_shared_markdown_test_tokenizer() -> Unit {
  @syntax.tokenization_registry.register(
    "moonbit",
    @plain_tokenizer.PlainTokenizer(),
  )
  |> ignore
}

///|
test "shared tokenized code override emits editor classes and threads active language" {
  register_shared_markdown_test_tokenizer()
  let fenced = render_markdown(
    (
      #|```mbt
      #|let answer = 42
      #|```
    ),
    language_id="plaintext",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(fenced.has_code_block)
  assert_true(fenced.html.contains("monaco-tokenized-source"))
  assert_true(fenced.html.contains("class=\"mtk3\""))

  let active = render_markdown(
    (
      #|```
      #|fn active() -> Unit {}
      #|```
    ),
    language_id="moonbit",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(active.html.contains("monaco-tokenized-source"))
  assert_true(active.html.contains("class=\"mtk3\""))
}

///|
test "mbtx fences share the moonbit tokenizer with mbt fences" {
  register_shared_markdown_test_tokenizer()
  let mbt = render_markdown(
    (
      #|```mbt
      #|let answer = 42
      #|```
    ),
    code_block_renderer=render_tokenized_code_block,
  )
  let mbtx = render_markdown(
    (
      #|```mbtx
      #|let answer = 42
      #|```
    ),
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(mbtx.has_code_block)
  assert_true(mbtx.html.contains("monaco-tokenized-source"))
  assert_true(mbtx.html.contains("class=\"mtk3\""))
  // Same program text, same tokenizer: an mbtx fence is an mbt fence, and
  // the only extra construct mbtx adds — its `import` block — is already a
  // MoonBit keyword in that shared tokenizer.
  assert_eq(mbtx.html, mbt.html)
}

///|
test "shared tokenized code override keeps unknown-language source as safe default tokens" {
  let rendered = render_markdown(
    (
      #|```unknown
      #|not really code
      #|```
    ),
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(rendered.has_code_block)
  assert_true(rendered.html.contains("monaco-tokenized-source"))
  assert_true(rendered.html.contains("class=\"mtk1\""))
  assert_true(rendered.html.contains("not really code"))
}
