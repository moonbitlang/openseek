// Structural tests for the markdown renderer. Rabbita's Html is opaque, so
// the tests assert on the number of block-level nodes a document produces and
// on the pure text helpers.

///|
test "markdown renders block structure" {
  inspect(markdown_nodes("").length(), content="0")
  inspect(markdown_nodes("just a paragraph").length(), content="1")
  inspect(markdown_nodes("# Title\n\nbody text").length(), content="2")
  inspect(markdown_nodes("- one\n- two\n- three").length(), content="1")
  inspect(
    markdown_nodes("para\n\n```moonbit\nfn main {}\n```\n\n---").length(),
    content="3",
  )
  inspect(markdown_nodes("> quoted\n> text").length(), content="1")
  inspect(
    markdown_nodes("| a | b |\n| - | - |\n| 1 | 2 |").length(),
    content="1",
  )
}

///|
#warnings("-alert_unstable")
test "exact UML fences render the shared Viewer SVG" {
  for language in ["uml", "plantuml"] {
    let rendered = @html.div(
      markdown_nodes(
        "```\{language}\n@startuml\nparticipant Alice\nAlice -> Bob : hello\n@enduml\n```",
      ),
    )
    let markup = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(rendered)
    })
    assert_true(
      markup.contains(
        "class=\"chat-markdown-diagram moonbit-viewer-markdown-diagram\"",
      ),
    )
    assert_true(markup.contains("data-diagram-language=\"uml\""))
    assert_true(markup.contains("<svg"))
    assert_false(markup.contains("<code class=\"language-\{language}\">"))
  }
}

///|
#warnings("-alert_unstable")
test "invalid UML and Mermaid keep their code-block fallback" {
  let invalid = @html.div(markdown_nodes("```uml\n@startuml\n@enduml\n```"))
  let invalid_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(invalid)
  })
  assert_true(invalid_markup.contains("<code class=\"language-uml\">"))
  assert_false(invalid_markup.contains("chat-markdown-diagram"))

  let mermaid = @html.div(markdown_nodes("```mermaid\nA --> B\n```"))
  let mermaid_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(mermaid)
  })
  assert_true(mermaid_markup.contains("<code class=\"language-mermaid\">"))
  assert_false(mermaid_markup.contains("chat-markdown-diagram"))
}

///|
test "markdown survives streaming-truncated input" {
  // An unterminated fence parses as *something* renderable rather than
  // aborting — the streaming view re-parses partial text on every delta.
  inspect(markdown_nodes("intro\n\n```moonbit\nfn ma").length(), content="2")
  inspect(markdown_nodes("broken **emphasi").length(), content="1")
  inspect(markdown_nodes("dangling [link](htt").length(), content="1")
}

///|
test "raw html stays text instead of markup" {
  // One pre.raw-html block; the structure proves the branch is taken and the
  // payload is routed through a text node, never through innerHTML.
  inspect(markdown_nodes("<script>alert(1)</script>").length(), content="1")
}

///|
#warnings("-alert_unstable")
test "local raster images wait for the transcript host loader" {
  let rendered = @html.div(
    markdown_nodes(
      "![relative](../../Downloads/meetup.png) ![escaped](My%20Plot.png) ![absolute](</Users/me/My Image.JPG>) ![file](file:///Users/me/My%20Image.webp) ![web](https://example.com/image.png) ![svg](./diagram.svg)",
    ),
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains("data-transcript-image=\"../../Downloads/meetup.png\""),
  )
  assert_true(markup.contains("data-transcript-image=\"My Plot.png\""))
  assert_true(
    markup.contains("data-transcript-image=\"/Users/me/My Image.JPG\""),
  )
  assert_true(
    markup.contains("data-transcript-image=\"/Users/me/My Image.webp\""),
  )
  assert_true(markup.contains("src=\"https://example.com/image.png\""))
  // SVG and web URLs stay under the renderer's existing destination policy;
  // only byte-signature-checked raster files enter the host read path.
  assert_true(markup.contains("src=\"./diagram.svg\""))
}

///|
#warnings("-alert_unstable")
test "markdown links do not navigate the app frame" {
  let node = link_node("https://example.com", [@html.text("example")])
  let expected =
    #|<a href="https://example.com" target="_blank" rel="noopener noreferrer">example</a>
  inspect(
    @rabbita.render_to_string(() => @rabbita.Val::constant(node)),
    content=expected,
  )
}

