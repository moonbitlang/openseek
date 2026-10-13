// Algorithm-fidelity port of `AnimationFrameQueueItem`,
// `scheduleAtNextAnimationFrame`, and
// `runAtThisOrScheduleAtNextAnimationFrame` from
// `vscode/src/vs/base/browser/dom.ts`, pinned at
// b18492a288de038fbc7643aae6de8247029d11bd.
//
// The production coordinator is concrete and realm-global. The injected
// native-frame request is retained only on the private coordinator so the
// queue algorithm can be tested without a browser clock.

///|
priv struct AnimationFrameQueueItem {
  callback : () -> Unit
  priority : Int32
  sequence : Int32
  mut canceled : Bool
}

///|
fn AnimationFrameQueueItem::dispose(self : AnimationFrameQueueItem) -> Unit {
  self.canceled = true
}

///|
fn AnimationFrameQueueItem::execute(self : AnimationFrameQueueItem) -> Unit {
  if !self.canceled {
    (self.callback)()
  }
}

///|
priv struct AnimationFrameCoordinator {
  request_native_frame : (() -> Unit) -> Unit
  mut next_queue : Array[AnimationFrameQueueItem]
  mut current_queue : Array[AnimationFrameQueueItem]
  mut native_frame_requested : Bool
  mut in_frame_runner : Bool
  mut next_sequence : Int32
}

///|
fn AnimationFrameCoordinator::AnimationFrameCoordinator(
  request_native_frame : (() -> Unit) -> Unit,
) -> AnimationFrameCoordinator {
  {
    request_native_frame,
    next_queue: [],
    current_queue: [],
    native_frame_requested: false,
    in_frame_runner: false,
    next_sequence: 0,
  }
}

///|
fn AnimationFrameCoordinator::new_item(
  self : AnimationFrameCoordinator,
  callback : () -> Unit,
  priority : Int32,
) -> AnimationFrameQueueItem {
  let item = {
    callback,
    priority,
    sequence: self.next_sequence,
    canceled: false,
  }
  self.next_sequence += 1
  item
}

///|
fn AnimationFrameCoordinator::schedule_next(
  self : AnimationFrameCoordinator,
  item : AnimationFrameQueueItem,
) -> Unit {
  self.next_queue.push(item)
  if !self.native_frame_requested {
    self.native_frame_requested = true
    (self.request_native_frame)(() => self.run_frame())
  }
}

///|
fn AnimationFrameCoordinator::schedule_at_next_animation_frame(
  self : AnimationFrameCoordinator,
  callback : () -> Unit,
  priority : Int32,
) -> @base_common.Disposable {
  let item = self.new_item(callback, priority)
  self.schedule_next(item)
  @base_common.Disposable::from(() => item.dispose())
}

///|
fn AnimationFrameCoordinator::run_at_this_or_schedule_at_next_animation_frame(
  self : AnimationFrameCoordinator,
  callback : () -> Unit,
  priority : Int32,
) -> @base_common.Disposable {
  let item = self.new_item(callback, priority)
  if self.in_frame_runner {
    self.current_queue.push(item)
  } else {
    self.schedule_next(item)
  }
  @base_common.Disposable::from(() => item.dispose())
}

///|
fn AnimationFrameCoordinator::run_frame(
  self : AnimationFrameCoordinator,
) -> Unit {
  self.native_frame_requested = false
  self.current_queue = self.next_queue
  self.next_queue = []
  self.in_frame_runner = true
  while !self.current_queue.is_empty() {
    // JavaScript's stable sort retains FIFO order for equal priorities. The
    // explicit sequence tie-break preserves that observable order even though
    // MoonBit's Array::sort_by is unstable.
    self.current_queue.sort_by((left, right) => {
      let priority_order = right.priority - left.priority
      if priority_order != 0 {
        priority_order
      } else {
        left.sequence - right.sequence
      }
    })
    let item = self.current_queue.remove(0)
    item.execute()
  }
  self.in_frame_runner = false
}

///|
extern "js" fn request_native_animation_frame(callback : () -> Unit) -> Unit =
  #| (callback) => { globalThis.requestAnimationFrame(callback); }

///|
let realm_animation_frame_coordinator : AnimationFrameCoordinator = AnimationFrameCoordinator(
  request_native_animation_frame,
)

///|
/// Registers work for the next native animation frame. Registrations share
/// one realm-global request, execute by descending priority, retain FIFO order
/// at equal priority, and can be canceled through the returned handle.
pub fn schedule_at_next_animation_frame(
  callback : () -> Unit,
  priority~ : Int32 = 0,
) -> @base_common.Disposable {
  realm_animation_frame_coordinator.schedule_at_next_animation_frame(
    callback, priority,
  )
}

///|
/// Registers work in the current coordinated drain when one is active;
/// otherwise registers it for the next native animation frame. Reentrant
/// current-drain work participates in the next descending-priority selection.
pub fn run_at_this_or_schedule_at_next_animation_frame(
  callback : () -> Unit,
  priority~ : Int32 = 0,
) -> @base_common.Disposable {
  realm_animation_frame_coordinator.run_at_this_or_schedule_at_next_animation_frame(
    callback, priority,
  )
}
