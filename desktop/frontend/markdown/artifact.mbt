///|
fn MarkdownRender::artifact_destination(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> String? {
  self
  .raw_link_destination(link)
  .bind(destination => {
    destination.strip_prefix("artifact://").map(id => id.to_owned())
  })
}

///|
/// Markdown embeds keep their authored position. Split prose around each
/// chart to render its SVG and legend as block content.
fn MarkdownRender::paragraph(
  self : MarkdownRender,
  out : Array[@html.Html],
  inline : @cmark.Inline,
) -> Unit {
  let prose : Array[@html.Html] = []
  fn flush() {
    if !prose.is_empty() {
      out.push(@html.p(prose.copy()))
      prose.clear()
    }
  }
  fn push(inline : @cmark.Inline) {
    match inline {
      Inlines(node) =>
        for child in node.v.iter() {
          push(child)
        }
      Image(node) if self.artifact_destination(node.v) is Some(id) => {
        flush()
        if self.artifact_view is Some(render) {
          out.push(render(id, plain_text(node.v.text)))
        }
      }
      Break(_) if prose.is_empty() => ()
      _ => prose.append(self.inline_nodes(inline))
    }
  }
  push(inline)
  flush()
}

///|
/// cmark keeps an unfinished image as text. Hide that trailing fragment while
/// a response is provisional, rather than flashing its internal URI. Closed
/// images already have their own AST node; code spans/fences bypass this path.
fn pending_embed_text(text : String) -> String {
  match text.split_once("![") {
    Some((before, _)) => before.to_owned()
    None => text
  }
}
