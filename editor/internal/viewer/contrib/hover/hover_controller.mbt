///|
struct HoverView {
  range : @base_common.Range
  parts : Array[HoverPart]
} derive(Eq)

///|
/// Monaco `IHoverPart.isValidForHoverAnchor` (markdown + marker participants):
/// the part still applies to the new anchor when the anchor is a range anchor
/// and the part's range contains the anchor range (`anchor.type ===
/// HoverAnchorType.Range && startColumn <= anchor.range.startColumn &&
/// endColumn >= anchor.range.endColumn`, the source's column-only comparison).
fn hover_part_valid_for_anchor(part : HoverPart, anchor : HoverAnchor) -> Bool {
  guard anchor is HoverRangeAnchor(range=anchor_range, ..) else { return false }
  let range = hover_part_range(part)
  range.start_column <= anchor_range.start_column &&
  range.end_column >= anchor_range.end_column
}

///|
/// Monaco `ContentHoverResult.filter`: keep the parts that are still valid for
/// the new anchor.
fn filter_hover_parts(
  parts : Array[HoverPart],
  anchor : HoverAnchor,
) -> Array[HoverPart] {
  parts.filter(part => hover_part_valid_for_anchor(part, anchor))
}

///|
/// VS Code's default `editor.hover.delay`.
let hover_delay_ms = 300

///|
/// Monaco `HoverOperation` schedule offsets derived from the hover delay
/// (`hoverOperation.ts`): the async (semantic) compute is kicked at half the
/// delay, the sync (markers / decorations) compute runs after the remaining
/// half — so at the full delay — and a loading message is shown at three times
/// the delay if the async compute has not finished.
pub let hover_first_wait_ms : Int = hover_delay_ms / 2

///|
pub let hover_second_wait_ms : Int = hover_delay_ms - hover_first_wait_ms

///|
pub let hover_loading_message_ms : Int = 3 * hover_delay_ms

///|
/// VS Code's default `editor.hover.hidingDelay`: once the widget is on screen,
/// a mouse move off the anchor is debounced by this grace period before the
/// hover reacts, so the pointer can travel onto the hover widget without it
/// closing. Mirrors `ContentHoverController`'s `_reactToEditorMouseMoveRunner`
/// scheduled at `hidingDelay`.
let hover_hiding_delay_ms = 300

///|
/// Source-shaped options retained by one hover operation.
pub struct HoverOperationOptions {
  priv should_focus : Bool
  priv anchor : HoverAnchor
  source : HoverStartSource
  priv insist_on_keeping_hover_visible : Bool
} derive(Eq, Debug)

///|
/// Builds one immutable operation-options snapshot with source defaults.
fn HoverOperationOptions::HoverOperationOptions(
  anchor : HoverAnchor,
  should_focus? : Bool = false,
  source? : HoverStartSource = HoverStartMouse,
  insist_on_keeping_hover_visible? : Bool = false,
) -> HoverOperationOptions {
  { should_focus, anchor, source, insist_on_keeping_hover_visible, }
}

///|
/// Immutable request facts captured before an asynchronous hover launch. The
/// owner supplies the monotonic controller generation and cancellation token;
/// the stamp snapshots stable model identity and the internal content
/// version at construction.
struct HoverRequestStamp {
  model : @model.TextModel
  model_version_id : Int
  generation : Int
  cancellation_token : @language.CancellationToken
}

///|
/// Captures one immutable request authority at the model's current internal
/// version. Callers must retain the exact operation generation/token owner.
fn HoverRequestStamp::HoverRequestStamp(
  model : @model.TextModel,
  generation : Int,
  cancellation_token : @language.CancellationToken,
) -> HoverRequestStamp {
  {
    model,
    model_version_id: model.get_version_id(),
    generation,
    cancellation_token,
  }
}

///|
/// Returns the exact model captured by this request authority.
pub fn HoverRequestStamp::model(self : HoverRequestStamp) -> @model.TextModel {
  self.model
}

///|
/// Returns the caller-owned cancellation token captured by this request.
pub fn HoverRequestStamp::cancellation_token(
  self : HoverRequestStamp,
) -> @language.CancellationToken {
  self.cancellation_token
}

///|
/// Returns the monotonic operation generation captured by this request.
pub fn HoverRequestStamp::generation(self : HoverRequestStamp) -> Int {
  self.generation
}

