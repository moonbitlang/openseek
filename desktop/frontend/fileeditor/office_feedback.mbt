///|
const OfficeFeedbackHostId = "office-feedback-input"

///|
priv struct OfficeFeedbackMount {
  host : @dom.Element
  input : @viewer.FeedbackComposer
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
    // Excel prevents the pointer default while selecting cells. Give the
    // document focus so its scoped shortcuts receive the next key event.
    if surface.query_selector(".office-cell-active") is Some(_) {
      surface.set_attribute("tabindex", "-1")
      @base_browser.focus_prevent_scroll(surface)
    }
    if office_feedback_mount.val is Some(mounted) &&
      @base_browser.element_contains(host, mounted.host) {
      if mounted.target.val != Some(preview) {
        guard office_feedback_anchor(surface, preview)
          is Some((anchor, selection_rects, prefer_below)) else {
          // Never associate a new target with an old visible anchor.
          mounted.target.val = None
          mounted.input.hide()
          scheduler.add(emit(OfficeSelectionDismissed(preview)))
          return
        }
        mounted.target.val = Some(preview)
        mounted.input.show(anchor, selection_rects~, prefer_below~)
      }
      return
    }
    guard office_feedback_anchor(surface, preview)
      is Some((anchor, selection_rects, prefer_below)) else {
      dispose_office_feedback()
      scheduler.add(emit(OfficeSelectionDismissed(preview)))
      return
    }
    guard viewer_state.services is Some(services) else { return }
    dispose_office_feedback()
    let target = Ref(Some(preview))
    let input = services.viewer_services.create_feedback_composer(
      host,
      viewport~,
      layout_source=surface,
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
    input.show(anchor, selection_rects~, prefer_below~)
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
) -> (() -> @dom.DOMRect?, () -> Array[@dom.DOMRect], Bool)? {
  let document : @js.Value = @js.Value::cast_from(surface).get_with_string(
    "ownerDocument",
  )
  let selection : @js.Nullable[@js.Value] = document.apply_with_string(
    "getSelection",
    ([] : FixedArray[@js.Value]),
  )
  if selection.to_option() is Some(selection) {
    let count : Int32 = selection.get_with_string("rangeCount")
    let collapsed : Bool = selection.get_with_string("isCollapsed")
    if count == 1 && !collapsed {
      let range : @js.Value = selection.apply_with_string("getRangeAt", [0])
      let start : @dom.Node = range.get_with_string("startContainer")
      let end : @dom.Node = range.get_with_string("endContainer")
      if surface.contains(start) && surface.contains(end) {
        let focus : @dom.Node = selection.get_with_string("focusNode")
        let offset : Int32 = selection.get_with_string("focusOffset")
        let end_offset : Int32 = range.get_with_string("endOffset")
        let prefer_below = focus.is_same_node(end) && offset == end_offset
        if preview.pdf_generation is Some(_) {
          return pdf_feedback_range(surface, preview.materialized).map(range => {
            pdf_feedback_anchor(range, prefer_below)
          })
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
            () => {
              if surface.contains(start) && surface.contains(end) {
                feedback_range_rects(pinned)
              } else {
                []
              }
            },
            prefer_below,
          ),
        )
      }
    }
  }
  // PDF source identity survives replacement of the native Selection and
  // text layer. The resolver can remain mounted while its DOM is unavailable;
  // the composer's mutation observer retries when the text layer returns.
  if preview.pdf_generation is Some(_) {
    return pdf_feedback_range(surface, preview.materialized).map(range => {
      pdf_feedback_anchor(range, true)
    })
  }
  // Cell selections and imported comments have element anchors instead.
  let element = surface.query_selector(
    ".office-cell-active, .office-annotation-selected",
  )
  // Snapshot the source cells, not the live selection classes: a typed draft
  // stays attached to this range while the user selects other cells.
  let cells = surface
    .query_selector_all(".office-cell-selected")
    .iter()
    .to_array()
  element.map(element => {
    (
      () => {
        if @base_browser.element_is_connected(element) {
          Some(element.get_bounding_client_rect())
        } else {
          None
        }
      },
      () => {
        cells
        .filter(@base_browser.element_is_connected)
        .map(cell => cell.get_bounding_client_rect())
      },
      true,
    )
  })
}

