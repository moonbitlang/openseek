// The viewer core's side of the agent-feedback contrib — the editor
// lifecycle of `vscode/src/vs/sessions/contrib/agentFeedback/browser/
// agentFeedbackEditorInputContribution.ts` (`AgentFeedbackEditorInputContribution`):
// service subscriptions, the hover "+" glyph decoration and its gates
// (`_updateHoverGlyph`), the reserved gutter lane
// (`_updateReservedGutterSpace`), the selection → inline-input flow
// (`_onSelectionChanged` / `_show` / `_updatePosition`) and the glyph-click
// line selection (`_selectLine`). The widget DOM lives in
// `internal/viewer/contrib/agent_feedback/browser`; the DOM-free store and
// grouping live in `internal/viewer/contrib/agent_feedback`. CodeEditorWidget-facing
// subscriptions stay in the root composition package: moving them into an
// internal contribution would reverse the dependency on `viewer` and create a
// package cycle.
//
// Deviations from the source, recorded up front: the session scope gate is
// the service's `is_feedback_enabled` (the host decides which files are in
// scope); Escape and Ctrl/Cmd+I route through the keybinding registry
// instead of an editor-DOM keydown listener (and the readonly-editor
// "typing steals focus into the input" arm is dropped — the viewer is
// always readonly, but its editor keys are navigation-only, so there is no
// typing to steal); blur auto-hide is the widget's own empty-blur event
// rather than the editor-blur `setTimeout(0)` dance; and the editor-resize
// reposition rides the scroll event (the viewer has no separate
// `onDidLayoutChange`).

///|
/// `_RESERVED_GUTTER_WIDTH` (`agentFeedbackEditorInputContribution.ts:252`):
/// extra lane width reserved so the add glyph renders fully.
let agent_feedback_reserved_gutter_px : Int = 18

///|
/// The overlay-widget id of the singleton input widget
/// (`AgentFeedbackInputWidget._ID`).
let agent_feedback_input_widget_id : String = "agentFeedback.inputWidget"

///|
/// `registerEditorContribution(AgentFeedbackEditorInputContribution.ID, …,
/// Eventually)` (`agentFeedbackEditorInputContribution.ts:911`) plus the
/// Escape/Ctrl+I routing the upstream contribution wired as DOM listeners.
fn register_agent_feedback_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    "agentFeedback.editorInputContribution",
    AgentFeedbackInput,
    Eventually,
    _viewer => AgentFeedbackInput(AgentFeedbackEditorInputContribution()),
    viewer => viewer.hook_agent_feedback(),
  )
  // The editor-level Escape arm of `_registerWidgetListeners` ("Don't
  // capture Escape … this._hide()"): close the input while the editor has
  // focus. Escape inside the textarea is the widget's own keydown.
  registry.register_editor_command(
    "agentFeedback.cancelInput",
    viewer => viewer.agent_feedback_input_visible(),
    viewer => viewer.hide_agent_feedback_input(refocus_editor=false),
    [("Escape", false, false)],
  )
  // "Ctrl+I / Cmd+I explicitly focuses the feedback input".
  registry.register_editor_command(
    "agentFeedback.focusInput",
    viewer => viewer.agent_feedback_input_visible(),
    viewer => viewer.focus_agent_feedback_input(),
    [("i", false, true)],
  )
  register_agent_feedback_widgets_contribution(registry)
}