///|
/// Full apply-boundary freshness predicate. URI, host version/revision, and
/// decoration IDs intentionally do not participate.
pub fn HoverRequestStamp::is_current(
  self : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
) -> Bool {
  if self.cancellation_token.is_cancellation_requested() ||
    self.generation != current_generation ||
    self.model.is_disposed() ||
    self.model.get_version_id() != self.model_version_id {
    return false
  }
  match current_model {
    Some(model) =>
      !model.is_disposed() &&
      model.same(self.model) &&
      model.get_version_id() == self.model_version_id
    None => false
  }
}

///|
/// Result snapshot emitted by the pure operation after the initial wait.
priv struct HoverResult {
  value : Array[HoverPart]
  is_complete : Bool
  options : HoverOperationOptions
}

///|
/// Host work selected by `HoverOperation::start`. Timers and computation stay
/// host-owned; this value makes every valid start-mode/state branch explicit
/// and deterministic.
priv enum HoverOperationStartEffect {
  HoverOperationNoStart
  HoverOperationScheduleDelayed(Int)
  HoverOperationRunAsyncAndSync(Int)
  HoverOperationRunSync
}

///|
/// Monaco `HoverOperationState` (`hoverOperation.ts`). `FirstWait` / `SecondWait`
/// suppress result emission — nothing shows before the hover delay; the two
/// `WaitingForAsync*` states cover the post-delay window while the async compute
/// is still in flight (the second one shows the loading message); `Idle` is the
/// complete (or quiescent) state.
priv enum HoverOpState {
  HoverOpIdle
  HoverOpFirstWait
  HoverOpSecondWait
  HoverOpWaitingForAsync
  HoverOpWaitingForAsyncShowingLoading
} derive(Eq, Debug)

///|
/// Monaco `HoverOperation`: the fine-tuned hover timing / aggregation core. It
/// is a pure state container; the viewer drives the three debounced schedulers
/// and the sync / async computes (through the browser-host timers and the
/// participant registry) and feeds their results back through the transition
/// methods. `parts` is Monaco's accumulating `_result`; `token` rotates per
/// anchor so stale timers and streamed async results are dropped at their guards
/// (the role Monaco's scheduler / iterable cancellation plays).
pub struct HoverOperation {
  priv state : HoverOpState
  token : Int
  priv parts : Array[HoverPart]
  priv async_done : Bool
  options : HoverOperationOptions?
} derive(Eq, Debug)

///|
/// Whether the current operation is displaying its delayed loading message.
/// This is the only operation-state distinction the browser host needs.
pub fn HoverOperation::shows_loading_message(self : HoverOperation) -> Bool {
  self.state is HoverOpWaitingForAsyncShowingLoading
}

///|
/// Creates an idle operation retaining the supplied monotonic generation.
fn HoverOperation::idle_at(token : Int) -> HoverOperation {
  { state: HoverOpIdle, token, parts: [], async_done: false, options: None, }
}

///|
/// Pure `HoverOperation.start`: delayed starts arm only from Idle; immediate
/// starts request async+sync from Idle, sync-only from SecondWait, and no-op in
/// every other typed state. The host interprets the returned work immediately.
fn HoverOperation::start(
  self : HoverOperation,
  mode : HoverStartMode,
  options : HoverOperationOptions,
) -> (HoverOperationStartEffect, HoverOperation) {
  match mode {
    HoverStartDelayed =>
      if self.state is HoverOpIdle {
        (
          HoverOperationScheduleDelayed(self.token),
          {
            ..self,
            state: HoverOpFirstWait,
            async_done: false,
            options: Some(options),
          },
        )
      } else {
        (HoverOperationNoStart, self)
      }
    HoverStartImmediate =>
      match self.state {
        HoverOpIdle =>
          (
            HoverOperationRunAsyncAndSync(self.token),
            {
              ..self,
              state: HoverOpSecondWait,
              async_done: false,
              options: Some(options),
            },
          )
        HoverOpSecondWait =>
          (HoverOperationRunSync, { ..self, options: Some(options), })
        _ => (HoverOperationNoStart, self)
      }
  }
}

///|
/// Mirrors `HoverOperation.cancel`: clear result/options, return to Idle, and
/// rotate the generation so dispatched callbacks cannot re-enter the operation.
fn HoverOperation::cancelled(self : HoverOperation) -> HoverOperation {
  HoverOperation::idle_at(self.token + 1)
}

