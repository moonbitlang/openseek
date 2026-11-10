// The skill ops: browsing the mooncakes.io skill registry and managing the
// engine's global skills library. Pure request/response — none of this touches
// the engine pump. A skill installed here is advertised to conversations whose
// engine sessions are created afterwards; running conversations keep the
// prompt they started with. Every failure returns inside the reply.

///|
pub async fn catalog() -> @protocol.SkillsCatalogReply {
  let skills = fetch_catalog() catch {
    error => return SkillsCatalogError("\{error}")
  }
  SkillsCatalog(
    [
      for skill in skills => {
        {
          name: skill.name,
          module_name: skill.module_name,
          package_path: skill.package_path,
          version: skill.version,
          description: skill.description,
          author: skill.author,
          repository: skill.repository,
        }
      }
    ],
  )
}

///|
/// The SKILL.md of a registry skill, before it is installed.
pub async fn content(
  payload : @protocol.InstallSkillPayload,
) -> @protocol.SkillContentReply {
  let content = fetch_skill_content(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
  ) catch {
    error => return SkillContentError("\{error}")
  }
  SkillContent(content)
}

///|
/// The SKILL.md of a skill already in the library.
pub async fn installed_content(
  payload : @protocol.UninstallSkillPayload,
) -> @protocol.SkillContentReply {
  let content = read_skill_content(payload.id) catch {
    error => return SkillContentError("\{error}")
  }
  SkillContent(content)
}

///|
/// Install a registry skill. A successful manual install also clears that
/// skill's built-in sync failure before `on_committed` notifies clients.
pub async fn BuiltinSkills::install(
  self : BuiltinSkills,
  payload : @protocol.InstallSkillPayload,
  on_committed : () -> Unit,
  registry? : String,
) -> @protocol.InstallSkillReply {
  let installed = install_skill(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
    registry?,
    on_committed=() => {
      self.clear_error(
        module_name=payload.module_name,
        package_path=payload.package_path.unwrap_or(""),
      )
      on_committed()
    },
  ) catch {
    error => return SkillInstallError("\{error}")
  }
  SkillInstalled(installed.to_protocol())
}

///|
fn InstalledSkill::to_protocol(
  self : InstalledSkill,
) -> @protocol.InstalledSkill {
  {
    id: self.id,
    name: self.name,
    description: self.description,
    source: self.source,
    enabled: self.enabled,
    builtin: self.registry is Some(identity) && is_builtin(identity),
    registry: self.registry.map(registry => {
      module_name: registry.module_name,
      package_path: registry.package_path,
    }),
  }
}

///|
/// The library's skills, with every built-in skill that failed to sync.
pub async fn BuiltinSkills::installed(
  self : BuiltinSkills,
) -> @protocol.InstalledSkillsReply {
  let skills = installed_skills() catch {
    error => return InstalledSkillsError("\{error}")
  }
  InstalledSkills(
    [
      for skill in skills => skill.to_protocol()
    ],
    builtin_errors=self
      .errors()
      .map(error => {
        registry: {
          module_name: error.registry.module_name,
          package_path: error.registry.package_path,
        },
        message: error.message,
      }),
  )
}

///|
pub async fn uninstall(
  payload : @protocol.UninstallSkillPayload,
  on_committed : () -> Unit,
) -> @protocol.UninstallSkillReply {
  uninstall_skill(payload.id, on_committed~) catch {
    error => return SkillUninstallError("\{error}")
  }
  SkillUninstalled
}

///|
pub async fn set_enabled(
  payload : @protocol.SetSkillEnabledPayload,
  on_committed : () -> Unit,
) -> @protocol.SetSkillEnabledReply {
  set_skill_enabled(payload.id, enabled=payload.enabled, on_committed~) catch {
    error => return SkillEnabledError("\{error}")
  }
  SkillEnabledSet
}