///|
/// The constructor-time wiring of `AgentFeedbackEditorInputContribution`:
/// service, cursor/model, scroll, and mouse subscriptions.
fn CodeEditorWidget::hook_agent_feedback(
  self : CodeEditorWidget,
) -> Array[@base_common.Disposable] {
  self.sync_agent_feedback_lane()
  [
    self.services.agent_feedback.on_did_change_feedback(event => {
      if self.is_current_resource(event.resource) {
        self.sync_agent_feedback_lane()
        // A feedback item may have landed on the glyph line; re-evaluate
        // the "line already has feedback" gate.
        let line = match self.agent_feedback_input_contribution() {
          Some(ic) => ic.hover_line_number
          None => -1
        }
        if line >= 1 {
          self.clear_agent_feedback_hover_glyph()
          self.update_agent_feedback_hover_glyph(line)
        }
      }
    }),
    self.on_did_change_model(_ => self.on_agent_feedback_model_changed()),
    // A `set_value` flush destroys the glyph/highlight decorations and may
    // remove the input's anchor line; treat it like a model change — hide
    // the input, clear the glyph, and re-evaluate the lane (Track E).
    self.on_did_change_model_content(_ => self.on_agent_feedback_model_changed()),
    self.on_did_change_cursor_selection(_ => {
      self.on_agent_feedback_selection_changed()
    }),
    self.on_did_scroll_change(_ => {
      if self.agent_feedback_input_visible() {
        self.update_agent_feedback_input_position()
      }
    }),
    self.on_mouse_move(event => self.on_agent_feedback_mouse_move(event)),
    self.on_mouse_leave(_ => self.clear_agent_feedback_hover_glyph()),
    self.on_mouse_down(event => self.on_agent_feedback_mouse_down(event)),
    self.on_mouse_up(event => self.on_agent_feedback_mouse_up(event)),
  ]
}

///|
/// Whether a service event's resource is the installed model's —
/// the per-editor filter every contribution subscription applies
/// (previously homed with the comments contrib).
fn CodeEditorWidget::is_current_resource(
  self : CodeEditorWidget,
  resource : @base_common.Uri,
) -> Bool {
  self.get_model() is Some(model) &&
  model.uri.to_string() == resource.to_string()
}

///|
/// The live input-contribution instance for this editor — the
/// `getContribution(AgentFeedbackEditorInputContribution.ID)` analog.
/// `None` after the contribution disposed.
fn CodeEditorWidget::agent_feedback_input_contribution(
  self : CodeEditorWidget,
) -> @agent_feedback_browser.AgentFeedbackEditorInputContribution? {
  match self.contributions.lookup("agentFeedback.editorInputContribution") {
    Some(entry) =>
      match entry.instance {
        AgentFeedbackInput(controller) => Some(controller)
        _ => None
      }
    _ => None
  }
}

///|
/// Whether the inline input is showing — the `_visible` read the keybinding
/// gates and the scroll hook consult.
fn CodeEditorWidget::agent_feedback_input_visible(
  self : CodeEditorWidget,
) -> Bool {
  self.agent_feedback_input_contribution() is Some(ic) && ic.visible
}

///|
/// Whether the current model's resource has the feedback affordances on —
/// the `_getSessionForFile` stand-in.
fn CodeEditorWidget::agent_feedback_enabled(self : CodeEditorWidget) -> Bool {
  guard self.is_code_presentation() else { return false }
  self.get_model() is Some(model) &&
  self.services.agent_feedback.is_feedback_enabled(model.uri)
}

///|
/// `_onModelChanged`: hide, clear the glyph, drop the one-shot suppress, and
/// re-evaluate the lane for the new resource.
fn CodeEditorWidget::on_agent_feedback_model_changed(
  self : CodeEditorWidget,
) -> Unit {
  self.hide_agent_feedback_input(refocus_editor=false)
  self.clear_agent_feedback_hover_glyph()
  match self.agent_feedback_input_contribution() {
    Some(ic) => ic.suppress_selection_change_once = false
    None => ()
  }
  self.sync_agent_feedback_lane()
}

// --- reserved lane ----------------------------------------------------------------

///|
/// Applies a complete host-owned options snapshot without dropping the
/// contribution-owned gutter reservation. DiffEditor replays its saved pane
/// options during every layout; once feedback is enabled, that replay must
/// rebase the saved lane width and then add the 18px feedback lane again.
///
/// The feedback contribution itself continues to call `update_options`
/// directly when it first reserves or finally restores the lane, because
/// those calls already contain the effective width.
pub fn CodeEditorWidget::update_host_options(
  self : CodeEditorWidget,
  options : CodeEditorOptions,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) &&
    ic.lane_base_width is Some(_) else {
    self.update_options(options)
    return
  }
  ic.lane_base_width = Some(options.line_decorations_width)
  self.update_options({
    ..options,
    line_decorations_width: options.line_decorations_width +
    agent_feedback_reserved_gutter_px,
  })
}

