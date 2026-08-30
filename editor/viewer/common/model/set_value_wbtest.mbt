///| White-box tests for the `setValue` flush lane (`text_model.mbt` setValue
/// region + `text_model_events.mbt`) — the plan's Phase-4 matrix rows local
/// to the model: version ids, whole-buffer equality, decoration
/// destruction, the public payload shape, the two-loop dispatch order, the
/// deferred content emitter, and the disposing guard.

///|
test "set_value bumps the version id and swaps the snapshot" {
  let model = wb_model("alpha\nbravo")
  assert_eq(model.get_version_id(), 1)
  model.set_value(
    (
      #|x
      #|y
      #|z
    ),
  )
  assert_eq(model.get_version_id(), 2)
  assert_eq(
    model.get_value(),
    (
      #|x
      #|y
      #|z
    ),
  )
  assert_eq(model.get_line_count(), 3)
  // identical content still flushes (the no-op early return is the host's,
  // per modelService.ts:370-373)
  model.set_value(
    (
      #|x
      #|y
      #|z
    ),
  )
  assert_eq(model.get_version_id(), 3)
}

///|
test "set_value emits one full-range public change with isFlush" {
  let model = wb_model("alpha\nbravo")
  let events : Array[ModelContentChangedEvent] = []
  let _sub = model.on_did_change_content(e => events.push(e))
  model.set_value(
    (
      #|x
      #|y
      #|z
    ),
  )
  assert_eq(events.length(), 1)
  let e = events[0]
  assert_eq(e.is_flush, true)
  assert_eq(e.is_eol_change, false)
  assert_eq(e.is_undoing, false)
  assert_eq(e.is_redoing, false)
  assert_eq(e.version_id, 2)
  assert_eq(e.eol, "\n")
  assert_eq(e.changes.length(), 1)
  let change = e.changes[0]
  // the replaced range is the OLD full model range and length
  assert_true(change.range == Range(1, 1, 2, 6))
  assert_eq(change.range_offset, 0)
  assert_eq(change.range_length, "alpha\nbravo".length())
  // the text is the NEW full value (read after the buffer swap)
  assert_eq(
    change.text,
    (
      #|x
      #|y
      #|z
    ),
  )
}

///|
test "set_value re-seeds visible token state without a full reset event" {
  let registration = @syntax.tokenization_registry.register(
    "moonbit",
    @plain_tokenizer.PlainTokenizer(),
  )
  let model = wb_model("alpha\nbravo")
  let view = model.on_before_attached()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2, }], true)
  let to_lines : Array[Int] = []
  let _sub = model.on_did_change_tokens(e => {
    to_lines.push(e.ranges[0].to_line_number)
  })
  model.set_value(
    (
      #|one
      #|two
      #|three
    ),
  )
  // The shared model state sees the NEW line count before flush handling, while
  // the internal reset suppresses its whole-document event. The retained
  // visible range is refreshed and reports only lines one through two.
  assert_true(to_lines == [2])
  assert_eq(model.tokenization.get_line_tokens(3).get_line_content(), "three")
  model.on_before_detached(view)
  registration.dispose()
}

///|
test "no content event is emitted while disposing" {
  let model = wb_model("alpha")
  let mut content_events = 0
  let _sub = model.on_did_change_content(_ => content_events += 1)
  let _will = model.on_will_dispose(() => model.set_value("ghost"))
  model.dispose()
  // the swap and version bump still happened; only the events are
  // suppressed (`textModel.ts:468-471`)
  assert_eq(content_events, 0)
  assert_eq(model.get_value(), "ghost")
  assert_eq(model.get_version_id(), 2)
}

///|
test "DidChangeContentEmitter merges flushes inside a deferred bracket" {
  let model = wb_model("a")
  let events : Array[ModelContentChangedEvent] = []
  let _sub = model.on_did_change_content(e => events.push(e))
  model.event_emitter.begin_deferred_emit()
  model.set_value("b")
  model.set_value("c\nd")
  assert_eq(events.length(), 0)
  model.event_emitter.end_deferred_emit()
  assert_eq(events.length(), 1)
  let e = events[0]
  // merged: both changes, the LAST version id, isFlush sticky-true
  assert_eq(e.changes.length(), 2)
  assert_eq(e.version_id, 3)
  assert_eq(e.is_flush, true)
  assert_eq(e.changes[1].text, "c\nd")
}

///|
test "two-loop dispatch: every structural update precedes every emit" {
  let log : Array[String] = []
  let model = wb_model("x")
  let registration_a = model.register_view_model(
    _e => log.push("a:structure"),
    _e => log.push("a:emit"),
  )
  let registration_b = model.register_view_model(
    _e => log.push("b:structure"),
    _e => log.push("b:emit"),
  )
  // the public emitter fires only after both loops (`textModel.ts:480-481`)
  let _sub = model.on_did_change_content(_ => log.push("public"))
  model.set_value("y")
  assert_true(
    log == ["a:structure", "b:structure", "a:emit", "b:emit", "public"],
  )
  // the registration handle removes exactly its callbacks and is idempotent
  registration_a.dispose()
  registration_a.dispose()
  log.clear()
  model.set_value("z")
  assert_true(log == ["b:structure", "b:emit", "public"])
  registration_b.dispose()
}

///|
test "raw change union carries the tier-2 shape (contains_event, merge)" {
  let flush_only : ModelRawContentChangedEvent = {
    changes: [ModelRawFlush],
    version_id: 2,
    is_undoing: false,
    is_redoing: false,
  }
  assert_eq(flush_only.contains_event(Flush), true)
  assert_eq(flush_only.contains_event(LinesInserted), false)
  let inserted : ModelRawContentChangedEvent = {
    changes: [
      ModelRawLinesInserted(
        from_line_number=1,
        from_line_number_post_edit=1,
        count=2,
      ),
    ],
    version_id: 3,
    is_undoing: true,
    is_redoing: false,
  }
  let merged = ModelRawContentChangedEvent::merge(flush_only, inserted)
  assert_eq(merged.changes.length(), 2)
  assert_eq(merged.version_id, 3)
  assert_eq(merged.is_undoing, true)
  assert_eq(merged.is_redoing, false)
  assert_eq(merged.contains_event(Flush), true)
  assert_eq(merged.contains_event(LinesInserted), true)
}
