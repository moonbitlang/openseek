///|
/// The stable DOM retained by one whole-line Markdown-comment ViewZone.
/// `outer` is the caller-owned ViewZone node; `content` is the auto-height
/// ResizeObserver target. `full` and `preview` are independent shared-Markdown
/// targets so folding never reparses or mutates the complete rendered body;
/// `source` is the lazy target for tokenized original model lines; it remains
/// empty until the per-block rendered/source switch first selects source.
/// `margin` is the caller-owned margin ViewZone node: ViewZones keeps its
/// top/height synced with `outer`, and `margin_toggle` sits in the
/// line-decorations lane so the documentation fold control lines up with the
/// code-folding chevrons. The whole margin plane is `aria-hidden` (Monaco
/// parity), so that chevron stays mouse-only while `toggle` carries keyboard
/// and screen-reader access from inside the exposed content zone.
pub struct MarkdownCommentDom {
  outer : @rdom.Element
  priv content : @rdom.Element
  full : @rdom.Element
  preview : @rdom.Element
  source : @rdom.Element
  priv source_toggle : @rdom.Element
  priv toggle : @rdom.Element
  priv toggle_icon : @rdom.Element
  margin : @rdom.Element
  priv margin_toggle : @rdom.Element
}

///|
/// Creates the required outer/content shape for one normalized half-open line
/// range. Projection and ViewZone registration remain root responsibilities.
pub fn MarkdownCommentDom::MarkdownCommentDom(
  start_line_number : Int,
  end_line_number_exclusive : Int,
) -> MarkdownCommentDom {
  let document = @rdom.document()
  let outer = document.create_element("div")
  outer.set_attribute("class", "moonbit-viewer-markdown-comment")
  outer.set_attribute("data-start-line", start_line_number.to_string())
  outer.set_attribute("data-end-line", end_line_number_exclusive.to_string())
  outer.set_attribute("data-documentation-foldable", "false")
  outer.set_attribute("data-documentation-expanded", "true")
  outer.set_attribute("data-source-visible", "false")
  let content = document.create_element("div")
  content.set_attribute("class", "moonbit-viewer-markdown-comment-content")
  let full = document.create_element("div")
  full.set_attribute(
    "class", "moonbit-viewer-markdown-comment-body moonbit-viewer-markdown-comment-full",
  )
  let preview = document.create_element("div")
  preview.set_attribute(
    "class", "moonbit-viewer-markdown-comment-body moonbit-viewer-markdown-comment-preview",
  )
  let source = document.create_element("div")
  source.set_attribute(
    "class", "moonbit-viewer-markdown-comment-body moonbit-viewer-markdown-comment-source",
  )
  let source_toggle = document.create_element("button")
  source_toggle.set_attribute(
    "class", "moonbit-viewer-markdown-comment-source-toggle",
  )
  source_toggle.set_attribute("type", "button")
  source_toggle.set_attribute("aria-pressed", "false")
  source_toggle.set_attribute("aria-label", "Original source")
  source_toggle.set_attribute("title", "Show original source")
  // A textual code mark remains legible if the optional codicon font is not
  // installed by an embedder.
  source_toggle.set_inner_html("{ }")
  let toggle = document.create_element("button")
  toggle.set_attribute("class", "moonbit-viewer-markdown-comment-toggle")
  toggle.set_attribute("type", "button")
  toggle.set_attribute("hidden", "")
  toggle.set_attribute("aria-hidden", "true")
  toggle.set_attribute("tabindex", "-1")
  let toggle_icon = document.create_element("span")
  toggle_icon.set_attribute("class", "codicon codicon-chevron-right")
  toggle_icon.set_attribute("aria-hidden", "true")
  toggle.append_child(toggle_icon.as_node())
  let margin = document.create_element("div")
  margin.set_attribute("class", "moonbit-viewer-markdown-comment-margin")
  margin.set_attribute("data-source-visible", "false")
  let margin_toggle = document.create_element("div")
  margin_toggle.set_attribute(
    "class",
    markdown_comment_margin_toggle_class(expanded=false),
  )
  margin_toggle.set_attribute("hidden", "")
  margin.append_child(margin_toggle.as_node())
  content.append_child(full.as_node())
  content.append_child(preview.as_node())
  content.append_child(source.as_node())
  outer.append_child(source_toggle.as_node())
  outer.append_child(toggle.as_node())
  outer.append_child(content.as_node())
  {
    outer,
    content,
    full,
    preview,
    source,
    source_toggle,
    toggle,
    toggle_icon,
    margin,
    margin_toggle,
  }
}

