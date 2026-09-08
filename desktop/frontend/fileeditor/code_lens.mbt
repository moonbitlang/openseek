// Moon IDE reference CodeLens integration for the current Source Viewer.
// The host owns workspace authorization and CLI parsing; this package owns
// source/model projection, Viewer command values, and click-time freshness.

///|
const MoonIdeLocalReferencesCommand : String = "moonbit.action.goToLocations"

///|
const MoonIdeOutsideReferencesCommand : String = "moonbit.executeReferenceProvider"

///|
/// CodeLens belongs only to the model installed in the permanent Source
/// Viewer. Diff kernels deliberately reuse the working file's resource URI,
/// so URI equality cannot distinguish their modified side from Source.
fn moon_ide_codelens_source_model_matches(
  candidate : @model.TextModel,
  source_model : @model.TextModel?,
) -> Bool {
  match source_model {
    Some(source_model) => source_model.same(candidate)
    None => false
  }
}

///|
fn moon_ide_codelens_source_projection(
  model : @model.TextModel,
) -> MoonIdeModelProjection? {
  guard mounted_viewer() is Some(viewer) &&
    moon_ide_codelens_source_model_matches(model, viewer.get_model()) &&
    model_uri_path(model.uri) is Some(_) &&
    moon_ide_model_projection(model) is Some(projection) &&
    (
      projection.path.0.has_suffix(".mbt") ||
      projection.path.0.has_suffix(".mbtp")
    ) else {
    return None
  }
  Some(projection)
}

///|
fn valid_codelens_lsp_position(position : @protocol.LspPosition) -> Bool {
  position.line >= 0 &&
  position.character >= 0 &&
  position.line < 0x7fff_ffff &&
  position.character < 0x7fff_ffff
}

///|
fn valid_codelens_lsp_range(range : @protocol.LspRange) -> Bool {
  valid_codelens_lsp_position(range.start) &&
  valid_codelens_lsp_position(range.end) &&
  (
    range.end.line > range.start.line ||
    (
      range.end.line == range.start.line &&
      range.end.character >= range.start.character
    )
  )
}

///|
/// Project one source LSP position into the Viewer's one-based model space.
/// Exact validation matters: TextModel's normal validator clamps, whereas an
/// out-of-bounds tool result must be discarded rather than silently moved.
fn project_codelens_position(
  model : @model.TextModel,
  projection : MoonIdeModelProjection,
  position : @protocol.LspPosition,
) -> @common.Position? {
  guard valid_codelens_lsp_position(position) else { return None }
  let projected = @common.Position(
    position.line + 1 - projection.line_offset,
    position.character + 1,
  )
  guard projected.line_number > 0 &&
    model.validate_position(projected) == projected else {
    return None
  }
  Some(projected)
}

///|
fn project_codelens_range(
  model : @model.TextModel,
  projection : MoonIdeModelProjection,
  range : @protocol.LspRange,
) -> @common.Range? {
  guard valid_codelens_lsp_range(range) &&
    project_codelens_position(model, projection, range.start) is Some(start) &&
    project_codelens_position(model, projection, range.end) is Some(end) else {
    return None
  }
  Some(
    @common.Range(start.line_number, start.column, end.line_number, end.column),
  )
}

///|
fn codelens_position_json(position : @common.Position) -> Json {
  { "line": position.line_number - 1, "character": position.column - 1 }
}

///|
fn codelens_location_json(location : @language.Location) -> Json {
  {
    "uri": location.uri.to_string(),
    "range": {
      "start": {
        "line": location.range.start_line_number - 1,
        "character": location.range.start_column - 1,
      },
      "end": {
        "line": location.range.end_line_number - 1,
        "character": location.range.end_column - 1,
      },
    },
  }
}

