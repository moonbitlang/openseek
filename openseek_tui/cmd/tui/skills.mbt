///|
/// `/skills` — inspect installed skills or toggle a global skill's enabled
/// state.
fn handle_skills_command(arguments : String, cmds : Array[Cmd]) -> Unit {
  let trimmed = arguments.trim().to_owned()
  if trimmed.is_empty() {
    cmds.push(ListSkills)
    return
  }
  for entry in [("enable", true), ("disable", false)] {
    let (verb, enabled) = entry
    if trimmed.strip_prefix(verb) is Some(rest) &&
      (rest.is_empty() || rest.has_prefix(" ")) {
      let raw = rest.trim()
      let id = match raw {
        ['"', .. inner, '"'] => inner.to_owned()
        _ => raw.to_owned()
      }
      if id.is_empty() {
        cmds.push(AppendItem(Error("usage: /skills \{verb} <id>")))
      } else {
        cmds.push(SetSkillEnabled(id~, enabled~))
      }
      return
    }
  }
  cmds.push(
    AppendItem(
      Error("usage: /skills | /skills enable <id> | /skills disable <id>"),
    ),
  )
}

///|
/// Render a concise summary of global and workspace skills plus any built-in
/// sync status.
async fn format_skills_summary(
  cwd~ : String,
  library_dir~ : String?,
  syncing~ : Bool,
  builtin_errors~ : Array[@skill_library.BuiltinSkillError],
) -> String {
  let workspace_dir = if cwd.has_suffix("/") || cwd.has_suffix("\\") {
    "\{cwd}.openseek/skills"
  } else {
    "\{cwd}/.openseek/skills"
  }
  let workspace = @agent_skill.discover_skills(workspace_dir)
  let global = match library_dir {
    Some(dir) => @skill_library.installed_skills(library_dir=dir)
    None => []
  }
  let lines : Array[String] = []
  if !workspace.is_empty() {
    lines.push("Workspace skills (\{workspace_dir}):")
    for skill in workspace {
      let desc = if skill.description().is_empty() {
        ""
      } else {
        " — \{skill.description()}"
      }
      lines.push("  - \{skill.name()}\{desc}")
    }
  }
  if !global.is_empty() {
    let header = match library_dir {
      Some(dir) => "Global skills (\{dir}):"
      None => "Global skills:"
    }
    lines.push(header)
    for skill in global {
      let tags : Array[String] = []
      if skill.registry is Some(identity) && @skill_library.is_builtin(identity) {
        tags.push("built-in")
      }
      if !skill.enabled {
        tags.push("disabled")
      }
      if skill.id != skill.name {
        tags.push("id: \{skill.id}")
      }
      let tag_text = if tags.is_empty() {
        ""
      } else {
        let joined = tags.join(", ")
        " [\{joined}]"
      }
      let desc = if skill.description.is_empty() {
        ""
      } else {
        " — \{skill.description}"
      }
      lines.push("  - \{skill.name}\{tag_text}\{desc}")
    }
  }
  if lines.is_empty() {
    lines.push("No skills installed.")
  }
  if syncing {
    lines.push("Built-in skills sync in progress…")
  }
  if !builtin_errors.is_empty() {
    lines.push("Built-in skill sync errors:")
    for err in builtin_errors {
      lines.push("  - \{err.registry.module_name}: \{err.message}")
    }
  }
  lines.join("\n")
}
