///|
fn CodeEditorWidget::editor_context(
  self : CodeEditorWidget,
) -> @hover_browser.EditorContext {
  let (mouse_posx, mouse_posy) = match self.content_hover_controller() {
    Some(hc) => (Some(hc.hover_mouse_posx), Some(hc.hover_mouse_posy))
    None => (None, None)
  }
  {
    view_model: self.get_view_model(),
    // The wrapper's `_participants` for the `suggestHoverAnchor` pass;
    // participants are stateless captures of the services, so a per-dispatch
    // build matches Monaco's per-editor set observably.
    participants: self.make_hover_computer().participants(),
    typical_halfwidth_character_width: self.configuration.snapshot().font_info.typical_halfwidth_character_width,
    mouse_posx,
    mouse_posy,
    show_at_position: self
    .content_hover_contribution()
    .bind(state => state.widget)
    .bind(widget => widget.rendered_hover)
    .map(rendered => rendered.show_at_position),
    content_hover_visible: self.content_hover_visible(),
  }
}

///|
/// The live content-hover state for this editor. This is the one typed view
/// over the central contribution wrapper; controller, widget/cache, and host
/// scheduling callers all resolve through it.
fn CodeEditorWidget::content_hover_contribution(
  self : CodeEditorWidget,
) -> ContentHoverContributionState? {
  match self.contributions.lookup("editor.contrib.contentHover") {
    Some(entry) =>
      match entry.instance {
        ContentHover(state) => Some(state)
        _ => None
      }
    _ => None
  }
}

///|
/// The live hover controller instance for this editor — the central-registry
/// equivalent of Monaco's `ContentHoverController.get(editor)`
/// (`contentHoverController.ts`). `None` after the contribution disposed.
fn CodeEditorWidget::content_hover_controller(
  self : CodeEditorWidget,
) -> @hover_browser.ContentHoverController? {
  self.content_hover_contribution().map(state => state.controller)
}

///|
/// Monaco `ContentHoverController._onEditorMouseMove`. Records the move; keeps
/// the current hover (cancelling the reaction) when the pointer is on it
/// (sticky) or keep-open is set; gives a visible sticky hover the `hidingDelay`
/// grace period — so the pointer can travel onto the widget without it closing —
/// before reacting; otherwise reacts immediately. The grace runner mirrors
/// Monaco's "only schedule when not already scheduled". `posx` / `posy` are read
/// from the last recorded pointer position (`record_hover_pointer`).
fn CodeEditorWidget::on_editor_mouse_move(
  self : CodeEditorWidget,
  target : @editor_browser.MouseTarget,
) -> Unit {
  // The public `onMouseMove` fired already (`emit_mouse_move`); this is the
  // hover controller's subscription body. `target` is model-space.
  guard self.content_hover_contribution() is Some(state) else { return }
  let hc = state.controller
  if hc.hover_ignore_mouse_events {
    return
  }
  hc.hover_pending_target = Some(target)
  let mouse_on_widget = self.mouse_on_hover_widget(
    hc.hover_mouse_posx,
    hc.hover_mouse_posy,
  )
  if @hover.should_keep_current_hover(
      hc.hover_keep_open,
      hc.hover_settings.sticky,
      mouse_on_widget,
    ) {
    hc.cancel_react()
    return
  }
  if @hover.should_reschedule_hover(
      self.content_hover_visible(),
      hc.hover_settings.sticky,
      hc.hover_settings.hiding_delay,
    ) {
    if !hc.hover_react_pending {
      hc.hover_react_pending = true
      let token = hc.hover_react_token
      hc.install_react_timer(
        (state.schedule_timeout)(
          () => {
            if hc.hover_react_pending && token == hc.hover_react_token {
              // Monaco `_reactToEditorMouseMoveRunner` fires `_reactToEditorMouseMove`,
              // so the deferred reaction re-gates `shouldShowHover` and the
              // sticky mouse-getting-closer keep, not just the bare dispatch.
              hc.hover_react_pending = false
              self.react_to_editor_mouse_move()
            }
          },
          hc.hover_settings.hiding_delay,
        ),
      )
    }
    return
  }
  self.react_to_editor_mouse_move()
}

