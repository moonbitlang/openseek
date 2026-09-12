///|
priv struct DiffViewModelTimerTask {
  delay_ms : Int
  callback : () -> Unit
  active : Ref[Bool]
}

///|
priv struct DiffViewModelFakeTimer {
  tasks : Array[DiffViewModelTimerTask]
}

///|
fn DiffViewModelFakeTimer::DiffViewModelFakeTimer() -> DiffViewModelFakeTimer {
  { tasks: [], }
}

///|
fn DiffViewModelFakeTimer::schedule_timeout(
  self : DiffViewModelFakeTimer,
  callback : () -> Unit,
  delay_ms : Int,
) -> @base_common.Disposable {
  let active = Ref(true)
  self.tasks.push({ delay_ms, callback, active, })
  @base_common.Disposable::from(() => active.val = false)
}

///|
fn DiffViewModelFakeTimer::active_delays(
  self : DiffViewModelFakeTimer,
) -> Array[Int] {
  self.tasks.filter_map(task => {
    if task.active.val {
      Some(task.delay_ms)
    } else {
      None
    }
  })
}

///|
fn DiffViewModelFakeTimer::fire_next(
  self : DiffViewModelFakeTimer,
  delay_ms : Int,
) -> Unit raise {
  for task in self.tasks {
    if task.active.val && task.delay_ms == delay_ms {
      task.active.val = false
      (task.callback)()
      return
    }
  }
  fail("no active diff ViewModel timer with delay \{delay_ms}ms")
}

///|
priv enum FakeDocumentDiffResult {
  Empty
  OneChange
  InvalidLineMapping
  InvalidInnerMapping
  InnerOutsideParent
  OverlappingInnerMappings
  Failure
}

///|
priv suberror FakeDocumentDiffProviderError {
  ComputeFailed
}

///|
priv struct FakeDocumentDiffProvider {
  result : Ref[FakeDocumentDiffResult]
  calls : Ref[Int]
  observed_ignore_trim_whitespace : Array[Bool]
  observed_original_values : Array[String]
  observed_modified_values : Array[String]
  before_compute : Ref[(() -> Unit)?]
  did_change : @base_common.Emitter[Unit]
}

///|
fn FakeDocumentDiffProvider::FakeDocumentDiffProvider(
  result? : FakeDocumentDiffResult = Empty,
) -> FakeDocumentDiffProvider {
  {
    result: Ref(result),
    calls: Ref(0),
    observed_ignore_trim_whitespace: [],
    observed_original_values: [],
    observed_modified_values: [],
    before_compute: Ref(None),
    did_change: Emitter(),
  }
}

///|
fn FakeDocumentDiffProvider::signal_change(
  self : FakeDocumentDiffProvider,
) -> Unit {
  self.did_change.fire(())
}

///|
impl @diff.DocumentDiffProvider for FakeDocumentDiffProvider with fn compute_diff(
  self,
  original,
  modified,
  options,
) {
  self.calls.val += 1
  self.observed_ignore_trim_whitespace.push(options.ignore_trim_whitespace)
  self.observed_original_values.push(original.get_value())
  self.observed_modified_values.push(modified.get_value())
  match self.before_compute.val {
    Some(callback) => {
      self.before_compute.val = None
      callback()
    }
    None => ()
  }
  match self.result.val {
    Empty => { changes: [], }
    OneChange => {
      let original_range = @base_common.LineRange(1, 2)
      let modified_range = @base_common.LineRange(1, 2)
      {
        changes: [
          DocumentDiffChange(
            DetailedLineRangeMapping(original_range, modified_range, None),
          ),
        ],
      }
    }
    InvalidLineMapping =>
      {
        changes: [
          DocumentDiffChange(
            DetailedLineRangeMapping(LineRange(0, 2), LineRange(1, 2), None),
          ),
        ],
      }
    InvalidInnerMapping =>
      {
        changes: [
          DocumentDiffChange(
            DetailedLineRangeMapping(
              LineRange(1, 2),
              LineRange(1, 2),
              Some([RangeMapping(Range(1, 1, 1, 99), Range(1, 1, 1, 2))]),
            ),
          ),
        ],
      }
    InnerOutsideParent =>
      {
        changes: [
          DocumentDiffChange(
            DetailedLineRangeMapping(
              LineRange(1, 2),
              LineRange(1, 2),
              Some([RangeMapping(Range(2, 1, 2, 2), Range(1, 1, 1, 2))]),
            ),
          ),
        ],
      }
    OverlappingInnerMappings =>
      {
        changes: [
          DocumentDiffChange(
            DetailedLineRangeMapping(
              LineRange(1, 2),
              LineRange(1, 2),
              Some([
                RangeMapping(Range(1, 1, 1, 3), Range(1, 1, 1, 3)),
                RangeMapping(Range(1, 2, 1, 3), Range(1, 2, 1, 3)),
              ]),
            ),
          ),
        ],
      }
    Failure => raise FakeDocumentDiffProviderError::ComputeFailed
  }
}