///|
/// Installs the independent rendered/source switch for this block. The caller
/// retains `source_visible` across same-range source replacement and owns the
/// lazily materialized source target. Documentation folding remains unchanged
/// in the background, so returning to the rendered body restores its prior
/// fold state.
pub fn MarkdownCommentDom::enable_source_toggle(
  self : MarkdownCommentDom,
  source_visible : Ref[Bool],
  on_did_toggle : () -> Unit,
) -> @base_common.Disposable {
  let apply_state = () => {
    let visible = source_visible.val
    let label = if visible {
      "Show rendered documentation"
    } else {
      "Show original source"
    }
    self.outer.set_attribute(
      "data-source-visible",
      if visible {
        "true"
      } else {
        "false"
      },
    )
    self.margin.set_attribute(
      "data-source-visible",
      if visible {
        "true"
      } else {
        "false"
      },
    )
    self.source_toggle.set_attribute(
      "aria-pressed",
      if visible {
        "true"
      } else {
        "false"
      },
    )
    self.source_toggle.set_attribute("title", label)
  }
  apply_state()
  let stop_mouse_down : @rdom.Listener = event => event.stop_propagation()
  let toggle_source : @rdom.Listener = event => {
    event.prevent_default()
    event.stop_propagation()
    source_visible.val = !source_visible.val
    apply_state()
    on_did_toggle()
  }
  self.source_toggle.add_event_listener("mousedown", stop_mouse_down)
  self.source_toggle.add_event_listener("click", toggle_source)
  @base_common.Disposable::from(() => {
    self.source_toggle.remove_event_listener("mousedown", stop_mouse_down)
    self.source_toggle.remove_event_listener("click", toggle_source)
  })
}

///|
/// The gutter chevron reuses the code-folding margin icons (`.cldr` +
/// `codicon-folding-*`) so both fold controls render identically in the
/// line-decorations lane.
fn markdown_comment_margin_toggle_class(expanded~ : Bool) -> String {
  if expanded {
    "moonbit-viewer-markdown-comment-margin-toggle cldr codicon codicon-folding-expanded"
  } else {
    "moonbit-viewer-markdown-comment-margin-toggle cldr codicon codicon-folding-collapsed"
  }
}

