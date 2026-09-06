///| Attached-view priority and shared syntactic backend contracts.
///
/// Source: `vscode/src/vs/editor/common/model/tokens/abstractSyntaxTokenBackend.ts`
/// in the checked-in source, lines 24-187. The local
/// emitter/generation scheduler is the Gate-B-approved FFI-free observable
/// adaptation; member order, range conversion, 50 ms delay, and early returns
/// follow that unit.

///|
/// Inclusive visible model-line range supplied by a view.
pub(all) struct VisibleLineRange {
  start_line_number : Int
  end_line_number : Int
} derive(Eq, Debug)

///|
/// Immutable normalized visible ranges plus stabilization state.
priv struct AttachedViewState {
  visible_line_ranges : Array[@base_common.LineRange]
  stabilized : Bool
}

///|
/// Retains caller-provided facts without normalization.
fn AttachedViewState::AttachedViewState(
  visible_line_ranges : Array[@base_common.LineRange],
  stabilized : Bool,
) -> AttachedViewState {
  { visible_line_ranges, stabilized, }
}

///|
/// Source-order equality: physical identity, then ranges, then stabilization.
fn AttachedViewState::equals(
  self : AttachedViewState,
  other : AttachedViewState,
) -> Bool {
  if physical_equal(self, other) {
    return true
  }
  if !line_range_arrays_equal(
      self.visible_line_ranges[:],
      other.visible_line_ranges[:],
    ) {
    return false
  }
  if self.stabilized != other.stabilized {
    return false
  }
  true
}

///|
/// Event payload preserving the exact attached-view identity and optional state.
priv struct AttachedViewStateChange {
  view : AttachedViewImpl
  state : AttachedViewState?
}

///|
/// One externally-owned attached-view handle.
struct AttachedViewImpl {
  id : Int
  mut state_value : AttachedViewState?
  handle_state_change : (AttachedViewImpl, AttachedViewState) -> Unit
}

///|
/// Converts inclusive ranges to `LineRange` and notifies after committing the
/// new state. Equality suppresses only the stored-state write; the source still
/// invokes the owner callback for every `setVisibleLines` call.
pub fn AttachedViewImpl::set_visible_lines(
  self : AttachedViewImpl,
  visible_lines : Array[VisibleLineRange],
  stabilized : Bool,
) -> Unit {
  let ranges = visible_lines.map(line => {
    @base_common.LineRange(line.start_line_number, line.end_line_number + 1)
  })
  let state = AttachedViewState(ranges, stabilized)
  match self.state_value {
    Some(old) => if !old.equals(state) { self.state_value = Some(state) }
    None => self.state_value = Some(state)
  }
  (self.handle_state_change)(self, state)
}

///|
/// Identity comparison used by the owning manager.
fn AttachedViewImpl::same(
  self : AttachedViewImpl,
  other : AttachedViewImpl,
) -> Bool {
  self.id == other.id
}

///|
/// Owner of all live attached-view identities and aggregate ranges.
priv struct AttachedViews {
  views : Array[AttachedViewImpl]
  next_id : Ref[Int]
  did_change_visible_ranges : @base_common.Emitter[AttachedViewStateChange]
}

///|
/// Creates an empty attached-view manager.
fn AttachedViews::AttachedViews() -> AttachedViews {
  { views: [], next_id: Ref(0), did_change_visible_ranges: Emitter(), }
}

///|
/// Subscribes to state commits and explicit detach notifications.
fn AttachedViews::on_did_change_visible_ranges(
  self : AttachedViews,
  listener : (AttachedViewStateChange) -> Unit,
) -> @base_common.Disposable {
  self.did_change_visible_ranges.event(listener)
}

///|
/// Adds and returns one exact externally-owned handle.
fn AttachedViews::attach_view(self : AttachedViews) -> AttachedViewImpl {
  let id = self.next_id.val
  self.next_id.val = id + 1
  let view : AttachedViewImpl = {
    id,
    state_value: None,
    handle_state_change: (view, state) => {
      self.did_change_visible_ranges.fire({ view, state: Some(state), })
    },
  }
  self.views.push(view)
  view
}

///|
/// Deletes exact identity, emits the explicit absent-state signal, then invalidates aggregate state.
fn AttachedViews::detach_view(
  self : AttachedViews,
  view : AttachedViewImpl,
) -> Unit {
  if self.views.search_by(candidate => candidate.same(view)) is Some(found) {
    self.views.remove(found) |> ignore
  }
  self.did_change_visible_ranges.fire({ view, state: None, })
}

