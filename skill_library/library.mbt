// The local skills library: installing a registry skill archive into the
// engine's global skills directory, listing what is there, and removing what
// OpenSeek installed. The directory layout deliberately mirrors the engine's
// `agent_skill` discovery (`<name>.md` flat files and `<name>/SKILL.md`
// directories, here with the archive's supporting files beside the SKILL.md),
// and names come from the engine's own frontmatter parser, so hosts show the
// names the model will see. Entries parked under `.disabled` are also listed,
// which the engine's one-level discovery does not advertise.

///|
/// The provenance marker written next to an installed SKILL.md. The engine's
/// discovery only reads `*.md`, so the sidecar never leaks into prompts; its
/// presence is what makes an entry ours to overwrite or uninstall.
const SidecarFile = ".mooncakes.json"

///|
/// Registry coordinates identifying a skill independently of its version.
#derive(Eq, Debug)
pub(all) struct RegistrySkillIdentity {
  /// Owner/name skill identity (e.g. `moonbitlang/typst`).
  module_name : String
  /// Legacy subpackage path, empty for standalone skills.
  package_path : String
}

///|
/// One entry of the local skills library.
pub struct InstalledSkill {
  /// The library entry (directory or file stem) — the key uninstall/enable take.
  id : String
  /// Display name from SKILL.md frontmatter, falling back to `id`.
  name : String
  /// One-line description from SKILL.md frontmatter.
  description : String
  /// `module@version[/package]` recorded at install time; `None` for a skill
  /// the user wrote by hand (which this package never overwrites or
  /// uninstalls).
  source : String?
  /// Registry identity when installed from mooncakes.io; `None` for hand-written skills.
  registry : RegistrySkillIdentity?
  /// Whether this skill sits live in the library (`true`) or under `.disabled` (`false`).
  enabled : Bool
}

///|
priv struct InstalledSource {
  label : String
  registry : RegistrySkillIdentity
}

///|
fn env_var(name : String) -> String? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  let value = value.trim().to_owned()
  if value.is_empty() {
    None
  } else {
    Some(value)
  }
}

///|
/// Where the global library lives: `OPENSEEK_GLOBAL_SKILLS_DIR`, else the
/// user's home directory (`USERPROFILE` on Windows, `HOME` elsewhere) plus
/// `/.openseek/skills`; `None` when neither is set. Hosts hand this same
/// directory to every engine they spawn, so installs land where the engine
/// reads.
pub fn global_library_dir() -> String? {
  if env_var("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(dir) {
    return Some(dir)
  }
  let home = if @async.platform is Windows &&
    env_var("USERPROFILE") is Some(dir) {
    Some(dir)
  } else {
    env_var("HOME")
  }
  home.map(dir => @path.Path(dir).join(Path(".openseek/skills")).to_string())
}

///|
fn library_dir_from_env() -> String raise SkillsError {
  guard global_library_dir() is Some(dir) else {
    raise SkillsError(
      "cannot locate the skills library; set OPENSEEK_GLOBAL_SKILLS_DIR",
    )
  }
  dir
}

///|
fn resolve_library_dir(library_dir : String?) -> String raise SkillsError {
  match library_dir {
    Some(dir) => dir
    None => library_dir_from_env()
  }
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
  name.all(ch => ch is ('a'..<='z' | '0'..<='9' | '-'))
}

