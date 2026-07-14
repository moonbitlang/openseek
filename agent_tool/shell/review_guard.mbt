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
          is_auto_check_moon_subcommand(
            command.argv,
            invocation.subcommand_index,
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
/// --update / ...) anywhere in a `Simple` parse, including `&&`/`;` chains,
/// pipes, and env prefixes — so a review does not reformat or regenerate the
/// tree wholesale. Opaque commands (`TooComplex`: subshells, command
/// substitution) are allowed: a review that runs `moon check`/`moon test` can
/// already trigger pre-build source generation, so chasing every last mutation
/// is not worth crippling the review's ability to investigate.
fn review_read_only_blocks(parsed : @shell_parse.ParseResult) -> Bool {
  match parsed {
    Simple(commands) => commands.any(command_is_mutating_moon)
    _ => false
  }
}

///|
test "read-only guard blocks mutating moon anywhere; allows read-only commands" {
  // mutating moon — plain, chained either way, and env-prefixed (all bypasses)
  assert_true(
    review_read_only_blocks(@shell_parse.parse_for_policy("moon fmt")),
  )
  assert_true(
    review_read_only_blocks(@shell_parse.parse_for_policy("moon info")),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon fmt && git diff"),
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("git diff && moon fmt"),
    ),
  )
  assert_true(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon test --update; true"),
    ),
  )
  assert_true(
    review_read_only_blocks(@shell_parse.parse_for_policy("FOO=bar moon fmt")),
  )
  // a pipe segment that mutates is still caught (pipes parse as Simple)
  assert_true(
    review_read_only_blocks(@shell_parse.parse_for_policy("moon fmt | tee out")),
  )
  // a read-only pipe is allowed (no mutating segment)
  assert_false(
    review_read_only_blocks(@shell_parse.parse_for_policy("git diff | head")),
  )
  // read-only commands — allowed
  assert_false(
    review_read_only_blocks(@shell_parse.parse_for_policy("moon check")),
  )
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("moon check --target all"),
    ),
  )
  assert_false(
    review_read_only_blocks(@shell_parse.parse_for_policy("moon test")),
  )
  assert_false(
    review_read_only_blocks(@shell_parse.parse_for_policy("moon fmt --check")),
  )
  assert_false(
    review_read_only_blocks(
      @shell_parse.parse_for_policy("git diff origin/main"),
    ),
  )
}
