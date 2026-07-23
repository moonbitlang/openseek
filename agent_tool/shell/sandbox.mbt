///|
const SandboxSourceWriteFeedback : String =
  #|shell sandbox: source file writes from shell are blocked. Editing source through the
  #|shell is not how this project works — it is discouraged, not a temporary obstacle to
  #|route around. Our practice is to make source changes with line-anchored `edit` (or
  #|`multi_edit` for several fixes in one file) so each change stays small and reviewable.
  #|For compiler-feedback or mechanical fixes, use `edit`, not shell-generated rewrites.
  #|Do NOT try to work around this block (redirects, `sed`/`awk`/scripts, `git apply`, or
  #|stage-then-checkout tricks) — apply the change with `edit`. Keep `shell` for read-only
  #|analysis and validation commands.

///|
priv enum SourceWriteMode {
  SourceReadOnly
  TrustedSourceWrite
}

///|
priv struct AgentShellLaunch {
  program : String
  args : Array[String]
  source_write_sandboxed : Bool
  sandbox_denial_subjects : Array[String]
}

///|
priv struct AgentShellOutput {
  output : ShellOutput
  source_write_sandboxed : Bool
  sandbox_denial_subjects : Array[String]
}

///|
/// A pre-block target that sits inside the child's scratch lab is not a
/// violation: the lab is the one place a read-only subagent MAY fabricate
/// and rewrite source to verify claims empirically. Everything else keeps
/// the pre-block. (Mixed commands that also touch real source still run
/// SANDBOXED, and the SBPL profile allows writes only under the lab — the
/// kernel enforces what this static filter waives.)
fn preblock_target_outside_lab(
  target : String?,
  scratch_dir : String?,
) -> String? {
  match (target, scratch_dir) {
    (Some(target), Some(lab)) if @source_write_policy.path_is_under_lab(
        target, lab,
      ) => None
    (target, _) => target
  }
}

///|
async fn agent_shell_launch(
  workspace_root : String,
  cmd : String,
  parsed : @shell_parse.ParseResult,
  cwd? : String,
  scratch_dir? : String,
) -> AgentShellLaunch {
  let real_workspace_root = @fs.realpath(workspace_root)
  let real_cwd = match cwd {
    Some(cwd) => Some(@fs.realpath(cwd) catch { _ => cwd })
    None => None
  }
  // The lab is realpath'd because sandbox-exec matches `file-write*` rules
  // against the kernel-canonical path (macOS `/tmp` → `/private/tmp`): the
  // allow-subpath must name the real path or it never matches.
  let scratch_dir = match scratch_dir {
    Some(lab) => Some(@fs.realpath(lab) catch { _ => lab })
    None => None
  }
  let mode = source_write_mode_for_parse(parsed, real_workspace_root, real_cwd)
  // `moon new` is trusted to scaffold, but only into a genuinely new or empty
  // target. A scaffold that would land in an existing non-empty directory is
  // downgraded to the source-write sandbox so it cannot overwrite existing
  // files (moon new refuses an existing Moon project, but overwrites loose
  // `.mbt` files in a non-project directory).
  let mode = if mode is TrustedSourceWrite &&
    parse_scaffolds_unsafe_target(
      parsed,
      real_cwd.unwrap_or(real_workspace_root),
    ) {
    SourceReadOnly
  } else {
    mode
  }
  // A scratch lab means this is a read-only subagent child whose ONLY
  // sanctioned writes are lab-local. The static guard admitted this
  // command as lab-bound, but "trusted" moon writes (e.g. `moon new`) would
  // otherwise run UNSANDBOXED — making the guard the sole defense (K3
  // review). Force the sandbox with the lab-allow profile so the kernel
  // denies any workspace-source write regardless of guard precision.
  let mode = if scratch_dir is Some(_) &&
    mode is TrustedSourceWrite &&
    @sandbox.sandbox_exec_available() {
    SourceReadOnly
  } else {
    mode
  }
  if mode is TrustedSourceWrite || !@sandbox.sandbox_exec_available() {
    return {
      program: @sandbox.PlatformShellProgram,
      args: @sandbox.platform_shell_args(cmd),
      source_write_sandboxed: false,
      sandbox_denial_subjects: [],
    }
  }
  let profile_data = @sandbox.source_write_readonly_profile_data(
    real_workspace_root,
    writable_lab?=scratch_dir,
  )
  {
    program: @sandbox.SandboxExecPath,
    args: @sandbox.sandbox_exec_args(profile_data.profile, cmd),
    source_write_sandboxed: true,
    sandbox_denial_subjects: profile_data.denial_subjects,
  }
}

///|
fn source_write_mode_for_parse(
  parsed : @shell_parse.ParseResult,
  real_workspace_root : String,
  cwd : String?,
) -> SourceWriteMode {
  match parsed {
    Simple(commands) if direct_source_write_redirect_target_for_root(
        parsed, real_workspace_root, cwd,
      )
      is None &&
      commands_are_trusted_source_writes(commands) => TrustedSourceWrite
    _ => SourceReadOnly
  }
}

///|
fn commands_are_trusted_source_writes(
  commands : Array[@shell_parse.SimpleCommand],
) -> Bool {
  let mut has_trusted_write = false
  for index, command in commands {
    if command.separator_before is Some("|" | "||") {
      return false
    }
    match trusted_command_class(command, commands, index) {
      TrustedCommandWrite => has_trusted_write = true
      TrustedCommandNeutral | TrustedCommandRead => ()
      UntrustedCommand => return false
    }
  }
  has_trusted_write
}

///|
priv enum TrustedCommandClass {
  TrustedCommandWrite
  TrustedCommandRead
  TrustedCommandNeutral
  UntrustedCommand
}

///|
fn trusted_command_class(
  command : @shell_parse.SimpleCommand,
  commands : Array[@shell_parse.SimpleCommand],
  index : Int,
) -> TrustedCommandClass {
  match command.command_index() {
    Some(command_index) if command_index < command.argv.length() =>
      match command.argv[command_index] {
        "cd" =>
          if command.env.length() == 0 &&
            static_relative_cd_command_effect(command, ".") is KnownCwd(_) &&
            next_command_is_guarded_by_and(commands, index) {
            TrustedCommandNeutral
          } else {
            UntrustedCommand
          }
        "moon" => trusted_moon_command_class(command, command_index)
        "git" => trusted_git_command_class(command, command_index)
        _ => UntrustedCommand
      }
    _ => UntrustedCommand
  }
}

///|
/// Classify a `git` command for the trusted-source-write path. Trust is granted
/// only to the recoverable worktree subcommands above, and only when the
/// invocation cannot reconfigure git to write from somewhere other than the
/// workspace repo's object store: a custom environment (`GIT_CONFIG_*`,
/// `env ... git`) or a relocating global option could repoint config (enabling a
/// smudge filter or merge driver), the git dir, the exec path, or the worktree —
/// e.g. `git -C /tmp/x --work-tree=. checkout` would write the workspace from a
/// different repository. Those fall through to the sandbox.
fn trusted_git_command_class(
  command : @shell_parse.SimpleCommand,
  git_index : Int,
) -> TrustedCommandClass {
  if command_has_custom_environment(command) {
    return UntrustedCommand
  }
  guard @git_policy.parse(command.argv, git_index + 1) is Some(invocation) else {
    return UntrustedCommand
  }
  for index in (git_index + 1)..<invocation.subcommand_index {
    if @git_policy.global_option_reconfigures(command.argv[index]) {
      return UntrustedCommand
    }
  }
  if @git_policy.subcommand_writes_from_object_store(invocation.subcommand) {
    TrustedCommandWrite
  } else {
    UntrustedCommand
  }
}

///|
fn trusted_moon_command_class(
  command : @shell_parse.SimpleCommand,
  moon_index : Int,
) -> TrustedCommandClass {
  if command_has_custom_environment(command) {
    return UntrustedCommand
  }
  match parse_moon_invocation(command.argv, moon_index, ".") {
    Some(invocation) if invocation.dry_run => TrustedCommandRead
    Some(invocation) if is_auto_check_moon_subcommand(
        command.argv,
        invocation.subcommand_index,
      ) => TrustedCommandWrite
    Some(invocation) if is_moon_subcommand_that_may_run_prebuild(
        command.argv,
        invocation.subcommand_index,
      ) => TrustedCommandWrite
    // Scaffolding is checked before the read-only arm: `moon new -- --help`
    // scaffolds a directory named `--help`, but that arm's help scan runs past
    // `--` and would otherwise misclassify it as read-only.
    Some(invocation) if is_moon_scaffold_subcommand(
        command.argv,
        invocation.subcommand_index,
      ) => TrustedCommandWrite
    Some(invocation) if is_source_readonly_moon_subcommand(
        command.argv,
        invocation.subcommand_index,
      ) => TrustedCommandRead
    _ => UntrustedCommand
  }
}

///|
/// Whether the moon subcommand scaffolds a new project — `moon new`, which
/// writes `moon.mod` and starter `.mbt` files into a fresh directory. That is a
/// legitimate source write, so it must be trusted; otherwise the sandbox's
/// source-write deny blocks the generated files and `moon new` fails. Kept
/// separate from `is_auto_check_moon_subcommand` so it grants ONLY the sandbox
/// trust here, without also triggering a post-command `moon check` (which would
/// run against the current package, not the freshly created one). A `--help`
/// invocation writes nothing, so it is not treated as a source write.
fn is_moon_scaffold_subcommand(
  argv : Array[String],
  subcommand_index : Int,
) -> Bool {
  // Detect help only BEFORE `--`; `moon new -- --help` scaffolds a directory
  // literally named `--help`, so that trailing token is a path, not a flag.
  argv[subcommand_index] == "new" &&
  !argv_contains_help_flag_before_double_dash(argv, subcommand_index + 1)
}

///|
/// The `<PATH>` positional of a `moon new` invocation. Absolute paths are
/// normalized directly; relative paths are resolved against the command's cwd.
/// Grammar is `moon new [OPTIONS] <PATH>`: `--user`/`--name`/`--target-dir`
/// take a value, the rest are boolean flags, and every token after `--` is
/// positional. Returns the first positional as a normalized path, or None when
/// none is present.
fn moon_new_target(
  argv : Array[String],
  new_index : Int,
  cwd : String,
) -> String? {
  let mut index = new_index + 1
  let mut after_double_dash = false
  while index < argv.length() {
    let arg = argv[index]
    if !after_double_dash && arg == "--" {
      after_double_dash = true
      index += 1
      continue
    }
    if !after_double_dash &&
      (arg == "--user" || arg == "--name" || arg == "--target-dir") {
      index += 2
      continue
    }
    if !after_double_dash && arg.has_prefix("-") && arg != "-" {
      index += 1
      continue
    }
    let target = @path.Path(arg)
    let resolved_target = if target.is_absolute() {
      target
    } else {
      @path.Path(cwd).join(target)
    }
    return Some(resolved_target.normalize().to_string())
  }
  None
}

///|
/// Whether the parse scaffolds (`moon new`) into a target that already exists
/// and is NON-EMPTY — where moon new could overwrite existing files (e.g.
/// `moon new --name main <dir-with-loose-source>`). A genuinely new or empty
/// target has nothing to clobber and stays trusted; an unsafe or undeterminable
/// target is reported so the caller re-applies the source-write sandbox.
///
/// This is a best-effort, good-will-agent guard: it catches an honest `moon new`
/// aimed at an existing directory. The target is resolved lexically against the
/// parsed cwd, so an agent deliberately defeating it (symlink tricks, a
/// preceding `cd`, or a chain that repopulates the target between this check and
/// launch) could still slip through — hard, race-free containment is the planned
/// wasm backend's job.
async fn parse_scaffolds_unsafe_target(
  parsed : @shell_parse.ParseResult,
  base_cwd : String,
) -> Bool {
  guard parsed is Simple(commands) else { return false }
  for command in commands {
    guard moon_command_start(command) is Some(moon_index) else { continue }
    guard parse_moon_invocation(command.argv, moon_index, base_cwd)
      is Some(invocation) else {
      continue
    }
    guard is_moon_scaffold_subcommand(command.argv, invocation.subcommand_index) else {
      continue
    }
    match
      moon_new_target(command.argv, invocation.subcommand_index, invocation.cwd) {
      None => return true
      Some(target) =>
        if @fs.exists(target) {
          let entries = @fs.readdir(target) catch {
            // A cancellation must abort the launch, not be turned into a
            // "treat as unsafe" verdict that lets setup continue.
            error if @async.is_being_cancelled() => raise error
            _ => return true
          }
          if entries.length() > 0 {
            return true
          }
        }
    }
  }
  false
}

///|
fn is_moon_subcommand_that_may_run_prebuild(
  argv : Array[String],
  subcommand_index : Int,
) -> Bool {
  match argv[subcommand_index] {
    "run" =>
      !argv_contains_update_flag_before_double_dash(argv, subcommand_index + 1) &&
      !argv_contains_help_flag_before_double_dash(argv, subcommand_index + 1) &&
      !moon_run_uses_inline_or_stdin_source(argv, subcommand_index + 1)
    "check" | "build" | "test" =>
      !argv_contains_update_flag(argv, subcommand_index + 1) &&
      !argv_contains_help_flag(argv, subcommand_index + 1)
    _ => false
  }
}

///|
fn moon_run_uses_inline_or_stdin_source(
  argv : Array[String],
  start : Int,
) -> Bool {
  let mut index = start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--" {
      index += 1
      continue
    }
    if arg == "-e" || moon_run_attached_inline_script_option(arg) {
      return true
    }
    if moon_run_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return false
      }
      index += 2
      continue
    }
    if moon_run_attached_value_option(arg) {
      index += 1
      continue
    }
    if arg.has_prefix("-") && arg != "-" {
      index += 1
      continue
    }
    return arg == "-"
  }
  false
}

///|
fn moon_run_option_consumes_next(arg : String) -> Bool {
  match arg {
    "-e"
    | "--target"
    | "--target-dir"
    | "--warn-list"
    | "-j"
    | "--jobs"
    | "--render-no-loc"
    | "--diagnostic-limit" => true
    _ => false
  }
}

///|
fn moon_run_attached_inline_script_option(arg : String) -> Bool {
  arg.has_prefix("-e") && arg.length() > 2
}

///|
fn moon_run_attached_value_option(arg : String) -> Bool {
  moon_attached_value_option(arg, "--target") ||
  moon_attached_value_option(arg, "--target-dir") ||
  moon_attached_value_option(arg, "--warn-list") ||
  moon_attached_value_option(arg, "-j") ||
  moon_attached_value_option(arg, "--jobs") ||
  moon_attached_value_option(arg, "--render-no-loc") ||
  moon_attached_value_option(arg, "--diagnostic-limit")
}

///|
fn is_source_readonly_moon_subcommand(
  argv : Array[String],
  subcommand_index : Int,
) -> Bool {
  if argv_contains_update_flag(argv, subcommand_index + 1) {
    return false
  }
  if argv_contains_help_flag(argv, subcommand_index + 1) {
    return true
  }
  match argv[subcommand_index] {
    "check" => true
    "fmt" =>
      argv_contains_flag(argv, subcommand_index + 1, "--check") ||
      argv_contains_flag(argv, subcommand_index + 1, "--warn")
    _ => false
  }
}

///|
/// Whether `redirect` writes a file (so its target may need source-write
/// guarding), skipping any leading fd number. `>&` is a file write only when
/// its target is a path, not an fd dup (`2>&1`). Each arm anchors with `$` so
/// the operator must match in full — the exact-string equivalent of the
/// original strip-then-literal-match, not a looser prefix; the end anchor also
/// makes the arms mutually exclusive (`>` backtracks to `>>` on `">>"`).
fn redirect_writes_file(redirect : @shell_parse.Redirect) -> Bool {
  lexscan redirect.op {
    re"^[0-9]*" + re">&$" => !is_fd_redirect_target(redirect.target)
    re"^[0-9]*" + re"(>|>\||>>|<>|&>|&>>)$" => true
    _ => false
  }
}

///|
fn is_fd_redirect_target(target : String) -> Bool {
  lexscan target {
    re"^(-|[0-9]*)$" => true
    _ => false
  }
}

