///|
pub(all) struct MarkdownInput {
  source : String
  locale : @i18n.Locale
  class : String
  defer_artifacts : Bool
  artifact_view : ((@workspace_file_ref.WorkspaceFileRef) -> @html.Html)?
}

///|
pub impl Eq for MarkdownInput with fn equal(left, right) {
  left.source == right.source &&
  left.locale == right.locale &&
  left.class == right.class &&
  left.defer_artifacts == right.defer_artifacts &&
  physical_equal(left.artifact_view, right.artifact_view)
}

///|
priv struct MarkdownContext {
  id : String
  next_menu : Ref[Int32]
  open_file : (String) -> @cmd.Cmd
  input : @rabbita.Val[@action_menu.ContextInput]
  actions : @action_menu.ContextActions
}

///|
priv struct MarkdownScope {
  render : MarkdownRender
  references : Array[ReferenceMarkup]
  source_title : (@cmark.Inline, Int32)?
  source_destination : (String, String)?
}

///|
priv struct ReferenceMarkup {
  inline : @cmark.Inline
  html : @html.Html
  target : @action_menu.ContextTarget
  revision : (String, String)?
}

///|
fn MarkdownScope::reference(
  self : MarkdownScope,
  inline : @cmark.Inline,
) -> ReferenceMarkup? {
  for reference in self.references {
    if physical_equal(inline, reference.inline) {
      return Some(reference)
    }
  }
  None
}

///|
fn MarkdownScope::is_title(
  self : MarkdownScope,
  inline : @cmark.Inline,
  index : Int32,
) -> Bool {
  self.source_title is Some((title, position)) &&
  physical_equal(title, inline) &&
  position == index
}

///|
priv struct Scoped[A] {
  scope : MarkdownScope
  node : A
}

///|
impl[A] Eq for Scoped[A] with fn equal(left, right) {
  physical_equal(left, right)
}

///|
priv struct ParsedMarkdown {
  root : @cmark.Block
  scope : MarkdownScope
  fallback : @html.Html?
}

///|
impl Eq for ParsedMarkdown with fn equal(left, right) {
  physical_equal(left, right)
}

///|
/// Markdown paragraphs, table cells and other parents own their child
/// components. Only those child branches are reconciled when the input grows.
pub fn markdown_component(
  input : @rabbita.Val[MarkdownInput],
  id : String,
  open_file~ : (String) -> @cmd.Cmd,
  context : @rabbita.Val[@action_menu.ContextInput],
  actions : @action_menu.ContextActions,
) -> @rabbita.Val[@html.Html] {
  let context : MarkdownContext = {
    id,
    next_menu: Ref(0),
    input: context,
    actions,
    open_file,
  }
  let parsed = input.map(value => prepare_markdown(value, open_file, id))
  let blocks = block_components(
    parsed.map(doc => { scope: doc.scope, node: doc.root, }),
    context,
  )
  let sources = source_components(parsed, context)
  let notes = footnote_components(parsed, context)
  let class = input.map(input => input.class)
  parsed.map5(blocks, sources, notes, class, (
    parsed,
    blocks,
    sources,
    notes,
    class,
  ) => {
    let children : Map[String, @html.Html] = Map([])
    if parsed.fallback is Some(fallback) {
      children["fallback"] = fallback
    }
    for index, block in blocks {
      children[index.to_string()] = block
    }
    if sources is Some(sources) {
      children["sources"] = sources
    }
    if notes is Some(notes) {
      children["footnotes"] = notes
    }
    @html.div(class~, children)
  })
}