///|
/// Makes this documentation body collapsible without owning either Markdown
/// renderer. The caller retains `expanded` across same-key body replacement;
/// newly mounted blocks pass a fresh `false` ref. The returned lifetime removes
/// every listener before the caller replaces or removes the DOM.
pub fn MarkdownCommentDom::enable_folding(
  self : MarkdownCommentDom,
  expanded : Ref[Bool],
  on_did_toggle : () -> Unit,
) -> @base_common.Disposable {
  self.outer.set_attribute("data-documentation-foldable", "true")
  self.toggle.remove_attribute("hidden")
  self.toggle.remove_attribute("aria-hidden")
  self.toggle.remove_attribute("tabindex")
  self.margin_toggle.remove_attribute("hidden")
  let apply_state = () => {
    let is_expanded = expanded.val
    let label = if is_expanded {
      "Collapse API documentation"
    } else {
      "Expand API documentation"
    }
    self.outer.set_attribute(
      "data-documentation-expanded",
      if is_expanded {
        "true"
      } else {
        "false"
      },
    )
    self.toggle.set_attribute(
      "aria-expanded",
      if is_expanded {
        "true"
      } else {
        "false"
      },
    )
    self.toggle.set_attribute("aria-label", label)
    self.toggle.set_attribute("title", label)
    self.toggle_icon.set_attribute(
      "class",
      if is_expanded {
        "codicon codicon-chevron-down"
      } else {
        "codicon codicon-chevron-right"
      },
    )
    self.margin_toggle.set_attribute(
      "class",
      markdown_comment_margin_toggle_class(expanded=is_expanded),
    )
    self.margin_toggle.set_attribute("title", label)
  }
  apply_state()
  let stop_mouse_down : @rdom.Listener = event => event.stop_propagation()
  let toggle_documentation : @rdom.Listener = event => {
    event.prevent_default()
    event.stop_propagation()
    expanded.val = !expanded.val
    apply_state()
    on_did_toggle()
  }
  self.toggle.add_event_listener("mousedown", stop_mouse_down)
  self.toggle.add_event_listener("click", toggle_documentation)
  self.margin_toggle.add_event_listener("mousedown", stop_mouse_down)
  self.margin_toggle.add_event_listener("click", toggle_documentation)
  @base_common.Disposable::from(() => {
    self.toggle.remove_event_listener("mousedown", stop_mouse_down)
    self.toggle.remove_event_listener("click", toggle_documentation)
    self.margin_toggle.remove_event_listener("mousedown", stop_mouse_down)
    self.margin_toggle.remove_event_listener("click", toggle_documentation)
  })
}

///|
/// Restores the ordinary full-body presentation for a one-line or
/// separator-only block. Stale preview children may remain renderer-owned in
/// their hidden target until the entry is replaced or disposed.
pub fn MarkdownCommentDom::disable_folding(self : MarkdownCommentDom) -> Unit {
  self.outer.set_attribute("data-documentation-foldable", "false")
  self.outer.set_attribute("data-documentation-expanded", "true")
  self.toggle.set_attribute("hidden", "")
  self.toggle.set_attribute("aria-hidden", "true")
  self.toggle.set_attribute("tabindex", "-1")
  self.toggle.remove_attribute("aria-expanded")
  self.toggle.remove_attribute("aria-label")
  self.toggle.remove_attribute("title")
  self.margin_toggle.set_attribute("hidden", "")
  self.margin_toggle.remove_attribute("title")
}

///|
/// Pins the caller-owned ViewZone node to the visible content viewport. The
/// ordinary ViewZone write performed by `add_zone` deliberately uses the
/// model's horizontal scroll plane; this contribution-specific write runs
/// immediately afterwards and consumes geometry published by ViewLines.
pub fn MarkdownCommentDom::pin_to_content_viewport(
  self : MarkdownCommentDom,
) -> Unit {
  @base_browser.set_style_property(
    self.outer,
    "left",
    "var(--moonbit-viewer-rendered-scroll-left, 0px)",
  )
  @base_browser.set_style_property(
    self.outer,
    "width",
    "var(--moonbit-viewer-visible-content-width, 0px)",
  )
}

///|
/// Pins the gutter chevron to the rendered line-decorations lane — the
/// configured `lineDecorationsWidth` plus the folding-control reserve. The
/// lane is right-aligned inside the margin ViewZone node, so this width keeps
/// the chevron centered on the same column as the code-folding icons. The
/// stylesheet default matches the default 10px + 16px reserve; the caller
/// reapplies the live width whenever runtime options change that reserve.
pub fn MarkdownCommentDom::set_margin_fold_lane_width(
  self : MarkdownCommentDom,
  width_px : Int,
) -> Unit {
  @base_browser.set_style_property(self.margin_toggle, "width", "\{width_px}px")
}

///|
/// Opts this caller-owned zone into the accessibility tree after ViewZones has
/// applied its default per-zone `aria-hidden`. The shared container remains a
/// presentation node; unrelated zones retain their hidden default.
pub fn MarkdownCommentDom::expose_accessible_content(
  self : MarkdownCommentDom,
) -> Unit {
  self.outer.remove_attribute("aria-hidden")
}

