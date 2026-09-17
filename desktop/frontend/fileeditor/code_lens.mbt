// MoonIDE owns titles and reference lookup. The host decodes its CLI output;
// this adapter supplies complete actions to the live Source Viewer.

///|
let moon_ide_code_lens_changes : @common.Emitter[Unit] = Emitter()

///|
fn moon_ide_codelens_source_model_matches(
  candidate : @model.TextModel,
  source_model : @model.TextModel?,
) -> Bool {
  source_model is Some(source) && source.same(candidate)
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
fn project_codelens_position(
  model : @model.TextModel,
  position : @protocol.LspPosition,
) -> @common.Position? {
  guard position.line >= 0 &&
    position.character >= 0 &&
    position.line < 0x7fff_ffff &&
    position.character < 0x7fff_ffff else {
    return None
  }
  let point = @common.Position(position.line + 1, position.character + 1)
  if model.validate_position(point) == point {
    Some(point)
  } else {
    None
  }
}

///|
fn project_codelens_range(
  model : @model.TextModel,
  range : @protocol.LspRange,
) -> @common.Range? {
  guard project_codelens_position(model, range.start) is Some(start) &&
    project_codelens_position(model, range.end) is Some(end) &&
    (
      end.line_number > start.line_number ||
      (end.line_number == start.line_number && end.column >= start.column)
    ) else {
    return None
  }
  Some(
    @common.Range(start.line_number, start.column, end.line_number, end.column),
  )
}

///|
priv struct MoonIdeCodeLensProvider {
  on_error : (@interop.ConversationKey, String) -> Unit
}

///|
impl @language.CodeLensProvider for MoonIdeCodeLensProvider with fn provide_code_lenses(
  self,
  model,
  token,
) {
  guard !token.is_cancellation_requested() &&
    moon_ide_codelens_source_projection(model) is Some(projection) else {
    return []
  }
  let version = model.get_version_id()
  let is_current = () => {
    !token.is_cancellation_requested() &&
    model.get_version_id() == version &&
    moon_ide_codelens_source_projection(model) is Some(current) &&
    current.context == projection.context &&
    current.path == projection.path
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
  guard is_current() else { return [] }
  let lenses : Array[@language.CodeLens] = []
  for lens in reply.lenses {
    guard project_codelens_range(model, lens.range) is Some(range) else {
      continue
    }
    let raw_position = match lens.action {
      @protocol.Local(position~, ..) | @protocol.Outside(position~) => position
    }
    guard project_codelens_position(model, raw_position) is Some(position) else {
      continue
    }
    lenses.push({
      range,
      title: lens.title,
      tooltip: None,
      execute: () => {
        guard is_current() else { return }
        let locations = match lens.action {
          @protocol.Local(locations~, ..) =>
            MoonIdeProjection::{
              reply: { locations, },
              channel: projection.context.owner.channel,
            }.to_viewer()
          @protocol.Outside(_) =>
            request_moon_ide_locations(
              projection.context.owner.channel,
              @commands.moonide_references,
              {
                session: projection.context.owner.session,
                root: projection.context.root.path,
                path: projection.path.0,
                line: position.line_number,
                column: position.column,
              },
            ) catch {
              error => {
                if is_current() {
                  (self.on_error)(
                    projection.context.owner,
                    "Find references failed: \{@interop.bridge_error_text(error)}",
                  )
                }
                return
              }
            }
        }
        guard is_current() && mounted_viewer() is Some(viewer) else { return }
        viewer.set_position(position)
        viewer.show_references(position, locations)
      },
    })
  }
  lenses
}

///|
fn register_moon_ide_code_lens_provider(
  on_error : (@interop.ConversationKey, String) -> Unit,
) -> @common.Disposable {
  @languages.languages.register_code_lens_provider(
    LanguageFilter(LanguageFilter(language="moonbit", scheme=@resource.Scheme)),
    MoonIdeCodeLensProvider::{ on_error, },
    on_did_change=listener => moon_ide_code_lens_changes.event(_ => listener()),
  )
}
