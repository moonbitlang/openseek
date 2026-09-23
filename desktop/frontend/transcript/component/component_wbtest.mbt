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
  }
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
}
