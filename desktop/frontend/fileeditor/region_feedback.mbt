///|
/// Both capture paths use the same anchored composer and delivery handshake.
pub(all) enum RegionFeedbackPreview {
  Pdf(PdfCapturePreview)
  Office(OfficeRegionPreview)
} derive(Eq)

///|
pub(all) struct RegionFeedbackDraft {
  preview : RegionFeedbackPreview
  comment : String
} derive(Eq)

///|
pub fn State::pending_region_feedback(
  self : State,
  ctx : Ctx,
) -> RegionFeedbackDraft? {
  if self.pending_office_region(ctx) is Some(draft) {
    Some({ preview: Office(draft.preview), comment: draft.comment, })
  } else {
    self
    .pending_pdf_capture(ctx)
    .map(draft => { preview: Pdf(draft.preview), comment: draft.comment, })
  }
}

///|
fn RegionFeedbackPreview::path(self : RegionFeedbackPreview) -> @common.Uri {
  match self {
    Pdf(p) => p.path
    Office(p) => p.request.path
  }
}

///|
pub fn RegionFeedbackPreview::url(self : RegionFeedbackPreview) -> String {
  match self {
    Pdf(p) => p.capture.url
    Office(p) => p.capture.url
  }
}

///|
pub fn RegionFeedbackPreview::key(self : RegionFeedbackPreview) -> String {
  match self {
    Pdf(p) =>
      "pdf:\{p.owner.key()}:\{p.path.to_string()}:\{p.epoch}:\{p.generation}:\{p.id}"
    Office({ request: p, .. }) =>
      "office:\{p.owner.key()}:\{p.path.to_string()}:\{p.epoch}:\{p.id}"
  }
}

///|
pub fn RegionFeedbackPreview::materialized_selection(
  self : RegionFeedbackPreview,
  comment : String,
) -> String {
  match self {
    Pdf(p) => p.materialized_selection(comment)
    Office(p) => p.materialized_selection(comment)
  }
}

///|
pub fn RegionFeedbackPreview::dismissed(self : RegionFeedbackPreview) -> Msg {
  match self {
    Pdf(p) => PdfCaptureDismissed(p)
    Office(p) => OfficeRegionDismissed(p)
  }
}

///|
pub fn RegionFeedbackPreview::declined(self : RegionFeedbackPreview) -> Msg {
  match self {
    Pdf(p) => PdfCaptureSubmissionDeclined(p)
    Office(p) => OfficeRegionSubmissionDeclined(p)
  }
}

///|
fn RegionFeedbackPreview::changed(
  self : RegionFeedbackPreview,
  text : String,
) -> Msg {
  match self {
    Pdf(p) => PdfCaptureFeedbackChanged(p, text)
    Office(p) => OfficeRegionFeedbackChanged(p, text)
  }
}

///|
fn RegionFeedbackPreview::batch_changed(
  self : RegionFeedbackPreview,
  batch : Bool,
) -> Msg {
  match self {
    Pdf(p) => PdfCaptureBatchChanged(p, batch)
    Office(p) => OfficeRegionBatchChanged(p, batch)
  }
}

///|
fn RegionFeedbackPreview::rects(
  self : RegionFeedbackPreview,
  surface : @dom.Element,
) -> Array[@dom.DOMRect] {
  match self {
    Pdf(p) => pdf_capture_rects(surface, p.capture)
    Office(p) => p.capture.selection_rects(surface)
  }
}

///|
pub extend RegionFeedbackPreview with Eq::{equal, not_equal}

///|
pub extend RegionFeedbackDraft with Eq::{equal, not_equal}

///|
pub fn RegionFeedbackPreview::image_name(
  self : RegionFeedbackPreview,
) -> String {
  let name = @common.basename_or_authority(self.path())
  match self {
    Pdf(_) => name + "-capture.png"
    Office(p) => name + "-region-" + p.request.id.to_string() + ".png"
  }
}

///|
fn RegionFeedbackPreview::label(self : RegionFeedbackPreview) -> String? {
  match self {
    Pdf(_) => None
    Office(p) => Some(p.request.id.to_string())
  }
}
