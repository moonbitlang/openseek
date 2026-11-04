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