///|
/// Returns the source-shaped result snapshot for observable states. Wait states
/// suppress emission; the initial Idle state has no options and no result.
fn HoverOperation::result(self : HoverOperation) -> HoverResult? {
  if self.state is HoverOpFirstWait || self.state is HoverOpSecondWait {
    return None
  }
  guard self.options is Some(options) else { return None }
  Some({
    value: self.parts.copy(),
    is_complete: self.state is HoverOpIdle,
    options,
  })
}

///|
/// Pure latest-options half of Monaco's `Debouncer`. The browser controller
/// owns the clearable timer handle; this value owns the deterministic schedule
/// generation, selected delay, and latest options read by the callback.
struct HoverDebouncer {
  default_delay_ms : Int
  generation : Int
  scheduled : Bool
  delay_ms : Int
  options : HoverOperationOptions?
} derive(Eq, Debug)

///|
/// Creates an idle latest-options debouncer with a caller-selected fallback
/// delay. Browser timer ownership remains outside this pure value.
pub fn HoverDebouncer::HoverDebouncer(
  default_delay_ms? : Int = 0,
) -> HoverDebouncer {
  {
    default_delay_ms,
    generation: 0,
    scheduled: false,
    delay_ms: default_delay_ms,
    options: None,
  }
}

///|
/// Stores the latest options before arming a new generation, exactly the
/// source's schedule order. Omitted delay selects the constructor default.
pub fn HoverDebouncer::schedule(
  self : HoverDebouncer,
  options : HoverOperationOptions,
  delay_ms? : Int = -1,
) -> (Int, HoverDebouncer) {
  let generation = self.generation + 1
  let delay_ms = if delay_ms < 0 { self.default_delay_ms } else { delay_ms }
  (
    generation,
    { ..self, generation, scheduled: true, delay_ms, options: Some(options), },
  )
}

///|
/// Cancels the scheduled generation while retaining the latest options, as
/// Monaco's debouncer does.
pub fn HoverDebouncer::cancel(self : HoverDebouncer) -> HoverDebouncer {
  { ..self, generation: self.generation + 1, scheduled: false, }
}

///|
/// Consumes the latest options only for the still-current scheduled callback.
/// A stale or canceled callback is a no-op.
pub fn HoverDebouncer::take(
  self : HoverDebouncer,
  generation : Int,
) -> (HoverOperationOptions?, HoverDebouncer) {
  if !self.scheduled || generation != self.generation {
    return (None, self)
  }
  (self.options, { ..self, scheduled: false, })
}

///|
/// What a hover transition asks the viewer to do; the controller stays a pure
/// state machine and the viewer interprets these (timers through the
/// browser-host timer bindings, computes through the hover computer).
pub(all) enum HoverEffect {
  HoverNoEffect
  /// Delayed start (Monaco `start(Delayed)`): schedule the async trigger at
  /// `hover_first_wait_ms` and the loading message at `hover_loading_message_ms`
  /// for this anchor token.
  HoverScheduleDelayed(Int)
  /// Immediate start from Idle: launch the async stream, then run the sync
  /// computer without arming the delay/loading schedulers.
  HoverRunAsyncAndSync(Int)
}

///|
/// Editor hover feature state. The timing lives in the embedded `HoverOperation`
/// (Monaco's `HoverOperation`); the controller adds the editor-facing concerns
/// the operation does not: the in-flight anchor and the currently shown result
/// (the `_currentResult` analog — its parts, the anchor it was computed for,
/// and whether it was complete). Placement (above/below, sizing) is the
/// content-hover widget's own state, as in the source
/// (`ContentHoverWidget._positionPreference`).
pub struct HoverController {
  /// Monaco `_hoverOperation.options.anchor`: the anchor the operation is
  /// currently computing for (`None` once cleared).
  anchor : HoverAnchor?
  operation : HoverOperation
  /// Monaco `ContentHoverWidgetWrapper._startHoverOperationIfNecessary`'s
  /// `insistOnKeepingHoverVisible` for the in-flight operation. Set only by the
  /// sticky mouse-getting-closer keep, which the viewer handles at the input
  /// seam, so it is currently always `false` (see the plan's Deviation 11).
  priv insist_on_keeping : Bool
  /// Monaco `_currentResult`: the shown hover parts (`view`), the anchor that
  /// produced them (`current_anchor`), and whether that result was complete
  /// (`current_complete`). `view` is `None` exactly when no hover is shown.
  view : HoverView?
  priv current_anchor : HoverAnchor?
  priv current_complete : Bool
} derive(Eq)

