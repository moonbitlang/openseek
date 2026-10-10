///|
extern "js" fn pathname() -> String =
  #|() => location.pathname

///|
extern "js" fn search() -> String =
  #|() => location.search

///|
extern "js" fn reload() -> Unit =
  #|() => location.reload()

///|
extern "js" fn random_id() -> String =
  #|() => crypto.randomUUID()

///|
extern "js" fn history_marker() -> @js.Value =
  #|() => history.state?.seekmoonNavigation ?? null

///|
extern "js" fn write_history(
  marker : String,
  path : String,
  replace : Bool,
) -> Unit =
  #|(marker, path, replace) => {
  #|  const state = { ...(replace ? history.state : {}), seekmoonNavigation: JSON.parse(marker) };
  #|  if (replace) history.replaceState(state, '', path);
  #|  else history.pushState(state, '', path);
  #|}

///|
/// Storage is best effort: private browsing or quota failure must not prevent
/// navigation in this document. Missing/unavailable storage returns null.
extern "js" fn storage_get(key : String) -> @js.Value =
  #|key => { try { return sessionStorage.getItem(key); } catch { return null; } }

///|
extern "js" fn storage_set(key : String, value : String) -> Unit =
  #|(key, value) => { try { sessionStorage.setItem(key, value); } catch {} }

///|
/// Freeze legacy documents' relative assets before changing their URL.
extern "js" fn preserve_asset_base() -> Unit =
  #|() => {
  #|  if (!document.querySelector('base')) {
  #|    const base = document.createElement('base'); base.href = document.baseURI;
  #|    document.head.prepend(base);
  #|  }
  #|}

///|
/// This object only dispatches commands/events into MoonBit closures. All
/// history data and transitions are owned by those closures' MoonBit state.
extern "js" fn install_handlers(
  visit : (String, Bool) -> Unit,
  promote : (String, String) -> Unit,
  pop : () -> Unit,
) -> @js.Value =
  #|(visit, promote, pop) => {
  #|  const handle = { visit, promote, pop };
  #|  window.__seekmoonApplicationHistory = handle;
  #|  window.addEventListener('popstate', pop);
  #|  return handle;
  #|}

///|
extern "js" fn dispose(handle : @js.Value) -> Unit =
  #|handle => {
  #|  window.removeEventListener('popstate', handle.pop);
  #|  if (window.__seekmoonApplicationHistory === handle) delete window.__seekmoonApplicationHistory;
  #|}

///|
extern "js" fn visit_raw(path : String, replace : Bool) -> Unit =
  #|(path, replace) => window.__seekmoonApplicationHistory.visit(path, replace)

///|
extern "js" fn promote_raw(old_path : String, new_path : String) -> Unit =
  #|(oldPath, newPath) => window.__seekmoonApplicationHistory.promote(oldPath, newPath)
