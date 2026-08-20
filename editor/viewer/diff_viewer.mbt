// Monaco's standalone diff-editor composition: two normal Viewer instances
// coordinated by line-level diff state. Side-by-side mode shows both children;
// unified mode keeps the modified child as the interactive editor and projects
// deleted original lines into it as tokenized ViewZones. The child Viewers
// deliberately remain ordinary editors so every model-scoped contribution
// (tokenization, hover, Definition/Peek, selection, feedback) follows the
// existing Viewer path.
//
// Remaining exclusions are explicit: no moved blocks, true-inline single-line
// rendering, revert actions, unchanged-region collapsing, or overview ruler.
// Soft wrapping and folding are disabled in the child panes because
// fixed-height logical lines are the invariant behind both ViewZone layouts.

///|
/// The presentation selected for one DiffViewer. Both modes retain the same
/// two models and ordinary child Viewers; changing this value is a rendering
/// operation, not a model swap.
pub(all) enum DiffEditorRenderMode {
  SideBySide
  Unified
} derive(Eq, Debug)

///|
/// A model-line viewport anchor retained while coordinator-owned ViewZones are
/// rebuilt. Content-space line tops change between render modes, while this
/// line's pixel position relative to the viewport must not.
priv struct DiffViewportAnchor {
  line_number : Int
  viewport_offset : Double
}

///|
/// The two caller-owned text models displayed by a DiffViewer. Like Monaco's
/// `IDiffEditorModel`, the comparison owns neither model and never disposes
/// them.
pub(all) struct DiffEditorModel {
  original : @model.TextModel
  modified : @model.TextModel
}

///|
pub fn DiffEditorModel::DiffEditorModel(
  original : @model.TextModel,
  modified : @model.TextModel,
) -> DiffEditorModel {
  { original, modified }
}

///|
/// The comparison strategy used by a DiffViewer. `StandardDiff` is the
/// editor's general-purpose line/character algorithm. The MoonBit-aware modes
/// are offered only when the modified model's URI ends in `.mbt`.
pub(all) enum DiffViewerMode {
  StandardDiff
  TokenDiff
  TreeDiff
} derive(Eq)

///|
/// A switchable diff surface composed from two ordinary Viewer instances.
/// The caller owns `host` and must keep it stable and otherwise child-free.
struct DiffViewer {
  host : @rdom.Element
  root : @rdom.Element
  original_host : @rdom.Element
  modified_host : @rdom.Element
  toolbar : @rdom.Element
  mode_status : @rdom.Element
  mode_buttons : Array[(DiffViewerMode, @rdom.Element)]
  ignore_comments_button : @rdom.Element
  original_viewer : Viewer
  modified_viewer : Viewer
  owned_services : ViewerServices?
  mut render_mode : DiffEditorRenderMode
  mut resize_observer : @base_common.Disposable?
  mut viewport_restore_frame : @base_common.Disposable?
  scroll_disposables : Array[@base_common.Disposable]
  model_disposables : Array[@base_common.Disposable]
  mut original_decoration_ids : Array[String]
  mut modified_decoration_ids : Array[String]
  mut original_zone_ids : Array[String]
  mut modified_zone_ids : Array[String]
  mut diff_mode : DiffViewerMode
  mut ignore_comments : Bool
  mut disposed : Bool
}

