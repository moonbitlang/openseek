///|
/// The platform shell used to interpret command text: `pwsh` on Windows and
/// `sh` on other targets. Callers pair it with `args` to run a command string
/// with the same semantics whether or not a sandbox wraps the invocation.
///
/// On Windows `program` is a `pub fn` that probes for `pwsh` at runtime
/// (cached process-wide), falling back to `powershell.exe` when `pwsh` is
/// unavailable. On non-Windows it is a `pub fn` returning `"sh"`. A public
/// `#cfg` const would bake whichever value survived into `pkg.generated.mbti`,
/// so regenerating the interface on Windows would rewrite it and the committed
/// one would no longer match. A `fn` records only `program : String`, which is
/// identical on every platform.
///
/// TODO(upstream): support `declare pub let`, so this note can sit on one
/// declaration the way `args` does instead of on the arms.
// declare pub let program : String

///|
/// `pwsh` on Windows — always preferred for its modern syntax (`&&` and other
/// PowerShell 7+ features). Falls back to the inbox `powershell.exe` (Windows
/// PowerShell 5.1) only when `pwsh` is unavailable, so PowerShell 7-only
/// syntax never produces a parser error. The availability probe is cached
/// process-wide.
#cfg(platform="windows")
pub fn program() -> String {
  match pwsh_available() {
    true => "pwsh"
    false => "powershell.exe"
  }
}

///|
/// `sh` on non-Windows targets.
#cfg(not(platform="windows"))
pub fn program() -> String {
  "sh"
}

///|
/// Build arguments that make `program` interpret `cmd` as shell text:
/// `-NoProfile -Command` for PowerShell, `-c` for `sh`.
declare pub fn args(cmd : String) -> Array[String]

///|
/// Build arguments that make `program` interpret `cmd` as shell text
/// (`-NoProfile -Command` for PowerShell). Sets UTF-8 output encoding so
/// commands with non-ASCII text (e.g. Chinese characters) produce valid
/// UTF-8 bytes instead of the system's active code page (GBK/CP936).
/// The flags are identical for `pwsh` and `powershell.exe`.
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