///|
/// Monaco `ContentHoverController._reactToEditorMouseMove`: when the hover may be
/// shown for this pointer (`shouldShowHover` — always true for the default
/// `enabled: 'on'`), drive the show-or-update path (Monaco's `showsOrWillShow`,
/// here the `MouseMoved` → `start_delayed` arm, which clears when the pointer is
/// off any token); otherwise, unless the dev sticky flag is set, hide.
fn CodeEditorWidget::react_to_editor_mouse_move(
  self : CodeEditorWidget,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  if @hover.should_show_hover(
      hc.hover_settings.enabled,
      @hover.hover_multi_cursor_modifier,
      hc.hover_last_modifiers,
    ) {
    // The sticky mouse-getting-closer keep + insist-update is decided inside the
    // controller's `_startShowingOrUpdateHover`; `run_hover_react` measures the
    // signal and passes it through.
    self.run_hover_react()
    return
  }
  if @hover.hover_sticky_debug {
    return
  }
  self.hide_content_hover()
}

///|
/// Records the latest pointer client position and modifier flags so the
/// controller handlers — which run from the pointer-handler seam that only
/// carries a hit target — can evaluate `_isMouseOnContentHoverWidget` and
/// `shouldShowHover`. Called by the input bridge before dispatching the move.
fn CodeEditorWidget::record_hover_pointer(
  self : CodeEditorWidget,
  posx : Double,
  posy : Double,
  modifiers : @hover.EventModifiers,
) -> Unit {
  match self.content_hover_controller() {
    Some(hc) => hc.record_pointer(posx, posy, modifiers)
    None => ()
  }
}

///|
/// Reacts to the latest mouse position, dispatching it as a `MouseMoved` event.
/// The sticky mouse-getting-closer signal (Monaco `isHoverSticky &&
/// isMouseGettingCloser`) is measured here — the one point that reacts to a
/// move — and threaded into the controller, which owns the keep/insist-update.
fn CodeEditorWidget::run_hover_react(self : CodeEditorWidget) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  hc.hover_react_pending = false
  match hc.hover_pending_target {
    Some(target) => {
      let sticky_mouse_getting_closer = hc.hover_settings.sticky &&
        self.hover_mouse_getting_closer()
      self.dispatch_editor_event(
        MouseMoved(target),
        sticky_mouse_getting_closer~,
      )
    }
    None => ()
  }
}

///|
/// Cancels any deferred mouse-move reaction (Monaco's
/// `_reactToEditorMouseMoveRunner.cancel()`).
fn CodeEditorWidget::cancel_hover_react(self : CodeEditorWidget) -> Unit {
  match self.content_hover_controller() {
    Some(hc) => hc.cancel_react()
    None => ()
  }
}

///|
/// The pointer is on the hover widget: keep the current hover and drop any
/// pending hide. Monaco's `_shouldKeepCurrentHover` short-circuit when the mouse
/// is over the content hover widget.
fn CodeEditorWidget::keep_hover_open(self : CodeEditorWidget) -> Unit {
  self.cancel_hover_react()
}

///|
/// Hides the hover and drops any deferred mouse-move reaction, so a stale
/// pending target cannot re-open it after an imperative dismiss (mouse-down,
/// fold toggle, model reset, Escape). Monaco's `hideContentHover()` pairs with
/// `_cancelScheduler()`. Callers own their own re-render.
fn CodeEditorWidget::dismiss_hover(self : CodeEditorWidget) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  hc.cancel_react()
  hc.cancel_operation_timers()
  hc.cancel_request()
  hc.hover = hc.hover.cleared()
  // Callers own their re-render, but the widget reconciliation must not wait
  // on one (idempotent; the imperative dismiss paths bypass
  // `after_hover_transition`).
  self.sync_content_hover_widget()
}

///|
/// Monaco `ContentHoverController.hideContentHover`: the dev sticky kill-switch
/// (and the inline-completion dropdown guard, N-A here) suppress hiding;
/// otherwise the widget hides. Wraps `dismiss_hover` with the repaint the
/// imperative callers would otherwise own.
fn CodeEditorWidget::hide_content_hover(self : CodeEditorWidget) -> Unit {
  if @hover.hover_sticky_debug {
    return
  }
  // `InlineSuggestionHintsContentWidget.dropDownVisible` guard is N-A — the
  // viewer has no inline-completion hints widget.
  guard self.content_hover_controller() is Some(hc) else { return }
  let before = hc.hover
  self.dismiss_hover()
  // `dismiss_hover` must always rotate the operation token and cancel pending
  // work, but an invisible-to-invisible cancellation has no render input or
  // DOM change. In particular, ordinary cursor mouse-down must not request a
  // frame solely because `HoverOperation.cancel()` advanced its generation.
  if before.view is Some(_) {
    self.after_hover_transition(before)
  }
}

