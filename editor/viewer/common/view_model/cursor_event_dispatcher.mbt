///|
/// Semantic kind of the scoped outgoing events. Monaco's const-enum values are
/// `4` for ViewZones and `7` for cursor state; MoonBit deliberately exposes no
/// numeric ABI for these variants.
pub(all) enum OutgoingViewModelEventKind {
  ViewZonesChanged
  HiddenAreasChanged
  CursorStateChanged
  ModelTokensChanged
} derive(Eq, Debug)

///|
/// Complete outgoing cursor payload owned by the ViewModel. It retains the
/// earliest old state when merged and the latest new state/source/reason.
pub(all) struct CursorStateChangedEvent {
  kind : OutgoingViewModelEventKind
  old_selections : Array[@core.Selection]?
  selections : Array[@core.Selection]
  old_model_version_id : Int
  model_version_id : Int
  source : String
  reason : @editor_api.CursorChangeReason
  reached_max_cursor_count : Bool
} derive(Debug)

///|
/// Builds the outgoing event from one controller transition fact.
fn CursorStateChangedEvent::from_change(
  change : @cursor.CursorStateChange,
) -> CursorStateChangedEvent {
  {
    kind: CursorStateChanged,
    old_selections: change.old_selections,
    selections: change.selections,
    old_model_version_id: change.old_model_version_id,
    model_version_id: change.model_version_id,
    source: change.source,
    reason: change.reason,
    reached_max_cursor_count: change.reached_max_cursor_count,
  }
}

///|
/// Nullable ordered-selection equality from
/// `CursorStateChangedEvent._selectionsAreEqual`.
fn selections_are_equal(
  a : Array[@core.Selection]?,
  b : Array[@core.Selection]?,
) -> Bool {
  a == b
}

///|
/// An outgoing cursor event is a no-op only when both the selections and the
/// internal model versions are equal.
pub fn CursorStateChangedEvent::is_no_op(
  self : CursorStateChangedEvent,
) -> Bool {
  selections_are_equal(self.old_selections, Some(self.selections)) &&
  self.old_model_version_id == self.model_version_id
}

///|
/// Payload-free outgoing ViewZones change event. Its kind is semantic rather
/// than Monaco's numeric const-enum ordinal `4`.
pub struct ViewZonesChangedEvent {
  kind : OutgoingViewModelEventKind
} derive(Debug)

///|
/// Creates one source-shaped ViewZones change event.
pub fn ViewZonesChangedEvent::ViewZonesChangedEvent() -> ViewZonesChangedEvent {
  { kind: ViewZonesChanged, }
}

///|
/// ViewZones changes are always observable.
pub fn ViewZonesChangedEvent::is_no_op(_self : ViewZonesChangedEvent) -> Bool {
  false
}

///|
/// Payload-free outgoing hidden-area change event. It is published only after
/// the line mapping, cursor/decorations, layout, and stable viewport have been
/// updated by `ViewModel::set_hidden_areas`.
pub struct HiddenAreasChangedOutgoingEvent {
  kind : OutgoingViewModelEventKind
} derive(Debug)

///|
/// Creates one source-shaped hidden-area change event.
pub fn HiddenAreasChangedOutgoingEvent::HiddenAreasChangedOutgoingEvent() -> HiddenAreasChangedOutgoingEvent {
  { kind: HiddenAreasChanged, }
}

///|
/// A changed hidden-area mapping is always observable.
pub fn HiddenAreasChangedOutgoingEvent::is_no_op(
  _self : HiddenAreasChangedOutgoingEvent,
) -> Bool {
  false
}

///|
/// Source-shaped outgoing wrapper for one original model-token event
/// (`viewModelEventDispatcher.ts:545-551`). The wrapper deliberately retains
/// the exact event object; view-coordinate conversion belongs to the earlier
/// browser ViewEvent delivery.
pub struct ModelTokensChangedOutgoingEvent {
  kind : OutgoingViewModelEventKind
  event : @model.ModelTokensChangedEvent
}

///|
/// Builds the distinct outgoing model-token wrapper.
pub fn ModelTokensChangedOutgoingEvent::ModelTokensChangedOutgoingEvent(
  event : @model.ModelTokensChangedEvent,
) -> ModelTokensChangedOutgoingEvent {
  { kind: ModelTokensChanged, event, }
}

///|
/// Model-token outgoing events are always observable, including an empty
/// range array (`viewModelEventDispatcher.ts:552-554`).
pub fn ModelTokensChangedOutgoingEvent::is_no_op(
  _self : ModelTokensChangedOutgoingEvent,
) -> Bool {
  false
}

