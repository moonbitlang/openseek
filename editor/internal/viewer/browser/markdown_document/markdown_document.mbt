///|
/// One source-bearing DOM line from the current same-parse Markdown
/// projection. The stable block/line indices are presentation identities;
/// `code_line` retains the exact UTF-16 boundary map back into the original
/// model snapshot.
pub struct MarkdownSemanticCodeLineDom {
  block_index : Int
  block_source_range : @base_common.OffsetRange
  line_index : Int
  priv code_line : @markdown_core.MarkdownCodeLine
  element : @rdom.Element
}

///|
/// Everything attached to one installed article generation. It is retired
/// before `RenderedMarkdown::dispose`, so callbacks cannot observe detached
/// line nodes and a caller can never retain a registry from two parses.
priv struct MarkdownSemanticDomLifetime {
  lines : Array[MarkdownSemanticCodeLineDom]
  listeners : Array[@base_common.Disposable]
  mut disposed : Bool
}

///|
fn MarkdownSemanticDomLifetime::empty() -> MarkdownSemanticDomLifetime {
  { lines: [], listeners: [], disposed: false, }
}

///|
fn MarkdownSemanticDomLifetime::dispose(
  self : MarkdownSemanticDomLifetime,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
  self.lines.clear()
}

///|
/// One JS-only readonly Markdown surface. The source model stays owned by the
/// root Viewer; this value owns only presentation DOM, the retained same-parse
/// projection, and listeners whose lifetime is one model attachment.
struct MarkdownDocumentView {
  root : @rdom.Element
  viewport : @rdom.Element
  article : @rdom.Element
  overlay_mount : @rdom.Element
  resource_kind : @markdown_core.MarkdownResourceKind
  language_id : String
  base_uri : @base_common.Uri
  on_size_changed : () -> Unit
  mut source : String
  mut source_model_version : Int
  mut theme : String
  mut projection_generation : Int
  mut rendered : @browser_markdown.RenderedMarkdown
  mut diagram_viewports : @diagram_viewport.DiagramViewports
  mut semantic_dom : MarkdownSemanticDomLifetime
  listeners : Array[@base_common.Disposable]
  mut on_section_fold_toggle : (Int) -> Unit
  toc_nav : @rdom.Element
  toc_list : @rdom.Element
  toc_toggle : @rdom.Element
  mut on_toc_navigate : (Int) -> Unit
  mut disposed : Bool
}

///|
fn markdown_document_root_class(show_unused : Bool) -> String {
  "moonbit-viewer-markdown-document\{(if show_unused { " showUnused" } else { "" })}"
}