///|
/// The protected workspace source file a write redirect in `parsed` would
/// clobber, or `None` when no simple command redirects into one. Backs
/// `shell`'s "source file write redirect" pre-run block: a redirect like
/// `echo x > src/foo.mbt` or `moon fmt >> lib.mbt` sidesteps the
/// `edit`/`multi_edit` tools that source changes must go through, so `shell`
/// refuses it up front rather than let it overwrite tracked source. The scan
/// covers the write forms `redirect_writes_file` recognizes (`>`, `>|`, `>>`,
/// `<>`, `&>`, `&>>`, and `>&` to a path) and returns on the first target that
/// `@source_write_policy.is_protected_workspace_source_path` flags.
///
/// Only `Simple` command lines are inspected (a non-simple parse returns
/// `None`); the sandbox's `deny file-write*` rules on protected source paths are
/// the runtime backstop for what this parse-based pass cannot see.
/// `workspace_root` and `cwd` are canonicalized and existing symlinks followed
/// first, so a redirect that reaches source through an existing link is still
/// caught, and the result is the resolved real path of that target.
async fn direct_source_write_redirect_target(
  parsed : @shell_parse.ParseResult,
  workspace_root : String,
  cwd : String?,
) -> String? {
  let real_workspace_root = @fs.realpath(workspace_root)
  let real_cwd = match cwd {
    Some(cwd) => Some(@fs.realpath(cwd) catch { _ => cwd })
    None => None
  }
  direct_source_write_redirect_target_for_root_following_existing_links(
    parsed, real_workspace_root, real_cwd,
  )
}

///|
async fn direct_source_write_redirect_target_for_root_following_existing_links(
  parsed : @shell_parse.ParseResult,
  real_workspace_root : String,
  cwd : String?,
) -> String? {
  match parsed {
    Simple(commands) =>
      direct_source_write_redirect_target_in_commands_following_existing_links(
        commands,
        real_workspace_root,
        source_write_detection_cwd(real_workspace_root, cwd),
      )
    _ => None
  }
}

///|
fn direct_source_write_redirect_target_for_root(
  parsed : @shell_parse.ParseResult,
  real_workspace_root : String,
  cwd : String?,
) -> String? {
  match parsed {
    Simple(commands) =>
      direct_source_write_redirect_target_in_commands(
        commands,
        real_workspace_root,
        source_write_detection_cwd(real_workspace_root, cwd),
      )
    _ => None
  }
}

///|
fn direct_source_write_redirect_target_in_commands(
  commands : Array[@shell_parse.SimpleCommand],
  real_workspace_root : String,
  initial_cwd : String,
) -> String? {
  let mut cwd_state = source_write_initial_cwd_state(initial_cwd)
  for index, command in commands {
    for redirect in command.redirects {
      if redirect_writes_file(redirect) {
        for
          cwd in source_write_detection_cwds(
            cwd_state.active,
            real_workspace_root,
          ) {
          let target = resolve_source_write_redirect_target(
            cwd,
            redirect.target,
          )
          if @source_write_policy.is_protected_workspace_source_path(
              real_workspace_root, target,
            ) {
            return Some(target)
          }
        }
      }
    }
    cwd_state = source_write_next_cwd_state(
      command,
      cwd_state,
      next_command_separator(commands, index),
    )
  }
  None
}

///|
async fn direct_source_write_redirect_target_in_commands_following_existing_links(
  commands : Array[@shell_parse.SimpleCommand],
  real_workspace_root : String,
  initial_cwd : String,
) -> String? {
  let mut cwd_state = source_write_initial_cwd_state(initial_cwd)
  for index, command in commands {
    for redirect in command.redirects {
      if redirect_writes_file(redirect) {
        for
          cwd in source_write_detection_cwds_following_existing_links(
            cwd_state.active,
            real_workspace_root,
          ) {
          let target = resolve_source_write_redirect_target(
            cwd,
            redirect.target,
          )
          if @source_write_policy.is_protected_workspace_source_path(
              real_workspace_root, target,
            ) {
            return Some(target)
          }
          match
            existing_path_resolves_to_protected_workspace_source(
              real_workspace_root, target,
            ) {
            Some(resolved) => return Some(resolved)
            None => ()
          }
        }
      }
    }
    cwd_state = source_write_next_cwd_state(
      command,
      cwd_state,
      next_command_separator(commands, index),
    )
  }
  None
}

///|
priv struct SourceWriteCwdState {
  active : Array[String?]
  deferred : Array[String?]
}

///|
fn source_write_initial_cwd_state(initial_cwd : String) -> SourceWriteCwdState {
  { active: [Some(initial_cwd)], deferred: [] }
}

///|
fn source_write_detection_cwds(
  candidates : Array[String?],
  real_workspace_root : String,
) -> Array[String] {
  let cwds : Array[String] = []
  for candidate in candidates {
    let cwd = candidate.unwrap_or(real_workspace_root)
    push_unique_normalized_path(cwds, cwd)
  }
  cwds
}

///|
async fn source_write_detection_cwds_following_existing_links(
  candidates : Array[String?],
  real_workspace_root : String,
) -> Array[String] {
  let cwds : Array[String] = []
  for candidate in candidates {
    let cwd = candidate.unwrap_or(real_workspace_root)
    push_unique_normalized_path(cwds, cwd)
    let real_cwd = @fs.realpath(cwd) catch {
      error if @async.is_being_cancelled() => raise error
      _ => cwd
    }
    push_unique_normalized_path(cwds, real_cwd)
  }
  cwds
}

///|
fn source_write_next_cwd_state(
  command : @shell_parse.SimpleCommand,
  state : SourceWriteCwdState,
  next_separator : String?,
) -> SourceWriteCwdState {
  let success : Array[String?] = []
  let failure : Array[String?] = []
  for cwd in state.active {
    match cwd_command_effect_for_detection(command, cwd) {
      KnownCwd(next) => {
        push_unique_cwd_candidate(success, Some(next))
        push_unique_cwd_candidate(failure, cwd)
      }
      UnknownCwd => {
        push_unique_cwd_candidate(success, None)
        push_unique_cwd_candidate(failure, cwd)
      }
      NotCwdCommand => {
        push_unique_cwd_candidate(success, cwd)
        push_unique_cwd_candidate(failure, cwd)
      }
    }
  }
  match next_separator {
    Some("&&") => {
      append_unique_cwd_candidates(state.deferred, failure)
      { active: success, deferred: state.deferred }
    }
    Some("||") => {
      append_unique_cwd_candidates(failure, state.deferred)
      { active: failure, deferred: success }
    }
    Some("|") => {
      append_unique_cwd_candidates(failure, state.deferred)
      { active: failure, deferred: [] }
    }
    _ => {
      append_unique_cwd_candidates(success, failure)
      append_unique_cwd_candidates(success, state.deferred)
      { active: success, deferred: [] }
    }
  }
}

///|
fn next_command_separator(
  commands : Array[@shell_parse.SimpleCommand],
  index : Int,
) -> String? {
  if index + 1 < commands.length() {
    commands[index + 1].separator_before
  } else {
    None
  }
}

///|
fn append_unique_cwd_candidates(
  target : Array[String?],
  source : Array[String?],
) -> Unit {
  for candidate in source {
    push_unique_cwd_candidate(target, candidate)
  }
}

///|
fn push_unique_cwd_candidate(
  candidates : Array[String?],
  candidate : String?,
) -> Unit {
  if !candidates.any(existing => cwd_candidate_equal(existing, candidate)) {
    candidates.push(candidate)
  }
}

///|
fn cwd_candidate_equal(left : String?, right : String?) -> Bool {
  match (left, right) {
    (Some(left), Some(right)) => left == right
    (None, None) => true
    _ => false
  }
}

///|
async fn existing_path_resolves_to_protected_workspace_source(
  real_workspace_root : String,
  target : String,
) -> String? {
  let resolved = @fs.realpath(target) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  if @source_write_policy.is_protected_workspace_source_path(
      real_workspace_root, resolved,
    ) {
    Some(resolved)
  } else {
    None
  }
}

///|
async fn direct_source_tree_operation_target(
  parsed : @shell_parse.ParseResult,
  workspace_root : String,
  cwd : String?,
) -> String? {
  let real_workspace_root = @fs.realpath(workspace_root)
  let real_cwd = match cwd {
    Some(cwd) => Some(@fs.realpath(cwd) catch { _ => cwd })
    None => None
  }
  direct_source_tree_operation_target_for_root(
    parsed, real_workspace_root, real_cwd,
  )
}

///|
async fn direct_source_tree_operation_target_for_root(
  parsed : @shell_parse.ParseResult,
  real_workspace_root : String,
  cwd : String?,
) -> String? {
  match parsed {
    Simple(commands) =>
      direct_source_tree_operation_target_in_commands(
        commands,
        real_workspace_root,
        source_write_detection_cwd(real_workspace_root, cwd),
      )
    _ => None
  }
}

///|
async fn dynamic_source_tree_operation_target(
  parsed : @shell_parse.ParseResult,
  cmd : String,
  workspace_root : String,
  cwd : String?,
) -> String? {
  guard parsed is TooComplex(_) else { return None }
  if !command_text_mentions_dynamic_source_tree_write(cmd) {
    return None
  }
  let real_workspace_root = @fs.realpath(workspace_root)
  let real_cwd = match cwd {
    Some(cwd) => Some(@fs.realpath(cwd) catch { _ => cwd })
    None => None
  }
  dynamic_source_tree_operation_target_for_text(
    cmd,
    real_workspace_root,
    source_write_detection_cwd(real_workspace_root, real_cwd),
  )
}

///|
fn command_text_mentions_dynamic_source_tree_write(text : String) -> Bool {
  let executable_text = command_text_without_heredoc_bodies(text)
  if command_text_mentions_unsafe_git_source_operation(executable_text) {
    return true
  }
  if command_text_mentions_unsafe_in_place_sed(executable_text) ||
    command_text_mentions_powershell_source_operation(executable_text) ||
    command_text_redirects_to_source_path(executable_text) {
    return true
  }
  let mentions_source_path = script_text_mentions_source_path(executable_text)
  let mentions_generated_path = script_text_mentions_generated_tree_path(
    executable_text,
  )
  if !mentions_source_path && !mentions_generated_path {
    return false
  }
  let mut source_tree_command = false
  let mut tree_transfer_command = false
  let words = command_text_words(executable_text)
  for index, word in words {
    if !command_text_is_command_position(words, index) {
      continue
    }
    match command_basename(word) {
      "mv" | "cp" | "install" => {
        source_tree_command = true
        tree_transfer_command = true
      }
      "rm" | "touch" | "tee" => source_tree_command = true
      _ => ()
    }
  }
  if mentions_source_path &&
    (source_tree_command || script_text_mentions_write_or_move(executable_text)) {
    return true
  }
  mentions_generated_path &&
  (tree_transfer_command || script_text_mentions_tree_transfer(executable_text))
}

///|
fn dynamic_source_tree_operation_target_for_text(
  text : String,
  real_workspace_root : String,
  initial_cwd : String,
) -> String? {
  if !command_text_mentions_dynamic_source_tree_write(text) {
    return None
  }
  let cwd = command_text_static_cwd_before_dynamic_source_write(
    text, initial_cwd,
  )
  if command_text_source_literals_are_only_absolute_outside_workspace(
      text, real_workspace_root,
    ) {
    return None
  }
  match script_source_literal_preblock_target(text, real_workspace_root, cwd) {
    Some(target) =>
      if target.contains("*") || target.contains("?") || target.contains("[") {
        return git_workspace_scope_target(real_workspace_root, cwd)
      } else {
        return Some(target)
      }
    None => ()
  }
  git_workspace_scope_target(real_workspace_root, cwd)
}

///|
fn command_text_static_cwd_before_dynamic_source_write(
  text : String,
  initial_cwd : String,
) -> String {
  let words = command_text_words(command_text_without_heredoc_bodies(text))
  let mut cwd = initial_cwd
  for index, word in words {
    if !command_text_is_command_position(words, index) {
      continue
    }
    let end = command_text_segment_end(words, index)
    if command_basename(word) == "cd" {
      let target_index = if index + 3 == end && words[index + 1] == "--" {
        Some(index + 2)
      } else if index + 2 == end {
        Some(index + 1)
      } else {
        None
      }
      match target_index {
        Some(target_index) => {
          let target = words[target_index]
          if target != "" && target != "--" && !target.has_prefix("-") {
            cwd = resolve_source_write_redirect_target(cwd, target)
          }
        }
        None => ()
      }
    } else {
      let segment = [ for segment_index in index..<end => words[segment_index] ]
      if command_text_mentions_dynamic_source_tree_write(segment.join(" ")) {
        return cwd
      }
    }
  }
  cwd
}

///|
fn command_text_source_literals_are_only_absolute_outside_workspace(
  text : String,
  real_workspace_root : String,
) -> Bool {
  let mut saw_source_literal = false
  for literal in script_quoted_literals(text) {
    if script_text_mentions_source_path(literal) {
      saw_source_literal = true
      let nested_literals = script_quoted_literals(literal)
      let nested_source_literals : Array[String] = []
      for nested in nested_literals {
        if script_text_mentions_source_path(nested) {
          nested_source_literals.push(nested)
        }
      }
      let source_literals = if nested_source_literals.length() > 0 {
        nested_source_literals
      } else {
        [literal]
      }
      if source_literals.any(source_literal => {
          let path : @path.Path = source_literal
          !path.is_absolute() ||
          @source_write_policy.is_protected_workspace_source_path(
            real_workspace_root, source_literal,
          )
        }) {
        return false
      }
    }
  }
  saw_source_literal
}

///|
fn command_text_redirects_to_source_path(text : String) -> Bool {
  for line in text.split("\n") {
    for target in heredoc_output_targets_in_line(line.to_owned()) {
      if script_text_mentions_source_path(target) {
        return true
      }
    }
  }
  false
}

///|
fn command_text_mentions_unsafe_in_place_sed(text : String) -> Bool {
  let words = command_text_words(text)
  for index, word in words {
    if command_token_basename_is(word, "sed") &&
      command_text_word_runs_as_command(words, index) {
      if command_text_sed_segment_has_in_place(words, index) {
        if !command_text_sed_is_safe_non_source_find_exec(words, index) {
          return true
        }
      }
    }
  }
  false
}

///|
/// True when `words[index]` is executed as a command: either a shell command
/// position (`| sed`, `&& sed`, `find ... -exec sed`) or the utility that an
/// `xargs` at the start of its segment runs (`... | xargs sed -i ...`). `xargs`
/// runs its first non-option operand as a command, so a `sed -i`/`git restore`
/// reached that way is a real source write even though the token sits in the
/// middle of the `xargs` argument list rather than in shell command position.
fn command_text_word_runs_as_command(
  words : Array[String],
  index : Int,
) -> Bool {
  command_text_is_command_position(words, index) ||
  command_text_is_xargs_utility(words, index)
}

///|
/// True when `words[index]` is the utility command an `xargs` invokes. The
/// `xargs` must be the effective command at the start of `index`'s segment, and
/// `index` must be the first operand that is not an `xargs` option (or its
/// consumed value).
fn command_text_is_xargs_utility(words : Array[String], index : Int) -> Bool {
  let segment_start = command_text_segment_start(words, index)
  let segment_end = command_text_segment_end(words, segment_start)
  guard command_text_effective_command_index(words, segment_start, segment_end)
    is Some(command_index) else {
    return false
  }
  guard command_index < index &&
    command_token_basename_is(words[command_index], "xargs") else {
    return false
  }
  command_text_xargs_utility_index(words, command_index + 1, segment_end) ==
  Some(index)
}

///|
/// Index of the first `xargs` operand that names the utility to run, skipping
/// `xargs` options and any separate values they consume. Returns the operand
/// after `--`, or `None` when only options remain (xargs then defaults to
/// `echo`, which writes nothing).
fn command_text_xargs_utility_index(
  words : Array[String],
  start : Int,
  limit : Int,
) -> Int? {
  let mut index = start
  while index < limit {
    let arg = words[index]
    if arg == "--" {
      return if index + 1 < limit { Some(index + 1) } else { None }
    }
    if arg.has_prefix("-") && arg != "-" {
      index += if command_text_xargs_option_consumes_next(arg) { 2 } else { 1 }
      continue
    }
    return Some(index)
  }
  None
}

