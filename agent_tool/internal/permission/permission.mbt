///|
priv enum Contents {
  Missing
  File(String)
  Directory(Array[String])
} derive(Eq)

///|
priv struct Snapshot {
  destination : String
  contents : Contents
} derive(Eq)

///|
async fn snapshot(path : String, scope : @write_scope.WriteScope?) -> Snapshot {
  let destination = match scope {
    Some(scope) => scope.destination(path)
    None => @fs.realpath(path)
  }
  let contents = if !@fs.exists(path) {
    Missing
  } else {
    match @fs.kind(path) {
      Regular =>
        File(
          @crypto.bytes_to_hex_string(
            @crypto.sha256(@fs.read_file(path).binary()),
          ),
        )
      Directory => Directory(@fs.readdir(path, include_hidden=true, sort=true))
      _ => fail("unsupported filesystem target: \{path}")
    }
  }
  { destination, contents, }
}

///|
/// Authorize one validated operation, never a session or a subtree. Called
/// under the file gate; only the human wait releases it. All affected targets,
/// including in-scope targets in a batch, are revalidated before resuming.
/// `reason` adds an operation-specific permission requirement (e.g. deletion).
pub async fn authorize(
  paths : Array[String],
  tool_name~ : String,
  arguments~ : Json,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
  reason? : String,
) -> @write_scope.WriteScope? {
  let reasons : Array[String] = []
  if reason is Some(reason) {
    reasons.push(reason)
  }
  if write_scope is Some(scope) {
    for path in paths {
      match scope.check(path) {
        Err(message) => fail("invalid write target: \{message}")
        Ok(Some(message)) => reasons.push("write blocked: \{path}: \{message}")
        Ok(None) => ()
      }
    }
  }
  if reasons.is_empty() {
    return write_scope
  }
  guard approval is Some(channel) else {
    fail(
      "\{reasons.join("; ")}; operation requires approval, but this session has no approval channel",
    )
  }
  let before : Array[Snapshot] = []
  for path in paths {
    before.push(snapshot(path, write_scope))
  }
  let outcome = file_state.without_access(() => {
    channel.ask({
      tool_name,
      detail: "Approve this one \{tool_name} operation: \{reasons.join("; ")}. No other operations or sandbox changes are granted.",
      body: Some(arguments.stringify()),
    })
  })
  match outcome {
    AllowedOnce => ()
    Rejected =>
      fail(
        "operation approval rejected; no changes made. Do not retry without new user instructions",
      )
    Cancelled => fail("operation approval cancelled; no changes made")
    Unavailable => fail("operation approval unavailable; no changes made")
  }
  for i, path in paths {
    guard snapshot(path, write_scope) == before[i] else {
      fail(
        "target changed while awaiting approval; reconsider and request approval again",
      )
    }
  }
  write_scope.map(scope => {
    scope.with_grants([ for i, path in paths => (path, before[i].destination) ])
  })
}