///|
pub fn MarkdownDocumentView::MarkdownDocumentView(
  source : String,
  source_model_version : Int,
  language_id : String,
  base_uri : @base_common.Uri,
  resource_kind : @markdown_core.MarkdownResourceKind,
  theme : String,
  on_scroll : () -> Unit,
  on_focus_changed : (Bool) -> Unit,
  on_size_changed : () -> Unit,
  show_unused? : Bool = true,
) -> MarkdownDocumentView {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", markdown_document_root_class(show_unused))
  root.set_attribute("aria-label", "Readonly Markdown viewer")
  root.set_attribute("tabindex", "0")
  root.set_attribute("data-theme", theme)
  root.set_attribute("data-uri", base_uri.to_string())
  root.set_attribute("data-source-uri", base_uri.to_string())
  let viewport = document.create_element("div")
  viewport.set_attribute("class", "moonbit-viewer-markdown-document-viewport")
  let article = document.create_element("article")
  article.set_attribute("class", "moonbit-viewer-markdown-document-article")
  let overlay_mount = document.create_element("div")
  overlay_mount.set_attribute(
    "class", "moonbit-viewer-markdown-document-overlays",
  )
  viewport.append_child(article.as_node())
  // The TOC bar is pinned in the root, above the viewport: a sibling of the
  // article, never a child, because every article child index is a projection
  // ordinal the folding and source-anchor machinery depends on.
  let toc_nav = document.create_element("nav")
  toc_nav.set_attribute("class", "moonbit-viewer-markdown-toc")
  toc_nav.set_attribute("aria-label", "Table of contents")
  toc_nav.set_attribute("data-toc-visible", "false")
  let toc_toggle = document.create_element("button")
  toc_toggle.set_attribute("type", "button")
  toc_toggle.set_attribute("class", "moonbit-viewer-markdown-toc-toggle")
  toc_toggle.set_attribute("aria-expanded", "false")
  let toc_list = document.create_element("ol")
  toc_list.set_attribute("class", "moonbit-viewer-markdown-toc-list")
  toc_nav.append_child(toc_toggle.as_node())
  toc_nav.append_child(toc_list.as_node())
  root.append_child(toc_nav.as_node())
  root.append_child(viewport.as_node())
  root.append_child(overlay_mount.as_node())
  let (rendered, diagram_viewports) = render_markdown_document_presentation(
    source, language_id, base_uri, resource_kind, theme, article, on_size_changed,
  )
  let view : MarkdownDocumentView = {
    root,
    viewport,
    article,
    overlay_mount,
    resource_kind,
    language_id,
    base_uri,
    on_size_changed,
    source,
    source_model_version,
    theme,
    projection_generation: 1,
    rendered,
    diagram_viewports,
    semantic_dom: MarkdownSemanticDomLifetime::empty(),
    listeners: [],
    on_section_fold_toggle: _ => (),
    toc_nav,
    toc_list,
    toc_toggle,
    on_toc_navigate: _ => (),
    disposed: false,
  }
  view.post_render()
  // One delegated listener owns every fold-toggle click for the view's whole
  // lifetime: the article element survives projection replacements even
  // though its children do not, so per-button listeners would need
  // per-generation bookkeeping for no benefit.
  view.listen(article, "click", event => {
    guard !view.disposed else { return }
    match markdown_fold_toggle_section(event) {
      Some(section_index) => (view.on_section_fold_toggle)(section_index)
      None => ()
    }
  })
  view.listen(toc_nav, "click", event => {
    guard !view.disposed else { return }
    guard event.target().to_element() is Some(target) else { return }
    if target.closest(".moonbit-viewer-markdown-toc-toggle") is Some(_) {
      let expanded = view.toc_nav.get_attribute("data-toc-expanded") ==
        Some("true")
      view.toc_nav.set_attribute(
        "data-toc-expanded",
        if expanded {
          "false"
        } else {
          "true"
        },
      )
      view.toc_toggle.set_attribute(
        "aria-expanded",
        if expanded {
          "false"
        } else {
          "true"
        },
      )
      return
    }
    match target.closest("[data-toc-offset]") {
      Some(row) =>
        match row.get_attribute("data-toc-offset") {
          Some(raw) =>
            match markdown_parse_section_index(raw) {
              Some(offset) => {
                // Row activation is a completed navigation, so return the
                // TOC to its compact state before reveal math runs. Otherwise
                // the expanded overlay can cover the heading aligned to the
                // viewport start edge.
                @base_browser.focus_prevent_scroll(view.toc_toggle)
                view.toc_nav.set_attribute("data-toc-expanded", "false")
                view.toc_toggle.set_attribute("aria-expanded", "false")
                (view.on_toc_navigate)(offset)
                view.scroll_toc_entry_into_view(offset)
              }
              None => ()
            }
          None => ()
        }
      None => ()
    }
  })
  view.listen(viewport, "scroll", _event => if !view.disposed { on_scroll() })
  view.listen(root, "focus", _event => {
    if !view.disposed {
      on_focus_changed(true)
    }
  })
  view.listen(root, "blur", _event => {
    if !view.disposed {
      on_focus_changed(false)
    }
  })
  view
}

///|
/// Builds one replaceable article generation and its diagram-controller
/// lifetime. Renderer callbacks include asynchronous Mermaid commits, so they
/// reconcile replaced SVGs before reporting the size change. Controller-owned
/// resize gestures report size directly and never rescan the article tree.
fn render_markdown_document_presentation(
  source : String,
  language_id : String,
  base_uri : @base_common.Uri,
  resource_kind : @markdown_core.MarkdownResourceKind,
  theme : String,
  article : @rdom.Element,
  on_size_changed : () -> Unit,
) -> (@browser_markdown.RenderedMarkdown, @diagram_viewport.DiagramViewports) {
  let diagram_viewports_slot : Ref[@diagram_viewport.DiagramViewports?] = Ref(
    None,
  )
  let on_rendered_size_changed = () => {
    match diagram_viewports_slot.val {
      Some(diagram_viewports) => diagram_viewports.refresh()
      None => ()
    }
    on_size_changed()
  }
  let rendered = render_markdown_document(
    source, language_id, base_uri, resource_kind, theme, article, on_rendered_size_changed,
  )
  let diagram_viewports = @diagram_viewport.DiagramViewports(
    article, on_size_changed,
  )
  diagram_viewports_slot.val = Some(diagram_viewports)
  (rendered, diagram_viewports)
}

///|
fn render_markdown_document(
  source : String,
  language_id : String,
  base_uri : @base_common.Uri,
  resource_kind : @markdown_core.MarkdownResourceKind,
  theme : String,
  article : @rdom.Element,
  on_size_changed : () -> Unit,
) -> @browser_markdown.RenderedMarkdown {
  // Keep sanitized links as native anchors. Desktop captures ordinary clicks
  // and routes them to its dock, while Chromium retains modified and middle
  // clicks so the embedding browser can apply its new-window policy.
  @browser_markdown.render_markdown(
    source,
    options=MarkdownRenderOptions(
      language_id~,
      base_uri~,
      code_block_renderer=(code_block, active_language_id) => {
        render_markdown_document_code_block(
          code_block, active_language_id, resource_kind,
        )
      },
      on_size_changed~,
      allow_remote_images=true,
      mermaid_theme=markdown_document_mermaid_theme(theme),
    ),
    target=article,
  )
}

