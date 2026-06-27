///|
const SandboxExecPath : String = "/usr/bin/sandbox-exec"

///|
const SandboxSourceWriteFeedback : String = "shell sandbox: source file writes from shell are blocked. For compiler-feedback or mechanical code fixes, use line-anchored `edit` (or `multi_edit` for several fixes in one file) instead of shell-generated rewrites. Do not generate rewritten files in shell and then overwrite source files with another tool; keep `shell` for read-only analysis and validation commands."

///|
let source_write_profile_cache : Map[String, CachedSourceWriteProfile] = {}

///|
let sandbox_exec_available_cache : Ref[Bool?] = { val: None }

///|
priv struct WatchedSourceProfileDir {
  path : String
  mtime_s : Int64
  mtime_ns : Int
}

///|
priv struct SourceWriteProfileScan {
  literal_paths : Array[String]
  watched_dirs : Array[WatchedSourceProfileDir]
  cacheable : Bool
}

///|
priv struct SourceWriteProfileScanBuilder {
  literal_paths : Array[String]
  watched_dirs : Array[WatchedSourceProfileDir]
  mut cacheable : Bool
}

///|
priv struct CachedSourceWriteProfile {
  profile : String
  watched_dirs : Array[WatchedSourceProfileDir]
  denial_subjects : Array[String]
}

///|
priv struct SourceWriteProfileData {
  profile : String
  denial_subjects : Array[String]
}

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
async fn collect_agent_shell_output(
  workspace_root : String,
  cmd : String,
  parsed : @shell_parse.ParseResult,
  cwd? : String,
  max_output_chars~ : Int,
) -> AgentShellOutput {
  let launch = agent_shell_launch(workspace_root, cmd, parsed, cwd?)
  let output = collect_process_output(
    launch.program,
    launch.args,
    cwd?,
    max_output_chars~,
  )
  {
    output,
    source_write_sandboxed: launch.source_write_sandboxed,
    sandbox_denial_subjects: launch.sandbox_denial_subjects,
  }
}

///|
async fn agent_shell_launch(
  workspace_root : String,
  cmd : String,
  parsed : @shell_parse.ParseResult,
  cwd? : String,
) -> AgentShellLaunch {
  let real_workspace_root = @fs.realpath(workspace_root)
  let real_cwd = match cwd {
    Some(cwd) => Some(@fs.realpath(cwd) catch { _ => cwd })
    None => None
  }
  let mode = source_write_mode_for_parse(parsed, real_workspace_root, real_cwd)
  if mode is TrustedSourceWrite || !sandbox_exec_available() {
    return {
      program: PlatformShellProgram,
      args: platform_shell_args(cmd),
      source_write_sandboxed: false,
      sandbox_denial_subjects: [],
    }
  }
  let profile_data = source_write_readonly_profile_data(real_workspace_root)
  let args = ["-p", profile_data.profile, PlatformShellProgram]
  for arg in platform_shell_args(cmd) {
    args.push(arg)
  }
  {
    program: SandboxExecPath,
    args,
    source_write_sandboxed: true,
    sandbox_denial_subjects: profile_data.denial_subjects,
  }
}

///|
async fn sandbox_exec_available() -> Bool {
  match sandbox_exec_available_cache.val {
    Some(value) => value
    None => {
      let value = probe_sandbox_exec_available()
      sandbox_exec_available_cache.val = Some(value)
      value
    }
  }
}

///|
async fn probe_sandbox_exec_available() -> Bool {
  if !@fs.exists(SandboxExecPath) {
    return false
  }
  let probe_dir = @fs.tmpdir(prefix="openseek-sandbox-probe-") catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  let blocked_path = @path.Path(probe_dir)
    .join(Path("blocked"))
    .normalize()
    .to_string()
  let probe_profile = sandbox_denial_probe_profile(blocked_path)
  let args = ["-p", probe_profile, PlatformShellProgram]
  for arg in platform_shell_args(PlatformNoopCommand) {
    args.push(arg)
  }
  let output = collect_process_output(
    SandboxExecPath,
    args,
    max_output_chars=200,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      cleanup_sandbox_probe(probe_dir, blocked_path)
      return false
    }
  }
  if output.exit_code != Some(0) {
    cleanup_sandbox_probe(probe_dir, blocked_path)
    return false
  }
  let write_args = ["-p", probe_profile, PlatformShellProgram]
  for arg in platform_shell_args("printf probe > \{shell_quote(blocked_path)}") {
    write_args.push(arg)
  }
  let write_output = collect_process_output(
    SandboxExecPath,
    write_args,
    max_output_chars=400,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      cleanup_sandbox_probe(probe_dir, blocked_path)
      return false
    }
  }
  let denied = write_output.exit_code != Some(0) && !@fs.exists(blocked_path)
  cleanup_sandbox_probe(probe_dir, blocked_path)
  denied
}

///|
#cfg(platform="windows")
const PlatformNoopCommand : String = "exit 0"

///|
#cfg(not(platform="windows"))
const PlatformNoopCommand : String = ":"

///|
fn sandbox_denial_probe_profile(blocked_path : String) -> String {
  (
    $|(version 1)
    $|(allow default)
    $|(deny file-write* (literal "\{sbpl_string_escape(blocked_path)}"))
  )
}

///|
fn shell_quote(text : String) -> String {
  "'\{text.replace_all(old="'", new="'\\''")}'"
}

///|
async fn cleanup_sandbox_probe(
  probe_dir : String,
  blocked_path : String,
) -> Unit {
  ignore(@fs.remove(blocked_path) catch { _ => () })
  ignore(@fs.rmdir(probe_dir) catch { _ => () })
}

