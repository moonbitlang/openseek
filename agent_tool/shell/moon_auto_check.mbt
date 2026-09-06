///|
async fn append_moon_command_check_summary(
  parsed : @shell_parse.ParseResult,
  cwd : String?,
  content : String,
  output : ShellOutput,
  timeout_ms : Int?,
  max_output_chars : Int,
) -> String {
  if output.exit_code != Some(0) || output.output_limit_reached {
    return content
  }
  if timeout_ms is Some(_) {
    return content
  }
  let check_max_output_chars = moon_check_output_budget(
    content, max_output_chars,
  )
  if check_max_output_chars <= 0 {
    return content
  }
  let check_start = match moon_auto_check_start_cwd_for_parse(parsed, cwd) {
    Some(check_start) => check_start
    None => return content
  }
  let summary = moon_check_summary_for_cwd(check_start, check_max_output_chars) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
  match summary {
    Some(summary) => insert_before_system_footer(content, summary)
    None => content
  }
}

///|
/// Insert `block` just before the trailing `<system>...</system>` footer of a
/// shell response, so the footer stays the last line (the read-tool convention).
/// `content` from `shell_response` always ends with that footer line.
fn insert_before_system_footer(content : String, block : String) -> String {
  match content.rev_split_once("\n") {
    Some((head, footer)) => "\{head}\n\{block}\n\{footer}"
    // Output-less command: content is the footer line alone.
    None => "\{block}\n\{content}"
  }
}

///|
fn moon_check_output_budget(content : String, max_output_chars : Int) -> Int {
  let remaining = max_output_chars - content.char_length() - 1
  remaining.clamp(min=0, max=@moon_check.MaxOutputChars)
}

