// The viewer's hover provider: when the pointer rests on a symbol in a `.mbt`
// file, ask the host's `hover` op (which proxies the workspace's moon-lsp) and
// render the reply as a viewer tooltip. The host owns the language server, so
// the front-end only marshals the position and decodes the reply.

///|
/// The scheme of viewer model URIs this app mints. The hover provider only
/// ever receives the `TextModel`, never the app `Model`, so the URI carries
/// the file's host-resolved absolute path as its path component — the whole
/// address the path-routed `hover` op needs.
const ModelUriScheme : String = "openseek"

///|
/// A viewer model URI this app minted (the `to_string()` of an `openseek`-
/// scheme `Uri` naming the file's absolute path) — the document key the
/// viewer's services (feedback, markers) index by. The newtype keeps
/// arbitrary strings and filesystem paths out of APIs that mean a viewer
/// document; mint one with `ModelUri::of`, or wrap only the string form of a
/// `Uri` that `model_uri_path` just accepted. Read-only outside this
/// package: the main package carries one in `EditorCommentAdded` and hands
/// it back to `remove_editor_feedback`, but only this package mints them.
pub struct ModelUri(String)

///|
pub fn ModelUri::of(
  channel : @interop.ChannelId,
  absolute_path : @pathx.Absolute,
) -> ModelUri {
  ModelUri(model_uri_of(channel, absolute_path).to_string())
}

///|
/// An app-scheme viewer `Uri` for `path`. `Uri::file` owns the platform
/// path normalization (backslashes, UNC authorities, drive letters) and
/// cannot fail; re-scheming its slash-rooted output cannot fail validation
/// either, so the catch is unreachable and keeps the `file` scheme.
fn app_uri(scheme : String, path : String) -> @common.Uri {
  let file = @common.Uri::file(path)
  file.with_(scheme~) catch {
    _ => file
  }
}

///|
/// The viewer `Uri` for the file at `absolute_path` on `channel`. The
/// authority carries the channel identity (`local`, `remote.<id>`), so a
/// registry-global service handed only the document — the hover provider —
/// still knows which host to ask; the URI type owns the percent-encoding,
/// so the path rides raw.
fn model_uri_of(
  channel : @interop.ChannelId,
  absolute_path : @pathx.Absolute,
) -> @common.Uri {
  let uri = app_uri(ModelUriScheme, absolute_path.0)
  uri.with_(authority=channel.uri_authority()) catch {
    _ => uri
  }
}

///|
/// The channel a viewer model URI belongs to; `None` for a URI this app did
/// not mint. A foreign or authority-less URI never falls back to a host.
fn model_uri_channel(uri : @common.Uri) -> @interop.ChannelId? {
  guard uri.scheme == ModelUriScheme else { return None }
  @interop.ChannelId::from_uri_authority(uri.authority)
}

///|
/// Decode a viewer model URI into the absolute path it names; `None` for a
/// URI this app did not mint, which has no host op to route to anyway.
/// Undoes `app_uri` exactly: the conversion runs against a `file`-scheme
/// twin (`uri_to_fs_path`'s UNC reconstruction is gated on that scheme) and
/// keeps the Windows drive letter's casing, so the path the host op gets is
/// byte-for-byte the one the model was minted with.
fn model_uri_path(uri : @common.Uri) -> @pathx.Absolute? {
  guard uri.scheme == ModelUriScheme else { return None }
  // The authority is the channel, not a UNC host — strip it before the
  // `file`-scheme conversion or it would be rebuilt into the path.
  let file = uri.with_(scheme="file", authority="") catch { _ => uri }
  let path = @common.uri_to_fs_path(file, true)
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
  guard model_uri_path(model.uri) is Some(path) else { return None }
  // A registry-global provider has no Ctx; the document's own URI carries
  // its channel in the authority, so the ask routes to the right host.
  guard model_uri_channel(model.uri) is Some(channel) else { return None }
  let reply = request_hover(
    channel~,
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
  channel~ : @interop.ChannelId,
  path~ : @pathx.Absolute,
  line~ : Int,
  character~ : Int,
) -> @js.Value {
  let payload = @js.Object::new()
  payload["path"] = path.0
  payload["line"] = line
  payload["character"] = character
  @interop.bridge_request(channel, "lsp.hover", payload.to_value())
}

///|
/// Decode the host's flat hover reply into a viewer `Hover`. `None` when the
/// reply has no text. The range comes back as LSP line/character positions,
/// which the model's snapshot converts to the document offsets `Range` uses.
fn decode_hover(text : String, model : @model.TextModel) -> @language.Hover? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  // `value` is always on the wire; the host says "no hover here" with "".
  guard @jsonx.json_text(reply, "value") is Some(value) && !value.is_empty() else {
    return None
  }
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
/// The offset range the tooltip highlights. An empty range at the document
/// start when the reply carries none (`has_range` unset) — or when a
/// position field is malformed, which reads the same way.
fn hover_range(
  reply : Map[String, Json],
  model : @model.TextModel,
) -> @common.Range {
  let snapshot = model.snapshot()
  guard reply.get("has_range") is Some(True) &&
    @jsonx.json_int(reply, "start_line") is Some(start_line) &&
    @jsonx.json_int(reply, "start_character") is Some(start_character) &&
    @jsonx.json_int(reply, "end_line") is Some(end_line) &&
    @jsonx.json_int(reply, "end_character") is Some(end_character) else {
    let origin = snapshot.get_position_at(0)
    return @common.Range::from_positions(origin, origin)
  }
  // The reply carries 0-based LSP positions; shift to the viewer's 1-based
  // line/column, then round-trip through offsets so the range stays clamped.
  let start = snapshot.get_offset_at(start_line + 1, start_character + 1)
  let end = snapshot.get_offset_at(end_line + 1, end_character + 1)
  @common.Range::from_positions(
    snapshot.get_position_at(start),
    snapshot.get_position_at(end),
  )
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
  owner : @interop.ConversationKey,
  absolute : @pathx.Absolute,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = request_lsp_open(channel=owner.channel, path=absolute) catch {
        _ => return
      }
      let diagnostics = reply_diagnostics(@interop.reply_json_text(reply))
      scheduler.add(
        dispatch(DiagnosticsLoaded(owner~, absolute~, diagnostics~)),
      )
    })
  })
}

