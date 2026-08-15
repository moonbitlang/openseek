// The viewer's hover provider: when the pointer rests on a symbol in a `.mbt`
// file, ask the host's `hover` op (served by `moon ide hover`) and render the
// reply as a viewer tooltip. The host owns the language tooling, so the
// front-end only marshals the position and decodes the reply.

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
pub fn ModelUri::of(resource : @common.Uri) -> ModelUri {
  ModelUri(resource.to_string())
}

///|
/// The Viewer uses the frontend resource URI itself as its document URI. Its
/// authority already carries the channel identity, so no platform-sensitive
/// `file:` conversion is needed in the browser.
fn model_uri_of(resource : @common.Uri) -> @common.Uri {
  resource
}

///|
/// The channel a viewer model URI belongs to; `None` for a URI this app did
/// not mint. A foreign or authority-less URI never falls back to a host.
fn model_uri_channel(uri : @common.Uri) -> @interop.ChannelId? {
  @resource.channel(uri)
}

///|
/// Decode a viewer model URI into the absolute path it names; `None` for a
/// URI this app did not mint, which has no host op to route to anyway.
/// The returned URI is the same typed resource: no browser-host filesystem
/// conversion is involved.
fn model_uri_path(uri : @common.Uri) -> @common.Uri? {
  guard @resource.channel(uri) is Some(_) else { return None }
  Some(uri)
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
  // v1 covers MoonBit only; other languages have no tooling behind the op.
  guard model.language_id == "moonbit" else { return None }
  guard !token.is_cancellation_requested() else { return None }
  // The provider is registry-global, so use the document route recorded when
  // Desktop placed this exact model in the Viewer.
  guard model_uri_path(model.uri) is Some(absolute) &&
    viewer_state.absolute == Some(absolute) &&
    viewer_state.navigation is Some(context) &&
    viewer_state.relative is Some(path) else {
    return None
  }
  let reply = request_hover(
    owner=context.owner,
    root=context.root,
    path~,
    // The viewer's Position is 1-based; the host op speaks 0-based LSP coords.
    line=position.line_number - 1,
    character=position.column - 1,
  ) catch {
    _ => return None
  }
  HoverProjection::{ reply, model }.to_viewer()
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
/// Call the host `hover` op for `path` relative to the explicit absolute
/// `root`, at a zero-based `line`/`character`.
async fn request_hover(
  owner~ : @interop.ConversationKey,
  root~ : @common.Uri,
  path~ : @pathx.Relative,
  line~ : Int,
  character~ : Int,
) -> @protocol.LspHoverReply {
  @interop.bridge_request(owner.channel, @commands.lsp_hover, {
    session: owner.session,
    root: root.path,
    path: path.0,
    line,
    character,
  })
}

///|
/// The typed host hover reply together with the document snapshot needed to
/// project its LSP coordinates into Viewer coordinates.
priv struct HoverProjection {
  reply : @protocol.LspHoverReply
  model : @model.TextModel
}

///|
fn HoverProjection::to_viewer(self : HoverProjection) -> @language.Hover? {
  // `value` is always on the wire; the host says "no hover here" with "".
  guard !self.reply.value.is_empty() else { return None }
  let content = if self.reply.markdown {
    @language.HoverContent::Markdown(self.reply.value)
  } else {
    @language.HoverContent::PlainText(self.reply.value)
  }
  Some(@language.Hover::{ range: self.range(), contents: [content] })
}

///|
/// The offset range the tooltip highlights. An empty range at the document
/// start when the reply carries none (`has_range` unset) — or when a
/// position field is malformed, which reads the same way.
fn HoverProjection::range(self : HoverProjection) -> @common.Range {
  let snapshot = self.model.snapshot()
  guard self.reply.has_range else {
    return snapshot.range_of(@common.OffsetRange::empty_at(0))
  }
  // The reply carries 0-based LSP positions; shift to the viewer's 1-based
  // line/column, then round-trip through offsets so the range stays clamped.
  let start = snapshot.get_offset_at(
    self.reply.start_line + 1,
    self.reply.start_character + 1,
  )
  let end = snapshot.get_offset_at(
    self.reply.end_line + 1,
    self.reply.end_character + 1,
  )
  snapshot.range_of(@common.OffsetRange::from_to(start, end))
}

///|
/// Tell the host the viewer now shows `relative` below its exact editor root,
/// so its language server syncs the file and starts publishing diagnostics,
/// then apply whatever it already has. Best-effort: a failed call just leaves
/// the file without squiggles; live re-analysis still arrives as `diagnostics`
/// events. v1 covers MoonBit only, the only language with a server behind the
/// op.
fn request_diagnostics(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  epoch : Int,
  root : @common.Uri,
  path : @pathx.Relative,
  absolute : @common.Uri,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = request_lsp_open(owner~, root~, path~) catch { _ => return }
      // An absent `diagnostics` field means the host's check could not run:
      // keep the markers we have rather than clearing them with fake "no
      // problems".
      guard reply.diagnostics is Some(diagnostics) else { return }
      scheduler.add(
        dispatch(DiagnosticsLoaded(owner~, epoch~, absolute~, diagnostics~)),
      )
    })
  })
}

