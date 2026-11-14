// Definition, References, and Peek integration for the embedded Viewer.
// Language queries use the host operations or authenticated Cloud endpoints;
// moon-lsp is deliberately not part of this path. Viewer owns the UI and
// request lifecycle, while Desktop owns routing, file opening, and preview
// model leases.

///|
/// The active root needed by cross-resource navigation: the checkout root
/// supplied by `Ctx`, plus the Cloud credentials for this account lifecycle.
#derive(Eq)
priv struct NavigationContext {
  owner : @interop.ConversationIdentity
  root : @common.Uri
  cloud : CloudFiles?
}

///|
/// Bring one Viewer model URI back into this editor root. The root is the
/// exact main checkout, linked worktree, or Codex cwd reconstructed when the
/// file was read. Cloud standard-library documents have a separate source root.
fn NavigationContext::relative_path(
  self : NavigationContext,
  absolute : @common.Uri,
) -> @pathx.Relative? {
  self.target(absolute).map(target => target.1)
}

///|
fn NavigationContext::target(
  self : NavigationContext,
  absolute : @common.Uri,
) -> (String, @pathx.Relative)? {
  if @resource.relative_to(absolute, self.root) is Some(path) && !path.is_root() {
    return Some(("workspace", path))
  }
  guard self.owner is @interop.Cloud(account~, session~) &&
    @resource.cloud_stdlib_root(@cloud.CloudOrigin, account, session)
    is Some(root) &&
    @resource.relative_to(absolute, root) is Some(path) &&
    !path.is_root() else {
    return None
  }
  Some(("stdlib", path))
}

///|
fn NavigationContext::accepts_location(
  self : NavigationContext,
  uri : @common.Uri,
) -> Bool {
  match self.owner {
    Host(_) => self.relative_path(uri) is Some(_)
    Cloud(..) => self.target(uri) is Some(_)
  }
}

///|
/// The navigation root for the document now on screen: the checkout root,
/// with Cloud standard-library documents retaining the same project context.
fn navigation_context_for_file(
  owner : @interop.ConversationIdentity,
  root : @common.Uri?,
  document : @common.Uri,
  cloud? : CloudFiles,
) -> NavigationContext? {
  guard root is Some(root) else { return None }
  match owner {
    Host(host) => if !@resource.belongs_to(root, host.channel) { return None }
    Cloud(account~, session~) => {
      guard cloud is Some(_) &&
        @resource.cloud_root(@cloud.CloudOrigin, account, session) == Some(root) else {
        return None
      }
    }
  }
  let context : NavigationContext = { owner, root, cloud, }
  if context.target(document) is Some(_) {
    Some(context)
  } else {
    None
  }
}

///|
/// One Viewer model projected back onto the live checkout document MoonIDE
/// understands. Full-file models have a zero offset; Token/Tree Modified
/// fragments carry the section's zero-based line displacement.
#derive(Eq)
priv struct MoonIdeModelProjection {
  context : NavigationContext
  path : @pathx.Relative
  document : @common.Uri
  line_offset : Int32
}

///|
fn MoonIdeModelProjection::source_line_number(
  self : MoonIdeModelProjection,
  model_line_number : Int32,
) -> Int32 {
  model_line_number + self.line_offset
}

///|
/// Resolve IDE ownership without ever treating an Original or historical
/// revision as the current checkout. The semantic branch additionally proves
/// that the live resource still belongs to the active navigation context, so
/// a stale fragment cannot address a replacement worktree.
fn moon_ide_model_projection(
  model : @model.TextModel,
) -> MoonIdeModelProjection? {
  guard viewer_state.navigation is Some(context) else { return None }
  match model_uri_path(model.uri) {
    Some(absolute) => {
      guard viewer_state.live &&
        viewer_state.document == Some(absolute) &&
        context.relative_path(absolute) is Some(path) else {
        return None
      }
      Some({ context, path, document: absolute, line_offset: 0, })
    }
    None => {
      guard semantic_modified_model_projection(model) is Some(semantic) &&
        context.relative_path(semantic.resource) is Some(rel) &&
        rel == semantic.path else {
        return None
      }
      Some({
        context,
        path: semantic.path,
        document: semantic.resource,
        line_offset: semantic.line_offset,
      })
    }
  }
}

