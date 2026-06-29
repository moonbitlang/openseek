// Runtime platform probes. MoonBit's `platform` cfg only distinguishes Windows,
// so macOS and Linux — which often need different system commands — are told
// apart at runtime via `uname`.

///|
#cfg(platform="windows")
pub async fn is_darwin() -> Bool {
  false
}

///|
/// Whether the host is macOS (`uname -s` == "Darwin"); false on any failure.
#cfg(not(platform="windows"))
pub async fn is_darwin() -> Bool {
  let (code, stdout, _) = @process.collect_output("uname", ["-s"]) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  guard code == 0 else { return false }
  let name = (stdout.text() catch { _ => "" }).trim()
  name == "Darwin"
}