///|
async fn source_write_readonly_profile_data(
  real_workspace_root : String,
) -> SourceWriteProfileData {
  let real_workspace_root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  match source_write_profile_cache.get(real_workspace_root) {
    Some(cached) if cached_source_write_profile_valid(cached) =>
      return {
        profile: cached.profile,
        denial_subjects: cached.denial_subjects,
      }
    Some(_) => ()
    None => ()
  }
  let scan = protected_source_tree_profile_scan(real_workspace_root)
  let denial_subjects = source_write_denial_subjects(scan.literal_paths)
  let source_regex = source_write_regex(real_workspace_root)
  let build_carveout_regex = source_write_build_carveout_regex(
    real_workspace_root,
  )
  let profile = StringBuilder()
  profile.write_string("(version 1)\n")
  profile.write_string("(allow default)\n")
  // `file-write*` already covers `file-write-create`, so this single deny blocks
  // both rewriting existing source and creating new source files. SBPL is
  // last-match-wins, so the following carve-out re-allows Moon-managed build and
  // cache trees without the deny regex having to special-case them.
  profile.write_string(
    "(deny file-write* (regex \"\{sbpl_string_escape(source_regex)}\"))\n",
  )
  profile.write_string(
    "(allow file-write* (regex \"\{sbpl_string_escape(build_carveout_regex)}\"))\n",
  )
  for dir in scan.literal_paths {
    profile.write_string(
      "(deny file-write* (literal \"\{sbpl_string_escape(dir)}\"))\n",
    )
  }
  let profile = profile.to_string()
  if scan.cacheable {
    source_write_profile_cache[real_workspace_root] = {
      profile,
      watched_dirs: scan.watched_dirs,
      denial_subjects,
    }
  }
  { profile, denial_subjects }
}

///|
fn source_write_denial_subjects(literal_paths : Array[String]) -> Array[String] {
  let subjects : Array[String] = []
  for path in literal_paths {
    subjects.push(path)
    let base = path_basename(path)
    if base != path {
      subjects.push(base)
    }
  }
  subjects
}

///|
async fn cached_source_write_profile_valid(
  cached : CachedSourceWriteProfile,
) -> Bool {
  for watched in cached.watched_dirs {
    let (mtime_s, mtime_ns) = @fs.mtime(watched.path, follow_symlink=false) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return false
    }
    if mtime_s != watched.mtime_s || mtime_ns != watched.mtime_ns {
      return false
    }
  }
  true
}

///|
fn source_write_regex(real_workspace_root : String) -> String {
  let root = regex_escape(strip_trailing_slash(real_workspace_root))
  let source_file = "([^/]*(\\.mbt\\.md|\\.mbt|\\.mbti)|(moon\\.mod\\.json|moon\\.pkg\\.json|moon\\.mod|moon\\.pkg|moon\\.work))"
  "^" + root + "(/|$)(.*/)?\{source_file}$"
}

///|
/// Paths under a Moon-managed `_build` or `.mooncakes` directory, where Moon
/// itself writes generated `.mbt` sources. Emitted as an `allow` rule after the
/// source deny so the sandbox blocks hand-written source rewrites while leaving
/// Moon's own build/cache writes untouched. Mirrors the component names in
/// `is_moon_managed_workspace_path`.
fn source_write_build_carveout_regex(real_workspace_root : String) -> String {
  let root = regex_escape(strip_trailing_slash(real_workspace_root))
  "^" + root + "/(.*/)?(_build|\\.mooncakes)(/|$)"
}

///|
async fn protected_source_tree_profile_scan(
  real_workspace_root : String,
) -> SourceWriteProfileScan {
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let state : SourceWriteProfileScanBuilder = {
    literal_paths: [],
    watched_dirs: [],
    cacheable: true,
  }
  ignore(collect_protected_source_tree_profile_scan(root, root, state))
  {
    literal_paths: state.literal_paths,
    watched_dirs: state.watched_dirs,
    cacheable: state.cacheable,
  }
}

///|
async fn collect_protected_source_tree_profile_scan(
  root : String,
  dir : String,
  state : SourceWriteProfileScanBuilder,
) -> Bool {
  if dir != root && is_moon_managed_workspace_path(root, dir) {
    return false
  }
  if dir != root && should_prune_profile_scan_path(root, dir) {
    return false
  }
  let (mtime_s, mtime_ns) = @fs.mtime(dir, follow_symlink=false) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      state.cacheable = false
      return false
    }
  }
  state.watched_dirs.push({ path: dir, mtime_s, mtime_ns })
  let entries = @fs.readdir(dir, include_hidden=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      state.cacheable = false
      return false
    }
  }
  let mut contains_protected = false
  for entry in entries {
    let child = @path.Path(dir).join(Path(entry)).normalize().to_string()
    if is_moon_managed_workspace_path(root, child) {
      continue
    }
    if is_protected_workspace_source_path(root, child) {
      contains_protected = true
      continue
    }
    let kind = @fs.kind(child, follow_symlink=false) catch {
      error if @async.is_being_cancelled() => raise error
      _ => {
        state.cacheable = false
        continue
      }
    }
    match kind {
      Directory =>
        if collect_protected_source_tree_profile_scan(root, child, state) {
          contains_protected = true
        }
      _ => ()
    }
  }
  if contains_protected && dir != root {
    state.literal_paths.push(dir)
  }
  contains_protected
}

///|
fn should_prune_profile_scan_path(root : String, path : String) -> Bool {
  guard is_under_workspace_root(root, path) && path != root else {
    return false
  }
  let relative = path[root.length() + 1:].to_owned()
  relative
  .replace_all(old="\\", new="/")
  .split("/")
  .any(part => {
    part == ".git" ||
    part == ".hg" ||
    part == ".svn" ||
    part == ".jj" ||
    part == "node_modules"
  })
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
        _ => UntrustedCommand
      }
    _ => UntrustedCommand
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
    Some(invocation) if is_source_readonly_moon_subcommand(
        command.argv,
        invocation.subcommand_index,
      ) => TrustedCommandRead
    _ => UntrustedCommand
  }
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
fn redirect_writes_file(redirect : @shell_parse.Redirect) -> Bool {
  match strip_fd_prefix(redirect.op) {
    ">" | ">|" | ">>" | "<>" | "&>" | "&>>" => true
    ">&" => !is_fd_redirect_target(redirect.target)
    _ => false
  }
}

///|
fn strip_fd_prefix(op : String) -> String {
  let mut index = 0
  for ch in op {
    if ch is ('0'..='9') {
      index += 1
    } else {
      break
    }
  }
  op[index:].to_owned()
}