///|
/// Hand-written entries need not use registry slugs, but an id still names
/// exactly one discoverable library entry and never an internal control dir.
fn valid_skill_id(id : String) -> Bool {
  !id.is_empty() &&
  !(id is ("." | "..")) &&
  !(id
  is (StagingDirectory
  | BackupDirectory
  | TrashDirectory
  | DisabledDirectory
  | LockDirectory)) &&
  !id.contains("/") &&
  !id.contains("\\")
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
    let lowered = if ch is ('A'..<='Z') { ch.to_ascii_lowercase() } else { ch }
    if lowered is ('a'..<='z' | '0'..<='9') {
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
  builder.to_string()[:64].to_owned()
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
fn decode_sidecar(text : String) -> InstalledSource? {
  let json = @json.parse(text) catch { _ => return None }
  guard json
    is { "module": String(module_name), "version": String(version), .. } else {
    return None
  }
  let package_path = if json is { "package": String(package_path), .. } {
    package_path
  } else {
    ""
  }
  let identity : RegistrySkillIdentity = { module_name, package_path, }
  let registry = match json {
    { "kind": String("standalone"), .. } => identity
    { "kind": _, .. } => return None
    _ => standalone_identity(identity)
  }
  Some({ label: source_label(module_name, version, package_path), registry, })
}

///|
async fn try_read_text(path : String) -> String? {
  Some(@fs.read_text(path)) catch {
    _ => None
  }
}

///|
async fn read_installed_source(target : String) -> InstalledSource? {
  let sidecar = @path.Path(target).join(Path(SidecarFile)).to_string()
  guard try_read_text(sidecar) is Some(text) else { return None }
  decode_sidecar(text)
}

///|
priv enum InstallMode {
  Replace
  IfUnchanged(String?)
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
async fn install_skill_impl(
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  registry~ : String,
  library_dir~ : String,
  mode~ : InstallMode = Replace,
  on_committed~ : () -> Unit,
) -> InstalledSkill? {
  let entry = skill_reference(module_name, version, package_path)
  let identity : RegistrySkillIdentity = { module_name, package_path, }
  let slug = slugify(module_name)
  guard valid_slug(slug) else {
    raise SkillsError("registry entry \{entry} has no installable name")
  }
  let (archive, digest) = fetch_archive(registry, entry)
  let skill = skill_files(archive, entry)
  let text = @utf8.decode(skill.skill_md) catch {
    _ =>
      raise SkillsError("the archive for \{entry} holds an unreadable SKILL.md")
  }
  let (name, description) = @agent_skill.parse_frontmatter(text, slug)
  let provenance : Json = {
    "kind": "standalone",
    "module": module_name,
    "version": version,
    "package": package_path,
    "digest": digest,
  }
  with_library_lock(library_dir, () => {
    let root : SkillLibrary = { root: Path(library_dir), }
    root.recover_all()
    // Reuse an older built-in's owned directory, including its disabled location.
    // Its sidecar is rewritten with standalone coordinates in the same commit.
    let slug = if legacy_builtin_slug(identity) is Some(legacy) {
      let previous = root.locate(legacy)
      if read_installed_source(previous.library.target(legacy)) is Some(source) &&
        source.registry == identity {
        legacy
      } else {
        slug
      }
    } else {
      slug
    }
    let location = root.locate(slug)
    let library = location.library
    let target = library.target(slug)
    let flat_target = library.flat(slug)
    let sidecar = @path.Path(target).join(Path(SidecarFile)).to_string()
    if mode is IfUnchanged(expected) {
      let current = read_installed_source(target).map(source => source.label)
      guard current == expected else { return None }
    }
    // Check ownership after acquiring the library lock:
    // another request may have installed this slug while the network fetch ran.
    guard !@fs.exists(flat_target) &&
      (!@fs.exists(target) || @fs.exists(sidecar)) else {
      raise SkillsError(
        "a skill named \{slug} already exists in your library; not overwriting it",
      )
    }
    library.stage(slug, skill.files, provenance.stringify())
    library.activate(slug, on_committed~)
    Some({
      id: slug,
      name,
      description,
      source: Some(source_label(module_name, version, package_path)),
      registry: Some({ module_name, package_path, }),
      enabled: location.enabled,
    })
  })
}

///|
/// The library's contents, mirroring the engine's discovery rules: every
/// `<name>.md`, plus every `<name>/SKILL.md`. A missing or unreadable
/// library is an empty one. Enabled and disabled entries are both included.
/// Entries we installed carry their registry source; everything else is the
/// user's own.
pub async fn installed_skills(library_dir? : String) -> Array[InstalledSkill] {
  let library_dir = resolve_library_dir(library_dir)
  with_existing_library_lock(library_dir, () => {
    let library : SkillLibrary = { root: Path(library_dir), }
    library.recover_all()
    let skills = library.list_entries(enabled=true)
    skills.append(library.disabled().list_entries(enabled=false))
    // Keep one stable order across enabled and disabled entries.
    skills.sort_by((a, b) => a.name.compare(b.name))
    skills
  }).unwrap_or([])
}

///|
async fn SkillLibrary::list_entries(
  self : SkillLibrary,
  enabled~ : Bool,
) -> Array[InstalledSkill] {
  let entries = @fs.readdir(self.root.to_string()) catch { _ => return [] }
  let skills : Array[InstalledSkill] = []
  for entry in entries {
    let path = self.root.join(Path(entry))
    if entry is [.. id, .. ".md"] {
      guard try_read_text(path.to_string()) is Some(text) else { continue }
      let id = id.to_owned()
      let (name, description) = @agent_skill.parse_frontmatter(text, id)
      skills.push({
        id,
        name,
        description,
        source: None,
        registry: None,
        enabled,
      })
    } else {
      guard try_read_text(path.join(Path(SkillFile)).to_string()) is Some(text) else {
        continue
      }
      let (name, description) = @agent_skill.parse_frontmatter(text, entry)
      let installed_source = {
        guard try_read_text(path.join(Path(SidecarFile)).to_string())
          is Some(sidecar) else {
          None
        }
        decode_sidecar(sidecar)
      }
      skills.push({
        id: entry,
        name,
        description,
        source: installed_source.map(source => source.label),
        registry: installed_source.map(source => source.registry),
        enabled,
      })
    }
  }
  skills
}

///|
/// Read an installed skill without exposing the library root to callers.
pub async fn read_skill_content(id : String, library_dir? : String) -> String {
  guard valid_skill_id(id) else { raise SkillsError("invalid skill id: \{id}") }
  let library_dir = resolve_library_dir(library_dir)
  guard with_existing_library_lock(library_dir, () => {
      let library : SkillLibrary = { root: Path(library_dir), }
      library.recover_all()
      let location = library.locate(id)
      let directory_file = location.library.root
        .join(Path(id))
        .join(Path(SkillFile))
        .to_string()
      let flat_file = location.library.flat(id)
      let path = {
        guard @fs.exists(directory_file) else { flat_file }
        directory_file
      }
      guard try_read_text(path) is Some(content) else {
        raise SkillsError("skill \{id} has no readable SKILL.md")
      }
      guard @utf8.encode(content).length() <= MaxPreviewBytes else {
        raise SkillsError("SKILL.md is too large to preview")
      }
      content
    })
    is Some(content) else {
    raise SkillsError("skill \{id} has no readable SKILL.md")
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
  library_dir? : String,
  on_committed? : () -> Unit,
) -> Unit {
  let library_dir = resolve_library_dir(library_dir)
  guard valid_slug(id) else { raise SkillsError("invalid skill id: \{id}") }
  guard with_existing_library_lock(library_dir, () => {
      let library : SkillLibrary = { root: Path(library_dir), }
      library.recover_all()
      let location = library.locate(id)
      let target = location.library.target(id)
      guard @fs.exists(target) else {
        raise SkillsError("no skill named \{id} in the library")
      }
      guard @fs.exists(@path.Path(target).join(Path(SidecarFile)).to_string()) else {
        raise SkillsError(
          "\{id} was not installed from the registry; remove it by hand",
        )
      }
      if read_installed_source(target) is Some(source) &&
        is_builtin(source.registry) {
        raise SkillsError(
          "built-in skills cannot be uninstalled; disable the skill instead",
        )
      }
      location.library.move_to_trash(id, on_committed?)
    })
    is Some(_) else {
    raise SkillsError("no skill named \{id} in the library")
  }
}

///|
/// Enable or disable an installed entry with a same-filesystem rename. The
/// complete directory (including supporting files and provenance), or a flat
/// hand-written .md file, moves together. Repeated requests are idempotent.
pub async fn set_skill_enabled(
  id : String,
  enabled~ : Bool,
  library_dir? : String,
  on_committed? : () -> Unit,
) -> Unit {
  guard valid_skill_id(id) else { raise SkillsError("invalid skill id: \{id}") }
  let library_dir = resolve_library_dir(library_dir)
  guard with_existing_library_lock(library_dir, () => {
      let library : SkillLibrary = { root: Path(library_dir), }
      library.recover_all()
      let location = library.locate(id)
      let entry = if location.library.has_directory_skill(id) {
        id
      } else if location.library.has_flat_skill(id) {
        "\{id}.md"
      } else {
        raise SkillsError("no skill named \{id} in the library")
      }
      guard location.enabled != enabled else { return }
      let destination = {
        guard enabled else { library.disabled() }
        library
      }
      @fs.mkdir(
        destination.root.to_string(),
        recursive=true,
        allow_existing=true,
      )
      @async.protect_from_cancel(() => {
        @fs.rename(
          location.library.child(entry),
          destination.child(entry),
          replace=false,
        ) catch {
          error => raise SkillsError("cannot move skill \{id}: \{error}")
        }
        if on_committed is Some(callback) {
          callback()
        }
      })
    })
    is Some(_) else {
    raise SkillsError("no skill named \{id} in the library")
  }
}
