///|
/// Monaco `ContentHoverController` (`contentHoverController.ts`): the
/// per-editor hover feature state, stored by the owning Viewer's central
/// contribution registry. The `Viewer::` dispatch glue remains in
/// `editor_events.mbt` because it reads private Viewer state and owns the
/// editor-event, timer, provider, decoration, and widget lifecycles. It
/// reads/writes state here through the root package's typed central accessor,
/// without making this internal package depend on the root Viewer.
pub(all) struct ContentHoverController {
  /// The shown-hover state machine (anchor, operation, derived view).
  mut hover : @hover.HoverController
  /// Mouse-move grace state (Monaco's `_reactToEditorMouseMoveRunner`):
  /// while a hover widget is on screen, a move off the anchor is deferred by
  /// `hiding_delay` instead of reacting immediately, so the pointer can
  /// reach the widget. `hover_react_token` invalidates a deferred reaction
  /// the pointer cancelled by entering the widget.
  mut hover_react_pending : Bool
  mut hover_react_token : Int32
  mut hover_pending_target : @editor_browser.MouseTarget?
  /// Clearable handle for the delayed mouse reaction. The generation guard is
  /// retained for dispatch races, but ordinary cancellation clears the host
  /// timer instead of leaving it alive.
  priv mut hover_react_timer : @base_common.Disposable?
  /// Clearable operation timers, owned by this Viewer-lifetime controller.
  priv mut hover_async_timer : @base_common.Disposable?
  priv mut hover_sync_timer : @base_common.Disposable?
  priv mut hover_loading_timer : @base_common.Disposable?
  /// Source-shaped latest-options debouncers paired with the three owned
  /// browser handles above.
  mut hover_async_debouncer : @hover.HoverDebouncer
  mut hover_sync_debouncer : @hover.HoverDebouncer
  mut hover_loading_debouncer : @hover.HoverDebouncer
  /// Viewer-lifetime async request generation/source. Model swaps and content
  /// invalidation advance the generation; it never resets while the
  /// contribution remains attached.
  priv mut hover_request_generation : Int32
  priv mut hover_request_source : @language.CancellationTokenSource?
  /// Accepted editor mouse-down state, cleared by the corresponding mouse-up.
  mut hover_is_mouse_down : Bool
  /// The `editor.hover` snapshot (`_hoverSettings`).
  hover_settings : @hover.HoverSettings
  /// `shouldKeepOpenOnEditorMouseMoveOrLeave`.
  mut hover_keep_open : Bool
  /// `_ignoreMouseEvents`: suppresses every handler while a context menu is
  /// up.
  mut hover_ignore_mouse_events : Bool
  /// The last pointer client position + modifiers (`_mouseMoveEvent`), so
  /// `_isMouseOnContentHoverWidget` / `shouldShowHover` can be evaluated
  /// where the controller reacts (the pointer-handler seam only carries a
  /// hit target).
  mut hover_mouse_posx : Double
  mut hover_mouse_posy : Double
  mut hover_last_modifiers : @hover.EventModifiers
  /// Monaco `RenderedContentHover`'s mouse-getting-closer state
  /// (`isMouseGettingCloser`): reset whenever a new hover view is shown, so
  /// a sticky hover the pointer is approaching is kept open even off the
  /// anchor token.
  hover_mouse_closer : @hover.MouseCloserState
  /// The last anchor token for which the public hover-resolution status
  /// fired, so it fires exactly once per anchor when the operation completes.
  mut hover_notified_token : Int32
  /// The hover highlight's model decoration ids (the hover-owned decorations
  /// collection): rewritten whenever the hover view's highlighted range
  /// changes.
  mut hover_decoration_ids : Array[String]
  mut hover_decoration_range : @base_common.Range?
}

///|
/// Constructs the bare controller for one editor — the contribution-ctor half
/// of Monaco's
/// `registerEditorContribution(ContentHoverController.ID, …)`.
pub fn ContentHoverController::ContentHoverController() -> ContentHoverController {
  {
    hover: @hover.HoverController::empty(),
    hover_react_pending: false,
    hover_react_token: 0,
    hover_pending_target: None,
    hover_react_timer: None,
    hover_async_timer: None,
    hover_sync_timer: None,
    hover_loading_timer: None,
    hover_async_debouncer: HoverDebouncer(),
    hover_sync_debouncer: HoverDebouncer(),
    hover_loading_debouncer: HoverDebouncer(),
    hover_request_generation: 0,
    hover_request_source: None,
    hover_is_mouse_down: false,
    hover_settings: @hover.HoverSettings::defaults(),
    hover_keep_open: false,
    hover_ignore_mouse_events: false,
    hover_mouse_posx: 0.0,
    hover_mouse_posy: 0.0,
    hover_last_modifiers: @hover.EventModifiers::none(),
    hover_mouse_closer: MouseCloserState(),
    hover_notified_token: 0,
    hover_decoration_ids: [],
    hover_decoration_range: None,
  }
}

