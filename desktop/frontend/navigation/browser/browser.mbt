///|
#derive(Eq)
pub(all) struct Snapshot {
  path : String
}

///|
priv suberror Subscription {
  Subscription(String, @cmd.Emit[Snapshot])
}

///|
pub fn listen(initial_path : String, emit : @cmd.Emit[Snapshot]) -> @sub.Sub {
  @sub.custom_sub(
    "application-history",
    Global,
    Subscription(initial_path, emit),
    loader,
  )
}

///|
fn loader(payload : Error, scheduler : &@cmd.Scheduler) -> @sub.RunningSub? {
  guard payload is Subscription(initial_path, original_emit) else {
    return None
  }
  let mut emit = original_emit
  let handle = install(initial_path, path => scheduler.add(emit({ path, })))
  Some({
    unload: _ => dispose(handle),
    update_tagger: payload => {
      if payload is Subscription(_, next) {
        emit = next
      }
    },
  })
}

///|
pub fn visit(path : String, replace~ : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => visit_raw(path, replace))
}

///|
pub fn promote(old_path : String, new_path : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => promote_raw(old_path, new_path))
}

///|
fn canonical_path(path : String) -> String {
  match @routes.parse(path) {
    Ok(location) => location.path().unwrap_or(path)
    Err(_) => path
  }
}

///|
/// The page owns every application route: the model writes history only for
/// destinations it accepted, and decides itself whether another device's
/// route stays in this page or loads that device's own.
fn install(initial_path : String, emit : (String) -> Unit) -> @js.Value {
  let owns = (path : String) => {
    @routes.is_cloud_path(path) || @routes.device(path) is Some(_)
  }
  write_history(canonical_path(initial_path) + search(), replace=true)
  let report = () => emit(pathname() + search())
  let handle = install_handlers(
    (path, replace) => {
      guard owns(path) else { return }
      let path = canonical_path(path)
      if path != pathname() {
        write_history(path, replace~)
      }
      report()
    },
    (old_path, new_path) => {
      guard owns(new_path) && pathname() == canonical_path(old_path) else {
        return
      }
      write_history(canonical_path(new_path), replace=true)
      report()
    },
    () => {
      let path = pathname()
      guard owns(path) else {
        reload()
        return
      }
      let canonical = canonical_path(path)
      if canonical != path {
        write_history(canonical + search(), replace=true)
      }
      report()
    },
  )
  report()
  handle
}

///|
pub extend Snapshot with Eq::{equal, not_equal}