///|
/// `_updateReservedGutterSpace`: reserve extra room in the line-decorations
/// margin while the resource offers feedback, restore the host's base width
/// when it no longer does (the comments contrib's store/restore shape; the
/// upstream added/subtracted a delta).
fn CodeEditorWidget::sync_agent_feedback_lane(self : CodeEditorWidget) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  let needed = self.agent_feedback_enabled()
  match (needed, ic.lane_base_width) {
    (true, None) => {
      let base = self.get_options().line_decorations_width
      ic.lane_base_width = Some(base)
      self.update_options({
        ..self.get_options(),
        line_decorations_width: base + agent_feedback_reserved_gutter_px,
      })
    }
    (false, Some(base)) => {
      ic.lane_base_width = None
      self.update_options({
        ..self.get_options(),
        line_decorations_width: base,
      })
    }
    _ => ()
  }
}

// --- hover "+" glyph ---------------------------------------------------------------

///|
/// `_onEditorMouseMove`: the glyph follows the hovered line unless the input
/// is open (or holds a draft).
fn CodeEditorWidget::on_agent_feedback_mouse_move(
  self : CodeEditorWidget,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  if self.agent_feedback_input_visible() || self.agent_feedback_has_draft() {
    self.clear_agent_feedback_hover_glyph()
    return
  }
  // `_updateHoverGlyph(e.target.position?.lineNumber)` — every
  // position-carrying kind updates the glyph (scrollbar targets included,
  // upstream behavior); positionless kinds clear it.
  let line = match event.target.position() {
    Some(position) => position.line_number
    None => -1
  }
  self.update_agent_feedback_hover_glyph(line)
}

///|
/// `_updateHoverGlyph` and its gates: a valid, non-empty line in an enabled
/// resource whose line has no existing feedback.
fn CodeEditorWidget::update_agent_feedback_hover_glyph(
  self : CodeEditorWidget,
  line : Int,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  guard self.get_model() is Some(model) else {
    self.clear_agent_feedback_hover_glyph()
    return
  }
  if line < 1 || line > model.snapshot.line_count() {
    self.clear_agent_feedback_hover_glyph()
    return
  }
  // "Don't offer feedback on empty lines (nothing to comment on)."
  if model.snapshot.get_line_first_non_whitespace_column(line) == 0 {
    self.clear_agent_feedback_hover_glyph()
    return
  }
  if ic.hover_line_number == line {
    return
  }
  if !self.agent_feedback_enabled() {
    self.clear_agent_feedback_hover_glyph()
    return
  }
  // "Don't render the add glyph on lines that already have a feedback
  // comment" (the add affordance would overlap the comment's gutter spot).
  if agent_feedback_line_has_feedback(
      self.services.agent_feedback.get_feedback(model.uri),
      line,
    ) {
    self.clear_agent_feedback_hover_glyph()
    return
  }
  ic.hover_line_number = line
  ic.hover_decoration_ids = model.delta_decorations(
    ic.hover_decoration_ids,
    [
      {
        range: Range(line, 1, line, 1),
        options: ModelDecorationOptions(
          "",
          is_whole_line=true,
          lines_decorations_class_name="agent-feedback-glyph line-hover",
          description="agent-feedback-hover-glyph",
        ),
      },
    ],
    owner_id=self.editor_id,
  )
}

///|
/// `_lineHasExistingFeedback`, resolved against unresolved items only (a
/// resolved item is invisible, so its line offers the add affordance again).
fn agent_feedback_line_has_feedback(
  items : Array[@agent_feedback_api.AgentFeedback],
  line : Int,
) -> Bool {
  items.search_by(item => {
    item.state != Resolved &&
    line >= item.range.start_line_number &&
    line <= item.range.end_line_number
  })
  is Some(_)
}

