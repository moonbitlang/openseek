///|
fn is_model_flush_cursor_event(
  event : @view_model.CursorStateChangedEvent,
) -> Bool {
  event.reason == ContentFlush &&
  event.old_selections is None &&
  event.old_model_version_id == 0
}

///|
/// CodeEditorWidget-lifetime owner of the reentrant cursor-pair queue and the exact
/// content-version barriers that make model Flush delivery wait for its public
/// content event. Model identity and every observable effect stay on CodeEditorWidget.
priv struct CursorEventDelivery {
  queue : Array[@view_model.CursorStateChangedEvent]
  mut is_draining : Bool
  mut content_barrier_depth : Int
  completed_content_versions : Array[Int]
}

///|
fn CursorEventDelivery::CursorEventDelivery() -> CursorEventDelivery {
  {
    queue: [],
    is_draining: false,
    content_barrier_depth: 0,
    completed_content_versions: [],
  }
}

///|
fn CursorEventDelivery::has_completed_content_version(
  self : CursorEventDelivery,
  version_id : Int,
) -> Bool {
  self.completed_content_versions.contains(version_id)
}

///|
/// Keeps the depth equal to the exact number of queued Flush facts still
/// waiting for their own public content version.
fn CursorEventDelivery::refresh_content_barrier_depth(
  self : CursorEventDelivery,
) -> Unit {
  let depth = for event in self.queue; depth = 0 {
    if is_model_flush_cursor_event(event) &&
      !self.has_completed_content_version(event.model_version_id) {
      continue depth + 1
    }
  } nobreak {
    depth
  }
  self.content_barrier_depth = depth
}

///|
fn CursorEventDelivery::enqueue(
  self : CursorEventDelivery,
  event : @view_model.CursorStateChangedEvent,
) -> Unit {
  self.queue.push(event)
  self.refresh_content_barrier_depth()
}

///|
/// Starts one outer drain. Reentrant callers leave the existing drain gate in
/// place and return their work to that outer loop.
fn CursorEventDelivery::begin_drain(self : CursorEventDelivery) -> Bool {
  if self.is_draining {
    return false
  }
  self.is_draining = true
  true
}

///|
/// Removes the FIFO head only when it is ready. A blocked Flush never permits
/// a later queue item to overtake it. Completion membership is consumed before
/// the event is returned to CodeEditorWidget, and therefore before any public callback.
fn CursorEventDelivery::take_next_ready(
  self : CursorEventDelivery,
) -> @view_model.CursorStateChangedEvent? {
  guard self.queue is [next, ..] else { return None }
  if self.content_barrier_depth > 0 &&
    is_model_flush_cursor_event(next) &&
    !self.has_completed_content_version(next.model_version_id) {
    return None
  }
  let event = self.queue.remove(0)
  if is_model_flush_cursor_event(event) {
    match self.completed_content_versions.search(event.model_version_id) {
      Some(index) => self.completed_content_versions.remove(index) |> ignore
      None => ()
    }
  }
  self.refresh_content_barrier_depth()
  Some(event)
}

///|
fn CursorEventDelivery::mark_content_complete(
  self : CursorEventDelivery,
  version_id : Int,
) -> Unit {
  if !self.has_completed_content_version(version_id) {
    self.completed_content_versions.push(version_id)
  }
  self.refresh_content_barrier_depth()
}

///|
fn CursorEventDelivery::end_drain(self : CursorEventDelivery) -> Unit {
  self.is_draining = false
  self.refresh_content_barrier_depth()
}

///|
/// Drops facts owned by the detached model while preserving an active outer
/// drain. A model swap can occur inside the position half of a pair; the old
/// selection and any newly queued model pair must still be drained in order.
fn CursorEventDelivery::reset_model_scope(self : CursorEventDelivery) -> Unit {
  self.queue.clear()
  self.content_barrier_depth = 0
  self.completed_content_versions.clear()
}

///|
/// Receives one ViewModel outgoing cursor fact. View state is already
/// committed; scheduling happens before any public listener. Flush facts open
/// a content barrier and remain queued until the model's public content event
/// has run.
fn CodeEditorWidget::enqueue_cursor_state_change(
  self : CodeEditorWidget,
  event : @view_model.CursorStateChangedEvent,
) -> Unit {
  // `set_selections` publicly accepts any reason, including ContentFlush.
  // Only the controller's real model-flush fact has the null-old-state
  // sentinel and therefore needs to wait for the public content event.
  self.schedule_render()
  self.cursor_delivery.enqueue(event)
  self.drain_cursor_delivery_queue()
}

///|
/// Closes one model-content barrier after all public content listeners return.
/// Nested/reentrant set-value calls increment the depth independently, so no
/// flush fact can overwrite another or drain before its content event.
fn CodeEditorWidget::complete_model_content_delivery(
  self : CodeEditorWidget,
  model : @model.TextModel,
  version_id : Int,
) -> Unit {
  guard self.get_model() is Some(active_model) && active_model.same(model) else {
    return
  }
  self.cursor_delivery.mark_content_complete(version_id)
  self.drain_cursor_delivery_queue()
}

///|
/// Drains cursor facts FIFO. A fact is removed before callbacks, and the gate
/// remains set through both public fires, so a reentrant cursor transition is
/// appended for a later iteration rather than interleaving the current pair.
fn CodeEditorWidget::drain_cursor_delivery_queue(
  self : CodeEditorWidget,
) -> Unit {
  if !self.cursor_delivery.begin_drain() {
    return
  }
  while self.cursor_delivery.take_next_ready() is Some(event) {
    guard event.selections.length() > 0 else { continue }
    let selection = event.selections[0]
    if is_model_flush_cursor_event(event) {
      match self.get_view_model() {
        Some(view_model) => self.emit_view_cursor_state_changed(view_model)
        None => ()
      }
    }
    self.did_change_cursor_position.fire({
      position: selection.get_position(),
      secondary_positions: [],
      reason: event.reason,
      source: event.source,
    })
    self.did_change_cursor_selection.fire({
      selection,
      secondary_selections: [],
      model_version_id: event.model_version_id,
      old_selections: event.old_selections,
      old_model_version_id: event.old_model_version_id,
      source: event.source,
      reason: event.reason,
    })
  }
  self.cursor_delivery.end_drain()
}