///|
fn prepare_markdown(
  input : MarkdownInput,
  open_file : (String) -> @cmd.Cmd,
  id : String,
) -> ParsedMarkdown {
  let render : MarkdownRender = {
    locale: input.locale,
    defs: Map([]),
    open_file: Some(open_file),
    artifact_view: input.artifact_view,
    defer_artifacts: input.defer_artifacts,
    render_math: math_node,
    citations: [],
    footnotes: Footnotes::new(prefix=id + "-note"),
    in_sources: false,
    user_preview: false,
  }
  @js.Error_::wrap(() => {
    let doc = @cmark.Doc::from_string(input.source, strict=false)
    let render = { ..render, defs: doc.defs, }
    let references = []
    if doc.defs.values().any(definition => definition is FootnoteDef(_)) {
      register_references(render, doc.block, references)
      let note_render = { ..render, in_sources: true, }
      for citation in render.citations {
        register_references(note_render, citation.block, references)
      }
      for index = 0; index < render.footnotes.notes.length(); index = index + 1 {
        register_references(
          note_render,
          render.footnotes.notes[index].block,
          references,
        )
      }
    }
    let scope : MarkdownScope = {
      render,
      references,
      source_title: None,
      source_destination: None,
    }
    @js.Value::cast_from(ParsedMarkdown::{
      root: doc.block,
      scope,
      fallback: None,
    })
  }) catch {
    _ =>
      {
        root: @cmark.Block::empty(),
        scope: {
          render,
          references: [],
          source_title: None,
          source_destination: None,
        },
        fallback: Some(@html.pre(class="markdown-fallback", input.source)),
      }
  }
}

///|
fn register_references(
  render : MarkdownRender,
  block : @cmark.Block,
  references : Array[ReferenceMarkup],
) -> Unit {
  let folder : @cmark.Folder[Unit] = @cmark.Folder::new(
    block=(_, _, block) => {
      if block is ExtFootnoteDefinition(_) {
        Fold(())
      } else {
        Default
      }
    },
    inline=(_, _, inline) => {
      match inline {
        Link(node) =>
          match render.citation(node.v) {
            Some(citation) =>
              references.push({
                inline,
                html: render.citation_node(citation, node.v),
                target: citation_menu_target(render, citation),
                revision: Some((citation.number, citation.summary)),
              })
            None =>
              if render.footnote_reference(node.v) is Some(note) {
                references.push({
                  inline,
                  html: note,
                  target: NoTarget,
                  revision: None,
                })
              }
          }
        Image(_) => return Fold(())
        _ => ()
      }
      Default
    },
  )
  folder.fold_block((), block) catch {
    _ => ()
  }
}

///|
fn citation_menu_target(
  render : MarkdownRender,
  citation : Citation,
) -> @action_menu.ContextTarget {
  guard citation.link is Some(link) else { return NoTarget }
  if render.file_destination(link) is Some(path) {
    let path = @office_location.citation_destination(path, citation.summary)
    FileLink(path, workspace_file=Some(FileReference(path).path()))
  } else {
    render.link_destination(link).map_or(NoTarget, @action_menu.link_target)
  }
}

///|
fn[A, B : Eq] component_children(
  children : @rabbita.Val[Array[(String, Scoped[A])]],
  render : (String, @rabbita.Val[Scoped[A]]) -> @rabbita.Val[B],
) -> @rabbita.Val[Array[B]] {
  children
  .map(children => @vector.from_array(children))
  .assoc_by((key, child) => render(key, child.map(child => child.1)), by=child => {
    child.0
  })
  .map(children => children.to_array())
}

///|
fn block_children(block : @cmark.Block, out : Array[@cmark.Block]) -> Unit {
  match block {
    Blocks(node) =>
      for child in node.v {
        block_children(child, out)
      }
    BlankLine(_) | LinkRefDefinition(_) | ExtFootnoteDefinition(_) => ()
    _ => out.push(block)
  }
}

///|
fn block_has_context_links(block : @cmark.Block) -> Bool {
  let folder : @cmark.Folder[Bool] = @cmark.Folder::new(
    block=(_, found, block) => {
      if found {
        Fold(true)
      } else {
        match block {
          CodeBlock(_)
          | HtmlBlock(_)
          | ThematicBreak(_)
          | BlankLine(_)
          | LinkRefDefinition(_)
          | ExtFootnoteDefinition(_) => Fold(false)
          _ => Default
        }
      }
    },
    inline=(_, found, inline) => {
      if found {
        return Fold(true)
      }
      match inline {
        Link(_) | Autolink(_) => Fold(true)
        Text(node) =>
          if bare_interactive_pattern.execute(node.v.clamped_view()) is Some(_) {
            Fold(true)
          } else {
            Fold(false)
          }
        Image(_) | CodeSpan(_) | Break(_) | ExtMathSpan(_) | RawHtml(_) =>
          Fold(false)
        _ => Default
      }
    },
  )
  folder.fold_block(false, block) catch {
    _ => true
  }
}

