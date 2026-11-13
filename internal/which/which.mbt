// Finding a program on a `PATH` the way a caller that must not run a
// checkout's own copy needs: only absolute directories count, so neither the
// current directory (which Windows searches first) nor a relative entry can
// supply the program.

///|
#cfg(platform="windows")
const ExecutableSuffix : String = ".exe"

///|
#cfg(not(platform="windows"))
const ExecutableSuffix : String = ""

///|
#cfg(platform="windows")
const PathListSeparator : String = ";"

///|
#cfg(not(platform="windows"))
const PathListSeparator : String = ":"

///|
#cfg(platform="windows")
fn is_absolute_dir(dir : String) -> Bool {
  dir.has_prefix("\\\\") || dir is [_, ':', '\\' | '/', ..]
}

///|
#cfg(not(platform="windows"))
fn is_absolute_dir(dir : String) -> Bool {
  dir.has_prefix("/")
}

///|
/// The path of the first `program` (with `.exe` appended on Windows) in an
/// absolute directory of `path`, a `PATH` value; relative and empty entries
/// are skipped. `None` when no such directory holds it.
pub async fn find(program : String, path~ : String) -> String? {
  for dir in path.split(PathListSeparator) {
    let dir = dir.to_owned()
    guard is_absolute_dir(dir) else { continue }
    let candidate = "\{dir}/\{program}\{ExecutableSuffix}"
    let found = @fs.exists(candidate) catch { _ => false }
    if found {
      break Some(candidate)
    }
  } nobreak {
    None
  }
}
