// Announcing a newer hosted release to the webview. The check runs in the
// background of the app-lifetime connect task, so it never delays startup
// and its failures (it reports none) cannot take the engine pump down.

///|
/// The `update_available` event: the newer version and the download page a
/// click should open.
priv struct UpdateAvailablePayload {
  version : String
  url : String
} derive(ToJson)

///|
async fn announce_update(context : @app.AppCommandExtensionContext) -> Unit {
  guard @update.check_for_update(current=@version.AppVersion) is Some(info) else {
    return
  }
  let payload : UpdateAvailablePayload = {
    version: info.version,
    url: info.url,
  }
  context.emit("update_available", payload)
}