///|
#warnings("-alert_unstable")
test "bare web URLs in prose become external anchors" {
  let node = @html.p(
    linkified_text_nodes(
      "See https://example.com/docs, then http://localhost:8080/a_(b).",
    ),
  )
  let expected =
    #|<p>See <a href="https://example.com/docs" target="_blank" rel="noopener noreferrer">https://example.com/docs</a>, then <a href="http://localhost:8080/a_(b)" target="_blank" rel="noopener noreferrer">http://localhost:8080/a_(b)</a>.</p>
  inspect(
    @rabbita.render_to_string(() => @rabbita.Val::constant(node)),
    content=expected,
  )
}

///|
#warnings("-alert_unstable")
test "URL detection stays out of code and existing links" {
  let rendered = @html.div(
    markdown_nodes(
      "`https://code.example` [https://label.example](https://target.example) https://plain.example",
    ),
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains("<code class=\"inline-code\">https://code.example</code>"),
  )
  assert_false(markup.contains("href=\"https://code.example\""))
  assert_true(markup.contains("href=\"https://target.example\""))
  assert_true(markup.contains("href=\"https://plain.example\""))
  // One explicit link and one bare URL; the URL-shaped label must not produce
  // an anchor nested inside the explicit one.
  inspect(markup.split("<a ").collect().length(), content="3")
}

