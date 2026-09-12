///|
/// High-resolution monotonic milliseconds for elapsed-time measurement. The
/// wall clock is only a compatibility fallback for runtimes without
/// `performance.now`.
pub extern "js" fn monotonic_now_ms() -> Double =
  #| () => globalThis.performance?.now() ?? Date.now()

///|
/// Wall-clock milliseconds for source paths whose behavior is defined in
/// terms of `Date.now()`.
pub extern "js" fn wall_clock_now_ms() -> Double =
  #| () => Date.now()

///|
/// Schedules one browser macrotask and returns an idempotent cancellation
/// handle. A callback retires its own handle before invoking user code so a
/// reentrant disposal is a no-op.
pub fn schedule_timeout(
  callback : () -> Unit,
  delay_ms : Int,
) -> @base_common.Disposable {
  let mut active = true
  let handle = set_timeout_js(
    () => {
      if active {
        active = false
        callback()
      }
    },
    delay_ms,
  )
  @base_common.Disposable::from(() => {
    if active {
      active = false
      clear_timeout_js(handle)
    }
  })
}

///|
/// Enqueues a callback in the browser microtask queue.
pub extern "js" fn queue_microtask(callback : () -> Unit) -> Unit =
  #| (callback) => globalThis.queueMicrotask(callback)

///|
/// Current CSS-to-device-pixel ratio, with the browser default outside a
/// windowed environment.
pub extern "js" fn device_pixel_ratio() -> Double =
  #| () => globalThis.devicePixelRatio || 1

///|
extern "js" fn set_timeout_js(callback : () -> Unit, delay_ms : Int) -> Double =
  #| (callback, delayMs) => globalThis.setTimeout(callback, delayMs)

///|
extern "js" fn clear_timeout_js(handle : Double) -> Unit =
  #| (handle) => globalThis.clearTimeout(handle)