///|
/// `_clearHoverGlyph`.
fn CodeEditorWidget::clear_agent_feedback_hover_glyph(
  self : CodeEditorWidget,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  if ic.hover_line_number == -1 {
    return
  }
  ic.hover_line_number = -1
  guard self.get_model() is Some(model) else {
    ic.hover_decoration_ids = []
    return
  }
  ic.hover_decoration_ids = model.delta_decorations(
    ic.hover_decoration_ids,
    [],
    owner_id=self.editor_id,
  )
}

// --- mouse → input flow --------------------------------------------------------------

///|
/// Whether the mouse target is the rendered hover glyph. Upstream checks the
/// DOM class — `_isHoverGlyphTarget`
/// (`agentFeedbackEditorInputContribution.ts:346-348`): the hit element
/// carries `agent-feedback-glyph`. Targets carry their DOM element now, so
/// the upstream predicate ports verbatim.
fn CodeEditorWidget::is_agent_feedback_glyph_target(
  self : CodeEditorWidget,
  target : @editor_browser.MouseTarget,
) -> Bool {
  guard self.agent_feedback_input_contribution() is Some(_) else {
    return false
  }
  guard target.element() is Some(element) else { return false }
  element_class_list_contains(element, "agent-feedback-glyph")
}

///|
/// FFI gap-fill (no `classList` binding in the vendored `@rdom`).
extern "js" fn element_class_list_contains(
  element : @rdom.Element,
  class_name : String,
) -> Bool =
  #| (el, cls) => !!el.classList && el.classList.contains(cls)

///|
/// `onMouseDown`: a glyph hit selects the line (which opens the input via
/// the selection-change handler); anything else records the pending press
/// and auto-hides. Widget-internal presses never reach here — the widget's
/// containment stops propagation (`_isWidgetTarget`).
fn CodeEditorWidget::on_agent_feedback_mouse_down(
  self : CodeEditorWidget,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  if self.is_agent_feedback_glyph_target(event.target) {
    // upstream: `e.event.preventDefault(); e.event.stopPropagation()`
    event.event.prevent_default()
    event.event.stop_propagation()
    match event.target.position() {
      Some(position) => self.select_agent_feedback_line(position.line_number)
      None => ()
    }
    return
  }
  match self.agent_feedback_input_contribution() {
    Some(ic) => ic.mouse_down = true
    None => ()
  }
  self.auto_hide_agent_feedback_input()
}

///|
/// `onMouseUp`: the press ended; re-evaluate the selection (a drag-selection
/// finished here opens the input).
fn CodeEditorWidget::on_agent_feedback_mouse_up(
  self : CodeEditorWidget,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  match self.agent_feedback_input_contribution() {
    Some(ic) => ic.mouse_down = false
    None => ()
  }
  if self.is_agent_feedback_glyph_target(event.target) {
    return
  }
  self.on_agent_feedback_selection_changed()
}

///|
/// `_selectLine`: select the whole clicked line, focus the editor (the
/// selection-change handler opens the input synchronously), then move focus
/// into the input so typing can start immediately.
fn CodeEditorWidget::select_agent_feedback_line(
  self : CodeEditorWidget,
  line : Int,
) -> Unit {
  if self.agent_feedback_input_visible() && self.agent_feedback_has_draft() {
    self.focus_agent_feedback_input()
    return
  }
  guard self.get_model() is Some(model) else { return }
  if line < 1 || line > model.snapshot.line_count() {
    return
  }
  if model.snapshot.get_line_first_non_whitespace_column(line) == 0 {
    return
  }
  let max_column = model.snapshot.line_text(line - 1).length() + 1
  self.set_selection(
    @core.Selection::from_positions(
      Position(line, 1),
      Position(line, max_column),
    ),
  )
  self.focus()
  // The selection change while unfocused was ignored; the focused
  // re-evaluation below opens the input for the fresh selection.
  self.on_agent_feedback_selection_changed()
  self.focus_agent_feedback_input()
}

// --- selection → input ---------------------------------------------------------------

