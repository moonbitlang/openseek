// Headless behavior-test harness — the MoonBit analog of vscode's
// editor/test/browser/testCodeEditor.ts. Drives a real CodeEditorWidget + ViewModel +
// CursorsController over an in-memory model WITHOUT attaching a DOM view
// (mirrors TestCodeEditor._createView returning null), so tests assert on
// semantic state — positions, ranges, projected view lines, frames — instead
// of rendered pixels.
//
// The seam is `CodeEditorWidget::attach_model` (attach_model.mbt): it builds the
// tokenized document, view model, and cursor context and stores
// them synchronously before `schedule_render`. Only the DOM flush is deferred,
// and `schedule_render`/`flush_render` already no-op while the model has no
// browser bundle. So an unattached viewer has fully-populated semantic state
// after `set_model` — no DOM, no requestAnimationFrame, no measurement needed.

///|
/// Builds a TextModel from raw text. The analog of `instantiateTextModel`.
fn test_model(
  text : String,
  language_id~ : String = "plaintext",
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/test-model",
    ),
    "test-model",
    language_id,
    1,
    "",
    text,
  )
}

///|
/// `withTestCodeEditor`: spin up a headless viewer over `text`, run `body`,
/// dispose. No `attach()` — no DOM view — but `set_model` still builds the
/// tokenized doc, view model, render frame, and cursor context synchronously.
///
/// The font is pinned (the macOS defaults) rather than platform-derived:
/// `editor_font_defaults`/`golden_line_height_ratio` differ per host OS
/// (12px/1.5 on macOS, 14px/1.35 elsewhere → line height 18 vs 19), and the
/// layout tests assert absolute pixel offsets. Monaco's testCodeEditor
/// likewise runs over a fixed `TestConfiguration`, not the host font.
fn with_test_viewer(
  text : String,
  body : (CodeEditorWidget) -> Unit raise,
  options~ : CodeEditorOptions = CodeEditorOptions(font_size=12, line_height=18),
) -> Unit raise {
  let viewer = CodeEditorWidget::CodeEditorWidget(options~) // NOTE: deliberately no attach()
  viewer.set_model(Some(test_model(text)))
  body(viewer)
  viewer.dispose()
}

///|
/// Opaque caller-owned node for headless APIs whose data shape includes an
/// element but whose tested behavior never reads or mounts that element. This
/// deliberately installs no `document`, DOM methods, timers, or animation
/// frames; any accidental UI access fails instead of being simulated.
extern "js" fn headless_test_element() -> @rdom.Element = "() => ({})"

///|
/// `ITestCodeEditor.getViewModel()` — whitebox read of the private field.
fn CodeEditorWidget::test_view_model(
  self : CodeEditorWidget,
) -> @view_model.ViewModel {
  self.get_view_model().unwrap()
}

///|
/// `ITestCodeEditor`'s cursor read — the view model's always-present
/// controller (`viewModelImpl.ts:124`).
fn CodeEditorWidget::test_cursor(
  self : CodeEditorWidget,
) -> @cursor.CursorsController {
  self.test_view_model().cursor
}

///|
/// The clamped view-line window the viewer would render for the layout's
/// current visible window — the headless analog of `synced_window`, which
/// only runs inside a DOM flush.
fn CodeEditorWidget::test_window(
  self : CodeEditorWidget,
) -> @view_layout.LineWindow {
  let view_model = self.test_view_model()
  view_model.clamp_window(view_model.view_layout.visible_window())
}

///|
/// Forces a soft-wrap column and reflows the view model, the headless analog
/// of the wrap width an attached viewer derives from its measured content box.
/// `CodeEditorOptions` carries no wrap-column field (the real column is measured
/// from the DOM via `soft_wrap_column_for_content_width`), so a headless wrap
/// test sets the private column directly. Requires `options.soft_wrap`.
fn CodeEditorWidget::test_set_soft_wrap_column(
  self : CodeEditorWidget,
  column : Int32,
) -> Unit {
  self.configuration.commit_soft_wrap_column(column) |> ignore
  self.on_configuration_changed()
}

///|
/// Sets the viewport box the layout windows against, the headless analog of the
/// measured content box, so frame-windowing can be tested without a DOM.
fn CodeEditorWidget::test_set_viewport(
  self : CodeEditorWidget,
  width~ : Double,
  height~ : Double,
) -> Unit {
  self.configuration.commit_measured_size(width, height)
  let configuration = self.configuration.snapshot()
  match self.get_view_model() {
    Some(view_model) =>
      view_model.view_layout.set_viewport_size(
        width=configuration.content_width,
        height=configuration.height,
      )
      |> ignore
    None => ()
  }
}

///|
/// A document of `line_count` distinct one-line entries, for windowing tests.
fn long_document(line_count : Int32) -> String {
  let out = StringBuilder()
  for i in 0..<line_count {
    if i > 0 {
      out.write_char('\n')
    }
    out <+ "line \{i}"
  }
  out.to_string()
}

///|
/// Component-wise position equality. `@base_common.Position` derives `Eq`/`Debug`
/// but not `Show`, so `assert_eq` on it cannot format a failure message; the
/// rest of this package's tests compare `line_number`/`column` (both `Int`,
/// which has `Show`) the same way.
fn assert_position(
  actual : @base_common.Position,
  expected : @base_common.Position,
) -> Unit raise {
  assert_eq(actual.line_number, expected.line_number)
  assert_eq(actual.column, expected.column)
}

///|
/// Selection equality by endpoints (anchor + active), for the same `Show` reason
/// as `assert_position`.
fn assert_selection_eq(
  actual : @core.Selection,
  expected : @core.Selection,
) -> Unit raise {
  assert_position(actual.get_selection_start(), expected.get_selection_start())
  assert_position(actual.get_position(), expected.get_position())
}

///|
/// `assertCursor`: compare the controller's model selection to an expected one.
fn assert_cursor(
  viewer : CodeEditorWidget,
  expected : @core.Selection,
) -> Unit raise {
  assert_selection_eq(viewer.test_cursor().get_model_selection(), expected)
}

///|
