///|
test "a reply starts an empty draft with the quote, then the comment" {
  assert_eq(
    quote_insertion("", "first line", " why? "),
    "> first line\n\nwhy?\n\n",
  )
}

///|
test "a reply without a comment leaves a blank line after the quote" {
  assert_eq(quote_insertion("", "first line", ""), "> first line\n\n")
}

///|
test "a reply keeps every selected line inside the block quote" {
  assert_eq(
    quote_insertion("", "  first  \n\nsecond\n", ""),
    "> first\n>\n> second\n\n",
  )
}

///|
test "a reply is separated from the existing draft by one blank line" {
  assert_eq(quote_insertion("draft", "text", "ok"), "\n\n> text\n\nok\n\n")
  assert_eq(quote_insertion("draft\n", "text", ""), "\n> text\n\n")
  assert_eq(quote_insertion("> earlier\n\nok\n\n", "text", ""), "> text\n\n")
}

///|
fn Model::quoted(
  self : Model,
  input : Input,
  identity : Identity,
  send~ : Bool,
) -> Model {
  self.update(
    input,
    QuoteReplied({
      identity,
      content: Text(quote=Some("quoted"), comment="why?"),
      images: [],
      send,
      accepted: @cmd.none,
      declined: @cmd.none,
    }),
    Msg::test_emit(),
    Action::test_emit(),
  ).0
}