///|
fn block_key(block : @cmark.Block) -> String {
  if !block_has_context_links(block) {
    return "leaf"
  }
  match block {
    Paragraph(_) => "paragraph"
    Heading(_) => "heading"
    BlockQuote(_) => "quote"
    List(_) => "list"
    ExtTable(_) => "table"
    _ => "leaf"
  }
}

///|
fn block_components(
  input : @rabbita.Val[Scoped[@cmark.Block]],
  context : MarkdownContext,
  tight~ : Bool = false,
) -> @rabbita.Val[Array[@html.Html]] {
  let children = input.map(input => {
    let blocks = []
    block_children(input.node, blocks)
    blocks.mapi((index, node) => {
      ("\{block_key(node)}:\{index}", { scope: input.scope, node, })
    })
  })
  component_children(children, (key, block) => {
    block_component(key, block, context, tight)
  })
}

///|
fn block_component(
  key : String,
  input : @rabbita.Val[Scoped[@cmark.Block]],
  context : MarkdownContext,
  tight : Bool,
) -> @rabbita.Val[@html.Html] {
  if key.has_prefix("paragraph:") || key.has_prefix("heading:") {
    let children = inline_components(
      input.map(input => {
        let node = match input.node {
          Paragraph(node) => node.v.inline
          Heading(node) => node.v.inline
          _ => @cmark.Inline::empty()
        }
        { scope: input.scope, node, }
      }),
      context,
    )
    input.map2(children, (input, children) => {
      match input.node {
        Heading(heading) => heading_html(heading.v, children)
        _ => if tight { @html.fragment(children) } else { @html.p(children) }
      }
    })
  } else if key.has_prefix("quote:") {
    block_components(
      input.map(input => {
        let node = if input.node is BlockQuote(quote) {
          quote.v.block
        } else {
          @cmark.Block::empty()
        }
        { scope: input.scope, node, }
      }),
      context,
    ).map(children => @html.blockquote(children))
  } else if key.has_prefix("list:") {
    list_component(input, context)
  } else if key.has_prefix("table:") {
    table_component(input, context)
  } else {
    input.map(input => {
      let children : Array[@html.Html] = if tight {
        input.scope.render.list_item_nodes(input.node, tight=true)
      } else {
        input.scope.render.block_nodes(input.node)
      }
      match children {
        [] => @html.nothing
        [single] => single
        _ => @html.fragment(children)
      }
    })
  }
}

///|
fn inline_children(inline : @cmark.Inline, out : Array[@cmark.Inline]) -> Unit {
  if inline is Inlines(node) {
    for child in node.v {
      inline_children(child, out)
    }
  } else {
    out.push(inline)
  }
}

///|
fn inline_key(inline : @cmark.Inline) -> String {
  match inline {
    Emphasis(_) => "em"
    StrongEmphasis(_) => "strong"
    ExtStrikethrough(_) => "del"
    Link(_) => "link"
    Autolink(_) => "auto"
    Text(_) => "text"
    _ => "leaf"
  }
}

///|
fn inline_components(
  input : @rabbita.Val[Scoped[@cmark.Inline]],
  context : MarkdownContext,
  linkify~ : Bool = true,
) -> @rabbita.Val[Array[@html.Html]] {
  let children = input.map(input => {
    let nodes = []
    inline_children(input.node, nodes)
    nodes.mapi((index, node) => {
      ("\{inline_key(node)}:\{index}", { scope: input.scope, node, })
    })
  })
  component_children(children, (key, inline) => {
    inline_component(key, inline, context, linkify)
  })
}

///|
fn inline_component(
  key : String,
  input : @rabbita.Val[Scoped[@cmark.Inline]],
  context : MarkdownContext,
  linkify : Bool,
) -> @rabbita.Val[@html.Html] {
  let tag = key.split_once(":").map(pair => pair.0).unwrap_or("")
  match tag {
    "em" | "strong" | "del" => {
      let children = inline_components(
        input.map(input => {
          let node = match input.node {
            Emphasis(node) | StrongEmphasis(node) => node.v.inline
            ExtStrikethrough(node) => node.v.0
            _ => @cmark.Inline::empty()
          }
          { scope: input.scope, node, }
        }),
        context,
        linkify~,
      )
      children.map(children => {
        match tag {
          "em" => @html.em(children)
          "strong" => @html.strong(children)
          _ => @html.del(children)
        }
      })
    }
    "link" | "auto" => inline_link_component(input, context)
    "text" if linkify => prose_component(input, context)
    _ =>
      input.map(input => {
        let nodes : Array[@html.Html] = input.scope.render.inline_nodes(
          input.node,
          linkify_urls=linkify,
        )
        nodes.get(0).unwrap_or(@html.nothing)
      })
  }
}

