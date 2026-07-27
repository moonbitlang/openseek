// The system folder picker behind the sidebar's "Add workspace". macOS goes
// through Proton's async sheet dialog: the panel is shown without nesting a
// modal run loop, so the bridge, timers and the CEF pump keep breathing while
// it is open. Windows still shells out to PowerShell's FolderBrowserDialog
// until the async dialog grows a win32 backend. `path: None` means the user
// cancelled; a platform without a chooser errors, and the frontend falls back
// to its manual path input.

///|
priv struct PickFolderReply {
  path : String?
} derive(ToJson)

///|
#cfg(not(platform="windows"))
async fn pick_workspace_op(
  request_context : @app.AppCommandRequestContext,
) -> PickFolderReply {
  guard @platform.is_darwin() else {
    raise HostError("no system folder picker on this platform")
  }
  let window = @proton_native.WindowRef::unsafe_from_handle(
    request_context.window(),
  )
  let dialog = window.begin_choose_directory_dialog(
    Some("Choose a project folder"),
    None,
  ) catch {
    error =>
      raise HostError("could not open the folder picker: " + error.message())
  }
  // Proton's managed runner reports native callbacks through the request
  // context wake signal. Poll before waiting so a callback delivered between
  // revisions cannot be lost.
  let mut selected = ""
  let mut waiting = true
  while waiting {
    let revision = request_context.wake_revision()
    let result = window.poll_dialog_result(dialog) catch {
      error =>
        raise HostError("could not open the folder picker: " + error.message())
    }
    match result {
      Ready(text) => {
        selected = text
        waiting = false
      }
      Pending => request_context.wait_for_wake(revision)
    }
  }
  { path: normalized_folder(selected) }
}

///|
#cfg(platform="windows")
async fn pick_workspace_op(
  request_context : @app.AppCommandRequestContext,
) -> PickFolderReply {
  ignore(request_context)
  // -STA: FolderBrowserDialog needs a single-threaded apartment.
  let script = "Add-Type -AssemblyName System.Windows.Forms; " +
    "$d = New-Object System.Windows.Forms.FolderBrowserDialog; " +
    "if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) " +
    "{ [Console]::Out.Write($d.SelectedPath) }"
  let (code, stdout, _) = @process.collect_output("powershell", [
    "-NoProfile", "-STA", "-Command", script,
  ]) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("could not open the folder picker: \{error}")
  }
  guard code == 0 else { return { path: None } }
  let text = (stdout.text() catch { _ => return { path: None } })
    .trim()
    .to_owned()
  { path: normalized_folder(text) }
}

///|
/// A picker result as a registry-ready path: the trailing separator the
/// macOS chooser appends comes off (except on the filesystem root), and an
/// empty selection reads as cancelled.
fn normalized_folder(text : String) -> String? {
  guard !text.is_empty() else { return None }
  let mut end = text.length()
  while end > 1 &&
        (text.code_unit_at(end - 1) == 47 || text.code_unit_at(end - 1) == 92) {
    end = end - 1
  }
  Some(text.view(end_offset=end).to_owned())
}
