///|
/// Mutable collector shared by nested `begin_view_event_batch` scopes.  Event
/// order is the append order; only the outermost matching `end` dispatches the
/// collected batch.
priv struct ViewEventCollector {
  view_events : Array[ViewEvent]
}

///|
fn ViewEventCollector::ViewEventCollector() -> ViewEventCollector {
  { view_events: [], }
}

///|
fn ViewEventCollector::emit(
  self : ViewEventCollector,
  event : ViewEvent,
) -> Unit {
  self.view_events.push(event)
}

///|
/// Reentrant FIFO dispatcher corresponding to Monaco's `ViewEventDispatcher`
/// plus `ViewEventsCollector`.  The callback represents the fixed, ordered
/// ViewPart handler array owned by `View`.
priv struct ViewEventDispatcher {
  deliver : (Array[ViewEvent]) -> Unit
  mut pending_view_events : Array[ViewEvent]?
  mut after_view_events : Array[() -> Unit]
  mut consuming : Bool
  mut collector : ViewEventCollector?
  mut collector_depth : Int
}

///|
fn ViewEventDispatcher::ViewEventDispatcher(
  deliver : (Array[ViewEvent]) -> Unit,
) -> ViewEventDispatcher {
  {
    deliver,
    pending_view_events: None,
    after_view_events: [],
    consuming: false,
    collector: None,
    collector_depth: 0,
  }
}

///|
fn ViewEventDispatcher::begin(self : ViewEventDispatcher) -> ViewEventCollector {
  self.collector_depth += 1
  match self.collector {
    Some(collector) => collector
    None => {
      let collector = ViewEventCollector::ViewEventCollector()
      self.collector = Some(collector)
      collector
    }
  }
}

///|
fn ViewEventDispatcher::end(self : ViewEventDispatcher) -> Unit {
  if self.collector_depth <= 0 {
    abort("ViewEventDispatcher.end without matching begin")
  }
  self.collector_depth -= 1
  if self.collector_depth > 0 {
    return
  }
  let events = match self.collector {
    Some(collector) => collector.view_events.copy()
    None => abort("ViewEventDispatcher collector missing")
  }
  self.collector = None
  self.enqueue(events)
}

///|
/// Enqueues one internal event and runs `after` only after that event and all
/// earlier/reentrant ViewEvent batches have completed. ViewZones uses this to
/// preserve its internal-before-outgoing contract; outgoing event values do
/// not enter this dispatcher.
fn ViewEventDispatcher::emit_view_event_then(
  self : ViewEventDispatcher,
  event : ViewEvent,
  after : () -> Unit,
) -> Unit {
  self.after_view_events.push(after)
  match self.collector {
    Some(collector) => collector.emit(event)
    None => self.enqueue([event])
  }
}

///|
fn ViewEventDispatcher::emit_view_event(
  self : ViewEventDispatcher,
  event : ViewEvent,
) -> Unit {
  match self.collector {
    Some(collector) => collector.emit(event)
    None => {
      let collector = self.begin()
      defer self.end()
      collector.emit(event)
    }
  }
}

///|
fn ViewEventDispatcher::enqueue(
  self : ViewEventDispatcher,
  events : Array[ViewEvent],
) -> Unit {
  if events.length() == 0 {
    return
  }
  match self.pending_view_events {
    Some(pending) =>
      for event in events {
        pending.push(event)
      }
    None => self.pending_view_events = Some(events.copy())
  }
  self.consume()
}

///|
fn ViewEventDispatcher::consume(self : ViewEventDispatcher) -> Unit {
  if self.consuming {
    return
  }
  self.consuming = true
  defer self.finish_consuming()
  // `deliver` is statically non-raising, so the consuming gate is restored on
  // every possible return.  A reentrant emit installs a fresh pending array;
  // clearing before delivery prevents callbacks from interleaving batches.
  while true {
    match self.pending_view_events {
      Some(events) => {
        self.pending_view_events = None
        (self.deliver)(events)
        continue
      }
      None => ()
    }
    if self.after_view_events.length() == 0 {
      break
    }
    let callbacks = self.after_view_events
    self.after_view_events = []
    for callback in callbacks {
      callback()
    }
  }
}

///|
fn ViewEventDispatcher::finish_consuming(self : ViewEventDispatcher) -> Unit {
  self.consuming = false
}

///|
fn ViewEventDispatcher::dispose(self : ViewEventDispatcher) -> Unit {
  self.pending_view_events = None
  self.after_view_events = []
  self.collector = None
  self.collector_depth = 0
  self.consuming = false
}
