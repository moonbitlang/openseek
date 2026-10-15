///|
priv struct PreparedSkill {
  installed : InstalledSkill
  files : Map[String, Bytes]
  provenance : String
}

///|
/// Installation and update share archive validation and complete candidates.
async fn prepare_skill(
  id~ : String,
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  entry~ : String,
  source~ : ArchiveSource,
) -> PreparedSkill {
  let skill = skill_files(fetch_archive(entry, source), entry)
  let text = @utf8.decode(skill.skill_md) catch {
    _ =>
      raise SkillMarketError(
        "the archive for \{entry} holds an unreadable SKILL.md",
      )
  }
  let (name, description) = parse_frontmatter(text, id)
  let provenance : Json = {
    "module": module_name,
    "version": version,
    "package": package_path,
    "digest": source.digest,
  }
  {
    installed: {
      id,
      name,
      description,
      source: source_label(module_name, version, package_path),
      registry: Some({ module_name, package_path, version, }),
    },
    files: skill.files,
    provenance: provenance.stringify(),
  }
}

///|
pub enum SkillUpdateResult {
  Updated(InstalledSkill)
  AlreadyCurrent(InstalledSkill)
  InstallationChanged
}

///|
/// The caller holds the library lock. Missing registry installations are an
/// expected state change; filesystem read errors keep their error channel.
async fn SkillLibrary::registered_skill(
  self : SkillLibrary,
  id : String,
) -> (InstalledSkill, String)? {
  let target = self.target(id)
  guard @fsx.read_text_if_exists(target.join(SidecarFile)) is Some(provenance) else {
    return None
  }
  guard decode_sidecar(provenance) is Some(source) else { return None }
  guard @fsx.read_text_if_exists(target.join(SkillFile)) is Some(text) else {
    return None
  }
  let (name, description) = parse_frontmatter(text, id)
  Some(
    (
      {
        id,
        name,
        description,
        source: source.label,
        registry: Some(source.registry),
      },
      provenance,
    ),
  )
}

///|
async fn SkillLibrary::update_snapshot(
  self : SkillLibrary,
  id : String,
) -> (InstalledSkill, String, Int32)? {
  library_lock.acquire()
  defer library_lock.release()
  self.recover()
  self.registered_skill(id).map(pair => (pair.0, pair.1, self.revision(id)))
}

///|
/// Update an existing registry installation to the exact requested version.
/// Downloads happen outside the lock. Commit only while the original entry
/// still exists unchanged, so another client's uninstall/reinstall or update
/// cannot be silently undone by a slower request.
pub async fn update_skill(
  id : String,
  target_version~ : String,
  registry~ : String = DefaultRegistry,
  library_dir~ : @pathx.Path = library_dir_from_env(),
  on_committed? : () -> Unit,
) -> SkillUpdateResult {
  guard valid_slug(id) else {
    raise SkillMarketError("invalid skill id: \{id}")
  }
  let library : SkillLibrary = { root: library_dir, }
  guard library.update_snapshot(id) is Some((installed, provenance, revision)) else {
    return InstallationChanged
  }
  guard installed.registry is Some(coordinates) else {
    return InstallationChanged
  }
  if target_version == coordinates.version {
    return AlreadyCurrent(installed)
  }
  let entry = entry_path(
    coordinates.module_name,
    target_version,
    coordinates.package_path,
  )
  let source = fetch_archive_source(registry, entry)
  let prepared = prepare_skill(
    id~,
    module_name=coordinates.module_name,
    version=target_version,
    package_path=coordinates.package_path,
    entry~,
    source~,
  )
  library_lock.acquire()
  defer library_lock.release()
  library.recover()
  guard library.revision(id) == revision else { return InstallationChanged }
  guard library.registered_skill(id) is Some((_, current_provenance)) &&
    current_provenance == provenance else {
    return InstallationChanged
  }
  library.stage(id, prepared.files, prepared.provenance)
  library.activate(id, on_committed?)
  Updated(prepared.installed)
}
