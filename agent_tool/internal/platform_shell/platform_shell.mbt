///|
/// The platform shell used to interpret command text: `pwsh` on Windows and
/// `sh` on other targets. Callers pair it with `args` to run a command string
/// with the same semantics whether or not a sandbox wraps the invocation.
///
/// A `pub let`, not a `pub const`. A public `#cfg` const bakes whichever value
/// survived into `pkg.generated.mbti`, so regenerating the interface on Windows
/// rewrites it to `"pwsh"` and the committed one no longer matches. A `let`
/// records only `program : String`, which is identical on every platform.
///
/// TODO(upstream): support `declare pub let`, so this note can sit on one
/// declaration the way `args` does instead of on the arms.
// declare pub let program : String

///|
/// `powershell.exe` on Windows — always available as a built-in component.
/// `pwsh` (PowerShell 7) is an optional install that many systems lack;
/// fall back to the inbox `powershell.exe` to avoid `Access is denied`
/// when the process host cannot find or execute `pwsh`.
#cfg(platform="windows")
pub let program : String = "powershell.exe"

///|
/// `sh` on non-Windows targets — see the note above.
#cfg(not(platform="windows"))
pub let program : String = "sh"

///|
/// Build arguments that make `program` interpret `cmd` as shell text:
/// `-NoProfile -Command` for PowerShell, `-c` for `sh`.
declare pub fn args(cmd : String) -> Array[String]

///|
/// Build arguments that make `program` interpret `cmd` as shell text
/// (`-NoProfile -Command` for PowerShell). Sets UTF-8 output encoding so
/// commands with non-ASCII text (e.g. Chinese characters) produce valid
/// UTF-8 bytes instead of the system's active code page (GBK/CP936).
/// Uses `powershell.exe` (always available inbox) rather than `pwsh`
/// (optional install many systems lack).
#cfg(platform="windows")
pub fn args(cmd : String) -> Array[String] {
  [
    "-NoProfile",
    "-Command",
    "$OutputEncoding=[Console]::OutputEncoding=[Text.Encoding]::UTF8;chcp 65001 > $null;" +
    cmd,
  ]
}

///|
/// Build arguments that make `program` interpret `cmd` as shell text (`-c` for
/// `sh`).
#cfg(not(platform="windows"))
pub fn args(cmd : String) -> Array[String] {
  ["-c", cmd]
}
