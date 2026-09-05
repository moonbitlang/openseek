// Platform probes. MoonBit's `platform` cfg only distinguishes Windows, so
// macOS and Linux are told apart by tonyfettes/platform, whose C stub answers
// from compile-time preprocessor checks — no subprocess, no failure mode.

///|
/// Whether the host is macOS, decided at compile time.
pub fn is_darwin() -> Bool {
  @sys.apple_os_mac
}

///|
/// Whether the host is Windows, decided at compile time.
pub fn is_windows() -> Bool {
  @sys.win32 || @sys.win64
}

///|
/// This host's platform in the protocol's vocabulary. It rides
/// `agent.connected` so a remote client learns the device's operating
/// system — and with it the path semantics — without asking.
pub fn host_platform() -> @protocol.HostPlatform {
  if is_windows() {
    Windows
  } else if is_darwin() {
    MacOS
  } else {
    Linux
  }
}

///|
/// Hand one UTF-16 target to the native opener. The C stub calls
/// `ShellExecuteW` on Windows and returns failure elsewhere; the public
/// wrappers only select it on Windows. MoonBit strings are NUL-terminated
/// UTF-16 on the native backend, which is exactly what `ShellExecuteW`
/// consumes, so no command interpreter sees the target.
#borrow(target)
extern "C" fn windows_open(target : String) -> Int = "moonbit_openseek_desktop_platform_open"

///|
/// Ask Explorer to show and select one path without routing it through a
/// command interpreter. The non-Windows stub fails closed; the public wrapper
/// selects it only on Windows.
#borrow(target)
extern "C" fn windows_reveal(target : String) -> Int = "moonbit_openseek_desktop_platform_reveal"

///|
/// Hand `path` to the platform's default opener, returning its exit code. The
/// opener returns as soon as it has handed the file off (LaunchServices on
/// macOS, the desktop portal on Linux), so the code reports the hand-off, not
/// the opened app's lifetime. `path` should already be absolute.
pub async fn open_path(path : String) -> Int {
  if @sys.win32 || @sys.win64 {
    windows_open(path)
  } else if is_darwin() {
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
pub async fn open_url(url : String) -> Int {
  if @sys.win32 || @sys.win64 {
    windows_open(url)
  } else if is_darwin() {
    @process.run("open", [url])
  } else {
    @process.run("xdg-open", [url])
  }
}

///|
/// Show `path` in the host's file manager. macOS and Windows select the exact
/// target; Linux has no universal selection protocol, so its portable fallback
/// opens the containing directory. The code reports the hand-off only.
pub async fn reveal_path(path : String) -> Int {
  if @sys.win32 || @sys.win64 {
    windows_reveal(path)
  } else if is_darwin() {
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
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code == 0 else { return None }
  let name = output.text().trim().to_owned() catch {
      error if @async.is_being_cancelled() => raise error
      _ => return None
    }
  guard !name.is_empty() else { return None }
  Some(name)
}