///|
/// Creates an idle controller with generation zero and no shown result.
pub fn HoverController::empty() -> HoverController {
  HoverController::empty_at(0)
}

///|
/// Creates an empty controller without resetting the caller-owned monotonic
/// generation. Browser/controller teardown uses this instead of reusing zero.
fn HoverController::empty_at(generation : Int) -> HoverController {
  {
    anchor: None,
    operation: HoverOperation::idle_at(generation),
    insist_on_keeping: false,
    view: None,
    current_anchor: None,
    current_complete: false,
  }
}

///|
/// Monaco `HoverOperation.cancel()` paired with hiding the widget: drop the
/// in-flight anchor and the shown result, reset the operation to Idle, and rotate
/// the token so in-flight timers and streamed async results are dropped at their
/// guards.
pub fn HoverController::cleared(self : HoverController) -> HoverController {
  {
    ..self.cancel_operation_preserving_view(),
    view: None,
    current_anchor: None,
    current_complete: false,
  }
}

///|
/// Cancels pending hover work while retaining only a complete rendered result.
/// Model-content invalidation may keep a settled hover visible, but an
/// incomplete/loading result must be cleared: after its request is cancelled it
/// can never become complete, and retaining its anchor would suppress a fresh
/// request at the same position. Every old timer/item/done callback is
/// invalidated by the rotated operation generation.
pub fn HoverController::cancel_operation_preserving_view(
  self : HoverController,
) -> HoverController {
  let cancelled = {
    ..self,
    anchor: None,
    operation: self.operation.cancelled(),
    insist_on_keeping: false,
  }
  if self.current_complete && self.view is Some(_) {
    cancelled
  } else {
    { ..cancelled, view: None, current_anchor: None, current_complete: false, }
  }
}

///|
/// Monaco `ContentHoverWidgetWrapper._startShowingOrUpdateHover`. With no hover
/// shown, start an operation for the anchor. With one shown: the sticky
/// mouse-getting-closer case keeps the current result untouched and kicks an
/// `insist`-update operation at the new anchor; the same anchor keeps the hover
/// untouched; a compatible anchor (same line) keeps the parts still valid for it
/// and kicks a fresh operation; an incompatible anchor hides the current hover
/// and restarts. `sticky_mouse_getting_closer` is computed at the input seam
/// (`sticky && isMouseGettingCloser`, both host concerns). Browser callers may
/// supply the widget's actual `show_at_position`; the union-range start is the
/// compatibility fallback for existing callers.
pub fn HoverController::start_showing_or_update_hover(
  self : HoverController,
  anchor : HoverAnchor,
  sticky_mouse_getting_closer : Bool,
  show_at_position? : @base_common.Position,
  mode? : HoverStartMode = HoverStartDelayed,
  source? : HoverStartSource = HoverStartMouse,
  should_focus? : Bool = false,
  live_widget_visible? : Bool = false,
) -> (HoverEffect, HoverController) {
  let content_hover_is_visible = live_widget_visible || self.view is Some(_)
  if !content_hover_is_visible {
    return self.start_hover_operation_if_necessary(
      anchor,
      insist=false,
      mode~,
      source~,
      should_focus~,
    )
  }
  // The pointer is approaching the shown hover: keep the current result
  // untouched and kick an operation that insists on keeping it visible.
  if sticky_mouse_getting_closer {
    return self.start_hover_operation_if_necessary(
      anchor,
      insist=true,
      mode~,
      source~,
      should_focus~,
    )
  }
  // A hover is shown. The new anchor equals the shown one: keep it untouched.
  let visible_result_anchor = match
    (self.current_anchor, self.operation.options) {
    (Some(anchor), _) => Some(anchor)
    (None, Some(options)) => Some(options.anchor)
    (None, None) => None
  }
  if visible_result_anchor is Some(current) &&
    hover_anchor_equals(current, anchor) {
    return (HoverNoEffect, self)
  }
  let compatible = match visible_result_anchor {
    Some(current) => {
      let shown_position = match (show_at_position, self.view) {
        (Some(position), _) => position
        (None, Some(view)) => view.range.get_start_position()
        (None, None) => current.range().get_start_position()
      }
      hover_anchor_can_adopt_at(anchor, current, shown_position)
    }
    None => false
  }
  if !compatible {
    // Hide the incompatible hover, then start a fresh operation.
    let hidden = self.set_current_result([], false, anchor)
    return hidden.start_hover_operation_if_necessary(
      anchor,
      insist=false,
      mode~,
      source~,
      should_focus~,
    )
  }
  // Compatible: keep the parts still valid for the new anchor (Monaco
  // `_currentResult.filter(anchor)`, which preserves the previous anchor and
  // completeness), then kick a fresh operation.
  let filtered_parts = match self.view {
    Some(view) => filter_hover_parts(view.parts, anchor)
    None => []
  }
  let result_anchor = visible_result_anchor.unwrap_or(anchor)
  let filtered = self.set_current_result(
    filtered_parts,
    self.current_complete,
    result_anchor,
  )
  filtered.start_hover_operation_if_necessary(
    anchor,
    insist=false,
    mode~,
    source~,
    should_focus~,
  )
}

