// The viewer's hover provider: when the pointer rests on a symbol in a MoonBit
// source or standalone script, request Moon IDE hover through the owning
// Host or Cloud session and render the reply as a Viewer tooltip.

///|
/// A viewer model URI this app minted (the `to_string()` of a Host or Cloud
/// resource `Uri`) — the document key the
/// viewer's services (feedback, markers) index by. The newtype keeps
/// arbitrary strings and filesystem paths out of APIs that mean a viewer
/// document. Revision/fragment feedback may also retain its Cloud workspace
/// file identity so it reaches that file's composer. Mint one with
/// `ModelUri::of`, or wrap only the string form of a
/// `Uri` that `model_uri_path` just accepted. Read-only outside this
/// package: the main package carries one in `EditorCommentAdded` and hands
/// it back to `remove_editor_feedback`, but only this package mints them.
pub struct ModelUri {
  uri : String
  feedback_source : @common.Uri?
}

///|
fn ModelUri::ModelUri(uri : String, feedback_source? : @common.Uri) -> ModelUri {
  { uri, feedback_source, }
}

///|
pub fn ModelUri::resource(self : ModelUri) -> @common.Uri {
  self.feedback_source.unwrap_or_else(() => try! @common.Uri::parse(self.uri))
}

///|
/// Decode a viewer model URI into the absolute path it names; `None` for a
/// URI this app did not mint, which has no host op to route to anyway.
/// The returned URI is the same typed resource: no browser-host filesystem
/// conversion is involved.
fn model_uri_path(uri : @common.Uri) -> @common.Uri? {
  guard @resource.channel(uri) is Some(_) ||
    (
      (uri.scheme == "openseek-cloud" || uri.scheme == "openseek-cloud-stdlib") &&
      !uri.authority.is_empty() &&
      uri.query.is_empty() &&
      uri.fragment.is_empty()
    ) else {
    return None
  }
  Some(uri)
}

///|
/// Desktop language features are revision-sensitive today: host operations
/// read live workspace/toolchain sources. Token/Tree's Modified
/// fragments opt in through their distinct scheme and an explicit coordinate
/// projection; Original and historical schemes remain excluded.
fn moon_ide_model_selector() -> @language.LanguageSelector {
  LanguageSelectorList([
    LanguageFilter(LanguageFilter(language="moonbit", scheme=@resource.Scheme)),
    LanguageFilter(LanguageFilter(language="moonbit", scheme="openseek-cloud")),
    LanguageFilter(
      LanguageFilter(language="moonbit", scheme="openseek-cloud-stdlib"),
    ),
    LanguageFilter(
      LanguageFilter(language="moonbit", scheme=SemanticReviewModifiedScheme),
    ),
  ])
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
  // The provider is registry-global, so resolve either the live full model or
  // a currently mounted semantic Modified projection before addressing the
  // host checkout.
  guard moon_ide_model_projection(model) is Some(projection) else {
    return None
  }
  let version = model.get_version_id()
  let reply = request_hover(
    context=projection.context,
    document=projection.document,
    path=projection.path,
    // The viewer's Position is 1-based; the host op speaks 0-based LSP coords.
    line=projection.source_line_number(position.line_number) - 1,
    character=position.column - 1,
  ) catch {
    _ => return None
  }
  guard !token.is_cancellation_requested() &&
    projection.is_current(model) &&
    model.get_version_id() == version else {
    return None
  }
  HoverProjection::{ reply, model, line_offset: projection.line_offset, }.to_viewer()
}

///|
/// Register the hover provider on the shared language registry.
fn register_hover_provider() -> Unit {
  let provider = LspHoverProvider::{ }
  @languages.languages.register_hover_provider(
    moon_ide_model_selector(),
    provider,
  )
  |> ignore
}

///|
/// Query hover for the captured source at zero-based `line`/`character`.
async fn request_hover(
  context~ : NavigationContext,
  document~ : @common.Uri,
  path~ : @pathx.Relative,
  line~ : Int32,
  character~ : Int32,
) -> @protocol.LspHoverReply {
  request_moonide(
    context,
    document,
    @commands.lsp_hover,
    {
      session: context.owner.session(),
      root: context.root.path,
      path: path.0,
      line,
      character,
    },
    "hover",
  )
}

///|
/// The typed host hover reply together with the document snapshot needed to
/// project its LSP coordinates into Viewer coordinates.
priv struct HoverProjection {
  reply : @protocol.LspHoverReply
  model : @model.TextModel
  line_offset : Int32
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
  Some(@language.Hover::{ range: self.range(), contents: [content], })
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
    self.reply.start_line + 1 - self.line_offset,
    self.reply.start_character + 1,
  )
  let end = snapshot.get_offset_at(
    self.reply.end_line + 1 - self.line_offset,
    self.reply.end_character + 1,
  )
  snapshot.range_of(@common.OffsetRange::from_to(start, end))
}

