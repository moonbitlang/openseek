///|
/// The neutral local-OpenSeek input the component tests below start from;
/// each test names only the fields it varies, with struct update.
fn base_input() -> Input {
  Input(
    source=OpenSeek,
    focused=Local,
    active_session="desktop-test",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    items=[],
    streaming_response=None,
    streaming_identity="idle",
  )
}

///|
/// The pinned model matching `base_input()`.
fn pinned_model(input : Input) -> Model {
  {
    pinned: true,
    overview: @transcript_overview.State::empty(),
    image_owner: input.image_owner(),
    images: ImageCache::empty(),
    artifact_owner: input.artifact_owner(),
    artifact_files: ArtifactFileCache::empty(),
  }
}

///|
test "transcript editor drafts stay immutable and cancel releases the row" {
  let input = {
    ..base_input(),
    can_fork: true,
    editable_users: [1],
    items: [
      {
        identity: "s1",
        item: {
          kind: User(content=Content([Text("original")])),
          sequence: Some(1),
          ts: None,
        },
      },
    ],
  }
  let blocks = stream_blocks(input).map(block => (input.locale, block))
  let block = blocks[0].1
  let key = block.branch_key()
  let send : @cmd.Emit[(Int32, @composer.Draft)] = @cmd.Emit(_ => @cmd.none)
  let empty = MessageEditors(Map([]))
  let (opened, _) = empty.update(blocks, key, BeginEdit, send, unpin=@cmd.none)
  let (typed, _) = opened.update(
    blocks,
    key,
    EditText("draft"),
    send,
    unpin=@cmd.none,
  )
  let (again, _) = opened.update(
    blocks,
    key,
    EditText("draft"),
    send,
    unpin=@cmd.none,
  )
  assert_true(typed == again)
  assert_true(empty.for_block(block) is EditorClosed)
  assert_true(opened.for_block(block) is EditorDraft({ task: "original", .. }))
  let (sent, _) = typed.update(blocks, key, SendEdit, send, unpin=@cmd.none)
  assert_true(sent == typed)
  let busy = stream_blocks({ ..input, edit_busy: true, }).map(block => {
    (input.locale, block)
  })
  let (held, _) = typed.update(
    busy,
    key,
    EditText("lost"),
    send,
    unpin=@cmd.none,
  )
  assert_true(held == typed)
  let (cancelled, _) = held.update(busy, key, CancelEdit, send, unpin=@cmd.none)
  assert_true(cancelled.0.is_empty())
  let (removed, _) = typed.update(
    @vector.from_array([]),
    key,
    SendEdit,
    send,
    unpin=@cmd.none,
  )
  assert_true(removed.0.is_empty())
}

///|
test "an overview click unpins and highlights inside the component" {
  let key = @transcript_overview.Durable(3)
  let input = base_input()
  let state = pinned_model(input)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (next, _) = state.update(input, Overview(Clicked(key)), emit)
  assert_false(next.pinned)
  @debug.assert_eq(next.overview.active, Some(key))
}

///|
test "a stale follow scroll does not unpin the reader" {
  // Seeking the tail reports even when the reader was unpinned.
  assert_true(reports_pin(true, false, false))
  // Leaving the tail reports when the reader scrolled up.
  assert_true(reports_pin(false, true, true))
  // A content-animated follow can move down, or not at all, while its scroll
  // event reads a taller scroller; that is not the reader leaving the tail.
  assert_false(reports_pin(false, true, false))
  // An unchanged reading never reports.
  assert_false(reports_pin(true, true, true))
  assert_false(reports_pin(false, false, false))
}

///|
test "local pinned transitions are pure" {
  let input = base_input()
  let state = pinned_model(input)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (first, _) = state.update(input, Pinned(false), emit)
  let (second, _) = state.update(input, Pinned(false), emit)
  assert_false(first.pinned)
  assert_false(second.pinned)
  // Content growth never re-pins by itself: only the reader's scroll or an
  // explicit jump does. Another client's User item must not impersonate a
  // local send.
  let (grown, _) = first.update(input, ContentRendered, emit)
  assert_false(grown.pinned)
  let (received, _) = first.update(
    {
      ..input,
      items: [
        {
          item: {
            kind: User(content=Content([Text("new turn")])),
            ts: None,
            sequence: None,
          },
          identity: "l0",
        },
      ],
    },
    ContentRendered,
    emit,
  )
  assert_false(received.pinned)
  let (jumped, _) = grown.update(input, JumpToLatest, emit)
  assert_true(jumped.pinned)

  let editing_input = {
    ..input,
    can_fork: true,
    editable_users: [1],
    items: [
      {
        identity: "s1",
        item: {
          kind: User(content=Content([Text("original")])),
          sequence: Some(1),
          ts: None,
        },
      },
    ],
  }
  let blocks = stream_blocks(editing_input)
  guard blocks.get(0) is Some(block) else { fail("user block") }
  let send : @cmd.Emit[(Int32, @composer.Draft)] = @cmd.Emit(_ => @cmd.none)
  let closed = MessageEditor::EditorClosed
  let (opened, _) = closed.update(block, BeginEdit, send, unpin=@cmd.none)
  let (repeated, _) = closed.update(block, BeginEdit, send, unpin=@cmd.none)
  assert_true(opened == repeated)
  assert_true(opened is EditorDraft({ task: "original", .. }))
  let (typed, _) = opened.update(
    block,
    EditText("revised"),
    send,
    unpin=@cmd.none,
  )
  let (typed_again, _) = opened.update(
    block,
    EditText("revised"),
    send,
    unpin=@cmd.none,
  )
  assert_true(typed == typed_again)
  assert_true(opened is EditorDraft({ task: "original", .. }))
  let (sent, _) = typed.update(block, SendEdit, send, unpin=@cmd.none)
  assert_true(sent == typed)
  let (cancelled, _) = typed.update(block, CancelEdit, send, unpin=@cmd.none)
  assert_true(cancelled is EditorClosed)
  guard stream_blocks({ ..editing_input, fork_busy: true, }).get(0)
    is Some(busy) else {
    fail("busy block")
  }
  for msg in [BeginEdit, EditText("lost"), CancelEdit, SendEdit] {
    let (held, _) = typed.update(busy, msg, send, unpin=@cmd.none)
    assert_true(held == typed)
  }
}

///|
test "a run starting during inline editing keeps the draft and allows cancellation" {
  let input = base_input()
  let input = {
    ..input,
    can_fork: true,
    editable_users: [1],
    edit_busy: true,
    items: [
      {
        identity: "s1",
        item: {
          kind: User(content=Content([Text("original")])),
          sequence: Some(1),
          ts: None,
        },
      },
    ],
  }
  guard stream_blocks(input).get(0) is Some(block) else { fail("user block") }
  let send : @cmd.Emit[(Int32, @composer.Draft)] = @cmd.Emit(_ => @cmd.none)
  let draft = MessageEditor::EditorDraft({
    task: "draft",
    images: [],
    mentions: [],
  })
  let (held, _) = draft.update(block, SendEdit, send, unpin=@cmd.none)
  assert_true(held == draft)
  let (closed, _) = draft.update(block, CancelEdit, send, unpin=@cmd.none)
  assert_true(closed is EditorClosed)
  let (blocked, _) = closed.update(block, BeginEdit, send, unpin=@cmd.none)
  assert_true(blocked is EditorClosed)
}
