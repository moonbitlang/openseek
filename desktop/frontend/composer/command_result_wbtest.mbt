///|
test "standalone command results preserve both providers' newer drafts" {
  for
    owner in [
      Input::fixture("").identity.owner,
      @interop.Cloud(account="account", session="cloud"),
    ] {
    let base = Input::fixture("later writing")
    let input = {
      ..base,
      identity: { ..base.identity, owner, },
      draft: {
        ..base.draft,
        images: [{ name: "photo", url: "data:image/png;base64,eA==", }],
      },
    }
    let actions : Array[Action] = []
    let emit = @cmd.Emit(action => {
      actions.push(action)
      @cmd.none
    })
    let (pending, _) = Model(input).command_result(
      Ready(input, "command", "result"),
      emit,
    )
    assert_true(
      actions is [CommandResultSubmitted(text="result", choice=None, ..)],
    )
    assert_eq(pending.active(input).draft, input.draft)
    let (rejected, _) = pending.command_result(
      Settled(owner, "command", false),
      emit,
    )
    assert_eq(rejected.active(input).draft.task, "result\n\nlater writing")
    assert_eq(rejected.active(input).draft.images, input.draft.images)
    let (repeated, _) = rejected.command_result(
      Settled(owner, "command", false),
      emit,
    )
    assert_eq(repeated.active(input).draft, rejected.active(input).draft)
    let (admitted, _) = repeated.command_result(
      Settled(owner, "command", true),
      emit,
    )
    assert_eq(admitted.active(input).draft, input.draft)
  }
}

///|
test "blocked results stay recoverable and restoring a command never overwrites writing" {
  let base = Input::fixture("newer draft")
  let input = {
    ..base,
    presentation: {
      ..base.presentation,
      primary_action: Send(available=false),
    },
  }
  let (held, _) = Model(input).command_result(
    Ready(input, "command", "output"),
    Action::test_emit(),
  )
  assert_eq(held.active(input).draft.task, "output\n\nnewer draft")
  let (kept, _) = held.command_result(
    Restore(input, "!original"),
    Action::test_emit(),
  )
  assert_eq(kept.active(input).draft.task, "output\n\nnewer draft")
  let empty = Input::fixture("")
  let (restored, _) = Model(empty).command_result(
    Restore(empty, "!original"),
    Action::test_emit(),
  )
  assert_eq(restored.active(empty).draft.task, "!original")
}

///|
test "background command results and late admission remain scoped to their own entry" {
  let first = Input::fixture("draft A")
  let second = {
    ..first,
    identity: {
      ..first.identity,
      owner: @interop.Cloud(account="account", session="B"),
    },
    draft: { ..first.draft, task: "draft B", },
  }
  let (pending, _) = Model(first).command_result(
    Ready(first, "one", "first result"),
    Action::test_emit(),
  )
  let pending = pending.with_entry(Entry(second))
  let (pending, _) = pending.command_result(
    Ready(first, "two", "second result"),
    Action::test_emit(),
  )
  let (held, _) = pending.command_result(
    Settled(first.identity.owner, "one", false),
    Action::test_emit(),
  )
  let (held, _) = held.command_result(
    Settled(first.identity.owner, "two", false),
    Action::test_emit(),
  )
  assert_eq(
    held.active(first).draft.task,
    "second result\n\nfirst result\n\ndraft A",
  )
  assert_eq(held.active(second).draft.task, "draft B")
  let (accepted, _) = held.command_result(
    Settled(first.identity.owner, "one", true),
    Action::test_emit(),
  )
  assert_eq(accepted.active(first).draft.task, "second result\n\ndraft A")
  let edited = accepted.with_entry({
    ..accepted.active(first),
    draft: { ..first.draft, task: "edited result", },
  })
  let (accepted, _) = edited.command_result(
    Settled(first.identity.owner, "two", true),
    Action::test_emit(),
  )
  assert_eq(accepted.active(first).draft.task, "edited result")
}

///|
test "command results follow the selected queue choice without consuming editor attachments" {
  let base = Input::fixture("later draft")
  let input = {
    ..base,
    presentation: {
      ..base.presentation,
      primary_action: Running(
        steer_available=true,
        can_stop=true,
        submit=Steer,
        queue_available=true,
      ),
    },
  }
  let entry = {
    ..Entry(input),
    followup_choice: Some(QueueNext),
    image_reads: 1,
  }
  let actions : Array[Action] = []
  let emit = @cmd.Emit(action => {
    actions.push(action)
    @cmd.none
  })
  let (pending, _) = Model(input)
    .with_entry(entry)
    .command_result(Ready(input, "one", "output"), emit)
  assert_true(actions is [CommandResultSubmitted(choice=Some(QueueNext), ..)])
  assert_eq(pending.active(input).image_reads, 1)
  assert_eq(pending.active(input).draft.task, "later draft")
}