///|
/// Monaco `ContentHoverWidgetWrapper._startHoverOperationIfNecessary`: skip when
/// the operation is already computing this anchor; otherwise cancel the previous
/// operation (rotating the token so its timers / async results are dropped) and
/// arm a fresh operation in the supplied mode with source/focus/options
/// retained exactly. The shown result is left untouched until new output.
fn HoverController::start_hover_operation_if_necessary(
  self : HoverController,
  anchor : HoverAnchor,
  insist~ : Bool,
  mode? : HoverStartMode = HoverStartDelayed,
  source? : HoverStartSource = HoverStartMouse,
  should_focus? : Bool = false,
) -> (HoverEffect, HoverController) {
  match self.anchor {
    Some(current) =>
      if hover_anchor_equals(current, anchor) {
        return (HoverNoEffect, self)
      }
    None => ()
  }
  let token = self.operation.token + 1
  let options = HoverOperationOptions(
    anchor,
    should_focus~,
    source~,
    insist_on_keeping_hover_visible=insist,
  )
  let (start_effect, operation) = HoverOperation::idle_at(token).start(
    mode, options,
  )
  let effect = match start_effect {
    HoverOperationScheduleDelayed(generation) =>
      HoverScheduleDelayed(generation)
    HoverOperationRunAsyncAndSync(generation) =>
      HoverRunAsyncAndSync(generation)
    HoverOperationNoStart | HoverOperationRunSync => HoverNoEffect
  }
  (
    effect,
    { ..self, anchor: Some(anchor), operation, insist_on_keeping: insist, },
  )
}

///|
/// Monaco `_triggerAsyncComputation`: move to `SecondWait`. The viewer then
/// schedules the sync compute at `hover_second_wait_ms` and kicks the async
/// compute. Returns whether the transition applied (the token is still current);
/// a stale timer is a no-op. Invoking this then `op_trigger_sync` back to back
/// — without the schedulers — is Monaco's immediate (`start(Immediate)`) path.
fn HoverController::op_trigger_async(
  self : HoverController,
  token : Int,
) -> (Bool, HoverController) {
  if token != self.operation.token {
    return (false, self)
  }
  (
    true,
    {
      ..self,
      operation: {
        ..self.operation,
        state: HoverOpSecondWait,
        async_done: false,
      },
    },
  )
}

///|
/// Monaco `_triggerSyncComputation`: append the sync parts, then move to `Idle`
/// if the async compute already finished or `WaitingForAsync` otherwise, and
/// emit the accumulated result.
fn HoverController::op_trigger_sync(
  self : HoverController,
  token : Int,
  sync_parts : Array[HoverPart],
) -> HoverController {
  if token != self.operation.token {
    return self
  }
  let parts = self.operation.parts.copy()
  parts.append(sync_parts)
  let state = if self.operation.async_done {
    HoverOpIdle
  } else {
    HoverOpWaitingForAsync
  }
  { ..self, operation: { ..self.operation, parts, state, }, }.emit()
}

///|
/// Monaco `_triggerLoadingMessage`: when still waiting on the async compute,
/// switch to showing the loading message.
fn HoverController::op_trigger_loading(
  self : HoverController,
  token : Int,
) -> HoverController {
  if token != self.operation.token {
    return self
  }
  match self.operation.state {
    HoverOpWaitingForAsync =>
      {
        ..self,
        operation: {
          ..self.operation,
          state: HoverOpWaitingForAsyncShowingLoading,
        },
      }.emit()
    _ => self
  }
}

