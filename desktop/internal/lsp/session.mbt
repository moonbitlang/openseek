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
  // The server's latest `publishDiagnostics` per document uri (the raw LSP
  // `diagnostics` array). A late subscriber — the editor opening a file the
  // server already analyzed — reads the current set here rather than waiting for
  // the next publish.
  diagnostics : Map[String, Json]
  mut initialized : Bool
  // Called when the server publishes diagnostics for a uri, with the raw
  // `diagnostics` array. The default drops them; a host that forwards them to
  // the editor installs its own via `on_publish_diagnostics`.
  mut on_publish : (String, Json) -> Unit
}

///|
/// Build a session over an already-connected client. Wires the client's
/// notification handler to capture `textDocument/publishDiagnostics`.
pub fn Session::new(client : @jsonrpc.Client) -> Session {
  let session = {
    client,
    opened: {},
    diagnostics: {},
    initialized: false,
    on_publish: (_, _) => (),
  }
  client.set_notification_handler((method_, params) => {
    guard method_ == "textDocument/publishDiagnostics" else { return }
    guard params is { "uri": String(uri), "diagnostics": diagnostics, .. } else {
      return
    }
    session.diagnostics.set(uri, diagnostics)
    (session.on_publish)(uri, diagnostics)
  })
  session
}

///|
/// Install the handler run when the server publishes diagnostics for a uri
/// (uri, raw `diagnostics` array). Replaces any previous handler. It runs on the
/// client's reader task, so it must not block on I/O — a host forwarding to the
/// editor should hand off over a queue.
pub fn Session::on_publish_diagnostics(
  self : Session,
  handler : (String, Json) -> Unit,
) -> Unit {
  self.on_publish = handler
}

///|
/// Whether the underlying transport has ended (the server exited or its pipe
/// closed). A closed session answers nothing further; a pool holding one
/// should retire it and start a fresh server.
pub fn Session::is_closed(self : Session) -> Bool {
  self.client.is_closed()
}

///|
/// The server's latest diagnostics for `uri` (the raw LSP `diagnostics` array),
/// or `None` if it has published none.
pub fn Session::diagnostics_for(self : Session, uri~ : String) -> Json? {
  self.diagnostics.get(uri)
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
