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
/// The one-operation scope and the observed state of its targets.
struct Authorization {
  scope : @write_scope.WriteScope?
  snapshots : Array[(String, Snapshot)]
}

///|
/// Check the current destination against this operation's effective scope.
pub async fn Authorization::deny_reason(
  self : Authorization,
  path : String,
) -> String? {
  match self.scope {
    Some(scope) => scope.deny_reason(path)
    None => None
  }
}

///|
/// Compare the targets with their authorized snapshots. Call this with the
/// file gate held, after preparing any temporary data and just before mutation.
pub async fn Authorization::recheck(self : Authorization) -> Unit {
  for (path, before) in self.snapshots {
    guard snapshot(path, self.scope) == before else {
      fail(
        "target changed while awaiting approval or preparing the operation; reconsider and retry",
      )
    }
  }
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
      Regular => {
        let file = @fs.open(path, mode=ReadOnly)
        defer file.close()
        let (_, digest) = @file_content.transfer(file)
        File(digest)
      }
      Directory => Directory(@fs.readdir(path, include_hidden=true, sort=true))
      _ => fail("unsupported filesystem target: \{path}")
    }
  }
  { destination, contents, }
}

///|
/// Authorize one validated operation, never a session or a subtree. Called
/// under the file gate; only the human wait releases it. Callers revalidate
/// the returned authorization before mutating their targets.
/// `target_path` names the operation's root for the approval summary.
/// `reason` adds an operation-specific permission requirement (e.g. deletion).
/// `track_changes` also snapshots targets that do not need human approval.
pub async fn authorize(
  paths : Array[String],
  target_path~ : String,
  tool_name~ : String,
  arguments~ : Json,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
  reason? : String,
  track_changes~ : Bool = false,
) -> Authorization {
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
    let snapshots = if track_changes {
      [
        for path in paths => (path, snapshot(path, write_scope))
      ]
    } else {
      []
    }
    return { scope: write_scope, snapshots, }
  }
  guard approval is Some(channel) else {
    fail(
      "\{reasons.join("; ")}; operation requires approval, but this session has no approval channel",
    )
  }
  let snapshots = [ for path in paths => (path, snapshot(path, write_scope)) ]
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
  let scope = write_scope.map(scope => {
    scope.with_grants(
      [
        for (path, before) in snapshots => (path, before.destination)
      ],
    )
  })
  { scope, snapshots, }
}
