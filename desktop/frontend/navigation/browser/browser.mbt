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
extern "js" fn install(
  initial_path : String,
  emit : (String, Bool, Bool) -> Unit,
) -> @js.Value =
  #|(initialPath, emit) => {
  #|  // Legacy versioned entry documents have relative assets. Freeze their
  #|  // base before the first path replacement, including lazy-loaded assets.
  #|  if (!document.querySelector('base')) {
  #|    const base = document.createElement('base'); base.href = document.baseURI;
  #|    document.head.prepend(base);
  #|  }
  #|  const slot = '__seekmoonApplicationHistory';
  #|  const prefix = 'seekmoon.history.v1.';
  #|  const device = initialPath.split('/')[2];
  #|  const owns = path => typeof path === 'string' && path.startsWith('/device/' + device + '/');
  #|  const read = key => { try { return JSON.parse(sessionStorage.getItem(prefix + key)); } catch { return null; } };
  #|  const token = () => crypto.randomUUID();
  #|  let group, entries, cursor;
  #|  const saved = history.state?.seekmoonNavigation;
  #|  const stored = saved && typeof saved.group === 'string' ? read(saved.group) : null;
  #|  const valid = stored && Array.isArray(stored.entries) && stored.entries.length > 0 &&
  #|    stored.entries.every(e => e && typeof e.key === 'string' && owns(e.path) && owns(e.original));
  #|  const position = (items, key) => items.map((entry, index) => ({ entry, index }))
  #|    .find(({ entry: e }) => e.key === key &&
  #|      (e.original === location.pathname || e.path === location.pathname))?.index;
  #|  const restored = valid ? position(stored.entries, saved.key) : undefined;
  #|  const writeState = (entry, path) => history.replaceState(
  #|    { ...history.state, seekmoonNavigation: { group, key: entry.key } }, '', path);
  #|  const persist = () => { try { sessionStorage.setItem(prefix + group, JSON.stringify({ entries })); } catch {} };
  #|  const report = () => emit(entries[cursor].path + location.search, cursor > 0, cursor + 1 < entries.length);
  #|  const reset = path => {
  #|    group = token(); cursor = 0;
  #|    entries = [{ key: token(), path, original: path }];
  #|    writeState(entries[0], path + location.search); persist();
  #|  };
  #|  if (restored !== undefined) {
  #|    group = saved.group; entries = stored.entries; cursor = restored;
  #|    writeState(entries[cursor], entries[cursor].path + location.search);
  #|  } else { reset(initialPath); }
  #|  const pop = () => {
  #|    if (!owns(location.pathname)) { location.reload(); return; }
  #|    const state = history.state?.seekmoonNavigation;
  #|    const index = state?.group === group ? position(entries, state.key) : undefined;
  #|    if (index === undefined) reset(location.pathname);
  #|    else { cursor = index; writeState(entries[cursor], entries[cursor].path + location.search); }
  #|    report();
  #|  };
  #|  const controller = {
  #|    visit(path, replace) {
  #|      if (!owns(path)) throw new Error('Navigation belongs to another device');
  #|      if (path === entries[cursor].path) { report(); return; }
  #|      if (replace) {
  #|        entries = entries.map((e, i) => i === cursor ? { ...e, path, original: path } : e);
  #|        writeState(entries[cursor], path);
  #|      } else {
  #|        const entry = { key: token(), path, original: path };
  #|        history.pushState({ seekmoonNavigation: { group, key: entry.key } }, '', path);
  #|        entries = [...entries.slice(0, cursor + 1), entry]; cursor++;
  #|      }
  #|      persist(); report();
  #|    },
  #|    promote(oldPath, newPath) {
  #|      if (!owns(newPath)) throw new Error('Navigation belongs to another device');
  #|      entries = entries.map(e => e.path === oldPath ? { ...e, path: newPath } : e);
  #|      if (location.pathname === oldPath) writeState(entries[cursor], entries[cursor].path);
  #|      persist(); report();
  #|    },
  #|    dispose() {
  #|      window.removeEventListener('popstate', pop);
  #|      if (window[slot] === controller) delete window[slot];
  #|    }
  #|  };
  #|  window[slot] = controller;
  #|  window.addEventListener('popstate', pop);
  #|  report();
  #|  return controller;
  #|}

///|
extern "js" fn dispose(handle : @js.Value) -> Unit =
  #|handle => handle.dispose()

///|
extern "js" fn visit_raw(path : String, replace : Bool) -> Unit =
  #|(path, replace) => window.__seekmoonApplicationHistory.visit(path, replace)

///|
extern "js" fn promote_raw(old_path : String, new_path : String) -> Unit =
  #|(oldPath, newPath) => window.__seekmoonApplicationHistory.promote(oldPath, newPath)

///|
pub extend Snapshot with Eq::{equal, not_equal}