///|
async fn moon_check_summary_for_cwd(
  cwd : String,
  max_output_chars : Int,
) -> String? {
  let check_cwd = match @moon_check.nearest_project_dir(cwd) {
    Some(check_cwd) => check_cwd
    None => return None
  }
  let result = @async.with_timeout_opt(@moon_check.TimeoutMs, () => {
    collect_shell_output(@moon_check.Command, cwd=check_cwd, max_output_chars~)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return Some("moon check: failed to run")
  }
  match result {
    Some(output) =>
      Some(
        @moon_check.format_output(
          output.exit_code,
          output.text,
          output.output_limit_reached,
        ),
      )
    None => Some("moon check: timed out")
  }
}

///|
fn should_auto_check_moon_command(cmd : String) -> Bool {
  moon_auto_check_start_cwd(cmd, None) is Some(_)
}

///|
fn moon_auto_check_start_cwd(cmd : String, cwd : String?) -> String? {
  moon_auto_check_start_cwd_for_parse(@shell_parse.parse_for_policy(cmd), cwd)
}

///|
fn moon_auto_check_start_cwd_for_parse(
  parsed : @shell_parse.ParseResult,
  cwd : String?,
) -> String? {
  let base_cwd = cwd.unwrap_or(".")
  match parsed {
    Simple(commands) => {
      if has_unsafe_command_separator(commands) {
        return None
      }
      let mut current_cwd : String? = Some(base_cwd)
      let mut cwd_depends_on_cd = false
      for index, command in commands {
        match command.separator_before {
          None | Some(";") =>
            if cwd_depends_on_cd {
              current_cwd = None
              cwd_depends_on_cd = false
            }
          Some("&&") => ()
          _ => return None
        }
        match current_cwd {
          Some(cwd) => {
            if command_may_mutate_shell_environment(command) {
              current_cwd = None
              cwd_depends_on_cd = false
              continue
            }
            match cwd_command_effect(command, cwd) {
              KnownCwd(next_cwd) => {
                if next_command_is_guarded_by_and(commands, index) {
                  current_cwd = Some(next_cwd)
                  cwd_depends_on_cd = true
                } else {
                  current_cwd = None
                  cwd_depends_on_cd = false
                }
                continue
              }
              UnknownCwd => {
                current_cwd = None
                cwd_depends_on_cd = false
                continue
              }
              NotCwdCommand => ()
            }
            if index + 1 == commands.length() {
              match auto_check_cwd_for_moon_command(command, cwd) {
                Some(cwd) => return Some(cwd)
                None => ()
              }
            }
          }
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
fn command_may_mutate_shell_environment(
  command : @shell_parse.SimpleCommand,
) -> Bool {
  if command.argv.length() == 0 {
    return command.env.length() > 0
  }
  match command.command_index() {
    Some(command_index) if command_index < command.argv.length() =>
      shell_environment_builtin(command.argv[command_index])
    _ => false
  }
}

///|
fn shell_environment_builtin(command_name : String) -> Bool {
  match command_name {
    "export" | "readonly" | "set" | "unset" | "typeset" | "declare" | "local" =>
      true
    "alias" | "unalias" | "hash" => true
    _ => false
  }
}

///|
fn has_unsafe_command_separator(
  commands : Array[@shell_parse.SimpleCommand],
) -> Bool {
  commands.any(command => command.separator_before is Some("|" | "||"))
}

///|
fn next_command_is_guarded_by_and(
  commands : Array[@shell_parse.SimpleCommand],
  index : Int,
) -> Bool {
  index + 1 < commands.length() &&
  commands[index + 1].separator_before == Some("&&")
}

///|
priv enum CwdCommandEffect {
  NotCwdCommand
  KnownCwd(String)
  UnknownCwd
}

///|
fn cwd_command_effect(
  command : @shell_parse.SimpleCommand,
  base_cwd : String,
) -> CwdCommandEffect {
  let argv = command.argv
  if argv is ["env", ..] {
    return NotCwdCommand
  }
  match command.command_index() {
    Some(command_index) if command_index < argv.length() =>
      match argv[command_index] {
        "cd" =>
          if command.env.length() > 0 {
            UnknownCwd
          } else {
            cd_command_effect(argv, command_index + 1, base_cwd)
          }
        "pushd" | "popd" => UnknownCwd
        _ => NotCwdCommand
      }
    _ => NotCwdCommand
  }
}

///|
fn cd_command_effect(
  argv : Array[String],
  arg_start : Int,
  base_cwd : String,
) -> CwdCommandEffect {
  let target = match argv.length() - arg_start {
    1 if !argv[arg_start].has_prefix("-") => argv[arg_start]
    2 if argv[arg_start] == "--" => argv[arg_start + 1]
    _ => return UnknownCwd
  }
  if cd_target_resolves_from_base(target) {
    KnownCwd(resolve_command_cwd(base_cwd, target))
  } else {
    UnknownCwd
  }
}

///|
fn cd_target_resolves_from_base(target : String) -> Bool {
  let target_path : @path.Path = target
  let normalized = target.replace_all(old="\\", new="/")
  target_path.is_absolute() ||
  normalized == "." ||
  normalized == ".." ||
  normalized.has_prefix("./") ||
  normalized.has_prefix("../")
}

///|
fn auto_check_cwd_for_moon_command(
  command : @shell_parse.SimpleCommand,
  base_cwd : String,
) -> String? {
  if command_has_custom_environment(command) {
    return None
  }
  match moon_command_start(command) {
    Some(index) =>
      match parse_moon_invocation(command.argv, index, base_cwd) {
        Some(invocation) if !invocation.dry_run &&
          is_auto_check_moon_subcommand(
            command.argv,
            invocation.subcommand_index,
          ) => Some(invocation.cwd)
        _ => None
      }
    _ => None
  }
}

///|
fn command_has_custom_environment(command : @shell_parse.SimpleCommand) -> Bool {
  command.env.length() > 0 ||
  (command.argv.length() > 0 && command.argv[0] == "env")
}

///|
priv struct MoonInvocation {
  subcommand_index : Int
  cwd : String
  dry_run : Bool
}

///|
fn parse_moon_invocation(
  argv : Array[String],
  moon_index : Int,
  base_cwd : String,
) -> MoonInvocation? {
  let mut index = moon_index + 1
  let mut cwd = base_cwd
  let mut dry_run = false
  while index < argv.length() {
    match argv[index] {
      "-C" => {
        if index + 1 >= argv.length() {
          return None
        }
        cwd = resolve_command_cwd(cwd, argv[index + 1])
        index += 2
      }
      option if moon_attached_cwd_option(option) is Some(target) => {
        cwd = resolve_command_cwd(cwd, target)
        index += 1
      }
      "--target-dir" | "-Z" | "--unstable-feature" => {
        if index + 1 >= argv.length() {
          return None
        }
        index += 2
      }
      option if moon_attached_value_option(option, "--target-dir") ||
        moon_attached_value_option(option, "-Z") ||
        moon_attached_value_option(option, "--unstable-feature") => index += 1
      "--dry-run" => {
        dry_run = true
        index += 1
      }
      "-q" | "--quiet" | "-v" | "--verbose" | "--trace" => index += 1
      "-V" | "--version" | "-h" | "--help" => return None
      option if option.has_prefix("-") => return None
      _ => return Some({ subcommand_index: index, cwd, dry_run, })
    }
  }
  None
}

///|
fn moon_attached_cwd_option(option : String) -> String? {
  if option.has_prefix("-C=") {
    option_value_after_prefix(option, "-C=")
  } else {
    option_value_after_prefix(option, "-C")
  }
}

///|
fn moon_attached_value_option(option : String, name : String) -> Bool {
  if name.has_prefix("--") {
    option_value_after_prefix(option, "\{name}=") is Some(_)
  } else if option.has_prefix("\{name}=") {
    option_value_after_prefix(option, "\{name}=") is Some(_)
  } else {
    option_value_after_prefix(option, name) is Some(_)
  }
}

///|
fn option_value_after_prefix(option : String, prefix : String) -> String? {
  match option.strip_prefix(prefix) {
    Some(value) => {
      let value = value.to_owned()
      if value == "" {
        None
      } else {
        Some(value)
      }
    }
    None => None
  }
}

///|
fn is_auto_check_moon_subcommand(
  argv : Array[String],
  subcommand_index : Int,
) -> Bool {
  if argv_contains_flag(argv, subcommand_index + 1, "--dry-run") {
    return false
  }
  if argv_contains_help_flag(argv, subcommand_index + 1) {
    return false
  }
  match argv[subcommand_index] {
    "add" | "remove" | "update" | "info" => true
    "fmt" =>
      !argv_contains_flag(argv, subcommand_index + 1, "--check") &&
      !argv_contains_flag(argv, subcommand_index + 1, "--warn")
    "ide" =>
      subcommand_index + 1 < argv.length() &&
      argv[subcommand_index + 1] == "rename" &&
      argv_contains_flag(argv, subcommand_index + 2, "--apply")
    "test" => argv_contains_update_flag(argv, subcommand_index + 1)
    _ => false
  }
}

///|
fn argv_contains_update_flag(argv : Array[String], start : Int) -> Bool {
  argv_contains_flag(argv, start, "--update") ||
  argv_contains_flag(argv, start, "-u")
}

///|
fn argv_contains_update_flag_before_double_dash(
  argv : Array[String],
  start : Int,
) -> Bool {
  argv_contains_flag_before_double_dash(argv, start, "--update") ||
  argv_contains_flag_before_double_dash(argv, start, "-u")
}

///|
fn argv_contains_help_flag(argv : Array[String], start : Int) -> Bool {
  argv_contains_flag(argv, start, "--help") ||
  argv_contains_flag(argv, start, "-h")
}

///|
fn argv_contains_help_flag_before_double_dash(
  argv : Array[String],
  start : Int,
) -> Bool {
  argv_contains_flag_before_double_dash(argv, start, "--help") ||
  argv_contains_flag_before_double_dash(argv, start, "-h")
}

///|
fn argv_contains_flag(argv : Array[String], start : Int, flag : String) -> Bool {
  for index in start..<argv.length() {
    if argv[index] == flag {
      return true
    }
  }
  false
}

///|
fn argv_contains_flag_before_double_dash(
  argv : Array[String],
  start : Int,
  flag : String,
) -> Bool {
  for index in start..<argv.length() {
    if argv[index] == "--" {
      return false
    }
    if argv[index] == flag {
      return true
    }
  }
  false
}

///|
fn moon_command_start(command : @shell_parse.SimpleCommand) -> Int? {
  match command.command_index() {
    Some(index) if index < command.argv.length() &&
      command.argv[index] == "moon" => Some(index)
    _ => None
  }
}

///|
fn resolve_command_cwd(base : String, target : String) -> String {
  let target_path : @path.Path = target
  if target_path.is_absolute() {
    target_path.normalize().to_string()
  } else {
    let base_path : @path.Path = base
    base_path.join(target_path).normalize().to_string()
  }
}

///|
fn parent_dir(path : String) -> String? {
  @workspace_path.parent_dir(path)
}

///|
fn strip_trailing_slash(path : String) -> String {
  @workspace_path.strip_trailing_slash(path)
}

///|
test "detect moon commands that should trigger follow-up check" {
  assert_true(should_auto_check_moon_command("moon add moonbitlang/async"))
  assert_true(should_auto_check_moon_command("moon remove moonbitlang/async"))
  assert_true(should_auto_check_moon_command("moon update"))
  assert_true(should_auto_check_moon_command("moon fmt"))
  assert_true(should_auto_check_moon_command("moon fmt # trailing note"))
  assert_true(should_auto_check_moon_command("moon info"))
  assert_true(should_auto_check_moon_command("moon -C pkg fmt"))
  assert_true(should_auto_check_moon_command("moon -Cpkg fmt"))
  assert_true(should_auto_check_moon_command("moon -C=pkg fmt"))
  assert_true(should_auto_check_moon_command("moon -q -C pkg info"))
  assert_true(
    should_auto_check_moon_command("moon --target-dir=/tmp/build fmt"),
  )
  assert_true(
    should_auto_check_moon_command(
      "moon ide rename old_name new_name --loc main.mbt:1:8 --apply",
    ),
  )
  assert_true(should_auto_check_moon_command("moon test --update"))
  assert_true(should_auto_check_moon_command("command moon fmt"))
  assert_true(should_auto_check_moon_command("command -- moon fmt"))
  assert_true(should_auto_check_moon_command("command -p moon fmt"))
  assert_true(should_auto_check_moon_command("cd ./pkg && moon fmt"))
  assert_true(should_auto_check_moon_command("cd ./pkg &&\nmoon fmt"))
  assert_true(
    should_auto_check_moon_command("cd ./pkg && moon fmt # trailing note"),
  )
}

///|
test "bound follow-up check output by remaining shell output budget" {
  assert_eq(moon_check_output_budget("exit=0\nabc", 10), 0)
  assert_eq(
    moon_check_output_budget("exit=0\n", 20000),
    @moon_check.MaxOutputChars,
  )
  assert_eq(moon_check_output_budget("exit=0\nabcdef", 20), 6)
}

///|
test "do not trigger follow-up check for read-only moon commands or data" {
  assert_false(should_auto_check_moon_command("moon check"))
  assert_false(should_auto_check_moon_command("moon test"))
  assert_false(should_auto_check_moon_command("moon --dry-run fmt"))
  assert_false(should_auto_check_moon_command("moon fmt --check"))
  assert_false(should_auto_check_moon_command("moon fmt --dry-run"))
  assert_false(should_auto_check_moon_command("moon fmt --help"))
  assert_false(should_auto_check_moon_command("moon add pkg -h"))
  assert_false(should_auto_check_moon_command("moon add pkg --dry-run"))
  assert_false(should_auto_check_moon_command("moon test --update --dry-run"))
  assert_false(should_auto_check_moon_command("moon test --update --help"))
  assert_false(should_auto_check_moon_command("moon ide doc String"))
  assert_false(
    should_auto_check_moon_command(
      "moon ide rename old_name new_name --loc main.mbt:1:8",
    ),
  )
  assert_false(
    should_auto_check_moon_command(
      "moon ide rename old_name new_name --loc main.mbt:1:8 --apply --help",
    ),
  )
  assert_false(should_auto_check_moon_command("FOO=bar moon fmt"))
  assert_false(should_auto_check_moon_command("env FOO=bar moon add pkg"))
  assert_false(should_auto_check_moon_command("env -i moon fmt"))
  assert_false(should_auto_check_moon_command("command -v moon"))
  assert_false(should_auto_check_moon_command("echo moon add"))
  assert_false(should_auto_check_moon_command("MOON=moon add pkg"))
  assert_false(should_auto_check_moon_command("env -u FOO moon add pkg"))
  assert_false(should_auto_check_moon_command("moon $SUBCOMMAND"))
  assert_false(should_auto_check_moon_command("true || moon fmt"))
  assert_false(should_auto_check_moon_command("false && cd other; moon fmt"))
  assert_false(should_auto_check_moon_command("cd pkg && moon fmt"))
  assert_false(should_auto_check_moon_command("cd pkg | moon fmt"))
  assert_false(should_auto_check_moon_command("cd pkg; moon fmt"))
  assert_false(
    should_auto_check_moon_command("cd missing; cd project && moon fmt"),
  )
  assert_false(should_auto_check_moon_command("false && moon fmt; true"))
  assert_false(should_auto_check_moon_command("moon fmt --badflag; true"))
  assert_false(should_auto_check_moon_command("moon fmt && true"))
  assert_false(should_auto_check_moon_command("exit 0; moon fmt"))
  assert_false(should_auto_check_moon_command("exit 0 && moon fmt"))
  assert_false(should_auto_check_moon_command("command exit 0; moon fmt"))
  assert_false(should_auto_check_moon_command("command -p exit 0; moon fmt"))
  assert_false(
    should_auto_check_moon_command("export MOON_HOME=/tmp/custom; moon fmt"),
  )
  assert_false(should_auto_check_moon_command("set -a; FOO=bar; moon fmt"))
  assert_false(should_auto_check_moon_command("PATH=/tmp; moon fmt"))
  assert_false(
    should_auto_check_moon_command("alias moon='echo fake'\nmoon fmt"),
  )
  assert_false(should_auto_check_moon_command("hash -r\nmoon fmt"))
  assert_false(
    should_auto_check_moon_command("command export FOO=bar; moon fmt"),
  )
  assert_false(
    should_auto_check_moon_command("builtin export FOO=bar; moon fmt"),
  )
  assert_false(
    should_auto_check_moon_command("CDPATH=/tmp cd ./project && moon fmt"),
  )
  assert_false(
    should_auto_check_moon_command("FOO=bar cd ./project && moon fmt"),
  )
}

///|
#cfg(not(platform="windows"))
test "detect moon command check cwd from -C option" {
  fn cwd_for(cmd : String, base : String) -> String? {
    moon_auto_check_start_cwd(cmd, Some(base))
  }

  assert_true(cwd_for("moon fmt", "/repo") is Some("/repo"))
  assert_true(cwd_for("moon -C pkg fmt", "/repo") is Some("/repo/pkg"))
  assert_true(cwd_for("moon -Cpkg fmt", "/repo") is Some("/repo/pkg"))
  assert_true(cwd_for("moon -C=pkg fmt", "/repo") is Some("/repo/pkg"))
  assert_true(
    cwd_for("moon -C ../other info", "/repo/pkg") is Some("/repo/other"),
  )
  assert_true(cwd_for("moon -C /tmp/mod fmt", "/repo") is Some("/tmp/mod"))
  assert_true(
    cwd_for("moon --target-dir=/tmp/moonbuild fmt", "/repo") is Some("/repo"),
  )
  assert_true(cwd_for("cd project && moon fmt", "/repo") is None)
  assert_true(
    cwd_for("cd ./project && moon fmt", "/repo") is Some("/repo/project"),
  )
  assert_true(
    cwd_for("cd ./project &&\nmoon fmt", "/repo") is Some("/repo/project"),
  )
  assert_true(cwd_for("env cd ./project && moon fmt", "/repo") is Some("/repo"))
  assert_true(
    cwd_for("env -i cd ./project && moon fmt", "/repo") is Some("/repo"),
  )
  assert_true(cwd_for("cd -- project && moon fmt", "/repo") is None)
  assert_true(
    cwd_for("cd -- ./project && moon fmt", "/repo") is Some("/repo/project"),
  )
  assert_true(cwd_for("command cd project && moon fmt", "/repo") is None)
  assert_true(
    cwd_for("command cd ./project && moon fmt", "/repo")
    is Some("/repo/project"),
  )
  assert_true(cwd_for("command -- cd project && moon fmt", "/repo") is None)
  assert_true(
    cwd_for("command -- cd ./project && moon fmt", "/repo")
    is Some("/repo/project"),
  )
  assert_true(cwd_for("builtin cd project && moon fmt", "/repo") is None)
  assert_true(
    cwd_for("builtin cd ./project && moon fmt", "/repo")
    is Some("/repo/project"),
  )
  assert_true(cwd_for("cd && moon fmt", "/repo") is None)
  assert_true(cwd_for("cd - && moon fmt", "/repo") is None)
  assert_true(cwd_for("cd -P project && moon fmt", "/repo") is None)
  assert_true(cwd_for("pushd project && moon fmt", "/repo") is None)
  assert_true(cwd_for("cd project && moon -C nested info", "/repo") is None)
  assert_true(
    cwd_for("cd ./project && moon -C nested info", "/repo")
    is Some("/repo/project/nested"),
  )
  assert_true(cwd_for("moon check && cd project && moon fmt", "/repo") is None)
  assert_true(
    cwd_for("moon check && cd ./project && moon fmt", "/repo")
    is Some("/repo/project"),
  )
  assert_true(cwd_for("moon check && cd project; moon fmt", "/repo") is None)
  assert_true(cwd_for("cd missing; cd project && moon fmt", "/repo") is None)
  assert_true(cwd_for("moon check; moon fmt", "/repo") is Some("/repo"))
  assert_true(cwd_for("moon fmt; true", "/repo") is None)
  assert_true(cwd_for("echo ok; moon fmt", "/repo") is Some("/repo"))
}
