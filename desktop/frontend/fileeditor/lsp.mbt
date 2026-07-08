// The viewer's hover provider: when the pointer rests on a symbol in a `.mbt`
// file, ask the host's `hover` op (which proxies the workspace's moon-lsp) and
// render the reply as a viewer tooltip. The host owns the language server, so
// the front-end only marshals the position and decodes the reply.

///|
/// The scheme prefixing viewer model URIs. The hover provider only ever
/// receives the `TextModel`, never the app `Model`, so the URI carries the
/// file's host-resolved absolute path (percent-encoded) — the whole address
/// the path-routed `hover` op needs.
const ModelUriPrefix : String = "openseek://"

///|
/// A viewer model URI this app minted (`openseek://` + the file's
/// percent-encoded absolute path) — the document key the viewer's services
/// (feedback, markers) index by. The newtype keeps arbitrary strings and
/// filesystem paths out of APIs that mean a viewer document; mint one with
/// `ModelUri::of`, or wrap only a string that `parse_model_uri` just accepted.
/// Read-only outside this package: the main package carries one in
/// `EditorCommentAdded` and hands it back to `remove_editor_feedback`, but
/// only this package mints them.
pub struct ModelUri(String)

///|
pub fn ModelUri::of(absolute_path : @pathx.Absolute) -> ModelUri {
  ModelUri(ModelUriPrefix + @uri.encode_path(absolute_path.0))
}

///|
/// Decode a viewer model URI into the absolute path it names; `None` for a
/// URI this app did not mint, which has no host op to route to anyway.
fn parse_model_uri(uri : String) -> @pathx.Absolute? {
  guard uri.strip_prefix(ModelUriPrefix) is Some(rest) else { return None }
  let path = @uri.decode(rest)
  guard !path.is_empty() else { return None }
  Some(Absolute(path))
}

///|
priv struct LspHoverProvider {}

///|
impl @language.HoverProvider for LspHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  token,
) {
  // v1 covers MoonBit only; other languages have no server behind the op.
  guard model.language_id == "moonbit" else { return None }
  guard !token.is_cancellation_requested() else { return None }
  guard parse_model_uri(model.uri.value) is Some(path) else { return None }
  let reply = request_hover(
    path~,
    // The viewer's Position is 1-based; the host op speaks 0-based LSP coords.
    line=position.line_number - 1,
    character=position.column - 1,
  ) catch {
    _ => return None
  }
  decode_hover(@interop.reply_json_text(reply), model)
}

///|
/// Register the hover provider on the shared language registry.
fn register_hover_provider() -> Unit {
  @languages.languages.register_hover_provider(
    @language.LanguageSelector::LanguageId("moonbit"),
    LspHoverProvider::{  },
  )
  |> ignore
}

///|
/// Call the host `hover` op for the absolute `path` at a zero-based
/// `line`/`character`.
async fn request_hover(
  path~ : @pathx.Absolute,
  line~ : Int,
  character~ : Int,
) -> @js.Value {
  let payload = @js.Object::new()
  payload["path"] = path.0
  payload["line"] = line
  payload["character"] = character
  @interop.bridge_request("hover", payload.to_value())
}

///|
/// Decode the host's flat hover reply into a viewer `Hover`. `None` when the
/// reply has no text. The range comes back as LSP line/character positions,
/// which the model's snapshot converts to the document offsets `Range` uses.
fn decode_hover(text : String, model : @model.TextModel) -> @language.Hover? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  let value = @transcript.json_text(reply, "value")
  guard !value.is_empty() else { return None }
  let content = if reply.get("markdown") is Some(True) {
    @language.HoverContent::Markdown(value)
  } else {
    @language.HoverContent::PlainText(value)
  }
  Some(@language.Hover::{
    range: hover_range(reply, model),
    contents: [content],
  })
}