///|
fn render_markdown_document_code_block(
  code_block : @markdown_core.MarkdownCodeBlock,
  active_language_id : String?,
  resource_kind : @markdown_core.MarkdownResourceKind,
) -> String {
  let fallback = @markdown_core.render_tokenized_code_block(
    code_block, active_language_id,
  )
  let tokenized = if code_block.is_moonbit_check_fence(resource_kind) {
    render_semantic_tokenized_code_lines(code_block, fallback)
  } else {
    fallback
  }
  let body = match code_block.language_id {
    Some("mermaid") =>
      (
        $|<div class="moonbit-viewer-markdown-diagram" data-diagram-language="mermaid" data-mermaid-state="fallback">
        $|\{tokenized}
        $|</div>
        $|
      )
    _ => tokenized
  }
  let semantic_attribute = if code_block.is_moonbit_check_fence(resource_kind) {
    " data-markdown-semantic=\"moonbit-check\""
  } else {
    ""
  }
  (
    $|<div class="moonbit-viewer-markdown-code-block" data-markdown-code-block="\{code_block.block_index}"\{semantic_attribute}>
    $|\{body}</div>
    $|
  )
}

///|
/// Wraps exactly the source-bearing projected lines after the whole block has
/// already been tokenized. This preserves the tokenizer's cross-line state
/// while dropping only `_tokenizeToString`'s synthetic final empty segment
/// caused by the code block's mandatory trailing newline.
fn render_semantic_tokenized_code_lines(
  code_block : @markdown_core.MarkdownCodeBlock,
  tokenized : String,
) -> String {
  let prefix = "<div class=\"monaco-tokenized-source\">"
  let suffix = "</div>"
  guard tokenized.has_prefix(prefix) &&
    tokenized.has_suffix(suffix) &&
    tokenized.length() >= prefix.length() + suffix.length() else {
    return tokenized
  }
  let inner = tokenized[prefix.length():tokenized.length() - suffix.length()].to_owned()
  let rendered_lines = split_tokenized_code_lines(inner)
  // `MarkdownCodeBlock::code` ends in one source newline. The shared
  // tokenizer must therefore produce exactly the projected lines plus one
  // final empty segment. Any future renderer-shape drift disables semantic
  // line markup rather than guessing at source coordinates.
  guard rendered_lines.length() == code_block.code_lines.length() + 1 &&
    tokenized_line_segment_is_empty(rendered_lines[rendered_lines.length() - 1]) else {
    return tokenized
  }
  let result = StringBuilder()
  result.write_string(prefix)
  for line_index, code_line in code_block.code_lines {
    if line_index > 0 {
      result.write_string("<br/>")
    }
    let phrase_divider_attributes = if markdown_semantic_line_is_phrase_divider(
        code_line,
      ) {
      " data-markdown-phrase-divider=\"true\" role=\"separator\" aria-label=\"MoonBit item separator\""
    } else {
      ""
    }
    result <+
      $|<span class="moonbit-viewer-markdown-code-line" data-markdown-block-index="\{code_block.block_index}" data-markdown-code-line="\{line_index}" data-markdown-source-line="\{code_line.source_line_number}" data-markdown-source-start="\{code_line.source_range.start}" data-markdown-source-end="\{code_line.source_range.end_exclusive}"\{phrase_divider_attributes}>\{rendered_lines[line_index]}</span>
  }
  result.write_string(suffix)
  result.to_string()
}

///|
/// Recognizes only a source-bearing, column-zero MoonBit item marker. cmark
/// may prepend synthetic spaces when a fence is nested in Markdown containers;
/// the exact four-unit source range and boundary map keep those spaces from
/// widening the language-level marker contract.
fn markdown_semantic_line_is_phrase_divider(
  code_line : @markdown_core.MarkdownCodeLine,
) -> Bool {
  let marker = "///|"
  guard code_line.source_range.length() == marker.length() &&
    code_line.displayed_text.has_suffix(marker) else {
    return false
  }
  let padding = code_line.displayed_text.length() - marker.length()
  guard padding >= 0 &&
    code_line.source_offset_at_displayed_boundary(padding) ==
    Some(code_line.source_range.start) else {
    return false
  }
  for index in 0..<padding {
    if code_line.displayed_text[index] != ' ' {
      return false
    }
  }
  true
}

///|
/// The shared tokenizer represents an empty line as one empty token span, not
/// an empty string. Recognize only that reviewed shape; arbitrary markup is
/// not accepted as the synthetic trailing line.
fn tokenized_line_segment_is_empty(segment : String) -> Bool {
  guard segment.has_prefix("<span class=\"") &&
    segment.find("\">") is Some(content_start) else {
    return false
  }
  segment[content_start + 2:] == "</span>"
}