///|
/// Disposes only the manager event; handles remain externally owned values.
fn AttachedViews::dispose(self : AttachedViews) -> Unit {
  self.did_change_visible_ranges.dispose()
}

///|
/// Exact visible-range debounce delay from `AttachedViewHandler`.
const ATTACHED_VIEW_REFRESH_DELAY_MS : Int = 50

///|
/// Per-view stabilized/debounced visible refresh owner.
priv struct AttachedViewHandler {
  refresh_tokens : () -> Unit
  scheduler : () -> TokenizationScheduler?
  mut computed_line_ranges : Array[@base_common.LineRange]
  mut requested_line_ranges : Array[@base_common.LineRange]
  mut pending : @base_common.Disposable?
  generation : Ref[Int]
  mut disposed : Bool
}

///|
/// Creates a handler using the model's current scheduler at schedule time.
fn AttachedViewHandler::AttachedViewHandler(
  refresh_tokens : () -> Unit,
  scheduler : () -> TokenizationScheduler?,
) -> AttachedViewHandler {
  {
    refresh_tokens,
    scheduler,
    computed_line_ranges: [],
    requested_line_ranges: [],
    pending: None,
    generation: Ref(0),
    disposed: false,
  }
}

///|
/// Latest requested ranges.
fn AttachedViewHandler::line_ranges(
  self : AttachedViewHandler,
) -> Array[@base_common.LineRange] {
  self.requested_line_ranges
}

///|
/// Equality guard, commit, then one refresh.
fn AttachedViewHandler::update(self : AttachedViewHandler) -> Unit {
  if self.disposed ||
    line_range_arrays_equal(
      self.computed_line_ranges[:],
      self.requested_line_ranges[:],
    ) {
    return
  }
  self.computed_line_ranges = self.requested_line_ranges
  (self.refresh_tokens)()
}

///|
/// Replaces requested ranges and chooses immediate or 50 ms debounced refresh.
fn AttachedViewHandler::handle_state_change(
  self : AttachedViewHandler,
  state : AttachedViewState,
) -> Unit {
  self.requested_line_ranges = state.visible_line_ranges
  if state.stabilized {
    self.cancel_pending()
    self.update()
  } else {
    self.cancel_pending()
    match (self.scheduler)() {
      Some(scheduler) => {
        let generation = self.generation.val
        self.pending = Some(
          scheduler.delay(ATTACHED_VIEW_REFRESH_DELAY_MS, () => {
            if !self.disposed && generation == self.generation.val {
              self.pending = None
              self.update()
            }
          }),
        )
      }
      None => ()
    }
  }
}

///|
/// Cancels the current one-shot and invalidates stale callbacks.
fn AttachedViewHandler::cancel_pending(self : AttachedViewHandler) -> Unit {
  self.generation.val += 1
  match self.pending {
    Some(handle) => handle.dispose()
    None => ()
  }
  self.pending = None
}

///|
/// Releases the one-shot owner.
fn AttachedViewHandler::dispose(self : AttachedViewHandler) -> Unit {
  if !self.disposed {
    self.disposed = true
    self.cancel_pending()
  }
}

///|
/// Shared state/events held by the concrete syntactic backend.
priv struct AbstractSyntaxTokenBackend {
  did_change_tokens : @base_common.Emitter[ModelTokensChangedEvent]
}

///|
/// Creates the shared backend contract.
fn AbstractSyntaxTokenBackend::AbstractSyntaxTokenBackend() -> AbstractSyntaxTokenBackend {
  { did_change_tokens: Emitter(), }
}

///|
/// Subscribes to exact changed line ranges.
fn AbstractSyntaxTokenBackend::on_did_change_tokens(
  self : AbstractSyntaxTokenBackend,
  listener : (ModelTokensChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_tokens.event(listener)
}

///|
/// Releases shared emitters.
fn AbstractSyntaxTokenBackend::dispose(
  self : AbstractSyntaxTokenBackend,
) -> Unit {
  self.did_change_tokens.dispose()
}

///|
/// Normalizes ranges in ascending order and joins touching intervals.
fn join_line_ranges(
  ranges : ArrayView[@base_common.LineRange],
) -> Array[@base_common.LineRange] {
  let set = @base_common.LineRangeSet()
  for range in ranges {
    set.add_range(range)
  }
  set.ranges()
}

///|
/// Element equality without allocation.
fn line_range_arrays_equal(
  left : ArrayView[@base_common.LineRange],
  right : ArrayView[@base_common.LineRange],
) -> Bool {
  left == right
}

///|
pub extend VisibleLineRange with Debug::{to_repr}

///|
pub extend VisibleLineRange with Eq::{equal, not_equal}
