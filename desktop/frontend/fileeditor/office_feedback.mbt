///|
const OfficeFeedbackHostId = "office-feedback-input"

///|
priv struct OfficeFeedbackMount {
  host : @dom.Element
  input : @feedback_input.FeedbackInput
  target : Ref[OfficeSelectionPreview?]
}

///|
let office_feedback_mount : Ref[OfficeFeedbackMount?] = Ref(None)

///|
/// DOM ownership stays inside commands; the model keeps only the draft text
/// and versioned source identity. Callbacks carry the selection they display.
pub fn show_office_feedback(
  emit : @cmd.Emit[Msg],
  preview : OfficeSelectionPreview,
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    guard @dom.document().get_element_by_id(OfficeFeedbackHostId).to_option()
      is Some(host) else {
      return
    }
    if office_feedback_mount.val is Some(mounted) &&
      @base_browser.element_contains(host, mounted.host) {
      if mounted.target.val != Some(preview) {
        mounted.target.val = Some(preview)
        mounted.input.show()
      }
      return
    }
    dispose_office_feedback()
    let target = Ref(Some(preview))
    let input = @feedback_input.FeedbackInput(
      host,
      localization=viewer_localization,
      on_submit=(text, apply) => {
        if target.val is Some(preview) {
          scheduler.add(emit(OfficeFeedbackSubmitted(preview, text, apply~)))
        }
      },
      on_change=text => {
        if target.val is Some(preview) {
          scheduler.add(emit(OfficeFeedbackChanged(preview, text)))
        }
      },
      on_cancel=() => {
        if target.val is Some(preview) {
          scheduler.add(emit(OfficeSelectionDismissed(preview)))
        }
      },
    )
    office_feedback_mount.val = Some({ host, input, target, })
    input.show()
  })
}

///|
fn hide_office_feedback() -> @cmd.Cmd {
  after_render_effect(() => {
    if office_feedback_mount.val is Some(mounted) {
      mounted.target.val = None
      mounted.input.hide()
    }
  })
}

///|
fn dispose_office_feedback() -> Unit {
  if office_feedback_mount.val is Some(mounted) {
    mounted.input.dispose()
    office_feedback_mount.val = None
  }
}