///|
/// Deterministic split that retains leading, adjacent, and trailing empty
/// lines. Core `String::split` intentionally drops the final empty item, but
/// here that item is the reviewed tokenizer-shape sentinel.
fn split_tokenized_code_lines(inner : String) -> Array[String] {
  let separator = "<br/>"
  let result : Array[String] = []
  let mut start = 0
  while start <= inner.length() {
    let remainder = inner[start:]
    match remainder.find(separator) {
      Some(relative) => {
        result.push(inner[start:start + relative].to_owned())
        start = start + relative + separator.length()
      }
      None => {
        result.push(inner[start:].to_owned())
        break
      }
    }
  }
  result
}

///|
fn markdown_document_mermaid_theme(
  theme : String,
) -> @browser_markdown.MermaidTheme {
  if theme == "light" {
    Light
  } else {
    Dark
  }
}

///|
fn MarkdownDocumentView::listen(
  self : MarkdownDocumentView,
  target : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_name, listener)
    }),
  )
}

///|
/// The sole post-render choke point. It rebuilds DOM/source associations after
/// every article replacement; later semantic listeners and registries attach
/// here without creating a second parse or a parallel replacement path.
fn MarkdownDocumentView::post_render(self : MarkdownDocumentView) -> Unit {
  self.semantic_dom.dispose()
  let semantic_dom = MarkdownSemanticDomLifetime::empty()
  let children = self.article.get_children()
  for anchor in self.rendered.projection.block_anchors {
    guard anchor.rendered_element_index is Some(element_index) &&
      element_index >= 0 &&
      element_index < children.length() else {
      continue
    }
    let element = children[element_index]
    element.set_attribute(
      "data-markdown-block-anchor",
      anchor.index.to_string(),
    )
    element.set_attribute(
      "data-markdown-source-start",
      anchor.source_range.start.to_string(),
    )
    element.set_attribute(
      "data-markdown-source-end",
      anchor.source_range.end_exclusive.to_string(),
    )
  }
  self.root.set_attribute(
    "data-markdown-projection-generation",
    self.projection_generation.to_string(),
  )
  self.root.set_attribute(
    "data-markdown-source-version",
    self.source_model_version.to_string(),
  )
  for block in self.rendered.projection.code_blocks {
    guard block.is_moonbit_check_fence(self.resource_kind) &&
      self.article.query_selector(
        "[data-markdown-code-block=\"\{block.block_index}\"]",
      )
      is Some(block_element) else {
      continue
    }
    let block_lines : Array[MarkdownSemanticCodeLineDom] = []
    let mut block_is_valid = true
    for line_index, code_line in block.code_lines {
      match
        block_element.query_selector(
          "[data-markdown-code-line=\"\{line_index}\"]",
        ) {
        Some(element) => {
          let dom_text = markdown_semantic_line_text(element)
          if dom_text != code_line.displayed_text ||
            dom_text.length() != code_line.displayed_text.length() {
            block_is_valid = false
          }
          block_lines.push({
            block_index: block.block_index,
            block_source_range: block.block_source_range,
            line_index,
            code_line,
            element,
          })
        }
        None => block_is_valid = false
      }
    }
    if block_is_valid && block_lines.length() == block.code_lines.length() {
      semantic_dom.lines.append(block_lines)
    } else {
      // Keep ordinary tokenized presentation but remove every source-bearing
      // affordance from the mismatched block.
      block_element.remove_attribute("data-markdown-semantic")
      let downgrade_attributes = markdown_semantic_line_downgrade_attributes()
      for line in block_lines {
        for attribute in downgrade_attributes {
          line.element.remove_attribute(attribute)
        }
      }
    }
  }
  self.semantic_dom = semantic_dom
}

///|
/// Every line-level affordance that must disappear when decoded DOM text no
/// longer matches its source projection. Keeping this list centralized makes
/// visual and accessibility additions participate in the same fail-closed
/// downgrade as semantic coordinates.
fn markdown_semantic_line_downgrade_attributes() -> Array[String] {
  [
    "data-markdown-block-index", "data-markdown-code-line", "data-markdown-source-line",
    "data-markdown-source-start", "data-markdown-source-end", "data-markdown-phrase-divider",
    "role", "aria-label",
  ]
}

///|
extern "js" fn markdown_semantic_line_text(element : @rdom.Element) -> String =
  #| (element) => String(element.textContent || "")

///|
/// Replaces the article from one source snapshot. The root, viewport, and
/// overlay mount survive. The returned projection and installed HTML always
/// come from the same parse.
pub fn MarkdownDocumentView::replace_source(
  self : MarkdownDocumentView,
  source : String,
  source_model_version : Int,
) -> Unit {
  guard !self.disposed else { return }
  self.semantic_dom.dispose()
  self.diagram_viewports.dispose()
  self.rendered.dispose.dispose()
  self.source = source
  self.source_model_version = source_model_version
  self.projection_generation += 1
  let (rendered, diagram_viewports) = render_markdown_document_presentation(
    source,
    self.language_id,
    self.base_uri,
    self.resource_kind,
    self.theme,
    self.article,
    self.on_size_changed,
  )
  self.rendered = rendered
  self.diagram_viewports = diagram_viewports
  self.post_render()
  (self.on_size_changed)()
}