///|
// A later refresh of the active file supersedes an older diagnostics request.
let moon_ide_diagnostics_generation : Ref[Int32] = Ref(0)

///|
/// Tell the host the viewer now shows `absolute` below its exact editor root,
/// so its language server syncs the file and starts publishing diagnostics,
/// then apply whatever it already has. Best-effort: a failed call just leaves
/// the file without squiggles; live re-analysis still arrives as `diagnostics`
/// events. v1 covers MoonBit only, the only language with a server behind the
/// op. Cloud standard-library checks retain the owning session context.
fn request_diagnostics(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationIdentity,
  epoch : Int32,
  root : @common.Uri,
  absolute : @common.Uri,
  cloud? : CloudFiles,
) -> @cmd.Cmd {
  guard navigation_context_for_file(owner, Some(root), absolute, cloud?)
    is Some(context) &&
    context.target(absolute) is Some((_, path)) else {
    return @cmd.none
  }
  @cmd.custom_cmd(
    scheduler => {
      guard viewer_state.document == Some(absolute) &&
        viewer_state.live &&
        viewer_state.navigation == Some(context) else {
        return
      }
      moon_ide_diagnostics_generation.val += 1
      let generation = moon_ide_diagnostics_generation.val
      let version = viewer_state.version
      @js.Promise::from_async(() => {
        let reply = request_moonide(
          context,
          absolute,
          @commands.lsp_open,
          { session: owner.session(), root: root.path, path: path.0, },
          "diagnostics",
        ) catch {
          _ => return
        }
        // Absence means the check could not run; only an actual empty result
        // clears diagnostics already displayed by the Viewer.
        guard generation == moon_ide_diagnostics_generation.val &&
          viewer_state.version == version &&
          viewer_state.document == Some(absolute) &&
          viewer_state.navigation == Some(context) &&
          reply.diagnostics is Some(diagnostics) else {
          return
        }
        scheduler.add(
          dispatch(DiagnosticsLoaded(owner~, epoch~, absolute~, diagnostics~)),
        )
      })
      |> ignore
    },
    kind=@cmd.after_render,
  )
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
    range: @common.Range(
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
fn diagnostic_severity(value : Int32?) -> @language.DiagnosticSeverity {
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
      let minted = resource
      assert_true(model_uri_path(minted) == Some(resource))
      assert_true(@resource.channel(minted) == Some(channel))
      // The ModelUri string form re-parses to the same document key — the
      // `remove_editor_feedback` path. URI serialization owns escaping while
      // the parsed path and channel remain stable.
      let reparsed = @common.Uri::parse(ModelUri::of(resource).uri)
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
  assert_true(@resource.channel(@common.Uri::file("/a.bin")) is None)
  assert_true(
    @resource.channel(@common.Uri::parse("openseek://unknown/a.bin")) is None,
  )
}

///|
test "IDE language selector includes semantic Modified but excludes revisions" {
  for name in ["main.mbt", "run.mbtx"] {
    let live = @model.TextModel(
      @common.Uri::parse("openseek://local/work/\{name}"),
      name,
      language_id(name),
      1,
      "live",
      "fn main {}",
    )
    let original = @model.TextModel(
      @common.Uri::parse("openseek-review-original://local/work/\{name}"),
      name,
      language_id(name),
      1,
      "head",
      "fn main {}",
    )
    let semantic_modified = @model.TextModel(
      @common.Uri::parse("\{SemanticReviewModifiedScheme}:/section-1.mbt"),
      name,
      language_id(name),
      1,
      "semantic-new",
      "fn main {}",
    )
    let semantic_original = @model.TextModel(
      @common.Uri::parse("\{SemanticReviewOriginalScheme}:/section-1.mbt"),
      name,
      language_id(name),
      1,
      "semantic-old",
      "fn main {}",
    )
    defer live.dispose()
    defer original.dispose()
    defer semantic_modified.dispose()
    defer semantic_original.dispose()
    assert_true(moon_ide_model_selector().score(live) > 0)
    assert_true(moon_ide_model_selector().score(semantic_modified) > 0)
    assert_eq(moon_ide_model_selector().score(original), 0)
    assert_eq(moon_ide_model_selector().score(semantic_original), 0)
  }
}

///|
test "semantic hover response range projects back to fragment coordinates" {
  let model = @model.TextModel(
    @common.Uri::parse("\{SemanticReviewModifiedScheme}:/section-2.mbt"),
    "main.mbt",
    "moonbit",
    1,
    "semantic-new",
    "fn value() -> Int {\n  2\n}",
  )
  defer model.dispose()
  let projected = HoverProjection::{
    reply: {
      value: "Int",
      markdown: false,
      has_range: true,
      start_line: 30,
      start_character: 2,
      end_line: 30,
      end_character: 3,
    },
    model,
    line_offset: 29,
  }.to_viewer()
  guard projected is Some(hover) else { fail("expected projected hover") }
  assert_eq(hover.range, @common.Range(2, 3, 2, 4))
}
