// The boundary between the application root and the Skills page. The page
// owns everything only it can see — the registry catalog, the search filter,
// in-flight actions, the failure notice — while the installed library stays a
// root-owned mirror, because the composer's `$` completion reads the same list.

///|
/// The skills library the page acts on: the focused device's engine library,
/// or the signed-in account's Cloud library. Every request the page issues
/// carries it, and every reply is fenced against it, so a result that outlived
/// a switch — to another device, another account, or between the two — is
/// dropped instead of being applied to another library.
#derive(Eq)
pub(all) enum Library {
  Host(@interop.ChannelId)
  Cloud(@cloud_client.Access)
}

///|
pub extend Library with Eq::{equal, not_equal}

///|
/// The two libraries a signed-in Desktop can show, independent of which
/// device or account backs them.
#derive(Eq)
pub(all) enum LibraryKind {
  DeviceLibrary
  CloudLibrary
}

///|
pub extend LibraryKind with Eq::{equal, not_equal}

///|
pub fn Library::kind(self : Library) -> LibraryKind {
  match self {
    Host(_) => DeviceLibrary
    Cloud(_) => CloudLibrary
  }
}

///|
/// A stable key for DOM identity and the preview cache. A Cloud library is
/// keyed by its account epoch, so another account's documents never match.
fn Library::key(self : Library) -> String {
  match self {
    Host(channel) => "host:\{channel.uri_authority()}"
    Cloud(access) => "cloud:\{access.epoch}"
  }
}

///|
/// Cloud's built-ins are always on: the service refuses to disable, update or
/// uninstall them, so the page offers none of those actions.
fn Library::locks_builtins(self : Library) -> Bool {
  self is Cloud(_)
}

///|
/// The root-owned facts the page draws against. `switchable` says whether the
/// page offers the choice between the device's library and Cloud's.
/// `locale` renders request failures the page reports.
#derive(Eq)
pub(all) struct Input {
  library : Library
  installed : Array[InstalledItem]
  switchable : Bool
  locale : @i18n.Locale
}

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
/// What the page asks the root to do. The library is not the page's to
/// refresh: it belongs to the root's mirror, so a successful install, update,
/// or uninstall reports the change and lets the root re-read it from its
/// source. Which library to show is also the root's, so a choice in the
/// switch is reported rather than applied.
#derive(Eq)
pub enum Outcome {
  LibraryChanged(library~ : Library)
  LibrarySelected(LibraryKind)
}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Outcome with Eq::{equal, not_equal}
