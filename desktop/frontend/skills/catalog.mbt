// Projection of typed host skill-market replies into the rows the page draws.
// The installed library is the one skills fact the rest of the app shares —
// the composer's `$` completion reads the same list — so its item type lives
// here beside the page that manages it.

///|
/// One installable entry of the registry catalog, as the host reports it.
pub(all) struct MarketItem {
  // Registry entry name, e.g. "moonbit-community/meta-skill".
  name : String
  module_name : String
  // Subpackage path relative to the module root; "" for a root skill.
  package_path : String
  version : String
  description : String
  author : String
  repository : String
} derive(Eq)

///|
/// One entry of the local skills library.
pub(all) struct InstalledItem {
  // The library entry — the key `skill_uninstall` takes.
  id : String
  // Display name from SKILL.md frontmatter.
  name : String
  description : String
  // `module@version[/package]` for registry installs; "" for a skill the
  // user wrote by hand (which the app never uninstalls).
  source : String
} derive(Eq)

///|
/// The source label a catalog entry would carry once installed — the link
/// between a catalog row and the installed list.
pub fn source_label(item : MarketItem) -> String {
  if item.package_path.is_empty() {
    "\{item.module_name}@\{item.version}"
  } else {
    "\{item.module_name}@\{item.version}/\{item.package_path}"
  }
}

///|
/// Project a `skills_catalog` reply. The native catalog adapter has already
/// removed malformed registry rows before constructing this value.
pub fn catalog_from_reply(
  reply : @protocol.SkillsCatalogReply,
) -> Array[MarketItem] {
  let items : Array[MarketItem] = []
  for entry in reply.skills {
    guard !entry.module_name.is_empty() && !entry.version.is_empty() else {
      continue
    }
    items.push({
      name: if entry.name.is_blank() {
        entry.module_name
      } else {
        entry.name
      },
      module_name: entry.module_name,
      package_path: entry.package_path,
      version: entry.version,
      description: entry.description,
      author: entry.author,
      repository: entry.repository,
    })
  }
  items
}

///|
/// Project a `skills_installed` reply.
pub fn installed_from_reply(
  reply : @protocol.InstalledSkillsReply,
) -> Array[InstalledItem] {
  let items : Array[InstalledItem] = []
  for entry in reply.skills {
    guard !entry.id.is_empty() else { continue }
    items.push({
      id: entry.id,
      name: if entry.name.is_blank() {
        entry.id
      } else {
        entry.name
      },
      description: entry.description,
      source: entry.source,
    })
  }
  items
}

///|
pub extend InstalledItem with Eq::{equal, not_equal}

///|
pub extend MarketItem with Eq::{equal, not_equal}
