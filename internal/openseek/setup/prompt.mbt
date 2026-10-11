///|
/// Assemble the selected prompt, project instructions, skills, and workspace
/// environment in cache-friendly order.
pub async fn configured_system_prompt(
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root? : String = ".",
  session_scratch_dir? : String,
) -> String {
  let (base_path, addendum_path, global_skills_dir) = match matches {
    {
      values: {
        "system-prompt-file": [base_path, ..],
        "system-prompt-addendum-file": [addendum_path, ..],
        "global-skills-dir": [global_skills_dir, ..],
        ..
      },
      ..
    } => (base_path, addendum_path, global_skills_dir)
    _ => fail("missing parsed system-prompt defaults")
  }
  let prompt = StringBuilder()
  // The environment section goes LAST: DeepSeek's context cache matches on
  // request prefixes, and the cwd is the only per-project variable in the
  // prompt. Base and addendum are byte-identical across projects (and across
  // an eval harness's N concurrent trial workspaces testing one addendum),
  // so ordering them first keeps the whole shared text cache-hittable; the
  // end position also gives the grounding instruction recency weight.
  let base = if base_path == "" {
    @prompt.system_prompt_for_model(model)
  } else {
    @fs.read_file(@workspace_path.resolve(workspace_root, base_path)).text()
  }
  prompt <+ "\{base}"
  if addendum_path != "" {
    let addendum = @fs.read_file(
      @workspace_path.resolve(workspace_root, addendum_path),
    ).text()
    prompt <+ "\n\n\{addendum}"
  }
  // The runtime environment block appended to every system prompt — including
  // a `--system-prompt-file` override, since grounding describes the process,
  // not the prompt content. Without it the model has no idea where it is and
  // guesses: in a five-run benchmark batch one agent passed
  // `cwd="/workspace"` on its very first call, then explored the parent
  // directory, found a concurrent sibling run's files, and adopted that
  // workspace wholesale. A durable session stores the prompt at creation, so
  // the recorded directory is where the session was started — resume it from
  // the same project root.
  //
  // The resource directory is resolved from the running executable.
  // Documentation layout and usage instructions live in the static default
  // prompt, keeping the installation-dependent path in this tail.
  let cwd = working_directory(workspace_root)
  prompt <+ "\n\n\{environment_block(cwd)}"
  if session_scratch_dir is Some(dir) {
    prompt <+ "\n\n\{scratch_directory_line(dir)}"
  }
  if @resources.directory() is Some(dir) {
    prompt <+ "\n\nBundled resources: \{dir}"
  }
  let agents_section = agents_prompt_section(cwd)
  if agents_section is Some(section) {
    prompt <+ "\n\n\{section}"
  }
  // Workspace skills join the per-project tail after the environment
  // section: like the cwd they vary per project (and change when skills are
  // edited), so they must sit after all globally shared text to keep it
  // prefix-cache hittable.
  let skills_section = skills_prompt_section_for_cwd(
    global_dir=global_skills_dir,
    workspace_root~,
  )
  if skills_section is Some(section) {
    prompt <+ "\n\n\{section}"
  }
  prompt.to_string()
}

///|
/// The physical directory a session started with `workspace_root` works in.
async fn working_directory(workspace_root : String) -> String {
  let target = if workspace_root == "" { "." } else { workspace_root }
  @fs.realpath(target) catch {
    _ => target
  }
}

///|
/// Where the process works and what is there. A system prompt records it at
/// a session's creation, and a fork's opening notice states it again for the
/// fork.
async fn environment_block(cwd : String) -> String {
  let outline = dir_outline(cwd).unwrap_or(
    "(empty directory): use `moon new` to create a new project here",
  )
  let block =
    $|## Environment
    $|
    $|Working directory: \{cwd}
    $|Relative paths resolve against it; treat it as the workspace root and stay inside it.
    $|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
    $|Project layout (directories; hidden, build, and vendored dirs omitted):
    $|\{outline}
  block
}

///|
fn scratch_directory_line(dir : String) -> String {
  "Session scratch directory: \{dir.to_json().stringify()} (read/write; helper scripts and cross-call files; allowed outside the workspace)."
}