///|
/// Theme refresh is a projection replacement, matching source-editor
/// highlighter refresh semantics. Scroll and overlay DOM survive.
pub fn MarkdownDocumentView::apply_theme(
  self : MarkdownDocumentView,
  theme : String,
) -> Unit {
  guard !self.disposed else { return }
  self.theme = theme
  self.root.set_attribute("data-theme", theme)
  self.replace_source(self.source, self.source_model_version)
}

///|
pub fn MarkdownDocumentView::root(self : MarkdownDocumentView) -> @rdom.Element {
  self.root
}

///|
pub fn MarkdownDocumentView::viewport(
  self : MarkdownDocumentView,
) -> @rdom.Element {
  self.viewport
}

///|
fn MarkdownDocumentView::article(self : MarkdownDocumentView) -> @rdom.Element {
  self.article
}

///|
pub fn MarkdownDocumentView::overlay_mount(
  self : MarkdownDocumentView,
) -> @rdom.Element {
  self.overlay_mount
}

///|
pub fn MarkdownDocumentView::projection(
  self : MarkdownDocumentView,
) -> @markdown_core.MarkdownDocumentProjection {
  self.rendered.projection
}

///|
pub fn MarkdownDocumentView::projection_generation(
  self : MarkdownDocumentView,
) -> Int {
  self.projection_generation
}

///|
pub fn MarkdownDocumentView::source_model_version(
  self : MarkdownDocumentView,
) -> Int {
  self.source_model_version
}

///|
pub fn MarkdownDocumentView::language_id(self : MarkdownDocumentView) -> String {
  self.language_id
}

///|
/// Mirrors the Code root's `showUnused` option class without rebuilding the
/// current Markdown projection.
pub fn MarkdownDocumentView::apply_marker_unused_visibility(
  self : MarkdownDocumentView,
  show_unused : Bool,
) -> Unit {
  guard !self.disposed else { return }
  self.root.set_attribute("class", markdown_document_root_class(show_unused))
}

///|
/// Hides exactly the root elements at `hidden_element_indexes` and shows every
/// other rendered root element.
///
/// This is a pure visibility operation over already-rendered nodes: it never
/// re-renders, never rebuilds the projection, and never advances
/// `projection_generation`. That is what preserves the `.mbt.md` semantic-fence
/// contract across folding — the hover bridge resolves a caret through retained
/// per-line boundary maps plus a DOM descendant check, both of which survive a
/// visibility change untouched.
///
/// `display:none` is required rather than `visibility:hidden` or a zero height:
/// only `display:none` removes the subtree from hit testing, so
/// `caretPositionFromPoint` cannot return a node inside hidden content and the
/// bridge's descendant check fails closed. A hidden-but-hit-testable element
/// would produce hovers on text the reader cannot see.
///
/// The view owns no fold policy. Which sections are collapsed, and how that
/// survives a source or theme replacement, belongs to the root Viewer; a
/// replacement resets every element to visible and the root re-applies.
/// Out-of-range indexes are ignored so a stale caller cannot abort a render.
pub fn MarkdownDocumentView::set_hidden_root_elements(
  self : MarkdownDocumentView,
  hidden_element_indexes : Array[Int],
) -> Unit {
  guard !self.disposed else { return }
  let children = self.article.get_children()
  let hidden : Set[Int] = Set([])
  for index in hidden_element_indexes {
    if index >= 0 && index < children.length() {
      hidden.add(index)
    }
  }
  // Visibility rides on a dedicated attribute the stylesheet maps to
  // `display:none`, so the view never owns or clobbers an element's `style`
  // attribute, and no `aria-hidden` bookkeeping is needed: `display:none`
  // already removes the subtree from the accessibility tree.
  for index, child in children {
    if hidden.contains(index) {
      child.set_attribute(markdown_hidden_element_attribute, "true")
    } else if child.has_attribute(markdown_hidden_element_attribute) {
      child.remove_attribute(markdown_hidden_element_attribute)
    }
  }
}

///|
/// The attribute `markdown_document.css` maps to `display:none`. Exclusively
/// owned by `set_hidden_root_elements`, so the renderer's own classes and
/// inline styles are never disturbed.
let markdown_hidden_element_attribute : String = "data-markdown-section-hidden"

///|
/// One heading's fold affordance: which article root element carries the
/// control, which section it toggles, and the state the control displays.
pub(all) struct MarkdownSectionFoldControl {
  heading_element_index : Int
  section_index : Int
  collapsed : Bool
} derive(Eq, Debug)