///|
#warnings("-alert_unstable")
test "positioned file references keep explicit destinations authoritative" {
  let rendered = @html.div(
    markdown_nodes(
      "pango/aliases.mbt:5:10 /Users/me/project/update.mbt:2738 `pango/code.mbt:2:3`\n\n[`pango/aliases.mbt:20`](pango/aliases.mbt#L5)",
      open_file=_ => @cmd.none,
    ),
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  // Bare prose carries its own location, while an explicit link follows the
  // destination even when its display label claims a different line.
  inspect(
    markup.split("title=\"Open pango/aliases.mbt:5:10\"").collect().length(),
    content="2",
  )
  assert_true(markup.contains("title=\"Open pango/aliases.mbt#L5\""))
  assert_false(markup.contains("title=\"Open pango/aliases.mbt:20\""))
  assert_true(
    markup.contains("title=\"Open /Users/me/project/update.mbt:2738\""),
  )
  assert_true(
    markup.contains("<code class=\"inline-code\">pango/code.mbt:2:3</code>"),
  )
  assert_false(markup.contains("title=\"Open pango/code.mbt:2:3\""))
}

///|
#warnings("-alert_unstable")
test "explicit directory destinations use the local path action" {
  let rendered = @html.div(
    markdown_nodes(
      "[absolute](</Users/me/My Project/src>) [relative](./src/) [bare](src) [web](https://example.com/src)",
      open_file=_ => @cmd.none,
    ),
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("title=\"Open /Users/me/My Project/src\""))
  assert_true(markup.contains("title=\"Open ./src/\""))
  // A bare word remains an ordinary link, and a web destination remains an
  // external anchor rather than being confused for a slash-bearing path.
  assert_false(markup.contains("title=\"Open src\""))
  assert_true(markup.contains("href=\"src\""))
  assert_true(markup.contains("href=\"https://example.com/src\""))
}

///|
#warnings("-alert_unstable")
test "local file URI destinations open decoded filesystem paths" {
  let rendered = @html.div(
    markdown_nodes(
      "[action_row.mbt:28](file:///Users/me/My%20Project/adw/action_row.mbt#L28) [local](file://localhost/Users/me/src/local.mbt#L2) [remote](file://server/share/remote.mbt#L3) [query](file:///Users/me/src/query.mbt?download=1#L4)",
      open_file=_ => @cmd.none,
    ),
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains(
      "title=\"Open /Users/me/My Project/adw/action_row.mbt#L28\"",
    ),
  )
  assert_true(markup.contains("title=\"Open /Users/me/src/local.mbt#L2\""))
  // A remote authority or URI query must not escape into a browser anchor or
  // be reinterpreted as a local host path.
  assert_false(markup.contains("title=\"Open //server/share/remote.mbt#L3\""))
  assert_false(markup.contains("title=\"Open /Users/me/src/query.mbt#L4\""))
  assert_false(markup.contains("href=\"file:"))
}

///|
test "a scheme without an authority remains text" {
  inspect(linkified_text_nodes("streaming https://").length(), content="1")
}

///|
#warnings("-alert_unstable")
test "interactive prose keeps unsafe and longer path-shaped tokens inert" {
  let rendered = @html.div(
    markdown_nodes(
      "https:///docs vscode://host/src/a.mbt:12 build%20/src/a.mbt:12 src/a.mbt:12.bak src/a.mbt:12. src/a.mbt:13,",
      open_file=_ => @cmd.none,
    ),
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  // Enabling file links must not widen the URL-only renderer's HTTP(S) and
  // authority policy, or turn a prefix of a longer filename into a button.
  assert_false(markup.contains("href=\"https:///docs\""))
  assert_false(markup.contains("href=\"vscode://host/src/a.mbt:12\""))
  assert_false(markup.contains("title=\"Open vscode://host/src/a.mbt:12\""))
  assert_false(markup.contains("title=\"Open 20/src/a.mbt:12\""))
  assert_false(markup.contains("title=\"Open src/a.mbt:12.bak\""))
  inspect(
    markup.split("title=\"Open src/a.mbt:12\"").collect().length(),
    content="2",
  )
  assert_true(markup.contains("title=\"Open src/a.mbt:13\""))
}

///|
fn first_paragraph(block : @cmark.Block) -> @cmark.BlockParagraph? {
  match block {
    Paragraph(node) => Some(node.v)
    Blocks(node) => {
      for child in node.v.iter() {
        if first_paragraph(child) is Some(para) {
          return Some(para)
        }
      }
      None
    }
    _ => None
  }
}

///|
test "plain text flattens inline trees" {
  let doc = @cmark.Doc::from_string("some **bold** and `code`", strict=false)
  guard first_paragraph(doc.block) is Some(para) else {
    fail("expected a paragraph")
  }
  inspect(plain_text(para.inline), content="some bold and code")
}

///|
test "file-path shapes are recognized" {
  // Slash-bearing relative and absolute paths.
  assert_true(is_file_path("frontend/view.mbt"))
  assert_true(is_file_path("/Users/me/Documents/OpenSeek/s1/main.mbt"))
  assert_true(is_file_path("./src/lib.rs"))
  // Bare filenames with a known extension.
  assert_true(is_file_path("README.md"))
  assert_true(is_file_path("moon.pkg"))
  assert_true(is_file_path("config.json"))
  // Position suffixes do not become part of the extension. The raw link is
  // still preserved for the host's exact-file-first existence check.
  assert_true(
    is_file_path(
      "/Users/me/Documents/OpenSeek/desktop/frontend/update.mbt:2738",
    ),
  )
  assert_true(is_file_path("frontend/update.mbt:12345"))
  assert_true(is_file_path("frontend/update.mbt:2738:17"))
  assert_true(is_file_path("frontend/update.mbt#L2738"))
  // Stray surrounding whitespace in a destination is tolerated.
  assert_true(is_file_path(" view.mbt "))
}

///|
test "bare filenames and slash paths alike are clickable" {
  // Exactly the tokens from a real transcript: bare `.mbt` names and
  // slash-bearing paths both qualify; a directory and a bare word do not.
  assert_true(is_file_path("array_nonjs.mbt"))
  assert_true(is_file_path("core/builtin/array_nonjs_test.mbt"))
  assert_true(is_file_path("core/builtin/arraycore_nonjs.mbt"))
  assert_true(is_file_path("array.mbt"))
  assert_true(is_file_path("view.mbt"))
  assert_true(is_file_path("array_test.mbt"))
  assert_false(is_file_path("core"))
  assert_false(is_file_path("core/array/"))
  assert_false(is_file_path("_nonjs"))
}

///|
test "slash paths accept any extension; bare names need a known one" {
  // A `/` makes it a path: any plausible extension lights up, even ones the
  // bare-name allowlist omits.
  assert_true(is_file_path("~/Documents/openseek-deck/dist/openseek.pptx"))
  assert_true(is_file_path("pages/*.page.toml"))
  assert_true(is_file_path("build/out/report.xyz"))
  // A bare name still needs a recognized type.
  assert_true(is_file_path("slides.pptx"))
  assert_true(is_file_path("diagram.png"))
  assert_false(is_file_path("report.xyz"))
  // A trailing slash is a directory.
  assert_false(is_file_path("~/Documents/openseek-deck/"))
}

///|
test "non-paths are left alone" {
  // Identifiers and prose, not files.
  assert_false(is_file_path("OpenFile"))
  assert_false(is_file_path("self.value"))
  assert_false(is_file_path("a.b"))
  assert_false(is_file_path("moon check --target js"))
  assert_false(is_file_path(""))
  // URLs and fragments stay as ordinary links/text.
  assert_false(is_file_path("https://example.com/readme.md"))
  assert_false(is_file_path("mailto:me@example.com"))
  assert_false(is_file_path("#section"))
  // Dotfiles have an empty stem, so they are not treated as an extension.
  assert_false(is_file_path(".gitignore"))
}
