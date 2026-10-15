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
/// Index installed registry coordinates once for catalog filtering.
/// Hand-written skills have no registry identity and do not enter the set.
fn Input::installed_registry_skills(self : Input) -> Set[(String, String)] {
  let installed : Set[(String, String)] = Set([])
  for skill in self.installed {
    if skill.registry is Some(registry) {
      installed.add((registry.module_name, registry.package_path))
    }
  }
  installed
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
