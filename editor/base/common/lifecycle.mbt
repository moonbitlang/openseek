///|
/// Idempotent lifecycle handle for subscriptions, watches, and teardown
/// callbacks. Calling `dispose` more than once runs the callback at most once.
struct Disposable {
  dispose_handler : () -> Unit
}

///|
/// Builds a disposable handle from a teardown callback.
pub fn Disposable::from(dispose : () -> Unit) -> Disposable {
  let disposed = Ref(false)
  {
    dispose_handler: () => {
      if !disposed.val {
        disposed.val = true
        dispose()
      }
    },
  }
}

///|
/// Runs the disposable's teardown callback if it has not already run.
pub fn Disposable::dispose(self : Disposable) -> Unit {
  (self.dispose_handler)()
}

///|
priv struct ListenerCell[T] {
  id : Int
  listener : (T) -> Unit
  active : Ref[Bool]
}

///|
/// Small typed event emitter for host-neutral subscription APIs. It stores
/// listeners in registration order and returns a disposable per listener.
struct Emitter[T] {
  listeners : Array[ListenerCell[T]]
  disposed : Ref[Bool]
  next_id : Ref[Int]
}

///|
/// Creates an empty typed emitter.
pub fn[T] Emitter::Emitter() -> Emitter[T] {
  { listeners: [], disposed: Ref(false), next_id: Ref(0), }
}

///|
/// Registers a listener and returns a disposable for just that listener.
pub fn[T] Emitter::event(
  self : Emitter[T],
  listener : (T) -> Unit,
) -> Disposable {
  if self.disposed.val {
    return Disposable::from(() => ())
  }
  let id = self.next_id.val
  self.next_id.val = id + 1
  let active = Ref(true)
  self.listeners.push({ id, listener, active, })
  Disposable::from(() => {
    active.val = false
    self.listeners.retain(cell => cell.id != id)
  })
}

///|
/// Whether any active listener is registered, `Emitter.hasListeners`
/// (`event.ts`).
pub fn[T] Emitter::has_listeners(self : Emitter[T]) -> Bool {
  self.listeners.any(cell => cell.active.val)
}

///|
/// Notifies currently active listeners in registration order. Delivery
/// iterates a snapshot: a listener disposing itself (or a sibling) mid-fire
/// must not disturb the walk, and the `active` flag keeps listeners removed
/// mid-fire from running.
pub fn[T] Emitter::fire(self : Emitter[T], event : T) -> Unit {
  if self.disposed.val {
    return
  }
  let cells = self.listeners.copy()
  for cell in cells {
    if cell.active.val {
      (cell.listener)(event)
    }
  }
}

///|
/// Disposes every listener and prevents later registrations from firing.
pub fn[T] Emitter::dispose(self : Emitter[T]) -> Unit {
  if !self.disposed.val {
    self.disposed.val = true
    for cell in self.listeners {
      cell.active.val = false
    }
    self.listeners.clear()
  }
}

///|
/// Emitter that queues events fired in one tick and delivers them on a
/// scheduled flush, `MicrotaskEmitter` (`event.ts:1594-1620`). With a `merge`
/// function every event queued before the flush collapses into one merged
/// event.
///
/// Deviation: Monaco schedules the flush with a hardcoded `queueMicrotask`;
/// this package compiles for js *and* native, so the scheduler is injected at
/// construction. The default runs the flush inline, degenerating to the
/// synchronous `Emitter` semantics — the browser host passes the real
/// microtask scheduler (`viewer/services.mbt`).
struct MicrotaskEmitter[T] {
  inner : Emitter[T]
  mut queued_events : Array[T]
  merge_fn : ((Array[T]) -> T)?
  schedule : (() -> Unit) -> Unit
}

///|
/// Creates a queueing emitter; `merge` collapses one flush's events into one.
pub fn[T] MicrotaskEmitter::MicrotaskEmitter(
  merge? : (Array[T]) -> T,
  schedule? : (() -> Unit) -> Unit = run => run(),
) -> MicrotaskEmitter[T] {
  { inner: Emitter(), queued_events: [], merge_fn: merge, schedule, }
}

///|
/// Registers a listener and returns a disposable for just that listener.
pub fn[T] MicrotaskEmitter::event(
  self : MicrotaskEmitter[T],
  listener : (T) -> Unit,
) -> Disposable {
  self.inner.event(listener)
}

///|
/// Queues the event; the queue's first event schedules the flush
/// (`MicrotaskEmitter.fire`). Events re-fired while the flush runs are
/// dropped, matching the source's `forEach` + reassignment.
pub fn[T] MicrotaskEmitter::fire(self : MicrotaskEmitter[T], event : T) -> Unit {
  if !self.inner.has_listeners() {
    return
  }
  self.queued_events.push(event)
  if self.queued_events.length() == 1 {
    (self.schedule)(() => {
      match self.merge_fn {
        Some(merge) => self.inner.fire(merge(self.queued_events))
        None => {
          let events = self.queued_events
          let count = events.length()
          for i in 0..<count {
            self.inner.fire(events[i])
          }
        }
      }
      self.queued_events = []
    })
  }
}

///|
/// Releases every listener and pending queue state.
pub fn[T] MicrotaskEmitter::dispose(self : MicrotaskEmitter[T]) -> Unit {
  self.queued_events = []
  self.inner.dispose()
}
