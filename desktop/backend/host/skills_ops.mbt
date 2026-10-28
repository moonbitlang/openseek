// The skill-market ops: browsing the mooncakes.io skill registry and
// managing the engine's global skills library. Pure request/response — none
// of this touches the engine pump. A skill installed here is advertised to
// conversations whose engine sessions are created afterwards; running
// conversations keep the prompt they started with.

///|
pub async fn HostState::sync_builtin_skills(
  self : HostState,
  on_changed : () -> Unit,
  registry? : String,
  library_dir? : @pathx.Path,
) -> Unit {
  self.skills.sync(registry?, library_dir?, on_changed)
}

///|
async fn skills_catalog_op() -> SkillsCatalogReply {
  let skills = @skillmarket.fetch_catalog() catch {
    @skillmarket.SkillMarketError(message) => return SkillsCatalogError(message)
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
async fn skills_content_op(
  payload : InstallSkillPayload,
) -> @protocol.SkillContentReply {
  let content = @skillmarket.fetch_skill_content(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
  ) catch {
    @skillmarket.SkillMarketError(message) => return SkillContentError(message)
    error => return SkillContentError("\{error}")
  }
  SkillContent(content)
}

///|
async fn installed_skill_content_op(
  payload : UninstallSkillPayload,
) -> @protocol.SkillContentReply {
  let content = @skillmarket.read_skill_content(payload.id) catch {
    @skillmarket.SkillMarketError(message) => return SkillContentError(message)
    error => return SkillContentError("\{error}")
  }
  SkillContent(content)
}

///|
async fn install_skill_op(
  state : HostState,
  payload : InstallSkillPayload,
  on_committed : () -> Unit,
  registry? : String,
) -> InstallSkillReply {
  let installed = @skillmarket.install_skill(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
    registry?,
    on_committed=() => {
      state.skills.clear_error(
        module_name=payload.module_name,
        package_path=payload.package_path.unwrap_or(""),
      )
      on_committed()
    },
  ) catch {
    @skillmarket.SkillMarketError(message) => return SkillInstallError(message)
    error => return SkillInstallError("\{error}")
  }
  SkillInstalled(installed.to_protocol())
}

///|
fn @skillmarket.InstalledSkill::to_protocol(
  self : @skillmarket.InstalledSkill,
) -> @protocol.InstalledSkill {
  {
    id: self.id,
    name: self.name,
    description: self.description,
    source: self.source,
    enabled: self.enabled,
    builtin: self.registry is Some(identity) &&
    @skillmarket.is_builtin(identity),
    registry: self.registry.map(registry => {
      module_name: registry.module_name,
      package_path: registry.package_path,
    }),
  }
}

///|
async fn installed_skills_op(state : HostState) -> InstalledSkillsReply {
  let skills = @skillmarket.installed_skills() catch {
    @skillmarket.SkillMarketError(message) =>
      return InstalledSkillsError(message)
    error => return InstalledSkillsError("\{error}")
  }
  InstalledSkills(
    [
      for skill in skills => skill.to_protocol()
    ],
    builtin_errors=state.skills
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
async fn uninstall_skill_op(
  payload : UninstallSkillPayload,
  on_committed : () -> Unit,
) -> UninstallSkillReply {
  @skillmarket.uninstall_skill(payload.id, on_committed~) catch {
    @skillmarket.SkillMarketError(message) =>
      return SkillUninstallError(message)
    error => return SkillUninstallError("\{error}")
  }
  SkillUninstalled
}

///|
async fn set_skill_enabled_op(
  payload : @protocol.SetSkillEnabledPayload,
  on_committed : () -> Unit,
) -> @protocol.SetSkillEnabledReply {
  @skillmarket.set_skill_enabled(
    payload.id,
    enabled=payload.enabled,
    on_committed~,
  ) catch {
    @skillmarket.SkillMarketError(message) => return SkillEnabledError(message)
    error => return SkillEnabledError("\{error}")
  }
  SkillEnabledSet
}