///|
/// One implementation serves both editor provider traits. The model URI names
/// the absolute file and host; `NavigationContext` supplies its editor root.
priv struct MoonIdeNavigationProvider {
  // Viewer providers run outside Rabbita's update function. This callback
  // re-enters the owning app through a scheduled `Msg`; it never mutates the
  // panel model directly.
  on_error : (@interop.ConversationIdentity, Failure, Int32?) -> Unit
}

///|
impl @language.DefinitionProvider for MoonIdeNavigationProvider with fn provide_definition(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() || model.language_id != "moonbit" {
    return []
  }
  guard moon_ide_model_projection(model) is Some(projection) else { return [] }
  let version = model.get_version_id()
  let locations = projection.locations(
    "definition",
    projection.source_line_number(position.line_number),
    position.column,
  ) catch {
    error => {
      if !token.is_cancellation_requested() &&
        projection.is_current(model) &&
        model.get_version_id() == version {
        (self.on_error)(
          projection.context.owner,
          language_request_failure(error, problem => DefinitionFailed(problem)),
          projection.context.cloud.map(files => files.epoch),
        )
      }
      return []
    }
  }
  if token.is_cancellation_requested() ||
    !projection.is_current(model) ||
    model.get_version_id() != version {
    []
  } else {
    locations
  }
}

///|
impl @language.ReferencesProvider for MoonIdeNavigationProvider with fn provide_references(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() || model.language_id != "moonbit" {
    return []
  }
  guard moon_ide_model_projection(model) is Some(projection) else { return [] }
  let version = model.get_version_id()
  let locations = projection.locations(
    "references",
    projection.source_line_number(position.line_number),
    position.column,
  ) catch {
    error => {
      if !token.is_cancellation_requested() &&
        projection.is_current(model) &&
        model.get_version_id() == version {
        (self.on_error)(
          projection.context.owner,
          language_request_failure(error, problem => ReferencesFailed(problem)),
          projection.context.cloud.map(files => files.epoch),
        )
      }
      return []
    }
  }
  if token.is_cancellation_requested() ||
    !projection.is_current(model) ||
    model.get_version_id() != version {
    []
  } else {
    locations
  }
}

///|
/// Register both navigation providers on the process-wide language registry.
/// The returned handles are retained by `DesktopViewerServices` for the full
/// lifetime of the one mounted Viewer.
fn register_moon_ide_navigation_providers(
  on_error : (@interop.ConversationIdentity, Failure, Int32?) -> Unit,
) -> Array[@common.Disposable] {
  let provider = MoonIdeNavigationProvider::{ on_error, }
  [
    @languages.languages.register_definition_provider(
      moon_ide_model_selector(),
      provider,
    ),
    @languages.languages.register_references_provider(
      moon_ide_model_selector(),
      provider,
    ),
  ]
}

///|
priv suberror NavigationRequestError {
  NavigationRequestError(String)
}

///|
impl Show for NavigationRequestError with fn output(self, logger) {
  let NavigationRequestError(message) = self
  logger.write_string(message)
}

///|
async fn request_moon_ide_locations(
  channel : @interop.ChannelId,
  command : @commands.Command[
    @protocol.MoonIdeNavigationPayload,
    @protocol.MoonIdeNavigationReply,
  ],
  payload : @protocol.MoonIdeNavigationPayload,
) -> Array[@language.Location] {
  let reply = match @interop.bridge_request(channel, command, payload) {
    NavigationLocations(reply) => reply
    NavigationError(message) => raise NavigationRequestError(message)
  }
  MoonIdeProjection::{ reply, channel, }.to_viewer()
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
  self.reply.locations.filter_map(location => {
    @resource.of_path(self.channel, location.path).bind(uri => {
      project_moonide_location(location, uri)
    })
  })
}

///|
fn project_moonide_location(
  location : @protocol.MoonIdeLocation,
  uri : @common.Uri,
) -> @language.Location? {
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
    return None
  }
  Some(@language.Location::{
    is_test: location.is_test,
    uri,
    range: @common.Range(
      location.start_line,
      location.start_column,
      location.end_line,
      location.end_column,
    ),
  })
}