///|
impl @diff.DocumentDiffProvider for FakeDocumentDiffProvider with fn on_did_change(
  self,
  listener,
) {
  self.did_change.event(_ => listener())
}

///|
fn diff_view_model_test_model(name : String, text : String) -> @model.TextModel {
  TextModel(
    @base_common.Uri::file("/diff-view-model-\{name}.mbt"),
    name,
    "moonbit",
    1,
    "rev-1",
    text,
  )
}

///|
fn new_diff_view_model_for_test(
  provider : &@diff.DocumentDiffProvider,
  timer : DiffViewModelFakeTimer,
) -> DiffEditorViewModel {
  DiffEditorViewModel(provider, schedule_timeout=(callback, delay_ms) => {
    timer.schedule_timeout(callback, delay_ms)
  })
}

///|
test "DiffEditorViewModel uses immediate and content debounce scheduler lanes" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("scheduler-original", "before")
  let modified = diff_view_model_test_model("scheduler-modified", "after")
  let updates = Ref(0)
  let update_subscription = view_model.on_did_update_diff(() => updates.val += 1)

  view_model.set_model(Some({ original, modified, })) |> ignore
  assert_true(view_model.get_state() == Pending)
  assert_true(timer.active_delays() == [0])
  assert_eq(provider.calls.val, 0)
  assert_eq(updates.val, 1)

  timer.fire_next(0)
  assert_true(view_model.get_state() == Ready)
  assert_true(view_model.is_diff_up_to_date())
  assert_eq(provider.calls.val, 1)
  assert_eq(view_model.get_diff().unwrap().changes.length(), 1)
  assert_eq(updates.val, 2)

  modified.set_value("after one")
  assert_true(view_model.get_state() == Pending)
  assert_true(view_model.get_diff() is None)
  assert_true(timer.active_delays() == [200])
  modified.set_value("after two")
  assert_true(timer.active_delays() == [200])
  assert_eq(provider.calls.val, 1)

  timer.fire_next(200)
  assert_true(view_model.get_state() == Ready)
  assert_eq(provider.calls.val, 2)
  assert_eq(provider.observed_modified_values[1], "after two")
  assert_true(timer.active_delays().is_empty())

  update_subscription.dispose()
  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "DiffEditorViewModel treats the same model pair as a complete no-op" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider()
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("same-original", "a")
  let modified = diff_view_model_test_model("same-modified", "b")
  let updates = Ref(0)
  let update_subscription = view_model.on_did_update_diff(() => updates.val += 1)

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)
  let generation = view_model.generation
  let task_count = timer.tasks.length()
  let returned = view_model.set_model(Some({ original, modified, }))

  assert_true(returned is None)
  assert_eq(view_model.generation, generation)
  assert_eq(timer.tasks.length(), task_count)
  assert_eq(provider.calls.val, 1)
  assert_eq(updates.val, 2)
  assert_true(view_model.get_state() == Ready)

  update_subscription.dispose()
  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "DiffEditorViewModel replaces provider subscription and recomputes immediately" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let first = FakeDocumentDiffProvider::FakeDocumentDiffProvider()
  let second = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let first_object : &@diff.DocumentDiffProvider = first
  let second_object : &@diff.DocumentDiffProvider = second
  let view_model = new_diff_view_model_for_test(first_object, timer)
  let original = diff_view_model_test_model("provider-original", "a")
  let modified = diff_view_model_test_model("provider-modified", "b")

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)
  assert_eq(first.calls.val, 1)
  assert_true(first.did_change.has_listeners())

  view_model.set_provider(second_object)
  assert_false(first.did_change.has_listeners())
  assert_true(second.did_change.has_listeners())
  assert_true(view_model.get_state() == Pending)
  assert_true(timer.active_delays() == [0])
  first.signal_change()
  assert_true(timer.active_delays() == [0])

  timer.fire_next(0)
  assert_eq(first.calls.val, 1)
  assert_eq(second.calls.val, 1)
  assert_eq(view_model.get_diff().unwrap().changes.length(), 1)

  second.result.val = Empty
  second.signal_change()
  assert_true(view_model.get_state() == Pending)
  assert_true(timer.active_delays() == [0])
  timer.fire_next(0)
  assert_eq(second.calls.val, 2)
  assert_true(view_model.get_diff().unwrap().changes.is_empty())

  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "DiffEditorViewModel converts provider errors and invalid mappings to Failed" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=Failure,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("failure-original", "abc\nsecond")
  let modified = diff_view_model_test_model("failure-modified", "xyz\nsecond")

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)
  assert_true(view_model.get_state() == Failed)
  assert_false(view_model.is_diff_up_to_date())
  assert_true(view_model.get_diff() is None)
  assert_eq(view_model.get_failure_diagnostic(), Some("provider error"))

  provider.result.val = InvalidLineMapping
  provider.signal_change()
  timer.fire_next(0)
  assert_true(view_model.get_state() == Failed)
  assert_true(view_model.get_diff() is None)
  assert_eq(view_model.get_failure_diagnostic(), Some("validator rejection"))

  provider.result.val = InvalidInnerMapping
  provider.signal_change()
  timer.fire_next(0)
  assert_true(view_model.get_state() == Failed)
  assert_true(view_model.get_diff() is None)

  provider.result.val = InnerOutsideParent
  provider.signal_change()
  timer.fire_next(0)
  assert_true(view_model.get_state() == Failed)
  assert_true(view_model.get_diff() is None)

  provider.result.val = OverlappingInnerMappings
  provider.signal_change()
  timer.fire_next(0)
  assert_true(view_model.get_state() == Failed)
  assert_true(view_model.get_diff() is None)

  provider.result.val = OneChange
  provider.signal_change()
  timer.fire_next(0)
  assert_true(view_model.get_state() == Ready)
  assert_eq(view_model.get_diff().unwrap().changes.length(), 1)
  assert_true(view_model.get_failure_diagnostic() is None)

  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "validator accepts Line inner anchors on empty hunk sides" {
  let provider = @diff.get_line_document_diff_provider()
  let original = @model.TextSnapshot(
    [
      "fn navigation_anchors() {", "  let stable_head = 0", "  let deleted_only = 1",
      "  let stable_middle_one = 2", "  let stable_middle_two = 3", "  let stable_tail = 5",
      "}",
    ].join("\n"),
  )
  let modified = @model.TextSnapshot(
    [
      "fn navigation_anchors() {", "  let stable_head = 0", "  let stable_middle_one = 2",
      "  let stable_middle_two = 3", "  let inserted_only = 4", "  let stable_tail = 5",
      "}",
    ].join("\n"),
  )
  let result = provider.compute_diff(original, modified, {
    ignore_trim_whitespace: true,
  })
  assert_eq(result.changes.length(), 2)
  assert_true(result.changes[0].mapping.modified.is_empty())
  assert_true(result.changes[1].mapping.original.is_empty())
  assert_true(
    @diff.normalize_and_validate_document_diff(result, original, modified)
    is Some(_),
  )

  let fragmented_original = StringBuilder()
  let fragmented_modified = StringBuilder()
  for fragment in 0..<20 {
    for line in 0..<130 {
      fragmented_original.write_string(
        "let fragment_\{fragment}_deleted_\{line} = \{line}\n",
      )
    }
    let retained = "let fragment_\{fragment}_retained = \{fragment}\n"
    fragmented_original.write_string(retained)
    fragmented_modified.write_string(retained)
  }
  let fragmented_original = @model.TextSnapshot(fragmented_original.to_string())
  let fragmented_modified = @model.TextSnapshot(fragmented_modified.to_string())
  let fragmented = provider.compute_diff(
    fragmented_original,
    fragmented_modified,
    { ignore_trim_whitespace: true, },
  )
  assert_eq(fragmented.changes.length(), 20)
  assert_true(
    @diff.normalize_and_validate_document_diff(
      fragmented, fragmented_original, fragmented_modified,
    )
    is Some(_),
  )
}

