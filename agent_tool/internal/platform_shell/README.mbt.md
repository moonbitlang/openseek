# agent_tool/internal/platform_shell

The platform shell pair: `program` (`sh`, or `powershell.exe` on Windows) and
`args(cmd)`, which makes that shell interpret `cmd` as command text. The
`shell` tool uses the pair for plain launches, and `internal/sandbox` builds
its `sandbox-exec` command line around the same pair — so a command means the
same thing whether or not a sandbox wraps it.

The values are platform-`#cfg`'d, so assertions here stay portable by
checking shape rather than spelling:

```mbt check
///|
#cfg(not(platform="windows"))
test "args carries the command text through as the final argument" {
  // ["-c", cmd] on POSIX, ["-NoProfile", "-Command", cmd] on Windows —
  // either way the command text is the last argument, verbatim.
  let args = @platform_shell.args("printf 'hi there'")
  inspect(args[args.length() - 1], content="printf 'hi there'")
  inspect(@platform_shell.program.is_empty(), content="false")
}
```
