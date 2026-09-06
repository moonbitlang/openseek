// The boundary between the application root and the Skills page. The page
// owns everything only it can see — the registry catalog, the search filter,
// in-flight actions, the failure notice — while the installed library stays a
// root-owned mirror of the focused host, because the composer's `$` completion
// reads the same list.

///|
/// The root-owned facts the page draws against. `channel` is the focused
/// device: every request the page issues carries it, and every reply is
/// fenced against it, so a result that outlived a focus switch is dropped
/// instead of being applied to another host's library.
pub(all) struct Input {
  channel : @interop.ChannelId
  installed : Array[InstalledItem]
} derive(Eq)

///|
/// Whether a catalog entry (identified by its source label) is already in
/// the local library — at that exact version; an older install keeps the
/// Install button alive as the upgrade path.
fn Input::has_installed(self : Input, source : String) -> Bool {
  self.installed.any(skill => skill.source == source)
}

///|
/// What the page asks the root to do once an action settles. The library is
/// not the page's to refresh: it belongs to the root's focused-host mirror,
/// so a successful install or uninstall reports the change and lets the root
/// re-read it from disk.
pub enum Outcome {
  LibraryChanged(channel~ : @interop.ChannelId)
} derive(Eq)

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Outcome with Eq::{equal, not_equal}