///|
/// Create an empty comparison in a stable host. An explicit service bundle is
/// borrowed and shared by both panes; when omitted, one bundle is created and
/// owned by the DiffViewer. Hosts can keep original-revision semantic requests
/// inert by giving that model a URI outside their live-document selectors. The
/// comparison observes its outer host because either child may be constructed
/// while the caller keeps that host at `display: none`; revealing or resizing
/// the host then remeasures both ordinary Viewer panes automatically.
pub fn DiffViewer::create(
  host : @rdom.Element,
  services? : ViewerServices,
  options? : ViewerOptions = ViewerOptions::default(),
  render_mode? : DiffEditorRenderMode = SideBySide,
) -> DiffViewer {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-diff-editor")
  root.set_attribute("role", "region")
  root.set_attribute("aria-label", "File comparison")
  let toolbar = document.create_element("div")
  toolbar.set_attribute("class", "moonbit-diff-editor-toolbar")
  toolbar.set_attribute("role", "toolbar")
  toolbar.set_attribute("aria-label", "Diff mode")
  toolbar.set_attribute("hidden", "")
  let toolbar_label = document.create_element("span")
  toolbar_label.set_attribute("class", "moonbit-diff-editor-toolbar-label")
  toolbar_label.set_inner_html("Diff")
  toolbar.append_child(toolbar_label.as_node())
  let mode_group = document.create_element("div")
  mode_group.set_attribute("class", "moonbit-diff-editor-mode-group")
  mode_group.set_attribute("role", "group")
  mode_group.set_attribute("aria-label", "Comparison algorithm")
  let mode_buttons : Array[(DiffViewerMode, @rdom.Element)] = []
  for mode in [StandardDiff, TokenDiff, TreeDiff] {
    let button = document.create_element("button")
    button.set_attribute("type", "button")
    button.set_attribute("class", "moonbit-diff-editor-mode")
    button.set_attribute("data-diff-mode", mode.attribute_name())
    button.set_attribute("aria-label", mode.accessible_label())
    button.set_attribute("title", mode.title())
    button.set_attribute("aria-pressed", "false")
    button.set_inner_html(mode.visible_label())
    mode_group.append_child(button.as_node())
    mode_buttons.push((mode, button))
  }
  toolbar.append_child(mode_group.as_node())
  let ignore_comments_button = document.create_element("button")
  ignore_comments_button.set_attribute("type", "button")
  ignore_comments_button.set_attribute(
    "class", "moonbit-diff-editor-ignore-comments active",
  )
  ignore_comments_button.set_attribute("aria-label", "Ignore comments")
  ignore_comments_button.set_attribute("aria-pressed", "true")
  ignore_comments_button.set_attribute("disabled", "")
  let ignore_comments_icon = document.create_element("span")
  ignore_comments_icon.set_attribute(
    "class", "moonbit-diff-editor-ignore-comments-icon",
  )
  ignore_comments_icon.set_attribute("aria-hidden", "true")
  ignore_comments_icon.set_inner_html("//")
  ignore_comments_button.append_child(ignore_comments_icon.as_node())
  let ignore_comments_label = document.create_element("span")
  ignore_comments_label.set_attribute(
    "class", "moonbit-diff-editor-ignore-comments-label",
  )
  ignore_comments_label.set_inner_html("Ignore comments")
  ignore_comments_button.append_child(ignore_comments_label.as_node())
  toolbar.append_child(ignore_comments_button.as_node())
  let mode_status = document.create_element("span")
  mode_status.set_attribute("class", "moonbit-diff-editor-mode-status")
  mode_status.set_attribute("aria-live", "polite")
  mode_status.set_attribute("hidden", "")
  toolbar.append_child(mode_status.as_node())
  let panes = document.create_element("div")
  panes.set_attribute("class", "moonbit-diff-editor-panes")
  let original_host = document.create_element("div")
  original_host.set_attribute(
    "class", "moonbit-diff-editor-pane moonbit-diff-editor-original",
  )
  original_host.set_attribute("role", "group")
  original_host.set_attribute("aria-label", "Original file")
  let modified_host = document.create_element("div")
  modified_host.set_attribute(
    "class", "moonbit-diff-editor-pane moonbit-diff-editor-modified",
  )
  modified_host.set_attribute("role", "group")
  modified_host.set_attribute("aria-label", "Modified file")
  panes.append_child(original_host.as_node())
  panes.append_child(modified_host.as_node())
  root.append_child(toolbar.as_node())
  root.append_child(panes.as_node())
  host.append_child(root.as_node())

  let (shared_services, owned_services) = match services {
    Some(services) => (services, None)
    None => {
      let services = ViewerServices()
      (services, Some(services))
    }
  }
  // Logical-line alignment currently relies on one fixed line height. Keep
  // the rest of the host's visual/runtime policy intact.
  let pane_options = { ..options, soft_wrap: false, folding: false }
  let original_viewer = create_diff_pane(
    original_host, shared_services, pane_options,
  )
  let modified_viewer = create_diff_pane(
    modified_host, shared_services, pane_options,
  )
  let diff_viewer : DiffViewer = {
    host,
    root,
    original_host,
    modified_host,
    toolbar,
    mode_status,
    mode_buttons,
    ignore_comments_button,
    original_viewer,
    modified_viewer,
    owned_services,
    render_mode,
    resize_observer: None,
    viewport_restore_frame: None,
    scroll_disposables: [],
    model_disposables: [],
    original_decoration_ids: [],
    modified_decoration_ids: [],
    original_zone_ids: [],
    modified_zone_ids: [],
    diff_mode: StandardDiff,
    ignore_comments: true,
    disposed: false,
  }
  diff_viewer.apply_render_mode_dom()
  for entry in diff_viewer.mode_buttons {
    let (mode, button) = entry
    button.add_event_listener("click", event => {
      event.prevent_default()
      event.stop_propagation()
      diff_viewer.set_diff_mode(mode)
    })
  }
  diff_viewer.ignore_comments_button.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    if diff_viewer.diff_mode is StandardDiff {
      return
    }
    diff_viewer.ignore_comments = !diff_viewer.ignore_comments
    diff_viewer.refresh_diff()
  })
  diff_viewer.update_diff_mode_controls(
    specialized_available=false,
    effective_mode=StandardDiff,
    fell_back=false,
  )
  diff_viewer.scroll_disposables.push(
    original_viewer.on_did_scroll_change(event => {
      if diff_viewer.render_mode == SideBySide && event.scroll_top_changed {
        diff_viewer.sync_scroll_top_to(modified_viewer, event.scroll_top)
      }
      if diff_viewer.render_mode == SideBySide && event.scroll_left_changed {
        diff_viewer.sync_scroll_left_to(modified_viewer, event.scroll_left)
      }
    }),
  )
  diff_viewer.scroll_disposables.push(
    modified_viewer.on_did_scroll_change(event => {
      if event.scroll_top_changed {
        diff_viewer.sync_scroll_top_to(original_viewer, event.scroll_top)
      }
      if event.scroll_left_changed {
        diff_viewer.sync_scroll_left_to(original_viewer, event.scroll_left)
      }
    }),
  )
  diff_viewer.resize_observer = @base_browser.observe_element_resize(host, () => {
    diff_viewer.layout()
  })
  diff_viewer
}

