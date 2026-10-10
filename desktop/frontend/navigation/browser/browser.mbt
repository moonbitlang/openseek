///|
pub struct Snapshot {
  path : String
  can_back : Bool
  can_forward : Bool
} derive(Eq)

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
  let handle = install(initial_path, (path, can_back, can_forward) => {
    scheduler.add(emit({ path, can_back, can_forward, }))
  })
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
fn read_marker() -> Json {
  history_marker().to_json() catch {
    _ => Json::null()
  }
}

///|
fn read_stored(group : String) -> Json {
  let value : String? = @js.Cast::into(storage_get(StoragePrefix + group))
  if value is Some(text) {
    @json.parse(text) catch {
      _ => Json::null()
    }
  } else {
    Json::null()
  }
}

///|
const StoragePrefix = "seekmoon.history.v1."

///|
fn persist(history : @browser_history.History) -> Unit {
  storage_set(
    StoragePrefix + history.storage_group(),
    history.stored().stringify(),
  )
}

///|
fn write_entry(
  history : @browser_history.History,
  path : String,
  replace~ : Bool,
) -> Unit {
  write_history(history.marker().stringify(), path, replace)
}

///|
/// Only the effect/subscription runtime reads browser globals. History
/// transitions and persisted-data validation are pure MoonBit operations.
fn install(
  initial_path : String,
  emit : (String, Bool, Bool) -> Unit,
) -> @js.Value {
  preserve_asset_base()
  let marker = read_marker()
  let stored = @browser_history.storage_group(marker).map(read_stored)
  let restored = stored.bind(value => {
    @browser_history.History::restore(initial_path, pathname(), marker, value)
  })
  let mut history = restored.unwrap_or_else(() => {
    @browser_history.History(initial_path, group=random_id(), key=random_id())
  })
  write_entry(history, history.path() + search(), replace=true)
  if restored is None {
    persist(history)
  }
  let report = () => {
    emit(history.path() + search(), history.can_back(), history.can_forward())
  }
  let handle = install_handlers(
    (path, replace) => {
      if path == history.path() {
        report()
        return
      }
      guard history.visit(path, replace~, key=random_id()) is Some(next) else {
        return
      }
      write_entry(next, path, replace~)
      history = next
      persist(history)
      report()
    },
    (old_path, new_path) => {
      guard history.promote(old_path, new_path) is Some(next) else { return }
      history = next
      if pathname() == old_path {
        write_entry(history, history.path(), replace=true)
      }
      persist(history)
      report()
    },
    () => {
      let path = pathname()
      if !history.owns(path) {
        reload()
        return
      }
      let selected = history.select(path, read_marker())
      history = selected.unwrap_or_else(() => {
        @browser_history.History(path, group=random_id(), key=random_id())
      })
      write_entry(history, history.path() + search(), replace=true)
      if selected is None {
        persist(history)
      }
      report()
    },
  )
  report()
  handle
}

///|
pub extend Snapshot with Eq::{equal, not_equal}
