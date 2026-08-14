///|
fn Input::fixture(task : String) -> Input {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "composer-test",
  }
  {
    identity: { owner, archive_generation: 0 },
    draft: { task, mentions: [] },
    goal: { draft: None, standing: None, pending: None },
    root: Some(@common.Uri::file("/workspace")),
    installed_skills: [],
    context_generation: 0,
    submission_sequence: 0,
    replacements: [],
    retirements: [],
    file_candidates: [],
    open_files: [],
    active_file: None,
    file_index: FileIndexReady(epoch=0, truncated=false),
    presentation: {
      context: [],
      status: [],
      placeholder: "Prompt",
      primary_action: Send(available=true),
    },
  }
}

///|
fn Msg::test_emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
fn Action::test_emit() -> @cmd.Emit[Action] {
  @cmd.Emit(_ => @cmd.none)
}

///|
test "typing is local, pure, and idempotent" {
  let input = Input::fixture("")
  let initial = Model(input)
  let (once, _) = initial.update(
    input,
    TextChanged("a local draft"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (twice, _) = initial.update(
    input,
    TextChanged("a local draft"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(once == twice)
  inspect(input.draft.task, content="")
  inspect(once.active(input).draft.task, content="a local draft")
}

///|
test "each conversation keeps an independent local draft" {
  let first = Input::fixture("")
  let second_owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "composer-second",
  }
  let second = {
    ..first,
    identity: { owner: second_owner, archive_generation: 0 },
  }
  let (with_first, _) = Model(first).update(
    first,
    TextChanged("first draft"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (with_both, _) = with_first.update(
    second,
    TextChanged("second draft"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  inspect(with_both.active(first).draft.task, content="first draft")
  inspect(with_both.active(second).draft.task, content="second draft")
}

///|
test "background retirement prevents an old draft from reviving" {
  let input = Input::fixture("")
  let (drafted, _) = Model(input).update(
    input,
    TextChanged("retired draft"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let retired = { ..input, retirements: [input.identity.owner] }
  let (without_old, _) = drafted.update(
    retired,
    EntriesRetired,
    Msg::test_emit(),
    Action::test_emit(),
  )
  inspect(without_old.active(retired).draft.task, content="")
}

///|
test "queued archive replacements preserve every draft handoff" {
  let input = Input::fixture("")
  let (drafted, _) = Model(input).update(
    input,
    TextChanged("draft through two rotations"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let first_fresh : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "composer-fresh-one",
  }
  let second_fresh : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "composer-fresh-two",
  }
  let rotated = {
    ..input,
    identity: { owner: second_fresh, archive_generation: 2 },
    replacements: [
      {
        archived: input.identity.owner,
        fresh: first_fresh,
        archive_generation: 1,
      },
      { archived: first_fresh, fresh: second_fresh, archive_generation: 2 },
    ],
    retirements: [input.identity.owner, first_fresh],
  }
  let (moved, _) = drafted.update(
    rotated,
    EntriesTransferred,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let entry = moved.active(rotated)
  inspect(entry.draft.task, content="draft through two rotations")
  assert_true(entry.owner == second_fresh)
  // The moved draft keeps the generation at which it was authored. The root
  // follows later archive facts from that cursor to resolve queued actions.
  inspect(entry.identity().archive_generation, content="0")
}

///|
test "file completion accepts a local candidate inside the component" {
  let input = {
    ..Input::fixture(""),
    file_candidates: [@pathx.Relative("src/main.mbt")],
  }
  let (searching, _) = Model(input).update(
    input,
    TextChanged("Inspect @main"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let entry = searching.active(input)
  guard entry.completion is Some(menu) else {
    fail("the file token should open completion")
  }
  assert_true(menu.kind is Files)
  assert_false(menu.menu.loading())
  inspect(menu.menu.length(), content="1")
  let (accepted, _) = searching.update(
    input,
    CompletionAccept,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let draft = accepted.active(input).draft
  inspect(draft.task, content="Inspect ")
  assert_true(
    draft.mentions ==
    [{ ref_: @mention_context.File(path="src/main.mbt"), range: None }],
  )
}

///|
test "goal submission acknowledgement preserves the prompt underneath" {
  let prompt = Input::fixture("waiting prompt")
  let goal = { ..prompt, goal: { ..prompt.goal, draft: Some("old goal") } }
  let (edited, _) = Model(goal).update(
    goal,
    TextChanged("new goal"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (submitted, _) = edited.update(
    goal,
    SubmitRequested,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let accepted = { ..prompt, submission_sequence: 1 }
  let entry = submitted.active(accepted)
  inspect(entry.draft.task, content="waiting prompt")
  assert_true(entry.goal_draft is None)
  assert_true(entry.pending_submission is None)
}

///|
test "draft prompt encoding belongs to composer" {
  let draft : Draft = {
    task: "inspect this",
    mentions: [
      { ref_: @mention_context.File(path="src/main.mbt"), range: None },
    ],
  }
  assert_true(draft.prompt().contains("<user_mentions>"))
  assert_true(draft.prompt().contains("inspect this"))
}

///|
#warnings("-alert_unstable")
test "composer declares form focus ownership" {
  let input = Input::fixture("")
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      Model(input)
      .active(input)
      .view(Msg::test_emit(), Action::test_emit(), input),
    )
  })
  assert_true(markup.contains("class=\"composer-inner\""))
  assert_true(markup.contains("data-focus-owner=\"\""))
  assert_true(markup.contains("data-focus-target=\"\""))
}
