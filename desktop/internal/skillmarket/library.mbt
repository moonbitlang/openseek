// The local skills library: installing a registry skill archive into the
// engine's global skills directory, listing what is there, and removing what
// this app installed. The directory layout and frontmatter rules deliberately
// mirror the engine's `agent_skill` discovery (`<name>.md` flat files and
// `<name>/SKILL.md` directories, here with the archive's supporting files
// beside the SKILL.md), so the panel lists exactly what the engine
// advertises to the model.

///|
/// The provenance marker written next to an installed SKILL.md. The engine's
/// discovery only reads `*.md`, so the sidecar never leaks into prompts; its
/// presence is what makes an entry ours to overwrite or uninstall.
const SidecarFile = ".mooncakes.json"

///|
/// One entry of the local skills library.
pub struct InstalledSkill {
  // The library entry (directory or file stem) — the key uninstall takes.
  id : String
  // Display name from SKILL.md frontmatter, falling back to `id`.
  name : String
  description : String
  // `module@version[/package]` recorded at install time; "" for a skill the
  // user wrote by hand (which this package will never touch).
  source : String
} derive(ToJson)

///|
/// Where the library lives: `OPENSEEK_GLOBAL_SKILLS_DIR`, else the user's
/// home directory (`HOME`, or `USERPROFILE` on Windows) plus
/// `/.openseek/skills`. Deliberately resolved like the engine resolves it:
/// installing somewhere the engine never reads would be a silent no-op.
fn library_dir_from_env() -> @pathx.Path raise SkillMarketError {
  if @env.get("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(dir) {
    return dir
  }
  if @home.dir() is Some(home) {
    return home.join(".openseek/skills")
  }
  raise SkillMarketError(
    "cannot locate the skills library; set OPENSEEK_GLOBAL_SKILLS_DIR",
  )
}

///|
/// Whether `name` is a safe single path segment for the library — lowercase
/// `[a-z0-9-]`, at most 64 chars. `slugify` produces these; the check is a
/// final guard that the derived slug is non-empty and in range before it
/// becomes a directory name, so registry data can never path-escape the
/// library.
fn valid_slug(name : String) -> Bool {
  if name.is_empty() || name.length() > 64 {
    return false
  }
  name.iter().all(ch => ch is ('a'..='z' | '0'..='9' | '-'))
}

///|
/// A safe single-segment library name derived from a skill's `owner/name`
/// identity: lowercased, with every run of other characters collapsed to one
/// `-` and no leading or trailing `-`. `Yoorkin/cowsay` -> `yoorkin-cowsay`.
/// The registry's own (possibly slash-bearing) name can never become a path.
fn slugify(name : String) -> String {
  let builder = StringBuilder()
  let mut wrote_alnum = false
  let mut pending_dash = false
  for ch in name {
    let lowered = if ch is ('A'..='Z') { ch.to_ascii_lowercase() } else { ch }
    if lowered is ('a'..='z' | '0'..='9') {
      if pending_dash && wrote_alnum {
        builder.write_char('-')
      }
      builder.write_char(lowered)
      wrote_alnum = true
      pending_dash = false
    } else {
      pending_dash = true
    }
  }
  let slug = builder.to_string()
  if slug.length() > 64 {
    slug.clamped_view(end=64).to_owned()
  } else {
    slug
  }
}

///|
/// The `sha256:`-prefixed hex digest of `content`: how a downloaded skill
/// archive is checked against the digest the registry declares, and what an
/// install's provenance sidecar records.
fn content_digest(content : Bytes) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(content))}"
}

///|
/// Parse `name:` and `description:` from a markdown frontmatter block —
/// the same rules as the engine's `agent_skill` parser, so the panel shows
/// the names the model will see. Anything missing falls back to
/// `fallback_name` / empty.
fn parse_frontmatter(text : String, fallback_name : String) -> (String, String) {
  let mut name = fallback_name
  let mut description = ""
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  guard lines is [first, .. rest] && first.trim() == "---" else {
    return (name, description)
  }
  for line in rest {
    if line.trim() == "---" {
      break
    }
    if line.find(":") is Some(index) {
      let key = line[0:index].to_owned().trim().to_owned()
      let value = line[index + 1:].to_owned().trim().to_owned()
      match key {
        "name" => if !value.is_empty() { name = value }
        "description" => description = value
        _ => ()
      }
    }
  }
  (name, description)
}

///|
fn source_label(
  module_name : String,
  version : String,
  package_path : String,
) -> String {
  entry_path(module_name, version, package_path)
}

///|
fn decode_sidecar(text : String) -> String {
  let json = @json.parse(text) catch { _ => return "" }
  guard json
    is { "module": String(module_name), "version": String(version), .. } else {
    return ""
  }
  let package_path = if json is { "package": String(package_path), .. } {
    package_path
  } else {
    ""
  }
  source_label(module_name, version, package_path)
}

