///| Faithful conformance port of
/// `vscode/src/vs/editor/test/common/model/model.test.ts` in the checked-in
/// vscode source.
///
/// Readonly-subset triage of the file's 32 cases. In scope: 7 readonly reads
/// plus `setValue eventing` (in scope since the flush lane landed, plan
/// `monaco-set-value-api-port.md`). All 7 reads are ported here (`Get word at
/// position` runs against `TextModel`; the other 6 run against `TextSnapshot`);
/// `setValue eventing` runs against `TextModel`:
///   - `Editor Model - Model`: `model getValue`, `getValueInRange`,
///     `getValueLengthInRange`, `setValue eventing`
///   - `Editor Model - Model Line Separators`: `model getValue`, `model lines`,
///     `Bug 13333: Model should line break on lonely CR too`
///
/// SKIPPED (out of scope, not silently dropped):
///   - 22 `Editor Model - Model` editing/eventing cases — `model insert*`
///     (empty / without newline 1-2 / one / two / many newlines), `model
///     delete*` (empty / one line / one line 2 / all from a line / two lines /
///     many lines / everything), every `* eventing` variant of those, and
///     `issue #46342` — all call `model.applyEdits` (model mutation) or assert
///     the per-line `ModelRawContentChangedEvent`s of the tier-2 edit lane.
///   - `Editor Model - Words`:
///     - SKIPPED: getWordAtPosition at embedded language boundaries — needs DI
///       language services and embedded-language token boundaries.
///     - SKIPPED: issue #61296: VS code freezes when editing CSS file with emoji
///       — needs dynamic per-language word patterns.
///

///|
/// The suite's shared 5-line model (`LINE1..LINE5` joined with mixed CRLF/LF, as
/// in `setup()`).
fn this_model() -> TextSnapshot {
  TextSnapshot("My First Line\r\n\t\tMy Second Line\n    Third Line\n\r\n1")
}

///|
fn rng(sl : Int32, sc : Int32, el : Int32, ec : Int32) -> @base_common.Range {
  Range(sl, sc, el, ec)
}

///|
fn word_at(model : TextModel, column : Int32) -> WordAtPosition? {
  model.get_word_at_position(Position(1, column))
}

///|
test "model getValue" {
  assert_eq(
    this_model().get_value(),
    "My First Line\n\t\tMy Second Line\n    Third Line\n\n1",
  )
}

///|
test "getValueInRange" {
  let m = this_model()
  assert_eq(m.get_value_in_range(rng(1, 1, 1, 1)), "")
  assert_eq(m.get_value_in_range(rng(1, 1, 1, 2)), "M")
  assert_eq(m.get_value_in_range(rng(1, 2, 1, 3)), "y")
  assert_eq(m.get_value_in_range(rng(1, 1, 1, 14)), "My First Line")
  assert_eq(m.get_value_in_range(rng(1, 1, 2, 1)), "My First Line\n")
  assert_eq(m.get_value_in_range(rng(1, 1, 2, 2)), "My First Line\n\t")
  assert_eq(m.get_value_in_range(rng(1, 1, 2, 3)), "My First Line\n\t\t")
  assert_eq(
    m.get_value_in_range(rng(1, 1, 2, 17)),
    "My First Line\n\t\tMy Second Line",
  )
  assert_eq(
    m.get_value_in_range(rng(1, 1, 3, 1)),
    "My First Line\n\t\tMy Second Line\n",
  )
  assert_eq(
    m.get_value_in_range(rng(1, 1, 4, 1)),
    "My First Line\n\t\tMy Second Line\n    Third Line\n",
  )
}

///|
test "getValueLengthInRange" {
  let m = this_model()
  assert_eq(m.get_value_length_in_range(rng(1, 1, 1, 1)), "".length())
  assert_eq(m.get_value_length_in_range(rng(1, 1, 1, 2)), "M".length())
  assert_eq(m.get_value_length_in_range(rng(1, 2, 1, 3)), "y".length())
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 1, 14)),
    "My First Line".length(),
  )
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 2, 1)),
    "My First Line\n".length(),
  )
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 2, 2)),
    "My First Line\n\t".length(),
  )
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 2, 3)),
    "My First Line\n\t\t".length(),
  )
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 2, 17)),
    "My First Line\n\t\tMy Second Line".length(),
  )
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 3, 1)),
    "My First Line\n\t\tMy Second Line\n".length(),
  )
  assert_eq(
    m.get_value_length_in_range(rng(1, 1, 4, 1)),
    "My First Line\n\t\tMy Second Line\n    Third Line\n".length(),
  )
}

