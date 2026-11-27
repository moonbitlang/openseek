// Deliberate exports whose consumer lives outside this workspace (see
// shrink_package.md): the window host in `desktop/app` is a sibling module with
// its own `desktop/app/moon.work`, so `moon ide analyze` run from the repository
// root never sees its uses of the preview server. Each block names its caller.

///|
/// Build the server the window host starts before it opens a window. Every
/// field is private, so this constructor is the only way to make one.
///
/// Exported for the window host, which owns one server for the app's lifetime
/// (`desktop/app/main.mbt:152`) and defaults a parameter to it
/// (`desktop/app/internal/extension/browser_views.mbt:53`).
pub fn Server::Server(
  engine~ : String = "",
  runtime_dir? : @pathx.Path,
) -> Server {
  {
    moonx: @moonbit.MoonxProvider(engine~, runtime_dir~, source=DesktopBundle),
    group: None,
    tabs: Map([]),
  }
}

///|
/// Give the server the application's task group, so every preview process it
/// spawns lives no longer than the window does.
///
/// Exported for the window host's `BrowserViews::start_previews`
/// (`desktop/app/internal/extension/browser_views.mbt:85`).
pub fn Server::start(self : Server, group : @async.TaskGroup) -> Unit {
  self.group = Some(group)
}

///|
/// Serve one preview tab and return the loopback URL to load. Replacing an id
/// closes the tab's previous process first.
///
/// Exported for the window host's `browser.preview` endpoint
/// (`desktop/app/internal/extension/browser_views.mbt:486`).
pub async fn Server::open(
  self : Server,
  id : Int32,
  path : String,
  root? : String,
) -> String {
  guard self.group is Some(group) else {
    fail("Local HTML preview runtime is unavailable")
  }
  self.close(id)
  let ready : @async.Queue[String] = @async.Queue(kind=Blocking(1))
  let task = group.spawn(no_wait=true, allow_failure=true, () => {
    defer (if self.tabs.get(id) is Some((current, _)) &&
      physical_equal(current, ready) {
      self.tabs.remove(id)
    })
    serve(self.moonx, path, root?, ready) catch {
      error => ready.close(error~)
    }
    ready.close()
  })
  self.tabs[id] = (ready, task)
  errdefer (if self.tabs.get(id) is Some((current, _)) &&
    physical_equal(current, ready) {
    self.close(id)
  })
  let url = ready.get()
  guard self.tabs.get(id) is Some((current, _)) &&
    physical_equal(current, ready) else {
    fail("Preview was closed")
  }
  url
}

///|
/// Stop one tab's preview process; closing a tab that is already gone is not an
/// error.
///
/// Exported for the window host's `browser.close` handler and the failed-open
/// cleanup of `browser.preview`
/// (`desktop/app/internal/extension/browser_views.mbt:444`, `:491`).
pub fn Server::close(self : Server, id : Int32) -> Unit {
  if self.tabs.get(id) is Some((ready, task)) {
    self.tabs.remove(id)
    ready.close()
    task.cancel()
  }
}

///|
/// Stop every preview process, for a window close or a page reload that
/// discards the tabs it had.
///
/// Exported for the window host's window-close and `host.connect` reset
/// (`desktop/app/internal/extension/browser_views.mbt:100`, `:117`).
pub fn Server::clear(self : Server) -> Unit {
  for _, (ready, task) in self.tabs {
    ready.close()
    task.cancel()
  }
  self.tabs.clear()
}