///|
fn create_diff_pane(
  host : @rdom.Element,
  services : ViewerServices,
  options : ViewerOptions,
) -> Viewer {
  let viewer = Viewer(
    services~,
    options~,
    initial_container=host,
    force_code_presentation=true,
  )
  viewer.attach(host)
  viewer
}

///|
/// Replace or clear the comparison. Reapplying the same models is cheap but
/// still recomputes presentation so callers can explicitly refresh diff state.
pub fn DiffViewer::set_model(
  self : DiffViewer,
  diff_model : DiffEditorModel?,
) -> Unit {
  if self.disposed {
    return
  }
  self.cancel_modified_viewport_restore()
  self.dispose_model_disposables()
  self.clear_diff_artifacts()
  match diff_model {
    None => {
      self.original_viewer.set_model(None)
      self.modified_viewer.set_model(None)
      self.update_diff_mode_controls(
        specialized_available=false,
        effective_mode=StandardDiff,
        fell_back=false,
      )
    }
    Some(diff_model) => {
      self.original_viewer.set_model(Some(diff_model.original))
      self.modified_viewer.set_model(Some(diff_model.modified))
      self.model_disposables.push(
        diff_model.original.on_did_change_content(_ => self.refresh_diff()),
      )
      self.model_disposables.push(
        diff_model.original.on_did_change_tokens(_ => {
          if self.render_mode == Unified {
            self.refresh_diff()
          }
        }),
      )
      self.model_disposables.push(
        diff_model.modified.on_did_change_content(_ => self.refresh_diff()),
      )
      self.refresh_diff()
      self.original_viewer.handle_initialized()
      self.modified_viewer.handle_initialized()
    }
  }
}

///|
/// The currently installed pair, or `None` while either pane is empty.
pub fn DiffViewer::get_model(self : DiffViewer) -> DiffEditorModel? {
  match (self.original_viewer.get_model(), self.modified_viewer.get_model()) {
    (Some(original), Some(modified)) => Some({ original, modified })
    _ => None
  }
}

///|
/// The current comparison presentation.
pub fn DiffViewer::get_render_mode(self : DiffViewer) -> DiffEditorRenderMode {
  self.render_mode
}

///|
fn DiffViewer::capture_modified_viewport_anchor(
  self : DiffViewer,
) -> DiffViewportAnchor? {
  let visible_ranges = self.modified_viewer.get_visible_ranges()
  guard !visible_ranges.is_empty() else { return None }
  let line_number = visible_ranges[0].start_line_number
  let line_top = self.modified_viewer.get_top_for_line_number(line_number)
  let scroll_top = self.modified_viewer.get_scroll_top()
  guard line_top >= 0.0 && scroll_top >= 0.0 else { return None }
  Some({ line_number, viewport_offset: line_top - scroll_top })
}

///|
fn DiffViewer::restore_modified_viewport_anchor(
  self : DiffViewer,
  anchor : DiffViewportAnchor?,
) -> Unit {
  guard anchor is Some(anchor) else { return }
  let line_top = self.modified_viewer.get_top_for_line_number(
    anchor.line_number,
  )
  guard line_top >= 0.0 else { return }
  self.modified_viewer.set_scroll_top(
    (line_top - anchor.viewport_offset).max(0.0),
  )
}

///|
fn DiffViewer::cancel_modified_viewport_restore(self : DiffViewer) -> Unit {
  match self.viewport_restore_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  self.viewport_restore_frame = None
}

