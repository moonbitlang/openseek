///|
/// Whether a single parsed command is a source-mutating `moon` invocation
/// (fmt / info / install / test --update / ...). Unlike
/// `auto_check_cwd_for_moon_command`, this does NOT skip env-prefixed commands
/// or depend on cwd: read-only enforcement must err toward blocking, so e.g.
/// `FOO=bar moon fmt` is still caught.
fn command_is_mutating_moon(command : @shell_parse.SimpleCommand) -> Bool {
  match moon_command_start(command) {
    Some(index) =>
      match parse_moon_invocation(command.argv, index, ".") {
        Some(invocation) =>
          !invocation.dry_run &&
          (
            is_auto_check_moon_subcommand(
              command.argv,
              invocation.subcommand_index,
            ) ||
            // A review is read-only: scaffolding a project (`moon new`) creates
            // manifests and source and must be blocked here too, independently
            // of post-command auto-checking.
            is_moon_scaffold_subcommand(
              command.argv,
              invocation.subcommand_index,
            )
          )
        None => false
      }
    None => false
  }
}

///|
/// Whether read-only (review) mode should refuse this parsed command. This is a
/// best-effort guard, not an airtight guarantee: it blocks the obvious bulk
/// source-rewriters — a source-mutating moon command (fmt / info / test
/// --update / `new` scaffolding / ...) anywhere in a `Simple` parse, including `&&`/`;` chains,
/// pipes, and env prefixes — so a review does not reformat or regenerate the
/// tree wholesale. Opaque commands (`TooComplex`: subshells, command
/// substitution) are allowed: a review that runs `moon check`/`moon test` can
/// already trigger pre-build source generation, so chasing every last mutation
/// is not worth crippling the review's ability to investigate.
///
/// `scratch_dir` is the one carve-out: a mutating/scaffold moon command that
/// PROVABLY operates inside the child's scratch lab (its effective cwd —
/// tracked through `cd` chains and `-C` — resolves under the lab, and a
/// scaffold's target lands there too) is the empiricism the lab exists for.
/// Anything ambiguous (unknown cwd, env prefixes, out-of-lab paths) keeps
/// the block: the guard still errs toward blocking.
fn review_read_only_blocks(
  parsed : @shell_parse.ParseResult,
  base_cwd~ : String,
  scratch_dir~ : String?,
) -> Bool {
  match parsed {
    Simple(commands) => {
      let mut state = source_write_initial_cwd_state(base_cwd)
      for index, command in commands {
        if mutating_moon_blocked(command, state, scratch_dir) {
          return true
        }
        state = source_write_next_cwd_state(
          command,
          state,
          next_command_separator(commands, index),
        )
      }
      false
    }
    _ => false
  }
}

///|
/// Whether one mutating/scaffold moon command must be refused given the
/// chain's tracked cwd candidates. Without a lab every mutating moon blocks
/// (the original rule); with one, the command must prove EVERY candidate
/// interpretation stays inside the lab.
fn mutating_moon_blocked(
  command : @shell_parse.SimpleCommand,
  state : SourceWriteCwdState,
  scratch_dir : String?,
) -> Bool {
  guard command_is_mutating_moon(command) else { return false }
  guard scratch_dir is Some(lab) else { return true }
  // Env prefixes stay blocked, mirroring the original guard's refusal to
  // reason about them.
  if command_has_custom_environment(command) {
    return true
  }
  guard moon_command_start(command) is Some(moon_index) else { return true }
  for cwd in state.active {
    guard cwd is Some(cwd) else { return true }
    guard parse_moon_invocation(command.argv, moon_index, cwd)
      is Some(invocation) else {
      return true
    }
    if is_moon_scaffold_subcommand(command.argv, invocation.subcommand_index) {
      // A scaffold is judged by where it LANDS. Any argument that names a
      // location (absolute, or containing a path separator — flag VALUES
      // like `--user t` are bare words) must resolve under the lab: an
      // out-of-lab target with an in-lab cwd is the escape this closes.
      // With no location-shaped argument the scaffold lands in the
      // effective cwd, which must itself be under the lab.
      let mut has_path_target = false
      for index in (invocation.subcommand_index + 1)..<command.argv.length() {
        let argument = command.argv[index]
        if argument.has_prefix("-") || !argument.contains("/") {
          continue
        }
        has_path_target = true
        guard @source_write_policy.path_is_under_lab(
          resolve_command_cwd(invocation.cwd, argument),
          lab,
        ) else {
          return true
        }
      }
      guard has_path_target ||
        @source_write_policy.path_is_under_lab(invocation.cwd, lab) else {
        return true
      }
    } else {
      // A mutating (non-scaffold) moon command is judged by where it RUNS.
      guard @source_write_policy.path_is_under_lab(invocation.cwd, lab) else {
        return true
      }
    }
  }
  false
}

///|
test "read-only guard blocks mutating moon anywhere; allows read-only commands" {
  // mutating moon — plain, chained either way, and env-prefixed (all bypasses)
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon fmt"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon new app"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon new -- --help"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon info"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon fmt && git diff"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("git diff && moon fmt"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon test --update; true"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon test -u; true"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("FOO=bar moon fmt"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  // a pipe segment that mutates is still caught (pipes parse as Simple)
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon fmt | tee out"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  // a read-only pipe is allowed (no mutating segment)
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("git diff | head"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  // read-only commands — allowed
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon check"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon check --target all"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon test"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon fmt --check"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("git diff origin/main"),
      base_cwd=".",
      scratch_dir=None,
    ),
  )
}

///|
test "the scratch lab re-opens exactly the lab, nothing else" {
  let lab = "/tmp/openseek-explore-lab-x"
  fn blocks(cmd : String) -> Bool {
    review_read_only_blocks(
      @shell_parse.parse_for_policy(cmd),
      base_cwd="/repo",
      scratch_dir=Some(lab),
    )
  }
  // Inside the lab: scaffolding and mutating moon are the point.
  assert_false(blocks("moon new \{lab}/probe"))
  assert_false(blocks("cd \{lab} && moon new probe"))
  assert_false(blocks("cd \{lab}/probe && moon fmt"))
  assert_false(blocks("moon -C \{lab}/probe test --update"))
  assert_false(blocks("cd \{lab} && moon new probe && cd probe && moon check"))
  // Outside (or not provably inside): the original block stands.
  assert_true(blocks("moon fmt"))
  assert_true(blocks("moon new app"))
  assert_true(blocks("moon new /tmp/elsewhere"))
  assert_true(blocks("cd /repo && moon fmt"))
  assert_true(blocks("cd \{lab} && cd /repo && moon fmt"))
  // An in-lab cwd with an out-of-lab scaffold target is the escape the
  // target rule closes.
  assert_true(blocks("cd \{lab} && moon new /repo/pwned"))
  assert_true(blocks("cd \{lab} && moon new ../outside"))
  // Flag values are bare words, not landing spots; a bare-name scaffold
  // lands in the cwd, so the cwd rule decides it.
  assert_false(blocks("moon new \{lab}/probe --user t --name probe"))
  assert_false(blocks("cd \{lab} && moon new probe --user t"))
  assert_true(blocks("moon new probe --user t"))
  // Env prefixes stay out of scope, exactly like the original guard.
  assert_true(blocks("cd \{lab} && FOO=bar moon fmt"))
  // Read-only moon commands never blocked, lab or not.
  assert_false(blocks("moon check"))
  assert_false(blocks("cd /repo && moon test"))
}