///|
fn project_moonide_codelenses(
  reply : @protocol.MoonIdeCodeLensReply,
  model : @model.TextModel,
  projection : MoonIdeModelProjection,
) -> Array[@language.CodeLens] {
  let result : Array[@language.CodeLens] = []
  for lens in reply.lenses {
    guard project_codelens_range(model, projection, lens.range) is Some(range) else {
      continue
    }
    let command : @language.CodeLensCommand = match lens.action {
      @protocol.Local(position~, locations~) => {
        guard project_codelens_position(model, projection, position)
          is Some(position) else {
          continue
        }
        let locations = MoonIdeProjection::{
          reply: { locations, },
          channel: projection.context.owner.channel,
        }.to_viewer()
        let encoded_locations : Array[Json] = []
        for location in locations {
          encoded_locations.push(codelens_location_json(location))
        }
        {
          id: MoonIdeLocalReferencesCommand,
          title: lens.title,
          tooltip: None,
          arguments: [
            Json(model.uri.to_string()),
            codelens_position_json(position),
            Json(encoded_locations),
          ],
        }
      }
      @protocol.Outside(position~) => {
        guard project_codelens_position(model, projection, position)
          is Some(position) else {
          continue
        }
        {
          id: MoonIdeOutsideReferencesCommand,
          title: lens.title,
          tooltip: None,
          arguments: [
            Json(model.uri.to_string()),
            codelens_position_json(position),
          ],
        }
      }
    }
    result.push({ range, id: None, command: Some(command), })
  }
  result
}

///|
priv struct MoonIdeCodeLensProvider {}

///|
impl @language.CodeLensProvider for MoonIdeCodeLensProvider with fn provide_code_lenses(
  _self,
  model,
  token,
) {
  if token.is_cancellation_requested() || model.language_id != "moonbit" {
    return []
  }
  guard moon_ide_codelens_source_projection(model) is Some(projection) else {
    return []
  }
  let reply = @interop.bridge_request(
    projection.context.owner.channel,
    @commands.moonide_codelens,
    {
      session: projection.context.owner.session,
      root: projection.context.root.path,
      path: projection.path.0,
    },
  )
  if token.is_cancellation_requested() {
    []
  } else {
    project_moonide_codelenses(reply, model, projection)
  }
}

///|
fn register_moon_ide_code_lens_provider() -> @common.Disposable {
  @languages.languages.register_code_lens_provider(
    LanguageFilter(LanguageFilter(language="moonbit", scheme=@resource.Scheme)),
    MoonIdeCodeLensProvider::{ },
  )
}

///|
priv enum MoonIdeCodeLensExecution {
  LocalReferences(
    position~ : @common.Position,
    locations~ : Array[@language.Location]
  )
  OutsideReferences(position~ : @common.Position)
}

///|
fn decode_codelens_position(
  json : Json,
  model : @model.TextModel,
) -> @common.Position? {
  let position : @protocol.LspPosition = @json.from_json(json) catch {
    _ => return None
  }
  guard valid_codelens_lsp_position(position) else { return None }
  let viewer = @common.Position(position.line + 1, position.character + 1)
  if model.validate_position(viewer) == viewer {
    Some(viewer)
  } else {
    None
  }
}

///|
fn decode_codelens_location(
  json : Json,
  context : NavigationContext,
) -> @language.Location? {
  guard json is Object(fields) &&
    fields.get("uri") is Some(String(uri_text)) &&
    fields.get("range") is Some(raw_range) else {
    return None
  }
  let uri = @common.Uri::parse(uri_text) catch { _ => return None }
  guard model_uri_path(uri) is Some(absolute) &&
    context.relative_path(absolute) is Some(_) else {
    return None
  }
  let range : @protocol.LspRange = @json.from_json(raw_range) catch {
    _ => return None
  }
  guard valid_codelens_lsp_range(range) else { return None }
  Some(@language.Location::{
    uri,
    range: @common.Range(
      range.start.line + 1,
      range.start.character + 1,
      range.end.line + 1,
      range.end.character + 1,
    ),
  })
}

