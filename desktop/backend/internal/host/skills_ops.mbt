// The skill-market ops: browsing the mooncakes.io skill registry and
// managing the engine's global skills library. Pure request/response — none
// of this touches the engine pump. A skill installed here is advertised to
// conversations whose engine sessions are created afterwards; running
// conversations keep the prompt they started with.

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
  let content = try {
    match payload.skill {
      Builtin(id) => {
        let skills = builtin_skills()
        guard skills.iter().find_first(skill => skill.id == id) is Some(skill) else {
          fail("unknown builtin skill: \{id}")
        }
        @fs.read_file(skill.instructions).text()
      }
      User(id) => @skillmarket.read_skill_content(id)
    }
  } catch {
    @skillmarket.SkillMarketError(message) => return SkillContentError(message)
    error => return SkillContentError("\{error}")
  }
  SkillContent(content)
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
    @skillmarket.SkillMarketError(message) => return SkillInstallError(message)
    error => return SkillInstallError("\{error}")
  }
  SkillInstalled({
    skill: User(installed.id),
    name: installed.name,
    description: installed.description,
    source: installed.source,
  })
}

///|
async fn installed_skills_op() -> InstalledSkillsReply {
  let builtin = builtin_skills() catch {
    error => return InstalledSkillsError("\{error}")
  }
  let skills = @skillmarket.installed_skills() catch {
    @skillmarket.SkillMarketError(message) =>
      return InstalledSkillsError(message)
    error => return InstalledSkillsError("\{error}")
  }
  InstalledSkills(
    [
      ..builtin.map(skill => {
        (
          {
            skill: Builtin(skill.id),
            name: skill.prompt_name(),
            description: skill.description,
            source: "OpenSeek builtin · v\{skill.version}",
          } : @protocol.InstalledSkill)
      }),
      ..skills.map(skill => {
        (
          {
            skill: User(skill.id),
            name: skill.name,
            description: skill.description,
            source: skill.source,
          } : @protocol.InstalledSkill)
      }),
    ],
  )
}

///|
async fn uninstall_skill_op(
  payload : UninstallSkillPayload,
  on_committed : () -> Unit,
) -> UninstallSkillReply {
  try {
    match payload.skill {
      Builtin(_) =>
        return SkillUninstallError(
          "Builtin skills are updated with OpenSeek and cannot be uninstalled",
        )
      User(id) => @skillmarket.uninstall_skill(id, on_committed~)
    }
  } catch {
    @skillmarket.SkillMarketError(message) =>
      return SkillUninstallError(message)
    error => return SkillUninstallError("\{error}")
  }
  SkillUninstalled
}

///|
/// Read the same installation resources as the packaged engine.
async fn builtin_skills() -> Array[@agent_skill.BuiltinSkill] {
  let root : @pathx.Path = @proton.resource_dir()
  @agent_skill.builtin_skills(
    resources_dir=root.join("seekmoon/share").to_string(),
  )
}