///|
fn inline_target(
  render : MarkdownRender,
  inline : @cmark.Inline,
) -> @action_menu.ContextTarget {
  match inline {
    Link(node) =>
      if render.file_destination(node.v) is Some(path) {
        FileLink(path, workspace_file=Some(FileReference(path).path()))
      } else {
        render
        .link_destination(node.v)
        .map_or(NoTarget, @action_menu.link_target)
      }
    Autolink(node) => {
      let url = node.v.link.v
      if node.v.is_email {
        @action_menu.link_target("mailto:" + url)
      } else {
        render.safe_destination(url).map_or(NoTarget, @action_menu.link_target)
      }
    }
    _ => NoTarget
  }
}

///|
priv struct MarkdownLink {
  input : Scoped[@cmark.Inline]
  revision : String?
}

///|
impl Eq for MarkdownLink with fn equal(left, right) {
  physical_equal(left, right) ||
  (left.revision is Some(revision) && right.revision == Some(revision))
}

///|
fn markdown_link(input : Scoped[@cmark.Inline]) -> MarkdownLink {
  let render = input.scope.render
  let reference = input.scope.reference(input.node)
  let target = match reference {
    Some(reference) => reference.target
    None => inline_target(render, input.node)
  }
  let revision = if target is NoTarget {
    None
  } else {
    let title = match input.node {
      Link(node) => render.link_title(node.v)
      _ => None
    }
    Some(
      markdown_revision(
        (
          render.locale.tag(),
          input.node,
          target,
          title,
          input.scope.is_title(input.node, 0),
          reference.map(reference => reference.revision),
        ),
      ),
    )
  }
  { input, revision, }
}

///|
fn inline_link_component(
  input : @rabbita.Val[Scoped[@cmark.Inline]],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html] {
  let input = input.map(markdown_link).map(link => link.input)
  let label = inline_components(
    input.map(input => {
      let node = if input.node is Link(link) {
        link.v.text
      } else {
        @cmark.Inline::empty()
      }
      { scope: input.scope, node, }
    }),
    context,
    linkify=false,
  )
  let content = input.map2(label, (input, label) => {
    let render = input.scope.render
    if input.scope.reference(input.node) is Some(reference) {
      return reference.html
    }
    let source_title = input.scope.is_title(input.node, 0)
    match input.node {
      Link(node) => render.render_link_html(node.v, label, source_title~)
      Autolink(node) => render.render_autolink_html(node.v, source_title~)
      _ => @html.nothing
    }
  })
  let locale = input.map(input => input.scope.render.locale)
  let target = input.map(input => {
    if input.scope.reference(input.node) is Some(reference) {
      reference.target
    } else if input.scope.is_title(input.node, 0) {
      NoTarget
    } else {
      inline_target(input.scope.render, input.node)
    }
  })
  link_menu(locale, target, context, content)
}

///|
fn prose_component(
  input : @rabbita.Val[Scoped[@cmark.Inline]],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html] {
  let locale = input.map(input => input.scope.render.locale)
  let pieces = input.map(input => {
    guard input.node is Text(node) else { return @vector.Vector::new() }
    @vector.from_array(
      prose_parts(node.v).mapi((index, part) => {
        let destination = match input.scope.source_destination {
          Some((path, destination)) if path == part.0 => destination
          _ => part.0
        }
        (
          index,
          part.0,
          part.1,
          input.scope.is_title(input.node, index),
          destination,
        )
      }),
    )
  })
  let has_links = pieces.map(pieces => {
    pieces.iter().any(part => part.2 != NoTarget)
  })
  has_links.switch_by(
    interactive => {
      if !interactive {
        return input.map(input => {
          if input.node is Text(node) {
            @html.text(node.v)
          } else {
            @html.nothing
          }
        })
      }
      pieces
      .assoc_by(
        (_, part) => {
          let content = part.map2(locale, (part, locale) => {
            let (_, text, target, source_title, destination) = part
            render_prose_part_html(
              locale,
              text,
              target,
              path => {
                (context.open_file)(
                  if path == text {
                    destination
                  } else {
                    path
                  },
                )
              },
              source_title~,
            )
          })
          let target = part.map(part => {
            if part.3 {
              @action_menu.NoTarget
            } else {
              part.2
            }
          })
          link_menu(locale, target, context, content)
        },
        by=part => part.0,
      )
      .map(children => @html.fragment(children.to_array()))
    },
    by=interactive => if interactive { "links" } else { "text" },
  )
}