///|
test "ViewModel accepts pinned newline mapping for a pure deletion" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = @diff.get_line_document_diff_provider()
  let view_model = new_diff_view_model_for_test(provider, timer)
  let original = diff_view_model_test_model(
    "newline-deletion-original", "deleted\n\nkeep",
  )
  let modified = diff_view_model_test_model(
    "newline-deletion-modified", "\nkeep",
  )

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)

  assert_true(view_model.get_state() == Ready)
  assert_true(view_model.get_failure_diagnostic() is None)
  guard view_model.get_diff() is Some({ changes: [{ mapping: change, .. }], }) &&
    change.inner_changes is Some([inner]) else {
    fail("expected one normalized pure-deletion mapping")
  }
  assert_eq(change.original, LineRange(1, 2))
  assert_eq(change.modified, LineRange(1, 1))
  assert_eq(inner.original, Range(1, 1, 2, 1))
  assert_eq(inner.modified, Range(1, 1, 1, 1))

  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "ViewModel accepts pinned newline mapping for a pure insertion" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = @diff.get_line_document_diff_provider()
  let view_model = new_diff_view_model_for_test(provider, timer)
  let original = diff_view_model_test_model(
    "newline-insertion-original", "\nkeep",
  )
  let modified = diff_view_model_test_model(
    "newline-insertion-modified", "inserted\n\nkeep",
  )

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)

  assert_true(view_model.get_state() == Ready)
  assert_true(view_model.get_failure_diagnostic() is None)
  guard view_model.get_diff() is Some({ changes: [{ mapping: change, .. }], }) &&
    change.inner_changes is Some([inner]) else {
    fail("expected one normalized pure-insertion mapping")
  }
  assert_eq(change.original, LineRange(1, 1))
  assert_eq(change.modified, LineRange(1, 2))
  assert_eq(inner.original, Range(1, 1, 1, 1))
  assert_eq(inner.modified, Range(1, 1, 2, 1))

  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "validator rejects newline anchor over non-empty empty-hunk line" {
  let original = @model.TextSnapshot("deleted\nnot empty\nkeep")
  let modified = @model.TextSnapshot("not empty\nkeep")
  let invalid : @diff.DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(1, 2),
          LineRange(1, 1),
          Some([RangeMapping(Range(1, 1, 2, 1), Range(1, 1, 2, 1))]),
        ),
      ),
    ],
  }

  assert_true(
    @diff.normalize_and_validate_document_diff(invalid, original, modified)
    is None,
  )
}