///|
fn pdf_feedback_anchor(
  measure_range : () -> @js.Value?,
  prefer_below : Bool,
) -> (() -> @dom.DOMRect?, () -> Array[@dom.DOMRect], Bool) {
  (
    () => {
      measure_range().map(range => {
        let endpoint : @js.Value = range.apply_with_string(
          "cloneRange",
          ([] : FixedArray[@js.Value]),
        )
        let _ : @js.Value = endpoint.apply_with_string("collapse", [
          !prefer_below,
        ])
        endpoint.apply_with_string(
          "getBoundingClientRect",
          ([] : FixedArray[@js.Value]),
        )
      })
    },
    () => measure_range().map(feedback_range_rects).unwrap_or([]),
    prefer_below,
  )
}

///|
/// PDF.js recreates the text layer at a new scale. Resolve the saved item and
/// UTF-16 endpoint every time instead of retaining a detached browser Range.
fn pdf_feedback_range(
  surface : @dom.Element,
  materialized : String,
) -> (() -> @js.Value?)? {
  let value = @json.parse(materialized) catch { _ => return None }
  guard value
    is { "source": { "reference": { "start": start, "end": end, .. }, .. }, .. } else {
    return None
  }
  Some(() => {
    guard pdf_feedback_endpoint(surface, start)
      is Some((start_node, start_offset)) &&
      pdf_feedback_endpoint(surface, end) is Some((end_node, end_offset)) else {
      return None
    }
    let document : @js.Value = @js.Value::cast_from(surface).get_with_string(
      "ownerDocument",
    )
    let range : @js.Value = document.apply_with_string(
      "createRange",
      ([] : FixedArray[@js.Value]),
    )
    let _ : @js.Value = range.apply_with_string("setStart", [
      @js.Value::cast_from(start_node),
      @js.Value::cast_from(start_offset),
    ])
    let _ : @js.Value = range.apply_with_string("setEnd", [
      @js.Value::cast_from(end_node),
      @js.Value::cast_from(end_offset),
    ])
    Some(range)
  })
}

///|
fn pdf_feedback_endpoint(
  surface : @dom.Element,
  endpoint : Json,
) -> (@dom.Node, Int32)? {
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
      return Some((node, remaining))
    }
    remaining -= length
  }
  None
}

///|
/// Enumerate text fragments only: a cross-page Range also reports page and
/// canvas boxes, which must not become full-page selection backgrounds.
fn feedback_range_rects(range : @js.Value) -> Array[@dom.DOMRect] {
  let root : @dom.Node = range.get_with_string("commonAncestorContainer")
  let document : @js.Value = @js.Value::cast_from(root).get_with_string(
    "ownerDocument",
  )
  let walker : @js.Value = document.apply_with_string("createTreeWalker", [
    @js.Value::cast_from(root),
    @js.Value::cast_from(4),
  ])
  let rects : Array[@dom.DOMRect] = []
  let mut current = Some(root)
  while current is Some(node) {
    let kind : Int32 = @js.Value::cast_from(node).get_with_string("nodeType")
    let intersects : Bool = range.apply_with_string("intersectsNode", [node])
    if kind == 3 && intersects {
      let contents : @js.Value = document.apply_with_string(
        "createRange",
        ([] : FixedArray[@js.Value]),
      )
      let _ : @js.Value = contents.apply_with_string("selectNodeContents", [
        node,
      ])
      let selected : @js.Value = range.apply_with_string(
        "cloneRange",
        ([] : FixedArray[@js.Value]),
      )
      let starts_before : Int32 = selected.apply_with_string(
        "compareBoundaryPoints",
        [@js.Value::cast_from(0), contents],
      )
      let ends_after : Int32 = selected.apply_with_string(
        "compareBoundaryPoints",
        [@js.Value::cast_from(2), contents],
      )
      if starts_before < 0 {
        let _ : @js.Value = selected.apply_with_string(
          "setStart",
          (
            [
              contents.get_with_string("startContainer"),
              contents.get_with_string("startOffset"),
            ] : FixedArray[@js.Value]),
        )
      }
      if ends_after > 0 {
        let _ : @js.Value = selected.apply_with_string(
          "setEnd",
          (
            [
              contents.get_with_string("endContainer"),
              contents.get_with_string("endOffset"),
            ] : FixedArray[@js.Value]),
        )
      }
      let fragments : @dom.DOMRectList = selected.apply_with_string(
        "getClientRects",
        ([] : FixedArray[@js.Value]),
      )
      for fragment in fragments.iter() {
        if fragment.get_width() > 0.0 && fragment.get_height() > 0.0 {
          rects.push(fragment)
        }
      }
    }
    let next : @js.Nullable[@dom.Node] = walker.apply_with_string(
      "nextNode",
      ([] : FixedArray[@js.Value]),
    )
    current = next.to_option()
  }
  rects
}