///|
/// Monaco `ContentHoverController._isMouseOnContentHoverWidget`: whether the
/// pointer at client `(posx, posy)` is within the hover widget's box (false when
/// no widget exists or it is hidden). The widget is measured with
/// `getBoundingClientRect`, so the coordinates are client-space (see the
/// plan's Deviations on client- vs page).
fn CodeEditorWidget::mouse_on_hover_widget(
  self : CodeEditorWidget,
  posx : Double,
  posy : Double,
) -> Bool {
  guard self.content_hover_contribution() is Some(state) else { return false }
  guard state.widget is Some(widget) else { return false }
  guard widget.is_visible() else { return false }
  let rect = widget.wrapper.get_bounding_client_rect()
  @hover.mouse_within_element(
    rect.get_left(),
    rect.get_top(),
    rect.get_width(),
    rect.get_height(),
    posx,
    posy,
  )
}

///|
/// Monaco `ContentHoverWidget.isMouseGettingCloser`: whether the last recorded
/// pointer is approaching the hover widget rectangle (false when no hover is
/// rendered — the source's `!this._renderedHover` guard). Measures the widget
/// with `getBoundingClientRect`, so the recorded client pointer and the
/// rectangle are both client-space.
fn CodeEditorWidget::hover_mouse_getting_closer(
  self : CodeEditorWidget,
) -> Bool {
  guard self.content_hover_contribution() is Some(state) else { return false }
  let hc = state.controller
  guard state.widget is Some(widget) else { return false }
  guard widget.is_visible() else { return false }
  let rect = widget.wrapper.get_bounding_client_rect()
  hc.hover_mouse_closer.is_mouse_getting_closer(
    hc.hover_mouse_posx,
    hc.hover_mouse_posy,
    rect.get_left(),
    rect.get_top(),
    rect.get_width(),
    rect.get_height(),
  )
}

///|
/// Monaco `ContentHoverController._onEditorMouseDown`: a press that is not on the
/// hover widget hides it; a press on it keeps it. Accepted presses set the
/// controller's down-state before that decision, and mouse-up clears it.
fn CodeEditorWidget::on_editor_mouse_down(
  self : CodeEditorWidget,
  posx : Double,
  posy : Double,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  if hc.hover_ignore_mouse_events {
    return
  }
  hc.hover_is_mouse_down = true
  if @hover.should_keep_hover_widget_visible(
      self.mouse_on_hover_widget(posx, posy),
    ) {
    return
  }
  self.hide_content_hover()
}

///|
/// Monaco `_onEditorMouseUp`: an accepted release retires the down-state used
/// by hover-retention predicates; ignored mouse input leaves it unchanged.
fn CodeEditorWidget::on_editor_mouse_up(self : CodeEditorWidget) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  if hc.hover_ignore_mouse_events {
    return
  }
  hc.hover_is_mouse_down = false
}

///|
/// Monaco `ContentHoverController._onEditorMouseLeave`: with mouse events not
/// ignored and keep-open unset, cancel the scheduler and hide — unless the
/// pointer is still on the widget (or the dev sticky flag is set).
fn CodeEditorWidget::on_editor_mouse_leave(
  self : CodeEditorWidget,
  posx : Double,
  posy : Double,
) -> Unit {
  // The public `onMouseLeave` fired already (`emit_mouse_leave`).
  guard self.content_hover_controller() is Some(hc) else { return }
  if hc.hover_ignore_mouse_events {
    return
  }
  if hc.hover_keep_open {
    return
  }
  hc.cancel_react()
  if @hover.should_keep_hover_widget_visible(
      self.mouse_on_hover_widget(posx, posy),
    ) {
    return
  }
  if @hover.hover_sticky_debug {
    return
  }
  self.hide_content_hover()
}