///|
test "ViewModel normalizes full-line inner mappings like VS Code" {
  let original = @model.TextSnapshot("old\nkeep")
  let modified = @model.TextSnapshot("new\nkeep")
  let result : @diff.DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(1, 2),
          LineRange(1, 2),
          Some([RangeMapping(Range(1, 1, 1, 4), Range(1, 1, 1, 4))]),
        ),
      ),
    ],
  }
  guard @diff.normalize_and_validate_document_diff(result, original, modified)
    is Some(normalized) else {
    fail("expected a valid normalized document diff")
  }
  guard normalized.changes[0].mapping.inner_changes is Some([inner]) else {
    fail("expected normalized inner mapping")
  }
  assert_eq(inner.original, Range(1, 1, 2, 1))
  assert_eq(inner.modified, Range(1, 1, 2, 1))
  assert_eq(
    @diff.normalize_and_validate_document_diff(normalized, original, modified),
    Some(normalized),
  )
}

///|
test "normalization extends an empty-line anchor only with its full-line peer" {
  let original = @model.TextSnapshot("deleted\n\nkeep")
  let modified = @model.TextSnapshot("\nkeep")
  let raw : @diff.DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(1, 2),
          LineRange(1, 1),
          Some([RangeMapping(Range(1, 1, 1, 8), Range(1, 1, 1, 1))]),
        ),
      ),
    ],
  }
  guard @diff.normalize_and_validate_document_diff(raw, original, modified)
    is Some(normalized) else {
    fail("expected a valid normalized deletion mapping")
  }
  guard normalized.changes[0].mapping.inner_changes is Some([inner]) else {
    fail("expected normalized deletion mapping")
  }
  assert_eq(inner.original, Range(1, 1, 2, 1))
  assert_eq(inner.modified, Range(1, 1, 2, 1))
  assert_eq(
    @diff.normalize_and_validate_document_diff(normalized, original, modified),
    Some(normalized),
  )
}