///|
/// One zone's coalesced measurement request inside a
/// `MarkdownCommentMeasureBatch`.
priv struct MarkdownCommentMeasureEntry {
  dom : MarkdownCommentDom
  on_height_changed : (Int) -> Unit
  mut last_height : Int
  mut force_hidden : Bool
  mut queued : Bool
  mut disposed : Bool
}

///|
/// Coalesces every comment zone's size measurement of one owner into a
/// single animation-frame pass. A pass first reads every directly measurable
/// content height, then lays out all still-hidden zones invisibly at once,
/// reads their heights, restores their styles, and only then reports the
/// changed heights. Grouping the DOM writes ahead of the reads keeps the
/// browser at a constant number of forced layouts per pass instead of one
/// per zone; measuring each zone on its own is what made opening a large
/// MoonBit file stall for seconds. `on_pass_complete` runs once after a
/// pass's height callbacks so the owner can publish every changed zone in one
/// ViewZone transaction.
struct MarkdownCommentMeasureBatch {
  mut pending : Array[MarkdownCommentMeasureEntry]
  mut frame : @base_common.Disposable?
  mut frame_scheduled : Bool
  mut in_pass : Bool
  mut disposed : Bool
  on_pass_complete : () -> Unit
}

///|
/// Creates an empty batch owned by one root contribution.
pub fn MarkdownCommentMeasureBatch::MarkdownCommentMeasureBatch(
  on_pass_complete~ : () -> Unit,
) -> MarkdownCommentMeasureBatch {
  {
    pending: [],
    frame: None,
    frame_scheduled: false,
    in_pass: false,
    disposed: false,
    on_pass_complete,
  }
}

///|
/// Whether a measurement pass is reporting heights right now. Height callbacks
/// use it to defer their ViewZone relayout to `on_pass_complete`.
pub fn MarkdownCommentMeasureBatch::in_pass(
  self : MarkdownCommentMeasureBatch,
) -> Bool {
  self.in_pass
}

///|
/// Cancels queued frame work and makes every later request inert. The
/// per-zone observer lifetimes remain caller-owned.
pub fn MarkdownCommentMeasureBatch::dispose(
  self : MarkdownCommentMeasureBatch,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  match self.frame {
    Some(registration) => registration.dispose()
    None => ()
  }
  self.frame = None
  self.frame_scheduled = false
  for entry in self.pending {
    entry.queued = false
  }
  self.pending = []
}

///|
fn MarkdownCommentMeasureBatch::enqueue(
  self : MarkdownCommentMeasureBatch,
  entry : MarkdownCommentMeasureEntry,
  force_hidden : Bool,
) -> Unit {
  if self.disposed || entry.disposed {
    return
  }
  entry.force_hidden = entry.force_hidden || force_hidden
  if entry.queued {
    return
  }
  entry.queued = true
  self.pending.push(entry)
  if self.frame_scheduled {
    return
  }
  self.frame_scheduled = true
  let registration = @base_browser.schedule_at_next_animation_frame(() => {
    self.run_pass()
  })
  // Native requestAnimationFrame is asynchronous, but retaining this branch
  // makes the owner correct under a synchronous test/browser shim too.
  if self.frame_scheduled {
    self.frame = Some(registration)
  } else {
    registration.dispose()
  }
}

