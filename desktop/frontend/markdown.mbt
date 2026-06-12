// Markdown rendering for transcript content. The engine's assistant text is
// CommonMark (with the GFM-ish cmark extensions: tables, strikethrough, task
// lists); this module parses it with moonbit-community/cmark and maps the
// document tree directly onto Rabbita nodes. Untrusted model output therefore
// never reaches `innerHTML`: raw HTML blocks and spans are rendered as visible
// text instead of being injected into the DOM.

///|
/// Render a markdown string to a list of block-level Rabbita nodes.
///
/// The parse is guarded: cmark can panic on some inputs (observed: "Index
/// out of bounds" in `Parser::add_open_blocks` on streaming-truncated text).
/// A panic escaping `view` would kill Rabbita's render loop — and since
/// every delta re-renders the same accumulated text, the transcript would
/// freeze on the last good frame forever. MoonBit panics on the js target
/// surface as JS exceptions, so `@js.Error_::wrap` is the one place a cmark
/// crash can be contained; the fallback shows the raw text instead.
fn markdown_nodes(source : String) -> Array[@html.Html] {
  @js.Error_::wrap(() => @js.Value::cast_from(parsed_markdown_nodes(source))) catch {
    _ => [@html.pre(class="markdown-fallback", source)]
  }
}

///|
fn parsed_markdown_nodes(source : String) -> Array[@html.Html] {
  let doc = @cmark.Doc::from_string(source, strict=false)
  let render = MarkdownRender::{ defs: doc.defs }
  render.block_nodes(doc.block)
}

///|
priv struct MarkdownRender {
  // Link-reference and footnote definitions collected by the parser, used to
  // resolve `[text][label]` style references to their destinations.
  defs : Map[String, @cmark.LabelDef]
}

///|
fn MarkdownRender::block_nodes(
  self : MarkdownRender,
  block : @cmark.Block,
) -> Array[@html.Html] {
  let out : Array[@html.Html] = []
  self.push_block(out, block)
  out
}

///|
fn MarkdownRender::push_block(
  self : MarkdownRender,
  out : Array[@html.Html],
  block : @cmark.Block,
) -> Unit {
  match block {
    BlankLine(_) | LinkRefDefinition(_) => ()
    Blocks(node) =>
      for child in node.v.iter() {
        self.push_block(out, child)
      }
    Paragraph(node) => out.push(@html.p(self.inline_nodes(node.v.inline)))
    Heading(node) => out.push(self.heading(node.v))
    BlockQuote(node) =>
      out.push(@html.blockquote(self.block_nodes(node.v.block)))
    CodeBlock(node) | ExtMathBlock(node) => out.push(code_block(node.v))
    // Raw HTML is shown as text, not injected; see the module comment.
    HtmlBlock(node) =>
      out.push(@html.pre(class="raw-html", lines_text(node.v.0)))
    List(node) => out.push(self.list(node.v))
    ThematicBreak(_) => out.push(@html.hr(@html.nothing))
    ExtTable(node) => out.push(self.table(node.v))
    ExtFootnoteDefinition(node) => {
      let children : Array[@html.Html] = [
        @html.span(class="footnote-label", node.v.label.key),
      ]
      for child in self.block_nodes(node.v.block) {
        children.push(child)
      }
      out.push(@html.div(class="footnote", children))
    }
  }
}

///|
fn MarkdownRender::heading(
  self : MarkdownRender,
  heading : @cmark.BlockHeading,
) -> @html.Html {
  let children = self.inline_nodes(heading.inline)
  match heading.level {
    1 => @html.h1(children)
    2 => @html.h2(children)
    3 => @html.h3(children)
    4 => @html.h4(children)
    5 => @html.h5(children)
    _ => @html.h6(children)
  }
}

///|
fn lines_text(lines : @cmark.Seq[@cmark.Node[String]]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for line in lines.iter() {
    if !first {
      buf.write_char('\n')
    }
    buf.write_string(line.v)
    first = false
  }
  buf.to_string()
}

///|
fn code_block(block : @cmark.CodeBlock) -> @html.Html {
  let language = match block.info_string {
    Some(info) =>
      match @cmark.CodeBlock::language_of_info_string(info.v) {
        Some((language, _)) => language
        None => ""
      }
    None => ""
  }
  let code_class = if language.is_empty() { "" } else { "language-" + language }
  @html.pre([@html.code(class=code_class, lines_text(block.code))])
}