///|
/// Installs the reader-facing fold toggle on each listed heading and removes
/// stale toggles everywhere else.
///
/// Each control is one real `<button>` inserted as the heading's first child:
/// a single affordance that serves mouse and keyboard alike, unlike the
/// ViewZone chevron/in-content pair, because nothing here lives inside an
/// `aria-hidden` gutter. The button carries `aria-expanded` and an
/// `aria-label`; its chevron is drawn by CSS from `data-collapsed`.
///
/// The view owns only the control DOM. Which sections exist and what state
/// they display belongs to the root Viewer, which re-installs after every
/// projection replacement. Toggle clicks arrive through the handler set by
/// `set_section_fold_toggle_handler`; installation never fires it.
pub fn MarkdownDocumentView::install_section_fold_controls(
  self : MarkdownDocumentView,
  controls : Array[MarkdownSectionFoldControl],
) -> Unit {
  guard !self.disposed else { return }
  let children = self.article.get_children()
  let wanted : Map[Int, MarkdownSectionFoldControl] = Map([])
  for control in controls {
    if control.heading_element_index >= 0 &&
      control.heading_element_index < children.length() {
      wanted[control.heading_element_index] = control
    }
  }
  for index, child in children {
    let existing = child.query_selector(markdown_fold_toggle_selector)
    match wanted.get(index) {
      Some(control) => {
        let button = match existing {
          Some(button) => button
          None => {
            let button = @rdom.document().create_element("button")
            button.set_attribute("type", "button")
            button.set_attribute("class", markdown_fold_toggle_class)
            child
            .as_node()
            .insert_before(
              button.as_node(),
              @js.Nullable::from_option(markdown_first_child(child)),
            )
            button
          }
        }
        button.set_attribute(
          "data-markdown-fold-section",
          control.section_index.to_string(),
        )
        button.set_attribute(
          "data-collapsed",
          if control.collapsed {
            "true"
          } else {
            "false"
          },
        )
        button.set_attribute(
          "aria-expanded",
          if control.collapsed {
            "false"
          } else {
            "true"
          },
        )
        button.set_attribute(
          "aria-label",
          if control.collapsed {
            "Expand section"
          } else {
            "Collapse section"
          },
        )
      }
      None =>
        match existing {
          Some(button) => child.as_node().remove_child(button.as_node())
          None => ()
        }
    }
  }
}

///|
/// Replaces the toggle-click handler. One delegated article listener installed
/// at construction routes every toggle click here, so the handler survives
/// projection replacements without per-button listener bookkeeping.
pub fn MarkdownDocumentView::set_section_fold_toggle_handler(
  self : MarkdownDocumentView,
  handler : (Int) -> Unit,
) -> Unit {
  self.on_section_fold_toggle = handler
}

///|
let markdown_fold_toggle_class : String = "moonbit-viewer-markdown-fold-toggle"

///|
let markdown_fold_toggle_selector : String = ".moonbit-viewer-markdown-fold-toggle"

///|
fn markdown_first_child(element : @rdom.Element) -> @rdom.Node? {
  element.get_children().get(0).map(first => first.as_node())
}

///|
/// Resolves a click to the fold-section index of the toggle it landed on, or
/// `None` for every other click. Buttons live inside headings, so `closest`
/// from the real event target is exact; text selection and link activation in
/// the same heading never reach here.
fn markdown_fold_toggle_section(event : @rdom.Event) -> Int? {
  guard event.target().to_element() is Some(target) else { return None }
  guard target.closest("[data-markdown-fold-section]") is Some(button) else {
    return None
  }
  guard button.get_attribute("data-markdown-fold-section") is Some(raw) else {
    return None
  }
  markdown_parse_section_index(raw)
}

///|
/// Digit-only index parser for the toggle data attribute. Anything else --
/// including an empty string -- is a malformed control and is ignored rather
/// than routed to section 0.
fn markdown_parse_section_index(raw : String) -> Int? {
  guard raw.length() > 0 && raw.length() <= 9 else { return None }
  let value = for unit in raw; value = 0 {
    guard unit >= '0' && unit <= '9' else { return None }
    continue value * 10 + (unit.to_int() - '0'.to_int())
  } nobreak {
    value
  }
  Some(value)
}

///|
/// Snapshot of the current replacement-scoped line registry. The returned
/// array may be reordered by a caller without mutating the view's registry.
pub fn MarkdownDocumentView::semantic_code_lines(
  self : MarkdownDocumentView,
) -> Array[MarkdownSemanticCodeLineDom] {
  self.semantic_dom.lines.copy()
}

///|
/// Installs a delegated semantic-surface listener into the current article
/// generation. Root-owned bridges call this again after a source/theme
/// replacement; the old listener is always removed before old rendered
/// Markdown resources are released.
pub fn MarkdownDocumentView::listen_semantic_dom(
  self : MarkdownDocumentView,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  guard !self.disposed &&
    !self.semantic_dom.disposed &&
    self.semantic_dom.lines.length() > 0 else {
    return
  }
  self.article.add_event_listener(event_name, listener)
  self.semantic_dom.listeners.push(
    @base_common.Disposable::from(() => {
      self.article.remove_event_listener(event_name, listener)
    }),
  )
}

///|
pub fn MarkdownDocumentView::layout(
  self : MarkdownDocumentView,
  width : Double,
  height : Double,
) -> Unit {
  guard !self.disposed else { return }
  @base_browser.set_style_property(self.root, "width", "\{width}px")
  @base_browser.set_style_property(self.root, "height", "\{height}px")
}