///|
/// `_onSelectionChanged`: the non-empty selection drives the input's
/// presence; a draft freezes it; the anchor follows the selection's active
/// end (below an LTR selection, above an RTL one).
fn CodeEditorWidget::on_agent_feedback_selection_changed(
  self : CodeEditorWidget,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  if ic.suppress_selection_change_once {
    ic.suppress_selection_change_once = false
    return
  }
  if ic.mouse_down || !self.has_text_focus() {
    return
  }
  if ic.visible && self.agent_feedback_has_draft() {
    return
  }
  guard self.get_selection() is Some(selection) && !selection.is_empty() else {
    self.auto_hide_agent_feedback_input()
    return
  }
  guard self.get_model() is Some(_) && self.agent_feedback_enabled() else {
    self.auto_hide_agent_feedback_input()
    return
  }
  let prefer_below = selection.direction() == LTR
  let anchor = if prefer_below { selection.end() } else { selection.start() }
  let range : @base_common.Range = Range(
    selection.start().line_number,
    selection.start().column,
    selection.end().line_number,
    selection.end().column,
  )
  self.show_agent_feedback_input(range, anchor, prefer_below, focus_input=false)
}

///|
/// `_show`.
fn CodeEditorWidget::show_agent_feedback_input(
  self : CodeEditorWidget,
  range : @base_common.Range,
  anchor : @base_common.Position,
  prefer_below : Bool,
  focus_input~ : Bool,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  let widget = self.ensure_agent_feedback_input()
  self.clear_agent_feedback_hover_glyph()
  ic.visible = true
  ic.pinned_range = Some(range)
  ic.anchor_position = Some(anchor)
  ic.prefer_below = prefer_below
  widget.set_placeholder("Add feedback")
  widget.clear_input()
  widget.show()
  self.update_agent_feedback_input_position()
  if focus_input {
    widget.focus_input()
  }
}

///|
/// `_ensureWidget`: the widget is created once per viewer, on first use;
/// the overlay registration re-adds it to each per-model view.
fn CodeEditorWidget::ensure_agent_feedback_input(
  self : CodeEditorWidget,
) -> @agent_feedback_browser.AgentFeedbackInputWidget {
  let ic = self.agent_feedback_input_contribution()
  let existing = ic.bind(contribution => contribution.widget)
  match existing {
    Some(widget) => widget
    None => {
      let widget = @agent_feedback_browser.AgentFeedbackInputWidget({
        on_add: () => self.add_agent_feedback_from_input(submit=false),
        on_add_and_submit: () => self.add_agent_feedback_from_input(submit=true),
        on_cancel: () => self.hide_agent_feedback_input(refocus_editor=true),
        on_layout: () => self.update_agent_feedback_input_position(),
        on_blur_empty: () => self.auto_hide_agent_feedback_input(),
        content_width: () => {
          let layout = self.get_layout_info()
          (layout.width - layout.content_left).max(0.0)
        },
      })
      match ic {
        Some(ic) => ic.widget = Some(widget)
        None => ()
      }
      self.add_overlay_widget(
        overlay_widget(agent_feedback_input_widget_id, widget.get_dom_node()),
      )
      widget
    }
  }
}

///|
fn CodeEditorWidget::agent_feedback_has_draft(self : CodeEditorWidget) -> Bool {
  match self.agent_feedback_input_contribution() {
    Some({ widget: Some(widget), .. }) => widget.has_text()
    _ => false
  }
}

///|
/// `_hide` (+ the `_hideAndRefocusEditor` variant the add/cancel paths use:
/// the refocus suppresses the selection re-evaluation once).
fn CodeEditorWidget::hide_agent_feedback_input(
  self : CodeEditorWidget,
  refocus_editor~ : Bool,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  if !ic.visible {
    return
  }
  ic.visible = false
  ic.pinned_range = None
  ic.anchor_position = None
  match ic.widget {
    Some(widget) => {
      widget.hide()
      widget.clear_input()
    }
    None => ()
  }
  if refocus_editor {
    ic.suppress_selection_change_once = true
    self.focus()
  }
}

///|
/// `_autoHide`: never discard a draft.
fn CodeEditorWidget::auto_hide_agent_feedback_input(
  self : CodeEditorWidget,
) -> Unit {
  if self.agent_feedback_has_draft() {
    return
  }
  self.hide_agent_feedback_input(refocus_editor=false)
}

