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
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request(
        "workspace_symbols",
        payload.to_value(),
      ) catch {
        _ => {
          scheduler.add(dispatch(SymbolsFailed(session~, query~)))
          return
        }
      }
      match decode_symbols(@interop.reply_json_text(reply)) {
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
    // `name`/`path`/`range` are unconditional on the wire (an all-zeros
    // range stands in for a location without one) — a row missing any is
    // malformed. `container` really is optional: omitted for a top-level
    // symbol.
    guard @jsonx.json_text(fields, "name") is Some(name) && !name.is_empty() else {
      continue
    }
    guard @jsonx.json_text(fields, "path") is Some(path) &&
      json_range(fields) is Some(range) else {
      continue
    }
    rows.push(
      symbol_item(
        name,
        container=@jsonx.json_text(fields, "container"),
        path~,
        range~,
      ),
    )
  }
  Some(rows)
}

///|
/// A symbol row's `range` (LSP-shaped, zero-based) as a one-based viewer
/// range; `None` for a malformed one. The host always sends a range — all
/// zeros for a location without one, which lands as the empty range at the
/// document start.
fn json_range(fields : Map[String, Json]) -> @common.Range? {
  guard fields.get("range")
    is Some(Object({ "start": Object(start), "end": Object(end_), .. })) &&
    @jsonx.json_int(start, "line") is Some(start_line) &&
    @jsonx.json_int(start, "col") is Some(start_col) &&
    @jsonx.json_int(end_, "line") is Some(end_line) &&
    @jsonx.json_int(end_, "col") is Some(end_col) else {
    return None
  }
  Some(
    @common.Range::Range(
      start_line + 1,
      start_col + 1,
      end_line + 1,
      end_col + 1,
    ),
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
  container~ : String?,
  path~ : String,
  range~ : @common.Range,
) -> CompletionItem {
  let location = if path.is_empty() {
    ""
  } else {
    "\{path}:\{range.start_line_number}"
  }
  let detail = if container is Some(container) && !container.is_empty() {
    if location.is_empty() {
      container
    } else {
      "\{container} · \{location}"
    }
  } else {
    location
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