///|
/// One streamed async result arrived (Monaco pushes each iterable item onto
/// `_result` and re-fires): accumulate and emit.
fn HoverController::op_async_item(
  self : HoverController,
  token : Int,
  parts : Array[HoverPart],
) -> HoverController {
  if token != self.operation.token || parts.length() == 0 {
    return self
  }
  let merged = self.operation.parts.copy()
  merged.append(parts)
  { ..self, operation: { ..self.operation, parts: merged, }, }.emit()
}

///|
/// The async compute finished (Monaco's `_asyncIterableDone`): mark it done and,
/// if we were waiting on it, complete to `Idle`, then emit.
fn HoverController::op_async_done(
  self : HoverController,
  token : Int,
) -> HoverController {
  if token != self.operation.token {
    return self
  }
  let done = { ..self.operation, async_done: true, }
  let advanced = match done.state {
    HoverOpWaitingForAsync | HoverOpWaitingForAsyncShowingLoading =>
      { ..done, state: HoverOpIdle, }
    _ => done
  }
  { ..self, operation: advanced, }.emit()
}

///|
/// Constructs the full request stamp for the operation's current generation.
pub fn HoverController::request_stamp(
  self : HoverController,
  model : @model.TextModel,
  cancellation_token : @language.CancellationToken,
) -> HoverRequestStamp {
  HoverRequestStamp(model, self.operation.token, cancellation_token)
}

///|
fn HoverController::accepts_request(
  self : HoverController,
  request : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
) -> Bool {
  request.generation == self.operation.token &&
  request.is_current(current_model, current_generation)
}

///|
/// Cancellation/model/version/generation-aware async-trigger boundary. The
/// Int-only method remains as the compatibility seam for existing callers.
pub fn HoverController::op_trigger_async_request(
  self : HoverController,
  request : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
) -> (Bool, HoverController) {
  if !self.accepts_request(request, current_model, current_generation) {
    return (false, self)
  }
  self.op_trigger_async(request.generation)
}

///|
/// Applies the sync-result transition only while the full request authority
/// remains current; otherwise returns the controller unchanged.
pub fn HoverController::op_trigger_sync_request(
  self : HoverController,
  request : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
  sync_parts : Array[HoverPart],
) -> HoverController {
  if !self.accepts_request(request, current_model, current_generation) {
    return self
  }
  self.op_trigger_sync(request.generation, sync_parts)
}

///|
/// Applies the loading transition only for the current request/model/version.
pub fn HoverController::op_trigger_loading_request(
  self : HoverController,
  request : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
) -> HoverController {
  if !self.accepts_request(request, current_model, current_generation) {
    return self
  }
  self.op_trigger_loading(request.generation)
}

///|
/// Appends one streamed async result only for the current request authority.
pub fn HoverController::op_async_item_request(
  self : HoverController,
  request : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
  parts : Array[HoverPart],
) -> HoverController {
  if !self.accepts_request(request, current_model, current_generation) {
    return self
  }
  self.op_async_item(request.generation, parts)
}

///|
/// Completes the async stream only for the current request authority.
pub fn HoverController::op_async_done_request(
  self : HoverController,
  request : HoverRequestStamp,
  current_model : @model.TextModel?,
  current_generation : Int,
) -> HoverController {
  if !self.accepts_request(request, current_model, current_generation) {
    return self
  }
  self.op_async_done(request.generation)
}

///|
/// Monaco `HoverOperation._fireResult` feeding `ContentHoverWidgetWrapper._withResult`.
/// `_fireResult` suppresses results before the hover delay (`FirstWait` /
/// `SecondWait`). `_withResult` then gates the swap: while a complete hover is
/// already shown, a still-incomplete result is held back (no flicker to a partial
/// result); a complete-but-empty result is held back too when the operation
/// insisted on keeping the hover visible; otherwise the accumulated parts become
/// the shown result via `_setCurrentResult`.
fn HoverController::emit(self : HoverController) -> HoverController {
  match self.operation.result() {
    None => self
    Some(result) => {
      let result_anchor = result.options.anchor
      let result_parts = result.value
      let result_is_complete = result.is_complete
      let previous_visible_complete = self.view is Some(_) &&
        self.current_complete
      let updated = if !previous_visible_complete {
        self.set_current_result(result_parts, result_is_complete, result_anchor)
      } else {
        self
      }
      if !result_is_complete {
        return updated
      }
      let result_empty = result_parts.length() == 0
      let should_keep_previous = result_empty &&
        result.options.insist_on_keeping_hover_visible
      if should_keep_previous {
        return updated
      }
      updated.set_current_result(
        result_parts, result_is_complete, result_anchor,
      )
    }
  }
}