///|
pub fn MarkdownDocumentView::scroll_top(self : MarkdownDocumentView) -> Double {
  self.viewport.get_scroll_top()
}

///|
pub fn MarkdownDocumentView::scroll_left(self : MarkdownDocumentView) -> Double {
  self.viewport.get_scroll_left()
}

///|
pub fn MarkdownDocumentView::set_scroll_position(
  self : MarkdownDocumentView,
  scroll_top? : Double,
  scroll_left? : Double,
) -> Unit {
  guard !self.disposed else { return }
  match scroll_top {
    Some(value) => self.viewport.set_scroll_top(value)
    None => ()
  }
  match scroll_left {
    Some(value) => self.viewport.set_scroll_left(value)
    None => ()
  }
}

///|
pub fn MarkdownDocumentView::content_width(
  self : MarkdownDocumentView,
) -> Double {
  self.article.get_scroll_width()
}

///|
pub fn MarkdownDocumentView::content_height(
  self : MarkdownDocumentView,
) -> Double {
  self.article.get_scroll_height()
}

///|
pub fn MarkdownDocumentView::scroll_width(
  self : MarkdownDocumentView,
) -> Double {
  self.viewport.get_scroll_width()
}

///|
pub fn MarkdownDocumentView::scroll_height(
  self : MarkdownDocumentView,
) -> Double {
  self.viewport.get_scroll_height()
}

///|
fn MarkdownDocumentView::element_for_source_offset(
  self : MarkdownDocumentView,
  source_offset : Int,
) -> @rdom.Element? {
  for block in self.rendered.projection.code_blocks {
    if block.block_source_range.contains(source_offset) ||
      source_offset == block.block_source_range.end_exclusive {
      match
        self.article.query_selector(
          "[data-markdown-code-block=\"\{block.block_index}\"]",
        ) {
        Some(element) => return Some(element)
        None => ()
      }
    }
  }
  let children = self.article.get_children()
  for anchor in self.rendered.projection.block_anchors {
    if !(anchor.source_range.contains(source_offset) ||
      source_offset == anchor.source_range.end_exclusive) {
      continue
    }
    match anchor.rendered_element_index {
      Some(index) if index >= 0 && index < children.length() =>
        return Some(children[index])
      _ => ()
    }
  }
  let mut nearest_before : @rdom.Element? = None
  let mut first_mapped : @rdom.Element? = None
  for anchor in self.rendered.projection.block_anchors {
    guard anchor.rendered_element_index is Some(index) &&
      index >= 0 &&
      index < children.length() else {
      continue
    }
    let element = children[index]
    if first_mapped is None {
      first_mapped = Some(element)
    }
    if anchor.source_range.start <= source_offset {
      nearest_before = Some(element)
    } else {
      break
    }
  }
  match nearest_before {
    Some(element) => Some(element)
    None => first_mapped
  }
}

///|
/// Scrolls a TOC target by changing only the Markdown viewport. Avoid
/// `scrollIntoView` here because older WebKitGTK versions may also move the
/// surrounding desktop page. The navigation callback runs first so folded
/// ancestors are expanded before the target rectangle is measured.
fn MarkdownDocumentView::scroll_toc_entry_into_view(
  self : MarkdownDocumentView,
  source_offset : Int,
) -> Unit {
  guard !self.disposed &&
    self.element_for_source_offset(source_offset) is Some(element) else {
    return
  }
  let element_top = element.get_bounding_client_rect().get_top()
  let toc_bottom = self.toc_nav.get_bounding_client_rect().get_bottom()
  self.viewport.set_scroll_top(
    self.viewport.get_scroll_top() + element_top - toc_bottom,
  )
}

///|
/// Reveals the nearest retained source anchor. Horizontal source columns do
/// not synthesize code-editor scrolling; browser layout owns the native block.
/// The scroll is applied to the Markdown viewport alone: `scrollIntoView`
/// would also move every scrollable ancestor (older WebKitGTK builds move the
/// surrounding desktop page), so only the viewport's `scrollTop` changes.
/// The overlaid TOC panel, when visible, acts as the top padding for
/// `start`/`nearest` landing, mirroring the viewport's `scroll-padding-top`.
pub fn MarkdownDocumentView::reveal_source_offset(
  self : MarkdownDocumentView,
  source_offset : Int,
  vertical_alignment : String,
) -> Unit {
  guard !self.disposed &&
    self.element_for_source_offset(source_offset) is Some(element) else {
    return
  }
  let element_rect = element.get_bounding_client_rect()
  let viewport_rect = self.viewport.get_bounding_client_rect()
  let viewport_top = viewport_rect.get_top()
  let viewport_bottom = viewport_rect.get_bottom()
  // The panel is `display: none` unless the document has at least three
  // sections; a hidden panel measures a zero rect, contributing no offset.
  let panel_bottom = self.toc_nav.get_bounding_client_rect().get_bottom()
  let padded_top = if panel_bottom > viewport_top {
    panel_bottom
  } else {
    viewport_top
  }
  let delta = match vertical_alignment {
    "center" =>
      element_rect.get_top() +
      element_rect.get_height() / 2.0 -
      (viewport_top + viewport_rect.get_height() / 2.0)
    "end" => element_rect.get_bottom() - viewport_bottom
    "nearest" =>
      if element_rect.get_top() < padded_top {
        element_rect.get_top() - padded_top
      } else if element_rect.get_bottom() > viewport_bottom {
        element_rect.get_bottom() - viewport_bottom
      } else {
        0.0
      }
    _ => element_rect.get_top() - padded_top
  }
  self.viewport.set_scroll_top(self.viewport.get_scroll_top() + delta)
}

