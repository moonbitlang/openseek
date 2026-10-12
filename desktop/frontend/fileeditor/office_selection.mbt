///|
pub(all) struct OfficeSelectionPreview {
  owner : @interop.ConversationKey
  epoch : Int32
  path : @common.Uri
  sig : String
  pdf_generation : Int32?
  materialized : String
  summary : @mention_context.OfficeSelectionSummary
} derive(Eq)

///|
pub extend OfficeSelectionPreview with Eq::{equal, not_equal}

///|
pub fn State::accepts_office_callback(
  self : State,
  ctx : Ctx,
  owner : @interop.ConversationKey,
  epoch : Int32,
  path : @common.Uri,
  sig : String,
) -> Bool {
  ctx.panel_open &&
  self.owner == Some(owner) &&
  ctx.owner == owner &&
  self.request_epoch == epoch &&
  ctx.active_file == Some(path) &&
  ctx.active_history_diff is None &&
  (match self.docs.get(path) {
    Some({ state: TabOffice(sig=current, ..), stale: false, .. }) =>
      current == sig
    _ => false
  })
}

///|
/// Recheck the source at confirmation time, including PDF runtime identity.
pub fn State::pending_office_selection(
  self : State,
  ctx : Ctx,
) -> OfficeSelectionPreview? {
  guard self.office_selection is Some(preview) && ctx.panel_open else {
    return None
  }
  let valid = match preview.pdf_generation {
    Some(generation) =>
      self.accepts_pdf_callback(
        ctx,
        preview.owner,
        preview.epoch,
        preview.path,
        preview.sig,
        generation,
      ) &&
      (match self.docs.get(preview.path) {
        Some({ state: TabPdf(document~, ..), .. }) =>
          document.status is PdfReady
        _ => false
      })
    None =>
      self.accepts_office_callback(
        ctx,
        preview.owner,
        preview.epoch,
        preview.path,
        preview.sig,
      )
  }
  if valid {
    Some(preview)
  } else {
    None
  }
}

///|
pub fn State::offer_office_selection(
  self : State,
  ctx : Ctx,
  raw : String,
) -> Result[State, String] {
  guard ctx.panel_open &&
    self.owner == Some(ctx.owner) &&
    ctx.active_history_diff is None &&
    ctx.active_file is Some(path) else {
    return Ok(self)
  }
  // A typed draft pins its original source until submission or cancellation.
  if self.pending_office_selection(ctx) is Some(_) &&
    self.office_selection_comment is Some(comment) &&
    !comment.trim().is_empty() {
    return Ok(self)
  }
  let (sig, pdf_generation) = match self.docs.get(path) {
    Some({ state: TabOffice(sig~, ..), stale: false, .. }) => (sig, None)
    Some({ state: TabPdf(document~, sig~), stale: false, .. }) if document.status
      is PdfReady => (sig, Some(document.generation))
    _ => return Ok(self)
  }
  let materialized = match
    @office_viewer.materialize_selection_preview(raw, 4000) {
    Ok(value) => value
    Err(_) => return Err(ui(ctx.locale, OfficeSelectionFailed))
  }
  guard @mention_context.office_selection_summary(materialized) is Some(summary) &&
    summary.file == path.path else {
    return Err(ui(ctx.locale, OfficeSelectionFailed))
  }
  Ok({
    ..self,
    office_selection_comment: Some(""),
    office_selection: Some({
      owner: ctx.owner,
      epoch: self.request_epoch,
      path,
      sig,
      pdf_generation,
      materialized,
      summary,
    }),
  })
}

///|
pub fn State::dismiss_office_selection(
  self : State,
  ctx : Ctx,
  candidate : OfficeSelectionPreview,
) -> (@cmd.Cmd, State) {
  guard self.pending_office_selection(ctx) is Some(preview) &&
    preview == candidate else {
    return (@cmd.none, self)
  }
  (
    @cmd.batch([
      hide_office_feedback(),
      @office_viewer.clear_selection_command(OfficeSurfaceId),
    ]),
    { ..self, office_selection: None, office_selection_comment: None, },
  )
}

///|
fn State::sync_office_selection(self : State, ctx : Ctx) -> State {
  if self.office_selection is Some(_) &&
    self.pending_office_selection(ctx) is None {
    { ..self, office_selection: None, office_selection_comment: None, }
  } else {
    self
  }
}
