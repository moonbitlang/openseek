// The Office surface is a document renderer owned by the file panel. Its
// markup is produced by office-viewer, while this package owns the surrounding
// OpenSeek layout and the after-render interaction lifecycle.

///|
const OfficeSurfaceId = "openseek-office-surface"

///|
/// The XLSX renderer emits its own body/table rules and workbook style classes.
/// Scope its generated style blocks before either the view or interaction
/// commands mount them; application fonts and widgets stay owned by the host.
fn scope_excel_styles(surface_html : String) -> String {
  surface_html
  .replace(old="<style>", new="<style>@scope (#\{OfficeSurfaceId}) {\n")
  .replace(old="</style>", new="\n}</style>")
}

///|
fn empty_office_surface_config(state : State) -> @office_viewer.SurfaceConfig {
  {
    surface_id: OfficeSurfaceId,
    kind: None,
    document_file: "",
    surface_html: "",
    zoom: state.office_zoom,
    query: state.office_query,
    prefer_system_fonts: state.office_prefer_system_fonts,
  }
}

///|
fn office_surface_config(
  state : State,
  document : @office_viewer.RenderedDocument,
) -> @office_viewer.SurfaceConfig {
  {
    surface_id: OfficeSurfaceId,
    kind: Some(document.kind),
    document_file: document.file,
    surface_html: document.surface_html,
    zoom: state.office_zoom,
    query: state.office_query,
    prefer_system_fonts: state.office_prefer_system_fonts,
  }
}

///|
fn office_pinch_command(
  dispatch : @cmd.Emit[Msg],
  config : @office_viewer.SurfaceConfig,
) -> @cmd.Cmd {
  let pdf = config.kind == Some(Pdf)
  @office_viewer.pinch_zoom_command(
    config,
    zoom => dispatch(OfficeZoomChanged(zoom.to_string())),
    min_zoom=if pdf { 25 } else { 50 },
    max_zoom=if pdf { 400 } else { 200 },
  )
}

///|
/// Install native cursor/range selection and the fixed-font visual policy
/// after Rabbita has inserted the rendered Office surface. The callback keeps
/// the JSON envelope in the file-editor message stream; the root owns the
/// conversation and decides how to attach it to a composer.
fn show_office_document(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  state : State,
  path : @common.Uri,
  document : @office_viewer.RenderedDocument,
  sig : String,
) -> @cmd.Cmd {
  let config = office_surface_config(state, document)
  @cmd.batch([
    @office_viewer.interactions_command(config, selection => {
      dispatch(
        OfficeSelectionChanged(
          owner~,
          epoch=state.request_epoch,
          path~,
          sig~,
          selection~,
        ),
      )
    }),
    @office_viewer.visual_command(config),
    office_pinch_command(dispatch, config),
  ])
}

///|
/// Reapply embedded Office controls after a state-only toolbar update. The
/// surface HTML remains the same, so this avoids reparsing the package while
/// still updating zoom, search highlights, and the font preference.
fn refresh_office_visual(state : State, ctx : Ctx) -> @cmd.Cmd {
  guard ctx.active_history_diff is None && ctx.active_file is Some(path) else {
    return @cmd.none
  }
  match state.docs.get(path) {
    Some({ state: TabOffice(document~, ..), .. }) =>
      @office_viewer.visual_command(office_surface_config(state, document))
    Some({ state: TabPdf(..), .. }) =>
      @office_viewer.visual_command(pdf_surface_config(state, path))
    _ => @cmd.none
  }
}

///|
fn clear_office_surface() -> @cmd.Cmd {
  @cmd.batch([
    after_render_effect(() => dispose_office_feedback()),
    @office_viewer.dispose_interactions_command(OfficeSurfaceId),
  ])
}