///|
/// Private heterogeneous outgoing-only queue. The generic mixed browser-view
/// collector/postponement layer remains intentionally absent.
priv enum PendingOutgoingEvent {
  CursorEvent(CursorStateChangedEvent)
  ViewZonesEvent(ViewZonesChangedEvent)
  HiddenAreasEvent(HiddenAreasChangedOutgoingEvent)
  ModelTokensEvent(ModelTokensChangedOutgoingEvent)
}

///|
/// Merges only another cursor event. Earliest old state/version remain; latest
/// new state/version/source/reason win.
fn CursorStateChangedEvent::attempt_to_merge(
  self : CursorStateChangedEvent,
  other : PendingOutgoingEvent,
) -> CursorStateChangedEvent? {
  match other {
    ViewZonesEvent(_) => None
    HiddenAreasEvent(_) => None
    ModelTokensEvent(_) => None
    CursorEvent(other) =>
      Some({
        kind: CursorStateChanged,
        old_selections: self.old_selections,
        selections: other.selections,
        old_model_version_id: self.old_model_version_id,
        model_version_id: other.model_version_id,
        source: other.source,
        reason: other.reason,
        reached_max_cursor_count: self.reached_max_cursor_count ||
        other.reached_max_cursor_count,
      })
  }
}

///|
/// Merges only another ViewZones event and retains the first queued instance.
fn ViewZonesChangedEvent::attempt_to_merge(
  self : ViewZonesChangedEvent,
  other : PendingOutgoingEvent,
) -> ViewZonesChangedEvent? {
  match other {
    CursorEvent(_) => None
    HiddenAreasEvent(_) => None
    ModelTokensEvent(_) => None
    ViewZonesEvent(_) => Some(self)
  }
}

///|
/// Merges only another hidden-area event and retains the first queued instance.
fn HiddenAreasChangedOutgoingEvent::attempt_to_merge(
  self : HiddenAreasChangedOutgoingEvent,
  other : PendingOutgoingEvent,
) -> HiddenAreasChangedOutgoingEvent? {
  match other {
    CursorEvent(_) | ViewZonesEvent(_) | ModelTokensEvent(_) => None
    HiddenAreasEvent(_) => Some(self)
  }
}

///|
/// Unlike cursor, ViewZones, and hidden-area siblings, the source model-token
/// wrapper never merges, even with another model-token event
/// (`viewModelEventDispatcher.ts:556-559`).
fn ModelTokensChangedOutgoingEvent::attempt_to_merge(
  _self : ModelTokensChangedOutgoingEvent,
  _other : PendingOutgoingEvent,
) -> ModelTokensChangedOutgoingEvent? {
  None
}

///|
/// Whether one queued outgoing fact can be dropped before delivery.
fn PendingOutgoingEvent::is_no_op(self : PendingOutgoingEvent) -> Bool {
  match self {
    CursorEvent(event) => event.is_no_op()
    ViewZonesEvent(event) => event.is_no_op()
    HiddenAreasEvent(event) => event.is_no_op()
    ModelTokensEvent(event) => event.is_no_op()
  }
}

///|
/// Attempts a same-kind merge and preserves the existing queue slot.
fn PendingOutgoingEvent::attempt_to_merge(
  self : PendingOutgoingEvent,
  other : PendingOutgoingEvent,
) -> PendingOutgoingEvent? {
  match self {
    CursorEvent(event) =>
      event.attempt_to_merge(other).map(merged => CursorEvent(merged))
    ViewZonesEvent(event) =>
      event.attempt_to_merge(other).map(merged => ViewZonesEvent(merged))
    HiddenAreasEvent(event) =>
      event.attempt_to_merge(other).map(merged => HiddenAreasEvent(merged))
    ModelTokensEvent(event) =>
      event.attempt_to_merge(other).map(merged => ModelTokensEvent(merged))
  }
}

///|
/// DOM-free outgoing-only half of Monaco's `ViewModelEventDispatcher`.
/// Pending cursor/ViewZones/hidden-area events coalesce into their first
/// same-kind slot; delivery is FIFO, discards no-ops, and remains safe when
/// listeners emit reentrantly.
struct CursorEventDispatcher {
  event_listeners : Array[OutgoingEventListenerCell]
  outgoing_events : Array[PendingOutgoingEvent]
  mut listener_count : Int
  mut listeners_are_array : Bool
  mut delivery_index : Int
  mut delivery_end : Int
  mut delivery_value : PendingOutgoingEvent?
  mut delivery_active : Bool
  mut disposed : Bool
}

