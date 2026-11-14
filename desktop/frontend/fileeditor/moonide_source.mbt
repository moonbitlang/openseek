// Keep language providers and Viewer projections independent of transport.

///|
fn MoonIdeModelProjection::is_current(
  self : MoonIdeModelProjection,
  model : @model.TextModel,
) -> Bool {
  !model.is_disposed() && moon_ide_model_projection(model) == Some(self)
}

///|
fn language_request_failure(
  error : Error,
  from_bridge : (@interop.BridgeProblem) -> Failure,
) -> Failure {
  match error {
    @cloud_client.RequestError(failure) => Cloud(failure)
    SourceError(failure) => failure
    _ => from_bridge(@interop.bridge_problem(error))
  }
}

///|
async fn[Payload : ToJson, Reply : FromJson] request_moonide(
  context : NavigationContext,
  document : @common.Uri,
  command : @commands.Command[Payload, Reply],
  payload : Payload,
  operation : String,
) -> Reply {
  match context.owner {
    Host(owner) => @interop.bridge_request(owner.channel, command, payload)
    Cloud(..) => {
      let json = request_cloud_moonide(
        context,
        document,
        payload.to_json(),
        operation,
      )
      @json.from_json(json) catch {
        _ => raise @cloud_client.RequestError(@cloud_client.Malformed)
      }
    }
  }
}

///|
async fn request_cloud_moonide(
  context : NavigationContext,
  document : @common.Uri,
  payload : Json,
  operation : String,
) -> Json {
  guard context.owner is @interop.Cloud(session~, ..) &&
    context.cloud is Some(cloud) &&
    context.target(document) is Some((source, path)) &&
    payload is Object(fields) else {
    raise SourceError(CloudFileOwnershipLost)
  }
  fields.remove("session")
  fields.remove("root")
  fields["source"] = Json(source)
  fields["path"] = Json(path.0)
  @cloud_client.request(
    @cloud.CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/moonide/\{operation}",
    Post,
    token=cloud.token,
    body=payload,
  )
}

///|
/// Cloud adds a required source discriminator to the existing location shape.
priv struct CloudMoonIdeLocation {
  source : String
  location : @protocol.MoonIdeLocation
}

///|
impl @json.FromJson for CloudMoonIdeLocation with fn from_json(json, path) {
  guard json is { "source": String(source), .. } &&
    (source == "workspace" || source == "stdlib") else {
    raise @json.JsonDecodeError((path, "expected workspace or stdlib source"))
  }
  { source, location: @json.from_json(json, path~), }
}

///|
fn cloud_moonide_locations(
  context : NavigationContext,
  json : Json,
) -> Array[@language.Location] raise {
  let locations : Array[CloudMoonIdeLocation] = @json.from_json(json)
  guard context.owner is @interop.Cloud(account~, session~) else { return [] }
  let result = []
  for entry in locations {
    let root = if entry.source == "stdlib" {
      @resource.cloud_stdlib_root(@cloud.CloudOrigin, account, session)
    } else {
      Some(context.root)
    }
    guard root is Some(root) &&
      !entry.location.path.is_empty() &&
      !entry.location.path.has_prefix("/") else {
      continue
    }
    let target = @resource.join_relative(
      root,
      @pathx.Relative(entry.location.path),
    )
    guard @resource.relative_to(target, root) is Some(_) else { continue }
    if project_moonide_location(entry.location, target) is Some(location) {
      result.push(location)
    }
  }
  result
}

///|
async fn MoonIdeModelProjection::locations(
  self : MoonIdeModelProjection,
  operation : String,
  line : Int32,
  column : Int32,
) -> Array[@language.Location] {
  let payload : @protocol.MoonIdeNavigationPayload = {
    session: self.context.owner.session(),
    root: self.context.root.path,
    path: self.path,
    line,
    column,
  }
  match self.context.owner {
    Host(owner) =>
      request_moon_ide_locations(
        owner.channel,
        if operation == "definition" {
          @commands.moonide_definition
        } else {
          @commands.moonide_references
        },
        payload,
      )
    Cloud(..) => {
      let reply = request_cloud_moonide(
        self.context,
        self.document,
        payload.to_json(),
        operation,
      )
      match reply {
        { "kind": "error", "message": String(message), .. } =>
          raise NavigationRequestError(message)
        { "kind": "locations", "locations": locations, .. } =>
          cloud_moonide_locations(self.context, locations)
        _ => raise @cloud_client.RequestError(@cloud_client.Malformed)
      }
    }
  }
}

///|
priv struct SourceCodeLens {
  range : @protocol.LspRange
  title : String
  position : @protocol.LspPosition
  locations : Array[@language.Location]?
}

///|
async fn MoonIdeModelProjection::code_lenses(
  self : MoonIdeModelProjection,
) -> Array[SourceCodeLens] {
  let payload : @protocol.MoonIdeCodeLensPayload = {
    session: self.context.owner.session(),
    root: self.context.root.path,
    path: self.path,
  }
  let (reply, raw) : (@protocol.MoonIdeCodeLensReply, Array[Json]?) = match
    self.context.owner {
    Host(owner) =>
      (
        @interop.bridge_request(
          owner.channel,
          @commands.moonide_codelens,
          payload,
        ),
        None,
      )
    Cloud(..) => {
      let json = request_cloud_moonide(
        self.context,
        self.document,
        payload.to_json(),
        "codelens",
      )
      guard json is { "lenses": Array(raw), .. } else {
        raise @cloud_client.RequestError(@cloud_client.Malformed)
      }
      (@json.from_json(json), Some(raw))
    }
  }
  let result = []
  for index, lens in reply.lenses {
    let (position, locations) = match lens.action {
      @protocol.Outside(position~) => (position, None)
      @protocol.Local(position~, locations~) => {
        let targets = match self.context.owner {
          Host(owner) =>
            MoonIdeProjection::{
              reply: { locations, },
              channel: owner.channel,
            }.to_viewer()
          Cloud(..) => {
            guard raw is Some(values) &&
              values[index] is { "action": { "locations": entries, .. }, .. } else {
              raise @cloud_client.RequestError(@cloud_client.Malformed)
            }
            cloud_moonide_locations(self.context, entries)
          }
        }
        (position, Some(targets))
      }
    }
    result.push({ range: lens.range, title: lens.title, position, locations, })
  }
  result
}