///|
/// Replaces the current request owner, canceling and disposing the previous
/// source before recording the supplied operation generation.
pub fn ContentHoverController::begin_request(
  self : ContentHoverController,
  source : @language.CancellationTokenSource,
  generation : Int32,
) -> Unit {
  match self.hover_request_source {
    Some(previous) => previous.dispose(cancel=true)
    None => ()
  }
  self.hover_request_generation = generation
  self.hover_request_source = Some(source)
}

///|
/// Cancels and retires the current request source. Repeated calls are harmless;
/// the caller rotates the hover operation generation separately.
pub fn ContentHoverController::cancel_request(
  self : ContentHoverController,
) -> Unit {
  match self.hover_request_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  self.hover_request_source = None
}

///|
/// Releases listener ownership for a successfully completed current request.
/// A stale completion cannot retire a newer source.
pub fn ContentHoverController::finish_request(
  self : ContentHoverController,
  generation : Int32,
) -> Unit {
  if self.hover_request_generation != generation {
    return
  }
  match self.hover_request_source {
    Some(source) => source.dispose()
    None => ()
  }
  self.hover_request_source = None
}

///|
fn dispose_timer(timer : @base_common.Disposable?) -> Unit {
  match timer {
    Some(timer) => timer.dispose()
    None => ()
  }
}

///|
/// Replaces the owned mouse-reaction handle, disposing the old handle first.
pub fn ContentHoverController::install_react_timer(
  self : ContentHoverController,
  timer : @base_common.Disposable,
) -> Unit {
  dispose_timer(self.hover_react_timer)
  self.hover_react_timer = Some(timer)
}

///|
/// Replaces the owned first-wait handle, disposing the old handle first.
pub fn ContentHoverController::install_async_timer(
  self : ContentHoverController,
  timer : @base_common.Disposable,
) -> Unit {
  dispose_timer(self.hover_async_timer)
  self.hover_async_timer = Some(timer)
}

///|
/// Replaces the owned second-wait handle, disposing the old handle first.
pub fn ContentHoverController::install_sync_timer(
  self : ContentHoverController,
  timer : @base_common.Disposable,
) -> Unit {
  dispose_timer(self.hover_sync_timer)
  self.hover_sync_timer = Some(timer)
}

///|
/// Replaces the owned loading-message handle, disposing the old handle first.
pub fn ContentHoverController::install_loading_timer(
  self : ContentHoverController,
  timer : @base_common.Disposable,
) -> Unit {
  dispose_timer(self.hover_loading_timer)
  self.hover_loading_timer = Some(timer)
}

///|
/// Clears all operation handles and invalidates each latest-options debouncer.
pub fn ContentHoverController::cancel_operation_timers(
  self : ContentHoverController,
) -> Unit {
  dispose_timer(self.hover_async_timer)
  dispose_timer(self.hover_sync_timer)
  dispose_timer(self.hover_loading_timer)
  self.hover_async_timer = None
  self.hover_sync_timer = None
  self.hover_loading_timer = None
  self.hover_async_debouncer = self.hover_async_debouncer.cancel()
  self.hover_sync_debouncer = self.hover_sync_debouncer.cancel()
  self.hover_loading_debouncer = self.hover_loading_debouncer.cancel()
}

///|
/// Clears mouse reaction and operation handles in one idempotent teardown.
pub fn ContentHoverController::cancel_all_timers(
  self : ContentHoverController,
) -> Unit {
  self.cancel_react()
  self.cancel_operation_timers()
}

///|
/// Cancels any deferred mouse-move reaction (Monaco's
/// `_reactToEditorMouseMoveRunner.cancel()`). Bumping the token invalidates a
/// timer that is already in flight.
pub fn ContentHoverController::cancel_react(
  self : ContentHoverController,
) -> Unit {
  dispose_timer(self.hover_react_timer)
  self.hover_react_timer = None
  self.hover_react_token += 1
  self.hover_react_pending = false
  self.hover_pending_target = None
}

///|
/// Records the latest pointer client position and modifier flags so the
/// handlers — which run from the pointer-handler seam that only carries a
/// hit target — can evaluate `_isMouseOnContentHoverWidget` and
/// `shouldShowHover`.
pub fn ContentHoverController::record_pointer(
  self : ContentHoverController,
  posx : Double,
  posy : Double,
  modifiers : @hover.EventModifiers,
) -> Unit {
  self.hover_mouse_posx = posx
  self.hover_mouse_posy = posy
  self.hover_last_modifiers = modifiers
}

///|
/// Drops the per-model decoration bookkeeping on a model swap: the ids
/// belong to the outgoing model's decoration storage.
pub fn ContentHoverController::reset_model_state(
  self : ContentHoverController,
) -> Unit {
  self.hover_decoration_ids = []
  self.hover_decoration_range = None
}
