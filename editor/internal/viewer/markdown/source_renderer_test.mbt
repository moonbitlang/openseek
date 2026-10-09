///|
fn markdown_html_without_source_attributes(html : String) -> String {
  let mut result = html
  for
    name in [
      @markdown.MarkdownSourceStartAttribute,
      @markdown.MarkdownSourceEndAttribute,
      @markdown.MarkdownSourceOwnerAttribute,
    ] {
    let buffer = StringBuilder()
    let prefix = " \{name}=\""
    for index, part in result.split(prefix) {
      if index == 0 {
        buffer.write_view(part)
      } else {
        match part.split_once("\"") {
          Some((_, rest)) => buffer.write_view(rest)
          None => {
            buffer.write_string(prefix)
            buffer.write_view(part)
          }
        }
      }
    }
    result = buffer.to_string()
  }
  result
}

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
  assert_eq(markdown_html_without_source_attributes(mapped.html), ordinary.html)
  assert_false(mapped.html.contains("data-markdown-node-id"))
  assert_false(mapped.html.contains("<script>"))
  assert_false(mapped.html.contains("javascript:"))
}

///|
test "cancelled tasks close strikethrough before the following task" {
  for
    (separator, cancelled, pending) in [
      ("\n", "cancelled <em>item</em>", "pending"),
      ("\n\n", "\n<p>cancelled <em>item</em></p>\n", "\n<p>pending</p>\n"),
    ] {
    let rendered = @markdown.render_markdown(
      "- [~] cancelled *item*\{separator}- [ ] pending",
      source_mapping=true,
    )
    assert_eq(
      markdown_html_without_source_attributes(rendered.html),
      "<ul>\n<li><div class=\"task\"><input type=\"checkbox\" disabled><del>\{cancelled}</del></div></li>\n<li><div class=\"task\"><input type=\"checkbox\" disabled><div>\{pending}</div></div></li>\n</ul>\n",
    )
  }
}

///|
test "identical rendered paragraphs carry distinct original source ranges" {
  let source = "same\n\n<div>omitted</div>\n\nsame"
  let rendered = @markdown.render_markdown(source, source_mapping=true)
  let roots = rendered.projection.block_anchors.filter(anchor => {
    anchor.is_root_element
  })
  assert_eq(roots.length(), 2)
  assert_true(roots[0].source_range != roots[1].source_range)
  for root in roots {
    assert_true(
      rendered.html.contains(
        "<p\{@markdown.markdown_source_attributes(root.source_range)}>same</p>",
      ),
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
      "<div class=\"moonbit-viewer-markdown-source-block\"\{@markdown.markdown_source_attributes(anchor.source_range)}>\{html}</div>",
    )
    assert_eq(
      anchor.source_range,
      rendered.projection.code_blocks[0].block_source_range,
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
      "<div class=\"moonbit-viewer-markdown-source-block\"\{@markdown.markdown_source_attributes(anchor.source_range)}>\{@markdown.render_markdown(math).html}</div>",
    ),
  )
  assert_eq(
    @markdown.markdown_sections(rendered.projection)[0].body_source_ranges(
      rendered.projection,
    ),
    [anchor.source_range],
  )
  assert_eq(anchor.source_range.start, "# Math\n\n".length())
  assert_eq(anchor.source_range.length(), math.length())
}

///|
test "an owned code renderer writes source boundaries on its existing root" {
  let rendered = @markdown.render_markdown(
    "```custom\ncode\n```",
    source_mapping=true,
    code_block_renderer_owns_source_root=true,
    code_block_renderer=(block, _) => {
      match block.node_id {
        Some(_) =>
          "<pre\{@markdown.markdown_source_attributes(block.block_source_range)}>owned</pre>"
        None => "<pre>missing source identity</pre>"
      }
    },
  )
  guard rendered.projection.block_anchors is [anchor] else {
    fail("expected one source block")
  }
  assert_eq(
    rendered.html,
    "<pre\{@markdown.markdown_source_attributes(anchor.source_range)}>owned</pre>",
  )
  assert_true(rendered.projection.code_blocks[0].node_id is Some(_))
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
    assert_true(
      mapped.html.contains(
        @markdown.markdown_source_attributes(anchor.source_range),
      ),
    )
    assert_eq(
      markdown_html_without_source_attributes(mapped.html),
      ordinary.html,
    )
  }
}
