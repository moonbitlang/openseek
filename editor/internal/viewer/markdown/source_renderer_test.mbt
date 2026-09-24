///|
test "source block rendering preserves cmark content and safe rendering" {
  let source =
    #|# Heading
    #|
    #|Text with *emphasis*, `code`, [a link](/target), and [unsafe](javascript:alert(1)).
    #|
    #|> quoted
    #|>
    #|> ## Nested heading
    #|
    #|3. first
    #|   - nested
    #|4. second
    #|
    #|- [x] done
    #|- [ ] pending
    #|
    #|- loose
    #|
    #|  continuation
    #|
    #|| left | right |
    #|| :--- | ---: |
    #|| value | *other* |
    #|
    #|---
    #|
    #|```plain
    #|<tag> & "quoted"
    #|```
    #|
    #|<script>alert(1)</script>
    #|
    #|Footnote[^one].
    #|
    #|[^one]: body
  let ordinary = @markdown.render_markdown(source)
  let mapped = @markdown.render_markdown(source, source_mapping=true)
  let mut without_ids = mapped.html
  for anchor in mapped.projection.block_anchors {
    without_ids = without_ids.replace_all(
      old=" data-markdown-node-id=\"\{anchor.node_id}\"",
      new="",
    )
  }
  assert_eq(without_ids, ordinary.html)
  assert_false(mapped.html.contains("<script>"))
  assert_false(mapped.html.contains("javascript:"))
}

///|
test "identical rendered paragraphs retain distinct source identities" {
  let source = "same\n\n<div>omitted</div>\n\nsame"
  let rendered = @markdown.render_markdown(source, source_mapping=true)
  let roots = rendered.projection.block_anchors.filter(anchor => {
    anchor.is_root_element
  })
  assert_eq(roots.length(), 2)
  assert_true(roots[0].node_id != roots[1].node_id)
  for root in roots {
    assert_true(
      rendered.html.contains(
        "<p data-markdown-node-id=\"\{root.node_id}\">same</p>",
      ),
    )
    assert_eq(
      rendered.projection.source_range_for_node(root.node_id),
      Some(root.source_range),
    )
    assert_eq(
      source[root.source_range.start:root.source_range.end_exclusive],
      "same",
    )
  }
  assert_eq(roots[0].source_range.start, 0)
  assert_eq(roots[1].source_range.start, source.length() - 4)
}

///|
test "a code override keeps one source owner for empty or multiple HTML roots" {
  for html in ["", "<pre>first</pre><aside>second</aside>"] {
    let rendered = @markdown.render_markdown(
      "```custom\ncode\n```",
      source_mapping=true,
      code_block_renderer=(_, _) => html,
    )
    guard rendered.projection.block_anchors is [anchor] else {
      fail("expected one source block")
    }
    assert_true(anchor.is_root_element)
    assert_eq(
      rendered.html,
      "<div class=\"moonbit-viewer-markdown-source-block\" data-markdown-node-id=\"\{anchor.node_id}\">\{html}</div>",
    )
    assert_eq(
      rendered.projection.source_range_for_node(anchor.node_id),
      Some(rendered.projection.code_blocks[0].block_source_range),
    )
  }
}

///|
test "math text has a source owner and participates in section folding" {
  let math = "```math\nx < y\n```"
  let rendered = @markdown.render_markdown(
    "# Math\n\n" + math,
    source_mapping=true,
  )
  guard rendered.projection.block_anchors is [_, anchor] else {
    fail("expected a heading and a math block")
  }
  assert_true(anchor.is_root_element)
  assert_true(
    rendered.html.contains(
      "<div class=\"moonbit-viewer-markdown-source-block\" data-markdown-node-id=\"\{anchor.node_id}\">\{@markdown.render_markdown(math).html}</div>",
    ),
  )
  assert_eq(
    @markdown.markdown_sections(rendered.projection)[0].body_node_ids(
      rendered.projection,
    ),
    [anchor.node_id],
  )
  assert_eq(anchor.source_range.start, "# Math\n\n".length())
  assert_eq(anchor.source_range.length(), math.length())
}

///|
test "an owned code renderer writes the source ID on its existing root" {
  let rendered = @markdown.render_markdown(
    "```custom\ncode\n```",
    source_mapping=true,
    code_block_renderer_owns_source_root=true,
    code_block_renderer=(block, _) => {
      match block.node_id {
        Some(id) => "<pre data-markdown-node-id=\"\{id}\">owned</pre>"
        None => "<pre>missing source identity</pre>"
      }
    },
  )
  guard rendered.projection.block_anchors is [anchor] else {
    fail("expected one source block")
  }
  assert_eq(
    rendered.html,
    "<pre data-markdown-node-id=\"\{anchor.node_id}\">owned</pre>",
  )
  assert_eq(rendered.projection.code_blocks[0].node_id, Some(anchor.node_id))
}

///|
test "built-in diagrams retain their original source-bearing root" {
  for
    (language, code) in [
      ("d2", "a -> b"),
      ("uml", "@startuml\nparticipant Alice\nAlice -> Bob : hello\n@enduml"),
    ] {
    let source = "```\{language}\n\{code}\n```"
    let ordinary = @markdown.render_markdown(source)
    let mapped = @markdown.render_markdown(source, source_mapping=true)
    guard mapped.projection.block_anchors is [anchor] else {
      fail("expected one diagram block")
    }
    assert_true(
      mapped.html.has_prefix("<div class=\"moonbit-viewer-markdown-diagram\""),
    )
    assert_true(mapped.html.contains("<svg"))
    assert_eq(
      mapped.html.replace_all(
        old=" data-markdown-node-id=\"\{anchor.node_id}\"",
        new="",
      ),
      ordinary.html,
    )
  }
}