///|
fn link_menu(
  locale : @rabbita.Val[@i18n.Locale],
  target : @rabbita.Val[@action_menu.ContextTarget],
  context : MarkdownContext,
  content : @rabbita.Val[@html.Html],
  inline~ : Bool = true,
) -> @rabbita.Val[@html.Html] {
  let keyed = target.map(target => {
    if target is NoTarget {
      ("", target)
    } else {
      let id = "\{context.id}-\{context.next_menu.val}"
      context.next_menu.val += 1
      (id, target)
    }
  })
  keyed.switch_by(
    entry => {
      let (id, target) = entry
      if target is NoTarget {
        return content
      }
      @action_menu.link_context(
        id,
        locale,
        context.input,
        target,
        context.actions,
        content,
        inline~,
      )
      // RUI attaches native event listeners to the trigger. A different link
      // at this position needs a new trigger element with its new menu ID.
      .map(menu => @html.span(style=["display:contents"], Map([(id, menu)])))
    },
    by=entry => entry.0,
  )
}

///|
fn list_component(
  input : @rabbita.Val[Scoped[@cmark.Block]],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html] {
  let items = input.map(input => {
    guard input.node is List(list) else { return [] }
    list.v.items
    .to_array()
    .mapi((index, item) => {
      let key = "\{list.v.tight}:\{index}"
      (key, { scope: input.scope, node: item.v, })
    })
  })
  let rows = component_children(items, (key, item) => {
    let body = block_components(
      item.map(item => { scope: item.scope, node: item.node.block, }),
      context,
      tight=key.has_prefix("true:"),
    )
    item.map2(body, (item, body) => list_item_html(item.node, body))
  })
  input.map2(rows, (input, rows) => {
    if input.node is List(list) {
      list_html(list.v, rows)
    } else {
      @html.nothing
    }
  })
}

///|
fn table_component(
  input : @rabbita.Val[Scoped[@cmark.Block]],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html] {
  let groups = input.map(input => {
    guard input.node is ExtTable(table) else { return [] }
    table_groups(table.v).mapi((index, group) => {
      (index.to_string(), { scope: input.scope, node: group, })
    })
  })
  component_children(groups, (_, group) => {
    let rows = group.map(group => {
      group.node.mapi((index, row) => {
        (index.to_string(), { scope: group.scope, node: row, })
      })
    })
    let rows = component_children(rows, (_, row) => {
      let cells = row.map(row => {
        row.node.cells.mapi((index, cell) => {
          (
            index.to_string(),
            { scope: row.scope, node: (row.node.header, cell.0, cell.1), },
          )
        })
      })
      component_children(cells, (_, cell) => {
        let children = inline_components(
          cell.map(cell => { scope: cell.scope, node: cell.node.1, }),
          context,
        )
        cell.map2(children, (cell, children) => {
          table_cell_html(cell.node.0, cell.node.2, children)
        })
      }).map(cells => @html.tr(cells))
    })
    group.map2(rows, (group, rows) => {
      if group.node.get(0) is Some({ header: true, .. }) {
        @html.thead(rows)
      } else {
        @html.tbody(rows)
      }
    })
  }).map(table_html)
}

///|
fn source_components(
  input : @rabbita.Val[ParsedMarkdown],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html?] {
  let rows = input.map(input => {
    input.scope.render.citations.map(citation => {
      (citation.number, { scope: input.scope, node: citation, })
    })
  })
  let cards = component_children(rows, (_, row) => {
    source_component(row, context)
  })
  input.map2(cards, (input, cards) => {
    if cards.is_empty() {
      None
    } else {
      Some(input.scope.render.sources_html(cards))
    }
  })
}

///|
priv struct SourceInput {
  input : Scoped[Citation]
  revision : String
}

///|
impl Eq for SourceInput with fn equal(left, right) {
  left.revision == right.revision &&
  physical_equal(
    left.input.scope.render.artifact_view,
    right.input.scope.render.artifact_view,
  )
}

