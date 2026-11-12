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
extern "js" fn write_history(path : String, replace~ : Bool) -> Unit =
  #|(path, replace) => {
  #|  if (replace) history.replaceState(history.state, '', path);
  #|  else history.pushState(null, '', path);
  #|}

///|
extern "js" fn install_handlers(
  visit : (String, Bool) -> Unit,
  promote : (String, String) -> Unit,
  pop : () -> Unit,
  open : (String) -> Bool,
) -> @js.Value =
  #|(visit, promote, pop, open) => {
  #|  // sw.js asks an open page to show a notification's link in place and
  #|  // falls back to a full navigation unless the page answers true.
  #|  const message = event => {
  #|    if (event.data?.type !== 'seekmoon.open' || typeof event.data.url !== 'string') return;
  #|    event.ports[0]?.postMessage(open(event.data.url));
  #|  };
  #|  const handle = { visit, promote, pop, message };
  #|  window.__seekmoonApplicationHistory = handle;
  #|  window.addEventListener('popstate', pop);
  #|  navigator.serviceWorker?.addEventListener('message', message);
  #|  return handle;
  #|}

///|
extern "js" fn dispose(handle : @js.Value) -> Unit =
  #|handle => {
  #|  window.removeEventListener('popstate', handle.pop);
  #|  navigator.serviceWorker?.removeEventListener('message', handle.message);
  #|  if (window.__seekmoonApplicationHistory === handle) delete window.__seekmoonApplicationHistory;
  #|}

///|
extern "js" fn visit_raw(path : String, replace : Bool) -> Unit =
  #|(path, replace) => window.__seekmoonApplicationHistory.visit(path, replace)

///|
extern "js" fn promote_raw(old_path : String, new_path : String) -> Unit =
  #|(oldPath, newPath) => window.__seekmoonApplicationHistory.promote(oldPath, newPath)
