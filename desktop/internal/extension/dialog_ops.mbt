// The system folder picker behind the sidebar's "Add workspace". The host
// shells out to the platform's chooser — AppleScript's `choose folder` on
// macOS, WinForms' FolderBrowserDialog on Windows — rather than linking a
// native dialog: the picker runs out of process, so the UI thread and the
// async runtime keep breathing while it is open. `path: None` means the user
// cancelled; a platform without a chooser raises, and the frontend falls
// back to its manual path input.

///|
priv struct PickFolderReply {
  path : String?
} derive(ToJson)

///|
async fn pick_workspace_op() -> PickFolderReply {
  { path: pick_folder() }
}

///|
#cfg(not(platform="windows"))
async fn pick_folder() -> String? {
  let supported = @platform.is_darwin() catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  guard supported else {
    raise HostError("no system folder picker on this platform")
  }
  let (code, stdout, _) = @process.collect_output("osascript", [
    "-e", "POSIX path of (choose folder with prompt \"Choose a project folder\")",
  ]) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("could not open the folder picker: \{error}")
  }
  // Cancelling reads as a non-zero exit ("User canceled." on stderr), not
  // as an error worth surfacing.
  guard code == 0 else { return None }
  let text = (stdout.text() catch { _ => return None }).trim().to_owned()
  normalized_folder(text)
}

///|
#cfg(platform="windows")
async fn pick_folder() -> String? {
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
  guard code == 0 else { return None }
  let text = (stdout.text() catch { _ => return None }).trim().to_owned()
  normalized_folder(text)
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