///|
/// Whether an `xargs` option takes the next word as a separate value (so the
/// scanner must skip that value when locating the utility). Covers GNU and the
/// BSD/macOS-only `-J`/`-R`/`-S` (replacement string, max replacements, replace
/// size). Attached forms (`-n5`, `-I{}`, `--max-args=5`) and no-arg flags
/// (`-r`, `-0`, `-t`) consume only their own token via the generic option branch.
fn command_text_xargs_option_consumes_next(arg : String) -> Bool {
  match arg {
    "-a"
    | "-d"
    | "-E"
    | "-I"
    | "-J"
    | "-L"
    | "-n"
    | "-P"
    | "-R"
    | "-S"
    | "-s"
    | "--arg-file"
    | "--delimiter"
    | "--eof"
    | "--replace"
    | "--max-lines"
    | "--max-args"
    | "--max-procs"
    | "--max-chars" => true
    _ => false
  }
}

///|
fn command_text_mentions_unsafe_git_source_operation(text : String) -> Bool {
  let words = command_text_words(text)
  for index, word in words {
    if command_token_basename_is(word, "git") &&
      command_text_word_runs_as_command(words, index) {
      let segment_end = command_text_segment_end(words, index)
      if @git_policy.text_should_preblock(words, index + 1, segment_end) {
        return true
      }
      // A custom environment before `git` (e.g. `GIT_DIR=… git checkout -- *.mbt`)
      // can repoint git's repo/worktree/config; the text path cannot see it from
      // `words[index + 1..]`, so block object-store writers carrying one.
      if command_text_segment_has_custom_env(words, index) &&
        @git_policy.text_invocation_writes_from_object_store(
          words,
          index + 1,
          segment_end,
        ) {
        return true
      }
    }
  }
  false
}

///|
/// True when the command segment ending at the `git` word at `git_index` carries
/// a custom environment — a leading `env` runner or a `VAR=value` assignment.
fn command_text_segment_has_custom_env(
  words : Array[String],
  git_index : Int,
) -> Bool {
  for index in command_text_segment_start(words, git_index)..<git_index {
    let word = words[index]
    if command_basename(word) == "env" || command_text_env_assignment_word(word) {
      return true
    }
  }
  false
}

///|
fn command_text_mentions_powershell_source_operation(text : String) -> Bool {
  let words = command_text_words(text)
  for index, word in words {
    if !command_text_is_command_position(words, index) {
      continue
    }
    let name = command_basename(word).to_lower()
    if powershell_source_writing_command_name(name) {
      let end = command_text_segment_end(words, index)
      for arg_index in (index + 1)..<end {
        if script_text_mentions_source_path(words[arg_index]) {
          return true
        }
      }
    }
  }
  false
}

///|
fn powershell_source_writing_command_name(name : String) -> Bool {
  match name {
    "set-content"
    | "sc"
    | "add-content"
    | "ac"
    | "clear-content"
    | "clc"
    | "out-file"
    | "tee-object"
    | "copy-item"
    | "cpi"
    | "move-item"
    | "mi"
    | "remove-item"
    | "ri"
    | "del"
    | "erase"
    | "rename-item"
    | "rni"
    | "ren"
    | "new-item"
    | "ni" => true
    _ => false
  }
}

///|
fn command_text_sed_segment_has_in_place(
  words : Array[String],
  sed_index : Int,
) -> Bool {
  scan_sed_args_for_in_place(
    words,
    sed_index + 1,
    command_text_segment_end(words, sed_index),
  )
}

///|
fn command_text_sed_is_safe_non_source_find_exec(
  words : Array[String],
  sed_index : Int,
) -> Bool {
  let payload_start = command_text_segment_start(words, sed_index)
  if payload_start == 0 {
    return false
  }
  let exec_index = payload_start - 1
  let exec = words[exec_index]
  guard exec == "-exec" || exec == "-execdir" else { return false }
  let command_start = command_text_segment_start(words, exec_index)
  guard command_start < words.length() else { return false }
  guard command_token_basename_is(words[command_start], "find") else {
    return false
  }
  find_non_source_name_or_path_filter_proves_safe_before(
    words,
    command_start + 1,
    exec_index,
  ) &&
  sed_targets_only_find_results(
    words,
    sed_index + 1,
    command_text_segment_end(words, sed_index),
  )
}

///|
fn command_text_word_is_command_separator(word : String) -> Bool {
  word == ";" || word == "&" || word == "&&" || word == "||" || word == "|"
}

///|
fn command_text_segment_end(words : Array[String], command_index : Int) -> Int {
  let mut index = command_index + 1
  while index < words.length() {
    if command_text_word_is_command_separator(words[index]) {
      return index
    }
    index += 1
  }
  words.length()
}

///|
fn command_text_is_command_position(words : Array[String], index : Int) -> Bool {
  if index == 0 {
    return true
  }
  let prev = words[index - 1]
  if prev == ";" ||
    prev == "&&" ||
    prev == "||" ||
    prev == "|" ||
    prev == "(" ||
    prev == "{" ||
    prev == "-exec" ||
    prev == "-execdir" ||
    prev == "elif" ||
    prev == "do" ||
    prev == "then" ||
    prev == "else" ||
    prev == "if" ||
    prev == "while" ||
    prev == "until" ||
    prev == "time" {
    return true
  }
  command_text_effective_command_index(
    words,
    command_text_segment_start(words, index),
    index + 1,
  ) ==
  Some(index)
}

///|
fn command_text_segment_start(words : Array[String], before : Int) -> Int {
  let mut index = before
  while index > 0 {
    if command_text_word_starts_next_command_segment(words[index - 1]) {
      return index
    }
    index -= 1
  }
  0
}

///|
fn command_text_word_starts_next_command_segment(word : String) -> Bool {
  command_text_word_is_command_separator(word) ||
  word == "(" ||
  word == "{" ||
  word == "!" ||
  word == "if" ||
  word == "while" ||
  word == "until" ||
  word == "elif" ||
  word == "then" ||
  word == "else" ||
  word == "do" ||
  word == "-exec" ||
  word == "-execdir" ||
  word == "time"
}

///|
fn command_text_effective_command_index(
  words : Array[String],
  start : Int,
  limit : Int,
) -> Int? {
  let mut start = start
  while start < limit && command_text_env_assignment_word(words[start]) {
    start += 1
  }
  if start >= limit {
    return None
  }
  match words[start] {
    "env" => command_text_env_wrapped_command_index(words, start, limit)
    "command" => command_text_command_wrapped_command_index(words, start, limit)
    "builtin" =>
      if start + 1 < limit {
        let index = if words[start + 1] == "--" { start + 2 } else { start + 1 }
        if index < limit {
          Some(index)
        } else {
          Some(start)
        }
      } else {
        Some(start)
      }
    _ => Some(start)
  }
}

///|
fn command_text_env_wrapped_command_index(
  words : Array[String],
  start : Int,
  limit : Int,
) -> Int? {
  let mut index = start + 1
  let mut scanning_options = true
  while index < limit {
    let arg = words[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && (arg == "-i" || arg == "-") {
      index += 1
      continue
    }
    if scanning_options && command_text_env_option_consumes_next(arg) {
      index += 2
      continue
    }
    if scanning_options &&
      (
        command_text_env_option_with_attached_value(arg) ||
        command_text_env_no_arg_option(arg)
      ) {
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") {
      return Some(start)
    }
    if command_text_env_assignment_word(arg) {
      scanning_options = false
      index += 1
      continue
    }
    return Some(index)
  }
  Some(start)
}

///|
fn command_text_command_wrapped_command_index(
  words : Array[String],
  start : Int,
  limit : Int,
) -> Int? {
  let mut index = start + 1
  while index < limit {
    let arg = words[index]
    if arg == "--" {
      index += 1
      break
    }
    if arg == "-p" {
      index += 1
      continue
    }
    if arg == "-v" || arg == "-V" || arg.has_prefix("-") {
      return Some(start)
    }
    return Some(index)
  }
  if index < limit {
    Some(index)
  } else {
    Some(start)
  }
}

///|
fn command_text_env_option_consumes_next(arg : String) -> Bool {
  arg == "-u" || arg == "--unset"
}

///|
fn command_text_env_option_with_attached_value(arg : String) -> Bool {
  (arg.has_prefix("-u") && arg != "-u") || arg.has_prefix("--unset=")
}

///|
fn command_text_env_no_arg_option(arg : String) -> Bool {
  match arg {
    "--ignore-environment" | "-0" | "--null" | "--debug" => true
    _ => false
  }
}

///|
fn command_text_env_assignment_word(word : String) -> Bool {
  [..word.split("=")] is [name, _, ..] && command_text_valid_env_name(name)
}

///|
fn command_text_valid_env_name(name : StringView) -> Bool {
  lexscan name {
    re"^[A-Za-z_][A-Za-z0-9_]*$" => true
    _ => false
  }
}

///|
priv struct HeredocDelimiter {
  marker : String
  strip_tabs : Bool
}

///|
priv struct CommandWordReadResult {
  word : String
  next : Int
}

///|
fn command_text_without_heredoc_bodies(text : String) -> String {
  let lines : Array[String] = [
    for line in text.split("\n") => line.to_owned()
  ]
  if command_lines_execute_generated_heredoc_script(lines) {
    return text
  }
  command_lines_without_nonexecuted_heredoc_bodies(lines)
}

///|
fn command_lines_without_nonexecuted_heredoc_bodies(
  lines : Array[String],
) -> String {
  let output = StringBuilder()
  let mut index = 0
  while index < lines.length() {
    let line = lines[index]
    output.write_string(line)
    if index + 1 < lines.length() {
      output.write_char('\n')
    }
    let delimiters = heredoc_delimiters_in_line(line)
    if delimiters.length() > 0 && !command_line_executes_heredoc_body(line) {
      index += 1
      for delimiter in delimiters {
        while index < lines.length() {
          if heredoc_line_matches_delimiter(lines[index], delimiter) {
            index += 1
            break
          }
          index += 1
        }
      }
    } else {
      index += 1
    }
  }
  output.to_string()
}

///|
fn command_lines_execute_generated_heredoc_script(
  lines : Array[String],
) -> Bool {
  let targets : Array[String] = []
  for line in lines {
    let delimiters = heredoc_delimiters_in_line(line)
    if delimiters.length() > 0 && !command_line_executes_heredoc_body(line) {
      for target in heredoc_output_targets_in_line(line) {
        if target != "" {
          targets.push(target)
        }
      }
    }
  }
  if targets.length() == 0 {
    return false
  }
  let executable_text = command_lines_without_nonexecuted_heredoc_bodies(lines)
  command_text_executes_generated_heredoc_target(executable_text, targets)
}

///|
fn heredoc_output_targets_in_line(line : String) -> Array[String] {
  let targets : Array[String] = []
  let chars = [ for ch in line => ch ]
  let mut index = 0
  let mut quote : Char? = None
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    match quote {
      Some(end_quote) =>
        if escaped {
          escaped = false
        } else if end_quote == '"' && ch == '\\' {
          escaped = true
        } else if ch == end_quote {
          quote = None
        }
      None =>
        if escaped {
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if ch == '>' {
          index += 1
          if index < chars.length() &&
            (chars[index] == '>' || chars[index] == '|' || chars[index] == '&') {
            index += 1
          }
          while index < chars.length() && command_text_line_space(chars[index]) {
            index += 1
          }
          match read_command_word(chars, index) {
            Some(result) => {
              if !command_redirect_target_is_fd(result.word) {
                targets.push(result.word)
              }
              index = result.next
              continue
            }
            None => ()
          }
        } else if ch == '&' &&
          index + 1 < chars.length() &&
          chars[index + 1] == '>' {
          index += 2
          if index < chars.length() && chars[index] == '>' {
            index += 1
          }
          while index < chars.length() && command_text_line_space(chars[index]) {
            index += 1
          }
          match read_command_word(chars, index) {
            Some(result) => {
              if !command_redirect_target_is_fd(result.word) {
                targets.push(result.word)
              }
              index = result.next
              continue
            }
            None => ()
          }
        }
    }
    index += 1
  }
  for target in heredoc_tee_output_targets_in_line(line) {
    targets.push(target)
  }
  targets
}

///|
fn heredoc_tee_output_targets_in_line(line : String) -> Array[String] {
  guard command_line_before_first_heredoc(line) is Some(prefix) else {
    return []
  }
  let targets : Array[String] = []
  for target in heredoc_tee_output_targets_in_command_text(prefix) {
    targets.push(target)
  }
  match command_line_after_first_post_heredoc_pipe(line) {
    Some(suffix) =>
      for target in heredoc_tee_output_targets_in_command_text(suffix) {
        targets.push(target)
      }
    None => ()
  }
  targets
}

///|
fn heredoc_tee_output_targets_in_command_text(text : String) -> Array[String] {
  let targets : Array[String] = []
  let words = command_text_words(text)
  for index, word in words {
    if command_token_basename_is(word, "tee") &&
      command_text_is_command_position(words, index) {
      for
        target in command_text_tee_targets(
          words,
          index + 1,
          command_text_segment_end(words, index),
        ) {
        targets.push(target)
      }
    }
  }
  targets
}

///|
fn command_line_before_first_heredoc(line : String) -> String? {
  let prefix = StringBuilder()
  let chars = [ for ch in line => ch ]
  let mut index = 0
  let mut quote : Char? = None
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    match quote {
      Some(end_quote) => {
        prefix.write_char(ch)
        if escaped {
          escaped = false
        } else if end_quote == '"' && ch == '\\' {
          escaped = true
        } else if ch == end_quote {
          quote = None
        }
      }
      None =>
        if escaped {
          prefix.write_char(ch)
          escaped = false
        } else if ch == '\\' {
          prefix.write_char(ch)
          escaped = true
        } else if ch == '\'' || ch == '"' {
          prefix.write_char(ch)
          quote = Some(ch)
        } else if ch == '<' &&
          index + 1 < chars.length() &&
          chars[index + 1] == '<' {
          return Some(prefix.to_string())
        } else {
          prefix.write_char(ch)
        }
    }
    index += 1
  }
  None
}