///|
test "ViewModel rejects touching provider rows that were not grouped" {
  let original = @model.TextSnapshot("old one\nold two\nkeep")
  let modified = @model.TextSnapshot("new one\nnew two\nkeep")
  let fragmented : @diff.DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 2), LineRange(1, 2), None),
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(2, 3), LineRange(2, 3), None),
      ),
    ],
  }
  assert_true(
    @diff.normalize_and_validate_document_diff(fragmented, original, modified)
    is None,
  )
  let grouped : @diff.DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 3), LineRange(1, 3), None),
      ),
    ],
  }
  assert_true(
    @diff.normalize_and_validate_document_diff(grouped, original, modified)
    is Some(_),
  )
}

///|
test "normalization leaves invalid provider coordinates for validation" {
  let original = @model.TextSnapshot("old\nkeep")
  let modified = @model.TextSnapshot("new\nkeep")
  let invalid : @diff.DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(1, 2),
          LineRange(1, 2),
          Some([RangeMapping(Range(1, 1, 99, 1), Range(1, 1, 99, 1))]),
        ),
      ),
    ],
  }
  assert_true(
    @diff.normalize_and_validate_document_diff(invalid, original, modified)
    is None,
  )
}

///|
test "DiffEditorViewModel rejects a result made stale by reentrant provider change" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("reentrant-original", "a")
  let modified = diff_view_model_test_model("reentrant-modified", "b")
  provider.before_compute.val = Some(() => provider.signal_change())

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)
  assert_eq(provider.calls.val, 1)
  assert_true(view_model.get_state() == Pending)
  assert_true(view_model.get_diff() is None)
  assert_true(timer.active_delays() == [0])

  timer.fire_next(0)
  assert_eq(provider.calls.val, 2)
  assert_true(view_model.get_state() == Ready)
  assert_eq(view_model.get_diff().unwrap().changes.length(), 1)

  view_model.dispose()
  original.dispose()
  modified.dispose()
}

///|
test "DiffEditorViewModel dispose cancels tasks subscriptions and stale callbacks" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("dispose-original", "a")
  let modified = diff_view_model_test_model("dispose-modified", "b")

  view_model.set_model(Some({ original, modified, })) |> ignore
  assert_true(timer.active_delays() == [0])
  let stale_callback = timer.tasks[0].callback
  assert_true(provider.did_change.has_listeners())
  view_model.dispose()

  assert_true(timer.active_delays().is_empty())
  assert_false(provider.did_change.has_listeners())
  assert_true(view_model.get_state() == NoModel)
  assert_true(view_model.get_model() is None)
  assert_true(view_model.get_diff() is None)
  stale_callback()
  modified.set_value("changed after dispose")
  provider.signal_change()
  assert_eq(provider.calls.val, 0)
  assert_true(timer.active_delays().is_empty())
  assert_false(original.is_disposed())
  assert_false(modified.is_disposed())

  original.dispose()
  modified.dispose()
}