///|
/// Monaco `ContentHoverWidgetWrapper._setCurrentResult`: dedupe an unchanged
/// result, treat an empty result as hiding the hover, and otherwise show the
/// sorted parts.
fn HoverController::set_current_result(
  self : HoverController,
  parts : Array[HoverPart],
  is_complete : Bool,
  result_anchor : HoverAnchor,
) -> HoverController {
  if parts.length() == 0 {
    // An empty result hides the hover (Monaco maps it to `null`).
    return match self.view {
      None => self
      Some(_) =>
        { ..self, view: None, current_anchor: None, current_complete: false, }
    }
  }
  let sorted = sort_hover_parts_stably(parts)
  // Dedupe: identical shown parts at the same completeness are a no-op.
  match self.view {
    Some(existing) =>
      if existing.parts == sorted &&
        self.current_complete == is_complete &&
        self.current_anchor == Some(result_anchor) {
        return self
      }
    None => ()
  }
  let range = hover_parts_range(sorted, result_anchor.range())
  let new_view : HoverView = { range, parts: sorted, }
  {
    ..self,
    view: Some(new_view),
    current_anchor: Some(result_anchor),
    current_complete: is_complete,
  }
}

///|
/// Whether the async compute has finished for the current operation; the viewer
/// reads this to fire the resolution status exactly once per anchor.
pub fn HoverController::is_complete(self : HoverController) -> Bool {
  self.operation.state is HoverOpIdle
}

///|
/// The hover highlight's model decoration, Monaco's
/// `ContentHoverController` `_highlightDecorations` collection entry
/// (`className: 'hoverHighlight'`, `contentHoverWidgetParticipants`): the
/// range under the visible hover, used directly.
pub fn HoverController::highlight_decorations(
  self : HoverController,
) -> Array[@model.ModelDeltaDecoration] {
  match self.view {
    Some(hover) =>
      [
        {
          range: hover.range,
          options: ModelDecorationOptions(
            "hoverHighlight",
            description="content-hover-highlight",
          ),
        },
      ]
    None => []
  }
}

///|
/// What the hover widget should show, as data: the anchor range and the
/// resolved hover parts (or the loading placeholder while the async compute
/// is still resolving past the loading delay). The `Viewer` renders this into
/// a `RenderedContentHover` and drives the content-hover widget's `show` /
/// `hide` when it changes — Monaco's `_setCurrentResult` →
/// `_showHover`/`_hideHover` seam. Placement is the widget's own concern.
pub struct HoverWidgetView {
  anchor_range : @base_common.Range
  parts : Array[HoverPart]
} derive(Eq)

///|
/// Host-selected loading augmentation. The live Viewer obtains this from the
/// first participant that provides one; `None` preserves an existing result
/// without inventing a loading row.
pub fn HoverController::widget_view_with_loading(
  self : HoverController,
  loading_message : HoverPart?,
) -> HoverWidgetView? {
  match self.view {
    Some(hover) => {
      let parts = hover.parts.copy()
      // `_withResult` retains a previous complete result while a replacement
      // operation is incomplete; its loading row must be retained with the
      // suppressed replacement, not appended to the old complete view.
      if self.operation.state is HoverOpWaitingForAsyncShowingLoading &&
        !self.current_complete {
        match loading_message {
          Some(message) => parts.push(message)
          None => ()
        }
      }
      Some({ anchor_range: hover.range, parts, })
    }
    None =>
      match self.operation.state {
        HoverOpWaitingForAsyncShowingLoading =>
          match loading_message {
            Some(message) =>
              Some({
                anchor_range: hover_part_range(message),
                parts: [message],
              })
            None => None
          }
        _ => None
      }
  }
}

///|
pub extend HoverController with Eq::{equal, not_equal}

///|
pub extend HoverDebouncer with Eq::{equal, not_equal}

///|
pub extend HoverOperation with Debug::{to_repr}

///|
pub extend HoverOperation with Eq::{equal, not_equal}

///|
pub extend HoverOperationOptions with Debug::{to_repr}

///|
pub extend HoverOperationOptions with Eq::{equal, not_equal}

///|
pub extend HoverView with Eq::{equal, not_equal}

///|
pub extend HoverWidgetView with Eq::{equal, not_equal}
