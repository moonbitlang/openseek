// Definition, References, and Peek integration for the embedded Viewer.
// The language queries go directly to the host's `moonide.*` operations;
// moon-lsp is deliberately not part of this path. Viewer owns the UI and
// request lifecycle, while Desktop owns routing, file opening, and preview
// model leases.

///|
/// The active root needed by cross-resource navigation: either the explicit
/// checkout root supplied by `Ctx`, or the root reconstructed from the
/// absolute/relative pair returned by `fs.read_file`.
priv struct NavigationContext {
  owner : @interop.ConversationKey
  root : @common.Uri
} derive(Eq)

///|
/// Reconstruct the request root from one file's resource URI and its
/// root-relative name. URI paths already use slash separators. This is
/// lexical only; both values came from the same successful read request.
fn navigation_root_from_file(
  absolute : @common.Uri,
  relative : @pathx.Relative,
) -> @common.Uri? {
  let path = absolute.path
  let name = relative.normalize().0
  guard !name.is_empty() else { return None }
  let suffix = "/" + name
  guard path.strip_suffix(suffix) is Some(root) else { return None }
  let root = if root.is_empty() { "/" } else { root.to_owned() }
  let root = absolute.with_(path=root) catch { _ => return None }
  Some(root)
}

///|
/// Choose the root for the document now on screen. An explicit root is
/// accepted only when it maps the absolute file back to the exact relative
/// name; otherwise the host-returned file pair wins (important for canonical
/// paths behind symlinked workspace hints).
fn navigation_context_for_file(
  owner : @interop.ConversationKey,
  root_hint : @common.Uri?,
  absolute : @common.Uri,
  relative : @pathx.Relative,
) -> NavigationContext? {
  let root = match root_hint {
    Some(root) if @resource.relative_to(absolute, root) == Some(relative) =>
      Some(root)
    _ => navigation_root_from_file(absolute, relative)
  }
  root.map(root => { owner, root })
}

///|
/// One implementation serves both editor provider traits. The model URI is
/// the complete route: it names the absolute file and the local/remote host.
priv struct MoonIdeNavigationProvider {}

///|
impl @language.DefinitionProvider for MoonIdeNavigationProvider with fn provide_definition(
  _self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() || model.language_id != "moonbit" {
    return []
  }
  guard model_uri_path(model.uri) is Some(path) &&
    model_uri_channel(model.uri) is Some(channel) else {
    return []
  }
  let locations = request_moon_ide_locations(
    channel,
    @commands.moonide_definition,
    { path: path.path, line: position.line_number, column: position.column },
  ) catch {
    _ => return []
  }
  if token.is_cancellation_requested() {
    []
  } else {
    locations
  }
}

///|
impl @language.ReferencesProvider for MoonIdeNavigationProvider with fn provide_references(
  _self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() || model.language_id != "moonbit" {
    return []
  }
  guard model_uri_path(model.uri) is Some(path) &&
    model_uri_channel(model.uri) is Some(channel) else {
    return []
  }
  let locations = request_moon_ide_locations(
    channel,
    @commands.moonide_references,
    { path: path.path, line: position.line_number, column: position.column },
  ) catch {
    _ => return []
  }
  if token.is_cancellation_requested() {
    []
  } else {
    locations
  }
}

///|
/// Register both navigation providers on the process-wide language registry.
/// The returned handles are retained by `DesktopViewerServices` for the full
/// lifetime of the one mounted Viewer.
fn register_moon_ide_navigation_providers() -> Array[@common.Disposable] {
  let provider = MoonIdeNavigationProvider::{  }
  [
    @languages.languages.register_definition_provider(
      @language.LanguageSelector::LanguageId("moonbit"),
      provider,
    ),
    @languages.languages.register_references_provider(
      @language.LanguageSelector::LanguageId("moonbit"),
      provider,
    ),
  ]
}

///|
async fn request_moon_ide_locations(
  channel : @interop.ChannelId,
  command : @commands.Command[
    @protocol.MoonIdeNavigationPayload,
    @protocol.MoonIdeLocationsReply,
  ],
  payload : @protocol.MoonIdeNavigationPayload,
) -> Array[@language.Location] {
  let reply = @interop.bridge_request(channel, command, payload)
  MoonIdeProjection::{ reply, channel }.to_viewer()
}

///|
/// Project the host-normalized typed locations into Viewer locations. Every
/// coordinate is already a
/// one-based protocol position, so no client-side column conversion or
/// LSP-style shifting occurs here.
priv struct MoonIdeProjection {
  reply : @protocol.MoonIdeLocationsReply
  channel : @interop.ChannelId
}

