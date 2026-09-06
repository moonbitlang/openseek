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
test "image-only paragraphs are marked during conversion" {
  let rendered = render_markdown(
    (
      #|![plain](image.png)
      #|
      #|![mixed](image.png) caption
      #|
      #|[![linked](image.png)](https://docs.example.test/)
      #|
      #|[![linked mixed](image.png)](https://docs.example.test/) caption
      #|
    ),
  )
  assert_eq(
    rendered.html,
    (
      #|<p data-markdown-image-only="true"><img src="image.png" alt="plain" ></p>
      #|<p><img src="image.png" alt="mixed" > caption</p>
      #|<p data-markdown-image-only="true"><a href="https://docs.example.test/"><img src="image.png" alt="linked" ></a></p>
      #|<p><a href="https://docs.example.test/"><img src="image.png" alt="linked mixed" ></a> caption</p>
      #|
    ),
  )
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
  let observed_code = Ref("")
  let observed_fence = Ref("")
  let observed_info = Ref("")
  let observed_remainder = Ref("")
  let observed_source_line = Ref(0)
  let observed_active = Ref("")
  let rendered = render_markdown(
    (
      #|```mbt extra
      #|let answer = 42
      #|```
    ),
    language_id="moonbit",
    code_block_renderer=fn(block, active_language_id) {
      observed_code.val = block.code
      observed_fence.val = block.language_id.unwrap_or("")
      observed_info.val = block.full_info_string.unwrap_or("")
      observed_remainder.val = block.info_remainder.unwrap_or("")
      observed_source_line.val = block.code_lines[0].source_line_number
      observed_active.val = active_language_id.unwrap_or("")
      "<pre data-rendered=\"yes\">override</pre>"
    },
  )
  assert_eq(observed_code.val, "let answer = 42\n")
  assert_eq(observed_fence.val, "mbt")
  assert_eq(observed_info.val, "mbt extra")
  assert_eq(observed_remainder.val, "extra")
  assert_eq(observed_source_line.val, 2)
  assert_eq(observed_active.val, "moonbit")
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
