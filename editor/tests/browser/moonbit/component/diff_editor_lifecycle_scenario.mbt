///|
fn diff_editor_lifecycle_model(
  name : String,
  content : String,
) -> @model.TextModel {
  let uri = @base_common.Uri::from(
    scheme="memory",
    authority="diff-lifecycle",
    path="/\{name}.mbt",
  ) catch {
    _ => abort("invalid lifecycle fixture URI")
  }
  TextModel(uri, "\{name}.mbt", "moonbit", 1, "diff-lifecycle-\{name}", content)
}

///|
fn diff_editor_lifecycle_numbered_lines(start : Int, end : Int) -> String {
  let lines : Array[String] = []
  for line in start..<end {
    lines.push("stable line \{line}")
  }
  lines.join("\n")
}

///|
priv suberror DiffLifecycleProviderError {
  ComputeFailed
}

///|
priv struct FailingDiffLifecycleProvider {
  marker : Unit
}

///|
fn FailingDiffLifecycleProvider::FailingDiffLifecycleProvider() -> FailingDiffLifecycleProvider {
  { marker: (), }
}

///|
impl @diff.DocumentDiffProvider for FailingDiffLifecycleProvider with fn compute_diff(
  self,
  _original,
  _modified,
  _options,
) {
  self.marker |> ignore
  raise DiffLifecycleProviderError::ComputeFailed
}

///|
impl @diff.DocumentDiffProvider for FailingDiffLifecycleProvider with fn on_did_change(
  _self,
  _listener,
) {
  @base_common.Disposable::from(() => ())
}

///|
priv struct InvalidDiffLifecycleProvider {
  marker : Unit
}

///|
fn InvalidDiffLifecycleProvider::InvalidDiffLifecycleProvider() -> InvalidDiffLifecycleProvider {
  { marker: (), }
}

///|
impl @diff.DocumentDiffProvider for InvalidDiffLifecycleProvider with fn compute_diff(
  self,
  _original,
  _modified,
  _options,
) {
  self.marker |> ignore
  {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(0, 2), LineRange(1, 2), None),
      ),
    ],
  }
}

///|
impl @diff.DocumentDiffProvider for InvalidDiffLifecycleProvider with fn on_did_change(
  _self,
  _listener,
) {
  @base_common.Disposable::from(() => ())
}

///|
priv struct IgnoredDiffLifecycleProvider {
  marker : Unit
}

///|
impl @diff.DocumentDiffProvider for IgnoredDiffLifecycleProvider with fn compute_diff(
  self,
  _original,
  _modified,
  _options,
) {
  ignore(self.marker)
  {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 2), LineRange(1, 1), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(3, 5), LineRange(2, 2), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(5, 6), LineRange(2, 3), None),
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(6, 6), LineRange(3, 4), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(7, 8), LineRange(5, 6), None),
        kind=Ignored,
      ),
    ],
  }
}

///|
impl @diff.DocumentDiffProvider for IgnoredDiffLifecycleProvider with fn on_did_change(
  _self,
  _listener,
) {
  @base_common.Disposable::from(() => ())
}

