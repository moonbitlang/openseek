///|
/// Hand `path` to the platform's default opener, returning its exit code. The
/// opener returns as soon as it has handed the file off (LaunchServices on
/// macOS, the desktop portal on Linux), so the code reports the hand-off, not
/// the opened app's lifetime. `path` should already be absolute.
pub async fn open_path(path : String) -> Int32 {
  if @async.platform is Windows {
    windows_open(path)
  } else if @async.platform is MacOS {
    // Respect the file's app association, but fall back to the default text
    // editor for types with none. Oversized source files are deliberately
    // routed here, and extensions such as `.mbt` may have no association.
    let code = @process.run("open", [path])
    if code == 0 {
      code
    } else {
      @process.run("open", ["-t", path])
    }
  } else {
    @process.run("xdg-open", [path])
  }
}

///|
/// Open a URL in the system's default browser, returning the opener's exit
/// code. Unlike `open_path` there is no text-editor fallback — a URL that
/// the opener rejects should fail, not land in an editor.
pub async fn open_url(url : String) -> Int32 {
  if @async.platform is Windows {
    windows_open(url)
  } else if @async.platform is MacOS {
    @process.run("open", [url])
  } else {
    @process.run("xdg-open", [url])
  }
}

///|
/// Show `path` in the host's file manager. macOS and Windows select the exact
/// target; Linux has no universal selection protocol, so its portable fallback
/// opens the containing directory. The code reports the hand-off only.
pub async fn reveal_path(path : String) -> Int32 {
  if @async.platform is Windows {
    windows_reveal(path)
  } else if @async.platform is MacOS {
    @process.run("open", ["-R", path])
  } else {
    @process.run("xdg-open", [@path.Path(path).dirname().to_string()])
  }
}

///|
/// The machine's hostname, for labeling this device on a relay; `None` when
/// the probe fails. `hostname` ships with macOS, Linux, and Windows alike.
pub async fn machine_hostname() -> String? {
  let (code, output, _) = @processx.collect_output_no_stdin("hostname", []) catch {
    _ => return None
  }
  guard code == 0 else { return None }
  let name = output.text().trim().to_owned() catch { _ => return None }
  guard !name.is_empty() else { return None }
  Some(name)
}
