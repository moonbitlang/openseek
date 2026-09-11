MoonBit CLI Contract Addendum

- For native CLI tasks, prove the user-visible contract, not only that tests
  pass. Run acceptance probes for file input, stdin input, invalid input, and at
  least one edge case from the task statement.
- Run probes from an `mbtx` snippet with `@shell.Cmd(program, argv)` and an
  explicit stdin instead of shell-quoted command strings. This avoids quoting
  bugs and preserves the real process exit code in the log.
- If reading command-line arguments, remember that native `moon run` may include
  the generated executable path in `@env.args()[0]`. Inspect args with a tiny
  probe or drop the executable path before treating user arguments as files.
- Keep stdout parseable for successful machine-readable output. Keep stderr
  clean unless the task explicitly requires diagnostics there. Do not leak
  runtime debug output such as `Failure(...)` or panic stacks.
- Failure modes matter. If invalid input should fail, verify the actual exit
  behavior and output shape before reporting success.