///|
fn command_line_after_first_post_heredoc_pipe(line : String) -> String? {
  let chars = [ for ch in line => ch ]
  let mut index = 0
  let mut quote : Char? = None
  let mut escaped = false
  let mut saw_heredoc = false
  while index < chars.length() {
    let ch = chars[index]
    match quote {
      Some(end_quote) =>
        if escaped {
          escaped = false
        } else if end_quote == '"' && ch == '\\' {
          escaped = true
        } else if ch == end_quote {
          quote = None
        }
      None =>
        if escaped {
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if !saw_heredoc &&
          ch == '<' &&
          index + 1 < chars.length() &&
          chars[index + 1] == '<' {
          saw_heredoc = true
          index += 1
        } else if saw_heredoc &&
          ch == '|' &&
          !(index > 0 && chars[index - 1] == '|') &&
          !(index + 1 < chars.length() && chars[index + 1] == '|') {
          return Some(chars_to_string(chars, index + 1))
        }
    }
    index += 1
  }
  None
}

///|
fn chars_to_string(chars : Array[Char], start : Int) -> String {
  let output = StringBuilder()
  for index in start..<chars.length() {
    output.write_char(chars[index])
  }
  output.to_string()
}

///|
fn command_text_tee_targets(
  words : Array[String],
  start : Int,
  end : Int,
) -> Array[String] {
  let targets : Array[String] = []
  let mut scanning_options = true
  for index in start..<end {
    let arg = words[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      continue
    }
    if scanning_options && tee_supported_no_arg_option(arg) {
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      continue
    }
    targets.push(arg)
  }
  targets
}

///|
fn read_command_word(
  chars : Array[Char],
  start : Int,
) -> CommandWordReadResult? {
  if start >= chars.length() {
    return None
  }
  let word = StringBuilder()
  let mut index = start
  let mut quote : Char? = None
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    match quote {
      Some(end_quote) =>
        if escaped {
          word.write_char(ch)
          escaped = false
        } else if end_quote == '"' && ch == '\\' {
          escaped = true
        } else if ch == end_quote {
          quote = None
        } else {
          word.write_char(ch)
        }
      None =>
        if escaped {
          word.write_char(ch)
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if command_text_line_space(ch) || command_word_stop_char(ch) {
          break
        } else {
          word.write_char(ch)
        }
    }
    index += 1
  }
  let word = word.to_string()
  if word == "" {
    None
  } else {
    Some({ word, next: index })
  }
}

///|
fn command_word_stop_char(ch : Char) -> Bool {
  ch == ';' ||
  ch == '&' ||
  ch == '|' ||
  ch == '<' ||
  ch == '>' ||
  ch == '(' ||
  ch == ')'
}

///|
fn command_redirect_target_is_fd(target : String) -> Bool {
  if target == "-" || target == "" {
    return true
  }
  for ch in target {
    if !(ch is ('0'..='9')) {
      return false
    }
  }
  true
}

///|
fn command_text_executes_generated_heredoc_target(
  text : String,
  targets : Array[String],
) -> Bool {
  let words = command_text_words(text)
  for index, word in words {
    if !command_text_is_command_position(words, index) {
      continue
    }
    if command_text_token_executes_stdin_script(word) {
      if script_runtime_invocation_mentions_heredoc_target(
          words,
          word,
          index + 1,
          command_text_segment_end(words, index),
          targets,
        ) {
        return true
      }
    }
    if command_text_token_sources_script(word) {
      if script_runtime_invocation_mentions_heredoc_target(
          words,
          word,
          index + 1,
          command_text_segment_end(words, index),
          targets,
        ) {
        return true
      }
    }
    if command_word_matches_heredoc_target(word, targets) {
      return true
    }
  }
  false
}

///|
fn command_text_token_sources_script(word : String) -> Bool {
  word == "." || word == "source"
}

///|
fn script_runtime_invocation_mentions_heredoc_target(
  words : Array[String],
  runtime : String,
  start : Int,
  end : Int,
  targets : Array[String],
) -> Bool {
  let mut index = start
  while index < end {
    let word = words[index]
    if word == "--" {
      index += 1
      if index < end {
        return command_word_matches_heredoc_target(words[index], targets)
      }
      return false
    }
    if shell_runtime_c_payload_mentions_heredoc_target(
        runtime, words, index, end, targets,
      ) {
      return true
    }
    if script_runtime_option_consumes_next(runtime, word) {
      index += 2
      continue
    }
    if word.has_prefix("-") && word != "-" {
      index += 1
      continue
    }
    return command_word_matches_heredoc_target(word, targets)
  }
  false
}

///|
fn shell_runtime_c_payload_mentions_heredoc_target(
  runtime : String,
  words : Array[String],
  index : Int,
  end : Int,
  targets : Array[String],
) -> Bool {
  if !source_writing_shell_runtime(command_basename(runtime)) {
    return false
  }
  let word = words[index]
  if word == "-c" || shell_short_option_cluster_has_c(word) {
    index + 1 < end &&
    command_text_executes_generated_heredoc_target(words[index + 1], targets)
  } else {
    false
  }
}

///|
fn script_runtime_option_consumes_next(runtime : String, arg : String) -> Bool {
  let base = source_writing_runtime_name(command_basename(runtime))
  if source_writing_shell_runtime(base) {
    return shell_option_consumes_next(arg)
  }
  if base == "python" || base == "python3" || base.has_prefix("python3.") {
    arg == "-e" || arg == "-m" || arg == "-r" || arg == "-I"
  } else {
    match base {
      "node" | "ruby" | "perl" | "php" =>
        arg == "-e" || arg == "-m" || arg == "-r" || arg == "-I"
      _ => false
    }
  }
}

///|
fn command_word_matches_heredoc_target(
  word : String,
  targets : Array[String],
) -> Bool {
  for target in targets {
    if command_word_matches_one_heredoc_target(word, target) {
      return true
    }
  }
  false
}

///|
fn command_word_matches_one_heredoc_target(
  word : String,
  target : String,
) -> Bool {
  let word = strip_leading_dot_slash(word)
  let target = strip_leading_dot_slash(target)
  word == target ||
  @workspace_path.path_basename(word) == @workspace_path.path_basename(target)
}

///|
fn strip_leading_dot_slash(path : String) -> String {
  let mut result = path
  while result.strip_prefix("./") is Some(rest) {
    result = rest.to_owned()
  }
  result
}

///|
fn heredoc_delimiters_in_line(line : String) -> Array[HeredocDelimiter] {
  let delimiters : Array[HeredocDelimiter] = []
  let chars = [ for ch in line => ch ]
  for view = chars[:] {
    match view {
      [] => break
      // A backslash escapes the next code unit, so `\<\<` is not a here-document.
      ['\\', _, .. rest] => continue rest
      // Quoted spans never start a here-document or arithmetic expansion.
      ['\'', .. rest] => continue heredoc_skip_single_quoted(rest)
      ['"', .. rest] => continue heredoc_skip_double_quoted(rest)
      // Arithmetic expansion `$(( ... ))` never contains a here-document, so skip
      // its balanced parentheses. Otherwise a left shift such as `$((1 << 8))` is
      // misread as a here-document operator whose delimiter swallows later lines.
      ['$', '(', '(', .. rest] => continue heredoc_skip_arithmetic(rest)
      // Here-document operator: `<<`, an optional `-`, optional blanks, then the
      // delimiter word.
      ['<', '<', .. rest] => {
        let (strip_tabs, rest) = match rest {
          ['-', .. after] => (true, after)
          _ => (false, rest)
        }
        let rest = heredoc_skip_line_space(rest)
        match read_heredoc_delimiter(rest) {
          Some((marker, after)) => {
            if marker != "" {
              delimiters.push({ marker, strip_tabs })
            }
            continue after
          }
          None => continue rest
        }
      }
      [_, .. rest] => continue rest
    }
  }
  delimiters
}

///|
/// Consume a single-quoted span, returning the view after the closing `'`.
/// Single quotes are literal in POSIX shells, so nothing is escaped inside.
fn heredoc_skip_single_quoted(view : ArrayView[Char]) -> ArrayView[Char] {
  for v = view {
    match v {
      ['\'', .. rest] => break rest
      [_, .. rest] => continue rest
      [] => break v
    }
  }
}

///|
/// Consume a double-quoted span, returning the view after the closing `"`. A
/// backslash escapes the next code unit, so an escaped quote does not close it.
fn heredoc_skip_double_quoted(view : ArrayView[Char]) -> ArrayView[Char] {
  for v = view {
    match v {
      ['\\', _, .. rest] => continue rest
      ['"', .. rest] => break rest
      [_, .. rest] => continue rest
      [] => break v
    }
  }
}

///|
/// Consume an arithmetic expansion whose opening `$((` was already matched,
/// returning the view after the balancing `))`.
fn heredoc_skip_arithmetic(view : ArrayView[Char]) -> ArrayView[Char] {
  for v = view, depth = 2 {
    if depth == 0 {
      break v
    }
    match v {
      ['(', .. rest] => continue rest, depth + 1
      [')', .. rest] => continue rest, depth - 1
      [_, .. rest] => continue rest, depth
      [] => break v
    }
  }
}

///|
/// Drop leading shell blanks (space or tab) from `view`.
fn heredoc_skip_line_space(view : ArrayView[Char]) -> ArrayView[Char] {
  for v = view {
    match v {
      [ch, .. rest] if command_text_line_space(ch) => continue rest
      _ => break v
    }
  }
}

///|
/// Read the here-document delimiter word at the start of `view`, returning the
/// unquoted marker and the view positioned after it, or `None` when there is no
/// delimiter (empty input or an unterminated quote).
fn read_heredoc_delimiter(view : ArrayView[Char]) -> (String, ArrayView[Char])? {
  match view {
    ['\'', .. rest] => read_quoted_heredoc_marker(rest, '\'')
    ['"', .. rest] => read_quoted_heredoc_marker(rest, '"')
    [] => None
    _ => {
      let marker = StringBuilder()
      let rest = for v = view {
        match v {
          ['\\', ch, .. rest] if heredoc_delimiter_char(ch) => {
            marker.write_char(ch)
            continue rest
          }
          [ch, .. rest] if heredoc_delimiter_char(ch) => {
            marker.write_char(ch)
            continue rest
          }
          _ => break v
        }
      }
      Some((marker.to_string(), rest))
    }
  }
}

///|
/// Read a quoted here-document marker up to the closing `quote`, returning the
/// marker and the view after the quote, or `None` if the quote never closes. A
/// backslash escapes the next code unit only inside double quotes.
fn read_quoted_heredoc_marker(
  view : ArrayView[Char],
  quote : Char,
) -> (String, ArrayView[Char])? {
  let marker = StringBuilder()
  for v = view {
    match v {
      ['\\', ch, .. rest] if quote == '"' => {
        marker.write_char(ch)
        continue rest
      }
      [ch, .. rest] if ch == quote => break Some((marker.to_string(), rest))
      [ch, .. rest] => {
        marker.write_char(ch)
        continue rest
      }
      [] => break None
    }
  }
}

///|
fn heredoc_delimiter_char(ch : Char) -> Bool {
  !command_text_line_space(ch) &&
  ch != '\r' &&
  ch != ';' &&
  ch != '&' &&
  ch != '|' &&
  ch != '<' &&
  ch != '>' &&
  ch != '(' &&
  ch != ')'
}

///|
fn heredoc_line_matches_delimiter(
  line : String,
  delimiter : HeredocDelimiter,
) -> Bool {
  let line = strip_trailing_cr(line)
  let line = if delimiter.strip_tabs { strip_leading_tabs(line) } else { line }
  line == delimiter.marker
}

///|
fn strip_trailing_cr(line : String) -> String {
  // `\r` is one code unit and one Char, so dropping the trailing Char here is
  // exactly the old `line[:length-1]` code-unit slice.
  match line {
    [.. rest, '\r'] => rest.to_owned()
    _ => line
  }
}

///|
fn strip_leading_tabs(line : String) -> String {
  let mut index = 0
  for ch in line {
    if ch == '\t' {
      index += 1
    } else {
      break
    }
  }
  line[index:].to_owned()
}

///|
fn command_text_line_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t'
}

///|
fn command_line_executes_heredoc_body(line : String) -> Bool {
  let words = command_text_words(line)
  for index, word in words {
    if command_text_token_executes_stdin_script(word) &&
      command_text_is_command_position(words, index) {
      return true
    }
  }
  false
}

///|
fn command_text_token_executes_stdin_script(word : String) -> Bool {
  let base = source_writing_runtime_name(command_basename(word))
  base == "sh" ||
  base == "bash" ||
  base == "zsh" ||
  base == "dash" ||
  base == "ksh" ||
  base == "python" ||
  base == "python3" ||
  base.has_prefix("python3.") ||
  base == "node" ||
  base == "ruby" ||
  base == "perl" ||
  base == "php"
}

///|
fn command_text_words(text : String) -> Array[String] {
  let words : Array[String] = []
  let mut token = StringBuilder()
  let chars = [ for ch in text => ch ]
  let mut index = 0
  let mut quote : Char? = None
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    match quote {
      Some(end_quote) =>
        if escaped {
          token.write_char(ch)
          escaped = false
        } else if end_quote == '"' && ch == '\\' {
          escaped = true
        } else if ch == end_quote {
          quote = None
        } else {
          token.write_char(ch)
        }
      None =>
        if escaped {
          token.write_char(ch)
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if shell_token_char(ch) {
          token.write_char(ch)
        } else {
          token = push_command_text_word(words, token)
          match ch {
            '&' =>
              if index + 1 < chars.length() && chars[index + 1] == '&' {
                words.push("&&")
                index += 1
              } else {
                words.push("&")
              }
            '|' =>
              if index + 1 < chars.length() && chars[index + 1] == '|' {
                words.push("||")
                index += 1
              } else {
                words.push("|")
              }
            ';' => words.push(";")
            '\n' | '\r' => words.push(";")
            '(' => words.push("(")
            _ => ()
          }
        }
    }
    index += 1
  }
  ignore(push_command_text_word(words, token))
  words
}

///|
fn push_command_text_word(
  words : Array[String],
  token : StringBuilder,
) -> StringBuilder {
  let word = token.to_string()
  if word != "" {
    words.push(word)
  }
  StringBuilder()
}

///|
fn shell_token_char(ch : Char) -> Bool {
  ch is ('a'..='z') ||
  ch is ('A'..='Z') ||
  ch is ('0'..='9') ||
  ch == '_' ||
  ch == '-' ||
  ch == '.' ||
  ch == '/' ||
  ch == '=' ||
  ch == '*' ||
  ch == '?' ||
  ch == '[' ||
  ch == ']' ||
  ch == '!' ||
  ch == '^' ||
  ch == ':' ||
  ch == ',' ||
  ch == '{' ||
  ch == '}' ||
  ch == '+'
}

///|
fn command_token_basename_is(token : String, word : String) -> Bool {
  token == word || token.has_suffix("/\{word}")
}

///|
async fn direct_source_tree_operation_target_in_commands(
  commands : Array[@shell_parse.SimpleCommand],
  real_workspace_root : String,
  initial_cwd : String,
) -> String? {
  let mut cwd_state = source_write_initial_cwd_state(initial_cwd)
  let predicted_dirs : Array[String] = []
  for index, command in commands {
    match command.separator_before {
      Some("|") => predicted_dirs.clear()
      _ => ()
    }
    for
      detection_cwd in source_write_detection_cwds_following_existing_links(
        cwd_state.active,
        real_workspace_root,
      ) {
      match
        source_tree_operation_target_for_command(
          command, real_workspace_root, detection_cwd, predicted_dirs,
        ) {
        Some(target) => return Some(target)
        None => ()
      }
      record_created_dirs_for_command(command, detection_cwd, predicted_dirs)
    }
    cwd_state = source_write_next_cwd_state(
      command,
      cwd_state,
      next_command_separator(commands, index),
    )
  }
  None
}

///|
async fn source_tree_operation_target_for_command(
  command : @shell_parse.SimpleCommand,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard command.command_index() is Some(command_index) else { return None }
  guard command_index < command.argv.length() else { return None }
  match command_basename(command.argv[command_index]) {
    name if source_writing_shell_runtime(name) =>
      source_writing_shell_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    name if source_writing_script_runtime(name) =>
      source_writing_script_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    name if source_writing_awk_runtime(name) =>
      source_writing_awk_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    "mv" =>
      source_tree_mv_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
        predicted_dirs,
      )
    "rm" =>
      source_tree_rm_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    "cp" =>
      source_tree_cp_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
        predicted_dirs,
      )
    "install" =>
      source_tree_install_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
        predicted_dirs,
      )
    "git" =>
      git_preblock_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
        command_has_custom_environment(command),
      )
    "find" =>
      source_tree_find_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    "touch" =>
      source_tree_touch_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    "tee" =>
      source_tree_tee_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
      )
    name =>
      source_tree_powershell_target(
        name,
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
        predicted_dirs,
      )
  }
}

///|
async fn source_tree_powershell_target(
  command_name : String,
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  match command_basename(command_name).to_lower() {
    "set-content"
    | "sc"
    | "add-content"
    | "ac"
    | "clear-content"
    | "clc"
    | "out-file"
    | "tee-object" =>
      powershell_write_target(argv, arg_start, real_workspace_root, cwd)
    "copy-item" | "cpi" =>
      powershell_copy_target(
        argv, arg_start, real_workspace_root, cwd, predicted_dirs,
      )
    "move-item" | "mi" =>
      powershell_move_target(
        argv, arg_start, real_workspace_root, cwd, predicted_dirs,
      )
    "remove-item" | "ri" | "del" | "erase" =>
      powershell_remove_target(argv, arg_start, real_workspace_root, cwd)
    "rename-item" | "rni" | "ren" =>
      powershell_rename_target(
        argv, arg_start, real_workspace_root, cwd, predicted_dirs,
      )
    "new-item" | "ni" =>
      powershell_write_target(argv, arg_start, real_workspace_root, cwd)
    _ => None
  }
}

///|
priv struct PowershellPathOperands {
  paths : Array[String]
  dest : String?
  new_name : String?
}

///|
async fn powershell_write_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard parse_powershell_path_operands(argv, arg_start) is Some(operands) else {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  for target in powershell_new_item_targets(operands, cwd) {
    if @source_write_policy.is_protected_workspace_source_path(
        real_workspace_root, target,
      ) {
      return Some(target)
    }
    match
      existing_path_resolves_to_protected_workspace_source(
        real_workspace_root, target,
      ) {
      Some(resolved) => return Some(resolved)
      None => ()
    }
  }
  None
}

///|
/// Resolve the path(s) a `New-Item` invocation creates. `-Name` names the leaf
/// item created inside each `-Path` parent (or the cwd when no `-Path` is
/// given), so `New-Item -Path . -Name main.mbt` creates `./main.mbt`, not `.`.
/// Without `-Name`, each `-Path` value is itself the created item.
fn powershell_new_item_targets(
  operands : PowershellPathOperands,
  cwd : String,
) -> Array[String] {
  let targets : Array[String] = []
  match operands.new_name {
    Some(name) =>
      if operands.paths.length() == 0 {
        targets.push(resolve_source_write_redirect_target(cwd, name))
      } else {
        for parent in operands.paths {
          let parent_dir = resolve_source_write_redirect_target(cwd, parent)
          targets.push(resolve_source_write_redirect_target(parent_dir, name))
        }
      }
    None =>
      for path in operands.paths {
        targets.push(resolve_source_write_redirect_target(cwd, path))
      }
  }
  targets
}