///|
fn is_fd_redirect_target(target : String) -> Bool {
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
          if is_protected_workspace_source_path(real_workspace_root, target) {
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
          if is_protected_workspace_source_path(real_workspace_root, target) {
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
  if is_protected_workspace_source_path(real_workspace_root, resolved) {
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
      let segment : Array[String] = []
      for segment_index in index..<end {
        segment.push(words[segment_index])
      }
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
          is_protected_workspace_source_path(
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
  for index in 0..<words.length() {
    if command_token_basename_is(words[index], "sed") &&
      command_text_is_command_position(words, index) {
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
fn command_text_mentions_unsafe_git_source_operation(text : String) -> Bool {
  let words = command_text_words(text)
  for index in 0..<words.length() {
    if command_token_basename_is(words[index], "git") &&
      command_text_is_command_position(words, index) {
      let segment_end = command_text_segment_end(words, index)
      match command_text_git_subcommand_index(words, index + 1, segment_end) {
        Some(subcommand_index) =>
          if command_text_git_subcommand_updates_source_tree(
              words, subcommand_index, segment_end,
            ) {
            return true
          }
        None => ()
      }
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
fn command_text_git_subcommand_index(
  words : Array[String],
  start : Int,
  end : Int,
) -> Int? {
  let mut index = start
  while index < end {
    let arg = words[index]
    if arg == "--help" || arg == "-h" {
      return None
    }
    if arg == "-C" ||
      arg == "--work-tree" ||
      git_global_option_consumes_next(arg) {
      index += 2
      continue
    }
    if git_attached_cwd_option(arg) is Some(_) ||
      git_attached_work_tree_option(arg) is Some(_) ||
      git_global_option_with_attached_value(arg) ||
      git_global_no_arg_option(arg) {
      index += 1
      continue
    }
    if arg.has_prefix("-") && arg != "-" {
      return None
    }
    return Some(index)
  }
  None
}

///|
fn command_text_git_subcommand_updates_source_tree(
  words : Array[String],
  subcommand_index : Int,
  segment_end : Int,
) -> Bool {
  if command_text_git_subcommand_args_request_help(
      words,
      subcommand_index + 1,
      segment_end,
    ) {
    return false
  }
  match words[subcommand_index] {
    "checkout" | "switch" => true
    "restore" =>
      command_text_git_restore_updates_worktree(
        words,
        subcommand_index + 1,
        segment_end,
      )
    "reset" =>
      command_text_git_reset_updates_worktree(
        words,
        subcommand_index + 1,
        segment_end,
      )
    "clean" =>
      command_text_git_clean_updates_worktree(
        words,
        subcommand_index + 1,
        segment_end,
      )
    "apply" =>
      command_text_git_apply_updates_worktree(
        words,
        subcommand_index + 1,
        segment_end,
      )
    "rm" =>
      command_text_git_rm_updates_worktree(
        words,
        subcommand_index + 1,
        segment_end,
      )
    "mv" =>
      command_text_git_mv_updates_worktree(
        words,
        subcommand_index + 1,
        segment_end,
      )
    _ => false
  }
}

///|
fn command_text_git_subcommand_args_request_help(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  start < end && (words[start] == "--help" || words[start] == "-h")
}

///|
fn command_text_git_restore_updates_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut staged = false
  let mut worktree = false
  let mut index = start
  while index < end {
    let arg = words[index]
    if arg == "--" {
      break
    }
    if arg == "--staged" || git_restore_short_option_cluster_has(arg, "S") {
      staged = true
    }
    if arg == "--worktree" || git_restore_short_option_cluster_has(arg, "W") {
      worktree = true
    }
    if git_restore_option_consumes_next(arg) {
      index += 2
      continue
    }
    index += 1
  }
  worktree || !staged
}

///|
fn command_text_git_reset_updates_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut index = start
  while index < end {
    match words[index] {
      "--hard" | "--merge" | "--keep" => return true
      _ => index += 1
    }
  }
  false
}

///|
fn command_text_git_clean_updates_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut dry_run = false
  let mut index = start
  while index < end {
    let arg = words[index]
    if git_clean_short_option_has_dry_run(arg) ||
      git_clean_long_option_is_dry_run(arg) {
      dry_run = true
    }
    if git_clean_option_consumes_next(arg) {
      index += 2
      continue
    }
    index += 1
  }
  !dry_run
}

///|
fn command_text_git_apply_updates_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut applies = true
  let mut cached_only = false
  let mut index = start
  while index < end {
    match words[index] {
      "--check" | "--stat" | "--numstat" | "--summary" => applies = false
      "--cached" => cached_only = true
      "--index" => cached_only = false
      "--apply" => applies = true
      _ => ()
    }
    index += 1
  }
  applies && !cached_only
}

///|
fn command_text_git_rm_updates_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut cached_only = false
  let mut dry_run = false
  for index in start..<end {
    let arg = words[index]
    match arg {
      "--cached" => cached_only = true
      "-n" | "--dry-run" => dry_run = true
      _ => if git_restore_short_option_cluster_has(arg, "n") { dry_run = true }
    }
  }
  !cached_only && !dry_run
}

///|
fn command_text_git_mv_updates_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  for index in start..<end {
    let arg = words[index]
    if arg == "-n" ||
      arg == "--dry-run" ||
      git_restore_short_option_cluster_has(arg, "n") {
      return false
    }
  }
  true
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
  let parts = word.split("=").collect()
  if parts.length() < 2 {
    return false
  }
  command_text_valid_env_name(parts[0].to_owned())
}

///|
fn command_text_valid_env_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  let mut index = 0
  for ch in name {
    let valid = if index == 0 {
      ch is ('a'..='z') || ch is ('A'..='Z') || ch == '_'
    } else {
      ch is ('a'..='z') || ch is ('A'..='Z') || ch is ('0'..='9') || ch == '_'
    }
    if !valid {
      return false
    }
    index += 1
  }
  true
}

///|
priv struct HeredocDelimiter {
  marker : String
  strip_tabs : Bool
}

///|
priv struct HeredocReadResult {
  marker : String
  next : Int
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
  word == target || path_basename(word) == path_basename(target)
}

///|
fn strip_leading_dot_slash(path : String) -> String {
  let mut result = path
  while result.has_prefix("./") {
    result = result[2:].to_owned()
  }
  result
}

///|
fn heredoc_delimiters_in_line(line : String) -> Array[HeredocDelimiter] {
  let delimiters : Array[HeredocDelimiter] = []
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
        } else if ch == '<' &&
          index + 1 < chars.length() &&
          chars[index + 1] == '<' {
          index += 2
          let strip_tabs = if index < chars.length() && chars[index] == '-' {
            index += 1
            true
          } else {
            false
          }
          while index < chars.length() && command_text_line_space(chars[index]) {
            index += 1
          }
          match read_heredoc_delimiter(chars, index) {
            Some(result) => {
              if result.marker != "" {
                delimiters.push({ marker: result.marker, strip_tabs })
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
  delimiters
}

///|
fn read_heredoc_delimiter(
  chars : Array[Char],
  start : Int,
) -> HeredocReadResult? {
  if start >= chars.length() {
    return None
  }
  let marker = StringBuilder()
  let first = chars[start]
  if first == '\'' || first == '"' {
    let quote = first
    let mut index = start + 1
    let mut escaped = false
    while index < chars.length() {
      let ch = chars[index]
      if escaped {
        marker.write_char(ch)
        escaped = false
      } else if quote == '"' && ch == '\\' {
        escaped = true
      } else if ch == quote {
        return Some({ marker: marker.to_string(), next: index + 1 })
      } else {
        marker.write_char(ch)
      }
      index += 1
    }
    None
  } else {
    let mut index = start
    while index < chars.length() && heredoc_delimiter_char(chars[index]) {
      if chars[index] == '\\' &&
        index + 1 < chars.length() &&
        heredoc_delimiter_char(chars[index + 1]) {
        marker.write_char(chars[index + 1])
        index += 2
        continue
      }
      marker.write_char(chars[index])
      index += 1
    }
    Some({ marker: marker.to_string(), next: index })
  }
}

///|
fn heredoc_delimiter_char(ch : Char) -> Bool {
  !command_text_line_space(ch) &&
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
  if line.has_suffix("\r") {
    line[:line.length() - 1].to_owned()
  } else {
    line
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
      source_tree_git_target(
        command.argv,
        command_index + 1,
        real_workspace_root,
        cwd,
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
    if is_protected_workspace_source_path(real_workspace_root, target) {
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
  guard arg.has_prefix("-") && arg != "-" else { return None }
  match arg.find(":") {
    Some(colon) if colon > 1 =>
      Some((arg[1:colon].to_owned().to_lower(), arg[colon + 1:].to_owned()))
    _ => None
  }
}

///|
fn powershell_parameter_name(arg : String) -> String? {
  if !arg.has_prefix("-") || arg == "-" {
    None
  } else {
    Some(arg[1:].to_owned().to_lower())
  }
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
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg.length() <= 2 {
    return false
  }
  arg[1:].contains("c")
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
priv struct GitInvocation {
  subcommand : String
  subcommand_index : Int
  cwd : String
}

///|
async fn source_tree_git_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  guard git_invocation(argv, arg_start, real_workspace_root, cwd)
    is Some(invocation) else {
    return None
  }
  let subcommand_index = invocation.subcommand_index
  let git_cwd = invocation.cwd
  if git_subcommand_args_request_help(argv, subcommand_index + 1) {
    return None
  }
  match invocation.subcommand {
    "checkout" =>
      git_checkout_target(
        argv,
        subcommand_index + 1,
        real_workspace_root,
        git_cwd,
      )
    "switch" => git_workspace_scope_target(real_workspace_root, git_cwd)
    "restore" =>
      git_restore_target(
        argv,
        subcommand_index + 1,
        real_workspace_root,
        git_cwd,
      )
    "reset" =>
      if git_reset_updates_worktree(argv, subcommand_index + 1) {
        git_workspace_scope_target(real_workspace_root, git_cwd)
      } else {
        None
      }
    "clean" =>
      if git_clean_updates_worktree(argv, subcommand_index + 1) {
        git_workspace_scope_target(real_workspace_root, git_cwd)
      } else {
        None
      }
    "apply" =>
      if git_apply_updates_worktree(argv, subcommand_index + 1) {
        git_workspace_scope_target(real_workspace_root, git_cwd)
      } else {
        None
      }
    "rm" =>
      git_rm_target(argv, subcommand_index + 1, real_workspace_root, git_cwd)
    "mv" =>
      git_mv_target(argv, subcommand_index + 1, real_workspace_root, git_cwd)
    _ => None
  }
}

///|
fn git_invocation(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> GitInvocation? {
  let mut index = arg_start
  let mut effective_cwd = source_write_detection_cwd(
    real_workspace_root,
    Some(cwd),
  )
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--" {
      return None
    }
    if arg == "--help" || arg == "-h" {
      return None
    }
    if arg == "-C" {
      if index + 1 >= argv.length() {
        return None
      }
      effective_cwd = resolve_source_write_redirect_target(
        effective_cwd,
        argv[index + 1],
      )
      index += 2
      continue
    }
    match git_attached_cwd_option(arg) {
      Some(next_cwd) => {
        effective_cwd = resolve_source_write_redirect_target(
          effective_cwd, next_cwd,
        )
        index += 1
        continue
      }
      None => ()
    }
    if arg == "--work-tree" {
      if index + 1 >= argv.length() {
        return None
      }
      effective_cwd = resolve_source_write_redirect_target(
        effective_cwd,
        argv[index + 1],
      )
      index += 2
      continue
    }
    match git_attached_work_tree_option(arg) {
      Some(work_tree) => {
        effective_cwd = resolve_source_write_redirect_target(
          effective_cwd, work_tree,
        )
        index += 1
        continue
      }
      None => ()
    }
    if git_global_option_consumes_next(arg) {
      index += 2
      continue
    }
    if git_global_option_with_attached_value(arg) ||
      git_global_no_arg_option(arg) {
      index += 1
      continue
    }
    if arg.has_prefix("-") && arg != "-" {
      return None
    }
    return Some({ subcommand: arg, subcommand_index: index, cwd: effective_cwd })
  }
  None
}

///|
fn git_attached_cwd_option(arg : String) -> String? {
  if arg.has_prefix("-C") && arg != "-C" {
    Some(arg[2:].to_owned())
  } else {
    None
  }
}

///|
fn git_attached_work_tree_option(arg : String) -> String? {
  if arg.has_prefix("--work-tree=") {
    Some(arg["--work-tree=".length():].to_owned())
  } else {
    None
  }
}

///|
fn git_global_option_consumes_next(arg : String) -> Bool {
  arg == "-c" ||
  arg == "--config-env" ||
  arg == "--exec-path" ||
  arg == "--git-dir" ||
  arg == "--namespace"
}

///|
fn git_global_option_with_attached_value(arg : String) -> Bool {
  (arg.has_prefix("-c") && arg != "-c") ||
  arg.has_prefix("--config-env=") ||
  arg.has_prefix("--exec-path=") ||
  arg.has_prefix("--git-dir=") ||
  arg.has_prefix("--namespace=")
}

///|
fn git_global_no_arg_option(arg : String) -> Bool {
  match arg {
    "--version"
    | "--help"
    | "-p"
    | "--paginate"
    | "-P"
    | "--no-pager"
    | "--no-replace-objects"
    | "--no-optional-locks"
    | "--no-lazy-fetch"
    | "--literal-pathspecs"
    | "--glob-pathspecs"
    | "--noglob-pathspecs"
    | "--icase-pathspecs"
    | "--bare" => true
    _ => false
  }
}

///|
fn git_subcommand_args_request_help(
  argv : Array[String],
  arg_start : Int,
) -> Bool {
  arg_start < argv.length() &&
  (argv[arg_start] == "--help" || argv[arg_start] == "-h")
}

///|
async fn git_checkout_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  if git_command_has_dash_dash(argv, arg_start) {
    return git_restore_pathspec_target(
      git_pathspecs_after_dash_dash(argv, arg_start),
      real_workspace_root,
      cwd,
    )
  }
  git_workspace_scope_target(real_workspace_root, cwd)
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
  if is_under_workspace_root(root, target) {
    Some(target)
  } else {
    None
  }
}

///|
fn git_command_has_dash_dash(argv : Array[String], arg_start : Int) -> Bool {
  let mut index = arg_start
  while index < argv.length() {
    if argv[index] == "--" {
      return true
    }
    index += 1
  }
  false
}

///|
async fn git_restore_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  if !git_restore_updates_worktree(argv, arg_start) {
    return None
  }
  let paths = git_restore_paths(argv, arg_start)
  git_restore_pathspec_target(paths, real_workspace_root, cwd)
}

///|
fn git_restore_updates_worktree(argv : Array[String], arg_start : Int) -> Bool {
  let mut staged = false
  let mut worktree = false
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--" {
      break
    }
    if arg == "--staged" || git_restore_short_option_cluster_has(arg, "S") {
      staged = true
    }
    if arg == "--worktree" || git_restore_short_option_cluster_has(arg, "W") {
      worktree = true
    }
    if git_restore_option_consumes_next(arg) {
      index += 2
      continue
    }
    index += 1
  }
  worktree || !staged
}

///|
fn git_restore_short_option_cluster_has(arg : String, flag : String) -> Bool {
  arg.has_prefix("-") &&
  !arg.has_prefix("--") &&
  arg != "-" &&
  arg.contains(flag)
}

///|
async fn git_restore_pathspec_target(
  paths : Array[String],
  real_workspace_root : String,
  cwd : String,
) -> String? {
  if paths.length() == 0 {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  let mut has_positive_pathspec = false
  for path in paths {
    if !git_pathspec_is_exclude(path) {
      has_positive_pathspec = true
      break
    }
  }
  if !has_positive_pathspec {
    return git_workspace_scope_target(real_workspace_root, cwd)
  }
  for path in paths {
    if git_pathspec_is_exclude(path) {
      continue
    }
    guard git_positive_pathspec(path, real_workspace_root, cwd) is Some(spec) else {
      continue
    }
    if spec.path == "" || spec.path == "." {
      return git_workspace_scope_target(real_workspace_root, spec.base)
    }
    let target = resolve_source_write_redirect_target(spec.base, spec.path)
    if protected_workspace_source_or_tree_path(real_workspace_root, target) {
      return Some(target)
    }
    if git_pathspec_may_restore_workspace_source(real_workspace_root, target) {
      return Some(target)
    }
  }
  None
}

///|
priv struct GitPositivePathspec {
  base : String
  path : String
}

///|
fn git_positive_pathspec(
  pathspec : String,
  real_workspace_root : String,
  cwd : String,
) -> GitPositivePathspec? {
  if pathspec.has_prefix(":/") {
    return Some({ base: real_workspace_root, path: pathspec[2:].to_owned() })
  }
  if pathspec.has_prefix(":(") {
    match pathspec.find(")") {
      Some(close) => {
        let magic = pathspec[2:close]
        if git_long_pathspec_magic_is_exclude(magic) {
          return None
        }
        let base = if git_long_pathspec_magic_is_top(magic) {
          real_workspace_root
        } else {
          cwd
        }
        return Some({ base, path: pathspec[close + 1:].to_owned() })
      }
      None => ()
    }
  }
  Some({ base: cwd, path: pathspec })
}

///|
fn git_pathspec_is_exclude(pathspec : String) -> Bool {
  if pathspec.has_prefix(":!") || pathspec.has_prefix(":^") {
    return true
  }
  if pathspec.has_prefix(":/!") || pathspec.has_prefix(":/^") {
    return true
  }
  if pathspec.has_prefix(":(") {
    match pathspec.find(")") {
      Some(close) =>
        return git_long_pathspec_magic_is_exclude(pathspec[2:close])
      None => return false
    }
  }
  false
}

///|
fn git_long_pathspec_magic_is_top(magic : StringView) -> Bool {
  for part in magic.split(",") {
    if part == "top" || part == "/" {
      return true
    }
  }
  false
}

///|
fn git_long_pathspec_magic_is_exclude(magic : StringView) -> Bool {
  for part in magic.split(",") {
    if part == "exclude" || part == "!" || part == "^" {
      return true
    }
  }
  false
}

///|
fn git_pathspecs_after_dash_dash(
  argv : Array[String],
  arg_start : Int,
) -> Array[String] {
  let paths : Array[String] = []
  let mut index = arg_start
  let mut after_dash_dash = false
  while index < argv.length() {
    let arg = argv[index]
    if !after_dash_dash && arg == "--" {
      after_dash_dash = true
      index += 1
      continue
    }
    if after_dash_dash {
      paths.push(arg)
    }
    index += 1
  }
  paths
}

///|
fn git_pathspec_may_restore_workspace_source(
  real_workspace_root : String,
  target : String,
) -> Bool {
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let target = @path.Path(target).normalize().to_string()
  is_under_workspace_root(root, target) &&
  !is_moon_managed_workspace_path(root, target) &&
  !looks_like_non_source_file_path(target)
}

///|
fn git_restore_paths(argv : Array[String], arg_start : Int) -> Array[String] {
  let paths : Array[String] = []
  let mut index = arg_start
  let mut after_dash_dash = false
  while index < argv.length() {
    let arg = argv[index]
    if !after_dash_dash && arg == "--" {
      after_dash_dash = true
      index += 1
      continue
    }
    if !after_dash_dash && git_restore_option_consumes_next(arg) {
      index += 2
      continue
    }
    if !after_dash_dash && git_restore_option_with_attached_value(arg) {
      index += 1
      continue
    }
    if !after_dash_dash && arg.has_prefix("-") && arg != "-" {
      index += 1
      continue
    }
    if after_dash_dash || !arg.has_prefix("-") || arg == "-" {
      paths.push(arg)
    }
    index += 1
  }
  paths
}

///|
fn git_restore_option_consumes_next(arg : String) -> Bool {
  arg == "--source" || arg == "-s" || arg == "--pathspec-from-file"
}

///|
fn git_restore_option_with_attached_value(arg : String) -> Bool {
  arg.has_prefix("--source=") || arg.has_prefix("--pathspec-from-file=")
}

///|
fn git_reset_updates_worktree(argv : Array[String], arg_start : Int) -> Bool {
  let mut index = arg_start
  while index < argv.length() {
    match argv[index] {
      "--hard" | "--merge" | "--keep" => return true
      _ => index += 1
    }
  }
  false
}

///|
fn git_clean_updates_worktree(argv : Array[String], arg_start : Int) -> Bool {
  let mut dry_run = false
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if git_clean_short_option_has_dry_run(arg) ||
      git_clean_long_option_is_dry_run(arg) {
      dry_run = true
    }
    if git_clean_option_consumes_next(arg) {
      index += 2
      continue
    }
    index += 1
  }
  !dry_run
}

///|
fn git_clean_long_option_is_dry_run(arg : String) -> Bool {
  arg == "--dry-run"
}

///|
fn git_clean_option_consumes_next(arg : String) -> Bool {
  arg == "--exclude" || git_clean_short_option_cluster_consumes_next(arg)
}

///|
fn git_clean_short_option_cluster_consumes_next(arg : String) -> Bool {
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  let chars = [ for ch in arg => ch ]
  chars.length() >= 2 && chars[chars.length() - 1] == 'e'
}

///|
fn git_clean_short_option_has_dry_run(arg : String) -> Bool {
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  let chars = [ for ch in arg => ch ]
  for index in 1..<chars.length() {
    match chars[index] {
      'n' => return true
      'e' => return false
      _ => ()
    }
  }
  false
}

///|
fn git_apply_updates_worktree(argv : Array[String], arg_start : Int) -> Bool {
  let mut applies = true
  let mut cached_only = false
  let mut index = arg_start
  while index < argv.length() {
    match argv[index] {
      "--check" | "--stat" | "--numstat" | "--summary" => applies = false
      "--cached" => cached_only = true
      "--index" => cached_only = false
      "--apply" => applies = true
      _ => ()
    }
    index += 1
  }
  applies && !cached_only
}

///|
async fn git_rm_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let mut cached_only = false
  let mut dry_run = false
  let mut pathspec_from_file = false
  let paths : Array[String] = []
  let mut index = arg_start
  let mut after_dash_dash = false
  while index < argv.length() {
    let arg = argv[index]
    if !after_dash_dash && arg == "--" {
      after_dash_dash = true
      index += 1
      continue
    }
    if !after_dash_dash {
      match arg {
        "--cached" => {
          cached_only = true
          index += 1
          continue
        }
        "-n" | "--dry-run" => {
          dry_run = true
          index += 1
          continue
        }
        "--pathspec-from-file" => {
          if index + 1 >= argv.length() {
            return None
          }
          pathspec_from_file = true
          index += 2
          continue
        }
        "--pathspec-file-nul" => {
          index += 1
          continue
        }
        _ =>
          if git_restore_short_option_cluster_has(arg, "n") {
            dry_run = true
            index += 1
            continue
          } else if arg.has_prefix("--pathspec-from-file=") {
            pathspec_from_file = true
            index += 1
            continue
          } else if arg.has_prefix("-") && arg != "-" {
            index += 1
            continue
          }
      }
    }
    paths.push(arg)
    index += 1
  }
  if cached_only || dry_run {
    None
  } else if pathspec_from_file {
    git_workspace_scope_target(real_workspace_root, cwd)
  } else {
    git_restore_pathspec_target(paths, real_workspace_root, cwd)
  }
}

///|
async fn git_mv_target(
  argv : Array[String],
  arg_start : Int,
  real_workspace_root : String,
  cwd : String,
) -> String? {
  let paths : Array[String] = []
  let mut index = arg_start
  let mut after_dash_dash = false
  while index < argv.length() {
    let arg = argv[index]
    if !after_dash_dash && arg == "--" {
      after_dash_dash = true
      index += 1
      continue
    }
    if !after_dash_dash {
      if arg == "-n" ||
        arg == "--dry-run" ||
        git_restore_short_option_cluster_has(arg, "n") {
        return None
      }
      if arg.has_prefix("-") && arg != "-" {
        index += 1
        continue
      }
    }
    paths.push(arg)
    index += 1
  }
  if paths.length() < 2 {
    None
  } else {
    git_restore_pathspec_target(paths, real_workspace_root, cwd)
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
    if is_under_workspace_root(real_workspace_root, target) &&
      (
        !has_filter ||
        is_protected_workspace_source_path(real_workspace_root, target) ||
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
  let base = path_basename(pattern)
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
      is_protected_source_path(arg) {
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
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  for ch in arg[1:] {
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
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  for ch in arg[1:] {
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
  if arg.has_prefix("--source=") {
    Some(arg["--source=".length():].to_owned())
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
      if is_protected_workspace_source_path(root, target) {
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
  for source_index in 0..<literals.length() {
    for dest_index in 0..<literals.length() {
      if source_index != dest_index {
        let source = resolve_source_write_redirect_target(
          cwd,
          literals[source_index],
        )
        let dest = resolve_source_write_redirect_target(
          cwd,
          literals[dest_index],
        )
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
  is_protected_source_path(source) ||
  is_protected_source_path(dest) ||
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
  if !is_under_workspace_root(root, dest) ||
    is_moon_managed_workspace_path(root, dest) {
    return false
  }
  if !is_under_workspace_root(root, source) {
    return source_path_or_tree_contains_protected_source(source)
  }
  if !is_moon_managed_workspace_path(root, source) {
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
      if is_protected_workspace_source_path(root, target) {
        return Some(target)
      }
      if is_under_workspace_root(root, target) {
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
  } else if is_under_workspace_root(root, cwd) {
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
      if is_protected_workspace_source_path(real_workspace_root, target) {
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
  if is_protected_source_path(target) {
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
    if is_protected_source_path(child) {
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
  if is_protected_workspace_source_path(real_workspace_root, dest) {
    return true
  }
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let dest = @path.Path(dest).normalize().to_string()
  if !is_under_workspace_root(root, dest) ||
    is_moon_managed_workspace_path(root, dest) {
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
    @path.Path(dest).join(Path(path_basename(source))).normalize().to_string()
  } else {
    dest
  }
  if is_protected_workspace_source_path(root, final_dest) {
    return true
  }
  if dest_is_directory &&
    is_under_workspace_root(root, source) &&
    is_moon_managed_workspace_path(root, source) {
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
  let base = path_basename(path)
  match base.rev_find(".") {
    Some(dot) if dot + 1 < base.length() =>
      !is_protected_source_path(base) &&
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
fn path_basename(path : String) -> String {
  let normalized = strip_trailing_slash(path.replace_all(old="\\", new="/"))
  match normalized.rev_find("/") {
    Some(slash) => normalized[slash + 1:].to_owned()
    None => normalized
  }
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
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg.length() <= 2 {
    return false
  }
  for index, ch in arg[1:] {
    if ch == 'm' || ch == 'Z' {
      return index + 2 < arg.length()
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
  if !arg.has_prefix("-") || arg.has_prefix("--") {
    return false
  }
  for ch in arg[1:] {
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
  match target_directory {
    Some(dest) => Some({ sources: operands, dest: Some(dest) })
    None =>
      if operands.length() >= 2 {
        let sources : Array[String] = []
        for index in 0..<(operands.length() - 1) {
          sources.push(operands[index])
        }
        Some({ sources, dest: Some(operands[operands.length() - 1]) })
      } else {
        Some({ sources: [], dest: None })
      }
  }
}

///|
fn mv_option_consumes_next(arg : String) -> Bool {
  arg == "-t" || arg == "--target-directory" || arg == "-S" || arg == "--suffix"
}

///|
fn mv_attached_target_directory_option(arg : String) -> String? {
  if arg.has_prefix("-t") && arg.length() > 2 {
    Some(arg[2:].to_owned())
  } else if arg.has_prefix("--target-directory=") {
    Some(arg["--target-directory=".length():].to_owned())
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
  if !arg.has_prefix("-") || arg.has_prefix("--") {
    return false
  }
  for ch in arg[1:] {
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
      if is_protected_workspace_source_path(real_workspace_root, target) {
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
  if arg.has_prefix("-t") && arg.length() > 2 {
    Some(arg[2:].to_owned())
  } else if arg.has_prefix("--target-directory=") {
    Some(arg["--target-directory=".length():].to_owned())
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
  if !arg.has_prefix("-") || arg.has_prefix("--") {
    return false
  }
  for ch in arg[1:] {
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
  if arg.has_prefix("-t") && arg.length() > 2 {
    Some(arg[2:].to_owned())
  } else if arg.has_prefix("--target-directory=") {
    Some(arg["--target-directory=".length():].to_owned())
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
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg.length() <= 2 {
    return None
  }
  let mut index = 1
  for ch in arg[1:] {
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
  if !arg.has_prefix("-") || arg.has_prefix("--") {
    return false
  }
  for ch in arg[1:] {
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
  if !arg.has_prefix("-") || arg.has_prefix("--") {
    return false
  }
  for ch in arg[1:] {
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
    if is_protected_workspace_source_path(real_workspace_root, target) {
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
  if !arg.has_prefix("-") || arg.has_prefix("--") || arg == "-" {
    return false
  }
  for ch in arg[1:] {
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
    if is_protected_workspace_source_path(real_workspace_root, target) {
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
  if !arg.has_prefix("-") || arg.has_prefix("--") {
    return false
  }
  for ch in arg[1:] {
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
        let sources : Array[String] = []
        for index in 0..<(operands.length() - 1) {
          sources.push(operands[index])
        }
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
fn is_protected_workspace_source_path(
  real_workspace_root : String,
  target : String,
) -> Bool {
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let target = @path.Path(target).normalize().to_string()
  is_under_workspace_root(root, target) &&
  !is_moon_managed_workspace_path(root, target) &&
  is_protected_source_path(target)
}

///|
fn is_under_workspace_root(root : String, path : String) -> Bool {
  let root = workspace_compare_path(root)
  let path = workspace_compare_path(path)
  if path == root {
    true
  } else if root == "/" {
    path.has_prefix("/")
  } else {
    path.has_prefix("\{root}/")
  }
}

///|
async fn protected_workspace_source_or_tree_path(
  real_workspace_root : String,
  target : String,
) -> Bool {
  if is_protected_workspace_source_path(real_workspace_root, target) {
    return true
  }
  let root = strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let target = @path.Path(target).normalize().to_string()
  if !is_under_workspace_root(root, target) ||
    is_moon_managed_workspace_path(root, target) {
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
    if is_protected_workspace_source_path(root, child) {
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
fn is_moon_managed_workspace_path(root : String, path : String) -> Bool {
  let root = workspace_compare_path(root)
  let path = workspace_compare_path(path)
  if path == root {
    return false
  }
  if !is_under_workspace_root(root, path) {
    return false
  }
  let relative_start = if root == "/" { 1 } else { root.length() + 1 }
  let relative = path[relative_start:].to_owned()
  for part in relative.split("/") {
    if part == "_build" || part == ".mooncakes" {
      return true
    }
  }
  false
}

///|
fn workspace_compare_path(path : String) -> String {
  strip_trailing_slash(path.replace_all(old="\\", new="/"))
}

///|
fn is_protected_source_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path.has_suffix(".mbt.md") ||
  path.has_suffix(".mbt") ||
  path.has_suffix(".mbti") ||
  path == "moon.mod" ||
  path.has_suffix("/moon.mod") ||
  path == "moon.pkg" ||
  path.has_suffix("/moon.pkg") ||
  path == "moon.mod.json" ||
  path.has_suffix("/moon.mod.json") ||
  path == "moon.pkg.json" ||
  path.has_suffix("/moon.pkg.json") ||
  path == "moon.work" ||
  path.has_suffix("/moon.work")
}

///|
fn direct_source_write_redirect_blocked_content(target : String) -> String {
  (
    $|shell sandbox: source file write redirect is blocked before execution: \{target}
    $|\{SandboxSourceWriteFeedback}
    $|<system>exit=blocked</system>
  )
}

///|
fn direct_source_tree_operation_blocked_content(target : String) -> String {
  (
    $|shell sandbox: source tree operation is blocked before execution: \{target}
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
  sandbox_denied_source_write(
    agent_output.output,
    agent_output.sandbox_denial_subjects,
  )
}

///|
fn sandbox_denied_source_write(
  output : ShellOutput,
  denial_subjects : Array[String],
) -> Bool {
  output.text
  .split("\n")
  .any(line => {
    sandbox_denial_line_mentions_denial(line) &&
    (
      sandbox_denial_line_mentions_source_path(line) ||
      sandbox_denial_line_mentions_known_subject(line, denial_subjects)
    )
  })
}

///|
fn sandbox_denial_line_mentions_known_subject(
  line : StringView,
  denial_subjects : Array[String],
) -> Bool {
  denial_subjects.any(subject => {
    subject != "" && sandbox_denial_line_mentions_literal_subject(line, subject)
  })
}

///|
fn sandbox_denial_line_mentions_literal_subject(
  line : StringView,
  subject : String,
) -> Bool {
  line.contains("\{subject}:") ||
  line.contains("\{subject}'") ||
  line.contains("\{subject}\"") ||
  line.contains("\{subject}`") ||
  (
    sandbox_denial_line_has_denial_colon_before_subject(line) &&
    line.has_suffix(subject)
  )
}

///|
fn sandbox_denial_line_mentions_source_path(line : StringView) -> Bool {
  sandbox_denial_line_mentions_source_suffix(line, ".mbt.md") ||
  sandbox_denial_line_mentions_source_suffix(line, ".mbt") ||
  sandbox_denial_line_mentions_source_suffix(line, ".mbti") ||
  sandbox_denial_line_mentions_source_suffix(line, "moon.mod.json") ||
  sandbox_denial_line_mentions_source_suffix(line, "moon.pkg.json") ||
  sandbox_denial_line_mentions_source_suffix(line, "moon.mod") ||
  sandbox_denial_line_mentions_source_suffix(line, "moon.pkg") ||
  sandbox_denial_line_mentions_source_suffix(line, "moon.work")
}

///|
fn sandbox_denial_line_mentions_source_suffix(
  line : StringView,
  suffix : String,
) -> Bool {
  line.contains("\{suffix}:") ||
  line.contains("\{suffix}'") ||
  line.contains("\{suffix}\"") ||
  line.contains("\{suffix}`") ||
  (
    sandbox_denial_line_has_denial_colon_before_subject(line) &&
    line.has_suffix(suffix)
  )
}

///|
fn sandbox_denial_line_mentions_denial(line : StringView) -> Bool {
  line.contains("Operation not permitted") ||
  line.contains("operation not permitted") ||
  line.contains(": Permission denied") ||
  line.contains("Permission denied:")
}

///|
fn sandbox_denial_line_has_denial_colon_before_subject(
  line : StringView,
) -> Bool {
  line.contains("Operation not permitted:") ||
  line.contains("operation not permitted:") ||
  line.contains("Permission denied:")
}

///|
fn regex_escape(text : String) -> String {
  let escaped = StringBuilder()
  for ch in text {
    match ch {
      '\\'
      | '.'
      | '+'
      | '*'
      | '?'
      | '^'
      | '$'
      | '('
      | ')'
      | '['
      | ']'
      | '{'
      | '}'
      | '|'
      | '/' => {
        escaped.write_char('\\')
        escaped.write_char(ch)
      }
      _ => escaped.write_char(ch)
    }
  }
  escaped.to_string()
}

///|
fn sbpl_string_escape(text : String) -> String {
  let escaped = StringBuilder()
  for ch in text {
    match ch {
      '"' | '\\' => {
        escaped.write_char('\\')
        escaped.write_char(ch)
      }
      '\n' => escaped.write_string("\\n")
      '\r' => escaped.write_string("\\r")
      '\t' => escaped.write_string("\\t")
      _ => escaped.write_char(ch)
    }
  }
  escaped.to_string()
}
