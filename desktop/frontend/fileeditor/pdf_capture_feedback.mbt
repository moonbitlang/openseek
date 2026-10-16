///|
const PdfCaptureFeedbackHostId = "pdf-capture-feedback"

///|
priv struct PdfCaptureFeedbackMount {
  input : @viewer.FeedbackComposer
}

///|
let pdf_capture_feedback : Ref[PdfCaptureFeedbackMount?] = Ref(None)

///|
fn pdf_capture_feedback_view(state : State, ctx : Ctx) -> @html.Html {
  @html.div(
    id=PdfCaptureFeedbackHostId,
    class=if state.pending_region_feedback(ctx) is Some(_) {
      "pdf-capture-feedback editor-shell"
    } else {
      "pdf-capture-feedback editor-shell hidden"
    },
    attrs=@html.Attrs::build().data_set(
      "theme",
      if ctx.dark_mode {
        "dark"
      } else {
        "light"
      },
    ),
    ([] : Array[@html.Html]),
  )
}

///|
fn show_pdf_capture_feedback(
  emit : @cmd.Emit[Msg],
  draft : RegionFeedbackDraft,
  batch~ : Bool,
  submit : (String, Bool) -> @cmd.Cmd,
  alive : Ref[Bool],
) -> @cmd.Cmd {
  let preview = draft.preview
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    guard alive.val else { return }
    dispose_pdf_capture_feedback()
    guard @dom.document()
      .get_element_by_id(PdfCaptureFeedbackHostId)
      .to_option()
      is Some(host) &&
      @dom.document().get_element_by_id(OfficeSurfaceId).to_option()
      is Some(surface) &&
      surface.get_parent_element() is Some(viewport) &&
      viewer_state.services is Some(services) else {
      return
    }
    if preview.label() is Some(label) {
      host.set_attribute("data-annotation", label)
      host.set_attribute("style", "--office-region-label: '\{label}';")
    } else {
      host.remove_attribute("data-annotation")
      host.remove_attribute("style")
    }
    let rects = () => preview.rects(surface)
    let anchor = () => {
      let visible = rects().filter(rect => {
        let bounds = viewport.get_bounding_client_rect()
        rect.get_bottom() >= bounds.get_top() &&
        rect.get_top() <= bounds.get_bottom()
      })
      visible.last()
    }
    let input = services.viewer_services.create_feedback_composer(
      host,
      viewport~,
      layout_source=surface,
      allow_empty_submit=true,
      on_batch_change=batch => scheduler.add(emit(preview.batch_changed(batch))),
      on_submit=(text, apply) => scheduler.add(submit(text, apply)),
      on_change=text => scheduler.add(emit(preview.changed(text))),
      on_cancel=() => scheduler.add(emit(preview.dismissed())),
    )
    pdf_capture_feedback.val = Some({ input, })
    input.show(
      anchor,
      selection_rects=rects,
      prefer_below=true,
      text=draft.comment,
      batch~,
    )
    surface.set_attribute("tabindex", "-1")
    @base_browser.focus_prevent_scroll(surface)
  })
}

///|
fn dispose_pdf_capture_feedback() -> Unit {
  if pdf_capture_feedback.val is Some(mount) {
    mount.input.dispose()
    pdf_capture_feedback.val = None
  }
}

///|
fn hide_pdf_capture_feedback() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => dispose_pdf_capture_feedback(), kind=@cmd.after_render)
}

///|
/// Re-measure page-relative rectangles so the feedback follows scroll and zoom.
fn pdf_capture_rects(
  surface : @dom.Element,
  capture : @pdf_capture.Capture,
) -> Array[@dom.DOMRect] {
  let rects : Array[@dom.DOMRect] = []
  let maybe_session : @js.Nullable[@js.Value] = @js.Value::cast_from(surface).get_with_string(
    "__officeViewerPdf",
  )
  guard maybe_session.to_option() is Some(session) else { return rects }
  let viewer : @js.Value = session.get_with_string("viewer")
  let rotation : Int32 = viewer.get_with_string("pagesRotation")
  for original in capture.regions {
    let region = original.rotated((rotation - capture.rotation + 360) % 360)
    guard surface.query_selector(".page[data-page-number='\{region.page}']")
      is Some(page) else {
      continue
    }
    let b = page.get_bounding_client_rect()
    let rect : @dom.DOMRect = @js.globalThis.new_with_string("DOMRect", [
      b.get_left() + region.x * b.get_width(),
      b.get_top() + region.y * b.get_height(),
      region.width * b.get_width(),
      region.height * b.get_height(),
    ])
    rects.push(rect)
  }
  rects
}

///|
priv suberror PdfFeedbackSubscription {
  PdfFeedbackSubscription(
    @cmd.Emit[Msg],
    RegionFeedbackDraft,
    Bool,
    (String, Bool) -> @cmd.Cmd
  )
}

///|
pub fn region_feedback_subscription(
  emit : @cmd.Emit[Msg],
  draft : RegionFeedbackDraft,
  batch~ : Bool,
  submit : (String, Bool) -> @cmd.Cmd,
) -> @sub.Sub {
  @sub.custom_sub(
    "pdf-capture-feedback",
    @sub.Local,
    PdfFeedbackSubscription(emit, draft, batch, submit),
    (payload, scheduler) => {
      guard payload is PdfFeedbackSubscription(emit, draft, batch, submit) else {
        return None
      }
      let alive = Ref(true)
      scheduler.add(
        show_pdf_capture_feedback(emit, draft, batch~, submit, alive),
      )
      Some({
        unload: _ => {
          alive.val = false
          dispose_pdf_capture_feedback()
        },
        update_tagger: _ => (),
      })
    },
  )
}

///|
pub fn pdf_capture_feedback_subscription(
  emit : @cmd.Emit[Msg],
  draft : PdfCaptureDraft,
  batch~ : Bool,
  submit : (String, Bool) -> @cmd.Cmd,
) -> @sub.Sub {
  region_feedback_subscription(
    emit,
    { preview: Pdf(draft.preview), comment: draft.comment, },
    batch~,
    submit,
  )
}
