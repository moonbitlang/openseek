///|
priv struct Footnotes {
  prefix : String
  notes : Array[RenderedFootnote]
}

///|
priv struct RenderedFootnote {
  key : String
  number : Int32
  id : String
  block : @cmark.Block
  mut references : Int32
}

///|
// Several answers share one DOM. Each rendering owns its fragment IDs so a
// repeated Markdown label cannot navigate into another message's footnotes.
let next_footnote_scope : Ref[Int32] = Ref(0)

///|
fn Footnotes::new() -> Footnotes {
  next_footnote_scope.val += 1
  { prefix: "markdown-note-\{next_footnote_scope.val}", notes: [], }
}

///|
fn MarkdownRender::source_note_id(
  self : MarkdownRender,
  number : String,
) -> String {
  "\{self.footnotes.prefix}-source-\{number}"
}

///|
fn MarkdownRender::footnote_reference(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> @html.Html? {
  guard link.reference_definition(self.defs) is Some(FootnoteDef(definition)) else {
    return None
  }
  let key = definition.v.label.key
  let full = link.reference is Ref(Full, _, _)
  if citation_number(key) is Some(number) {
    for citation in self.citations {
      if citation.number == number {
        let children = if full {
          self.inline_nodes(link.text, linkify_urls=false)
        } else {
          [@html.text("[\{number}]")]
        }
        let anchor = @html.a(
          href="#" + self.source_note_id(number),
          attrs=@html.Attrs::build().role("doc-noteref"),
          escape=true,
          children,
        )
        return Some(if full { anchor } else { @html.sup([anchor]) })
      }
    }
  }
  let note = for note in self.footnotes.notes {
    if note.key == key {
      break note
    }
  } nobreak {
    let number = self.footnotes.notes.length() + 1
    let note = RenderedFootnote::{
      key,
      number,
      id: "\{self.footnotes.prefix}-\{number}",
      block: definition.v.block,
      references: 0,
    }
    self.footnotes.notes.push(note)
    note
  }
  note.references += 1
  let children = if full {
    self.inline_nodes(link.text, linkify_urls=false)
  } else {
    [@html.text("[\{note.number}]")]
  }
  let anchor = @html.a(
    id="\{note.id}-ref-\{note.references}",
    href="#" + note.id,
    attrs=@html.Attrs::build().role("doc-noteref"),
    escape=true,
    children,
  )
  Some(if full { anchor } else { @html.sup([anchor]) })
}

///|
fn MarkdownRender::footnotes_node(self : MarkdownRender) -> @html.Html {
  let rendered : Array[(RenderedFootnote, Array[@html.Html])] = []
  let render = { ..self, in_sources: true, }
  // A note may reference another note, including itself. Register references
  // before rendering bodies, visit each note once, then build backlinks after
  // the complete reference graph has been discovered.
  for index = 0; index < self.footnotes.notes.length(); index = index + 1 {
    let note = self.footnotes.notes[index]
    rendered.push((note, render.block_nodes(note.block)))
  }
  let items : Array[@html.Html] = []
  for (note, children) in rendered {
    let backlinks : Array[@html.Html] = []
    for reference in 1..<=note.references {
      backlinks.push(
        @html.a(
          href="#\{note.id}-ref-\{reference}",
          attrs=@html.Attrs::build().role("doc-backlink"),
          escape=true,
          [@html.text(if reference == 1 { "↩" } else { "↩\{reference}" })],
        ),
      )
    }
    children.push(@html.span(backlinks))
    items.push(
      @html.li(
        id=note.id,
        attrs=@html.Attrs::build()
          .role("doc-footnote")
          .data_set("footnote", note.key),
        children,
      ),
    )
  }
  @html.section(
    class="footnote",
    attrs=@html.Attrs::build().role("doc-endnotes"),
    [@html.ol(items)],
  )
}
