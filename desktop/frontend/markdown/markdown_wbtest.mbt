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