///|
/// Monaco `ContentHoverController._onEditorScrollChanged`: a vertical or
/// horizontal editor scroll hides the hover (unless mouse events are ignored).
fn CodeEditorWidget::on_editor_scroll_changed(
  self : CodeEditorWidget,
  change : @view_layout.ScrollChange,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  if hc.hover_ignore_mouse_events {
    return
  }
  if change.top_changed || change.left_changed {
    self.hide_content_hover()
  }
}

///|
/// Fans one editor event to every controller in a fixed order and applies
/// their effects; the contribution model with imperative sub-updates.
/// Hover is the only controller today.
fn CodeEditorWidget::dispatch_editor_event(
  self : CodeEditorWidget,
  event : @hover_browser.EditorEvent,
  sticky_mouse_getting_closer? : Bool = false,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  // Escape hides immediately and must drop any deferred mouse-move reaction so a
  // stale target cannot re-open the hover.
  match event {
    EscapePressed => hc.cancel_react()
    MouseMoved(_) => ()
  }
  let before = hc.hover
  let (effect, hover) = @hover_browser.hover_on_event(
    hc.hover,
    event,
    self.editor_context(),
    sticky_mouse_getting_closer~,
  )
  hc.hover = hover
  if before.operation.token != hover.operation.token {
    hc.cancel_operation_timers()
    hc.cancel_request()
  }
  self.apply_hover_effect(effect)
  self.after_hover_transition(before)
}

///|
/// Repaints after a hover transition and reconciles the persistent hover
/// widget (Monaco `_setCurrentResult` → `_showHover`/`_hideHover`). The hover
/// highlight is baked into the line HTML as a span decoration, so a changed
/// hover view also invalidates the rendered lines.
fn CodeEditorWidget::after_hover_transition(
  self : CodeEditorWidget,
  before : @hover.HoverController,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  if before == hc.hover {
    return
  }
  if before.view != hc.hover.view {
    // A new hover view is a fresh `RenderedContentHover`: reset the
    // mouse-getting-closer reference so the next move re-seeds it.
    hc.hover_mouse_closer.reset()
  }
  self.sync_content_hover_widget()
  self.schedule_render()
}

///|
fn new_hover_cancellation_source() -> @language.CancellationTokenSource {
  CancellationTokenSource(schedule=callback => {
    @base_browser.schedule_timeout(callback, 0)
  })
}

///|
/// Interprets a hover transition. Monaco's `@hover.HoverOperation.start(Delayed)`
/// schedules only the async trigger and the loading message up front; the sync
/// trigger is scheduled by the async trigger (see `hover_trigger_async`).
fn CodeEditorWidget::apply_hover_effect(
  self : CodeEditorWidget,
  effect : @hover.HoverEffect,
) -> Unit {
  match effect {
    HoverNoEffect => ()
    HoverScheduleDelayed(token) => {
      guard self.content_hover_contribution() is Some(state) else { return }
      let hc = state.controller
      guard self.get_model() is Some(model) else { return }
      guard hc.hover.operation.options is Some(options) else { return }
      let source = new_hover_cancellation_source()
      hc.begin_request(source, token)
      let request = hc.hover.request_stamp(model, source.token())
      let (async_generation, async_debouncer) = hc.hover_async_debouncer.schedule(
        options,
        delay_ms=@hover.hover_first_wait_ms,
      )
      hc.hover_async_debouncer = async_debouncer
      hc.install_async_timer(
        (state.schedule_timeout)(
          () => {
            let (latest, debouncer) = hc.hover_async_debouncer.take(
              async_generation,
            )
            hc.hover_async_debouncer = debouncer
            if latest is Some(_) {
              self.hover_trigger_async(request)
            }
          },
          @hover.hover_first_wait_ms,
        ),
      )
      let (loading_generation, loading_debouncer) = hc.hover_loading_debouncer.schedule(
        options,
        delay_ms=@hover.hover_loading_message_ms,
      )
      hc.hover_loading_debouncer = loading_debouncer
      hc.install_loading_timer(
        (state.schedule_timeout)(
          () => {
            let (latest, debouncer) = hc.hover_loading_debouncer.take(
              loading_generation,
            )
            hc.hover_loading_debouncer = debouncer
            if latest is Some(_) {
              self.hover_trigger_loading(request)
            }
          },
          @hover.hover_loading_message_ms,
        ),
      )
    }
    HoverRunAsyncAndSync(token) => {
      guard self.content_hover_controller() is Some(hc) else { return }
      guard self.get_model() is Some(model) else { return }
      let source = new_hover_cancellation_source()
      hc.begin_request(source, token)
      let request = hc.hover.request_stamp(model, source.token())
      self.kick_hover_async(request)
      self.hover_trigger_sync(request)
    }
  }
}