///|
/// ViewZone mutations enter the ViewModel queue synchronously but reach
/// ViewLayout during the Viewer's priority-100 render. Restore later in the
/// same native frame so the browser never paints the displaced numeric
/// scrollTop. A later model or mode change cancels this anchor.
fn DiffViewer::schedule_modified_viewport_restore(
  self : DiffViewer,
  anchor : DiffViewportAnchor?,
) -> Unit {
  guard anchor is Some(anchor) else { return }
  let expected_render_mode = self.render_mode
  self.viewport_restore_frame = Some(
    @base_browser.run_at_this_or_schedule_at_next_animation_frame(
      () => {
        self.viewport_restore_frame = None
        if self.disposed || self.render_mode != expected_render_mode {
          return
        }
        self.restore_modified_viewport_anchor(Some(anchor))
      },
      // Viewer render runs at 100; restoring at 0 observes the committed zone
      // geometry and still runs before the browser paints this native frame.
      priority=0,
    ),
  )
}

///|
/// Switch the existing comparison between two panes and one interleaved pane.
/// Models, services, selections, and the modified Viewer's scroll state stay
/// installed. Rebuilding only coordinator-owned decorations and ViewZones also
/// makes repeated calls idempotent.
pub fn DiffViewer::set_render_mode(
  self : DiffViewer,
  render_mode : DiffEditorRenderMode,
) -> Unit {
  if self.disposed || self.render_mode == render_mode {
    return
  }
  self.cancel_modified_viewport_restore()
  let viewport_anchor = self.capture_modified_viewport_anchor()
  self.render_mode = render_mode
  self.apply_render_mode_dom()
  self.layout()
  self.refresh_diff()
  self.schedule_modified_viewport_restore(viewport_anchor)
  if render_mode == SideBySide {
    self.sync_scroll_top_to(
      self.original_viewer,
      self.modified_viewer.get_scroll_top(),
    )
    self.sync_scroll_left_to(
      self.original_viewer,
      self.modified_viewer.get_scroll_left(),
    )
  }
}

///|
/// Select a comparison strategy. MoonBit-aware modes remain selected while a
/// non-`.mbt` model is open, but that model is rendered with `StandardDiff`
/// and the specialized controls stay hidden.
pub fn DiffViewer::set_diff_mode(
  self : DiffViewer,
  mode : DiffViewerMode,
) -> Unit {
  if self.disposed || self.diff_mode == mode {
    return
  }
  self.diff_mode = mode
  self.refresh_diff()
}

///|
/// The user's selected strategy. The effective renderer can temporarily be
/// `StandardDiff` for non-`.mbt` files or after a specialized calculation
/// fails.
pub fn DiffViewer::get_diff_mode(self : DiffViewer) -> DiffViewerMode {
  self.diff_mode
}

///|
/// Clear the comparison while retaining the reusable two-pane surface.
pub fn DiffViewer::clear(self : DiffViewer) -> Unit {
  self.set_model(None)
}

///|
/// Re-measure both child hosts after their caller-controlled layout changes.
pub fn DiffViewer::layout(self : DiffViewer) -> Unit {
  if !self.disposed {
    self.original_viewer.layout()
    self.modified_viewer.layout()
  }
}

///|
/// Release both Viewers and all coordinator-owned state. Caller models and an
/// explicitly supplied ViewerServices bundle remain caller-owned.
pub fn DiffViewer::dispose(self : DiffViewer) -> Unit {
  if self.disposed {
    return
  }
  self.cancel_modified_viewport_restore()
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  self.resize_observer = None
  self.dispose_model_disposables()
  for disposable in self.scroll_disposables {
    disposable.dispose()
  }
  self.scroll_disposables.clear()
  self.clear_diff_artifacts()
  self.original_viewer.dispose()
  self.modified_viewer.dispose()
  self.host.remove_child(self.root.as_node())
  match self.owned_services {
    Some(services) => services.dispose()
    None => ()
  }
  self.disposed = true
}

///|
fn DiffViewer::dispose_model_disposables(self : DiffViewer) -> Unit {
  for disposable in self.model_disposables {
    disposable.dispose()
  }
  self.model_disposables.clear()
}

///|
fn DiffViewer::apply_render_mode_dom(self : DiffViewer) -> Unit {
  match self.render_mode {
    SideBySide => {
      self.root.set_attribute(
        "class", "moonbit-diff-editor moonbit-diff-editor-side-by-side",
      )
      self.root.set_attribute("data-render-mode", "side-by-side")
      self.original_host.remove_attribute("aria-hidden")
      self.modified_host.set_attribute("aria-label", "Modified file")
    }
    Unified => {
      self.root.set_attribute(
        "class", "moonbit-diff-editor moonbit-diff-editor-unified",
      )
      self.root.set_attribute("data-render-mode", "unified")
      self.original_host.set_attribute("aria-hidden", "true")
      self.modified_host.set_attribute("aria-label", "Unified diff")
    }
  }
}

