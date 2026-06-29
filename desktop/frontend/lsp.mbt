// The viewer's hover provider: when the pointer rests on a symbol in a `.mbt`
// file, ask the host's `hover` op (which proxies the workspace's moon-lsp) and
// render the reply as a viewer tooltip. The host owns the language server, so
// the front-end only marshals the position and decodes the reply.

///|
/// The session whose file the viewer currently shows. The hover provider needs
/// it to address the host op, but a `TextModel` carries only the file path — so
/// it is stashed here whenever a file is shown.
let current_session : Ref[String] = Ref("")

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
  let session = current_session.val
  guard !session.is_empty() else { return None }
  let reply = request_hover(
    session~,
    path=strip_model_uri(model.uri.value),
    // The viewer's Position is 1-based; the host op speaks 0-based LSP coords.
    line=position.line_number - 1,
    character=position.column - 1,
  ) catch {
    _ => return None
  }
  decode_hover(reply_json_text(reply), model)
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
/// Strip the `openseek:///` scheme the viewer models use, leaving the
/// workspace-relative path the host op expects.
fn strip_model_uri(uri : String) -> String {
  let prefix = "openseek:///"
  if uri.has_prefix(prefix) {
    uri[prefix.length():].to_owned()
  } else {
    uri
  }
}

///|
/// Call the host `hover` op for `path` at a zero-based `line`/`character`.
async fn request_hover(
  session~ : String,
  path~ : String,
  line~ : Int,
  character~ : Int,
) -> @js.Value {
  let payload = @js.Object::new()
  payload["session"] = session
  payload["path"] = path
  payload["line"] = line
  payload["character"] = character
  bridge_request("hover", payload.to_value())
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
    let origin = snapshot.position_at_offset(0)
    return @common.Range::from_positions(origin, origin)
  }
  // The reply carries 0-based LSP positions; shift to the viewer's 1-based
  // Position, then round-trip through offsets so the range stays clamped.
  let start = snapshot.offset_at_position(
    @common.Position::Position(
      json_int(reply, "start_line") + 1,
      json_int(reply, "start_character") + 1,
    ),
  )
  let end = snapshot.offset_at_position(
    @common.Position::Position(
      json_int(reply, "end_line") + 1,
      json_int(reply, "end_character") + 1,
    ),
  )
  @common.Range::from_positions(
    snapshot.position_at_offset(start),
    snapshot.position_at_offset(end),
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