///|
test "DiffEditorViewModel returns a fully detached old pair for immediate disposal" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let first_original = diff_view_model_test_model("old-original", "old left")
  let first_modified = diff_view_model_test_model("old-modified", "old right")
  let next_original = diff_view_model_test_model("new-original", "new left")
  let next_modified = diff_view_model_test_model("new-modified", "new right")

  view_model.set_model(
    Some({ original: first_original, modified: first_modified, }),
  )
  |> ignore
  timer.fire_next(0)
  let returned = view_model.set_model(
    Some({ original: next_original, modified: next_modified, }),
  )
  guard returned is Some(returned) else {
    fail("replacing a model pair must return the detached old pair")
  }
  assert_true(returned.original.same(first_original))
  assert_true(returned.modified.same(first_modified))

  returned.original.dispose()
  returned.modified.dispose()
  assert_true(first_original.is_disposed())
  assert_true(first_modified.is_disposed())
  timer.fire_next(0)

  assert_true(view_model.get_state() == Ready)
  assert_eq(provider.observed_original_values[1], "new left")
  assert_eq(provider.observed_modified_values[1], "new right")
  guard view_model.get_model() is Some(current) else {
    fail("new model pair must remain installed")
  }
  assert_true(current.original.same(next_original))
  assert_true(current.modified.same(next_modified))

  view_model.dispose()
  next_original.dispose()
  next_modified.dispose()
}

///|
test "one model will-dispose atomically clears the pair and both pane slots" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("will-dispose-original", "old left")
  let modified = diff_view_model_test_model(
    "will-dispose-modified", "old right",
  )
  let mut original_slot : @model.TextModel? = None
  let mut modified_slot : @model.TextModel? = None
  let pane_commit = new_diff_editor_model_pair_commit_barrier()
  let mut model_changes = 0
  let mut update_count = 0
  let mut every_update_saw_synchronized_slots = true
  let model_subscription = view_model.on_did_change_model(() => {
    model_changes += 1
    let generation_before = pane_commit.committed_generation
    commit_diff_editor_model_pair_transaction(pane_commit, () => {
      commit_diff_editor_model_pair(
        pane_commit,
        view_model.get_model(),
        model => {
          // Assert in the first synchronous setter callback, not after both
          // slots happen to contain the expected values.
          if !pane_commit.is_committing ||
            pane_commit.committed_generation != generation_before {
            abort("original setter escaped the pair commit barrier")
          }
          original_slot = model
        },
        model => {
          if !pane_commit.is_committing ||
            pane_commit.committed_generation != generation_before {
            abort("modified setter observed an early committed generation")
          }
          modified_slot = model
        },
      )
    })
  })
  let update_subscription = view_model.on_did_update_diff(() => {
    if pane_commit.is_committing {
      abort("outer diff update escaped before both pane setters committed")
    }
    update_count += 1
    let synchronized = match
      (view_model.get_model(), original_slot, modified_slot) {
      (None, None, None) => true
      (Some(current), Some(slot_original), Some(slot_modified)) =>
        current.original.same(slot_original) &&
        current.modified.same(slot_modified)
      _ => false
    }
    if !synchronized {
      every_update_saw_synchronized_slots = false
    }
  })

  view_model.set_model(Some({ original, modified, })) |> ignore
  guard (original_slot, modified_slot)
    is (Some(installed_original), Some(installed_modified)) else {
    fail("both pane slots must receive the installed pair")
  }
  assert_true(installed_original.same(original))
  assert_true(installed_modified.same(modified))
  timer.fire_next(0)
  assert_true(view_model.get_state() == Ready)
  assert_true(view_model.get_diff() is Some(_))
  assert_eq(provider.calls.val, 1)

  modified.set_value("pending right")
  assert_true(timer.active_delays() == [200])
  let stale_content_callback = timer.tasks.last().unwrap().callback
  original.dispose()

  assert_true(view_model.get_model() is None)
  assert_true(view_model.get_state() == NoModel)
  assert_true(view_model.get_diff() is None)
  assert_true(original_slot is None)
  assert_true(modified_slot is None)
  assert_true(timer.active_delays().is_empty())
  assert_eq(model_changes, 2)
  assert_false(pane_commit.is_committing)
  assert_eq(pane_commit.committed_generation, 2)
  assert_eq(update_count, 4)
  assert_true(every_update_saw_synchronized_slots)
  assert_true(original.is_disposed())
  assert_false(modified.is_disposed())

  // The live sibling was detached, not consumed or disposed. Its content and
  // a canceled timer callback cannot resurrect work for the invalidated pair.
  modified.set_value("changed after sibling disposal")
  stale_content_callback()
  assert_eq(provider.calls.val, 1)
  assert_true(timer.active_delays().is_empty())
  assert_true(view_model.get_model() is None)

  model_subscription.dispose()
  update_subscription.dispose()
  view_model.dispose()
  modified.dispose()
}