///|
fn DiffViewer::sync_scroll_top_to(
  self : DiffViewer,
  target : Viewer,
  scroll_top : Double,
) -> Unit {
  if !self.disposed && (target.get_scroll_top() - scroll_top).abs() > 0.5 {
    target.set_scroll_top(scroll_top)
  }
}

///|
fn DiffViewer::sync_scroll_left_to(
  self : DiffViewer,
  target : Viewer,
  scroll_left : Double,
) -> Unit {
  if !self.disposed && (target.get_scroll_left() - scroll_left).abs() > 0.5 {
    target.set_scroll_left(scroll_left)
  }
}

///|
fn DiffViewerMode::attribute_name(self : DiffViewerMode) -> String {
  match self {
    StandardDiff => "standard"
    TokenDiff => "token"
    TreeDiff => "tree"
  }
}

///|
fn DiffViewerMode::visible_label(self : DiffViewerMode) -> String {
  match self {
    StandardDiff => "Standard"
    TokenDiff => "Token"
    TreeDiff => "Tree"
  }
}

///|
fn DiffViewerMode::accessible_label(self : DiffViewerMode) -> String {
  match self {
    StandardDiff => "Standard diff"
    TokenDiff => "Token diff"
    TreeDiff => "Tree diff"
  }
}

///|
fn DiffViewerMode::title(self : DiffViewerMode) -> String {
  match self {
    StandardDiff => "Use the standard line and character diff"
    TokenDiff => "Compare MoonBit tokens with moondiff"
    TreeDiff => "Compare MoonBit syntax trees with moondiff"
  }
}

///|
fn DiffViewer::update_diff_mode_controls(
  self : DiffViewer,
  specialized_available~ : Bool,
  effective_mode~ : DiffViewerMode,
  fell_back~ : Bool,
) -> Unit {
  let selected_mode = if specialized_available {
    self.diff_mode
  } else {
    StandardDiff
  }
  if specialized_available {
    self.toolbar.remove_attribute("hidden")
    self.root.set_attribute("data-moondiff-available", "true")
  } else {
    self.toolbar.set_attribute("hidden", "")
    self.root.remove_attribute("data-moondiff-available")
  }
  self.root.set_attribute("data-diff-mode", selected_mode.attribute_name())
  self.root.set_attribute("data-diff-renderer", effective_mode.attribute_name())
  self.root.set_attribute(
    "data-ignore-comments",
    self.ignore_comments.to_string(),
  )
  for entry in self.mode_buttons {
    let (mode, button) = entry
    let active = mode == selected_mode
    button.set_attribute(
      "class",
      if active {
        "moonbit-diff-editor-mode active"
      } else {
        "moonbit-diff-editor-mode"
      },
    )
    button.set_attribute("aria-pressed", active.to_string())
  }
  self.ignore_comments_button.set_attribute(
    "class",
    if self.ignore_comments {
      "moonbit-diff-editor-ignore-comments active"
    } else {
      "moonbit-diff-editor-ignore-comments"
    },
  )
  self.ignore_comments_button.set_attribute(
    "aria-pressed",
    self.ignore_comments.to_string(),
  )
  if specialized_available && !(self.diff_mode is StandardDiff) {
    self.ignore_comments_button.remove_attribute("disabled")
    self.ignore_comments_button.set_attribute(
      "title",
      if self.ignore_comments {
        "Show comment and blank-line changes"
      } else {
        "Ignore MoonBit comment and blank-line changes"
      },
    )
  } else {
    self.ignore_comments_button.set_attribute("disabled", "")
    self.ignore_comments_button.set_attribute(
      "title", "Available in Token and Tree diff",
    )
  }
  if fell_back {
    self.root.set_attribute("data-diff-fallback", "true")
    self.mode_status.remove_attribute("hidden")
    let message = match (self.diff_mode, effective_mode) {
      (TokenDiff, StandardDiff) =>
        "Token diff unavailable — showing standard diff"
      (TreeDiff, TokenDiff) => "Tree diff unavailable — showing token diff"
      (TreeDiff, StandardDiff) =>
        "Tree diff unavailable — showing standard diff"
      _ => ""
    }
    self.mode_status.set_attribute("title", message)
    self.mode_status.set_inner_html(message)
  } else {
    self.root.remove_attribute("data-diff-fallback")
    self.mode_status.set_attribute("hidden", "")
    self.mode_status.remove_attribute("title")
    self.mode_status.set_inner_html("")
  }
}

