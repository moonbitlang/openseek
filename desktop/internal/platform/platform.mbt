// Platform probes. MoonBit's `platform` cfg only distinguishes Windows, so
// macOS and Linux are told apart by tonyfettes/platform, whose C stub answers
// from compile-time preprocessor checks — no subprocess, no failure mode.

///|
/// Whether the host is macOS, decided at compile time.
pub fn is_darwin() -> Bool {
  @sys.apple_os_mac
}

///|
/// Hand `path` to the platform's default opener, returning its exit code. The
/// opener returns as soon as it has handed the file off (LaunchServices on
/// macOS, the desktop portal on Linux), so the code reports the hand-off, not
/// the opened app's lifetime. `path` should already be absolute.
#cfg(platform="windows")
pub async fn open_path(path : String) -> Int {
  // `start` is a `cmd` builtin, so it cannot be spawned directly; the empty
  // "" is its (otherwise required) window-title argument.
  @process.run("cmd", ["/c", "start", "", path])
}

///|
#cfg(not(platform="windows"))
pub async fn open_path(path : String) -> Int {
  if is_darwin() {
    // Respect the file's app association, but fall back to the default text
    // editor for types with none — source files like `.mbt` have no associated
    // app, and plain `open` rejects them with "no application knows how to
    // open" (exit non-zero) rather than showing their contents.
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
