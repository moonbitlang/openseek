# Shell Command Policy

This internal package contains the command-routing policy used by the `shell`
tool before it runs `sh -c`.

The policy redirects two command shapes that an agent should not run through
shell:

- the bare tool name `moon_cmd`, typed as a shell command — it is not an
  executable and should be the real `moon ...` subcommand run through shell;
- `sed -i` (in-place file editing) — it silently misapplies edits often enough
  to be untrustworthy, so the agent is sent to line-anchored `edit` (or
  `multi_edit` for several fixes in one file).

Everything else, including `moon check` and read-only `sed` (`sed -n '1,5p'`,
`... | sed s/a/b/`), runs normally.

This package is not a security sandbox. It is a local automation guardrail for a
trusted agent. The shell tool can run arbitrary commands; this package only
redirects the `moon_cmd` typo and `sed -i` editing before execution.

## Enforced Policy

`moonbit_command_policy_error(cmd)` returns `Some(message)` when the command
should be blocked by `shell`, and `None` when `shell` may continue.

The current policy blocks:

| Command shape | Reason |
| --- | --- |
| `moon_cmd ...` | `moon_cmd` is a tool name, not an executable shell command; run `moon ...` directly. |
| `sed -i ...` (incl. `--in-place`, `-i.bak`, `-Ei`) | In-place file editing is unreliable; use line-anchored `edit` (or `multi_edit` for several fixes in one file) for source changes. |

The policy allows:

| Command shape | Reason |
| --- | --- |
| `moon check` | Type-check for compiler feedback; runs through shell like any other `moon` subcommand. |
| `moon test`, `moon run`, `moon info`, `moon fmt`, `moon build` | One-shot Moon commands run through shell. |
| `sed -n '1,5p' f`, `... \| sed s/a/b/` | Read-only `sed` (no in-place flag) remains in shell. |
| `git status --short` | Non-MoonBit commands remain in shell. |
| `printf hi \| wc -c` | Shell-specific pipelines remain in shell. |

## Detection Strategy

Detection is **precise, not heuristic**, and prefers **no false positives**
(never block a command that is not actually an in-place edit) over exhaustive
recall:

- Parse the command with the internal shell policy parser.
- Reject `moon_cmd` when it is a statically visible simple command name,
  including in flat compounds such as `cd demo && moon_cmd check`.
- Reject `sed` carrying an in-place flag when it is a statically visible simple
  command. Because this runs on the structured parse, it correctly handles
  `env`/`command`/`builtin` wrappers (via `command_index`), a path-qualified
  `/usr/bin/sed` (via basename), quotes and separators (the parser unquotes argv
  and splits commands), and `sed`'s own option grammar — `grep -i sed`,
  `env -i sed ...`, and a script file named `-i` (`sed -f -i file`) are left
  alone, and `-i` is read off `sed`'s own arguments only.
- When the structured parse **fails** (globs, expansions, here-documents — e.g.
  `sed -i 's/a/b/' *.mbt`), only the narrow leading-word `moon_cmd` typo check
  runs. `sed -i` is **not** matched there.

This is not a security sandbox and not a full POSIX shell interpreter. The
sed guard is intentionally limited to commands the parser can analyze, because a
rough text scan of an unparseable command produces false positives — a quoted
`|sed -i` inside `grep 'a|sed -i' *.x`, or a here-document body that writes
`sed -i` to a script — and a false block is worse than missing a globbed edit.
The outer `shell` tool still stops TooComplex in-place `sed` commands before
execution, including shell loops where source paths are read indirectly from a
file. Other source-specific TooComplex shapes may also be stopped before
execution or at runtime with the source-write sandbox.

Known parser-policy gaps that are therefore *allowed* past this package (false
negatives, by design):

- any `sed -i` whose command parses as `TooComplex` and is not in a recognizable
  command position, such as after `do`, `then`, `if`, `-exec`, or `-execdir`;
- `sed` that is not a command's leading word — `find ... -exec sed -i`,
  `xargs sed -i`;
- `sed -i` behind an `env` option that changes command interpretation or cwd,
  e.g. `env -S 'sed -i ...'` or `env -C pkg sed -i ...`
  (`command_name()` stays `env`).

The outer `shell` tool recovers the common globbed, `find -exec`, and shell-loop
cases with a conservative text fallback. A cleaner lower-level recovery would be
to teach the lexer to treat an unquoted glob as an opaque word, so the command
stays `Simple` and this parser-policy package can own the precise path; that
shared-parser change is left for a separate PR.

## Examples

```moonbit check
///|
test "command policy allows moon subcommands through shell" {
  assert_true(
    @command_policy.moonbit_command_policy_error("moon check") is None,
  )
  assert_true(
    @command_policy.moonbit_command_policy_error("cd demo && moon check")
    is None,
  )
  assert_true(
    @command_policy.moonbit_command_policy_error("moon test --update") is None,
  )
  assert_true(
    @command_policy.moonbit_command_policy_error(
      "DEEPSEEK_MODEL=x moon run cmd/main",
    )
    is None,
  )
}
```

```moonbit check
///|
test "command policy redirects the moon_cmd tool name" {
  guard @command_policy.moonbit_command_policy_error("moon_cmd check")
    is Some(message) else {
    fail("expected moon_cmd to be redirected")
  }
  assert_true(message.contains("moon_cmd is not a shell command"))
  assert_true(
    @command_policy.moonbit_command_policy_error("git status --short") is None,
  )
}
```

## Operational Guidance

Run `moon check` through `shell` for compiler feedback — it is much faster than
`moon build` or `moon test` (it skips code generation). Also use shell for
one-shot commands such as `moon test`, `moon run`, `moon info`, `moon fmt`,
`moon build`, `moon update`, `moon add`, and `moon remove`, and the shell tool's
`cwd` field instead of `cd ... &&`.
