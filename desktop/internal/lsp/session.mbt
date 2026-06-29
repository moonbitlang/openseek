// The LSP language-session layer over a `@jsonrpc.Client`: the initialize
// handshake, document sync, and the hover request. All of it is LSP-specific
// glue expressed as plain `request`/`notify` calls — `initialize` is not a
// special client method, just the first request a session makes.

///|
/// One LSP session over a connected `@jsonrpc.Client` (typically one language
/// server process). Tracks the handshake and which documents have been synced,
/// so callers can drive `initialize` / `sync_document` / `hover` idempotently.
struct Session {
  client : @jsonrpc.Client
  // Documents synced to the server, mapped to the last version sent. A repeat
  // sync of a uri bumps the version with a full-text `didChange`.
  opened : Map[String, Int]
  mut initialized : Bool
}

///|
/// Build a session over an already-connected client.
pub fn Session::new(client : @jsonrpc.Client) -> Session {
  { client, opened: {}, initialized: false }
}

///|
/// Run the `initialize`/`initialized` handshake once, advertising the minimal
/// client capabilities hover needs. Idempotent: later calls are no-ops. Raises
/// if the server rejects `initialize`.
pub async fn Session::initialize(self : Session, root_uri~ : String) -> Unit {
  guard !self.initialized else { return }
  let params : Json = {
    "processId": Json::null(),
    "rootUri": root_uri,
    "capabilities": {
      "textDocument": {
        "hover": { "contentFormat": ["markdown", "plaintext"] },
      },
    },
  }
  self.client.request(method_="initialize", params~) |> ignore
  self.client.notify(method_="initialized", params={})
  self.initialized = true
}

///|
/// Make the server hold the current `text` of `uri`. The first call sends
/// `didOpen`; a later call bumps the version with a full-text `didChange` (the
/// viewer is read-only, so documents are always synced whole).
pub async fn Session::sync_document(
  self : Session,
  uri~ : String,
  language_id~ : String,
  text~ : String,
) -> Unit {
  match self.opened.get(uri) {
    None => {
      self.client.notify(method_="textDocument/didOpen", params={
        "textDocument": {
          "uri": uri,
          "languageId": language_id,
          "version": Json::number(1),
          "text": text,
        },
      })
      self.opened.set(uri, 1)
    }
    Some(version) => {
      let next = version + 1
      self.client.notify(method_="textDocument/didChange", params={
        "textDocument": {
          "uri": uri,
          "version": Json::number(next.to_double()),
        },
        "contentChanges": [{ "text": text }],
      })
      self.opened.set(uri, next)
    }
  }
}

///|
/// Request hover at a zero-based `line`/`character` in `uri`. Best-effort:
/// returns the server's hover result, or `None` when there is nothing to show,
/// the server errors, or the transport has closed. Cancellation propagates.
pub async fn Session::hover(
  self : Session,
  uri~ : String,
  line~ : Int,
  character~ : Int,
) -> Json? {
  let result = self.client.request(method_="textDocument/hover", params={
    "textDocument": { "uri": uri },
    "position": {
      "line": Json::number(line.to_double()),
      "character": Json::number(character.to_double()),
    },
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  if result is Null {
    None
  } else {
    Some(result)
  }
}

///|
/// Query the workspace's symbol index for `query` (a substring match the server
/// performs). Best-effort like `hover`: returns the raw `workspace/symbol`
/// result, or `None` when the server has nothing, errors, or the transport has
/// closed. No document needs to be synced — the request reads the server's
/// project index, not an open buffer. Cancellation propagates.
pub async fn Session::workspace_symbols(
  self : Session,
  query~ : String,
) -> Json? {
  let result = self.client.request(method_="workspace/symbol", params={
    "query": query,
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  if result is Null {
    None
  } else {
    Some(result)
  }
}
