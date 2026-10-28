///|
/// Assemble the selected prompt, project instructions, skills, and workspace
/// environment in cache-friendly order.
pub async fn configured_system_prompt(
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root~ : String = ".",
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
  let target = if workspace_root == "" { "." } else { workspace_root }
  let cwd = @fs.realpath(target) catch { _ => target }
  let outline = dir_outline(cwd).unwrap_or(
    "(empty directory): use `moon new` to create a new project here",
  )
  let environment_block =
    $|## Environment
    $|
    $|Working directory: \{cwd}
    $|Relative paths resolve against it; treat it as the workspace root and stay inside it.
    $|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
    $|Project layout (directories; hidden, build, and vendored dirs omitted):
    $|\{outline}
  prompt <+ "\n\n\{environment_block}"
  if session_scratch_dir is Some(dir) {
    prompt <+
      "\n\nSession scratch directory: \{Json(dir).stringify()} (read/write; helper scripts and cross-call files; allowed outside the workspace)."
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
  // Like skills, the configured servers vary per installation, so they also
  // sit in the tail. The section is the model's cue that a service is
  // reachable at all: without it the model has to guess that a script may
  // find something, and in practice it rarely looks.
  let mcp_section = mcp_prompt_section(@options.mcp_config_paths(matches))
  if mcp_section is Some(section) {
    prompt <+ "\n\n\{section}"
  }
  prompt.to_string()
}

///|
/// Name the servers of the merged MCP configuration in `config_paths`. A
/// server that later fails to connect is reported as unavailable by
/// `@mcp.search`. `None` when no server is configured.
async fn mcp_prompt_section(config_paths : Array[String]) -> String? {
  let names = mcp_server_names(config_paths).map(name => "`\{name}`")
  guard !names.is_empty() else { return None }
  Some(
    (
      $|## MCP servers
      $|
      $|Configured MCP servers: \{names.join(", ")}.
      $|
      $|They connect external services. Their tools are not in your function
      $|list: an mbtx script reaches them through the SDK's `mcp` package (see
      $|"MCP servers with moonbitlang/openseek_tools/mcp"). When a request
      $|involves one of these services, or before concluding that something
      $|cannot be done, search that server's tools with
      $|`@mcp.search(server="<name>")` and call one with
      $|`@mcp.call(server, tool, arguments)`, before reaching for `web_search`
      $|or a command-line client.
    ),
  )
}

///|
/// The server names `config_paths` declare under `mcpServers`, in file order;
/// a name declared again by a later file keeps its first position, as merging
/// keeps a replaced server's. Only the names are read, not the entries: the
/// prompt is built before the engine connects, sometimes by a process that
/// never connects (`sessions fork`) and lacks the variables an entry's
/// references need. A file that cannot be read or parsed names no server
/// here; the engine reports it when it connects.
async fn mcp_server_names(config_paths : Array[String]) -> Array[String] {
  let names : Array[String] = []
  for path in config_paths {
    let json = @json.parse(@fs.read_file(path).text()) catch { _ => continue }
    guard json is { "mcpServers": Object(servers), .. } else { continue }
    for name, _ in servers {
      if !names.contains(name) {
        names.push(name)
      }
    }
  }
  names
}

///|
/// Read only the workspace's `AGENTS.md`; ancestor directories may be outside
/// the caller's filesystem policy. Missing files are optional, but I/O errors
/// must remain visible.
async fn agents_prompt_section(workspace_root : String) -> String? {
  let path = @workspace_path.join_child(workspace_root, "AGENTS.md")
  guard @fs.exists(path) && @fs.kind(path) is Regular else { return None }
  // AGENTS files may start with a UTF-8 BOM; keep only the document text.
  let content = @utf8.decode(@fs.read_file(path).binary(), ignore_bom=true)
  Some(
    "Project-specific instructions and guidelines:\n\n<project_instructions path=\"\{path}\">\n\{content}\n</project_instructions>",
  )
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