///|
async fn powershell_copy_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard parse_powershell_path_operands(argv, arg_start) is Some(parsed) else {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  guard operands_with_optional_dest(parsed.paths, parsed.dest) is Some(operands) else {
    return None
  }
  source_tree_copy_destination_target(
    operands, real_workspace_root, cwd, predicted_dirs,
  )
}

///|
async fn powershell_move_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard parse_powershell_path_operands(argv, arg_start) is Some(parsed) else {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  guard operands_with_optional_dest(parsed.paths, parsed.dest) is Some(operands) else {
    return None
  }
  source_tree_move_target(operands, real_workspace_root, cwd, predicted_dirs)
}

///|
async fn powershell_remove_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard parse_powershell_path_operands(argv, arg_start) is Some(operands) else {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  for path in operands.paths {
    let target = resolve_source_write_redirect_target(cwd, path)
    if protected_workspace_source_or_tree_path(real_workspace_root, target) {
      return Some(target)
    }
  }
  None
}

///|
async fn powershell_rename_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard parse_powershell_path_operands(argv, arg_start) is Some(parsed) else {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  let new_name = match parsed.new_name {
    Some(new_name) => new_name
    None if parsed.paths.length() >= 2 =>
      parsed.paths[parsed.paths.length() - 1]
    None =>
      return powershell_remove_target(argv, arg_start, real_workspace_root, cwd)
  }
  let sources : Array[String] = []
  let source_count = if parsed.new_name is Some(_) {
    parsed.paths.length()
  } else {
    parsed.paths.length() - 1
  }
  for index in 0..<source_count {
    sources.push(parsed.paths[index])
  }
  let dest = match sources.get(0) {
    Some(source) =>
      match parent_dir(resolve_source_write_redirect_target(cwd, source)) {
        Some(dir) => resolve_source_write_redirect_target(dir, new_name)
        None => resolve_source_write_redirect_target(cwd, new_name)
      }
    None => resolve_source_write_redirect_target(cwd, new_name)
  }
  source_tree_move_target(
    { sources, dest: Some(dest) },
    real_workspace_root,
    cwd,
    predicted_dirs,
  )
}

///|
fn parse_powershell_path_operands(
  argv : Array[String],
  arg_start : Int,
) -> PowershellPathOperands? {
  let paths : Array[String] = []
  let mut dest : String? = None
  let mut new_name : String? = None
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--%" {
      return None
    }
    match powershell_attached_parameter(arg) {
      Some((name, value)) => {
        if powershell_path_parameter(name) {
          paths.push(value)
        } else if powershell_destination_parameter(name) {
          dest = Some(value)
        } else if name == "newname" || name == "name" {
          new_name = Some(value)
        } else if powershell_known_value_parameter(name) {
          ()
        } else if !powershell_no_value_parameter(name) {
          return None
        }
        index += 1
        continue
      }
      None => ()
    }
    match powershell_parameter_name(arg) {
      Some(name) => {
        if powershell_path_parameter(name) ||
          powershell_destination_parameter(name) ||
          name == "newname" ||
          name == "name" ||
          powershell_known_value_parameter(name) {
          if index + 1 >= argv.length() {
            return None
          }
          let value = argv[index + 1]
          if powershell_path_parameter(name) {
            paths.push(value)
          } else if powershell_destination_parameter(name) {
            dest = Some(value)
          } else if name == "newname" || name == "name" {
            new_name = Some(value)
          }
          index += 2
          continue
        }
        if powershell_no_value_parameter(name) {
          index += 1
          continue
        }
        return None
      }
      None => ()
    }
    paths.push(arg)
    index += 1
  }
  Some({ paths, dest, new_name })
}

///|
fn powershell_attached_parameter(arg : String) -> (String, String)? {
  guard arg.strip_prefix("-") is Some(parameter) && !parameter.is_empty() else {
    return None
  }
  match parameter.find(":") {
    Some(colon) if colon > 0 =>
      Some(
        (
          parameter[:colon].to_owned().to_lower(),
          parameter[colon + 1:].to_owned(),
        ),
      )
    _ => None
  }
}

///|
fn powershell_parameter_name(arg : String) -> String? {
  guard arg.strip_prefix("-") is Some(name) && !name.is_empty() else {
    return None
  }
  Some(name.to_owned().to_lower())
}

///|
fn powershell_path_parameter(name : String) -> Bool {
  name == "path" || name == "literalpath" || name == "filepath"
}

///|
fn powershell_destination_parameter(name : String) -> Bool {
  name == "destination"
}

///|
fn powershell_known_value_parameter(name : String) -> Bool {
  match name {
    "value"
    | "encoding"
    | "stream"
    | "filter"
    | "include"
    | "exclude"
    | "credential"
    | "itemtype"
    | "type"
    | "erroraction"
    | "warningaction"
    | "informationaction" => true
    _ => false
  }
}

///|
fn powershell_no_value_parameter(name : String) -> Bool {
  match name {
    "force"
    | "recurse"
    | "whatif"
    | "confirm"
    | "verbose"
    | "debug"
    | "append"
    | "noclobber"
    | "nonewline"
    | "passthru" => true
    _ => false
  }
}

///|
fn record_created_dirs_for_command(
  command : @shell_parse.SimpleCommand,
  cwd : String,
  predicted_dirs : Array[String],
) -> Unit {
  guard command.command_index() is Some(command_index) else { return }
  guard command_index < command.argv.length() else { return }
  if command_basename(command.argv[command_index]) != "mkdir" {
    return
  }
  guard parse_mkdir_dirs(command.argv, command_index + 1, cwd) is Some(dirs) else {
    return
  }
  for dir in dirs {
    push_unique_normalized_path(predicted_dirs, dir)
  }
}

///|
fn source_writing_shell_runtime(name : String) -> Bool {
  let name = source_writing_runtime_name(name)
  name == "sh" ||
  name == "bash" ||
  name == "zsh" ||
  name == "dash" ||
  name == "ksh"
}

///|
fn source_writing_script_runtime(name : String) -> Bool {
  let name = source_writing_runtime_name(name)
  name == "python" ||
  name == "python3" ||
  name.has_prefix("python3.") ||
  name == "perl" ||
  name == "ruby" ||
  name == "node"
}

///|
fn source_writing_awk_runtime(name : String) -> Bool {
  let name = source_writing_runtime_name(name)
  name == "awk" || name == "gawk" || name == "mawk" || name == "nawk"
}

///|
fn source_writing_runtime_name(name : String) -> String {
  let name = name.to_lower()
  match name.strip_suffix(".exe") {
    Some(base) => base.to_owned()
    None => name
  }
}

///|
async fn source_writing_shell_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard shell_c_command_text(argv, arg_start) is Some(body) else { return None }
  let parsed = @shell_parse.parse_for_policy(body)
  match
    direct_source_write_redirect_target_for_root_following_existing_links(
      parsed,
      real_workspace_root,
      Some(cwd),
    ) {
    Some(target) => return Some(target)
    None => ()
  }
  match
    direct_source_tree_operation_target_for_root(
      parsed,
      real_workspace_root,
      Some(cwd),
    ) {
    Some(target) => return Some(target)
    None => ()
  }
  if command_text_mentions_dynamic_source_tree_write(body) {
    return dynamic_source_tree_operation_target_for_text(
      body,
      real_workspace_root,
      source_write_detection_cwd(real_workspace_root, Some(cwd)),
    )
  }
  None
}

///|
fn shell_c_command_text(argv : Array[String], arg_start : Int) -> String? {
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "-c" || shell_short_option_cluster_has_c(arg) {
      if index + 1 < argv.length() {
        return Some(argv[index + 1])
      } else {
        return None
      }
    }
    if shell_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      index += 2
      continue
    }
    if shell_long_option_without_next(arg) || shell_attached_value_option(arg) {
      index += 1
      continue
    }
    if arg == "--" {
      return None
    }
    if arg.has_prefix("-") && arg != "-" && !arg.has_prefix("--") {
      index += 1
      continue
    }
    return None
  }
  None
}

///|
fn shell_option_consumes_next(arg : String) -> Bool {
  arg == "-o" ||
  arg == "+o" ||
  arg == "-O" ||
  arg == "+O" ||
  arg == "--init-file" ||
  arg == "--rcfile" ||
  arg == "--emulate"
}

///|
fn shell_long_option_without_next(arg : String) -> Bool {
  match arg {
    "--noprofile"
    | "--norc"
    | "--posix"
    | "--login"
    | "--noediting"
    | "--restricted"
    | "--no-rcs"
    | "--no-globalrcs" => true
    _ => false
  }
}

///|
fn shell_attached_value_option(arg : String) -> Bool {
  arg.has_prefix("--init-file=") ||
  arg.has_prefix("--rcfile=") ||
  arg.has_prefix("--emulate=")
}

///|
fn shell_short_option_cluster_has_c(arg : String) -> Bool {
  guard arg.strip_prefix("-") is Some(options) &&
    !options.has_prefix("-") &&
    options.length() > 1 else {
    return false
  }
  options.contains("c")
}

///|
async fn source_writing_script_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let text = command_tail_text(argv, arg_start)
  if !script_text_mentions_write_or_move(text) {
    return None
  }
  match script_generated_tree_transfer_target(text, real_workspace_root, cwd) {
    Some(target) => return Some(target)
    None => ()
  }
  if !script_text_mentions_source_path(text) {
    return None
  }
  script_source_literal_preblock_target(text, real_workspace_root, cwd)
}

///|
fn source_writing_awk_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard awk_program_text(argv, arg_start) is Some(program) else { return None }
  awk_output_redirect_target(program, real_workspace_root, cwd)
}

///|
/// Pre-block, before execution and independent of the runtime sandbox, the git
/// that mutates source but is not a recoverable object-store write —
/// `@git_policy.should_preblock` (store feeders, `mv`, non-dry-run `clean`, and
/// reconfigured writers). This is the cross-platform guard; on macOS `sandbox-exec`
/// is a second layer. The recoverable writers and read-only git are handled by
/// the trusted-source-write path (`trusted_git_command_class`) instead. NOTE: a
/// determined plumbing sequence (`replace`, `filter-branch`, `commit-tree`) can
/// still seed the object store while `.git` is writable — a residual channel, not
/// a hard boundary.
fn git_preblock_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  has_custom_env : Bool,
) -> String? {
  if git_must_preblock(argv, arg_start, has_custom_env) {
    // Block unconditionally; do not condition on the resolved cwd (that would let
    // `git -C <workspace> ...` run from an outside cwd slip through). Prefer the
    // workspace-scoped target for the message; fall back to the workspace root.
    match git_workspace_scope_target(real_workspace_root, cwd) {
      Some(target) => Some(target)
      None =>
        Some(
          strip_trailing_slash(
            @path.Path(real_workspace_root).normalize().to_string(),
          ),
        )
    }
  } else {
    None
  }
}

///|
fn git_must_preblock(
  argv : Array[String],
  arg_start : Int,
  has_custom_env : Bool,
) -> Bool {
  if @git_policy.should_preblock(argv, arg_start) {
    return true
  }
  // A custom environment (`GIT_DIR`/`GIT_WORK_TREE`/`GIT_CONFIG_*`, or `env ...
  // git`) is the environment analogue of `-c`/`-C`: it can repoint git's config,
  // git dir, or worktree, so a custom-env object-store writer can write workspace
  // source from another repository. The trust path already demotes it, but on
  // platforms without sandbox-exec SourceReadOnly still runs unsandboxed, so it
  // must be pre-blocked too.
  has_custom_env &&
  (match @git_policy.parse(argv, arg_start) {
    Some(invocation) =>
      @git_policy.subcommand_writes_from_object_store(invocation.subcommand)
    None => false
  })
}

///|
fn git_workspace_scope_target(
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let target = source_write_detection_cwd(real_workspace_root, Some(cwd))
  if @workspace_path.is_under_workspace_root(root, target) {
    Some(target)
  } else {
    None
  }
}

///|
async fn source_tree_find_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  if !find_executes_sed_in_place(argv, arg_start) {
    return None
  }
  if find_in_place_sed_targets_are_proven_non_source(argv, arg_start) {
    return None
  }
  let has_filter = find_has_name_or_path_filter(argv, arg_start)
  let starts = find_start_paths(argv, arg_start)
  let starts = if starts.length() == 0 { ["."] } else { starts }
  for start in starts {
    let target = resolve_source_write_redirect_target(cwd, start)
    if @workspace_path.is_under_workspace_root(real_workspace_root, target) &&
      (
        !has_filter ||
        @source_write_policy.is_protected_workspace_source_path(
          real_workspace_root, target,
        ) ||
        protected_workspace_source_or_tree_path(real_workspace_root, target)
      ) {
      return Some(target)
    }
  }
  None
}

///|
fn find_executes_sed_in_place(argv : Array[String], arg_start : Int) -> Bool {
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "-exec" || arg == "-execdir" {
      let exec_start = index + 1
      let exec_end = find_exec_end(argv, exec_start)
      if command_text_effective_command_index(argv, exec_start, exec_end)
        is Some(sed_index) &&
        command_basename(argv[sed_index]) == "sed" &&
        scan_sed_args_for_in_place(argv, sed_index + 1, exec_end) {
        return true
      }
      index = exec_end + 1
    } else {
      index += 1
    }
  }
  false
}

///|
fn find_in_place_sed_targets_are_proven_non_source(
  argv : Array[String],
  arg_start : Int,
) -> Bool {
  let mut saw_in_place_sed = false
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "-exec" || arg == "-execdir" {
      let exec_start = index + 1
      let exec_end = find_exec_end(argv, exec_start)
      if command_text_effective_command_index(argv, exec_start, exec_end)
        is Some(sed_index) &&
        command_basename(argv[sed_index]) == "sed" &&
        scan_sed_args_for_in_place(argv, sed_index + 1, exec_end) {
        saw_in_place_sed = true
        if !find_non_source_name_or_path_filter_proves_safe_before(
            argv, arg_start, index,
          ) {
          return false
        }
        if !sed_targets_only_find_results(argv, sed_index + 1, exec_end) {
          return false
        }
      }
      index = exec_end + 1
    } else {
      index += 1
    }
  }
  saw_in_place_sed
}

///|
fn find_exec_end(argv : Array[String], start : Int) -> Int {
  let mut index = start
  while index < argv.length() {
    let arg = argv[index]
    if arg == ";" || arg == "+" {
      return index
    }
    index += 1
  }
  argv.length()
}

///|
fn find_start_paths(argv : Array[String], arg_start : Int) -> Array[String] {
  let starts : Array[String] = []
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if find_arg_starts_expression(arg) {
      break
    }
    starts.push(arg)
    index += 1
  }
  starts
}

///|
fn find_arg_starts_expression(arg : String) -> Bool {
  arg == "!" || arg == "(" || arg == ")" || arg == "," || arg.has_prefix("-")
}

///|
fn find_non_source_name_or_path_filter_proves_safe_before(
  argv : Array[String],
  arg_start : Int,
  end : Int,
) -> Bool {
  find_has_excluding_name_or_path_filter_before(argv, arg_start, end) &&
  !find_has_source_name_or_path_filter_before(argv, arg_start, end) &&
  !find_has_branching_or_negated_expression_before(argv, arg_start, end)
}

///|
fn find_has_branching_or_negated_expression_before(
  argv : Array[String],
  arg_start : Int,
  end : Int,
) -> Bool {
  let mut index = find_expression_start(argv, arg_start)
  while index < end {
    match argv[index] {
      "-o" | "-or" | "!" | "-not" | "(" | ")" | "," => return true
      _ => index += 1
    }
  }
  false
}

///|
fn find_expression_start(argv : Array[String], arg_start : Int) -> Int {
  let mut index = arg_start
  while index < argv.length() && !find_arg_starts_expression(argv[index]) {
    index += 1
  }
  index
}

///|
fn find_has_name_or_path_filter(argv : Array[String], arg_start : Int) -> Bool {
  find_source_filter_before(argv, arg_start, argv.length(), accept_any=true)
}

