///|
/// Process-wide cache for the pwsh availability probe.
#cfg(platform="windows")
let pwsh_available_cache : Ref[Bool?] = { val: None }

///|
/// Probe whether `pwsh` is available on this system by running a lightweight
/// no-op. The result is cached process-wide.
#cfg(platform="windows")
extern "c" fn _system(cmd : Bytes) -> Int = "system"

///|
#cfg(platform="windows")
fn pwsh_available() -> Bool {
  match pwsh_available_cache.val {
    Some(value) => value
    None => {
      let value = _system(b"pwsh -NoProfile -Command exit 0 > nul 2>&1") == 0
      pwsh_available_cache.val = Some(value)
      value
    }
  }
}