///|
/// Desktop opens navigation targets in its current tab group. `Side` is not
/// accepted because the file panel has no second editor group; returning
/// false lets Viewer preserve its current state and report that limitation.
fn navigation_location_opener(
  open_location : (
    @interop.ConversationIdentity,
    @common.Uri,
    @common.Range,
    Int32?,
  ) -> Unit,
) -> @navigation_api.LocationOpenerHandle {
  LocationOpenerHandle(open=request => {
    guard request.mode is Current else { return false }
    guard viewer_state.navigation is Some(context) else { return false }
    let absolute = request.location.uri
    guard context.accepts_location(absolute) else { return false }
    open_location(
      context.owner,
      absolute,
      request.location.range,
      context.cloud.map(files => files.epoch),
    )
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
/// Resolve a cross-file Peek model through OpenSeek's existing file read.
/// Each request owns one fresh readonly model; the returned
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
  let document = viewer_state.document
  let version = viewer_state.version
  guard context.accepts_location(resource) else { return None }
  let reply = read_source(context.owner, context.cloud, resource) catch {
    _ => return None
  }
  let file = FileContent::from_reply(reply)
  if token.is_cancellation_requested() ||
    viewer_state.navigation != Some(context) ||
    viewer_state.document != document ||
    viewer_state.version != version {
    return None
  }
  guard file is Content(content~, sig~) else { return None }
  let name = @resource.label(resource)
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
test "navigation context follows the checkout root and its documents" {
  guard @resource.of_path(@interop.ChannelId::Local, "/ws/project/src/main.mbt")
    is Some(file) else {
    fail("test resource path was not absolute")
  }
  guard @resource.of_path(@interop.ChannelId::Local, "/ws/project")
    is Some(root) else {
    fail("test root path was not absolute")
  }
  let owner = @interop.Host({
    channel: @interop.ChannelId::Local,
    session: "test",
  })
  guard navigation_context_for_file(owner, Some(root), file) is Some(context) else {
    fail("checkout root was not accepted for its own document")
  }
  assert_eq(context.relative_path(file), Some(Relative("src/main.mbt")))
  guard @resource.of_path(@interop.ChannelId::Local, "/other/src/main.mbt")
    is Some(outside) else {
    fail("test outside resource was not absolute")
  }
  assert_true(navigation_context_for_file(owner, Some(root), outside) is None)
  assert_true(navigation_context_for_file(owner, None, file) is None)
  assert_true(context.relative_path(outside) is None)
  for
    uri in [
      "openseek://local/ws/project-other/main.mbt", "openseek://device/ws/project/src/main.mbt",
      "file:///ws/project/src/main.mbt", "openseek://local/ws/project",
    ] {
    assert_true(context.relative_path(@common.Uri::parse(uri)) is None)
  }
  let windows : NavigationContext = {
    owner: context.owner,
    cloud: None,
    root: @common.Uri::parse("openseek://local/C:/work/project/"),
  }
  assert_eq(
    windows.relative_path(
      @common.Uri::parse("openseek://local/C:/work/project/src/main.mbt"),
    ),
    Some(Relative("src/main.mbt")),
  )
}

///|
test "semantic navigation projects fragment-local lines onto the source" {
  let context : NavigationContext = {
    owner: @interop.Host({
      channel: @interop.ChannelId::Local,
      session: "test",
    }),
    cloud: None,
    root: @common.Uri::parse("openseek://local/work"),
  }
  let projection : MoonIdeModelProjection = {
    context,
    path: Relative("src/main.mbt"),
    document: @common.Uri::parse("openseek://local/work/src/main.mbt"),
    line_offset: 29,
  }
  assert_eq(projection.source_line_number(1), 30)
  assert_eq(projection.source_line_number(3), 32)
}

///|
test "moon ide locations stay one based and channel routed" {
  let locations = MoonIdeProjection::{
    reply: {
      locations: [
        {
          is_test: Some(true),
          path: "/ws/lib.mbt",
          start_line: 2,
          start_column: 3,
          end_line: 2,
          end_column: 9,
        },
        {
          is_test: None,
          path: "/ws/bad.mbt",
          start_line: 0,
          start_column: 1,
          end_line: 1,
          end_column: 1,
        },
        {
          is_test: None,
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
  assert_eq(locations[0].is_test, Some(true))
  assert_true(
    @resource.channel(locations[0].uri) == Some(Remote("device")) &&
    model_uri_path(locations[0].uri) is Some(resource) &&
    resource.path == "/ws/lib.mbt" &&
    locations[0].range == @common.Range(2, 3, 2, 9),
  )
}

///|
/// Label against the live workspace, retaining resource identity for navigation.
fn navigation_resource_path_label(uri : @common.Uri) -> String? {
  guard viewer_state.navigation is Some(context) else { return None }
  context.relative_path(uri).map(path => path.0)
}
