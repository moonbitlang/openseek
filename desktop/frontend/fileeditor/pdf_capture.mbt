///|
/// Capture callbacks carry the same source identity as PDF text selections.
pub fn capture_pdf_region(
  emit : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @cmd.Cmd {
  let owner = ctx.owner
  guard ctx.panel_open &&
    active_pdf_document(state, ctx) is Some((path, document, sig)) &&
    document.status is PdfReady else {
    return @cmd.none
  }
  @cmd.batch([
    @office_viewer.clear_selection_command(OfficeSurfaceId),
    hide_office_feedback(),
    hide_pdf_capture_feedback(),
    @pdf_capture.start(
      OfficeSurfaceId,
      hint=ui(ctx.locale, PdfCaptureHint),
      failure=ui(ctx.locale, PdfCaptureFailed),
      too_large=ui(ctx.locale, PdfCaptureTooLarge),
      unsupported_annotation=ui(ctx.locale, PdfCaptureUnsupportedAnnotation),
      emit.map(result => {
        PdfCaptureFinished(
          owner~,
          epoch=state.surface_epoch(ctx.owner),
          path~,
          sig~,
          generation=document.generation,
          result~,
        )
      }),
    ),
  ])
}

///|
pub fn capture_unavailable_message(locale : @i18n.Locale) -> String {
  ui(locale, PdfCaptureUnavailable)
}

///|
pub fn capture_submission_declined_message(locale : @i18n.Locale) -> String {
  ui(locale, PdfCaptureSubmissionFailed)
}

///|
pub(all) struct PdfCapturePreview {
  id : Int64
  owner : @interop.ConversationIdentity
  epoch : Int32
  path : @common.Uri
  sig : String
  generation : Int32
  capture : @pdf_capture.Capture
} derive(Eq)

///|
pub(all) struct PdfCaptureDraft {
  preview : PdfCapturePreview
  comment : String
} derive(Eq)

///|
pub fn State::pending_pdf_capture(self : State, ctx : Ctx) -> PdfCaptureDraft? {
  guard ctx.panel_open && self.pdf_capture is Some(draft) else { return None }
  let p = draft.preview
  if self.accepts_pdf_callback(
      ctx,
      p.owner,
      p.epoch,
      p.path,
      p.sig,
      p.generation,
    ) {
    Some(draft)
  } else {
    None
  }
}

///|
fn State::dismiss_pdf_capture(
  self : State,
  ctx : Ctx,
  preview : PdfCapturePreview,
) -> (@cmd.Cmd, State) {
  guard self.pending_pdf_capture(ctx).map(draft => draft.preview) ==
    Some(preview) else {
    return (@cmd.none, self)
  }
  (hide_pdf_capture_feedback(), { ..self, pdf_capture: None, })
}

///|
fn State::sync_pdf_capture(self : State, ctx : Ctx) -> (@cmd.Cmd, State) {
  if self.pdf_capture is Some(_) && self.pending_pdf_capture(ctx) is None {
    (hide_pdf_capture_feedback(), { ..self, pdf_capture: None, })
  } else {
    (@cmd.none, self)
  }
}

///|
pub extend PdfCapturePreview with Eq::{equal, not_equal}

///|
pub extend PdfCaptureDraft with Eq::{equal, not_equal}

///|
/// Use the shared Office mention envelope for screenshot feedback. Region
/// geometry has no text-range reference that office.read can resolve.
fn PdfCapturePreview::materialized_selection(
  self : PdfCapturePreview,
  comment : String,
) -> String {
  let selection : Map[String, Json] = {
    "format": "pdf",
    "kind": "pdf-region",
    "pages": Json::array(
      self.capture.regions.map(region => Json::number(region.page.to_double())),
    ),
  }
  match self.capture.text {
    Some(text) => selection.set("text", Json::string(text))
    None => ()
  }
  let payload : Map[String, Json] = {
    "schema": "office.selection.materialized.v1",
    "mode": "full",
    "selection": Json::object(selection),
    "source": {
      "file": reference_file(self.owner, self.path),
      "format": "pdf",
      "capture": self.capture.source,
      "readable": false,
      "reason": "Visual region; inspect the attached screenshot or render these PDF page coordinates.",
    },
  }
  if !comment.trim().is_empty() {
    payload.set("comment", Json::string(comment.trim().to_owned()))
  }
  Json::object(payload).stringify()
}
