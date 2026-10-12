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
    guard @dom.document().get_element_by_id(OfficeSurfaceId).to_option()
      is Some(surface) &&
      surface.get_parent_element() is Some(viewport) else {
      return
    }
    if office_feedback_mount.val is Some(mounted) &&
      @base_browser.element_contains(host, mounted.host) {
      if mounted.target.val != Some(preview) {
        mounted.target.val = Some(preview)
        if office_feedback_anchor(surface, preview)
          is Some((anchor, prefer_below)) {
          mounted.input.show(anchor, prefer_below~)
        }
      }
      return
    }
    dispose_office_feedback()
    let target = Ref(Some(preview))
    let input = @feedback_input.FeedbackInput(
      host,
      viewport~,
      layout_source=surface,
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
    if office_feedback_anchor(surface, preview) is Some((anchor, prefer_below)) {
      input.show(anchor, prefer_below~)
    }
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

///|
/// Capture the native range before textarea focus changes browser Selection.
/// Measure its active endpoint again after document scrolling and layout.
fn office_feedback_anchor(
  surface : @dom.Element,
  preview : OfficeSelectionPreview,
) -> (() -> @dom.DOMRect?, Bool)? {
  let document : @js.Value = @js.Value::cast_from(surface).get_with_string(
    "ownerDocument",
  )
  let selection : @js.Nullable[@js.Value] = document.apply_with_string(
    "getSelection",
    ([] : FixedArray[@js.Value]),
  )
  if selection.to_option() is Some(selection) {
    let count : Int = selection.get_with_string("rangeCount")
    let collapsed : Bool = selection.get_with_string("isCollapsed")
    if count == 1 && !collapsed {
      let range : @js.Value = selection.apply_with_string("getRangeAt", [0])
      let start : @dom.Node = range.get_with_string("startContainer")
      let end : @dom.Node = range.get_with_string("endContainer")
      if surface.contains(start) && surface.contains(end) {
        let focus : @dom.Node = selection.get_with_string("focusNode")
        let offset : Int = selection.get_with_string("focusOffset")
        let end_offset : Int = range.get_with_string("endOffset")
        let prefer_below = focus.is_same_node(end) && offset == end_offset
        if preview.pdf_generation is Some(_) &&
          pdf_feedback_anchor(surface, preview.materialized, prefer_below)
          is Some(anchor) {
          return Some((anchor, prefer_below))
        }
        let pinned : @js.Value = range.apply_with_string(
          "cloneRange",
          ([] : FixedArray[@js.Value]),
        )
        let endpoint : @js.Value = range.apply_with_string(
          "cloneRange",
          ([] : FixedArray[@js.Value]),
        )
        let _ : @js.Value = endpoint.apply_with_string("collapse", [
          !prefer_below,
        ])
        return Some(
          (
            () => {
              if !surface.contains(start) || !surface.contains(end) {
                return None
              }
              let rect : @dom.DOMRect = endpoint.apply_with_string(
                "getBoundingClientRect",
                ([] : FixedArray[@js.Value]),
              )
              if rect.get_height() > 0.0 {
                Some(rect)
              } else {
                let rects : @dom.DOMRectList = pinned.apply_with_string(
                  "getClientRects",
                  ([] : FixedArray[@js.Value]),
                )
                let visible = rects
                  .iter()
                  .filter(rect => rect.get_height() > 0.0)
                  .to_array()
                if visible.is_empty() {
                  None
                } else {
                  Some(
                    if prefer_below {
                      visible[visible.length() - 1]
                    } else {
                      visible[0]
                    },
                  )
                }
              }
            },
            prefer_below,
          ),
        )
      }
    }
  }
  // Cell selections and imported comments have element anchors instead.
  let element = surface.query_selector(
    ".office-cell-active, .office-annotation-selected",
  )
  element.map(element => {
    (
      () => {
        if @base_browser.element_is_connected(element) {
          Some(element.get_bounding_client_rect())
        } else {
          None
        }
      },
      true,
    )
  })
}

///|
/// PDF.js recreates the text layer at a new scale. Resolve the saved item and
/// UTF-16 endpoint every time instead of retaining a detached browser Range.
fn pdf_feedback_anchor(
  surface : @dom.Element,
  materialized : String,
  prefer_below : Bool,
) -> (() -> @dom.DOMRect?)? {
  let value = @json.parse(materialized) catch { _ => return None }
  guard value
    is { "source": { "reference": { "start": start, "end": end, .. }, .. }, .. } else {
    return None
  }
  let endpoint = if prefer_below { end } else { start }
  guard endpoint
    is {
      "page": Number(page, ..),
      "item_index": Number(item, ..),
      "offset_utf16": Number(offset, ..),
      ..
    } else {
    return None
  }
  let selector = "[data-pdf-page='\{page.to_int()}'][data-pdf-item='\{item.to_int()}']"
  Some(() => {
    guard surface.query_selector(selector) is Some(element) else { return None }
    let document : @js.Value = @js.Value::cast_from(element).get_with_string(
      "ownerDocument",
    )
    let walker : @js.Value = document.apply_with_string("createTreeWalker", [
      @js.Value::cast_from(element),
      @js.Value::cast_from(4),
    ])
    let mut remaining = offset.to_int()
    while true {
      let node : @js.Nullable[@dom.Node] = walker.apply_with_string(
        "nextNode",
        ([] : FixedArray[@js.Value]),
      )
      guard node.to_option() is Some(node) else { return None }
      let length = node.get_node_value().length()
      if remaining <= length {
        let range : @js.Value = document.apply_with_string(
          "createRange",
          ([] : FixedArray[@js.Value]),
        )
        let _ : @js.Value = range.apply_with_string("setStart", [
          @js.Value::cast_from(node),
          @js.Value::cast_from(remaining),
        ])
        let _ : @js.Value = range.apply_with_string("collapse", [true])
        let rect : @dom.DOMRect = range.apply_with_string(
          "getBoundingClientRect",
          ([] : FixedArray[@js.Value]),
        )
        return Some(rect)
      }
      remaining -= length
    }
    None
  })
}
