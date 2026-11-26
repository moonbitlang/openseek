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
/// A removal is authorized at the captured location of its root entry.
pub(all) enum Target {
  Write(String)
  RemoveEntry(String, location~ : String)
}

///|
/// Authorize one operation. Only the human wait releases the file gate.
/// `reason` adds an operation-specific permission requirement (e.g. deletion).
pub async fn authorize(
  target : Target,
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
  let path = match target {
    Write(path) | RemoveEntry(path, ..) => path
  }
  if write_scope is Some(scope) {
    let verdict = try {
      match target {
        Write(_) => scope.check(path)
        RemoveEntry(_, location~) => scope.check_entry(path, location)
      }
    } catch {
      error => fail("invalid write target: \{error}")
    }
    if verdict is Some(message) {
      reasons.push("write blocked: \{path}: \{message}")
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
  let before = match target {
    Write(_) => Some(snapshot(path, write_scope))
    RemoveEntry(_, ..) => None
  }
  let outcome = file_state.without_access(() => {
    channel.ask({
      tool_name,
      detail: "\{path} (\{reasons.join("; ")})",
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
  if before is Some(version) {
    guard snapshot(path, write_scope) == version else {
      fail(
        "target changed while awaiting approval; reconsider and request approval again",
      )
    }
    return write_scope.map(scope => {
      scope.with_grants([(path, version.destination)])
    })
  }
  write_scope
}
