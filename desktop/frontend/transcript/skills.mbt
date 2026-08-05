// Projection of typed host skill-market replies into the UI's catalog and
// installed-library rows.

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
} derive(Eq)

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
} derive(Eq)

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
/// Project a `skills_catalog` reply. The native catalog adapter has already
/// removed malformed registry rows before constructing this value.
pub fn skills_catalog_from_reply(
  reply : @desktop_protocol.SkillsCatalogReply,
) -> Array[MarketSkillItem] {
  let items : Array[MarketSkillItem] = []
  for entry in reply.skills {
    guard !entry.module_name.is_empty() && !entry.version.is_empty() else {
      continue
    }
    items.push({
      name: if entry.name.trim().is_empty() {
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
pub fn installed_skills_from_reply(
  reply : @desktop_protocol.InstalledSkillsReply,
) -> Array[InstalledSkillItem] {
  let items : Array[InstalledSkillItem] = []
  for entry in reply.skills {
    guard !entry.id.is_empty() else { continue }
    items.push({
      id: entry.id,
      name: if entry.name.trim().is_empty() {
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
test "skills catalog replies decode and skip odd entries" {
  let items = skills_catalog_from_reply({
    skills: [
      {
        name: "acme/widget",
        module_name: "acme/widget",
        package_path: "",
        version: "1.0.0",
        description: "Build widgets fast.",
        author: "acme",
        repository: "https://example.com/acme/widget",
      },
      {
        name: "odd",
        module_name: "",
        package_path: "",
        version: "1.0.0",
        description: "",
        author: "",
        repository: "",
      },
    ],
  })
  guard items is [item] else { fail("expected exactly one catalog item") }
  assert_eq(item.name, "acme/widget")
  assert_eq(item.module_name, "acme/widget")
  assert_eq(item.version, "1.0.0")
  assert_eq(item.description, "Build widgets fast.")
  assert_eq(market_source_label(item), "acme/widget@1.0.0")
}

///|
test "subpackage skills carry their package path in the source label" {
  let items = skills_catalog_from_reply({
    skills: [
      {
        name: "alice/alpha/cmd/run",
        module_name: "alice/alpha",
        package_path: "cmd/run",
        version: "0.2.0",
        description: "Run alpha commands",
        author: "",
        repository: "",
      },
    ],
  })
  guard items is [item] else { fail("expected one catalog item") }
  assert_eq(market_source_label(item), "alice/alpha@0.2.0/cmd/run")
  assert_eq(item.author, "")
}

///|
test "installed skill replies decode, with name falling back to id" {
  let items = installed_skills_from_reply({
    skills: [
      {
        id: "acme-widget",
        name: "widget",
        description: "Build widgets fast.",
        source: "acme/widget@1.0.0",
      },
      { id: "handmade", name: "", description: "", source: "" },
      { id: "", name: "no-id", description: "", source: "" },
    ],
  })
  guard items is [widget, handmade] else {
    fail("expected two installed items")
  }
  assert_eq(widget.id, "acme-widget")
  assert_eq(widget.name, "widget")
  assert_eq(widget.source, "acme/widget@1.0.0")
  assert_eq(handmade.name, "handmade")
  assert_eq(handmade.source, "")
}