///|
/// One frame's measurement pass: direct reads, then one invisible layout of
/// every hidden zone, then the reports.
fn MarkdownCommentMeasureBatch::run_pass(
  self : MarkdownCommentMeasureBatch,
) -> Unit {
  self.frame_scheduled = false
  self.frame = None
  if self.disposed {
    return
  }
  let entries = self.pending
  self.pending = []
  // Phase 1: direct reads. Visible content reports immediately; the first
  // read may force one layout, later reads reuse it.
  let hidden : Array[MarkdownCommentMeasureEntry] = []
  let measured : Array[(MarkdownCommentMeasureEntry, Int)] = []
  for entry in entries {
    entry.queued = false
    if entry.disposed || !@base_browser.element_is_connected(entry.dom.content) {
      continue
    }
    let allow_hidden = entry.force_hidden || entry.last_height == 0
    entry.force_hidden = false
    let direct = @base_browser.element_offset_height(entry.dom.content).to_int()
    if direct > 0 || !allow_hidden {
      measured.push((entry, direct))
    } else {
      hidden.push(entry)
    }
  }
  // Phase 2: writes. Every hidden zone is laid out invisibly at once.
  let saved = hidden.map(entry => {
    begin_hidden_markdown_comment_measure(entry.dom.outer)
  })
  // Phase 3: reads, all sharing the one layout the first read forces.
  for entry in hidden {
    measured.push(
      (
        entry,
        read_hidden_markdown_comment_height(entry.dom.outer, entry.dom.content),
      ),
    )
  }
  // Phase 4: restore every touched inline style and priority.
  for index, entry in hidden {
    end_hidden_markdown_comment_measure(entry.dom.outer, saved[index])
  }
  // Phase 5: report. A callback may dispose a later entry, so re-check each.
  self.in_pass = true
  defer {
    self.in_pass = false
  }
  for pair in measured {
    let (entry, height) = pair
    if entry.disposed || height <= 0 || height == entry.last_height {
      continue
    }
    entry.last_height = height
    (entry.on_height_changed)(height)
  }
  (self.on_pass_complete)()
}

///|
/// Observes the inner Markdown content and reports its first/changed positive
/// integer height through `batch`, after one shared animation-frame boundary.
/// Explicit requests cover renderer replacement, image load, and model-scoped
/// viewport-width changes while a zone is offscreen. The root callback owns
/// generation and zone-id stale checks before relayout.
pub fn MarkdownCommentDom::observe_size(
  self : MarkdownCommentDom,
  batch : MarkdownCommentMeasureBatch,
  on_height_changed : (Int) -> Unit,
) -> MarkdownCommentSizeObserver {
  let entry : MarkdownCommentMeasureEntry = {
    dom: self,
    on_height_changed,
    last_height: 0,
    force_hidden: false,
    queued: false,
    disposed: false,
  }
  let observer = @base_browser.observe_element_resize(self.content, () => {
    batch.enqueue(entry, false)
  })
  let lifetime = @base_common.Disposable::from(() => {
    if entry.disposed {
      return
    }
    entry.disposed = true
    match observer {
      Some(observer) => observer.dispose()
      None => ()
    }
  })
  { request_measure_: () => batch.enqueue(entry, true), lifetime, }
}

///|
/// A disposable size-observation lifetime with an explicit invalidation seam
/// for content replacement and image-load callbacks owned by the renderer.
struct MarkdownCommentSizeObserver {
  request_measure_ : () -> Unit
  lifetime : @base_common.Disposable
}

///|
pub fn MarkdownCommentSizeObserver::request_measure(
  self : MarkdownCommentSizeObserver,
) -> Unit {
  (self.request_measure_)()
}

///|
pub fn MarkdownCommentSizeObserver::dispose(
  self : MarkdownCommentSizeObserver,
) -> Unit {
  self.lifetime.dispose()
}

///|
/// One model-scoped observer for the editor content viewport. Width transitions
/// are deduplicated here; zero is remembered but not published so restoring a
/// previously equal positive width still invalidates hidden comment heights.
pub fn MarkdownCommentDom::observe_viewport_width(
  self : MarkdownCommentDom,
  on_width_changed : () -> Unit,
) -> MarkdownCommentViewportObserver {
  let disposed = Ref(false)
  let lifetime = match markdown_comment_content_viewport(self.outer) {
    Some(viewport) => {
      let last_width = Ref(
        @base_browser.element_client_width(viewport).to_int(),
      )
      let observer = @base_browser.observe_element_resize(viewport, () => {
        if disposed.val {
          return
        }
        let width = @base_browser.element_client_width(viewport).to_int()
        if width == last_width.val {
          return
        }
        last_width.val = width
        if width > 0 {
          on_width_changed()
        }
      })
      @base_common.Disposable::from(() => {
        disposed.val = true
        match observer {
          Some(observer) => observer.dispose()
          None => ()
        }
      })
    }
    None => @base_common.Disposable::from(() => disposed.val = true)
  }
  { lifetime, }
}