///|
/// Programmatic wrapper entry matching `startShowingAtRange`: constructs the
/// priority-zero range anchor and forwards mode, source, and focus unchanged.
fn CodeEditorWidget::start_showing_hover_at_range(
  self : CodeEditorWidget,
  range : @base_common.Range,
  mode : @hover.HoverStartMode,
  source : @hover.HoverStartSource,
  should_focus : Bool,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  let before = hc.hover
  let (effect, hover) = hc.hover.start_showing_or_update_hover(
    HoverRangeAnchor(
      priority=0,
      range~,
      initial_mouse_pos_x=None,
      initial_mouse_pos_y=None,
    ),
    false,
    mode~,
    source~,
    should_focus~,
    live_widget_visible=self.content_hover_visible(),
  )
  hc.hover = hover
  if before.operation.token != hover.operation.token {
    hc.cancel_operation_timers()
    hc.cancel_request()
  }
  self.apply_hover_effect(effect)
  self.after_hover_transition(before)
}

///|
/// Monaco `_triggerAsyncComputation` fired (at `hover_first_wait_ms`): advance
/// the operation to `SecondWait`, schedule the sync compute at
/// `hover_second_wait_ms`, and kick the streamed async compute. No view changes
/// yet (emission is still suppressed), so no re-render is needed here.
fn CodeEditorWidget::hover_trigger_async(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Unit {
  guard self.content_hover_contribution() is Some(state) else { return }
  let hc = state.controller
  let (proceed, hover) = hc.hover.op_trigger_async_request(
    request,
    self.get_model(),
    hc.hover.operation.token,
  )
  hc.hover = hover
  if proceed {
    guard hc.hover.operation.options is Some(options) else { return }
    let (sync_generation, sync_debouncer) = hc.hover_sync_debouncer.schedule(
      options,
      delay_ms=@hover.hover_second_wait_ms,
    )
    hc.hover_sync_debouncer = sync_debouncer
    hc.install_sync_timer(
      (state.schedule_timeout)(
        () => {
          let (latest, debouncer) = hc.hover_sync_debouncer.take(
            sync_generation,
          )
          hc.hover_sync_debouncer = debouncer
          if latest is Some(_) {
            self.hover_trigger_sync(request)
          }
        },
        @hover.hover_second_wait_ms,
      ),
    )
    self.kick_hover_async(request)
  }
}

///|
/// Monaco `_triggerSyncComputation` fired (at the full delay): run the sync
/// participants and feed their parts into the operation.
fn CodeEditorWidget::hover_trigger_sync(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  let before = hc.hover
  hc.hover = hc.hover.op_trigger_sync_request(
    request,
    self.get_model(),
    hc.hover.operation.token,
    self.compute_hover_sync(request),
  )
  self.after_hover_transition(before)
  self.maybe_notify_hover_resolved(request)
}

///|
/// Monaco `_triggerLoadingMessage` fired (at three times the delay): show the
/// loading message if the async compute is still pending.
fn CodeEditorWidget::hover_trigger_loading(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  let before = hc.hover
  hc.hover = hc.hover.op_trigger_loading_request(
    request,
    self.get_model(),
    hc.hover.operation.token,
  )
  self.after_hover_transition(before)
}

///|
/// Builds a content-hover computer over the current viewer services (Monaco
/// `ContentHoverWidgetWrapper._initializeHoverParticipants`).
fn CodeEditorWidget::make_hover_computer(
  self : CodeEditorWidget,
) -> @hover.ContentHoverComputer {
  let services : @hover.HoverParticipantServices = {
    languages: self.services.languages,
    marker_decorations: self.services.marker_decorations,
  }
  ContentHoverComputer(services)
}

///|
/// Runs the synchronous hover participants for the current anchor.
fn CodeEditorWidget::compute_hover_sync(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Array[@hover.HoverPart] {
  guard self.content_hover_controller() is Some(hc) else { return [] }
  match (self.get_model(), hc.hover.anchor) {
    (Some(model), Some(anchor)) =>
      if !request.is_current(Some(model), hc.hover.operation.token) {
        []
      } else {
        match self.make_hover_computer().compute_sync(model, anchor) {
          Some(hover) => hover.parts
          None => []
        }
      }
    _ => []
  }
}

///|
/// Kicks the streamed async hover compute (Monaco `computeAsync`): each
/// participant's parts are fed to the operation as they resolve, then the
/// operation is marked done. Results carry the requesting model and anchor token
/// so stale responses are dropped at their guards.
fn CodeEditorWidget::kick_hover_async(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Unit {
  guard self.content_hover_contribution() is Some(state) else { return }
  let hc = state.controller
  match hc.hover.anchor {
    Some(anchor) => {
      let computer = self.make_hover_computer()
      (state.launch_async_task)(() => {
        computer.compute_async_each(
          request.model(),
          anchor,
          token=request.cancellation_token(),
          is_current=() => self.is_current_hover_request(request),
          run_tasks=run_async_tasks_concurrently,
          emit=parts => self.hover_async_item(request, parts),
        )
        self.hover_async_done(request)
      })
    }
    _ => ()
  }
}

///|
fn CodeEditorWidget::hover_async_item(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
  parts : Array[@hover.HoverPart],
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  let before = hc.hover
  hc.hover = hc.hover.op_async_item_request(
    request,
    self.get_model(),
    hc.hover.operation.token,
    parts,
  )
  self.after_hover_transition(before)
}

///|
fn CodeEditorWidget::hover_async_done(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  let before = hc.hover
  hc.hover = hc.hover.op_async_done_request(
    request,
    self.get_model(),
    hc.hover.operation.token,
  )
  self.after_hover_transition(before)
  self.maybe_notify_hover_resolved(request)
}

///|
fn CodeEditorWidget::is_current_hover_request(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Bool {
  if self.disposed {
    return false
  }
  match self.content_hover_controller() {
    Some(hc) => request.is_current(self.get_model(), hc.hover.operation.token)
    None => false
  }
}

///|
/// Fires the public hover-resolution status exactly once per anchor, when the
/// operation completes (reaches `Idle`): `ok` reports whether any hover content
/// was produced. Replaces the old per-result notification.
fn CodeEditorWidget::maybe_notify_hover_resolved(
  self : CodeEditorWidget,
  request : @hover.HoverRequestStamp,
) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  let token = request.generation()
  if !request.is_current(self.get_model(), hc.hover.operation.token) ||
    !hc.hover.is_complete() {
    return
  }
  if hc.hover_notified_token == token {
    return
  }
  hc.cancel_operation_timers()
  hc.finish_request(token)
  hc.hover_notified_token = token
  let revision = match self.get_model() {
    Some(model) => model.revision
    None => ""
  }
  self.emit_hover_resolved({ ok: hc.hover.view is Some(_), revision, })
}

///|
/// Syncs the hover highlight into the model's decoration storage (Monaco's
/// hover-owned decorations collection: `delta_decorations` on show/hide).
/// Runs at flush time — every hover state change schedules a flush.
fn CodeEditorWidget::sync_hover_decorations(self : CodeEditorWidget) -> Unit {
  guard self.content_hover_controller() is Some(hc) else { return }
  guard self.get_model() is Some(model) else { return }
  let decorations = hc.hover.highlight_decorations()
  let range = match decorations {
    [decoration, ..] => Some(decoration.range)
    [] => None
  }
  if range == hc.hover_decoration_range {
    return
  }
  hc.hover_decoration_range = range
  hc.hover_decoration_ids = model.delta_decorations(
    hc.hover_decoration_ids,
    decorations,
    owner_id=self.editor_id,
  )
}

///|
fn CodeEditorWidget::is_current_model(
  self : CodeEditorWidget,
  model : @model.TextModel,
) -> Bool {
  match self.get_model() {
    Some(current) => current.same(model)
    None => false
  }
}
