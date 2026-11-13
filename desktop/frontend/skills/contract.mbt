// The boundary between the application root and the Skills page. The page
// owns its library selection, installed contents, registry catalog, search
// filter, in-flight actions, and notices. The root supplies source availability
// and keeps the composer's installed library separate from page selection.

///|
/// The skills library the page acts on: a selected device's engine library,
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
/// One library the page can select, including a device that is unavailable.
#derive(Eq)
pub(all) struct LibraryChoice {
  library : Library
  name : String?
  available : Bool
}

///|
pub extend LibraryChoice with Eq::{equal, not_equal}

///|
/// The page's selected library and its most recent installed contents.
#derive(Eq)
pub struct LibrarySelection {
  library : Library
  installed : Array[InstalledItem]
}

///|
pub extend LibrarySelection with Eq::{equal, not_equal}

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
/// The root-owned facts the page draws against. Each choice names a specific
/// device's library or the account's Cloud library.
/// `locale` renders request failures the page reports.
#derive(Eq)
pub(all) struct Input {
  library : Library
  installed : Array[InstalledItem]
  choices : Array[LibraryChoice]
  locale : @i18n.Locale
}

///|
pub fn Input::available(self : Input) -> Bool {
  self.choices.any(choice => choice.library == self.library && choice.available)
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
/// The page asks the root to read from a library after selecting it or
/// completing an install, update, or uninstall. Selection stays in page state;
/// these outcomes route the read through the application's source adapters.
#derive(Eq)
pub enum Outcome {
  LibraryChanged(library~ : Library)
  LibrarySelected(Library)
}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Outcome with Eq::{equal, not_equal}