///|
struct MarkdownCommentViewportObserver {
  lifetime : @base_common.Disposable
}

///|
pub fn MarkdownCommentViewportObserver::dispose(
  self : MarkdownCommentViewportObserver,
) -> Unit {
  self.lifetime.dispose()
}

///|
fn markdown_comment_content_viewport(element : @rdom.Element) -> @rdom.Element? {
  if markdown_comment_element_has_class(element, "editor-scrollable") {
    return Some(element)
  }
  match element.get_parent_node().to_option() {
    Some(parent) =>
      match parent.to_element() {
        Some(parent) => markdown_comment_content_viewport(parent)
        None => None
      }
    None => None
  }
}

///|
fn markdown_comment_element_has_class(
  element : @rdom.Element,
  class_name : String,
) -> Bool {
  for token in element.get_attribute("class").unwrap_or("").split(" ") {
    if token == class_name {
      return true
    }
  }
  false
}

///|
priv struct MarkdownCommentSavedStyle {
  name : String
  value : String
  priority : String
}

///|
fn save_markdown_comment_style(
  element : @rdom.Element,
  name : String,
) -> MarkdownCommentSavedStyle {
  {
    name,
    value: @base_browser.element_style_value(element, name),
    priority: @base_browser.element_style_priority(element, name),
  }
}

///|
fn restore_markdown_comment_style(
  element : @rdom.Element,
  saved : MarkdownCommentSavedStyle,
) -> Unit {
  if saved.value == "" {
    @base_browser.remove_style_property(element, saved.name)
  } else {
    @base_browser.set_style_property_with_priority(
      element,
      saved.name,
      saved.value,
      saved.priority,
    )
  }
}

///|
/// Prepares a connected `display:none` ViewZone for an invisible layout: the
/// caller-owned outer node is shown hidden at `top: 0` without replacing its
/// viewport-pinned `left` or `width`. Returns every touched inline declaration
/// and priority for `end_hidden_markdown_comment_measure`. A later zero-size
/// ResizeObserver notification is not allowed to repeat this hidden path unless
/// the shared viewport observer or renderer explicitly invalidated it.
fn begin_hidden_markdown_comment_measure(
  outer : @rdom.Element,
) -> Array[MarkdownCommentSavedStyle] {
  let saved = ["display", "visibility", "pointer-events", "height", "top"].map(name => {
    save_markdown_comment_style(outer, name)
  })
  @base_browser.set_style_property_with_priority(
    outer, "display", "block", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "visibility", "hidden", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "pointer-events", "none", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "height", "auto", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "top", "0px", "important",
  )
  saved
}

///|
/// Reads the invisibly laid out content height, or zero while the zone has no
/// usable width yet.
fn read_hidden_markdown_comment_height(
  outer : @rdom.Element,
  content : @rdom.Element,
) -> Int {
  let rect_width = outer.get_bounding_client_rect().get_width()
  let width = if rect_width > 0.0 {
    rect_width
  } else {
    @base_browser.element_offset_width(outer)
  }
  if width <= 0.0 {
    return 0
  }
  @base_browser.element_offset_height(content).to_int()
}

///|
/// Restores the declarations captured by `begin_hidden_markdown_comment_measure`.
fn end_hidden_markdown_comment_measure(
  outer : @rdom.Element,
  saved : Array[MarkdownCommentSavedStyle],
) -> Unit {
  for declaration in saved {
    restore_markdown_comment_style(outer, declaration)
  }
}
