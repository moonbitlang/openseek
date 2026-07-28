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
  { skills, }
}

///|
async fn install_skill_op(payload : InstallSkillPayload) -> InstallSkillReply {
  let installed = @skillmarket.install_skill(
    module_name=payload.module_name,
    version=payload.version,
    package_path=payload.package_path.unwrap_or(""),
  ) catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  { installed, }
}

///|
async fn installed_skills_op() -> InstalledSkillsReply {
  let skills = @skillmarket.installed_skills() catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  { skills, }
}

///|
async fn uninstall_skill_op(
  payload : UninstallSkillPayload,
) -> UninstallSkillReply {
  @skillmarket.uninstall_skill(payload.id) catch {
    @skillmarket.SkillMarketError(message) => raise HostError(message)
    error => raise error
  }
  { removed: true }
}
