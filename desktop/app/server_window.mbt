///|
/// A desktop window can join the exact host a terminal client uses. Its HTTP
/// page selects the existing WebSocket frontend transport and owns no engine,
/// schedules, or Codex app-server process of its own.
async fn run_server_window(url : String) -> Unit {
  guard url.has_prefix("http://") || url.has_prefix("https://") else {
    fail("--server-url requires an http:// or https:// frontend URL")
  }
  let app = @proton.url("SeekMoon", url, width=1120, height=760)
    .load_config()
    .entry_url(url)
    .titlebar_style(Overlay)
    .traffic_light_position(x=16, y=16)
    .on_new_window_request((_, request) => {
      if request.user_gesture {
        // Proton requires a non-raising native event callback. A closed
        // window still refuses the popup while its opener is being cancelled.
        ignore(@extension.open_external({ url: request.url, })) catch {
          error =>
            @xlog.error() <?
              { "event": "external_link_open_failed", "error": "\{error}" }
        }
      }
      Deny
    })
  let app = if @async.platform is Windows {
    app
  } else {
    app.menu(
      MenuBar(menus=[@proton.Menu::role(Edit), @proton.Menu::role(Window)]),
    )
  }
  app.run()
}
