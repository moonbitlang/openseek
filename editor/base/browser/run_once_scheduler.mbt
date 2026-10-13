///|
/// A cancelable one-shot scheduler shared by browser widgets. Scheduling a
/// second callback replaces the first delay window; disposal permanently
/// cancels the currently pending callback.
pub struct RunOnceScheduler {
  delay_ms : Int32
  mut handle : @base_common.Disposable?
  schedule_timeout : (() -> Unit, Int32) -> @base_common.Disposable
}

///|
pub fn RunOnceScheduler::RunOnceScheduler(delay_ms : Int32) -> RunOnceScheduler {
  RunOnceScheduler::new_with_timer(delay_ms, schedule_timeout)
}

///|
/// Capability-injected constructor used by deterministic widget tests.
pub fn RunOnceScheduler::new_with_timer(
  delay_ms : Int32,
  schedule_timeout : (() -> Unit, Int32) -> @base_common.Disposable,
) -> RunOnceScheduler {
  { delay_ms, handle: None, schedule_timeout, }
}

///|
pub fn RunOnceScheduler::is_scheduled(self : RunOnceScheduler) -> Bool {
  self.handle is Some(_)
}

///|
pub fn RunOnceScheduler::schedule(
  self : RunOnceScheduler,
  callback : () -> Unit,
) -> Unit {
  self.cancel()
  self.handle = Some(
    (self.schedule_timeout)(
      () => {
        self.handle = None
        callback()
      },
      self.delay_ms,
    ),
  )
}

///|
pub fn RunOnceScheduler::cancel(self : RunOnceScheduler) -> Unit {
  match self.handle {
    Some(handle) => {
      handle.dispose()
      self.handle = None
    }
    None => ()
  }
}

///|
pub fn RunOnceScheduler::dispose(self : RunOnceScheduler) -> Unit {
  self.cancel()
}
