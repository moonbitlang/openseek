///|
test "equal paths from different sources have independent component keys" {
  let live = Id(
    source="openseek.projects",
    channel="local",
    root="/work/openseek",
  )
  let archived = Id(
    source="openseek.archived",
    channel="local",
    root="/work/openseek",
  )
  assert_true(live != archived)
  assert_true(live.key() != archived.key())
}

///|
fn test_input(activation? : String) -> Input {
  {
    id: Id(source="openseek.projects", channel="local", root="/work/openseek"),
    title: "/work/openseek",
    label: "openseek",
    activation,
    can_start: true,
    managed: true,
    conversations: [],
    empty_label: None,
  }
}

///|
fn test_conversations(
  count : Int,
  active_index? : Int,
) -> Array[@conversation.Input] {
  let conversations : Array[@conversation.Input] = []
  for index = 0; index < count; index = index + 1 {
    let id = index.to_string()
    conversations.push({
      id: @conversation.Id(
        source="openseek.projects",
        channel="local",
        conversation=id,
      ),
      title: id,
      label: "Chat \{id}",
      nested: true,
      subrun: false,
      active: active_index == Some(index),
      loading: false,
      load_failed: false,
      running: false,
      openable: true,
      worktree: None,
      run_mark: @conversation.NoRunMark,
      trailing: [],
      rename: None,
      children: [],
    })
  }
  conversations
}

///|
test "the project component state owns its compact preview" {
  let state : State = { fold: Open, preview_limit: PreviewLimit, }
  assert_true(state.conversation_visible(4, false))
  assert_false(state.conversation_visible(5, false))
  assert_true(state.conversation_visible(5, true))
  let input = { ..test_input(), conversations: test_conversations(20), }
  let shown_once = state.update(input, ShowMore)
  assert_eq(shown_once.preview_limit, 12)
  assert_true(shown_once.conversation_visible(11, false))
  assert_false(shown_once.conversation_visible(12, false))
  let shown_twice = shown_once.update(input, ShowMore)
  assert_eq(shown_twice.preview_limit, 19)
  assert_true(shown_twice.conversation_visible(18, false))
  assert_false(shown_twice.conversation_visible(19, false))
}

///|
test "show more skips an active chat that was already visible" {
  let state : State = { fold: Open, preview_limit: PreviewLimit, }
  let input = {
    ..test_input(),
    conversations: test_conversations(20, active_index=7),
  }
  assert_true(state.conversation_visible(7, true))
  let shown_more = state.update(input, ShowMore)
  assert_eq(shown_more.preview_limit, 13)
}

///|
test "folding a project resets its compact preview" {
  let state : State = { fold: Open, preview_limit: PreviewLimit, }
  let input = { ..test_input(), conversations: test_conversations(20), }
  let shown_more = state.update(input, ShowMore)
  assert_true(shown_more.conversation_visible(11, false))
  let folded = shown_more.update(input, ToggleDisclosure)
  assert_true(folded.folded(test_input()))
  let reopened = folded.update(input, ToggleDisclosure)
  assert_false(reopened.folded(test_input()))
  assert_true(reopened.conversation_visible(4, false))
  assert_false(reopened.conversation_visible(5, false))
}

///|
/// The regression behind this state shape: folding the project you are
/// inside must take effect immediately, not silently arm a fold that fires
/// when the activation later moves away.
test "folding the active project folds it immediately and stays put" {
  let open : State = { fold: Open, preview_limit: PreviewLimit, }
  let folded = open.update(test_input(activation="desktop-a"), ToggleDisclosure)
  assert_true(folded.folded(test_input(activation="desktop-a")))
  // Leaving the branch, and returning to the same conversation, both respect
  // the explicit fold.
  assert_true(folded.folded(test_input()))
  assert_true(folded.folded(test_input(activation="desktop-a")))
  // A different activation is a jump into the branch: reveal it.
  assert_false(folded.folded(test_input(activation="desktop-b")))
}

///|
test "a fold made outside the branch is revealed by any activation" {
  let open : State = { fold: Open, preview_limit: PreviewLimit, }
  let folded = open.update(test_input(), ToggleDisclosure)
  assert_true(folded.folded(test_input()))
  assert_false(folded.folded(test_input(activation="desktop-a")))
}

///|
test "toggling a revealed branch folds what the user sees" {
  let open : State = { fold: Open, preview_limit: PreviewLimit, }
  // Folded while inactive, then revealed by an activation…
  let folded = open.update(test_input(), ToggleDisclosure)
  let revealed_input = test_input(activation="desktop-a")
  assert_false(folded.folded(revealed_input))
  // …a click now means "fold", not "flip the stale stored value to open".
  let refolded = folded.update(revealed_input, ToggleDisclosure)
  assert_true(refolded.folded(revealed_input))
}
