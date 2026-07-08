// The composer's `#` symbol completion: search the active conversation's
// workspace symbol index through the host's `workspace_symbols` op (which
// proxies the workspace's moon-lsp) and fold the matches into completion rows.
// Each reply carries the `session` and `query` it answers, so a reply that lost
// a conversation switch or was overtaken by a later keystroke is discarded.

///|
/// Search `query` against the conversation's workspace symbols and fold the
/// matches back as `SymbolsLoaded`.
fn read_workspace_symbols(
  dispatch : @cmd.Emit[Msg],
  session : String,
  query : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["query"] = query
      set_workspace(payload, workspace)
      let reply = bridge_request("workspace_symbols", payload.to_value()) catch {
        _ => {
          scheduler.add(dispatch(SymbolsFailed(session~, query~)))
          return
        }
      }
      match decode_symbols(reply_json_text(reply)) {
        Some(items) =>
          scheduler.add(dispatch(SymbolsLoaded(session~, query~, items~)))
        None => scheduler.add(dispatch(SymbolsFailed(session~, query~)))
      }
    })
  })
}

///|
/// Parse a `workspace_symbols` reply into completion rows. `None` only for
/// structurally unusable JSON; a malformed row is skipped.
fn decode_symbols(text : String) -> Array[CompletionItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("symbols") is Some(Array(items)) else { return None }
  let rows : Array[CompletionItem] = []
  for item in items {
    guard item is Object(fields) else { continue }
    let name = @transcript.json_text(fields, "name")
    guard !name.is_empty() else { continue }
    rows.push(
      symbol_item(
        name,
        container=@transcript.json_text(fields, "container"),
        path=@transcript.json_text(fields, "path"),
        range=json_range(fields),
      ),
    )
  }
  Some(rows)
}

///|
/// A symbol row's `range` (LSP-shaped, zero-based) as a one-based viewer
/// range. A missing or malformed range collapses to the empty range at the
/// document start — the same shape the host sends for a location without one.
fn json_range(fields : Map[String, Json]) -> @common.Range {
  guard fields.get("range")
    is Some(Object({ "start": Object(start), "end": Object(end_), .. })) else {
    return @common.Range::Range(1, 1, 1, 1)
  }
  @common.Range::Range(
    @transcript.json_int(start, "line", 0) + 1,
    @transcript.json_int(start, "col", 0) + 1,
    @transcript.json_int(end_, "line", 0) + 1,
    @transcript.json_int(end_, "col", 0) + 1,
  )
}

///|
/// Build a symbol's completion row. The label is the bare name; the detail
/// reads as `container · path:line` (each part dropped when blank). Accepting it
/// drops a reference into the composer for the agent — the name in backticks and
/// the location as the clickable `path:line` convention. `range` is one-based
/// (viewer coordinates); an empty range still anchors the reference's line,
/// it just gives the jump nothing to select.
fn symbol_item(
  name : String,
  container~ : String,
  path~ : String,
  range~ : @common.Range,
) -> CompletionItem {
  let location = if path.is_empty() {
    ""
  } else {
    "\{path}:\{range.start_line_number}"
  }
  let detail = match (container.is_empty(), location.is_empty()) {
    (true, _) => location
    (false, true) => container
    (false, false) => "\{container} · \{location}"
  }
  let reference = if location.is_empty() {
    "`\{name}`"
  } else {
    "`\{name}` — \{location}"
  }
  let (target_path, target_range) = if path.is_empty() {
    (None, None)
  } else {
    (Some(path), Some(range))
  }
  {
    label: name,
    detail,
    command: "",
    insert: reference + " ",
    path: target_path,
    range: target_range,
  }
}
