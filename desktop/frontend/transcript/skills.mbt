// Decoding of the host's skill-market replies: the mooncakes.io catalog of
// installable skills and the contents of the engine's global skills
// library.

///|
/// One installable entry of the registry catalog, as the host reports it.
pub(all) struct MarketSkillItem {
  // Registry entry name, e.g. "moonbit-community/meta-skill".
  name : String
  module_name : String
  // Subpackage path relative to the module root; "" for a root skill.
  package_path : String
  version : String
  description : String
  author : String
  repository : String
}

///|
/// One entry of the local skills library.
pub(all) struct InstalledSkillItem {
  // The library entry — the key `skill_uninstall` takes.
  id : String
  // Display name from SKILL.md frontmatter.
  name : String
  description : String
  // `module@version[/package]` for registry installs; "" for a skill the
  // user wrote by hand (which the app never uninstalls).
  source : String
}

///|
/// The source label a catalog entry would carry once installed — the link
/// between a catalog row and the installed list.
pub fn market_source_label(item : MarketSkillItem) -> String {
  if item.package_path.is_empty() {
    "\{item.module_name}@\{item.version}"
  } else {
    "\{item.module_name}@\{item.version}/\{item.package_path}"
  }
}

///|
/// Parse a `skills_catalog` reply. `None` only for structurally unusable
/// JSON; unrecognized entries are skipped so one odd skill cannot blank the
/// whole catalog.
pub fn decode_skills_catalog_reply(text : String) -> Array[MarketSkillItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("skills") is Some(Array(entries)) else { return None }
  let items : Array[MarketSkillItem] = []
  for entry in entries {
    guard entry is Object(fields) else { continue }
    let module_name = json_text(fields, "module_name")
    let version = json_text(fields, "version")
    guard !module_name.is_empty() && !version.is_empty() else { continue }
    items.push({
      name: non_empty_or(json_text(fields, "name"), module_name),
      module_name,
      package_path: json_text(fields, "package_path"),
      version,
      description: json_text(fields, "description"),
      author: json_text(fields, "author"),
      repository: json_text(fields, "repository"),
    })
  }
  Some(items)
}

///|
/// Parse a `skills_installed` reply.
pub fn decode_installed_skills_reply(
  text : String,
) -> Array[InstalledSkillItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("skills") is Some(Array(entries)) else { return None }
  let items : Array[InstalledSkillItem] = []
  for entry in entries {
    guard entry is Object(fields) else { continue }
    let id = json_text(fields, "id")
    guard !id.is_empty() else { continue }
    items.push({
      id,
      name: non_empty_or(json_text(fields, "name"), id),
      description: json_text(fields, "description"),
      source: json_text(fields, "source"),
    })
  }
  Some(items)
}