///|
fn DiffViewer::refresh_diff(self : DiffViewer) -> Unit {
  if self.disposed {
    return
  }
  guard self.get_model() is Some(diff_model) else { return }
  self.clear_diff_artifacts()
  let original_lines = diff_model.original.get_lines_content()
  let modified_lines = diff_model.modified.get_lines_content()
  let specialized_available = diff_model.supports_moondiff()
  let calculation = calculate_diff_changes(
    self.diff_mode,
    specialized_available,
    self.ignore_comments,
    original_lines,
    modified_lines,
    diff_model.original.get_value(),
    diff_model.modified.get_value(),
  )
  self.update_diff_mode_controls(
    specialized_available~,
    effective_mode=calculation.effective_mode,
    fell_back=calculation.fell_back,
  )
  let changes = calculation.changes
  let presentation = diff_presentation(changes)
  let modified_decorations = line_decorations(
    diff_model.modified,
    presentation.modified_changed,
    "diff-editor-line-insert",
    "diff-editor-gutter-insert",
    "diff-editor-modified-line",
  )
  modified_decorations.append(
    inline_decorations(
      presentation.modified_inner_changed,
      "diff-editor-char-insert",
      "diff-editor-modified-character",
    ),
  )
  self.modified_decoration_ids = self.modified_viewer.delta_decorations(
    [],
    modified_decorations,
  )
  match self.render_mode {
    SideBySide => {
      let original_decorations = line_decorations(
        diff_model.original,
        presentation.original_changed,
        "diff-editor-line-delete",
        "diff-editor-gutter-delete",
        "diff-editor-original-line",
      )
      original_decorations.append(
        inline_decorations(
          presentation.original_inner_changed,
          "diff-editor-char-delete",
          "diff-editor-original-character",
        ),
      )
      self.original_decoration_ids = self.original_viewer.delta_decorations(
        [],
        original_decorations,
      )
      self.original_zone_ids = install_alignment_zones(
        self.original_viewer,
        presentation.original_spacers,
      )
      self.modified_zone_ids = install_alignment_zones(
        self.modified_viewer,
        presentation.modified_spacers,
      )
    }
    Unified =>
      self.modified_zone_ids = install_unified_deleted_zones(
        self.modified_viewer,
        diff_model.original,
        changes,
      )
  }
}

///|
fn DiffViewer::clear_diff_artifacts(self : DiffViewer) -> Unit {
  self.original_decoration_ids = self.original_viewer.delta_decorations(
    self.original_decoration_ids,
    [],
  )
  self.modified_decoration_ids = self.modified_viewer.delta_decorations(
    self.modified_decoration_ids,
    [],
  )
  remove_diff_zones(self.original_viewer, self.original_zone_ids)
  remove_diff_zones(self.modified_viewer, self.modified_zone_ids)
  self.original_zone_ids = []
  self.modified_zone_ids = []
}

///|
priv struct DiffSpacer {
  after_line_number : Int
  height_in_lines : Int
}

///|
priv struct DiffLineChange {
  original : @base_common.LineRange
  modified : @base_common.LineRange
  original_inner_changed : Array[@base_common.Range]
  modified_inner_changed : Array[@base_common.Range]
  render_change : Bool
}

///|
priv struct DiffPresentation {
  original_changed : Array[@base_common.LineRange]
  modified_changed : Array[@base_common.LineRange]
  original_inner_changed : Array[@base_common.Range]
  modified_inner_changed : Array[@base_common.Range]
  original_spacers : Array[DiffSpacer]
  modified_spacers : Array[DiffSpacer]
}

///|
/// Convert line mappings once into the four independent rendering inputs.
/// Unequal replacement ranges align from their starts and put the remaining
/// height after the shorter block; insertions/deletions therefore use the
/// preceding logical line (including Monaco's valid line-zero anchor).
fn diff_presentation(changes : Array[DiffLineChange]) -> DiffPresentation {
  let original_changed = []
  let modified_changed = []
  let original_inner_changed = []
  let modified_inner_changed = []
  let original_spacers = []
  let modified_spacers = []
  for change in changes {
    if change.render_change {
      if !change.original.is_empty() {
        original_changed.push(change.original)
      }
      if !change.modified.is_empty() {
        modified_changed.push(change.modified)
      }
      for original in change.original_inner_changed {
        if !original.is_empty() {
          original_inner_changed.push(original)
        }
      }
      for modified in change.modified_inner_changed {
        if !modified.is_empty() {
          modified_inner_changed.push(modified)
        }
      }
    }
    let original_length = change.original.length()
    let modified_length = change.modified.length()
    if original_length < modified_length {
      original_spacers.push({
        after_line_number: change.original.end_line_number_exclusive - 1,
        height_in_lines: modified_length - original_length,
      })
    } else if modified_length < original_length {
      modified_spacers.push({
        after_line_number: change.modified.end_line_number_exclusive - 1,
        height_in_lines: original_length - modified_length,
      })
    }
  }
  {
    original_changed,
    modified_changed,
    original_inner_changed,
    modified_inner_changed,
    original_spacers,
    modified_spacers,
  }
}