///|
test "modified model will-dispose invalidates the whole pair too" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let original = diff_view_model_test_model("live-original", "left")
  let modified = diff_view_model_test_model("disposed-modified", "right")

  view_model.set_model(Some({ original, modified, })) |> ignore
  timer.fire_next(0)
  modified.dispose()

  assert_true(view_model.get_model() is None)
  assert_true(view_model.get_state() == NoModel)
  assert_true(view_model.get_diff() is None)
  assert_true(timer.active_delays().is_empty())
  assert_false(original.is_disposed())
  assert_true(modified.is_disposed())

  view_model.dispose()
  original.dispose()
}

///|
test "replacement owns the only detached-pair return and old disposal is inert" {
  let timer = DiffViewModelFakeTimer::DiffViewModelFakeTimer()
  let provider = FakeDocumentDiffProvider::FakeDocumentDiffProvider(
    result=OneChange,
  )
  let provider_object : &@diff.DocumentDiffProvider = provider
  let view_model = new_diff_view_model_for_test(provider_object, timer)
  let first_original = diff_view_model_test_model("replace-count-original", "a")
  let first_modified = diff_view_model_test_model("replace-count-modified", "b")
  let next_original = diff_view_model_test_model("replace-next-original", "c")
  let next_modified = diff_view_model_test_model("replace-next-modified", "d")
  let mut first_original_disposes = 0
  let mut first_modified_disposes = 0
  let original_dispose_subscription = first_original.on_will_dispose(() => {
    first_original_disposes += 1
  })
  let modified_dispose_subscription = first_modified.on_will_dispose(() => {
    first_modified_disposes += 1
  })

  view_model.set_model(
    Some({ original: first_original, modified: first_modified, }),
  )
  |> ignore
  let stale_first_compute = timer.tasks.last().unwrap().callback
  let returned = view_model.set_model(
    Some({ original: next_original, modified: next_modified, }),
  )
  guard returned is Some(returned) else {
    fail("replacement must return exactly the fully detached old pair")
  }
  let replacement_task_count = timer.tasks.length()
  returned.original.set_value("detached a")
  returned.modified.set_value("detached b")
  assert_eq(timer.tasks.length(), replacement_task_count)
  assert_true(timer.active_delays() == [0])
  returned.original.dispose()
  returned.modified.dispose()
  assert_eq(first_original_disposes, 1)
  assert_eq(first_modified_disposes, 1)

  // Disposal of a pair whose subscriptions were retired cannot clear the new
  // pair, and even an explicitly invoked stale callback cannot compute it.
  stale_first_compute()
  assert_eq(provider.calls.val, 0)
  guard view_model.get_model() is Some(current) else {
    fail("the replacement pair must remain installed")
  }
  assert_true(current.original.same(next_original))
  assert_true(current.modified.same(next_modified))
  assert_true(timer.active_delays() == [0])
  timer.fire_next(0)
  assert_eq(provider.calls.val, 1)

  original_dispose_subscription.dispose()
  modified_dispose_subscription.dispose()
  view_model.dispose()
  assert_false(next_original.is_disposed())
  assert_false(next_modified.is_disposed())
  next_original.dispose()
  next_modified.dispose()
}