///|
/// Call the host `lsp_open` op for `path` relative to `root`.
async fn request_lsp_open(
  owner~ : @interop.ConversationKey,
  root~ : @common.Uri,
  path~ : @pathx.Relative,
) -> @protocol.LspDiagnosticsReply {
  @interop.bridge_request(owner.channel, @commands.lsp_open, {
    session: owner.session,
    root: root.path,
    path: path.0,
  })
}

///|
/// A typed diagnostics batch projected into Viewer's diagnostic model.
priv struct DiagnosticsProjection(Array[@protocol.LspDiagnostic])

///|
fn DiagnosticsProjection::to_viewer(
  self : DiagnosticsProjection,
) -> Array[@language.Diagnostic] {
  self.0.map(diagnostic => DiagnosticProjection(diagnostic).to_viewer())
}

///|
/// One typed LSP diagnostic projected into Viewer's `Diagnostic` shape.
/// LSP positions are 0-based; the viewer's ranges are 1-based, so each bound
/// shifts by one. Malformed rows have already been dropped at the LSP adapter.
priv struct DiagnosticProjection(@protocol.LspDiagnostic)

///|
fn DiagnosticProjection::to_viewer(
  self : DiagnosticProjection,
) -> @language.Diagnostic {
  let diagnostic = self.0
  @language.Diagnostic::{
    range: @common.Range::Range(
      diagnostic.range.start.line + 1,
      diagnostic.range.start.character + 1,
      diagnostic.range.end.line + 1,
      diagnostic.range.end.character + 1,
    ),
    severity: diagnostic_severity(diagnostic.severity),
    message: diagnostic.message,
    tags: self.tags(),
  }
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
fn DiagnosticProjection::tags(
  self : DiagnosticProjection,
) -> Array[@language.DiagnosticTag]? {
  guard self.0.tags is Some(items) else { return None }
  let tags : Array[@language.DiagnosticTag] = []
  for item in items {
    match item {
      1 => tags.push(Unnecessary)
      2 => tags.push(Deprecated)
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
test "model uris retain resource paths and channels" {
  let channels : Array[@interop.ChannelId] = [Local, Remote("d_abc")]
  for channel in channels {
    for path in ["/ws/my proj/src/a b.mbt", "/tmp/中文/x.mbt", "/C:/ws/a.mbt"] {
      guard @resource.of_path(channel, path) is Some(resource) else {
        fail("test resource path was not absolute")
      }
      let minted = model_uri_of(resource)
      assert_true(model_uri_path(minted) == Some(resource))
      assert_true(model_uri_channel(minted) == Some(channel))
      // The ModelUri string form re-parses to the same document key — the
      // `remove_editor_feedback` path. URI serialization owns escaping while
      // the parsed path and channel remain stable.
      let reparsed = @common.Uri::parse(ModelUri::of(resource).0)
      assert_eq(reparsed.to_string(), minted.to_string())
      assert_true(model_uri_path(reparsed) == Some(resource))
    }
  }
}

///|
test "foreign uris do not parse as model paths or channels" {
  assert_true(model_uri_path(@common.Uri::parse("untitled:one")) is None)
  assert_true(model_uri_path(@common.Uri::file("/a.bin")) is None)
  assert_true(
    model_uri_path(@common.Uri::parse("openseek-notice:/a.bin")) is None,
  )
  assert_true(model_uri_channel(@common.Uri::file("/a.bin")) is None)
  assert_true(
    model_uri_channel(@common.Uri::parse("openseek://unknown/a.bin")) is None,
  )
}
