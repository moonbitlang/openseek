///|
test "safe conversion keeps raw HTML inert and removes unsafe link schemes" {
  let rendered = render_markdown(
    "<img src=x onerror=alert(1)> [unsafe](javascript:alert(1)) **safe**",
  )
  assert_false(rendered.html.contains("<img"))
  assert_false(rendered.html.contains("onerror"))
  assert_false(rendered.html.contains("javascript:"))
  assert_true(rendered.html.contains("<strong>safe</strong>"))
  assert_false(rendered.has_code_block)
  assert_eq(rendered.projection.code_blocks.length(), 0)
}

///|
test "conversion failure becomes one escaped plaintext paragraph" {
  let rendered = markdown_conversion_result(
    "<unsafe> & plain",
    Ref(true),
    empty_markdown_document_projection(),
    () => raise @cmark_renderer.RenderError("forced conversion failure"),
  )
  assert_eq(rendered.html, "<p>&lt;unsafe&gt; &amp; plain</p>\n")
  assert_false(rendered.has_code_block)
  assert_eq(rendered.projection, empty_markdown_document_projection())
}

///|
test "code override receives MoonBit DTO, fence language, and active language" {
  let mut observed_code = ""
  let mut observed_fence = ""
  let mut observed_info = ""
  let mut observed_remainder = ""
  let mut observed_source_line = 0
  let mut observed_active = ""
  let rendered = render_markdown(
    (
      #|```mbt extra
      #|let answer = 42
      #|```
    ),
    language_id="moonbit",
    code_block_renderer=fn(block, active_language_id) {
      observed_code = block.code
      observed_fence = block.language_id.unwrap_or("")
      observed_info = block.full_info_string.unwrap_or("")
      observed_remainder = block.info_remainder.unwrap_or("")
      observed_source_line = block.code_lines[0].source_line_number
      observed_active = active_language_id.unwrap_or("")
      "<pre data-rendered=\"yes\">override</pre>"
    },
  )
  assert_eq(observed_code, "let answer = 42\n")
  assert_eq(observed_fence, "mbt")
  assert_eq(observed_info, "mbt extra")
  assert_eq(observed_remainder, "extra")
  assert_eq(observed_source_line, 2)
  assert_eq(observed_active, "moonbit")
  assert_eq(rendered.html, "<pre data-rendered=\"yes\">override</pre>")
  assert_true(rendered.has_code_block)
  assert_eq(rendered.projection.code_blocks.length(), 1)
}

///|
test "default code rendering still reports code-block fact" {
  let rendered = render_markdown("    plain code")
  assert_true(rendered.html.contains("<pre><code>plain code\n</code></pre>"))
  assert_true(rendered.has_code_block)
  assert_eq(rendered.projection.code_blocks.length(), 1)
}