///|
test "a batched reply joins the prompt draft and waits there" {
  let input = Input::fixture("")
  let (typed, _) = Model(input).update(
    input,
    TextChanged("draft"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let entry = typed.quoted(input, input.identity, send=false).active(input)
  assert_eq(entry.draft.task, "draft\n\n> quoted\n\nwhy?\n\n")
  assert_true(entry.pending_submission is None)
}

///|
test "a reply sent now submits the draft past an open completion menu" {
  let input = {
    ..Input::fixture(""),
    file_candidates: [@pathx.Relative("src/main.mbt")],
  }
  let (searching, _) = Model(input).update(
    input,
    TextChanged("@main"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(searching.active(input).completion is Some(_))
  let entry = searching.quoted(input, input.identity, send=true).active(input)
  assert_true(entry.completion is None)
  assert_true(
    entry.pending_submission
    is Some(
      PromptSubmission(
        sequence_before=0,
        { task: "@main\n\n> quoted\n\nwhy?\n\n", .. }
      )
    ),
  )
}

///|
test "a reply addressed to another conversation is declined" {
  let input = Input::fixture("draft")
  let other : Identity = {
    owner: { channel: @interop.ChannelId::Local, session: "another", },
    archive_generation: 0,
  }
  let entry = Model(input).quoted(input, other, send=true).active(input)
  assert_eq(entry.draft.task, "draft")
  assert_true(entry.pending_submission is None)
  let archived = { ..input.identity, archive_generation: 1, }
  assert_eq(
    Model(input).quoted(input, archived, send=false).active(input).draft.task,
    "draft",
  )
}

///|
test "a composer that is not editing a message declines a reply" {
  let prompt = Input::fixture("draft")
  let goal = {
    ..prompt,
    goal: { draft: Some("ship it"), standing: None, pending: None, },
  }
  assert_true(goal.quote_target() is None)
  let entry = Model(goal).quoted(goal, goal.identity, send=true).active(goal)
  assert_eq(entry.draft.task, "draft")
  assert_eq(entry.goal_draft, Some("ship it"))
  assert_true(entry.pending_submission is None)
  let disabled = {
    ..prompt,
    presentation: { ..prompt.presentation, disabled: true, },
  }
  assert_true(disabled.quote_target() is None)
  assert_eq(
    Model(disabled)
    .quoted(disabled, disabled.identity, send=false)
    .active(disabled).draft.task,
    "draft",
  )
  // A `!` draft would run the reply as part of its shell command.
  let shell = { ..Input::fixture("!echo hello"), shell_available: true, }
  let entry = Model(shell)
    .quoted(shell, shell.identity, send=true)
    .active(shell)
  assert_eq(entry.draft.task, "!echo hello")
  assert_true(entry.pending_submission is None)
}

///|
test "image feedback preserves local typing and uses ordinary submission" {
  for send in [false, true] {
    let base = Input::fixture("")
    let input = {
      ..base,
      presentation: { ..base.presentation, images_enabled: true, },
    }
    let typed = Model(input).update(
        input,
        TextChanged("local draft"),
        Msg::test_emit(),
        Action::test_emit(),
      ).0
    let image : Image = {
      name: "capture.png",
      url: "data:image/png;base64,image",
    }
    let next = typed.update(
      input,
      QuoteReplied({
        identity: input.identity,
        content: Text(quote=None, comment="Change this heading"),
        images: [image],
        send,
        accepted: @cmd.none,
        declined: @cmd.none,
      }),
      Msg::test_emit(),
      Action::test_emit(),
    ).0.active(input)
    if send {
      guard next.pending_submission is Some(PromptSubmission(draft, ..)) else {
        fail("not submitted")
      }
      assert_eq(draft.task, "local draft\n\nChange this heading\n\n")
      assert_true(draft.images == [image])
    } else {
      assert_eq(next.draft.task, "local draft\n\nChange this heading\n\n")
      assert_true(next.draft.images == [image])
      assert_true(next.pending_submission is None)
    }
  }
}

///|
test "a model which lost image support declines screenshot feedback" {
  let input = Input::fixture("keep")
  let next = Model(input).update(
    input,
    QuoteReplied({
      identity: input.identity,
      content: Text(quote=None, comment="change"),
      images: [{ name: "capture.png", url: "data:image/png;base64,image", }],
      send: true,
      accepted: @cmd.none,
      declined: @cmd.none,
    }),
    Msg::test_emit(),
    Action::test_emit(),
  ).0.active(input)
  assert_eq(next.draft.task, "keep")
  assert_true(next.draft.images.is_empty())
  assert_true(next.pending_submission is None)
}

///|
test "Office feedback batches mentions and images atomically with the live draft" {
  let payload : Json = {
    "schema": "office.selection.materialized.v1",
    "selection": { "kind": "pdf-region", "pages": [2] },
    "source": { "file": "/docs/slides.pdf" },
    "comment": "Change this </office_selection> & heading\nNext line",
  }
  let materialized = payload.stringify()
  let base = Input::fixture("")
  let input = {
    ..base,
    presentation: { ..base.presentation, images_enabled: true, },
  }
  let image : Image = {
    name: "region.png",
    url: "data:image/png;base64,image",
  }
  let reply : QuoteReply = {
    identity: input.identity,
    content: OfficeSelection(materialized),
    images: [image],
    send: false,
    accepted: @cmd.none,
    declined: @cmd.none,
  }
  let typed = Model(input).update(
      input,
      TextChanged("unsent local typing"),
      Msg::test_emit(),
      Action::test_emit(),
    ).0
  let batched = typed.update(
      input,
      QuoteReplied(reply),
      Msg::test_emit(),
      Action::test_emit(),
    ).0
  let draft = batched.active(input).draft
  assert_eq(draft.task, "unsent local typing")
  assert_true(draft.images == [image])
  assert_eq(draft.mentions.length(), 1)
  assert_true(
    draft.mentions[0].ref_
    is @mention_context.OfficeSelection(materialized=value) &&
    value == materialized,
  )
  let encoded = draft.prompt()
  assert_true(encoded.contains("<office_selection>"))
  guard @mention_context.parse(encoded) is Some(parsed) else {
    fail("structured reply did not round trip")
  }
  assert_true(parsed.mentions == draft.mentions.map(mention => mention.ref_))
  let submitted = batched.update(
    input,
    QuoteReplied({
      ..reply,
      content: OfficeSelection("second selection"),
      send: true,
    }),
    Msg::test_emit(),
    Action::test_emit(),
  ).0.active(input)
  guard submitted.pending_submission is Some(PromptSubmission(combined, ..)) else {
    fail("not submitted")
  }
  assert_eq(combined.task, "unsent local typing")
  assert_eq(combined.mentions.length(), 2)
  assert_true(combined.images == [image, image])
}