///|
/// The offset range the tooltip highlights. Falls back to an empty range at the
/// document start when the reply carries none.
fn hover_range(
  reply : Map[String, Json],
  model : @model.TextModel,
) -> @common.Range {
  let snapshot = model.snapshot()
  guard reply.get("has_range") is Some(True) else {
    let origin = snapshot.get_position_at(0)
    return @common.Range::from_positions(origin, origin)
  }
  // The reply carries 0-based LSP positions; shift to the viewer's 1-based
  // line/column, then round-trip through offsets so the range stays clamped.
  let start = snapshot.get_offset_at(
    json_int(reply, "start_line") + 1,
    json_int(reply, "start_character") + 1,
  )
  let end = snapshot.get_offset_at(
    json_int(reply, "end_line") + 1,
    json_int(reply, "end_character") + 1,
  )
  @common.Range::from_positions(
    snapshot.get_position_at(start),
    snapshot.get_position_at(end),
  )
}

///|
/// Read an integer field, defaulting to 0 when missing or non-numeric.
fn json_int(fields : Map[String, Json], key : String) -> Int {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
/// Tell the host the viewer now shows the file at `absolute`, so its language
/// server syncs the file and starts publishing diagnostics, then apply whatever
/// it already has. Best-effort: a failed call just leaves the file without
/// squiggles; live re-analysis still arrives as `diagnostics` events. Routes by
/// absolute path exactly like hover — v1 covers MoonBit only, the only language
/// with a server behind the op.
fn request_diagnostics(
  dispatch : @cmd.Emit[Msg],
  absolute : @pathx.Absolute,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = request_lsp_open(path=absolute) catch { _ => return }
      let diagnostics = reply_diagnostics(@interop.reply_json_text(reply))
      scheduler.add(dispatch(DiagnosticsPublished(absolute~, diagnostics~)))
    })
  })
}

///|
/// Call the host `lsp_open` op for the absolute `path`.
async fn request_lsp_open(path~ : @pathx.Absolute) -> @js.Value {
  let payload = @js.Object::new()
  payload["path"] = path.0
  @interop.bridge_request("lsp_open", payload.to_value())
}

///|
/// The `diagnostics` array from an `lsp_open` reply; an empty array when the
/// reply is malformed or the server has none.
fn reply_diagnostics(text : String) -> Json {
  let json = @json.parse(text) catch { _ => return [] }
  guard json is Object(reply) && reply.get("diagnostics") is Some(diagnostics) else {
    return []
  }
  diagnostics
}

///|
/// Decode a raw LSP `diagnostics` array into the viewer's `Diagnostic` shape.
/// LSP positions are 0-based; the viewer's ranges are 1-based, so each bound
/// shifts by one. An item without a range or message is skipped.
fn decode_diagnostics(diagnostics : Json) -> Array[@language.Diagnostic] {
  guard diagnostics is Array(items) else { return [] }
  let result : Array[@language.Diagnostic] = []
  for item in items {
    guard item is Object(fields) else { continue }
    guard fields.get("range")
      is Some(Object({ "start": Object(start), "end": Object(end_), .. })) else {
      continue
    }
    let message = @transcript.json_text(fields, "message")
    guard !message.is_empty() else { continue }
    result.push(@language.Diagnostic::{
      range: @common.Range::Range(
        json_int(start, "line") + 1,
        json_int(start, "character") + 1,
        json_int(end_, "line") + 1,
        json_int(end_, "character") + 1,
      ),
      severity: diagnostic_severity(json_int(fields, "severity")),
      message,
      tags: decode_diagnostic_tags(fields),
    })
  }
  result
}

///|
/// Map an LSP `DiagnosticSeverity` (`Error=1 … Hint=4`) to the viewer's. An
/// absent or unknown severity reads as `Error`, LSP's own fallback.
fn diagnostic_severity(value : Int) -> @language.DiagnosticSeverity {
  match value {
    2 => Warning
    3 => Info
    4 => Hint
    _ => Error
  }
}

///|
/// Decode the optional LSP `tags` array (`Unnecessary=1`, `Deprecated=2`) that
/// drives the viewer's faded/struck-through rendering. `None` when there are
/// none, so the diagnostic carries no tag list at all.
fn decode_diagnostic_tags(
  fields : Map[String, Json],
) -> Array[@language.DiagnosticTag]? {
  guard fields.get("tags") is Some(Array(items)) else { return None }
  let tags : Array[@language.DiagnosticTag] = []
  for item in items {
    match item {
      Number(1, ..) => tags.push(Unnecessary)
      Number(2, ..) => tags.push(Deprecated)
      _ => ()
    }
  }
  if tags.is_empty() {
    None
  } else {
    Some(tags)
  }
}