///|
fn MarkdownRender::list(
  self : MarkdownRender,
  list : @cmark.BlockList,
) -> @html.Html {
  let items : Array[@html.Html] = []
  for item_node in list.items.iter() {
    let item = item_node.v
    let children : Array[@html.Html] = []
    if item.ext_task_marker is Some(marker) {
      let symbol = match @cmark.ListTaskStatus::from_marker(marker.v) {
        Checked => "☑"
        Cancelled => "☒"
        Unchecked | Other(_) => "☐"
      }
      children.push(@html.span(class="task-marker", symbol + " "))
    }
    for child in self.block_nodes(item.block) {
      children.push(child)
    }
    items.push(@html.li(children))
  }
  let class = if list.tight { "tight" } else { "" }
  match list.ty {
    Ordered(start, _) => @html.ol(class~, start~, items)
    Unordered(_) => @html.ul(class~, items)
  }
}

///|
fn MarkdownRender::table(
  self : MarkdownRender,
  table : @cmark.Table,
) -> @html.Html {
  let head : Array[@html.Html] = []
  let body : Array[@html.Html] = []
  for row in table.rows.iter() {
    let (row_node, _) = row
    match row_node.v {
      Header(cells) => {
        let cell_nodes : Array[@html.Html] = []
        for cell in cells.iter() {
          cell_nodes.push(@html.th(self.inline_nodes(cell.0)))
        }
        head.push(@html.tr(cell_nodes))
      }
      Data(cells) => {
        let cell_nodes : Array[@html.Html] = []
        for cell in cells.iter() {
          cell_nodes.push(@html.td(self.inline_nodes(cell.0)))
        }
        body.push(@html.tr(cell_nodes))
      }
      Sep(_) => ()
    }
  }
  @html.table([@html.thead(head), @html.tbody(body)])
}

///|
fn MarkdownRender::inline_nodes(
  self : MarkdownRender,
  inline : @cmark.Inline,
) -> Array[@html.Html] {
  let out : Array[@html.Html] = []
  self.push_inline(out, inline)
  out
}

///|
fn MarkdownRender::push_inline(
  self : MarkdownRender,
  out : Array[@html.Html],
  inline : @cmark.Inline,
) -> Unit {
  match inline {
    Text(node) => out.push(@html.text(node.v))
    Inlines(node) =>
      for child in node.v.iter() {
        self.push_inline(out, child)
      }
    Break(node) =>
      match node.v.ty {
        Hard => out.push(@html.br())
        Soft => out.push(@html.text(" "))
      }
    CodeSpan(node) => out.push(@html.code(class="inline-code", node.v.code()))
    Emphasis(node) => out.push(@html.em(self.inline_nodes(node.v.inline)))
    StrongEmphasis(node) =>
      out.push(@html.strong(self.inline_nodes(node.v.inline)))
    ExtStrikethrough(node) => out.push(@html.del(self.inline_nodes(node.v.0)))
    ExtMathSpan(node) => out.push(@html.code(class="inline-code", node.v.tex()))
    Autolink(node) => {
      let url = node.v.link.v
      let href = if node.v.is_email { "mailto:" + url } else { url }
      out.push(link_node(href, [@html.text(url)]))
    }
    Link(node) => {
      let children = self.inline_nodes(node.v.text)
      match self.link_destination(node.v) {
        Some(url) => out.push(link_node(url, children))
        None => out.push(@html.span(children))
      }
    }
    // Images keep their alt text visible; the picture itself is only loaded
    // from destinations that pass the same safety filter as links.
    Image(node) => {
      let alt = plain_text(node.v.text)
      match self.link_destination(node.v) {
        Some(url) => out.push(@html.img(src=url, alt~, @html.nothing))
        None => out.push(@html.text(alt))
      }
    }
    // Raw HTML is shown as text, not injected; see the module comment.
    RawHtml(node) => out.push(@html.text(tights_text(node.v.0)))
  }
}

///|
/// The resolved, safe destination of a link or image. `None` for unresolved
/// references and for destinations cmark flags as unsafe (`javascript:` and
/// friends); the caller then renders the text without linking it.
fn MarkdownRender::link_destination(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> String? {
  let definition = match link.reference {
    Inline(node) => Some(node.v)
    Ref(_, _, _) =>
      match link.reference_definition(self.defs) {
        Some(LinkDef(node)) => Some(node.v)
        _ => None
      }
  }
  match definition {
    Some(definition) =>
      match definition.dest {
        Some(dest) if !@cmark.InlineLink::is_unsafe(dest.v) => Some(dest.v)
        _ => None
      }
    None => None
  }
}

///|
fn link_node(href : String, children : Array[@html.Html]) -> @html.Html {
  @html.a(href~, rel="noopener noreferrer", children)
}

///|
fn plain_text(inline : @cmark.Inline) -> String {
  let buf = StringBuilder::new()
  for line in inline.to_plain_text(break_on_soft=false) {
    for segment in line {
      buf.write_string(segment)
    }
  }
  buf.to_string()
}

///|
fn tights_text(tights : @cmark.Seq[@cmark.Tight]) -> String {
  let buf = StringBuilder::new()
  for tight in tights.iter() {
    buf.write_string(tight.to_string())
  }
  buf.to_string()
}