///|
fn line_decorations(
  model : @model.TextModel,
  ranges : Array[@base_common.LineRange],
  line_class : String,
  gutter_class : String,
  description : String,
) -> Array[@model.ModelDeltaDecoration] {
  // An empty document has one model line for cursor geometry, but it is not a
  // deleted/inserted source line. Its physical line still contributes to
  // spacer height, so only the decoration is suppressed.
  if model.get_value().is_empty() {
    return []
  }
  let decorations : Array[@model.ModelDeltaDecoration] = []
  for range in ranges {
    guard !range.is_empty() else { continue }
    let end_line = range.end_line_number_exclusive - 1
    decorations.push({
      range: Range(
        range.start_line_number,
        1,
        end_line,
        model.get_line_max_column(end_line),
      ),
      options: ModelDecorationOptions(
        line_class,
        is_whole_line=true,
        lines_decorations_class_name=gutter_class,
        description~,
      ),
    })
  }
  decorations
}

///|
fn inline_decorations(
  ranges : Array[@base_common.Range],
  inline_class : String,
  description : String,
) -> Array[@model.ModelDeltaDecoration] {
  ranges.map(range => {
    range,
    options: ModelDecorationOptions(
      "",
      inline_class_name=inline_class,
      description~,
    ),
  })
}

///|
fn install_alignment_zones(
  viewer : Viewer,
  spacers : Array[DiffSpacer],
) -> Array[String] {
  let ids : Array[String] = []
  if spacers.is_empty() {
    return ids
  }
  viewer.change_view_zones(accessor => {
    for spacer in spacers {
      let dom_node = @rdom.document().create_element("div")
      dom_node.set_attribute("class", "diff-editor-alignment-zone")
      ids.push(
        accessor.add_zone(
          view_zone(
            spacer.after_line_number,
            dom_node,
            suppress_mouse_down=true,
            height_in_lines=spacer.height_in_lines.to_double(),
          ),
        ),
      )
    }
  })
  ids
}

///|
priv struct DiffInlineInterval {
  start_offset : Int
  end_offset : Int
}

///|
fn deleted_inline_intervals_for_line(
  ranges : Array[@base_common.Range],
  line_number : Int,
  line_length : Int,
) -> Array[DiffInlineInterval] {
  let intervals = []
  for range in ranges {
    if line_number < range.start_line_number ||
      line_number > range.end_line_number {
      continue
    }
    let start_offset = (if line_number == range.start_line_number {
        range.start_column - 1
      } else {
        0
      })
      .max(0)
      .min(line_length)
    let end_offset = (if line_number == range.end_line_number {
        range.end_column - 1
      } else {
        line_length
      })
      .max(0)
      .min(line_length)
    if start_offset < end_offset {
      intervals.push({ start_offset, end_offset })
    }
  }
  intervals
}

///|
fn append_deleted_line_tokens(
  row : @rdom.Element,
  model : @model.TextModel,
  line_number : Int,
  inner_ranges : Array[@base_common.Range],
) -> Unit {
  let document = @rdom.document()
  let text = model.get_line_content(line_number)
  if text.is_empty() {
    row.set_attribute("data-empty-line", "true")
    return
  }
  let intervals = deleted_inline_intervals_for_line(
    inner_ranges,
    line_number,
    text.length(),
  )
  let tokens = model.tokenization.get_line_tokens(line_number).inflate()
  let token_count = tokens.get_count()
  let mut token_index = 0
  let mut offset = 0
  while offset < text.length() {
    while token_index + 1 < token_count &&
          tokens.get_end_offset(token_index) <= offset {
      token_index += 1
    }
    let mut next_offset = if token_count > 0 &&
      tokens.get_end_offset(token_index) > offset {
      tokens.get_end_offset(token_index).min(text.length())
    } else {
      text.length()
    }
    let mut changed = false
    for interval in intervals {
      if interval.start_offset <= offset && offset < interval.end_offset {
        changed = true
      }
      if interval.start_offset > offset {
        next_offset = next_offset.min(interval.start_offset)
      }
      if interval.end_offset > offset {
        next_offset = next_offset.min(interval.end_offset)
      }
    }
    let span = document.create_element("span")
    let token_class = if token_count > 0 {
      tokens.get_class_name(token_index)
    } else {
      "mtk1"
    }
    span.set_attribute(
      "class",
      if changed {
        token_class + " diff-editor-char-delete"
      } else {
        token_class
      },
    )
    span.append_child(
      document
      .create_text_node(text.unsafe_substring(start=offset, end=next_offset))
      .as_node(),
    )
    row.append_child(span.as_node())
    offset = next_offset
  }
}