///|
fn MoonIdeProjection::to_viewer(
  self : MoonIdeProjection,
) -> Array[@language.Location] {
  let result : Array[@language.Location] = []
  for location in self.reply.locations {
    guard !location.path.is_empty() &&
      location.start_line > 0 &&
      location.start_column > 0 &&
      location.end_line > 0 &&
      location.end_column > 0 &&
      (
        location.end_line > location.start_line ||
        (
          location.end_line == location.start_line &&
          location.end_column >= location.start_column
        )
      ) else {
      continue
    }
    // Host navigation locations are external input. Ignore malformed paths
    // instead of letting them acquire Absolute's invariant.
    guard @resource.of_path(self.channel, location.path) is Some(absolute) else {
      continue
    }
    result.push(@language.Location::{
      uri: model_uri_of(absolute),
      range: @common.Range::Range(
        location.start_line,
        location.start_column,
        location.end_line,
        location.end_column,
      ),
    })
  }
  result
}

///|
/// Desktop opens navigation targets in its current tab group. `Side` is not
/// accepted because the file panel has no second editor group; returning
/// false lets Viewer preserve its current state and report that limitation.
fn navigation_location_opener(
  open_location : (@interop.ConversationKey, @pathx.Relative, @common.Range) -> Unit,
) -> @navigation_api.LocationOpenerHandle {
  LocationOpenerHandle(open=request => {
    guard request.mode is Current else { return false }
    guard viewer_state.navigation is Some(context) else { return false }
    guard model_uri_channel(request.location.uri) == Some(context.owner.channel) &&
      model_uri_path(request.location.uri) is Some(absolute) &&
      @resource.relative_to(absolute, context.root) is Some(relative) &&
      !relative.is_root() else {
      return false
    }
    open_location(context.owner, relative, request.location.range)
    true
  })
}

///|
fn navigation_text_model_resolver() -> @navigation_api.TextModelResolverHandle {
  TextModelResolverHandle(resolve=(resource, token) => {
    resolve_navigation_preview(resource, token)
  })
}

///|
/// Resolve one cross-file Peek model through OpenSeek's existing safe
/// workspace read. Each request owns one fresh readonly model; the returned
/// reference disposes it when Viewer's last use of that request ends. No LSP
/// document cache or development-shell protocol is involved.
async fn resolve_navigation_preview(
  resource : @common.Uri,
  token : @language.CancellationToken,
) -> @navigation_api.TextModelReference? noraise {
  if token.is_cancellation_requested() {
    return None
  }
  guard viewer_state.navigation is Some(context) else { return None }
  guard model_uri_channel(resource) == Some(context.owner.channel) &&
    model_uri_path(resource) is Some(absolute) &&
    @resource.relative_to(absolute, context.root) is Some(relative) &&
    !relative.is_root() else {
    return None
  }
  let file = read_file_snapshot(
    context.owner,
    relative,
    root=Some(context.root),
  ) catch {
    _ => return None
  }
  if token.is_cancellation_requested() ||
    viewer_state.navigation != Some(context) {
    return None
  }
  guard file is Some(Content(content~, absolute=loaded, sig~)) &&
    loaded == absolute else {
    return None
  }
  let name = basename(relative)
  let model = @model.TextModel(
    resource,
    name,
    language_id(name),
    1,
    sig,
    content,
  )
  Some(
    TextModelReference(model, release=() => {
      if !model.is_disposed() {
        model.dispose()
      }
    }),
  )
}

///|
test "navigation root follows resource and workspace-relative paths" {
  guard @resource.of_path(@interop.ChannelId::Local, "/ws/project/src/main.mbt")
    is Some(file) else {
    fail("test resource path was not absolute")
  }
  guard navigation_root_from_file(file, Relative("src/main.mbt")) is Some(root) else {
    fail("resource root was not reconstructed")
  }
  assert_eq(root.path, "/ws/project")
  guard @resource.of_path(@interop.ChannelId::Local, "/other/src/main.mbt")
    is Some(outside) else {
    fail("test outside resource was not absolute")
  }
  assert_true(
    navigation_root_from_file(outside, Relative("lib/main.mbt")) is None,
  )
}

///|
test "moon ide locations stay one based and channel routed" {
  let locations = MoonIdeProjection::{
    reply: {
      locations: [
        {
          path: "/ws/lib.mbt",
          start_line: 2,
          start_column: 3,
          end_line: 2,
          end_column: 9,
        },
        {
          path: "/ws/bad.mbt",
          start_line: 0,
          start_column: 1,
          end_line: 1,
          end_column: 1,
        },
        {
          path: "relative.mbt",
          start_line: 1,
          start_column: 1,
          end_line: 1,
          end_column: 2,
        },
      ],
    },
    channel: @interop.ChannelId::Remote("device"),
  }.to_viewer()
  assert_eq(locations.length(), 1)
  assert_true(
    model_uri_channel(locations[0].uri) == Some(Remote("device")) &&
    model_uri_path(locations[0].uri) is Some(resource) &&
    resource.path == "/ws/lib.mbt" &&
    locations[0].range == @common.Range::Range(2, 3, 2, 9),
  )
}