///|
pub fn run_diff_editor_lifecycle_test() -> Unit {
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    abort("missing #app mount point")
  }
  let host = document.create_element("div")
  host.set_attribute("class", "diff-lifecycle-host")
  host.set_attribute("style", "width:700px;height:420px;")
  app.append_child(host.as_node())
  let provider = @diff.LineDocumentDiffProvider()
  let provider_object : &@diff.DocumentDiffProvider = provider
  let failing_provider = FailingDiffLifecycleProvider::FailingDiffLifecycleProvider()
  let failing_provider_object : &@diff.DocumentDiffProvider = failing_provider
  let invalid_provider = InvalidDiffLifecycleProvider::InvalidDiffLifecycleProvider()
  let invalid_provider_object : &@diff.DocumentDiffProvider = invalid_provider
  let ignored_provider = IgnoredDiffLifecycleProvider::{ marker: (), }
  let ignored_provider_object : &@diff.DocumentDiffProvider = ignored_provider
  let widget = @diff_editor.DiffEditorWidget::create(
    host,
    provider_object,
    editor_options=@code_widget.CodeEditorOptions::default()
      .with_soft_wrap(true)
      .with_line_numbers_min_chars(1),
    options=DiffEditorOptions(layout=Inline, automatic_inline=false),
  )
  let original = diff_editor_lifecycle_model(
    "original",
    ("deleted line " + "x".repeat(400) + "\n").repeat(260) +
    "shared tail\n".repeat(120) +
    "end",
  )
  let modified = diff_editor_lifecycle_model(
    "modified",
    "shared tail\n".repeat(120) + "end",
  )
  let digit_original = diff_editor_lifecycle_model(
    "digit-original",
    "digit line\n".repeat(8) + "digit line",
  )
  let digit_modified = diff_editor_lifecycle_model(
    "digit-modified",
    "digit line\n".repeat(8) + "digit line",
  )
  let indicator_original = diff_editor_lifecycle_model(
    "indicator-original", "shared head\nold value\nshared tail",
  )
  let indicator_modified = diff_editor_lifecycle_model(
    "indicator-modified", "shared head\nnew value\nshared tail",
  )
  let ignored_original = diff_editor_lifecycle_model(
    "ignored-original", "// removed\nkeep\n// before value one\n// before value two\nold value\nlast\n// tail old\nend",
  )
  let ignored_modified = diff_editor_lifecycle_model(
    "ignored-modified", "keep\nnew value\n// inserted\nlast\n// tail new\nend",
  )
  let late_prefix = diff_editor_lifecycle_numbered_lines(1, 121) + "\n"
  let late_middle = "\n" + diff_editor_lifecycle_numbered_lines(122, 190) + "\n"
  let late_suffix = "\n" + diff_editor_lifecycle_numbered_lines(191, 241)
  let late_original = diff_editor_lifecycle_model(
    "late-original",
    late_prefix +
    "old first hunk" +
    late_middle +
    "old second hunk" +
    late_suffix,
  )
  let late_modified = diff_editor_lifecycle_model(
    "late-modified",
    late_prefix +
    "new first hunk" +
    late_middle +
    "new second hunk" +
    late_suffix,
  )
  let first_line_middle = "\n" +
    diff_editor_lifecycle_numbered_lines(2, 100) +
    "\n"
  let first_line_suffix = "\n" + diff_editor_lifecycle_numbered_lines(101, 141)
  let first_line_original = diff_editor_lifecycle_model(
    "first-line-original",
    "old first hunk at line 1" +
    first_line_middle +
    "old second hunk at line 100" +
    first_line_suffix,
  )
  let first_line_modified = diff_editor_lifecycle_model(
    "first-line-modified",
    "new first hunk at line 1" +
    first_line_middle +
    "new second hunk at line 100" +
    first_line_suffix,
  )
  let horizontal_narrow = diff_editor_lifecycle_model(
    "horizontal-narrow",
    ("n".repeat(100) + "\n").repeat(40),
  )
  let horizontal_wide = diff_editor_lifecycle_model(
    "horizontal-wide",
    ("w".repeat(200) + "\n").repeat(40),
  )
  widget.set_model(Some({ original, modified, })) |> ignore
  install_diff_editor_lifecycle_controls(
    fixture => {
      let pair : @diff_editor.DiffEditorModelData = match fixture {
        "horizontal-original" =>
          { original: horizontal_wide, modified: horizontal_narrow, }
        "horizontal-modified" =>
          { original: horizontal_narrow, modified: horizontal_wide, }
        "horizontal-equal" =>
          { original: horizontal_wide, modified: horizontal_wide, }
        "ignored" => { original: ignored_original, modified: ignored_modified, }
        "digits" => { original: digit_original, modified: digit_modified, }
        "indicators" =>
          { original: indicator_original, modified: indicator_modified, }
        "late" => { original: late_original, modified: late_modified, }
        "first-line" =>
          { original: first_line_original, modified: first_line_modified, }
        _ => { original, modified, }
      }
      if fixture.has_prefix("horizontal-") {
        widget.update_options(
          @code_widget.CodeEditorOptions::default(),
          DiffEditorOptions(
            layout=SideBySide,
            automatic_inline=false,
            diff_word_wrap=Off,
            handle_mouse_wheel=false,
          ),
        )
      }
      widget.set_model(Some(pair)) |> ignore
    },
    line_count => {
      let content = "digit line\n".repeat((line_count - 1).max(0)) +
        "digit line"
      digit_original.set_value(content)
      digit_modified.set_value(content)
    },
    (layout_name, render_indicators, font_size) => {
      let layout : @diff_editor.DiffEditorLayout = if layout_name == "split" {
        SideBySide
      } else {
        Inline
      }
      widget.update_options(
        @code_widget.CodeEditorOptions::default()
        .with_soft_wrap(true)
        .with_line_numbers_min_chars(1)
        .with_font_size(font_size),
        DiffEditorOptions(layout~, automatic_inline=false, render_indicators~),
      )
    },
    provider_kind => {
      match provider_kind {
        "ignored" => widget.set_diff_provider(ignored_provider_object)
        "provider" => widget.set_diff_provider(failing_provider_object)
        "validator" => widget.set_diff_provider(invalid_provider_object)
        _ => widget.set_diff_provider(provider_object)
      }
    },
    attached => {
      widget.set_model(
        if attached {
          Some({ original, modified, })
        } else {
          None
        },
      )
      |> ignore
    },
    () => widget.reveal_first_diff(),
    () => widget.reveal_last_diff(),
    left => widget.set_scroll_left(left),
    () => widget.dispose(),
    () => {
      horizontal_narrow.dispose()
      horizontal_wide.dispose()
      ignored_original.dispose()
      ignored_modified.dispose()
      original.dispose()
      modified.dispose()
      digit_original.dispose()
      digit_modified.dispose()
      indicator_original.dispose()
      indicator_modified.dispose()
      late_original.dispose()
      late_modified.dispose()
      first_line_original.dispose()
      first_line_modified.dispose()
    },
  )
}

///|
extern "js" fn install_diff_editor_lifecycle_controls(
  set_fixture : (String) -> Unit,
  set_digit_line_count : (Int) -> Unit,
  set_options : (String, Bool, Double) -> Unit,
  set_provider : (String) -> Unit,
  set_model_attached : (Bool) -> Unit,
  reveal_first_diff : () -> Unit,
  reveal_last_diff : () -> Unit,
  set_scroll_left : (Double) -> Unit,
  dispose : () -> Unit,
  dispose_models : () -> Unit,
) -> Unit =
  #| (setFixture, setDigitLineCount, setOptions, setProvider, setModelAttached, revealFirstDiff, revealLastDiff, setScrollLeft, dispose, disposeModels) => {
  #|   globalThis.__diffEditorLifecycleControls = Object.freeze({
  #|     set_fixture: setFixture,
  #|     set_digit_line_count: setDigitLineCount,
  #|     set_options: setOptions,
  #|     set_provider: setProvider,
  #|     set_model_attached: setModelAttached,
  #|     reveal_first_diff: revealFirstDiff,
  #|     reveal_last_diff: revealLastDiff,
  #|     set_scroll_left: setScrollLeft,
  #|     dispose,
  #|     dispose_models: disposeModels,
  #|   });
  #| }