///|
/// Download one skill archive and install it as `<library>/<slug>/` — its
/// SKILL.md plus any supporting files. The per-skill API locates the archive
/// and its digest; the download is verified against that digest before any
/// entry is unpacked. The slug is derived from the skill's `owner/name`
/// identity, so registry data can never path-escape the library. A same-named
/// entry the user wrote by hand (no sidecar) is never overwritten; one we
/// installed is — that is a reinstall or an upgrade. `on_committed` runs after
/// the complete staged directory becomes live, while the library lock and
/// cancellation shield are still held.
pub async fn install_skill(
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  registry? : String = DefaultRegistry,
  library_dir? : @pathx.Path = library_dir_from_env(),
  on_committed? : () -> Unit,
) -> InstalledSkill {
  let entry = entry_path(module_name, version, package_path)
  let source = fetch_archive_source(registry, entry)
  let identity = if package_path.is_empty() {
    module_name
  } else {
    "\{module_name}/\{package_path}"
  }
  let slug = slugify(identity)
  guard valid_slug(slug) else {
    raise SkillMarketError("registry entry \{entry} has no installable name")
  }
  let target = library_dir.join(slug)
  let sidecar = target.join(SidecarFile)
  let flat_target = @pathx.Path("\{target}.md")
  if @fsx.exists(flat_target) || (@fsx.exists(target) && !@fsx.exists(sidecar)) {
    raise SkillMarketError(
      "a skill named \{slug} already exists in your library; not overwriting it",
    )
  }
  let skill = skill_files(fetch_archive(entry, source), entry)
  let text = @utf8.decode(skill.skill_md) catch {
    _ =>
      raise SkillMarketError(
        "the archive for \{entry} holds an unreadable SKILL.md",
      )
  }
  let (name, description) = parse_frontmatter(text, slug)
  let installed = {
    id: slug,
    name,
    description,
    source: source_label(module_name, version, package_path),
  }
  let provenance : Json = {
    "module": module_name,
    "version": version,
    "package": package_path,
    "digest": source.digest,
  }
  library_lock.acquire()
  defer library_lock.release()
  let library : SkillLibrary = { root: library_dir, }
  library.recover()
  // Re-check ownership only after acquiring the process-wide boundary:
  // another request may have installed this slug while the network fetch ran.
  if @fsx.exists(flat_target) || (@fsx.exists(target) && !@fsx.exists(sidecar)) {
    raise SkillMarketError(
      "a skill named \{slug} already exists in your library; not overwriting it",
    )
  }
  library.stage(slug, skill.files, provenance.stringify())
  library.activate(slug, on_committed?)
  installed
}

///|
/// The library's contents, mirroring the engine's discovery rules: every
/// `<name>.md`, plus every `<name>/SKILL.md`. A missing or unreadable
/// library is an empty one. Entries we installed carry their registry
/// source; everything else is the user's own.
pub async fn installed_skills(
  library_dir? : @pathx.Path = library_dir_from_env(),
) -> Array[InstalledSkill] {
  library_lock.acquire()
  defer library_lock.release()
  let library : SkillLibrary = { root: library_dir, }
  library.recover()
  let entries = if @fsx.Directory::try_open(library_dir) is Some(dir) {
    dir.collect()
  } else {
    []
  }
  let skills : Array[InstalledSkill] = []
  for entry in entries {
    let entry = entry.name()
    let path = library_dir.join(entry)
    if entry is [.. id, .. ".md"] {
      guard @fsx.try_read_text(path) is Some(text) else { continue }
      let id = id.to_owned()
      let (name, description) = parse_frontmatter(text, id)
      skills.push({ id, name, description, source: "", })
    } else {
      guard @fsx.try_read_text(path.join("SKILL.md")) is Some(text) else {
        continue
      }
      let (name, description) = parse_frontmatter(text, entry)
      let source = if @fsx.try_read_text(path.join(SidecarFile))
        is Some(sidecar) {
        decode_sidecar(sidecar)
      } else {
        ""
      }
      skills.push({ id: entry, name, description, source, })
    }
  }
  // Sort like the engine's discovery does: readdir order is platform-defined,
  // and the marketplace listing should be stable across runs and platforms.
  skills.sort_by((a, b) => a.name.compare(b.name))
  skills
}

///|
/// Read an installed skill without exposing the library root to the frontend.
pub async fn read_skill_content(
  id : String,
  library_dir? : @pathx.Path = library_dir_from_env(),
) -> String {
  guard valid_slug(id) else {
    raise SkillMarketError("invalid skill id: \{id}")
  }
  let directory_file = library_dir.join(id).join("SKILL.md")
  let flat_file = library_dir.join("\{id}.md")
  let path = if @fsx.exists(directory_file) {
    directory_file
  } else {
    flat_file
  }
  guard @fsx.try_read_text(path) is Some(content) else {
    raise SkillMarketError("skill \{id} has no readable SKILL.md")
  }
  guard content.length() <= MaxPreviewBytes else {
    raise SkillMarketError("SKILL.md is too large to preview")
  }
  content
}

///|
/// Remove one installed skill. Only entries carrying our provenance sidecar
/// are removable — a hand-written skill is the user's file, not ours to
/// delete. `on_committed` runs after the live directory moves under `.trash`,
/// before any best-effort physical deletion.
pub async fn uninstall_skill(
  id : String,
  library_dir? : @pathx.Path = library_dir_from_env(),
  on_committed? : () -> Unit,
) -> Unit {
  library_lock.acquire()
  defer library_lock.release()
  let library : SkillLibrary = { root: library_dir, }
  library.recover()
  guard valid_slug(id) else {
    raise SkillMarketError("invalid skill id: \{id}")
  }
  let target = library_dir.join(id)
  guard @fsx.exists(target) else {
    raise SkillMarketError("no skill named \{id} in the library")
  }
  guard @fsx.exists(target.join(SidecarFile)) else {
    raise SkillMarketError(
      "\{id} was not installed from the registry; remove it by hand",
    )
  }
  library.move_to_trash(id, on_committed?)
}

///|
pub extend InstalledSkill with ToJson::{to_json}
