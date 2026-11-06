///|
test "exact diago fence wraps its source before the caller override" {
  let override_called = Ref(false)
  let rendered = render_markdown(
    (
      #|```diago extra
      #|a -> b
      #|```
    ),
    code_block_renderer=fn(_, _) {
      override_called.val = true
      "<pre data-fallback=\"caller\">fallback</pre>"
    },
  )
  assert_false(override_called.val)
  assert_true(
    rendered.html.contains(
      "class=\"moonbit-viewer-markdown-diagram\" data-diagram-language=\"diago\" data-diagram-state=\"fallback\"",
    ),
  )
  assert_true(
    rendered.html.contains("<pre><code class=\"language-diago\">a -&gt; b"),
  )
  assert_false(rendered.html.contains("data-fallback=\"caller\""))
  assert_true(rendered.has_code_block)
}

///|
test "exact d2 alias is a Diago diagram" {
  let rendered = render_markdown(
    (
      #|```d2
      #|source -> viewer
      #|```
    ),
  )
  assert_true(
    rendered.html.contains(
      "class=\"moonbit-viewer-markdown-diagram\" data-diagram-language=\"diago\"",
    ),
  )
  assert_true(rendered.html.contains("<code class=\"language-d2\">"))
  assert_true(rendered.has_code_block)
}

///|
test "exact uml and plantuml fences are UML diagrams" {
  for language in ["uml", "plantuml"] {
    let override_called = Ref(false)
    let rendered = render_markdown(
      "```\{language}\n@startuml\nAlice -> Bob : <hello>\n@enduml\n```",
      code_block_renderer=fn(_, _) {
        override_called.val = true
        "<pre data-fallback=\"caller\">fallback</pre>"
      },
    )
    assert_false(override_called.val)
    assert_true(
      rendered.html.contains(
        "class=\"moonbit-viewer-markdown-diagram\" data-diagram-language=\"uml\"",
      ),
    )
    assert_true(rendered.html.contains("Alice -&gt; Bob : &lt;hello&gt;"))
    assert_false(rendered.html.contains("data-fallback=\"caller\""))
    assert_true(rendered.has_code_block)
  }
}

///|
test "unsupported and differently cased fences remain ordinary cmark code" {
  let unknown = render_markdown(
    (
      #|```graph
      #|a -> b
      #|```
    ),
  )
  assert_true(unknown.html.contains("<pre><code class=\"language-graph\">"))
  assert_false(unknown.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(unknown.has_code_block)

  let differently_cased_uml = render_markdown(
    (
      #|```PlantUML
      #|Alice -> Bob
      #|```
    ),
  )
  assert_true(
    differently_cased_uml.html.contains(
      "<pre><code class=\"language-PlantUML\">",
    ),
  )
  assert_false(
    differently_cased_uml.html.contains("moonbit-viewer-markdown-diagram"),
  )
  assert_true(differently_cased_uml.has_code_block)

  let differently_cased = render_markdown(
    (
      #|```Diago
      #|a -> b
      #|```
    ),
  )
  assert_true(
    differently_cased.html.contains("<pre><code class=\"language-Diago\">"),
  )
  assert_false(
    differently_cased.html.contains("moonbit-viewer-markdown-diagram"),
  )
  assert_true(differently_cased.has_code_block)
}

///|
test "active diago language does not turn unlabelled or indented code into diagrams" {
  let unlabelled = render_markdown(
    (
      #|```
      #|a -> b
      #|```
    ),
    language_id="diago",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(unlabelled.html.contains("monaco-tokenized-source"))
  assert_false(unlabelled.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(unlabelled.has_code_block)

  let indented = render_markdown(
    "    a -> b",
    language_id="diago",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(indented.html.contains("monaco-tokenized-source"))
  assert_false(indented.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(indented.has_code_block)
}
