// The skill-market ops: browsing the mooncakes.io skill registry and
// managing the engine's global skills library. Pure request/response — none
// of this touches the engine pump. A skill installed here is advertised to
// conversations whose engine sessions are created afterwards; running
// conversations keep the prompt they started with.

///|
async fn skills_catalog_op() -> SkillsCatalogReply {
  let skills = @skillmarket.fetch_catalog() catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  {
    skills: [
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
  }
}

///|
async fn skills_content_op(payload : InstallSkillPayload) -> ReadFileReply {
  let content = @skillmarket.fetch_skill_content(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
  ) catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  Content(content~, absolute="", sig="")
}

///|
async fn installed_skill_content_op(
  payload : UninstallSkillPayload,
) -> ReadFileReply {
  let content = @skillmarket.read_skill_content(payload.id) catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  Content(content~, absolute="", sig="")
}

///|
async fn install_skill_op(
  payload : InstallSkillPayload,
  on_committed : () -> Unit,
) -> InstallSkillReply {
  let installed = @skillmarket.install_skill(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
    on_committed~,
  ) catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  {
    installed: {
      id: installed.id,
      name: installed.name,
      description: installed.description,
      source: installed.source,
    },
  }
}

///|
async fn installed_skills_op() -> InstalledSkillsReply {
  let skills = @skillmarket.installed_skills() catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  {
    skills: [
      for skill in skills => {
        {
          id: skill.id,
          name: skill.name,
          description: skill.description,
          source: skill.source,
        }
      }
    ],
  }
}

///|
async fn uninstall_skill_op(
  payload : UninstallSkillPayload,
  on_committed : () -> Unit,
) -> UninstallSkillReply {
  @skillmarket.uninstall_skill(payload.id, on_committed~) catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  { removed: true, }
}