///|
fn find_has_excluding_name_or_path_filter_before(
  argv : Array[String],
  arg_start : Int,
  end : Int,
) -> Bool {
  let mut index = arg_start
  while index < end {
    let arg = argv[index]
    if find_filter_option_takes_pattern(arg) {
      if index + 1 < end &&
        find_pattern_excludes_protected_source(
          argv[index + 1],
          case_insensitive=find_filter_option_case_insensitive(arg),
        ) {
        return true
      }
      index += 2
      continue
    }
    index += 1
  }
  false
}

///|
fn find_has_source_name_or_path_filter_before(
  argv : Array[String],
  arg_start : Int,
  end : Int,
) -> Bool {
  find_source_filter_before(argv, arg_start, end, accept_any=false)
}

///|
fn find_source_filter_before(
  argv : Array[String],
  arg_start : Int,
  end : Int,
  accept_any~ : Bool,
) -> Bool {
  let mut index = arg_start
  while index < end {
    let arg = argv[index]
    if find_filter_option_takes_pattern(arg) {
      if accept_any {
        return true
      }
      if index + 1 < end &&
        find_pattern_mentions_protected_source(
          argv[index + 1],
          case_insensitive=find_filter_option_case_insensitive(arg),
        ) {
        return true
      }
      index += 2
      continue
    }
    index += 1
  }
  false
}

///|
fn find_filter_option_takes_pattern(arg : String) -> Bool {
  arg == "-name" ||
  arg == "-iname" ||
  arg == "-path" ||
  arg == "-ipath" ||
  arg == "-wholename" ||
  arg == "-iwholename"
}

///|
fn find_filter_option_case_insensitive(arg : String) -> Bool {
  arg == "-iname" || arg == "-ipath" || arg == "-iwholename"
}

///|
fn find_pattern_mentions_protected_source(
  pattern : String,
  case_insensitive~ : Bool,
) -> Bool {
  let pattern = if case_insensitive { pattern.to_lower() } else { pattern }
  pattern.contains(".mbt") ||
  pattern.contains(".mbti") ||
  pattern.contains("moon.mod") ||
  pattern.contains("moon.pkg") ||
  pattern.contains("moon.work")
}

///|
fn find_pattern_excludes_protected_source(
  pattern : String,
  case_insensitive~ : Bool,
) -> Bool {
  let pattern = if case_insensitive { pattern.to_lower() } else { pattern }
  let base = @workspace_path.path_basename(pattern)
  match find_glob_literal_suffix(base) {
    Some(suffix) if suffix != "" => !protected_source_suffix_can_match(suffix)
    _ => false
  }
}

///|
fn find_glob_literal_suffix(pattern : String) -> String? {
  let mut suffix_start = 0
  let mut in_bracket = false
  for index, ch in pattern {
    if in_bracket {
      if ch == ']' {
        in_bracket = false
        suffix_start = index + 1
      }
    } else {
      match ch {
        '*' | '?' => suffix_start = index + 1
        '[' => {
          in_bracket = true
          suffix_start = index + 1
        }
        _ => ()
      }
    }
  }
  if in_bracket {
    None
  } else {
    Some(pattern[suffix_start:].to_owned())
  }
}

///|
fn protected_source_suffix_can_match(suffix : String) -> Bool {
  [
    "main.mbt", "main.mbti", "README.mbt.md", "moon.mod", "moon.pkg", "moon.mod.json",
    "moon.pkg.json", "moon.work",
  ].any(source => source.has_suffix(suffix))
}

///|
fn scan_sed_args_for_in_place(
  argv : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut index = start
  while index < end {
    let arg = argv[index]
    if arg == "--" {
      return false
    }
    if is_sed_in_place_flag(arg) {
      return true
    }
    index += if sed_option_consumes_next(arg) { 2 } else { 1 }
  }
  false
}

///|
fn sed_targets_only_find_results(
  argv : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut index = start
  let mut script_seen = false
  let mut placeholder_seen = false
  while index < end {
    let arg = argv[index]
    if arg == "--" {
      index += 1
      continue
    }
    if arg == "+" {
      break
    }
    if sed_in_place_flag_consumes_empty_suffix(argv, index, end) {
      index += 2
      continue
    }
    if sed_option_consumes_next(arg) {
      if sed_option_supplies_script(arg) {
        script_seen = true
      }
      index += 2
      continue
    }
    if sed_option_supplies_script(arg) {
      script_seen = true
      index += 1
      continue
    }
    if is_sed_in_place_flag(arg) || sed_readonly_option(arg) {
      index += 1
      continue
    }
    if !script_seen {
      script_seen = true
      index += 1
      continue
    }
    if arg == "{}" {
      placeholder_seen = true
    } else if find_pattern_mentions_protected_source(
        arg,
        case_insensitive=false,
      ) ||
      @source_write_policy.is_protected_source_path(arg) {
      return false
    } else {
      return false
    }
    index += 1
  }
  placeholder_seen
}

///|
fn sed_in_place_flag_consumes_empty_suffix(
  argv : Array[String],
  index : Int,
  end : Int,
) -> Bool {
  index + 1 < end && argv[index] == "-i" && argv[index + 1] == ""
}

///|
fn sed_option_supplies_script(arg : String) -> Bool {
  if arg == "--expression" ||
    arg == "--file" ||
    arg.has_prefix("--expression=") ||
    arg.has_prefix("--file=") {
    return true
  }
  guard arg.strip_prefix("-") is Some(options) &&
    !options.has_prefix("-") &&
    !options.is_empty() else {
    return false
  }
  for ch in options {
    match ch {
      'e' | 'f' => return true
      'i' => return false
      _ => ()
    }
  }
  false
}

///|
fn sed_readonly_option(arg : String) -> Bool {
  guard arg.strip_prefix("-") is Some(options) &&
    !options.has_prefix("-") &&
    !options.is_empty() else {
    return false
  }
  for ch in options {
    match ch {
      'n' | 'E' | 'r' | 's' | 'u' | 'l' => ()
      _ => return false
    }
  }
  true
}

///|
fn sed_option_consumes_next(arg : String) -> Bool {
  if arg == "--expression" || arg == "--file" {
    return true
  }
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  let chars = [ for ch in arg => ch ]
  let mut idx = 1
  while idx < chars.length() {
    match chars[idx] {
      'e' | 'f' => return idx == chars.length() - 1
      'i' => return false
      _ => idx += 1
    }
  }
  false
}

///|
fn is_sed_in_place_flag(arg : String) -> Bool {
  if arg == "--in-place" || arg.has_prefix("--in-place=") {
    return true
  }
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  let mut first = true
  for ch in arg {
    if first {
      first = false
      continue
    }
    match ch {
      'i' => return true
      'e' | 'f' => return false
      _ => ()
    }
  }
  false
}

///|
fn awk_program_text(argv : Array[String], arg_start : Int) -> String? {
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--" {
      if index + 1 < argv.length() {
        return Some(argv[index + 1])
      }
      return None
    }
    if awk_option_is_inline_program(arg) {
      if index + 1 < argv.length() {
        return Some(argv[index + 1])
      }
      return None
    }
    match awk_attached_inline_program(arg) {
      Some(program) => return Some(program)
      None => ()
    }
    if awk_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      index += 2
      continue
    }
    if awk_attached_value_option(arg) {
      index += 1
      continue
    }
    if arg.has_prefix("-") && arg != "-" {
      index += 1
      continue
    }
    return Some(arg)
  }
  None
}

///|
fn awk_option_is_inline_program(arg : String) -> Bool {
  arg == "-e" || arg == "--source"
}

///|
fn awk_attached_inline_program(arg : String) -> String? {
  if arg.strip_prefix("--source=") is Some(program) {
    Some(program.to_owned())
  } else {
    None
  }
}

///|
fn awk_option_consumes_next(arg : String) -> Bool {
  arg == "-F" ||
  arg == "-v" ||
  arg == "-f" ||
  arg == "-i" ||
  arg == "-l" ||
  arg == "--field-separator" ||
  arg == "--assign" ||
  arg == "--file" ||
  arg == "--include" ||
  arg == "--load"
}

///|
fn awk_attached_value_option(arg : String) -> Bool {
  (
    arg.length() > 2 &&
    (
      arg.has_prefix("-F") ||
      arg.has_prefix("-v") ||
      arg.has_prefix("-f") ||
      arg.has_prefix("-i") ||
      arg.has_prefix("-l")
    )
  ) ||
  arg.has_prefix("--field-separator=") ||
  arg.has_prefix("--assign=") ||
  arg.has_prefix("--file=") ||
  arg.has_prefix("--include=") ||
  arg.has_prefix("--load=")
}

///|
fn awk_output_redirect_target(
  program : String,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let cwd = @path.Path(cwd).normalize().to_string()
  let mut quote : Char? = None
  let mut escaped = false
  let mut index = 0
  while index < program.length() {
    match program.get_char(index) {
      Some(ch) =>
        match quote {
          None =>
            if ch == '"' || ch == '\'' {
              quote = Some(ch)
              escaped = false
            } else if ch == '>' {
              match awk_redirect_literal_target(program, index, root, cwd) {
                Some(target) => return Some(target)
                None => ()
              }
            }
          Some(end_quote) =>
            if escaped {
              escaped = false
            } else if ch == '\\' {
              escaped = true
            } else if ch == end_quote {
              quote = None
            }
        }
      None => ()
    }
    index += 1
  }
  None
}