///|
/// Stable listener slot. Disposals mark slots inactive instead of changing the
/// array while a source-shaped delivery walk is in progress.
priv struct OutgoingEventListenerCell {
  listener : (PendingOutgoingEvent) -> Unit
  active : Ref[Bool]
}

///|
/// Creates an empty dispatcher.
fn CursorEventDispatcher::CursorEventDispatcher() -> CursorEventDispatcher {
  {
    event_listeners: [],
    outgoing_events: [],
    listener_count: 0,
    listeners_are_array: false,
    delivery_index: -1,
    delivery_end: 0,
    delivery_value: None,
    delivery_active: false,
    disposed: false,
  }
}

///|
/// Retires the registered outgoing listeners and drops any queued facts.
/// Later subscriptions and emissions are inert, matching the source-owned
/// emitter's registration in the ViewModel lifetime store.
fn CursorEventDispatcher::dispose(self : CursorEventDispatcher) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.outgoing_events.clear()
  for cell in self.event_listeners {
    cell.active.val = false
  }
  self.event_listeners.clear()
  self.listener_count = 0
  self.reset_event_delivery()
}

///|
/// Registers one listener on the shared heterogeneous outgoing emitter.
fn CursorEventDispatcher::on_outgoing_event(
  self : CursorEventDispatcher,
  listener : (PendingOutgoingEvent) -> Unit,
) -> @base_common.Disposable {
  if self.disposed {
    return @base_common.Disposable::from(() => ())
  }
  if self.listener_count == 1 && !self.listeners_are_array {
    // Monaco upgrades from its optimized single-listener representation to a
    // sparse array when the second listener is registered. It deliberately
    // does not downgrade that array while one listener remains.
    self.listeners_are_array = true
  }
  let active = Ref(true)
  self.event_listeners.push({ listener, active, })
  self.listener_count += 1
  @base_common.Disposable::from(() => {
    if active.val {
      active.val = false
      self.listener_count -= 1
      if self.listener_count == 0 {
        self.listeners_are_array = false
      }
    }
  })
}

