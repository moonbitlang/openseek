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
    owner: @interop.Host({
      channel: @interop.ChannelId::Local,
      session: "another",
    }),
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

///|
test "selection feedback retains the pending snapshot until acknowledgement for Local and Cloud" {
  for cloud in [false, true] {
    let base = Input::fixture("")
    let input = {
      ..base,
      identity: if cloud {
        {
          owner: @interop.Cloud(account="account", session="session"),
          archive_generation: 0,
        }
      } else {
        base.identity
      },
      presentation: { ..base.presentation, images_enabled: true, },
    }
    let old : Image = { name: "sent.png", url: "data:image/png;base64,YQ==", }
    let next : Image = {
      name: "capture.png",
      url: "data:image/png;base64,Yg==",
    }
    let draft : Draft = {
      task: "sent",
      images: [old],
      mentions: [{ ref_: File(path="sent.pdf"), range: None, }],
    }
    let model = Model(input).with_entry({ ..Entry(input), draft, })
    let sending = model.update(
        input,
        SubmitRequested,
        Msg::test_emit(),
        Action::test_emit(),
      ).0
    let payload : Json = {
      "schema": "office.selection.materialized.v1",
      "selection": { "kind": "pdf-region", "pages": [2] },
      "source": { "file": "/docs/slides.pdf" },
      "comment": "Change this",
    }
    let quoted = sending.update(
        input,
        QuoteReplied({
          identity: input.identity,
          content: OfficeSelection(payload.stringify()),
          images: [next],
          send: false,
          accepted: @cmd.none,
          declined: @cmd.none,
        }),
        Msg::test_emit(),
        Action::test_emit(),
      ).0
    assert_true(
      quoted.active(input).pending_submission is Some(PromptSubmission(_, ..)),
    )
    let acknowledged = quoted.active({ ..input, submission_sequence: 1, }).draft
    assert_eq(acknowledged.task, "")
    assert_eq(acknowledged.images, [next])
    assert_true(acknowledged.mentions is [{ ref_: OfficeSelection(..), .. }])
  }
}

///|
test "Cloud annotations preserve typing, owner isolation and ordinary send availability" {
  let base = Input::fixture("")
  let input = {
    ..base,
    identity: {
      owner: @interop.Cloud(account="account", session="session"),
      archive_generation: 0,
    },
  }
  let mention : Mention = {
    ref_: Annotation(
      file="src/main.mbt",
      start_line=2,
      end_line=3,
      quote="selected code",
      comment="Explain this",
      side=WorkingRevision,
    ),
    range: Some(@common.Range(2, 1, 3, 4)),
  }
  let reply : QuoteReply = {
    identity: input.identity,
    content: Annotation(mention),
    images: [],
    send: false,
    accepted: @cmd.none,
    declined: @cmd.none,
  }
  let typed = Model(input).update(
      input,
      TextChanged("unsent typing"),
      Msg::test_emit(),
      Action::test_emit(),
    ).0
  let batched = typed.update(
      input,
      QuoteReplied(reply),
      Msg::test_emit(),
      Action::test_emit(),
    ).0
  assert_eq(batched.active(input).draft.task, "unsent typing")
  assert_eq(batched.active(input).draft.mentions, [mention])
  let running = {
    ..input,
    presentation: {
      ..input.presentation,
      primary_action: Send(available=false),
    },
  }
  let entry = batched.update(
    running,
    QuoteReplied({ ..reply, send: true, }),
    Msg::test_emit(),
    Action::test_emit(),
  ).0.active(running)
  assert_eq(entry.draft.mentions, [mention])
  assert_true(entry.pending_submission is None)
  for
    unavailable in [
      { ..input, identity: { ..input.identity, archive_generation: 1, }, },
      { ..input, presentation: { ..input.presentation, disabled: true, }, },
      {
        ..input,
        identity: {
          ..input.identity,
          owner: @interop.Cloud(account="other", session="session"),
        },
      },
      {
        ..input,
        identity: {
          ..input.identity,
          owner: @interop.Cloud(account="account", session="other"),
        },
      },
    ] {
    let entry = Model(unavailable).update(
      unavailable,
      QuoteReplied(reply),
      Msg::test_emit(),
      Action::test_emit(),
    ).0.active(unavailable)
    assert_true(entry.draft.mentions.is_empty())
  }
  let sent = batched.update(
    input,
    SubmitRequested,
    Msg::test_emit(),
    Action::test_emit(),
  ).0.active(input)
  assert_true(
    sent.pending_submission
    is Some(
      PromptSubmission({ task: "unsent typing", mentions: [saved], .. }, ..)
    ) &&
    saved == mention,
  )
}

///|
test "editor feedback conversion preserves exact text and revision navigation" {
  let range = @common.Range(5, 2, 6, 8)
  for
    side in [
      @mention_context.WorkingRevision,
      @mention_context.OriginalRevision,
    ] {
    let mention = Mention::editor_annotation(
      "src/main.mbt",
      range,
      "exact\nselection",
      "Explain this",
      side~,
    )
    assert_eq(
      mention.ref_,
      @mention_context.Annotation(
        file="src/main.mbt",
        start_line=5,
        end_line=6,
        quote="exact\nselection",
        comment="Explain this",
        side~,
      ),
    )
    assert_eq(
      mention.range,
      if side is @mention_context.OriginalRevision {
        None
      } else {
        Some(range)
      },
    )
  }
}
