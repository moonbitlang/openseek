///|
/// wasm has no Windows shell to hand a target to. The public wrappers select
/// this path only on Windows; it fails closed with a non-zero exit code, like
/// the native stub off Windows.
fn windows_open(_target : String) -> Int32 {
  1
}

///|
/// wasm has no Explorer to select a path in; fails closed with a non-zero
/// exit code, like the native stub off Windows.
fn windows_reveal(_target : String) -> Int32 {
  1
}
