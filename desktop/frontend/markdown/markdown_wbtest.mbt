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
test "markdown links do not navigate the app frame" {
  let node = link_node("https://example.com", [@html.text("example")])
  let expected =
    #|<a href="https://example.com" target="_blank" rel="noopener noreferrer">example</a>
  inspect(
    @rabbita.render_to_string(@rabbita.static_cell(node)),
    content=expected,
  )
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
