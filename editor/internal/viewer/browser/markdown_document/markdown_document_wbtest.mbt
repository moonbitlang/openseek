///|
priv struct StatefulMarkdownFenceTokenizer {}

///|
let markdown_normal_state : @syntax.TokenizerState = TokenizerState()

///|
let markdown_comment_state : @syntax.TokenizerState = markdown_normal_state.push_mode(
  b'c',
)

///|
impl @syntax.LineTokenizer for StatefulMarkdownFenceTokenizer with fn initial_state(
  _self,
) {
  markdown_normal_state
}

///|
impl @syntax.LineTokenizer for StatefulMarkdownFenceTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  if state == markdown_comment_state {
    let end = match line_text.find("*/") {
      Some(index) => index + 2
      None => line_text.length()
    }
    tokens.push({ start: 0, end, tag: Comment, })
    return (
      tokens,
      if end == line_text.length() {
        markdown_comment_state
      } else {
        markdown_normal_state
      },
    )
  }
  match line_text.find("/*") {
    Some(start) => {
      tokens.push({ start, end: line_text.length(), tag: Comment, })
      (tokens, markdown_comment_state)
    }
    None => (tokens, markdown_normal_state)
  }
}

///|
fn projected_document_code_block(
  source : String,
) -> @markdown_core.MarkdownCodeBlock {
  let rendered = @markdown_core.render_markdown(source)
  guard rendered.projection.code_blocks is [block, ..] else {
    abort("fixture did not produce a projected code block")
  }
  block
}