///|
fn awk_redirect_literal_target(
  program : String,
  operator_index : Int,
  root : String,
  cwd : String,
) -> String? {
  let mut index = operator_index + 1
  if index < program.length() && program.get_char(index) is Some('>') {
    index += 1
  }
  while index < program.length() {
    match program.get_char(index) {
      Some(ch) if ch == ' ' || ch == '\t' => index += 1
      _ => break
    }
  }
  if index >= program.length() {
    return None
  }
  let quote = match program.get_char(index) {
    Some(ch) => ch
    None => return None
  }
  if quote != '"' && quote != '\'' {
    return None
  }
  match collect_quoted_literal_from(program, index, quote) {
    Some(literal) => {
      let target = resolve_source_write_redirect_target(cwd, literal)
      if @source_write_policy.is_protected_workspace_source_path(root, target) {
        Some(target)
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn collect_quoted_literal_from(
  text : String,
  start : Int,
  quote : Char,
) -> String? {
  let literal = StringBuilder()
  let mut escaped = false
  let mut index = start + 1
  while index < text.length() {
    match text.get_char(index) {
      Some(ch) =>
        if escaped {
          literal.write_char(ch)
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == quote {
          return Some(literal.to_string())
        } else {
          literal.write_char(ch)
        }
      None => ()
    }
    index += 1
  }
  None
}

///|
async fn script_generated_tree_transfer_target(
  text : String,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  if !script_text_mentions_tree_transfer(text) {
    return None
  }
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let cwd = @path.Path(cwd).normalize().to_string()
  for marker in script_tree_transfer_markers() {
    let mut offset = 0
    while offset < text.length() {
      match text[offset:].find(marker) {
        Some(found) => {
          let start = offset + found
          match
            script_generated_tree_transfer_call_target(
              text[start:].to_owned(),
              root,
              cwd,
            ) {
            Some(target) => return Some(target)
            None => ()
          }
          match
            script_generated_tree_transfer_literal_pair_target(text, root, cwd) {
            Some(target) => return Some(target)
            None => ()
          }
          offset = start + marker.length()
        }
        None => break
      }
    }
  }
  None
}

///|
async fn script_generated_tree_transfer_literal_pair_target(
  text : String,
  root : String,
  cwd : String,
) -> String? {
  let literals = script_quoted_literals(text)
  for source_index, source_literal in literals {
    for dest_index, dest_literal in literals {
      if source_index != dest_index {
        let source = resolve_source_write_redirect_target(cwd, source_literal)
        let dest = resolve_source_write_redirect_target(cwd, dest_literal)
        if script_generated_tree_transfer_literal_pair_can_create_workspace_source(
            root, source, dest,
          ) {
          return Some(dest)
        }
      }
    }
  }
  None
}

///|
async fn script_generated_tree_transfer_literal_pair_can_create_workspace_source(
  root : String,
  source : String,
  dest : String,
) -> Bool {
  if !script_generated_tree_transfer_can_create_workspace_source(
      root, source, dest,
    ) {
    return false
  }
  @source_write_policy.is_protected_source_path(source) ||
  @source_write_policy.is_protected_source_path(dest) ||
  (
    !looks_like_non_source_file_path(source) &&
    !looks_like_non_source_file_path(dest)
  )
}

///|
async fn script_generated_tree_transfer_call_target(
  text : String,
  root : String,
  cwd : String,
) -> String? {
  let literals = script_quoted_literals(text)
  if literals.length() < 2 {
    return None
  }
  let source = resolve_source_write_redirect_target(cwd, literals[0])
  let dest = resolve_source_write_redirect_target(cwd, literals[1])
  if script_generated_tree_transfer_can_create_workspace_source(
      root, source, dest,
    ) {
    Some(dest)
  } else {
    None
  }
}

///|
async fn script_generated_tree_transfer_can_create_workspace_source(
  root : String,
  source : String,
  dest : String,
) -> Bool {
  let source = @path.Path(source).normalize().to_string()
  let dest = @path.Path(dest).normalize().to_string()
  if !@workspace_path.is_under_workspace_root(root, dest) ||
    @source_write_policy.is_moon_managed_workspace_path(root, dest) {
    return false
  }
  if !@workspace_path.is_under_workspace_root(root, source) {
    return source_path_or_tree_contains_protected_source(source)
  }
  if !@source_write_policy.is_moon_managed_workspace_path(root, source) {
    return source_path_or_tree_contains_protected_source(source)
  }
  !(looks_like_non_source_file_path(source) &&
  looks_like_non_source_file_path(dest))
}

///|
fn script_source_literal_preblock_target(
  text : String,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let cwd = @path.Path(cwd).normalize().to_string()
  let mut saw_source_literal = false
  let mut saw_workspace_source_literal = false
  let mut saw_absolute_outside_source_literal = false
  for literal in script_quoted_literals(text) {
    if script_text_mentions_source_path(literal) {
      saw_source_literal = true
      let target = resolve_source_write_redirect_target(cwd, literal)
      if @source_write_policy.is_protected_workspace_source_path(root, target) {
        return Some(target)
      }
      if @workspace_path.is_under_workspace_root(root, target) {
        saw_workspace_source_literal = true
      } else if @path.Path(literal).is_absolute() {
        saw_absolute_outside_source_literal = true
      }
    }
  }
  if saw_workspace_source_literal {
    Some(cwd)
  } else if saw_source_literal && saw_absolute_outside_source_literal {
    None
  } else if @workspace_path.is_under_workspace_root(root, cwd) {
    Some(cwd)
  } else {
    None
  }
}

///|
fn script_quoted_literals(text : String) -> Array[String] {
  let literals : Array[String] = []
  let mut quote : Char? = None
  let mut escaped = false
  let mut literal = StringBuilder()
  for ch in text {
    match quote {
      None =>
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          escaped = false
          literal = StringBuilder()
        }
      Some(end_quote) =>
        if escaped {
          literal.write_char(ch)
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == end_quote {
          literals.push(literal.to_string())
          quote = None
        } else {
          literal.write_char(ch)
        }
    }
  }
  literals
}

///|
fn command_tail_text(argv : Array[String], start : Int) -> String {
  let text = StringBuilder()
  for index in start..<argv.length() {
    if index > start {
      text.write_char(' ')
    }
    text.write_string(argv[index])
  }
  text.to_string()
}

///|
fn script_text_mentions_source_path(text : String) -> Bool {
  text.contains(".mbt") ||
  text.contains(".mbti") ||
  text.contains("moon.mod") ||
  text.contains("moon.pkg") ||
  text.contains("moon.work")
}

///|
fn script_text_mentions_generated_tree_path(text : String) -> Bool {
  text.contains("_build") || text.contains(".mooncakes")
}

///|
fn script_text_mentions_write_or_move(text : String) -> Bool {
  script_text_mentions_non_stdio_write_method(text) ||
  text.contains("write_text") ||
  text.contains("write_bytes") ||
  text.contains("writeFile") ||
  text.contains("appendFile") ||
  text.contains("createWriteStream") ||
  text.contains("copyFile") ||
  text.contains("cpSync") ||
  text.contains("renameSync") ||
  text.contains("fs.rename") ||
  text.contains("fs.promises.rename") ||
  text.contains("rmSync") ||
  script_text_mentions_open_write_mode(text) ||
  text.contains("os.remove(") ||
  text.contains("os.unlink(") ||
  text.contains(".unlink(") ||
  text.contains("fs.unlink") ||
  text.contains("fs.rm") ||
  text.contains("os.rename(") ||
  text.contains("os.replace(") ||
  text.contains("rename(") ||
  text.contains("shutil.copy") ||
  text.contains("shutil.move") ||
  text.contains("shutil.copytree") ||
  text.contains("copytree(")
}

///|
fn script_text_mentions_open_write_mode(text : String) -> Bool {
  let marker = "open("
  let mut offset = 0
  while offset < text.length() {
    match text[offset:].find(marker) {
      Some(relative_index) => {
        let args_start = offset + relative_index + marker.length()
        let tail = text[args_start:]
        let args_end = match tail.find(")") {
          Some(relative_end) => args_start + relative_end
          None => text.length()
        }
        let args = text[args_start:args_end]
        if [
            "\"w\"", "'w'", "\"wb\"", "'wb'", "\"w+\"", "'w+'", "\"wb+\"", "'wb+'",
            "\"w+b\"", "'w+b'", "\"a\"", "'a'", "\"ab\"", "'ab'", "\"a+\"", "'a+'",
            "\"ab+\"", "'ab+'", "\"a+b\"", "'a+b'", "\"x\"", "'x'", "\"xb\"", "'xb'",
            "\"x+\"", "'x+'", "\"xb+\"", "'xb+'", "\"x+b\"", "'x+b'", "\"r+\"", "'r+'",
            "\"rb+\"", "'rb+'", "\"r+b\"", "'r+b'",
          ].any(mode => args.contains(mode)) {
          return true
        }
        offset = args_start
      }
      None => return false
    }
  }
  false
}

///|
fn script_text_mentions_non_stdio_write_method(text : String) -> Bool {
  let marker = ".write("
  let mut offset = 0
  while offset < text.length() {
    match text[offset:].find(marker) {
      Some(relative_index) => {
        let index = offset + relative_index
        if !write_method_receiver_is_stdio(text, index) {
          return true
        }
        offset = index + marker.length()
      }
      None => return false
    }
  }
  false
}

///|
fn write_method_receiver_is_stdio(text : String, write_dot_index : Int) -> Bool {
  let start = if write_dot_index > 64 { write_dot_index - 64 } else { 0 }
  let receiver = text[start:write_dot_index]
    .replace_all(old=" ", new="")
    .replace_all(old="\t", new="")
  receiver.has_suffix("stdout") ||
  receiver.has_suffix("stderr") ||
  receiver.has_suffix("sys.stdout") ||
  receiver.has_suffix("sys.stderr") ||
  receiver.has_suffix("sys.stdout.buffer") ||
  receiver.has_suffix("sys.stderr.buffer") ||
  receiver.has_suffix("process.stdout") ||
  receiver.has_suffix("process.stderr") ||
  receiver.has_suffix("STDOUT") ||
  receiver.has_suffix("STDERR")
}

///|
fn script_text_mentions_tree_transfer(text : String) -> Bool {
  script_tree_transfer_markers().any(marker => text.contains(marker))
}

///|
fn script_tree_transfer_markers() -> Array[String] {
  [
    "fs.promises.rename", "fs.rename", "renameSync", "cpSync", "fs.cp", "os.rename(",
    "os.replace(", "shutil.move", "shutil.copy(", "shutil.copytree", "copytree(",
    "rename(",
  ]
}

///|
fn command_basename(name : String) -> String {
  let normalized = name.replace_all(old="\\", new="/")
  match normalized.rev_find("/") {
    Some(slash) => normalized[slash + 1:].to_owned()
    None => name
  }
}

///|
priv struct MvOperands {
  sources : Array[String]
  dest : String?
}

///|
async fn source_tree_mv_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard parse_mv_operands(argv, arg_start) is Some(operands) else {
    return None
  }
  source_tree_move_target(operands, real_workspace_root, cwd, predicted_dirs)
}

///|
async fn source_tree_move_target(
  operands : MvOperands,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  let dest_target = operands.dest.map(dest => {
    resolve_source_write_redirect_target(cwd, dest)
  })
  for source in operands.sources {
    let target = resolve_source_write_redirect_target(cwd, source)
    if protected_workspace_source_or_tree_path(real_workspace_root, target) {
      return Some(target)
    }
    match dest_target {
      Some(dest) => {
        let source_contains_protected = source_path_or_tree_contains_protected_source(
          target,
        )
        if move_destination_can_create_workspace_source(
            real_workspace_root,
            dest,
            target,
            source_contains_protected~,
            predicted_dirs~,
          ) {
          return Some(dest)
        }
      }
      None => ()
    }
  }
  match dest_target {
    Some(target) =>
      if @source_write_policy.is_protected_workspace_source_path(
          real_workspace_root, target,
        ) {
        Some(target)
      } else {
        None
      }
    None => None
  }
}

///|
async fn source_path_or_tree_contains_protected_source(target : String) -> Bool {
  let target = @path.Path(target).normalize().to_string()
  if @source_write_policy.is_protected_source_path(target) {
    return true
  }
  let kind = @fs.kind(target, follow_symlink=false) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  match kind {
    Directory => directory_contains_protected_source_path(target)
    SymLink => {
      let resolved = @fs.realpath(target) catch {
        error if @async.is_being_cancelled() => raise error
        _ => return false
      }
      source_path_or_tree_contains_protected_source(resolved)
    }
    _ => false
  }
}

///|
async fn directory_contains_protected_source_path(dir : String) -> Bool {
  let entries = @fs.readdir(dir, include_hidden=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  for entry in entries {
    let child = @path.Path(dir).join(Path(entry)).normalize().to_string()
    if @source_write_policy.is_protected_source_path(child) {
      return true
    }
    let kind = @fs.kind(child, follow_symlink=false) catch {
      error if @async.is_being_cancelled() => raise error
      _ => continue
    }
    match kind {
      Directory =>
        if directory_contains_protected_source_path(child) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
async fn move_destination_can_create_workspace_source(
  real_workspace_root : String,
  dest : String,
  source : String,
  source_contains_protected~ : Bool,
  predicted_dirs~ : Array[String],
) -> Bool {
  if @source_write_policy.is_protected_workspace_source_path(
      real_workspace_root, dest,
    ) {
    return true
  }
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let dest = @path.Path(dest).normalize().to_string()
  if !@workspace_path.is_under_workspace_root(root, dest) ||
    @source_write_policy.is_moon_managed_workspace_path(root, dest) {
    return false
  }
  let source_kind = @fs.kind(source, follow_symlink=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ =>
      return missing_move_source_can_create_workspace_source(
        root,
        dest,
        source,
        predicted_dirs~,
      )
  }
  let dest_is_directory = path_is_directory(dest) ||
    path_is_predicted_directory(dest, predicted_dirs)
  match source_kind {
    Directory => source_contains_protected
    _ => source_contains_protected && dest_is_directory
  }
}

///|
async fn missing_move_source_can_create_workspace_source(
  root : String,
  dest : String,
  source : String,
  predicted_dirs~ : Array[String],
) -> Bool {
  let dest_is_directory = path_is_directory(dest) ||
    path_is_predicted_directory(dest, predicted_dirs)
  let source = @path.Path(source).normalize().to_string()
  let final_dest = if dest_is_directory {
    @path.Path(dest)
    .join(Path(@workspace_path.path_basename(source)))
    .normalize()
    .to_string()
  } else {
    dest
  }
  if @source_write_policy.is_protected_workspace_source_path(root, final_dest) {
    return true
  }
  if dest_is_directory &&
    @workspace_path.is_under_workspace_root(root, source) &&
    @source_write_policy.is_moon_managed_workspace_path(root, source) {
    return true
  }
  if path_is_predicted_directory(source, predicted_dirs) {
    return true
  }
  !(looks_like_non_source_file_path(source) &&
  looks_like_non_source_file_path(final_dest))
}

///|
fn looks_like_non_source_file_path(path : String) -> Bool {
  let base = @workspace_path.path_basename(path)
  match base.rev_find(".") {
    Some(dot) if dot + 1 < base.length() =>
      !@source_write_policy.is_protected_source_path(base) &&
      looks_like_file_extension(base[dot + 1:].to_owned())
    _ => false
  }
}

///|
fn looks_like_file_extension(ext : String) -> Bool {
  for ch in ext {
    if !(ch is ('a'..='z') || ch is ('A'..='Z')) {
      return false
    }
  }
  ext.length() > 0
}

///|
async fn path_is_directory(path : String) -> Bool {
  let kind = @fs.kind(path, follow_symlink=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  kind == Directory
}

///|
fn path_is_predicted_directory(
  path : String,
  predicted_dirs : Array[String],
) -> Bool {
  let normalized = normalized_directory_path(path)
  predicted_dirs.any(dir => dir == normalized)
}

///|
fn push_unique_normalized_path(paths : Array[String], path : String) -> Unit {
  let normalized = normalized_directory_path(path)
  if !paths.any(existing => existing == normalized) {
    paths.push(normalized)
  }
}

///|
fn normalized_directory_path(path : String) -> String {
  strip_trailing_slash(@path.Path(path).normalize().to_string())
}

///|
fn parse_mkdir_dirs(
  argv : Array[String],
  arg_start : Int,
  cwd : String,
) -> Array[String]? {
  let dirs : Array[String] = []
  let mut index = arg_start
  let mut scanning_options = true
  while index < argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && mkdir_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      index += 2
      continue
    }
    if scanning_options &&
      (mkdir_attached_value_option(arg) || mkdir_supported_no_arg_option(arg)) {
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      return None
    }
    dirs.push(resolve_source_write_redirect_target(cwd, arg))
    index += 1
  }
  Some(dirs)
}

///|
fn mkdir_option_consumes_next(arg : String) -> Bool {
  arg == "-m" || arg == "--mode" || arg == "-Z" || arg == "--context"
}

///|
fn mkdir_attached_value_option(arg : String) -> Bool {
  if arg.has_prefix("--mode=") || arg.has_prefix("--context=") {
    return true
  }
  guard arg.strip_prefix("-") is Some(options) &&
    !options.has_prefix("-") &&
    options.length() > 1 else {
    return false
  }
  for index, ch in options {
    if ch == 'm' || ch == 'Z' {
      return index + 1 < options.length()
    }
  }
  false
}

///|
fn mkdir_supported_no_arg_option(arg : String) -> Bool {
  if arg == "-" {
    return false
  }
  match arg {
    "--parents" | "--verbose" => return true
    _ => ()
  }
  guard arg.strip_prefix("-") is Some(options) && !options.has_prefix("-") else {
    return false
  }
  for ch in options {
    match ch {
      'p' | 'v' => ()
      _ => return false
    }
  }
  true
}

///|
fn parse_mv_operands(argv : Array[String], arg_start : Int) -> MvOperands? {
  let operands : Array[String] = []
  let mut index = arg_start
  let mut target_directory : String? = None
  let mut scanning_options = true
  while index < argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && mv_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      if arg == "-t" || arg == "--target-directory" {
        target_directory = Some(argv[index + 1])
      }
      index += 2
      continue
    }
    if scanning_options {
      match mv_attached_target_directory_option(arg) {
        Some(dest) => {
          target_directory = Some(dest)
          index += 1
          continue
        }
        None => ()
      }
    }
    if scanning_options && mv_supported_no_arg_option(arg) {
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      return None
    }
    operands.push(arg)
    index += 1
  }
  operands_with_optional_dest(operands, target_directory)
}

///|
fn mv_option_consumes_next(arg : String) -> Bool {
  arg == "-t" || arg == "--target-directory" || arg == "-S" || arg == "--suffix"
}

///|
fn mv_attached_target_directory_option(arg : String) -> String? {
  if arg.strip_prefix("-t") is Some(target) && !target.is_empty() {
    Some(target.to_owned())
  } else if arg.strip_prefix("--target-directory=") is Some(target) {
    Some(target.to_owned())
  } else {
    None
  }
}

///|
fn mv_supported_no_arg_option(arg : String) -> Bool {
  if arg == "-" {
    return false
  }
  if arg.has_prefix("--backup") || arg.has_prefix("--suffix=") {
    return true
  }
  match arg {
    "--debug"
    | "--exchange"
    | "--force"
    | "--interactive"
    | "--no-clobber"
    | "--no-copy"
    | "--no-target-directory"
    | "--strip-trailing-slashes"
    | "--update"
    | "--verbose" => return true
    _ => ()
  }
  guard arg.strip_prefix("-") is Some(options) && !options.has_prefix("-") else {
    return false
  }
  for ch in options {
    match ch {
      'b' | 'f' | 'i' | 'n' | 'v' | 'T' | 'u' | 'Z' => ()
      _ => return false
    }
  }
  true
}

///|
async fn source_tree_cp_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard parse_cp_operands(argv, arg_start) is Some(operands) else {
    return None
  }
  source_tree_copy_destination_target(
    operands, real_workspace_root, cwd, predicted_dirs,
  )
}

///|
async fn source_tree_copy_destination_target(
  operands : MvOperands,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  let dest_target = operands.dest.map(dest => {
    resolve_source_write_redirect_target(cwd, dest)
  })
  match dest_target {
    Some(dest) =>
      match
        existing_path_resolves_to_protected_workspace_source(
          real_workspace_root, dest,
        ) {
        Some(resolved) => return Some(resolved)
        None => ()
      }
    None => ()
  }
  for source in operands.sources {
    match dest_target {
      Some(dest) => {
        let source_target = resolve_source_write_redirect_target(cwd, source)
        let source_contains_protected = source_path_or_tree_contains_protected_source(
          source_target,
        )
        if move_destination_can_create_workspace_source(
            real_workspace_root,
            dest,
            source_target,
            source_contains_protected~,
            predicted_dirs~,
          ) {
          return Some(dest)
        }
      }
      None => ()
    }
  }
  match dest_target {
    Some(target) =>
      if @source_write_policy.is_protected_workspace_source_path(
          real_workspace_root, target,
        ) {
        Some(target)
      } else {
        None
      }
    None => None
  }
}

///|
fn parse_cp_operands(argv : Array[String], arg_start : Int) -> MvOperands? {
  let operands : Array[String] = []
  let mut index = arg_start
  let mut target_directory : String? = None
  let mut scanning_options = true
  while index < argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && cp_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      if arg == "-t" || arg == "--target-directory" {
        target_directory = Some(argv[index + 1])
      }
      index += 2
      continue
    }
    if scanning_options {
      match cp_attached_target_directory_option(arg) {
        Some(dest) => {
          target_directory = Some(dest)
          index += 1
          continue
        }
        None => ()
      }
    }
    if scanning_options && cp_supported_no_arg_option(arg) {
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      return None
    }
    operands.push(arg)
    index += 1
  }
  operands_with_optional_dest(operands, target_directory)
}

///|
fn cp_option_consumes_next(arg : String) -> Bool {
  arg == "-t" || arg == "--target-directory" || arg == "-S" || arg == "--suffix"
}

///|
fn cp_attached_target_directory_option(arg : String) -> String? {
  if arg.strip_prefix("-t") is Some(target) && !target.is_empty() {
    Some(target.to_owned())
  } else if arg.strip_prefix("--target-directory=") is Some(target) {
    Some(target.to_owned())
  } else {
    None
  }
}

///|
fn cp_supported_no_arg_option(arg : String) -> Bool {
  if arg == "-" {
    return false
  }
  if arg.has_prefix("--backup") ||
    arg.has_prefix("--preserve") ||
    arg.has_prefix("--reflink") ||
    arg.has_prefix("--sparse") ||
    arg.has_prefix("--suffix=") ||
    arg.has_prefix("--context") {
    return true
  }
  match arg {
    "--archive"
    | "--recursive"
    | "--force"
    | "--interactive"
    | "--no-clobber"
    | "--verbose"
    | "--dereference"
    | "--no-dereference"
    | "--parents"
    | "--remove-destination"
    | "--strip-trailing-slashes"
    | "--update"
    | "--link"
    | "--symbolic-link"
    | "--one-file-system" => return true
    _ => ()
  }
  guard arg.strip_prefix("-") is Some(options) && !options.has_prefix("-") else {
    return false
  }
  for ch in options {
    match ch {
      'R'
      | 'r'
      | 'a'
      | 'p'
      | 'f'
      | 'i'
      | 'n'
      | 'v'
      | 'L'
      | 'P'
      | 'H'
      | 'T'
      | 'u'
      | 'l'
      | 's'
      | 'x'
      | 'd' => ()
      _ => return false
    }
  }
  true
}

///|
async fn source_tree_install_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
  predicted_dirs : Array[String],
) -> String? {
  guard parse_install_operands(argv, arg_start) is Some(operands) else {
    return None
  }
  if operands.directory_mode {
    for operand in operands.sources {
      let target = resolve_source_write_redirect_target(cwd, operand)
      if protected_workspace_source_or_tree_path(real_workspace_root, target) {
        return Some(target)
      }
    }
    return None
  }
  source_tree_copy_destination_target(
    { sources: operands.sources, dest: operands.dest },
    real_workspace_root,
    cwd,
    predicted_dirs,
  )
}

///|
priv struct InstallOperands {
  sources : Array[String]
  dest : String?
  directory_mode : Bool
}

///|
fn parse_install_operands(
  argv : Array[String],
  arg_start : Int,
) -> InstallOperands? {
  let operands : Array[String] = []
  let mut index = arg_start
  let mut target_directory : String? = None
  let mut directory_mode = false
  let mut scanning_options = true
  while index < argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && (arg == "-d" || arg == "--directory") {
      directory_mode = true
      index += 1
      continue
    }
    if scanning_options && install_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      if install_short_cluster_has_directory_mode(arg) {
        directory_mode = true
      }
      if arg == "-t" || arg == "--target-directory" {
        target_directory = Some(argv[index + 1])
      }
      index += 2
      continue
    }
    if scanning_options {
      match install_attached_target_directory_option(arg) {
        Some(dest) => {
          target_directory = Some(dest)
          index += 1
          continue
        }
        None => ()
      }
      if install_attached_consuming_option(arg) {
        if install_short_cluster_has_directory_mode(arg) {
          directory_mode = true
        }
        index += 1
        continue
      }
    }
    if scanning_options && install_supported_no_arg_option(arg) {
      if arg.contains("d") {
        directory_mode = true
      }
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      return None
    }
    operands.push(arg)
    index += 1
  }
  if directory_mode {
    Some({ sources: operands, dest: None, directory_mode })
  } else {
    match operands_with_optional_dest(operands, target_directory) {
      Some(operands) =>
        Some({ sources: operands.sources, dest: operands.dest, directory_mode })
      None => None
    }
  }
}

