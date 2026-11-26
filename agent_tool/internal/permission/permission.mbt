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
/// Removal callers capture each entry's location and revalidate the tree after approval.
pub(all) enum Target {
  Write(String)
  RemoveEntry(String, location~ : String)
}

///|
/// Authorize one validated operation, never a session or a subtree. Called
/// under the file gate; only the human wait releases it. All affected targets,
/// including descendants of a removed directory, are revalidated before resuming.
/// `target_path` names the operation's root for the approval summary.
/// `reason` adds an operation-specific permission requirement (e.g. deletion).
pub async fn authorize(
  targets : Array[Target],
  target_path~ : String,
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
    for target in targets {
      let (path, verdict) = try {
        match target {
          Write(path) => (path, scope.check(path))
          RemoveEntry(path, location~) =>
            (path, scope.check_entry(path, location))
        }
      } catch {
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
  guard approval is Some(channel) else {
    fail(
      "\{reasons.join("; ")}; operation requires approval, but this session has no approval channel",
    )
  }
  let before = []
  let grants = []
  for target in targets {
    match target {
      Write(path) => {
        let version = snapshot(path, write_scope)
        before.push((path, version))
        grants.push((path, version.destination))
      }
      RemoveEntry(path, location~) => grants.push((path, location))
    }
  }
  let outcome = file_state.without_access(() => {
    channel.ask({
      tool_name,
      detail: "\{target_path} (\{reasons.join("; ")})",
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
  for (path, version) in before {
    guard snapshot(path, write_scope) == version else {
      fail(
        "target changed while awaiting approval; reconsider and request approval again",
      )
    }
  }
  write_scope.map(scope => scope.with_grants(grants))
}
