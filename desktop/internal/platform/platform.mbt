// Platform probes. MoonBit's `platform` cfg only distinguishes Windows, so
// macOS and Linux are told apart by tonyfettes/platform, whose C stub answers
// from compile-time preprocessor checks — no subprocess, no failure mode.

///|
/// Whether the host is macOS, decided at compile time.
pub fn is_darwin() -> Bool {
  @sys.apple_os_mac
}

///|
/// Whether the host is Windows, decided at compile time. The one platform
/// fact clients care about too: it rides `agent.connected` so a remote
/// client learns the device's path semantics without asking.
pub fn is_windows() -> Bool {
  @sys.win32 || @sys.win64
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
extern "C" fn windows_set_titlebar_dark_mode(dark : Int) -> Int = "moonbit_openseek_desktop_platform_set_titlebar_dark_mode"

///|
fn titlebar_dark_mode_flag(dark : Bool) -> Int {
  if dark {
    1
  } else {
    0
  }
}

///|
/// Keep the native Windows caption glyphs aligned with the app's effective
/// palette. The C side retains this preference across activation and DPI
/// changes because Proton 0.1.x reapplies its own overlay frame there.
/// TODO(https://github.com/moonbit-community/proton/issues/214): After adopting
/// a Proton release that resolves this issue, remove this host-owned Win32
/// workaround, including its FFI entry point and window subclass.
pub fn set_titlebar_dark_mode(dark : Bool) -> Bool {
  guard @sys.win32 || @sys.win64 else { return true }
  windows_set_titlebar_dark_mode(titlebar_dark_mode_flag(dark)) == 0
}

///|
test "titlebar theme converts the effective palette to a native flag" {
  assert_eq(titlebar_dark_mode_flag(false), 0)
  assert_eq(titlebar_dark_mode_flag(true), 1)
}

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