///|
/// Exposes the dispatcher's cursor event through a typed listener alias.
fn CursorEventDispatcher::on_event(
  self : CursorEventDispatcher,
  listener : (CursorStateChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.on_outgoing_event(event => {
    if event is CursorEvent(event) {
      listener(event)
    }
  })
}

///|
/// Exposes the dispatcher's ViewZones event through a typed listener alias.
fn CursorEventDispatcher::on_view_zones_changed(
  self : CursorEventDispatcher,
  listener : (ViewZonesChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.on_outgoing_event(event => {
    if event is ViewZonesEvent(event) {
      listener(event)
    }
  })
}

///|
/// Exposes the dispatcher's hidden-area event through a typed listener alias.
fn CursorEventDispatcher::on_hidden_areas_changed(
  self : CursorEventDispatcher,
  listener : (HiddenAreasChangedOutgoingEvent) -> Unit,
) -> @base_common.Disposable {
  self.on_outgoing_event(event => {
    if event is HiddenAreasEvent(event) {
      listener(event)
    }
  })
}

///|
/// Exposes the model-token outgoing arm through a typed ViewModel listener.
fn CursorEventDispatcher::on_model_tokens_changed(
  self : CursorEventDispatcher,
  listener : (ModelTokensChangedOutgoingEvent) -> Unit,
) -> @base_common.Disposable {
  self.on_outgoing_event(event => {
    if event is ModelTokensEvent(event) {
      listener(event)
    }
  })
}

///|
/// Adds or merges first, then attempts an immediate drain.
fn CursorEventDispatcher::emit_outgoing_event(
  self : CursorEventDispatcher,
  event : CursorStateChangedEvent,
) -> Unit {
  if self.disposed {
    return
  }
  self.add_outgoing_event(CursorEvent(event))
  self.emit_outgoing_events()
}

///|
/// Adds a ViewZones fact to the same heterogeneous queue and drains it.
fn CursorEventDispatcher::emit_view_zones_changed(
  self : CursorEventDispatcher,
  event : ViewZonesChangedEvent,
) -> Unit {
  if self.disposed {
    return
  }
  self.add_outgoing_event(ViewZonesEvent(event))
  self.emit_outgoing_events()
}

///|
/// Adds a hidden-area fact to the shared heterogeneous queue and drains it.
fn CursorEventDispatcher::emit_hidden_areas_changed(
  self : CursorEventDispatcher,
  event : HiddenAreasChangedOutgoingEvent,
) -> Unit {
  if self.disposed {
    return
  }
  self.add_outgoing_event(HiddenAreasEvent(event))
  self.emit_outgoing_events()
}

///|
/// Adds one nonmergeable model-token fact to the shared outgoing queue.
fn CursorEventDispatcher::emit_model_tokens_changed(
  self : CursorEventDispatcher,
  event : ModelTokensChangedOutgoingEvent,
) -> Unit {
  if self.disposed {
    return
  }
  self.add_outgoing_event(ModelTokensEvent(event))
  self.emit_outgoing_events()
}

///|
/// Scans queued events in order and replaces the first mergeable slot;
/// otherwise appends at the FIFO tail.
fn CursorEventDispatcher::add_outgoing_event(
  self : CursorEventDispatcher,
  event : PendingOutgoingEvent,
) -> Unit {
  if self.disposed {
    return
  }
  for index, pending in self.outgoing_events {
    if pending.attempt_to_merge(event) is Some(merged) {
      self.outgoing_events[index] = merged
      return
    }
  }
  self.outgoing_events.push(event)
}

///|
/// Drains FIFO until empty. There is deliberately no local reentrancy gate:
/// the source recursively shifts/fires a reentrant outgoing event immediately
/// unless its separate generic view-event collector is active (that collector
/// is outside this child). The root Viewer's delivery FIFO, not this semantic
/// dispatcher, keeps public position/selection pairs adjacent.
fn CursorEventDispatcher::emit_outgoing_events(
  self : CursorEventDispatcher,
) -> Unit {
  if self.disposed {
    return
  }
  while self.outgoing_events.length() > 0 {
    let event = self.outgoing_events.remove(0)
    if !event.is_no_op() {
      self.deliver_event(event)
    }
  }
}

///|
/// Resets the listener-level delivery cursor. Incrementing the cursor before a
/// callback and finishing an active walk at the start of a nested `fire` are
/// the two ordering rules owned by Monaco's `Emitter._deliverQueue`/`fire`.
fn CursorEventDispatcher::reset_event_delivery(
  self : CursorEventDispatcher,
) -> Unit {
  self.delivery_index = self.delivery_end
  self.delivery_end = 0
  self.delivery_value = None
  self.delivery_active = false
}

///|
/// Finishes the currently enqueued listener walk. A nested fire calls this
/// before enqueuing its own value, so the remaining listeners observe A, then
/// all listeners observe B, before the first A callback resumes.
fn CursorEventDispatcher::finish_event_delivery(
  self : CursorEventDispatcher,
) -> Unit {
  while self.delivery_active &&
        self.delivery_index < self.delivery_end &&
        !self.disposed {
    let index = self.delivery_index
    // Source increments before invoking the listener because the callback can
    // recursively finish this same delivery state.
    self.delivery_index += 1
    let cell = self.event_listeners[index]
    if cell.active.val {
      guard self.delivery_value is Some(value) else {
        self.reset_event_delivery()
        return
      }
      (cell.listener)(value)
    }
  }
  if self.delivery_active &&
    (self.delivery_index >= self.delivery_end || self.disposed) {
    self.reset_event_delivery()
  }
}

///|
/// Mirrors the source emitter's direct single-listener representation and its
/// listener-level `EventDeliveryQueue`. This cannot be an outer event FIFO:
/// on a nested fire, the source first drains the remaining listeners for the
/// current value and delivers the nested value before returning to the caller.
fn CursorEventDispatcher::deliver_event(
  self : CursorEventDispatcher,
  event : PendingOutgoingEvent,
) -> Unit {
  if self.disposed {
    return
  }
  if self.delivery_active {
    self.finish_event_delivery()
  }
  if self.disposed || self.listener_count == 0 {
    return
  }
  if !self.listeners_are_array {
    for cell in self.event_listeners {
      if cell.active.val {
        (cell.listener)(event)
        return
      }
    }
    return
  }
  self.delivery_index = 0
  self.delivery_end = self.event_listeners.length()
  self.delivery_value = Some(event)
  self.delivery_active = true
  self.finish_event_delivery()
}

///|
pub extend CursorStateChangedEvent with Debug::{to_repr}

///|
pub extend HiddenAreasChangedOutgoingEvent with Debug::{to_repr}

///|
pub extend OutgoingViewModelEventKind with Debug::{to_repr}

///|
pub extend OutgoingViewModelEventKind with Eq::{equal, not_equal}

///|
pub extend ViewZonesChangedEvent with Debug::{to_repr}