///|
/// The runtime notice that opens a fork of `source`.
///
/// A fork's system prompt is its source's, copied verbatim so the copied
/// history stays a cache-hittable prefix — which also means it names the
/// source's scratch directory and the directory the source started in. This
/// notice is the fork's own event after that history: it says the
/// conversation is a fork, and states the environment the fork works in.
pub async fn fork_notice(
  source : @agent_session.SessionId,
  workspace_root? : String = ".",
  session_scratch_dir~ : String,
) -> String {
  let environment = environment_block(working_directory(workspace_root))
  let notice =
    $|[session forked]
    $|This conversation was forked from session \{source.value().to_json().stringify()} and continues here on its own. The original keeps its scratch directory; this session's environment is stated below and replaces the one in the system prompt.
    $|
    $|\{environment}
    $|
    $|\{scratch_directory_line(session_scratch_dir)}
  notice
}

///|
/// Read `AGENTS.md` from the workspace and each ancestor directory. The
/// resulting section is ordered from the oldest ancestor to the workspace so
/// more specific instructions appear later, matching Pi's context layering.
async fn agents_prompt_section(workspace_root : String) -> String? {
  let files : Array[(String, String)] = []
  let mut current = Some(workspace_root)
  while current is Some(dir) {
    let path = @workspace_path.join_child(dir, "AGENTS.md")
    if @fs.exists(path) && @fs.kind(path) is Regular {
      // AGENTS files may start with a UTF-8 BOM; keep only the document text.
      files.push(
        (path, @utf8.decode(@fs.read_file(path).binary(), ignore_bom=true)),
      )
    }
    current = @workspace_path.parent_dir(dir)
  }
  guard files.length() > 0 else { return None }
  let entries = files
    .rev()
    .map(file => {
      let (path, content) = file
      "<project_instructions path=\"\{path}\">\n\{content}\n</project_instructions>"
    })
  let joined = entries.join("\n\n")
  Some("Project-specific instructions and guidelines:\n\n\{joined}")
}

///|
fn global_skills_dir_for_home(value : String?) -> String? {
  let home = value.unwrap_or("").trim()
  if home.is_empty() {
    None
  } else {
    Some("\{home}/.openseek/skills")
  }
}

///|
/// The user-level skills default: `USERPROFILE` on Windows, `HOME` everywhere
/// else — a Windows `HOME` may be a Git Bash/MSYS translation of it.
fn default_global_skills_dir() -> String? {
  if @async.platform is Windows &&
    global_skills_dir_for_home(@env.get_env_var("USERPROFILE")) is Some(dir) {
    return Some(dir)
  }
  global_skills_dir_for_home(@env.get_env_var("HOME"))
}

///|
/// The skills advertised to the model: the user-level library (`global_dir`,
/// defaulting to `$HOME/.openseek/skills` or `%USERPROFILE%/.openseek/skills`
/// when empty) merged with the
/// workspace library under `.openseek/skills`, listing `<name>.md` files and
/// `<name>/SKILL.md` layouts. Workspace skills shadow same-named global ones
/// so a project can specialize a shared playbook. Empty or absent
/// directories advertise nothing — and eval harnesses point `global_dir` at
/// a path inside the trial workspace so the developer's own library never
/// leaks into trials.
async fn skills_prompt_section_for_cwd(
  global_dir~ : String,
  workspace_root~ : String,
) -> String? {
  let resolved_global_dir = if global_dir != "" {
    Some(@workspace_path.resolve(workspace_root, global_dir))
  } else {
    default_global_skills_dir()
  }
  let global_skills = if resolved_global_dir is Some(resolved_global_dir) {
    @agent_skill.discover_skills(resolved_global_dir)
  } else {
    []
  }
  @agent_skill.skills_prompt_section(
    @agent_skill.merge_skills(
      global_skills,
      overrides=@agent_skill.discover_skills(
        @workspace_path.resolve(workspace_root, ".openseek/skills"),
      ),
    ),
  )
}