///|
/// Original-source anchors whose rendered root intersects the viewport.
pub fn MarkdownDocumentView::visible_source_ranges(
  self : MarkdownDocumentView,
) -> Array[@base_common.OffsetRange] {
  guard !self.disposed else { return [] }
  let viewport_rect = self.viewport.get_bounding_client_rect()
  let viewport_top = viewport_rect.get_top()
  let viewport_bottom = viewport_rect.get_bottom()
  let children = self.article.get_children()
  let result : Array[@base_common.OffsetRange] = []
  for anchor in self.rendered.projection.block_anchors {
    guard anchor.rendered_element_index is Some(index) &&
      index >= 0 &&
      index < children.length() else {
      continue
    }
    let rect = children[index].get_bounding_client_rect()
    if rect.get_bottom() > viewport_top && rect.get_top() < viewport_bottom {
      result.push(anchor.source_range)
    }
  }
  result
}

///|
pub fn MarkdownDocumentView::has_rendered_source_anchors(
  self : MarkdownDocumentView,
) -> Bool {
  let child_count = self.article.get_children().length()
  self.rendered.projection.block_anchors.any(anchor => {
    match anchor.rendered_element_index {
      Some(index) => index >= 0 && index < child_count
      None => false
    }
  })
}

///|
pub fn MarkdownDocumentView::dispose(self : MarkdownDocumentView) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.projection_generation += 1
  while self.listeners.length() > 0 {
    let listener = self.listeners.remove(self.listeners.length() - 1)
    listener.dispose()
  }
  self.semantic_dom.dispose()
  self.diagram_viewports.dispose()
  self.rendered.dispose.dispose()
}

///|
/// One row of the pinned table-of-contents bar.
pub(all) struct MarkdownTocBarEntry {
  depth : Int
  text : String
  source_offset : Int
} derive(Eq, Debug)

///|
/// Replaces the TOC bar's rows and the navigation handler.
///
/// The bar renders only for a document with at least three sections -- an
/// outline of one or two headings is noise -- and starts collapsed to one
/// summary row. Row clicks arrive as the entry's heading source offset, the
/// same coordinate `reveal_source_offset` and the fold seam use; the root
/// Viewer owns what navigation means (expand ancestors, then reveal).
pub fn MarkdownDocumentView::set_toc_entries(
  self : MarkdownDocumentView,
  entries : Array[MarkdownTocBarEntry],
  on_navigate : (Int) -> Unit,
) -> Unit {
  guard !self.disposed else { return }
  self.on_toc_navigate = on_navigate
  let document = @rdom.document()
  // Re-read the first child every pass: the underlying collection is live in
  // a real browser, so removing while iterating a snapshot hands the DOM an
  // undefined mid-loop.
  while self.toc_list.get_children() is [stale, ..] {
    self.toc_list.as_node().remove_child(stale.as_node())
  }
  for entry in entries {
    let item = document.create_element("li")
    let row = document.create_element("button")
    row.set_attribute("type", "button")
    row.set_attribute("class", "moonbit-viewer-markdown-toc-row")
    row.set_attribute("data-toc-offset", entry.source_offset.to_string())
    row.set_attribute("data-toc-depth", entry.depth.to_string())
    row.set_attribute(
      "style",
      "padding-left:\{0.75 * entry.depth.to_double()}em",
    )
    row.append_child(document.create_text_node(entry.text).as_node())
    item.append_child(row.as_node())
    self.toc_list.append_child(item.as_node())
  }
  if entries.length() >= 3 {
    self.toc_nav.set_attribute("data-toc-visible", "true")
    self.toc_toggle.set_attribute(
      "aria-label",
      "Contents, \{entries.length()} sections",
    )
    // textContent assignment already replaces every child.
    self.toc_toggle.set_property(
      "textContent",
      @js.Value::cast_from("Contents \u{00b7} \{entries.length()}"),
    )
  } else {
    self.toc_nav.set_attribute("data-toc-visible", "false")
  }
}

///|
pub extend MarkdownSectionFoldControl with Debug::{to_repr}

///|
pub extend MarkdownSectionFoldControl with Eq::{equal, not_equal}

///|
pub extend MarkdownTocBarEntry with Debug::{to_repr}

///|
pub extend MarkdownTocBarEntry with Eq::{equal, not_equal}
