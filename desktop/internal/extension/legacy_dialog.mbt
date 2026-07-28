// The old desktop sidebar's native folder picker. It remains local to the
// Proton bridge compatibility profile; the shared host catalog uses
// `fs.browse` and never lets a remote browser open a native dialog.

///|
priv struct LegacyPickFolderReply {
  path : String?
} derive(ToJson)

///|
/// MoonBit's platform cfg distinguishes Windows; macOS versus Linux remains
/// the platform package's runtime probe.
#cfg(platform="windows")
const LegacyWindows = true

///|
#cfg(not(platform="windows"))
const LegacyWindows = false

///|
async fn DesktopBridgeActor::pick_workspace(
  self : DesktopBridgeActor,
  request_context : @app.AppCommandRequestContext,
) -> LegacyPickFolderReply {
  if LegacyWindows {
    return self.pick_workspace_windows()
  }
  if !@platform.is_darwin() {
    raise @host.HostError("no system folder picker on this platform")
  }
  let window = @proton_native.WindowRef::unsafe_from_handle(
    request_context.window(),
  )
  let dialog = window.begin_choose_directory_dialog(
    Some("Choose a project folder"),
    None,
  ) catch {
    error =>
      raise @host.HostError(
        "could not open the folder picker: " + error.message(),
      )
  }
  // Managed Proton wakes this request context when the AppKit sheet finishes.
  // Poll before waiting so a callback delivered between revisions is kept.
  let mut selected = ""
  let mut waiting = true
  while waiting {
    let revision = request_context.wake_revision()
    let result = window.poll_dialog_result(dialog) catch {
      error =>
        raise @host.HostError(
          "could not open the folder picker: " + error.message(),
        )
    }
    match result {
      Ready(text) => {
        selected = text
        waiting = false
      }
      Pending => request_context.wait_for_wake(revision)
    }
  }
  { path: self.normalize_workspace(selected) }
}

///|
/// Windows still uses the managed PowerShell folder dialog; the desktop page
/// falls back to its manual path input when this command fails.
async fn DesktopBridgeActor::pick_workspace_windows(
  self : DesktopBridgeActor,
) -> LegacyPickFolderReply {
  let script = "Add-Type -AssemblyName System.Windows.Forms; " +
    "$d = New-Object System.Windows.Forms.FolderBrowserDialog; " +
    "if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) " +
    "{ [Console]::Out.Write($d.SelectedPath) }"
  let (code, stdout, _) = @process.collect_output("powershell", [
    "-NoProfile", "-STA", "-Command", script,
  ]) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise @host.HostError("could not open the folder picker: \{error}")
  }
  guard code == 0 else { return { path: None } }
  let text = (stdout.text() catch { _ => return { path: None } })
    .trim()
    .to_owned()
  { path: self.normalize_workspace(text) }
}

///|
fn DesktopBridgeActor::normalize_workspace(
  self : DesktopBridgeActor,
  text : String,
) -> String? {
  ignore(self)
  guard !text.is_empty() else { return None }
  let mut end = text.length()
  while end > 1 &&
        (text.code_unit_at(end - 1) == 47 || text.code_unit_at(end - 1) == 92) {
    end = end - 1
  }
  Some(text.view(end_offset=end).to_owned())
}
