///|
// Each pending lane owns a monotonically increasing generation. A retry only
// runs while its generation is still current, so a remount using the same id
// can supersede stale work without storing callback state on `globalThis`.
#cfg(target="js")
let ui_after_mount_pending : Map[String, Map[String, Int32]] = Map([])

///|
#cfg(target="js")
let ui_after_ready_pending : Map[String, Int32] = Map([])

///|
#cfg(target="js")
let ui_after_operation_generation : Ref[Int32] = Ref(0)

///|
#cfg(target="js")
fn ui_next_after_operation_generation() -> Int32 {
  ui_after_operation_generation.val = ui_after_operation_generation.val + 1
  ui_after_operation_generation.val
}

///|
#cfg(target="js")
fn ui_after_request_frame(callback : () -> Unit) -> Unit {
  if ui_has_window() {
    ignore(@dom.window().request_animation_frame(_ => callback()))
  } else {
    // Non-browser JS tests may not expose a Window. Retrying synchronously
    // preserves the bounded behavior without reaching outside @dom.
    callback()
  }
}

///|
/// Run a DOM operation once an incremental view has actually mounted its
/// element. `create_state_with_init` may enqueue an AfterRender command before
/// the owning `Val::view` has inserted that element into the document. A newer
/// request with the same element id and purpose supersedes an older pending
/// retry, while distinct purposes may wait on the same element independently.
#cfg(target="js")
fn ui_after_mount(
  id : String,
  mounted : () -> Unit,
  purpose~ : String = "default",
) -> Unit {
  let lanes = if ui_after_mount_pending.get(id) is Some(lanes) {
    lanes
  } else {
    let lanes : Map[String, Int32] = Map([])
    ui_after_mount_pending[id] = lanes
    lanes
  }
  let generation = ui_next_after_operation_generation()
  lanes[purpose] = generation
  fn is_current() -> Bool {
    ui_after_mount_pending.get(id) is Some(current_lanes) &&
    current_lanes.get(purpose) == Some(generation)
  }

  fn finish() -> Unit {
    if is_current() {
      lanes.remove(purpose)
      if lanes.length() == 0 {
        ui_after_mount_pending.remove(id)
      }
    }
  }

  fn try_mount(attempt : Int32) -> Unit {
    if !is_current() {
      return
    }
    if !ui_has_document() {
      finish()
    } else if @dom.document().get_element_by_id(id).to_option() is Some(_) {
      finish()
      mounted()
    } else if attempt >= 60 {
      finish()
    } else {
      ui_after_request_frame(() => try_mount(attempt + 1))
    }
  }

  try_mount(0)
}

///|
/// Retry a live-DOM operation until all of its own prerequisites are ready.
/// The key makes a newer operation supersede an older pending retry for the
/// same component and purpose, which prevents stale incremental instances from
/// installing callbacks after a same-id remount.
#cfg(target="js")
fn ui_after_ready(key : String, ready : () -> Bool raise) -> Unit {
  if !ui_has_document() {
    return
  }
  let generation = ui_next_after_operation_generation()
  ui_after_ready_pending[key] = generation
  fn is_current() -> Bool {
    ui_after_ready_pending.get(key) == Some(generation)
  }

  fn finish() -> Unit {
    if is_current() {
      ui_after_ready_pending.remove(key)
    }
  }

  fn try_ready(attempt : Int32) -> Unit {
    if !is_current() {
      return
    }
    let complete = try ready() catch {
      _ => false
    } noraise {
      value => value
    }
    if complete {
      finish()
    } else if attempt >= 60 {
      finish()
    } else {
      ui_after_request_frame(() => try_ready(attempt + 1))
    }
  }

  try_ready(0)
}
