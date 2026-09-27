///|
/// The options a delegated run (`--cancel-on-stdin-eof`) accepts on its
/// command line. A parent launches it with values the parent chose, but the
/// parent may itself be a sandboxed snippet whose sandbox admits the engine by
/// an argv PREFIX: whatever follows that prefix is the snippet's. So a
/// delegated run accepts only options that grant nothing. The host pins its own
/// values (`--dir`, `--session-root`, `--result-root`, `--model`, `--api-url`)
/// in the prefix, and a second copy appended after it cannot win: the parser
/// refuses any option given twice.
let delegated_options : Array[String] = [
  "input-format", "cancel-on-stdin-eof", "kind", "result-file", "result-root", "dir",
  "session", "session-root", "no-session", "model", "api-url", "api-key", "thinking",
  "max-steps", "retry-attempts", "retry-backoff-ms", "approval",
]

///|
/// Settings a delegated run never takes from its environment, which the
/// launching parent controls: each would run a command (`mcp-config`) or read
/// a file (the prompt files, the skills directory) the parent did not grant.
let delegated_ignored_settings : Array[String] = [
  "mcp-config", "system-prompt-file", "system-prompt-addendum-file", "global-skills-dir",
]

///|
/// Refuse a delegated run's command line unless it holds only
/// `delegated_options`; then drop the settings it never takes from the
/// environment, saying so for the MCP servers it will not start.
fn restrict_delegated_run(matches : @argparse.Matches) -> Unit raise {
  for name, source in matches.sources {
    guard source is Argv else { continue }
    guard delegated_options.contains(name) else {
      fail(
        "a delegated run (--cancel-on-stdin-eof) does not take --\{name}: it gets only what its parent's launch grants",
      )
    }
  }
  for name in delegated_ignored_settings {
    guard matches.values.get(name) is Some([value, ..]) && !value.is_blank() else {
      continue
    }
    if name == "mcp-config" {
      @emit.emit(
        McpConfigIgnored(
          reason="a delegated run starts no MCP servers its parent did not grant",
        ),
      )
    }
    matches.values[name] = [""]
  }
}

///|
/// The directory a result file must be written in, when the launch named one:
/// `--result-root`, resolved. With it, `--result-file` must name a new file
/// inside it — the file is never an existing one to replace or remove — so a
/// launcher that pins the root decides where the run may write its result.
async fn check_result_root(
  matches : @argparse.Matches,
  result_file : String?,
) -> String? {
  guard matches.values.get("result-root") is Some([root, ..]) else {
    return None
  }
  guard !root.is_blank() else { fail("--result-root needs a directory") }
  let root = @fs.realpath(root) catch {
    error => fail("--result-root is not a directory: \{error}")
  }
  guard result_file is Some(path) else { return Some(root) }
  let parent = @path.Path(path).dirname().to_string()
  let parent = @fs.realpath(if parent == "" { "." } else { parent }) catch {
    error => fail("--result-file's directory does not exist: \{error}")
  }
  guard parent == root ||
    parent.has_prefix("\{root}/") ||
    parent.has_prefix("\{root}\\") else {
    fail("--result-file must be inside --result-root \{root}")
  }
  guard !@fs.exists(path) else {
    fail("--result-file must name a new file: \{path} already exists")
  }
  Some(root)
}