///|
fn install_option_consumes_next(arg : String) -> Bool {
  arg == "-g" ||
  arg == "--group" ||
  arg == "-m" ||
  arg == "--mode" ||
  arg == "-o" ||
  arg == "--owner" ||
  arg == "-S" ||
  arg == "--suffix" ||
  arg == "-t" ||
  arg == "--target-directory" ||
  install_short_cluster_ends_with_consuming_option(arg)
}

///|
fn install_attached_target_directory_option(arg : String) -> String? {
  if arg.strip_prefix("-t") is Some(target) && !target.is_empty() {
    Some(target.to_owned())
  } else if arg.strip_prefix("--target-directory=") is Some(target) {
    Some(target.to_owned())
  } else {
    None
  }
}

///|
fn install_attached_consuming_option(arg : String) -> Bool {
  arg.has_prefix("--group=") ||
  arg.has_prefix("--mode=") ||
  arg.has_prefix("--owner=") ||
  arg.has_prefix("--suffix=") ||
  install_short_cluster_has_attached_consuming_option(arg)
}

///|
fn install_short_cluster_has_directory_mode(arg : String) -> Bool {
  install_short_option_cluster_has(arg, 'd')
}

///|
fn install_short_cluster_has_attached_consuming_option(arg : String) -> Bool {
  match install_short_cluster_consuming_option_index(arg) {
    Some(index) => index + 1 < arg.length()
    None => false
  }
}

///|
fn install_short_cluster_ends_with_consuming_option(arg : String) -> Bool {
  match install_short_cluster_consuming_option_index(arg) {
    Some(index) => index + 1 == arg.length()
    None => false
  }
}

///|
fn install_short_cluster_consuming_option_index(arg : String) -> Int? {
  guard arg.strip_prefix("-") is Some(options) &&
    !options.has_prefix("-") &&
    options.length() > 1 else {
    return None
  }
  let mut index = 1
  for ch in options {
    match ch {
      'g' | 'm' | 'o' | 'S' => return Some(index)
      'C' | 'D' | 'd' | 'p' | 's' | 'v' => ()
      _ => return None
    }
    index += 1
  }
  None
}

///|
fn install_short_option_cluster_has(arg : String, needle : Char) -> Bool {
  guard arg.strip_prefix("-") is Some(options) && !options.has_prefix("-") else {
    return false
  }
  for ch in options {
    if ch == needle {
      return true
    }
  }
  false
}

///|
fn install_supported_no_arg_option(arg : String) -> Bool {
  if arg == "-" {
    return false
  }
  if arg.has_prefix("--backup") || arg.has_prefix("--suffix=") {
    return true
  }
  match arg {
    "--compare"
    | "--directory"
    | "--preserve-timestamps"
    | "--strip"
    | "--verbose" => return true
    _ => ()
  }
  guard arg.strip_prefix("-") is Some(options) && !options.has_prefix("-") else {
    return false
  }
  for ch in options {
    match ch {
      'C' | 'D' | 'd' | 'p' | 's' | 'v' => ()
      _ => return false
    }
  }
  true
}

///|
async fn source_tree_touch_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard parse_touch_operands(argv, arg_start)
    is Some((operands, follow_symlinks)) else {
    return None
  }
  for operand in operands {
    let target = resolve_source_write_redirect_target(cwd, operand)
    if @source_write_policy.is_protected_workspace_source_path(
        real_workspace_root, target,
      ) {
      return Some(target)
    }
    if follow_symlinks {
      match
        existing_path_resolves_to_protected_workspace_source(
          real_workspace_root, target,
        ) {
        Some(resolved) => return Some(resolved)
        None => ()
      }
    }
  }
  None
}

///|
fn parse_touch_operands(
  argv : Array[String],
  arg_start : Int,
) -> (Array[String], Bool)? {
  let operands : Array[String] = []
  let mut follow_symlinks = true
  let mut index = arg_start
  let mut scanning_options = true
  while index < argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && touch_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      index += 2
      continue
    }
    if scanning_options && touch_attached_consuming_option(arg) {
      index += 1
      continue
    }
    if scanning_options && touch_supported_no_arg_option(arg) {
      if arg == "--no-dereference" ||
        (arg.has_prefix("-") && !arg.has_prefix("--") && arg.contains("h")) {
        follow_symlinks = false
      }
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      return None
    }
    operands.push(arg)
    index += 1
  }
  Some((operands, follow_symlinks))
}

///|
fn touch_option_consumes_next(arg : String) -> Bool {
  arg == "-d" ||
  arg == "--date" ||
  arg == "-r" ||
  arg == "--reference" ||
  arg == "-t"
}

///|
fn touch_attached_consuming_option(arg : String) -> Bool {
  if arg.length() <= 2 {
    return false
  }
  arg.has_prefix("-d") ||
  arg.has_prefix("-r") ||
  arg.has_prefix("-t") ||
  arg.has_prefix("--date=") ||
  arg.has_prefix("--reference=") ||
  arg.has_prefix("--time=")
}

///|
fn touch_supported_no_arg_option(arg : String) -> Bool {
  match arg {
    "--no-create" | "--no-dereference" | "--help" | "--version" => return true
    _ => ()
  }
  guard arg.strip_prefix("-") is Some(options) &&
    !options.has_prefix("-") &&
    !options.is_empty() else {
    return false
  }
  for ch in options {
    match ch {
      'a' | 'c' | 'm' | 'h' | 'f' => ()
      _ => return false
    }
  }
  true
}

///|
async fn source_tree_tee_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard parse_tee_operands(argv, arg_start) is Some(operands) else {
    return None
  }
  for operand in operands {
    let target = resolve_source_write_redirect_target(cwd, operand)
    if @source_write_policy.is_protected_workspace_source_path(
        real_workspace_root, target,
      ) {
      return Some(target)
    }
    match
      existing_path_resolves_to_protected_workspace_source(
        real_workspace_root, target,
      ) {
      Some(resolved) => return Some(resolved)
      None => ()
    }
  }
  None
}

///|
fn parse_tee_operands(argv : Array[String], arg_start : Int) -> Array[String]? {
  let operands : Array[String] = []
  let mut scanning_options = true
  for index in arg_start..<argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      continue
    }
    if scanning_options && tee_supported_no_arg_option(arg) {
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      return None
    }
    operands.push(arg)
  }
  Some(operands)
}

///|
fn tee_supported_no_arg_option(arg : String) -> Bool {
  if arg == "-" {
    return false
  }
  if arg.has_prefix("--output-error") {
    return true
  }
  match arg {
    "--append" | "--ignore-interrupts" | "--help" | "--version" => return true
    _ => ()
  }
  guard arg.strip_prefix("-") is Some(options) && !options.has_prefix("-") else {
    return false
  }
  for ch in options {
    match ch {
      'a' | 'i' | 'p' => ()
      _ => return false
    }
  }
  true
}

///|
fn operands_with_optional_dest(
  operands : Array[String],
  target_directory : String?,
) -> MvOperands? {
  match target_directory {
    Some(dest) => Some({ sources: operands, dest: Some(dest) })
    None =>
      if operands.length() >= 2 {
        let sources = [
          for index in 0..<(operands.length() - 1) => operands[index]
        ]
        Some({ sources, dest: Some(operands[operands.length() - 1]) })
      } else {
        Some({ sources: [], dest: None })
      }
  }
}

///|
async fn source_tree_rm_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let operands = parse_rm_operands(argv, arg_start)
  for operand in operands {
    let target = resolve_source_write_redirect_target(cwd, operand)
    if protected_workspace_source_or_tree_path(real_workspace_root, target) {
      return Some(target)
    }
  }
  None
}

///|
fn parse_rm_operands(argv : Array[String], arg_start : Int) -> Array[String] {
  let operands : Array[String] = []
  let mut scanning_options = true
  for index in arg_start..<argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      continue
    }
    if scanning_options && arg.has_prefix("-") && arg != "-" {
      continue
    }
    operands.push(arg)
  }
  operands
}

///|
fn cwd_command_effect_for_detection(
  command : @shell_parse.SimpleCommand,
  cwd : String?,
) -> CwdCommandEffect {
  match cwd {
    Some(cwd) =>
      match cwd_command_effect(command, cwd) {
        UnknownCwd => static_relative_cd_command_effect(command, cwd)
        effect => effect
      }
    None => cwd_command_effect_from_unknown_base(command)
  }
}

///|
fn static_relative_cd_command_effect(
  command : @shell_parse.SimpleCommand,
  base_cwd : String,
) -> CwdCommandEffect {
  let argv = command.argv
  match command.command_index() {
    Some(command_index) if command_index < argv.length() &&
      argv[command_index] == "cd" =>
      if command.env.length() > 0 {
        UnknownCwd
      } else {
        static_relative_cd_target(argv, command_index + 1, base_cwd)
      }
    _ => UnknownCwd
  }
}

///|
fn static_relative_cd_target(
  argv : Array[String],
  arg_start : Int,
  base_cwd : String,
) -> CwdCommandEffect {
  let remaining = argv.length() - arg_start
  if remaining == 1 {
    known_static_cd_target(argv[arg_start], base_cwd)
  } else if remaining == 2 && argv[arg_start] == "--" {
    known_static_cd_target(argv[arg_start + 1], base_cwd)
  } else {
    UnknownCwd
  }
}

///|
fn known_static_cd_target(
  target : String,
  base_cwd : String,
) -> CwdCommandEffect {
  if target == "" || target == "--" || target.has_prefix("-") {
    UnknownCwd
  } else {
    KnownCwd(resolve_command_cwd(base_cwd, target))
  }
}

///|
fn cwd_command_effect_from_unknown_base(
  command : @shell_parse.SimpleCommand,
) -> CwdCommandEffect {
  let argv = command.argv
  if argv.length() > 0 && argv[0] == "env" {
    return NotCwdCommand
  }
  match command.command_index() {
    Some(command_index) if command_index < argv.length() =>
      match argv[command_index] {
        "cd" =>
          if command.env.length() > 0 {
            UnknownCwd
          } else {
            cd_command_effect_from_unknown_base(argv, command_index + 1)
          }
        "pushd" | "popd" => UnknownCwd
        _ => NotCwdCommand
      }
    _ => NotCwdCommand
  }
}

///|
fn cd_command_effect_from_unknown_base(
  argv : Array[String],
  arg_start : Int,
) -> CwdCommandEffect {
  let remaining = argv.length() - arg_start
  if remaining == 1 {
    known_absolute_cd_target(argv[arg_start])
  } else if remaining == 2 && argv[arg_start] == "--" {
    known_absolute_cd_target(argv[arg_start + 1])
  } else {
    UnknownCwd
  }
}

///|
fn known_absolute_cd_target(target : String) -> CwdCommandEffect {
  let target_path : @path.Path = target
  if target == "--" || target.has_prefix("-") || !target_path.is_absolute() {
    UnknownCwd
  } else {
    KnownCwd(target_path.normalize().to_string())
  }
}

///|
fn source_write_detection_cwd(
  real_workspace_root : String,
  cwd : String?,
) -> String {
  match cwd {
    Some(cwd) => {
      let cwd_path : @path.Path = cwd
      if cwd_path.is_absolute() {
        cwd_path.normalize().to_string()
      } else {
        @path.Path(real_workspace_root).join(cwd_path).normalize().to_string()
      }
    }
    None => real_workspace_root
  }
}

///|
fn resolve_source_write_redirect_target(
  cwd : String,
  target : String,
) -> String {
  let target_path : @path.Path = target
  if target_path.is_absolute() {
    target_path.normalize().to_string()
  } else {
    @path.Path(cwd).join(target_path).normalize().to_string()
  }
}

///|
async fn protected_workspace_source_or_tree_path(
  real_workspace_root : String,
  target : String,
) -> Bool {
  if @source_write_policy.is_protected_workspace_source_path(
      real_workspace_root, target,
    ) {
    return true
  }
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let target = @path.Path(target).normalize().to_string()
  if !@workspace_path.is_under_workspace_root(root, target) ||
    @source_write_policy.is_moon_managed_workspace_path(root, target) {
    return false
  }
  let kind = @fs.kind(target, follow_symlink=false) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  match kind {
    Directory => directory_contains_protected_workspace_source(root, target)
    _ => false
  }
}

///|
async fn directory_contains_protected_workspace_source(
  root : String,
  dir : String,
) -> Bool {
  let entries = @fs.readdir(dir, include_hidden=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  for entry in entries {
    let child = @path.Path(dir).join(Path(entry)).normalize().to_string()
    if @source_write_policy.is_protected_workspace_source_path(root, child) {
      return true
    }
    let kind = @fs.kind(child, follow_symlink=false) catch {
      error if @async.is_being_cancelled() => raise error
      _ => continue
    }
    match kind {
      Directory =>
        if directory_contains_protected_workspace_source(root, child) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
/// Refusal content for a source-write `operation` (e.g. "source tree
/// operation") blocked before the command is ever executed.
fn direct_source_blocked_content(operation : String, target : String) -> String {
  (
    $|shell sandbox: \{operation} is blocked before execution: \{target}
    $|\{SandboxSourceWriteFeedback}
    $|<system>exit=blocked</system>
  )
}

///|
fn append_shell_sandbox_feedback_if_needed(
  content : String,
  agent_output : AgentShellOutput,
) -> String {
  if agent_output_has_shell_sandbox_denial(agent_output) {
    insert_before_system_footer(content, SandboxSourceWriteFeedback)
  } else {
    content
  }
}

///|
fn agent_output_has_shell_sandbox_denial(
  agent_output : AgentShellOutput,
) -> Bool {
  agent_output.source_write_sandboxed &&
  @sandbox.source_write_denied_in_text(
    agent_output.output.text,
    agent_output.sandbox_denial_subjects,
  )
}

///|
/// The guidance appended when a shell command's output shows a sandboxed
/// source-write denial. Exposed for `shell_output`.
pub fn source_write_denial_feedback() -> String {
  SandboxSourceWriteFeedback
}
