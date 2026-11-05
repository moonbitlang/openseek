// Ported from `vscode/src/vs/base/common/platform.ts` (the OS facts only).
// Monaco reads `process.platform` in a native environment and falls back to
// `navigator.userAgent` sniffing in a browser; the js target applies the
// same order (`platform_js.mbt`) so unit tests under Node and browser runs
// agree on the host OS. Non-js targets report an unknown platform
// (`platform_fallback.mbt`) — they exist only for the no-DOM boundary check.

///|
#derive(Eq)
priv enum HostPlatform {
  Mac
  Windows
  Linux
  UnknownPlatform
}

///|
let host_platform : HostPlatform = match detect_platform_code() {
  1 => Mac
  2 => Windows
  3 => Linux
  _ => UnknownPlatform
}

///|
/// Monaco `platform.isMacintosh`.
pub let is_macintosh : Bool = host_platform == Mac

///|
/// Monaco `platform.isWindows`.
pub let is_windows : Bool = host_platform == Windows

///|
/// D8 test seam for the URI/path stack: `None` reads the host platform.
let is_windows_override : Ref[Bool?] = { val: None, }

///|
/// `path.ts:82 platformIsWin32` / the `platform.isWindows` reads inside
/// `uri.ts` and `resources.ts`. Monaco binds the value at module load; we
/// read it per call so the D8 test seam can flip it (observationally
/// identical — the platform never changes mid-session, Deviation D1).
pub fn platform_is_win32() -> Bool {
  is_windows_override.val.unwrap_or(is_windows)
}
