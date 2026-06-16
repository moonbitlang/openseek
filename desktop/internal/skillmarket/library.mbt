// The local skills library: installing a registry skill into the engine's
// global skills directory, listing what is there, and removing what this
// app installed. The directory layout and frontmatter rules deliberately
// mirror the engine's `agent_skill` discovery (`<name>.md` flat files and
// `<name>/SKILL.md` directories), so the panel lists exactly what the
// engine advertises to the model.

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
fn resolved_library_dir(overridden : String?) -> String raise SkillMarketError {
  if overridden is Some(dir) {
    return dir
  }
  if @env.get("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(dir) &&
    !dir.trim().is_empty() {
    return dir
  }
  if @home.dir() is Some(home) && !home.trim().is_empty() {
    return home + "/.openseek/skills"
  }
  raise SkillMarketError(
    "cannot locate the skills library; set OPENSEEK_GLOBAL_SKILLS_DIR",
  )
}

///|
/// Whether `name` is one of the registry's discovery slugs — lowercase
/// `[a-z0-9-]`, at most 64 chars. Validated locally before it becomes a
/// directory name, so registry data can never path-escape the library.
fn valid_slug(name : String) -> Bool {
  if name.is_empty() || name.length() > 64 {
    return false
  }
  for ch in name {
    if !(ch is ('a'..='z' | '0'..='9' | '-')) {
      return false
    }
  }
  true
}

///|
fn digest_matches(expected : String, content : Bytes) -> Bool {
  let computed = "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(content))
  expected.to_lower() == computed
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
async fn read_text(path : String) -> String? {
  Some(@fs.read_file(path).text()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
/// Download one registry skill and install it as
/// `<library>/<slug>/SKILL.md`. The discovery index is authoritative: it
/// names the slug, the download URL, and the digest the content must hash
/// to. A same-named entry the user wrote by hand (no sidecar) is never
/// overwritten; one we installed is — that is a reinstall or an upgrade.
pub async fn install_skill(
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  registry? : String = DefaultRegistry,
  library_dir? : String,
) -> InstalledSkill {
  let library = resolved_library_dir(library_dir)
  let entry = entry_path(module_name, version, package_path)
  let found = fetch_discovery_entry(registry, entry)
  // The index body is registry-controlled data; never let it send the
  // download anywhere else.
  guard found.url.has_prefix(registry + "/") else {
    raise SkillMarketError(
      "refusing to download \{found.url}: outside the registry",
    )
  }
  guard valid_slug(found.name) else {
    raise SkillMarketError(
      "registry returned an unusable skill name: \{found.name}",
    )
  }
  let target = library + "/" + found.name
  let sidecar = target + "/" + SidecarFile
  let flat_target = target + ".md"
  if @fs.exists(flat_target) || (@fs.exists(target) && !@fs.exists(sidecar)) {
    raise SkillMarketError(
      "a skill named \{found.name} already exists in your library; not overwriting it",
    )
  }
  let (code, data) = fetch_response(found.url)
  guard code == 200 else {
    raise SkillMarketError("SKILL.md download returned HTTP \{code}")
  }
  let content = data.binary()
  guard digest_matches(found.digest, content) else {
    raise SkillMarketError(
      "SKILL.md digest mismatch for \{entry}; not installing",
    )
  }
  ensure_dir(target)
  @fs.write_file(target + "/SKILL.md", content, create_mode=CreateOrTruncate)
  let provenance : Json = {
    "module": module_name,
    "version": version,
    "package": package_path,
    "digest": found.digest,
  }
  @fs.write_file(sidecar, provenance.stringify(), create_mode=CreateOrTruncate)
  // Display fields only — the digest already vouched for the content.
  let text = data.text() catch { _ => "" }
  let (name, description) = parse_frontmatter(text, found.name)
  {
    id: found.name,
    name,
    description,
    source: source_label(module_name, version, package_path),
  }
}

///|
/// Create `dir` if missing. `@fs.mkdir` raises EEXIST even with
/// `recursive=true`, so probe first; losing a creation race leaves the
/// directory present, which is just as good.
async fn ensure_dir(dir : String) -> Unit {
  if @fs.exists(dir) {
    return
  }
  @fs.mkdir(dir, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => if @fs.exists(dir) { () } else { raise error }
  }
}

///|
/// The library's contents, mirroring the engine's discovery rules: every
/// `<name>.md`, plus every `<name>/SKILL.md`. A missing or unreadable
/// library is an empty one. Entries we installed carry their registry
/// source; everything else is the user's own.
pub async fn installed_skills(library_dir? : String) -> Array[InstalledSkill] {
  let library = resolved_library_dir(library_dir)
  let entries = @fs.readdir(library, sort=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  let skills : Array[InstalledSkill] = []
  for entry in entries {
    let path = library + "/" + entry
    if entry.has_suffix(".md") {
      guard read_text(path) is Some(text) else { continue }
      let id = entry[0:entry.length() - 3].to_owned()
      let (name, description) = parse_frontmatter(text, id)
      skills.push({ id, name, description, source: "" })
    } else {
      guard read_text(path + "/SKILL.md") is Some(text) else { continue }
      let (name, description) = parse_frontmatter(text, entry)
      let source = if read_text(path + "/" + SidecarFile) is Some(sidecar) {
        decode_sidecar(sidecar)
      } else {
        ""
      }
      skills.push({ id: entry, name, description, source })
    }
  }
  skills
}

///|
/// Remove one installed skill. Only entries carrying our provenance sidecar
/// are removable — a hand-written skill is the user's file, not ours to
/// delete.
pub async fn uninstall_skill(id : String, library_dir? : String) -> Unit {
  guard valid_slug(id) else {
    raise SkillMarketError("invalid skill id: \{id}")
  }
  let library = resolved_library_dir(library_dir)
  let target = library + "/" + id
  guard @fs.exists(target) else {
    raise SkillMarketError("no skill named \{id} in the library")
  }
  guard @fs.exists(target + "/" + SidecarFile) else {
    raise SkillMarketError(
      "\{id} was not installed from the registry; remove it by hand",
    )
  }
  @fs.rmdir(target, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise SkillMarketError("failed to remove \{id}: \{error}")
  }
}