///|
test "document code wrapper keeps stable block identity and semantic opt-in" {
  let first = projected_document_code_block(
    (
      #|```mbt check trailing
      #|fn first() -> Int { 1 }
      #|```
    ),
  )
  let ordinary = render_markdown_document_code_block(
    first,
    Some("moonbit"),
    OrdinaryMarkdown,
  )
  let semantic = render_markdown_document_code_block(
    first,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(ordinary.contains("data-markdown-code-block=\"0\""))
  assert_false(ordinary.contains("data-markdown-semantic"))
  assert_true(semantic.contains("data-markdown-code-block=\"0\""))
  assert_true(semantic.contains("data-markdown-semantic=\"moonbit-check\""))
  assert_true(semantic.contains("data-markdown-code-line=\"0\""))
  assert_true(
    semantic.contains(
      "data-markdown-source-start=\"22\" data-markdown-source-end=\"45\"",
    ),
  )
  assert_false(semantic.contains("data-markdown-code-line=\"1\""))

  let second = @markdown_core.render_markdown(
      (
        #|```mbt check
        #|fn same() {}
        #|```
        #|
        #|```mbt check
        #|fn same() {}
        #|```
      ),
    ).projection.code_blocks[1]
  let second_html = render_markdown_document_code_block(
    second,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(second_html.contains("data-markdown-code-block=\"1\""))
}

///|
test "semantic tokenized HTML has one source-bearing element per projected line" {
  let block = projected_document_code_block(
    (
      #|```moonbit check
      #|let first = 1
      #|
      #|let third = first
      #|```
    ),
  )
  let html = render_markdown_document_code_block(
    block,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_eq(block.code_lines.length(), 3)
  assert_true(html.contains("data-markdown-code-line=\"0\""))
  assert_true(html.contains("data-markdown-code-line=\"1\""))
  assert_true(html.contains("data-markdown-code-line=\"2\""))
  assert_false(html.contains("data-markdown-code-line=\"3\""))
  assert_true(
    html.contains(
      "data-markdown-code-line=\"1\" data-markdown-source-line=\"3\"",
    ),
  )
  // The empty source line owns hit geometry through its line element; no
  // zero-width or other synthetic text is inserted into the semantic mapping.
  let blank = block.code_lines[1]
  assert_eq(blank.displayed_text, "")
  assert_true(
    html.contains(
      "data-markdown-code-line=\"1\" data-markdown-source-line=\"\{blank.source_line_number}\" data-markdown-source-start=\"\{blank.source_range.start}\" data-markdown-source-end=\"\{blank.source_range.end_exclusive}\">",
    ),
  )
  assert_false(html.contains("&#8203;"))
  assert_false(html.contains("&#x200b;"))
}

///|
test "semantic line wrapping preserves escaped delimiter text and every blank line" {
  let block = projected_document_code_block(
    (
      #|```mbt check
      #|
      #|let literal = "<br/>"
      #|
      #|let after = 1
      #|
      #|```
    ),
  )
  let html = render_markdown_document_code_block(
    block,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  // cmark drops the final blank immediately before the closing fence; every
  // retained leading/middle/last projected line still receives one element.
  assert_eq(block.code_lines.length(), 4)
  assert_eq(
    block.code_lines.filter(line => line.displayed_text == "").length(),
    2,
  )
  for line_index in 0..<block.code_lines.length() {
    assert_true(html.contains("data-markdown-code-line=\"\{line_index}\""))
  }
  assert_false(html.contains("data-markdown-code-line=\"4\""))
  assert_true(html.contains("&lt;br/&gt;"))
  assert_false(html.contains(">\"<br/>\"<"))
}

///|
test "exact MoonBit phrase markers gain divider presentation only in semantic fences" {
  let block = projected_document_code_block(
    (
      #|```mbt check
      #|///|
      #|///| summary stays source
      #|  ///|
      #|test "divider" {}
      #|```
    ),
  )
  assert_true(markdown_semantic_line_is_phrase_divider(block.code_lines[0]))
  assert_false(markdown_semantic_line_is_phrase_divider(block.code_lines[1]))
  assert_false(markdown_semantic_line_is_phrase_divider(block.code_lines[2]))
  let semantic = render_markdown_document_code_block(
    block,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(
    semantic.contains(
      "data-markdown-code-line=\"0\" data-markdown-source-line=\"2\"",
    ),
  )
  assert_true(
    semantic.contains(
      "data-markdown-phrase-divider=\"true\" role=\"separator\" aria-label=\"MoonBit item separator\"",
    ),
  )
  // The source glyphs remain in the semantic row for post-render validation
  // and exact source-coordinate mapping; presentation hides them in CSS.
  assert_true(semantic.contains(">///|</span>"))
  assert_eq(semantic.split("data-markdown-phrase-divider=\"true\"").length(), 2)

  let ordinary = render_markdown_document_code_block(
    block,
    Some("moonbit"),
    OrdinaryMarkdown,
  )
  assert_false(ordinary.contains("data-markdown-phrase-divider"))
}

///|
test "semantic wrapping keeps astral UTF-16 text and fails closed on isolated surrogate cleanup" {
  let astral = projected_document_code_block(
    (
      #|```mbt check
      #|let planet = "🪐"
      #|```
    ),
  )
  let astral_html = render_markdown_document_code_block(
    astral,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(astral_html.contains("data-markdown-code-line=\"0\""))
  assert_true(astral_html.contains("🪐"))
  assert_eq(
    astral.code_lines[0].displayed_text.length(),
    "let planet = \"🪐\"".length(),
  )

  let source = StringBuilder()
  source.write_string("```mbt check\nlet invalid = \"")
  source.write_char(Int::unsafe_to_char(0xD800))
  source.write_string("\"\n```")
  let rendered = @markdown_core.render_markdown(source.to_string())
  assert_eq(rendered.projection.code_blocks.length(), 1)
  let invalid_html = render_markdown_document_code_block(
    rendered.projection.code_blocks[0],
    Some("moonbit"),
    MoonBitMarkdown,
  )
  // The cmark safety cleaner may replace the isolated unit, but semantic
  // cardinality remains exact and post-render text equality is the final gate.
  assert_true(invalid_html.contains("data-markdown-code-line=\"0\""))
  assert_false(invalid_html.contains("data-markdown-code-line=\"1\""))
}

///|
test "semantic line rendering preserves tokenization state across lines" {
  let registration = @syntax.tokenization_registry.register("moonbit", StatefulMarkdownFenceTokenizer::{
  })
  defer registration.dispose()
  let block = projected_document_code_block(
    (
      #|```mbt check
      #|let before = /* open
      #|still comment */ let after = 1
      #|```
    ),
  )
  let html = render_markdown_document_code_block(
    block,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(html.contains("data-markdown-code-line=\"0\""))
  assert_true(html.contains("data-markdown-code-line=\"1\""))
  assert_true(html.contains("class=\"mtk7\">still comment */"))
}

///|
test "empty semantic fences do not create a synthetic source line" {
  let block = projected_document_code_block(
    (
      #|```mbt check
      #|```
    ),
  )
  let html = render_markdown_document_code_block(
    block,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(html.contains("data-markdown-semantic=\"moonbit-check\""))
  assert_false(html.contains("data-markdown-code-line="))
  assert_true(html.contains("<div class=\"monaco-tokenized-source\"></div>"))
}

///|
test "semantic downgrade removes phrase-divider visual and accessibility state" {
  assert_eq(markdown_semantic_line_downgrade_attributes(), [
    "data-markdown-block-index", "data-markdown-code-line", "data-markdown-source-line",
    "data-markdown-source-start", "data-markdown-source-end", "data-markdown-phrase-divider",
    "role", "aria-label",
  ])
}

///|
test "document Mermaid theme follows the active presentation theme" {
  assert_true(markdown_document_mermaid_theme("light") == Light)
  assert_true(markdown_document_mermaid_theme("dark") == Dark)
  assert_true(markdown_document_mermaid_theme("custom-dark") == Dark)
}
