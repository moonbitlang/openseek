///|
/// `openseek-edit` — the `edit` agent tool as a standalone program, so a
/// program tool call (an `mbtx` snippet) can compose edits itself instead of
/// the model emitting one tool call per change. It is a thin main over
/// `agent_tool/edit`: the same decode, the same parse gate, the same response
/// text as the in-process tool, because it runs that package's own executor
/// rather than reimplementing it.
///
/// The edit arguments are the tool's own JSON object, read from `argv[1]` when
/// present and otherwise from stdin (stdin keeps large payloads off the command
/// line). The write confinement is deliberately NOT part of that payload: a
/// caller that authors the JSON must not be able to widen its own scope, so the
/// bound comes from the environment instead.
///
/// - `OPENSEEK_EDIT_ROOT` — workspace root. When set, every write is confined
///   to it by a `write_scope`; when unset the program runs unconfined against
///   the working directory, which is the standalone (non-agent) mode.
/// - `OPENSEEK_EDIT_ALLOWED_PATHS` — newline-separated paths that narrow that
///   scope further, matching a worker subagent's `allowed_paths`. Ignored
///   without `OPENSEEK_EDIT_ROOT`, since there is no root to resolve against.
///
/// Exit status is 0 when the tool responded normally and 1 when it reported an
/// error, so a snippet can branch on the result; the tool's own message goes to
/// stdout either way, error or not.
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("error: \{error}\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}

///|
/// Decode the arguments, build the tool with its environment-supplied
/// confinement, and run the tool's own executor.
async fn run() -> Unit {
  let arguments = @json.parse(payload_text())
  let root = match @env.get_env_var("OPENSEEK_EDIT_ROOT") {
    Some(value) if value.trim() != "" => "\{value.trim()}"
    _ => ""
  }
  let definition = if root == "" {
    @edit_tool.definition(workspace_root=".")
  } else {
    let write_scope = Some(confinement(root))
    @edit_tool.definition(workspace_root=root, write_scope?)
  }
  let action = match definition.execute {
    Async(execute) => execute(arguments)
    Sync(execute) => execute(arguments)
  }
  match action {
    Respond(output) => {
      println(output.content)
      if output.is_error {
        @sys.exit(1)
      }
    }
    // `edit` only ever responds; a control action would mean the definition
    // changed shape under us, which is a bug rather than a failed edit.
    Control(_) => {
      @stdio.stderr.write("error: edit returned a control action\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}

///|
/// The write scope for `root`, narrowed by `OPENSEEK_EDIT_ALLOWED_PATHS` when
/// that is set. A malformed allowlist fails the run rather than silently
/// widening to the whole root: a confinement that cannot be built is not a
/// confinement.
async fn confinement(root : String) -> @write_scope.WriteScope {
  let created = match allowed_paths() {
    Some(allowed_paths) =>
      @write_scope.WriteScope::create(root~, allowed_paths~)
    None => @write_scope.WriteScope::create(root~)
  }
  match created {
    Ok(scope) => scope
    Err(reason) => fail("cannot confine writes to '\{root}': \{reason}")
  }
}

///|
/// The `OPENSEEK_EDIT_ALLOWED_PATHS` entries, or `None` when the variable is
/// unset or holds only blank lines.
fn allowed_paths() -> Array[String]? {
  guard @env.get_env_var("OPENSEEK_EDIT_ALLOWED_PATHS") is Some(raw) else {
    return None
  }
  let paths = []
  for line in raw.split("\n") {
    let path = line.trim()
    if path != "" {
      paths.push("\{path}")
    }
  }
  if paths.is_empty() {
    None
  } else {
    Some(paths)
  }
}

///|
/// The raw JSON arguments: `argv[1]` when given, otherwise all of stdin.
async fn payload_text() -> String {
  match @env.args() {
    [_, argument, ..] => argument
    _ => {
      let text = StringBuilder()
      while @stdio.stdin.read_until("\n") is Some(line) {
        text.write_string(line)
      }
      text.to_string()
    }
  }
}
