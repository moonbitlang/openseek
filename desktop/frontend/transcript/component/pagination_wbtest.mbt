///|
fn paged_input(turns : Int, without_sequence? : Bool = false) -> Input {
  let items : Array[@transcript.TranscriptItem] = []
  for turn in 0..<turns {
    items.push({
      kind: User(content=Content([Text("question \{turn}")])),
      ts: None,
      sequence: if without_sequence {
        None
      } else {
        Some(turn * 2 + 1)
      },
    })
    items.push({
      kind: Assistant(
        reasoning=None,
        prose=Some("answer \{turn}"),
        calls=[],
        replay=false,
        finished=false,
      ),
      ts: None,
      sequence: if without_sequence {
        None
      } else {
        Some(turn * 2 + 2)
      },
    })
  }
  { ..base_input(), items: VisibleRow::history(items), }
}

///|
test "pages cover whole turns, including answers, with stable local anchors" {
  let input = paged_input(53, without_sequence=true)
  let bounds = TurnIndex::new(input.items).page_rows(Some(1))
  assert_eq((bounds.start, bounds.end), (40, 80))
  assert_eq(
    stream_blocks(input, bounds=TurnIndex::new(input.items).page_rows(Some(1))).length(),
    40,
  )
  assert_true(
    stream_blocks(input, bounds=TurnIndex::new(input.items).page_rows(Some(1))).to_array()[0].content
    is Item(anchor=Some("turn-i40"), ..),
  )
  assert_true(
    stream_blocks(input, bounds=TurnIndex::new(input.items).page_rows(Some(1))).to_array()[1].content
    is Item(step_label=Some("#21"), ..),
  )
  assert_eq(
    TurnIndex::new(input.items).page_for_turn(@transcript_overview.Local(80)),
    Some(2),
  )
  assert_eq(
    TurnIndex::new(input.items).page_for_turn(@transcript_overview.Local(1)),
    None,
  )
  let latest = TurnIndex::new(input.items).page_rows(None)
  assert_eq((latest.start, latest.end), (80, 106))
}

///|
test "empty and exact-boundary histories have no extra page" {
  assert_eq(TurnIndex::new(base_input().items).page_rows(None).page.count, 1)
  let input = paged_input(40)
  assert_eq(TurnIndex::new(input.items).page_rows(None).page.index, 1)
  assert_eq(TurnIndex::new(input.items).page_rows(Some(99)).page.index, 1)
  assert_eq(TurnIndex::new(input.items).page_rows(Some(-1)).page.index, 0)
  assert_eq(TurnIndex::new(paged_input(41).items).page_rows(None).page.index, 2)
}

///|
test "old-page bottom cannot pin or show the live response" {
  let input = { ..paged_input(41), streaming_response: Some("live"), }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (older, _) = pinned_model(input).update(
    input,
    Overview(PreviousPage),
    emit,
  )
  let (older, _) = older.update(
    input,
    MountPage(older.navigation_generation),
    emit,
  )
  let (older, _) = older.update(
    input,
    PageReady(older.navigation_generation),
    emit,
  )
  assert_eq(older.page, Some(1))
  let (bottom, _) = older.update(input, Pinned(true), emit)
  assert_false(bottom.pinned)
  assert_eq(bottom.page, Some(1))
  assert_false(
    stream_blocks(input, bounds=TurnIndex::new(input.items).page_rows(Some(1)))
    .to_array()
    .any(block => block.content is Live(..)),
  )
  assert_true(
    stream_blocks(input).to_array().any(block => block.content is Live(..)),
  )
  let (latest, _) = bottom.update(input, JumpToLatest, emit)
  assert_true(latest.pinned)
  assert_eq(latest.page, None)
}

///|
test "cross-page navigation uses global turn keys in both sources" {
  for source in [OpenSeek, Codex] {
    let input = { ..paged_input(53), source, }
    let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
    let (next, _) = pinned_model(input).update(
      input,
      Overview(Clicked(@transcript_overview.Durable(47))),
      emit,
    )
    assert_eq(next.page, None)
    let (next, _) = next.update(
      input,
      MountPage(next.navigation_generation),
      emit,
    )
    assert_eq(next.page, Some(1))
    assert_false(next.pinned)
    assert_eq(next.overview.active, Some(@transcript_overview.Durable(47)))
  }
}

///|
test "preamble belongs to the first page and a turn is never split" {
  let input = paged_input(21)
  let preamble : VisibleRow = {
    item: { kind: Summary("earlier context"), ts: None, sequence: Some(0), },
    identity: "summary",
  }
  let input = { ..input, items: [preamble, ..input.items], }
  let first = TurnIndex::new(input.items).page_rows(Some(0))
  let second = TurnIndex::new(input.items).page_rows(Some(1))
  assert_eq((first.start, first.end), (0, 41))
  assert_eq((second.start, second.end), (41, 43))
  assert_true(
    stream_blocks(input, bounds=TurnIndex::new(input.items).page_rows(Some(0))).to_array()[0].content
    is Item(item={ kind: Summary(_), .. }, ..),
  )
  // Background output without any user turns remains visible on its only page.
  let only_preamble = { ..input, items: [preamble], }
  assert_eq(stream_blocks(only_preamble).length(), 1)
}