///|
fn original_inner_ranges(change : DiffLineChange) -> Array[@base_common.Range] {
  let ranges = []
  for original in change.original_inner_changed {
    if !original.is_empty() {
      ranges.push(original)
    }
  }
  ranges
}

///|
fn unified_deleted_zone_anchor(change : DiffLineChange) -> Int {
  change.modified.start_line_number - 1
}

///|
fn deleted_line_visual_columns(text : String, tab_size : Int) -> Int {
  @core.visible_column_from_column(text, text.length() + 1, tab_size.max(1))
}

///|
fn deleted_block_min_width(
  model : @model.TextModel,
  range : @base_common.LineRange,
  tab_size : Int,
  typical_halfwidth_character_width : Double,
) -> Double {
  let mut longest_visual_columns = 0
  for line_number in range.start_line_number..<range.end_line_number_exclusive {
    longest_visual_columns = longest_visual_columns.max(
      deleted_line_visual_columns(model.get_line_content(line_number), tab_size),
    )
  }
  (longest_visual_columns.to_double() *
  typical_halfwidth_character_width.max(1.0) +
  24.0).min(1000000.0)
}

///|
fn install_unified_deleted_zones(
  viewer : Viewer,
  original_model : @model.TextModel,
  changes : Array[DiffLineChange],
) -> Array[String] {
  let ids : Array[String] = []
  let configuration = viewer.configuration.snapshot()
  let options = configuration.options
  viewer.change_view_zones(accessor => {
    for ordinal, change in changes {
      guard change.render_change && !change.original.is_empty() else {
        continue
      }
      let document = @rdom.document()
      let content = document.create_element("div")
      content.set_attribute("class", "diff-editor-unified-deleted-block")
      content.set_attribute("role", "group")
      content.set_attribute(
        "aria-label",
        "Deleted lines \{change.original.start_line_number} through \{change.original.end_line_number_exclusive - 1}",
      )
      content.set_attribute(
        "data-original-start-line",
        change.original.start_line_number.to_string(),
      )
      content.set_attribute(
        "data-original-end-line",
        (change.original.end_line_number_exclusive - 1).to_string(),
      )
      @base_browser.set_style_property(
        content,
        "tab-size",
        options.tab_size.to_string(),
      )
      let margin = document.create_element("div")
      margin.set_attribute("class", "diff-editor-unified-deleted-margin")
      let inner_ranges = original_inner_ranges(change)
      for
        line_number in change.original.start_line_number..<change.original.end_line_number_exclusive {
        let row = document.create_element("div")
        row.set_attribute("class", "diff-editor-unified-deleted-line")
        row.set_attribute("data-original-line", line_number.to_string())
        append_deleted_line_tokens(
          row, original_model, line_number, inner_ranges,
        )
        content.append_child(row.as_node())

        let line_number_node = document.create_element("div")
        line_number_node.set_attribute(
          "class", "diff-editor-unified-deleted-line-number",
        )
        line_number_node.append_child(
          document.create_text_node(line_number.to_string()).as_node(),
        )
        margin.append_child(line_number_node.as_node())
      }
      ids.push(
        accessor.add_zone(
          view_zone(
            unified_deleted_zone_anchor(change),
            content,
            ordinal~,
            suppress_mouse_down=false,
            height_in_lines=change.original.length().to_double(),
            min_width_in_px=deleted_block_min_width(
              original_model,
              change.original,
              options.tab_size,
              configuration.font_info.typical_halfwidth_character_width,
            ),
            margin_dom_node=margin,
          ),
        ),
      )
      // ViewZones defaults caller content to presentation-only. Deleted source
      // is meaningful comparison text, so expose this non-interactive block.
      content.remove_attribute("aria-hidden")
    }
  })
  ids
}

///|
fn remove_diff_zones(viewer : Viewer, ids : Array[String]) -> Unit {
  if ids.is_empty() {
    return
  }
  viewer.change_view_zones(accessor => {
    for id in ids {
      accessor.remove_zone(id)
    }
  })
}

///|
#deprecated
pub extend DiffEditorRenderMode with Debug::{to_repr}

///|
pub extend DiffEditorRenderMode with Eq::{equal, not_equal}

///|
pub extend DiffViewerMode with Eq::{equal, not_equal}