///|
fn CodeEditorWidget::focus_agent_feedback_input(
  self : CodeEditorWidget,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  if ic.visible {
    match ic.widget {
      Some(widget) => widget.focus_input()
      None => ()
    }
  }
}

// --- submit ---------------------------------------------------------------------------

///|
/// `_addFeedback` / `_addFeedbackAndSubmit`: store the draft over the pinned
/// range (falling back to the live selection like upstream), then hide and
/// refocus. The submit arm marks the accepted items submitted; the host
/// reacts to the service's submit event (the chat hand-off upstream drives
/// here stays outside the viewer).
fn CodeEditorWidget::add_agent_feedback_from_input(
  self : CodeEditorWidget,
  submit~ : Bool,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  guard ic.widget is Some(widget) else { return }
  let text = widget.value().trim().to_owned()
  if text.is_empty() {
    return
  }
  let range = match ic.pinned_range {
    Some(range) => Some(range)
    None =>
      match self.get_selection() {
        Some(selection) =>
          Some(
            Range(
              selection.start().line_number,
              selection.start().column,
              selection.end().line_number,
              selection.end().column,
            ),
          )
        None => None
      }
  }
  guard range is Some(range) && self.get_model() is Some(model) else { return }
  let service = self.services.agent_feedback
  service.add_feedback(model.uri, range, text) |> ignore
  self.hide_agent_feedback_input(refocus_editor=true)
  if submit {
    service.mark_feedback_submitted(model.uri)
  }
}

// --- positioning ----------------------------------------------------------------------

///|
/// `_updatePosition` + `_getPositioningTarget`: anchor at the pinned
/// position (or the live selection's active end), prefer below/above by the
/// selection direction, flip when out of bounds, clamp into the editor and
/// right of the gutter.
fn CodeEditorWidget::update_agent_feedback_input_position(
  self : CodeEditorWidget,
) -> Unit {
  guard self.agent_feedback_input_contribution() is Some(ic) else { return }
  guard ic.widget is Some(widget) && ic.visible else { return }
  let target : (@base_common.Position, Bool)? = match
    (ic.pinned_range, ic.anchor_position) {
    (Some(_), Some(anchor)) => Some((anchor, ic.prefer_below))
    _ =>
      match self.get_selection() {
        Some(selection) =>
          if selection.is_empty() {
            None
          } else {
            let prefer_below = selection.direction() == LTR
            let anchor = if prefer_below {
              selection.end()
            } else {
              selection.start()
            }
            Some((anchor, prefer_below))
          }
        None => None
      }
  }
  guard target is Some((anchor, prefer_below)) else {
    self.auto_hide_agent_feedback_input()
    return
  }
  guard self.get_scrolled_visible_position(anchor) is Some(scrolled) else {
    return
  }
  let layout = self.get_layout_info()
  let widget_height = widget.measured_height()
  let widget_width = widget.measured_width()
  let line_height = scrolled.height
  let mut top = if prefer_below {
    // Cursor at the selection's bottom → below the line, flipping above
    // when out of space.
    let below = scrolled.top + line_height
    if below + widget_height > layout.height {
      scrolled.top - widget_height
    } else {
      below
    }
  } else {
    // Cursor at the selection's top → above the line, flipping below.
    let above = scrolled.top - widget_height
    if above < 0.0 {
      scrolled.top + line_height
    } else {
      above
    }
  }
  // Clamp vertically into the editor.
  let max_top = layout.height - widget_height
  if top > max_top {
    top = max_top
  }
  if top < 0.0 {
    top = 0.0
  }
  // Clamp horizontally: never over the gutter, never past the right edge.
  let min_left = layout.content_left
  let mut max_left = layout.width - widget_width
  if max_left < min_left {
    max_left = min_left
  }
  let mut left = scrolled.left
  if left < min_left {
    left = min_left
  }
  if left > max_left {
    left = max_left
  }
  widget.set_position(top, left)
}
