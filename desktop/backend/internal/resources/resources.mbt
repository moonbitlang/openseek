///|
/// Where this host's bundled files live, as the process that started it
/// knows it. The desktop window host reads both facts from Proton and hands
/// them on, so no operation in this module has to ask a window toolkit where
/// its files are.
///
/// `dir` is Proton's resource directory: the package root holding canonical
/// `seekmoon/` when `packaged`, and the checkout's `desktop/` otherwise.
pub(all) struct Resources {
  dir : @pathx.Path
  packaged : Bool
}
