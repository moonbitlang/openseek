// Numbered Markdown footnotes are the portable answer-citation contract.
// Sources remain ordinary Markdown links, using the existing URL/file routes.

///|
priv struct Citation {
  number : String
  block : @cmark.Block
  link : @cmark.InlineLink?
  summary : String
}

///|
fn citation_number(key : String) -> String? {
  if key =~ re"^\^[1-9][0-9]*$" {
    Some(key[1:].to_owned())
  } else {
    None
  }
}

///|
fn MarkdownRender::citation(
  self : MarkdownRender,
  link : @cmark.InlineLink,
) -> Citation? {
  guard !self.in_sources &&
    link.referenced_label() is Some(label) &&
    citation_number(label.key) is Some(number) &&
    link.reference_definition(self.defs) is Some(FootnoteDef(node)) else {
    return None
  }
  for citation in self.citations {
    if citation.number == number {
      return Some(citation)
    }
  }
  let (link, summary) = self.citation_details(node.v.block)
  let citation = Citation::{ number, block: node.v.block, link, summary, }
  self.citations.push(citation)
  Some(citation)
}

///|
/// Find the first usable source link and a plain-text preview. Code and nested
/// definitions do not become source actions. The footer still renders the full
/// note (including page/section/sheet metadata) as ordinary escaped Markdown.
fn MarkdownRender::citation_details(
  self : MarkdownRender,
  block : @cmark.Block,
) -> (@cmark.InlineLink?, String) {
  let links : Array[@cmark.InlineLink] = []
  let parts : Array[String] = []
  let folder : @cmark.Folder[Unit] = @cmark.Folder::new(
    block=(_, _, block) => {
      match block {
        ExtFootnoteDefinition(_) => @cmark.Folder::ret(())
        Paragraph(node) => {
          parts.push(plain_text(node.v.inline))
          Default
        }
        Heading(node) => {
          parts.push(plain_text(node.v.inline))
          Default
        }
        _ => Default
      }
    },
    inline=(_, _, inline) => {
      if links.is_empty() &&
        inline is Link(node) &&
        (
          self.file_destination(node.v) is Some(_) ||
          self.link_destination(node.v) is Some(_)
        ) {
        links.push(node.v)
      }
      Default
    },
  )
  folder.fold_block((), block) catch {
    _ => ()
  }
  (links.get(0), parts.join(" "))
}

///|
fn MarkdownRender::sources_label(self : MarkdownRender) -> String {
  match self.locale {
    English => "Sources"
    SimplifiedChinese => "来源"
    TraditionalChinese => "來源"
    Japanese => "出典"
    Spanish => "Fuentes"
  }
}

///|
fn MarkdownRender::citation_label(
  self : MarkdownRender,
  number : String,
) -> String {
  match self.locale {
    English => "Source \{number}"
    SimplifiedChinese => "来源 \{number}"
    TraditionalChinese => "來源 \{number}"
    Japanese => "出典 \{number}"
    Spanish => "Fuente \{number}"
  }
}

///|
fn MarkdownRender::citation_node(
  self : MarkdownRender,
  citation : Citation,
) -> @html.Html {
  let label = self.citation_label(citation.number)
  let title = if citation.summary.is_empty() {
    label
  } else {
    "\{label}: \{citation.summary}"
  }
  let attrs = @html.Attrs::build().aria_label(title)
  let children = [@html.text(citation.number)]
  let node = if citation.link is Some(link) &&
    self.open_file is Some(open) &&
    self.file_destination(link) is Some(path) {
    let path = @office_location.citation_destination(path, citation.summary)
    @html.button(
      class="citation-link file-link",
      type_="button",
      title~,
      attrs=attrs
        .data_set("context-file", path)
        .data_set("context-workspace-file", FileReference(path).path()),
      on_click=open(path),
      children,
    )
  } else if citation.link is Some(link) &&
    self.link_destination(link) is Some(href) {
    @html.a(
      class="citation-link",
      href~,
      target=Blank,
      rel="noopener noreferrer",
      title~,
      attrs~,
      children,
    )
  } else {
    // A textual footnote or an incomplete streamed source has no made-up
    // destination. Its contents remain readable in the Sources list.
    @html.span(class="citation-link citation-note", title~, attrs~, children)
  }
  @html.sup(
    class="citation",
    attrs=@html.Attrs::build().data_set("citation", citation.number),
    [node],
  )
}

///|
fn MarkdownRender::sources_node(self : MarkdownRender) -> @html.Html {
  let rows : Array[@html.Html] = []
  let previews : Array[@html.Html] = []
  for citation in self.citations {
    let source_path = citation.link.bind(link => self.file_destination(link))
    let render = {
      ..self,
      in_sources: true,
      open_file: self.open_file.map(open => {
        path => {
          open(
            if source_path == Some(path) {
              @office_location.citation_destination(path, citation.summary)
            } else {
              path
            },
          )
        }
      }),
    }
    if previews.length() < 3 {
      previews.push(self.source_glyph(citation))
    }
    rows.push(
      @html.li(
        class="citation-source",
        attrs=@html.Attrs::build().data_set("source", citation.number),
        [
          self.source_glyph(citation),
          @html.div(class="citation-source-content", [
            @html.div(
              class="citation-source-origin",
              self.source_origin(citation),
            ),
            @html.div(
              class="citation-source-copy",
              render.block_nodes(citation.block),
            ),
          ]),
          @html.span(class="citation-source-number", citation.number),
        ],
      ),
    )
  }
  @html.details(
    class="citation-sources",
    attrs=@html.Attrs::build().role("group").aria_label(self.sources_label()),
    [
      @html.summary(class="citation-sources-heading", [
        @html.span(class="citation-source-previews", previews),
        @html.text(self.sources_label()),
        @html.span(
          class="citation-sources-count",
          self.citations.length().to_string(),
        ),
        @html.span(class="citation-sources-chevron", [
          @icons.icon(@icons.icon_chevron_down),
        ]),
      ]),
      @html.ol(class="citation-source-list", rows),
    ],
  )
}

///|
fn MarkdownRender::source_glyph(
  self : MarkdownRender,
  citation : Citation,
) -> @html.Html {
  let (kind, icon) = if citation.link is Some(link) &&
    self.file_destination(link) is Some(path) {
    let kind = @workspace_file_ref.file_kind(FileReference(path).path())
    (
      workspace_file_kind_class(kind),
      @icons.codicon(@workspace_file_ref.file_icon_path(kind)),
    )
  } else if citation.link is Some(_) {
    ("web", @icons.icon_globe())
  } else {
    ("note", @icons.icon_book())
  }
  @html.span(
    class="citation-source-glyph workspace-file-glyph \{kind}",
    attrs=@html.Attrs::build().aria_hidden("true"),
    [icon],
  )
}

///|
fn MarkdownRender::source_origin(
  self : MarkdownRender,
  citation : Citation,
) -> String {
  if citation.link is Some(link) {
    if self.file_destination(link) is Some(path) {
      return workspace_file_kind_label(
        self.locale,
        @workspace_file_ref.file_kind(FileReference(path).path()),
      )
    }
    if self.link_destination(link) is Some(destination) {
      let uri = @common.Uri::parse(destination) catch {
        _ => return self.sources_label()
      }
      if !uri.authority.is_empty() {
        // Display the site, never URL credentials, alongside the source title.
        return match uri.authority.rev_split_once("@") {
          Some((_, host)) => host.to_owned()
          None => uri.authority
        }
      }
    }
  }
  self.sources_label()
}
