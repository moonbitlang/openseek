///|
pub fn builtin_skills() -> Array[RegistrySkillIdentity] {
  [
    { module_name: "moonbitlang/typst", package_path: "cli", },
    { module_name: "moonbitlang/office", package_path: "", },
  ]
}

///|
pub fn is_builtin(identity : RegistrySkillIdentity) -> Bool {
  builtin_skills().contains(identity)
}

///|
pub struct BuiltinSkillError {
  registry : RegistrySkillIdentity
  message : String
}

///|
struct BuiltinSkills {
  entries : Array[RegistrySkillIdentity]
  mut errors : Array[BuiltinSkillError]
}

///|
pub fn BuiltinSkills::new(
  entries~ : Array[RegistrySkillIdentity] = builtin_skills(),
) -> BuiltinSkills {
  { entries: entries.copy(), errors: [], }
}

///|
pub fn BuiltinSkills::errors(self : BuiltinSkills) -> Array[BuiltinSkillError] {
  self.errors.copy()
}

///|
pub fn BuiltinSkills::clear_error(
  self : BuiltinSkills,
  module_name~ : String,
  package_path~ : String,
) -> Unit {
  self.errors = self.errors.filter(error => {
    error.registry.module_name != module_name ||
    error.registry.package_path != package_path
  })
}

///|
fn BuiltinSkills::record_error(
  self : BuiltinSkills,
  identity : RegistrySkillIdentity,
  error : Error,
  on_changed : () -> Unit,
) -> Unit {
  let message = match error {
    SkillMarketError(message) => message
    error => "\{error}"
  }
  self.clear_error(
    module_name=identity.module_name,
    package_path=identity.package_path,
  )
  self.errors.push({ registry: identity, message, })
  on_changed()
}

///|
fn installed_source(
  skills : Array[InstalledSkill],
  identity : RegistrySkillIdentity,
) -> String? {
  skills
  .iter()
  .find_first(skill => skill.registry == Some(identity))
  .map(skill => skill.source)
}

///|
/// Each host runs this once on its lifetime task group. The catalog guarantees
/// increasing published versions, so matching sources need no download.
pub async fn BuiltinSkills::sync(
  self : BuiltinSkills,
  registry~ : String = DefaultRegistry,
  library_dir? : @pathx.Path,
  on_changed : () -> Unit,
) -> Unit {
  guard !self.entries.is_empty() else { return }
  let library_dir = match library_dir {
    Some(dir) => dir
    None =>
      library_dir_from_env() catch {
        error => {
          for identity in self.entries {
            self.record_error(identity, error, on_changed)
          }
          return
        }
      }
  }
  let before = installed_skills(library_dir~) catch {
    error => {
      for identity in self.entries {
        self.record_error(identity, error, on_changed)
      }
      return
    }
  }
  let catalog = fetch_catalog(registry~) catch {
    error => {
      let current = installed_skills(library_dir~) catch { _ => before }
      for identity in self.entries {
        if installed_source(current, identity) ==
          installed_source(before, identity) {
          self.record_error(identity, error, on_changed)
        }
      }
      return
    }
  }
  for identity in self.entries {
    let expected = installed_source(before, identity)
    try {
      guard catalog
        .iter()
        .find_first(skill => {
          skill.module_name == identity.module_name &&
          skill.package_path == identity.package_path
        })
        is Some(skill) else {
        raise SkillMarketError(
          "built-in skill is missing from the registry catalog",
        )
      }
      let desired = source_label(
        skill.module_name,
        skill.version,
        skill.package_path,
      )
      if expected == Some(desired) {
        self.clear_error(
          module_name=identity.module_name,
          package_path=identity.package_path,
        )
        continue
      }
      ignore(
        install_skill_impl(
          module_name=identity.module_name,
          version=skill.version,
          package_path=identity.package_path,
          registry~,
          library_dir~,
          mode=IfUnchanged(expected),
          on_committed=() => {
            self.clear_error(
              module_name=identity.module_name,
              package_path=identity.package_path,
            )
            on_changed()
          },
        ),
      )
    } catch {
      error => {
        let current = installed_skills(library_dir~) catch { _ => before }
        if installed_source(current, identity) == expected {
          self.record_error(identity, error, on_changed)
        }
      }
    }
  }
}
