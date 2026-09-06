// Page-lifetime vertical split between current Changes and Git Graph. The
// permanent file-tree pane owns the CSS custom property, so ordinary Rabbita
// renders do not reset a drag.

///|
const GitGraphResizeHandleId = "git-graph-resize-handle"

///|
const GitGraphLayoutId = "review-git-layout"

///|
const GitGraphChangesSectionId = "review-changes-section"

///|
const MinReviewSectionHeight = 96

///|
let git_graph_resize_installed : Ref[Bool] = Ref(false)

///|
let git_graph_resizing : Ref[Bool] = Ref(false)

///|
fn set_git_graph_split(height : Int) -> Unit {
  guard document_element() is Some(root) else { return }
  let style : @js.Value = @js.Value::cast_from(root).get_with_string("style")
  let _ : @js.Value = style.apply_with_string("setProperty", [
    @js.Value::cast_from("--review-changes-height"),
    @js.Value::cast_from("\{height}px"),
  ])
}

///|
fn request_git_graph_resize_mount() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      if git_graph_resize_installed.val {
        return
      }
      let document : @js.Value = @js.globalThis.get_with_string("document")
      // The handle is part of Rabbita's rendered tree and may be replaced when
      // the user enters Review. Delegate from the stable document instead of
      // retaining the first (possibly detached) element.
      @interop.add_capture_listener(document, "mousedown", event => {
        guard event.to_mouse_event() is Some(mouse) &&
          mouse.get_button() == 0 &&
          event.target().to_element() is Some(element) &&
          element.closest("#\{GitGraphResizeHandleId}") is Some(_) else {
          return
        }
        event.prevent_default()
        git_graph_resizing.val = true
        set_root_class("is-resizing-review")
      })
      @interop.add_capture_listener(document, "mousemove", event => {
        guard git_graph_resizing.val &&
          event.to_mouse_event() is Some(mouse) &&
          @dom.document().get_element_by_id(GitGraphLayoutId).to_option()
          is Some(layout) else {
          return
        }
        let rect = layout.get_bounding_client_rect()
        let height = drag_size(
          mouse.get_client_y() - rect.get_top(),
          floor=MinReviewSectionHeight.to_double(),
          max=rect.get_height() - MinReviewSectionHeight.to_double(),
        )
        set_git_graph_split(height)
      })
      @interop.add_capture_listener(document, "mouseup", _ => {
        end_drag(git_graph_resizing)
      })
      git_graph_resize_installed.val = true
    },
    kind=@cmd.after_render,
  )
}

///|
fn adjust_git_graph_split(delta : Int) -> Unit {
  guard @dom.document().get_element_by_id(GitGraphLayoutId).to_option()
    is Some(layout) &&
    @dom.document().get_element_by_id(GitGraphChangesSectionId).to_option()
    is Some(changes) else {
    return
  }
  let layout_rect = layout.get_bounding_client_rect()
  let current = changes.get_bounding_client_rect().get_height()
  set_git_graph_split(
    drag_size(
      current + delta.to_double(),
      floor=MinReviewSectionHeight.to_double(),
      max=layout_rect.get_height() - MinReviewSectionHeight.to_double(),
    ),
  )
}
