///|
/// A capture request pins both the document identity and its owning chat.
pub(all) struct OfficeRegionRequest {
  id : Int64
  owner : @interop.ConversationIdentity
  epoch : Int32
  path : @common.Uri
  sig : String
  pdf_generation : Int32?
} derive(Eq)

///|
pub(all) struct OfficeRegionPreview {
  request : OfficeRegionRequest
  capture : @office_capture.Capture
} derive(Eq)

///|
pub(all) struct OfficeRegionDraft {
  preview : OfficeRegionPreview
  comment : String
} derive(Eq)

///|
pub fn State::accepts_office_region(
  self : State,
  ctx : Ctx,
  request : OfficeRegionRequest,
) -> Bool {
  match request.pdf_generation {
    Some(generation) =>
      self.accepts_pdf_callback(
        ctx,
        request.owner,
        request.epoch,
        request.path,
        request.sig,
        generation,
      )
    None =>
      self.accepts_office_callback(
        ctx,
        request.owner,
        request.epoch,
        request.path,
        request.sig,
      )
  }
}

///|
pub fn State::pending_office_region(
  self : State,
  ctx : Ctx,
) -> OfficeRegionDraft? {
  self.office_region.filter(draft => {
    self.accepts_office_region(ctx, draft.preview.request)
  })
}

///|
pub fn State::start_office_region(
  self : State,
  ctx : Ctx,
  emit : @cmd.Emit[Msg],
) -> (@cmd.Cmd, State) {
  let owner = ctx.owner

  guard ctx.panel_open && ctx.active_file is Some(path) else {
    return (@cmd.none, self)
  }
  let (sig, format, pdf_generation) = match self.docs.get(path) {
    Some({ state: TabOffice(document~, sig~), stale: false, .. }) =>
      (
        sig,
        match document.kind {
          Word => @office_capture.Word
          Excel => @office_capture.Excel
          Pdf => @office_capture.Pdf
        },
        None,
      )
    Some({ state: TabPdf(document~, sig~), stale: false, .. }) if document.status
      is PdfReady => (sig, @office_capture.Pdf, Some(document.generation))
    _ => return (@cmd.none, self)
  }
  let request : OfficeRegionRequest = {
    id: self.office_region_id + 1L,
    owner,
    epoch: self.surface_epoch(ctx.owner),
    path,
    sig,
    pdf_generation,
  }
  (
    @cmd.batch([
      @office_viewer.clear_selection_command(OfficeSurfaceId),
      hide_office_feedback(),
      hide_pdf_capture_feedback(),
      @office_capture.start(
        OfficeSurfaceId,
        format,
        label=request.id.to_string(),
        hint=ui(ctx.locale, OfficeRegionHint),
        failure=ui(ctx.locale, OfficeRegionFailed),
        too_large=ui(ctx.locale, PdfCaptureTooLarge),
        unsupported_annotation=ui(ctx.locale, PdfCaptureUnsupportedAnnotation),
        emit.map(result => OfficeRegionFinished(request, result)),
      ),
    ]),
    {
      ..self,
      office_region_request: Some(request),
      office_region_id: request.id,
      office_selection: None,
      office_selection_comment: None,
      excel_copy_selection: None,
      excel_copy_feedback: None,
    },
  )
}

///|
fn State::sync_office_region(self : State, ctx : Ctx) -> (@cmd.Cmd, State) {
  let invalid_request = self.office_region_request is Some(request) &&
    !self.accepts_office_region(ctx, request)
  let invalid_draft = self.office_region is Some(_) &&
    self.pending_office_region(ctx) is None
  if invalid_request || invalid_draft {
    (
      @cmd.batch([
        @office_capture.cancel(OfficeSurfaceId),
        hide_pdf_capture_feedback(),
      ]),
      { ..self, office_region_request: None, office_region: None, },
    )
  } else {
    (@cmd.none, self)
  }
}

///|
pub fn OfficeRegionPreview::materialized_selection(
  self : OfficeRegionPreview,
  comment : String,
) -> String {
  let capture = self.capture
  let selection : Map[String, Json] = {
    "format": Json(capture.format.name()),
    "kind": "office-region",
    "pages": Json(
      capture.regions.filter_map(region => region.page).map(page => Json(page)),
    ),
  }
  if capture.text is Some(text) {
    selection.set("text", Json(text))
  }
  if capture.sheet is Some(sheet) {
    selection.set("sheet", Json(sheet))
  }
  if capture.range is Some(range_) {
    selection.set("range", Json(range_))
  }
  let payload : Map[String, Json] = {
    "schema": "office.selection.materialized.v1",
    "mode": "full",
    "selection": Json::object(selection),
    "source": {
      "file": Json(reference_file(self.request.owner, self.request.path)),
      "format": Json(capture.format.name()),
      "capture": capture.source,
      "readable": false,
      "reason": "Visual region; inspect the attached screenshot. Coordinates refer to the selected region, excluding the surrounding context.",
    },
    "annotation": Json(self.request.id.to_string()),
  }
  if !comment.trim().is_empty() {
    payload.set("comment", Json(comment.trim().to_owned()))
  }
  Json::object(payload).stringify()
}

///|
pub extend OfficeRegionRequest with Eq::{equal, not_equal}

///|
pub extend OfficeRegionPreview with Eq::{equal, not_equal}

///|
pub extend OfficeRegionDraft with Eq::{equal, not_equal}