///|
fn source_input(input : Scoped[Citation]) -> SourceInput {
  let render = input.scope.render
  let definitions : Array[@cmark.LabelDef?] = []
  let folder : @cmark.Folder[Unit] = @cmark.Folder::new(inline=(_, _, inline) => {
    if inline is (Link(node) | Image(node)) {
      definitions.push(node.v.reference_definition(render.defs))
    }
    Default
  })
  folder.fold_block((), input.node.block) catch {
    _ => ()
  }
  let revision = markdown_revision(
    (render.locale.tag(), render.defer_artifacts, input.node, definitions),
  )
  { input, revision, }
}

///|
fn source_component(
  input : @rabbita.Val[Scoped[Citation]],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html] {
  let input = input.map(source_input).map(source => source.input)
  let input = input.map(input => {
    let render = input.scope.render
    let citation = input.node
    let source_path = citation.link.bind(link => render.file_destination(link))
    let source_destination = source_path.map(path => {
      (path, @office_location.citation_destination(path, citation.summary))
    })
    let render = {
      ..render,
      in_sources: true,
      open_file: render.open_file.map(open => {
        path => {
          open(
            match source_destination {
              Some((source, destination)) if path == source => destination
              _ => path
            },
          )
        }
      }),
    }
    let (source_title, target) = find_source_title(render, citation.block)
    (
      {
        scope: { ..input.scope, render, source_title, source_destination, },
        node: citation,
      },
      target,
    )
  })
  let source = input.map(input => input.0)
  let body = block_components(
    source.map(source => { scope: source.scope, node: source.node.block, }),
    context,
  )
  let card = source.map2(body, (source, body) => {
    source.scope.render.source_card_html(source.node, body)
  })
  let locale = source.map(source => source.scope.render.locale)
  let target = input.map(input => input.1)
  let card = link_menu(locale, target, context, card, inline=false)
  source.map2(card, (source, card) => {
    source.scope.render.source_row_html(source.node, card)
  })
}

///|
fn find_source_title(
  render : MarkdownRender,
  block : @cmark.Block,
) -> ((@cmark.Inline, Int32)?, @action_menu.ContextTarget) {
  let folder : @cmark.Folder[
    ((@cmark.Inline, Int32)?, @action_menu.ContextTarget),
  ] = @cmark.Folder::new(
    block=(_, acc, block) => {
      if acc.0 is Some(_) || block is ExtFootnoteDefinition(_) {
        Fold(acc)
      } else {
        Default
      }
    },
    inline=(_, acc, inline) => {
      if acc.0 is Some(_) {
        return Fold(acc)
      }
      if inline is Text(node) {
        for index, piece in prose_parts(node.v) {
          if piece.1 != NoTarget {
            return Fold((Some((inline, index)), piece.1))
          }
        }
      }
      if inline is Link(node) &&
        node.v.reference_definition(render.defs) is Some(FootnoteDef(_)) {
        return Fold(acc)
      }
      let target = inline_target(render, inline)
      if target != NoTarget {
        Fold((Some((inline, 0)), target))
      } else if inline is Image(_) {
        Fold(acc)
      } else {
        Default
      }
    },
  )
  folder.fold_block((None, NoTarget), block) catch {
    _ => (None, NoTarget)
  }
}

///|
fn footnote_components(
  input : @rabbita.Val[ParsedMarkdown],
  context : MarkdownContext,
) -> @rabbita.Val[@html.Html?] {
  let notes = input.map(input => {
    let scope = {
      ..input.scope,
      render: { ..input.scope.render, in_sources: true, },
    }
    scope.render.footnotes.notes.map(note => (note.key, { scope, node: note, }))
  })
  component_children(notes, (_, note) => {
    let body = block_components(
      note.map(note => { scope: note.scope, node: note.node.block, }),
      context,
    )
    note.map2(body, (note, body) => footnote_html(note.node, body))
  }).map(items => {
    if items.is_empty() {
      None
    } else {
      Some(footnotes_html(items))
    }
  })
}

///|
/// The parser omits source locations by default, so repeated parses can
/// compare the content of labels and source cards across streaming updates.
fn[T : Debug] markdown_revision(value : T) -> String {
  @debug.render(Repr::Repr(value), max_depth=@int.MAX_VALUE)
}