///|
fn decode_moonide_codelens_command(
  request : @code_lens_api.CodeLensCommandRequest,
  model : @model.TextModel,
  context : NavigationContext,
) -> MoonIdeCodeLensExecution? {
  guard request.resource.to_string() == model.uri.to_string() &&
    model.validate_range(request.range) == request.range else {
    return None
  }
  match (request.command.id, request.command.arguments) {
    (
      MoonIdeLocalReferencesCommand,
      [String(resource), raw_position, Array(raw_locations)],
    ) => {
      guard resource == request.resource.to_string() &&
        decode_codelens_position(raw_position, model) is Some(position) else {
        return None
      }
      let locations : Array[@language.Location] = []
      for raw_location in raw_locations {
        guard decode_codelens_location(raw_location, context) is Some(location) else {
          return None
        }
        locations.push(location)
      }
      Some(LocalReferences(position~, locations~))
    }
    (MoonIdeOutsideReferencesCommand, [String(resource), raw_position]) => {
      guard resource == request.resource.to_string() &&
        decode_codelens_position(raw_position, model) is Some(position) else {
        return None
      }
      Some(OutsideReferences(position~))
    }
    _ => None
  }
}

///|
priv struct MoonIdeCodeLensFence {
  viewer_id : String
  model : @model.TextModel
  version_id : Int
  resource : String
  context : NavigationContext
}

///|
fn MoonIdeCodeLensFence::matches(
  self : MoonIdeCodeLensFence,
  viewer_id : String,
  model : @model.TextModel?,
  context : NavigationContext?,
) -> Bool {
  guard viewer_id == self.viewer_id &&
    model is Some(model) &&
    model.same(self.model) &&
    model.get_version_id() == self.version_id &&
    model.uri.to_string() == self.resource &&
    context == Some(self.context) else {
    return false
  }
  true
}

///|
fn MoonIdeCodeLensFence::is_current(self : MoonIdeCodeLensFence) -> Bool {
  guard mounted_viewer() is Some(viewer) else { return false }
  self.matches(viewer.get_id(), viewer.get_model(), viewer_state.navigation)
}

///|
fn moon_ide_code_lens_executor(
  on_error : (@interop.ConversationKey, String) -> Unit,
) -> @code_lens_api.CodeLensCommandExecutorHandle {
  @code_lens_api.CodeLensCommandExecutorHandle(execute=request => {
    guard mounted_viewer() is Some(viewer) &&
      viewer.get_id() == request.source_viewer_id &&
      viewer.get_model() is Some(model) &&
      moon_ide_codelens_source_projection(model) is Some(projection) else {
      return false
    }
    let fence : MoonIdeCodeLensFence = {
      viewer_id: viewer.get_id(),
      model,
      version_id: model.get_version_id(),
      resource: request.resource.to_string(),
      context: projection.context,
    }
    guard fence.is_current() &&
      decode_moonide_codelens_command(request, model, projection.context)
      is Some(execution) else {
      return false
    }
    match execution {
      LocalReferences(position~, locations~) => {
        // The References controller keys its session to the Viewer's current
        // symbol anchor. A CodeLens click originates outside the text surface,
        // so move the cursor to the command's authorized symbol before opening
        // the already-computed Local result set.
        viewer.set_position(position)
        viewer.show_references(position, locations)
        true
      }
      OutsideReferences(position~) => {
        let locations = request_moon_ide_locations(
          projection.context.owner.channel,
          @commands.moonide_references,
          {
            session: projection.context.owner.session,
            root: projection.context.root.path,
            path: projection.path.0,
            line: projection.source_line_number(position.line_number),
            column: position.column,
          },
        ) catch {
          error => {
            if fence.is_current() {
              on_error(
                projection.context.owner,
                "Find references failed: \{@interop.bridge_error_text(error)}",
              )
            }
            return true
          }
        }
        if fence.is_current() {
          // The async Outside lookup may finish while the cursor still points
          // somewhere unrelated to the CodeLens. Re-establish the command's
          // symbol anchor only after the stale fence has passed.
          viewer.set_position(position)
          viewer.show_references(position, locations)
        }
        true
      }
    }
  })
}