///|
/// Exact port of `Get word at position` (`model.test.ts:439-455`) using the
/// upstream default word definition.
test "Get word at position" {
  let snapshot = wb_model("This text has some  words. ")
  assert_true(
    word_at(snapshot, 1) ==
    Some({ word: "This", start_column: 1, end_column: 5, }),
  )
  assert_true(
    word_at(snapshot, 2) ==
    Some({ word: "This", start_column: 1, end_column: 5, }),
  )
  assert_true(
    word_at(snapshot, 4) ==
    Some({ word: "This", start_column: 1, end_column: 5, }),
  )
  assert_true(
    word_at(snapshot, 5) ==
    Some({ word: "This", start_column: 1, end_column: 5, }),
  )
  assert_true(
    word_at(snapshot, 6) ==
    Some({ word: "text", start_column: 6, end_column: 10, }),
  )
  assert_true(
    word_at(snapshot, 19) ==
    Some({ word: "some", start_column: 15, end_column: 19, }),
  )
  assert_true(word_at(snapshot, 20) is None)
  assert_true(
    word_at(snapshot, 21) ==
    Some({ word: "words", start_column: 21, end_column: 26, }),
  )
  assert_true(
    word_at(snapshot, 26) ==
    Some({ word: "words", start_column: 21, end_column: 26, }),
  )
  assert_true(word_at(snapshot, 27) is None)
  assert_true(word_at(snapshot, 28) is None)
}

///|
/// `setValue eventing` (`model.test.ts:302-315`): a flush is one
/// `ModelRawFlush` raw change at version 2, not undoing, not redoing. The
/// upstream captures through `withEventCapturing`
/// (`onDidChangeContentOrInjectedText`); the port captures the same
/// internal event through the model's `event_emitter` (whitebox).
test "setValue eventing" {
  let this_model = TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/model-test.txt",
    ),
    "",
    "plaintext",
    1,
    "",
    "My First Line\r\n\t\tMy Second Line\n    Third Line\n\r\n1",
  )
  let raw : Array[ModelRawContentChangedEvent] = []
  let _sub = this_model.event_emitter.event(e => {
    raw.push(e.raw_content_changed_event)
  })
  this_model.set_value("new value")
  assert_eq(raw.length(), 1)
  let e = raw[0]
  assert_eq(e.changes.length(), 1)
  assert_true(e.changes[0] is ModelRawFlush)
  assert_eq(e.version_id, 2)
  assert_eq(e.is_undoing, false)
  assert_eq(e.is_redoing, false)
}

///|
/// `Editor Model - Model Line Separators` suite: `\u{2028}` (LINE SEPARATOR) is
/// not a line break — only `\n`/`\r`/`\r\n` are.
fn this_model_line_separators() -> TextSnapshot {
  TextSnapshot(
    "My First Line\u{2028}\t\tMy Second Line\n    Third Line\u{2028}\r\n1",
  )
}

///|
test "model getValue [Line Separators]" {
  assert_eq(
    this_model_line_separators().get_value(),
    "My First Line\u{2028}\t\tMy Second Line\n    Third Line\u{2028}\n1",
  )
}

///|
test "model lines" {
  assert_eq(this_model_line_separators().line_count(), 3)
}

///|
/// Adaptation: Monaco expects `getValue()` = `"Hello\r\nWorld!\r\nAnother
/// line"` because `createTextBuffer` normalizes to the majority EOL (`\r\n`
/// here); the viewer has no EOL option and always joins with `\n`.
test "Bug 13333: Model should line break on lonely CR too" {
  let m = TextSnapshot("Hello\rWorld!\r\nAnother line")
  assert_eq(m.line_count(), 3)
  assert_eq(
    m.get_value(),
    (
      #|Hello
      #|World!
      #|Another line
    ),
  )
}
