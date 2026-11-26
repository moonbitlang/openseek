///|
#derive(Eq)
priv enum Contents {
  Missing
  File(String)
  Directory(Array[String])
}

///|
#derive(Eq)
priv struct Snapshot {
  destination : String
  contents : Contents
}

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
        File(@crypto.bytes_to_hex_string(@crypto.sha256(@fs.read_binary(path))))
      Directory => Directory(@fs.readdir(path, include_hidden=true, sort=true))
      _ => fail("unsupported filesystem target: \{path}")
    }
  }
  { destination, contents, }
}

///|
/// Authorize one validated operation, never a session or a subtree. Called
/// under the file gate; only the human wait releases it.
/// `target_path` names the operation's root for the approval summary.
pub async fn authorize(
  paths : Array[String],
  target_path~ : String,
  tool_name~ : String,
  arguments~ : Json,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @write_scope.WriteScope? {
  let reasons : Array[String] = []
  if write_scope is Some(scope) {
    for path in paths {
      let verdict = scope.check(path) catch {
        error => fail("invalid write target: \{error}")
      }
      if verdict is Some(message) {
        reasons.push("write blocked: \{path}: \{message}")
      }
    }
  }
  if reasons.is_empty() {
    return write_scope
  }
  let ask = prepare_approval(
    target_path~,
    tool_name~,
    arguments~,
    file_state~,
    approval?,
    reason=reasons.join("; "),
  )
  let before : Array[Snapshot] = []
  for path in paths {
    before.push(snapshot(path, write_scope))
  }
  ask()
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

///|
/// Check for an approval channel before capturing any additional state.
/// Calling the returned action releases the file gate for the human wait.
pub fn prepare_approval(
  target_path~ : String,
  tool_name~ : String,
  arguments~ : Json,
  file_state~ : @agent_tool.FileStateMap,
  approval? : @agent_runtime.ApprovalChannel,
  reason~ : String,
) -> (async () -> Unit) raise {
  guard approval is Some(channel) else {
    fail(
      "\{reason}; operation requires approval, but this session has no approval channel",
    )
  }
  () => {
    let outcome = file_state.without_access(() => {
      channel.ask({
        tool_name,
        detail: "\{target_path} (\{reason})",
        body: Some(arguments.stringify(indent=2)),
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
  }
}