///|
/// Call the host `lsp_open` op for the absolute `path`.
async fn request_lsp_open(
  channel~ : @interop.ChannelId,
  path~ : @pathx.Absolute,
) -> @js.Value {
  let payload = @js.Object::new()
  payload["path"] = path.0
  @interop.bridge_request(channel, "lsp.open", payload.to_value())
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
    // LSP requires `range` (with all four positions) and `message`; an item
    // missing any is malformed and skipped. `severity` really is optional.
    guard fields.get("range")
      is Some(Object({ "start": Object(start), "end": Object(end_), .. })) &&
      @jsonx.json_int(start, "line") is Some(start_line) &&
      @jsonx.json_int(start, "character") is Some(start_character) &&
      @jsonx.json_int(end_, "line") is Some(end_line) &&
      @jsonx.json_int(end_, "character") is Some(end_character) else {
      continue
    }
    guard @jsonx.json_text(fields, "message") is Some(message) &&
      !message.is_empty() else {
      continue
    }
    result.push(@language.Diagnostic::{
      range: @common.Range::Range(
        start_line + 1,
        start_character + 1,
        end_line + 1,
        end_character + 1,
      ),
      severity: diagnostic_severity(@jsonx.json_int(fields, "severity")),
      message,
      tags: decode_diagnostic_tags(fields),
    })
  }
  result
}

///|
/// Map an LSP `DiagnosticSeverity` (`Error=1 … Hint=4`) to the viewer's. The
/// field is optional in LSP; an absent or unknown severity reads as `Error`,
/// LSP's own documented client fallback.
fn diagnostic_severity(value : Int?) -> @language.DiagnosticSeverity {
  match value {
    Some(2) => Warning
    Some(3) => Info
    Some(4) => Hint
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

///|
test "model uris round-trip the absolute path and the channel" {
  let channels : Array[@interop.ChannelId] = [Local, Remote("d_abc")]
  for channel in channels {
    for path in ["/ws/my proj/src/a b.mbt", "/tmp/中文/x.mbt", "C:/ws/a.mbt"] {
      let minted = model_uri_of(channel, Absolute(path))
      assert_true(model_uri_path(minted) == Some(Absolute(path)))
      assert_true(model_uri_channel(minted) == Some(channel))
      // The ModelUri string form re-parses to the same document key — the
      // `remove_editor_feedback` path. Monaco's string form normalizes the
      // Windows drive letter's case, so the key, not the path bytes, is what
      // must survive this leg.
      let reparsed = @common.Uri::parse(ModelUri::of(channel, Absolute(path)).0)
      assert_eq(reparsed.to_string(), minted.to_string())
      assert_true(model_uri_path(reparsed) is Some(_))
    }
  }
}

///|
test "foreign uris do not parse as model paths or channels" {
  assert_true(model_uri_path(@common.Uri::parse("untitled:one")) is None)
  assert_true(model_uri_path(@common.Uri::file("/a.bin")) is None)
  assert_true(model_uri_path(app_uri("openseek-notice", "/a.bin")) is None)
  assert_true(model_uri_channel(@common.Uri::file("/a.bin")) is None)
  assert_true(model_uri_channel(app_uri(ModelUriScheme, "/a.bin")) is None)
}
