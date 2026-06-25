// Host-side LSP hover backing the editor side-panel: one `moon-lsp --stdio` per
// conversation workspace, spawned lazily and reused. The host reads the file
// from disk (the same sandboxed path the viewer shows) and asks the language
// server for hover at a position. Everything is best-effort — no workspace yet,
// a failed spawn, a server error, or a non-text file all just yield no tooltip.
//
// moon-lsp is spawned as an orphan rather than into a task group: the pull-based
// `@jsonrpc.Client` needs no background reader, so the only thing to keep alive
// between hovers is the process, and it exits on its own when the host closes
// its stdin at shutdown.

///|
/// One language server bound to a conversation's workspace.
priv struct LspWorkspace {
  session : @lsp.Session
  // Last text synced per file uri, so an unchanged file is not re-sent.
  synced : Map[String, String]
}

///|
/// Lazily-started `moon-lsp` instances, keyed by conversation session id.
priv struct LspManager {
  command : String
  workspaces : Map[String, LspWorkspace]
  // Serializes lazy workspace creation so two concurrent hovers don't spawn two
  // servers for the same conversation.
  create_lock : @semaphore.Semaphore
}

///|
fn new_lsp_manager(command? : String = "moon-lsp") -> LspManager {
  { command, workspaces: {}, create_lock: Semaphore(1, initial_value=1) }
}

///|
/// Resolve the file under the conversation's workspace, ensure its server is
/// running, sync the file if its text changed, and request hover.
async fn lsp_hover_op(
  manager : LspManager,
  payload : LspHoverPayload,
) -> LspHoverReply {
  guard @engine.resolve_in_workspace(payload.session, payload.path)
    is Some(file) else {
    raise HostError("path is outside the conversation workspace")
  }
  guard workspace_for(manager, payload.session) is Some(workspace) else {
    return no_hover()
  }
  guard read_text(file) is Some(text) else { return no_hover() }
  let uri = file_uri(file.to_string())
  // Re-sync only when the file's text actually changed since the last hover.
  if !(workspace.synced.get(uri) is Some(synced) && synced == text) {
    workspace.session.sync_document(uri~, language_id="moonbit", text~)
    workspace.synced.set(uri, text)
  }
  parse_hover(
    workspace.session.hover(
      uri~,
      line=payload.line,
      character=payload.character,
    ),
  )
}

///|
/// The conversation's language server, started on first use. `None` when the
/// workspace does not exist yet or the server could not be spawned.
async fn workspace_for(manager : LspManager, session : String) -> LspWorkspace? {
  if manager.workspaces.get(session) is Some(workspace) {
    return Some(workspace)
  }
  manager.create_lock.acquire()
  defer manager.create_lock.release()
  // Another hover may have created it while we waited for the lock.
  if manager.workspaces.get(session) is Some(workspace) {
    return Some(workspace)
  }
  guard spawn_workspace(manager, session) is Some(workspace) else {
    return None
  }
  manager.workspaces.set(session, workspace)
  Some(workspace)
}

///|
/// Spawn `moon-lsp` in the conversation's workspace directory and run the
/// initialize handshake. `None` if there is no workspace directory yet or the
/// process could not start.
async fn spawn_workspace(
  manager : LspManager,
  session : String,
) -> LspWorkspace? {
  guard @engine.resolve_in_workspace(session, "") is Some(dir) else {
    return None
  }
  let directory = dir.to_string()
  // The workspace directory is created on a conversation's first run; before
  // then there is nothing for the server to analyze.
  guard @fs.exists(directory) else { return None }
  let (child_stdin, stdin_writer) = @process.write_to_process()
  let (stdout_reader, child_stdout) = @process.read_from_process()
  (@process.spawn_orphan(
    manager.command,
    ["--stdio"],
    stdin=child_stdin,
    stdout=child_stdout,
    cwd=directory,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  })
  |> ignore
  let client = @jsonrpc.Client::new(
    @lsp.StreamTransport::new(stdout_reader, stdin_writer),
  )
  let session_object = @lsp.Session::new(client)
  // A failed handshake is non-fatal: later hovers simply return nothing.
  session_object.initialize(root_uri=file_uri(directory)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  Some({ session: session_object, synced: {} })
}

///|
/// Read a workspace file as text. `None` for an unreadable or non-UTF-8 (binary)
/// file, which has no meaningful hover anyway.
async fn read_text(file : @path.Path) -> String? {
  let data = @fs.read_file(file.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  Some(data.text()) catch {
    _ => None
  }
}

///|
/// Build a `file:` URI for an absolute path. On a Unix path `/a/b` this yields
/// `file:///a/b`. (Native targets are macOS/Linux; Windows paths would need a
/// drive prefix and percent-encoding.)
fn file_uri(absolute_path : String) -> String {
  "file://" + absolute_path
}

///|
/// An empty hover reply — "nothing to show here".
fn no_hover() -> LspHoverReply {
  {
    value: "",
    markdown: false,
    has_range: false,
    start_line: 0,
    start_character: 0,
    end_line: 0,
    end_character: 0,
  }
}

///|
/// Normalize an LSP hover result into the flat reply the front-end consumes.
/// `None`, an empty value, or an unrecognized shape all collapse to `no_hover`.
fn parse_hover(hover : Json?) -> LspHoverReply {
  guard hover is Some(json) else { return no_hover() }
  let (value, markdown) = parse_contents(json)
  guard !value.is_empty() else { return no_hover() }
  match parse_range(json) {
    Some((start_line, start_character, end_line, end_character)) =>
      {
        value,
        markdown,
        has_range: true,
        start_line,
        start_character,
        end_line,
        end_character,
      }
    None =>
      {
        value,
        markdown,
        has_range: false,
        start_line: 0,
        start_character: 0,
        end_line: 0,
        end_character: 0,
      }
  }
}

///|
/// Extract the hover text and whether it is markdown from an LSP `Hover`'s
/// `contents`, which may be a `MarkupContent`, a `MarkedString` (plain or
/// `{language, value}`), or an array of those.
fn parse_contents(hover : Json) -> (String, Bool) {
  guard hover is { "contents": contents, .. } else { return ("", false) }
  match contents {
    { "kind": String(kind), "value": String(value), .. } =>
      (value, kind == "markdown")
    { "value": String(value), .. } => (value, false)
    String(value) => (value, false)
    [first, ..] =>
      match first {
        { "value": String(value), .. } => (value, false)
        String(value) => (value, false)
        _ => ("", false)
      }
    _ => ("", false)
  }
}

///|
/// Extract the hover's optional range (the symbol the tooltip describes).
fn parse_range(hover : Json) -> (Int, Int, Int, Int)? {
  guard hover
    is {
      "range": {
        "start": {
          "line": Number(start_line, ..),
          "character": Number(start_character, ..),
          ..
        },
        "end": {
          "line": Number(end_line, ..),
          "character": Number(end_character, ..),
          ..
        },
        ..
      },
      ..
    } else {
    return None
  }
  Some(
    (
      start_line.to_int(),
      start_character.to_int(),
      end_line.to_int(),
      end_character.to_int(),
    ),
  )
}
