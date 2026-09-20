///|
fn saved_review_selection(file : String) -> @mention_context.ReviewChanges {
  {
    source: {
      workspace: "/work",
      file,
      original_file: None,
      base: Some("baseline"),
      version: "saved-comparison",
    },
    excerpts: [
      {
        original: [{ number: 2, text: "old", }],
        modified: [{ number: 2, text: "new", }],
      },
    ],
  }
}

///|
fn saved_review_file(file : String) -> @fileeditor.ChangedFile {
  {
    path: Relative(file),
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
}

///|
fn click_saved_review(model : Model, file : String) -> Model raise {
  guard model.transcript_slot() is Some(slot) else {
    fail("expected a visible transcript")
  }
  let (_, next) = update(
    test_dispatch(),
    TranscriptReviewChangesOpened(
      slot=slot.key(),
      selection=saved_review_selection(file),
    ),
    model,
  )
  next
}

///|
fn review_inventory_reply(
  model : Model,
  files : Array[@fileeditor.ChangedFile],
) -> Msg {
  FileEditor(
    @fileeditor.ChangesLoaded(
      owner=file_ctx(model).owner,
      generation=model.file_panel.changes_generation,
      repository=true,
      head=Some("baseline"),
      files~,
    ),
  )
}

///|
test "saved review jump loads a cold inventory and waits for its final snapshot" {
  let initial = desktop_model()
  assert_true(initial.file_panel.changes is @fileeditor.ChangeListIdle)
  let loading = click_saved_review(initial, "src/main.mbt")
  assert_true(loading.right_panel_open)
  assert_true(loading.dock.active is Some(FilePicker))
  assert_eq(loading.notifications.length(), 0)
  assert_true(loading.pending_review_context is Some(_))
  // Opening the watcher coalesces a fresh request. An intermediate empty
  // snapshot must not announce a missing change or spend the pending jump.
  let (_, intermediate) = update(
    test_dispatch(),
    review_inventory_reply(loading, []),
    loading,
  )
  assert_true(intermediate.pending_review_context is Some(_))
  assert_eq(intermediate.notifications.length(), 0)
  let (_, opened) = update(
    test_dispatch(),
    review_inventory_reply(intermediate, [saved_review_file("src/main.mbt")]),
    intermediate,
  )
  let file = opened.test_file("src/main.mbt")
  assert_eq(@dock.active_file(opened.dock), Some(file))
  assert_true(
    opened.file_panel.docs.get(file)
    is Some({ review: Some({ view_mode: @fileeditor.ReviewDiff, .. }), .. }),
  )
  assert_eq(
    opened.file_panel.review_context_reveal,
    Some(saved_review_selection("src/main.mbt")),
  )
  assert_true(opened.pending_review_context is None)
  assert_eq(opened.notifications.length(), 0)
}

///|
test "the latest saved review jump wins and rejects unrelated inventory replies" {
  let first = click_saved_review(desktop_model(), "src/first.mbt")
  let last = click_saved_review(first, "src/last.mbt")
  let owner = file_ctx(last).owner
  for
    stale in [
      @fileeditor.ChangesLoaded(
        owner={ ..owner, session: "another-session", },
        generation=last.file_panel.changes_generation,
        repository=true,
        head=Some("baseline"),
        files=[],
      ),
      @fileeditor.ChangesFailed(
        owner~,
        generation=last.file_panel.changes_generation - 1,
        message="obsolete failure",
      ),
    ] {
    let (_, unchanged) = update(test_dispatch(), FileEditor(stale), last)
    assert_true(unchanged.pending_review_context == last.pending_review_context)
    assert_true(unchanged.dock.active is Some(FilePicker))
    assert_eq(unchanged.notifications.length(), 0)
  }
  let (_, intermediate) = update(
    test_dispatch(),
    review_inventory_reply(last, []),
    last,
  )
  let (_, opened) = update(
    test_dispatch(),
    review_inventory_reply(intermediate, [
      saved_review_file("src/first.mbt"),
      saved_review_file("src/last.mbt"),
    ]),
    intermediate,
  )
  assert_eq(
    @dock.active_file(opened.dock),
    Some(opened.test_file("src/last.mbt")),
  )
  assert_eq(
    opened.file_panel.review_context_reveal,
    Some(saved_review_selection("src/last.mbt")),
  )
  assert_eq(opened.notifications.length(), 0)
}

///|
test "competing navigation or conversation cancels an inventory-backed saved review jump" {
  let model = desktop_model()
    .replace_conversation({
      ..test_conversation(),
      session_id: "desktop-other",
    })
    .with_listed(["desktop-test", "desktop-other"])
  let loading = click_saved_review(model, "src/main.mbt")
  for
    navigation in [
      JumpToLocation(path="other.mbt", range=None, annotation=None),
      ExplorerRequested(@fileeditor.ExplorerFiles),
      ToggleRightPanel,
      OpenSession(@interop.ChannelId::Local, "desktop-other"),
    ] {
    let (_, moved) = update(test_dispatch(), navigation, loading)
    assert_true(moved.pending_review_context is None)
    let (_, replied) = update(
      test_dispatch(),
      review_inventory_reply(loading, [saved_review_file("src/main.mbt")]),
      moved,
    )
    assert_true(replied.dock.active == moved.dock.active)
    assert_true(replied.file_panel.review_context_reveal is None)
    assert_eq(replied.notifications.length(), 0)
  }
}

///|
test "saved review jumps distinguish a missing change from an inventory failure" {
  let loading = click_saved_review(desktop_model(), "src/main.mbt")
  let (_, waiting) = update(
    test_dispatch(),
    review_inventory_reply(loading, []),
    loading,
  )
  let (_, missing) = update(
    test_dispatch(),
    review_inventory_reply(waiting, []),
    waiting,
  )
  assert_true(missing.pending_review_context is None)
  assert_eq(missing.notifications.length(), 1)
  assert_eq(
    missing.notifications[0].message,
    "This selection belongs to a review that is no longer available. Its saved context is unchanged.",
  )
  // A failed refresh can leave an older cached list visible. That list is
  // useful for browsing but must not turn this failed jump into a success.
  for
    changes in [
      @fileeditor.ChangeListLoading(refresh_again=false),
      @fileeditor.ChangeListReady(
        repository=true,
        files=[saved_review_file("src/main.mbt")],
        refreshing=true,
        refresh_again=false,
      ),
    ] {
    let model = { ..waiting, file_panel: { ..waiting.file_panel, changes, }, }
    let (_, failed) = update(
      test_dispatch(),
      FileEditor(
        @fileeditor.ChangesFailed(
          owner=file_ctx(model).owner,
          generation=model.file_panel.changes_generation,
          message="Git is unavailable",
        ),
      ),
      model,
    )
    assert_true(failed.pending_review_context is None)
    assert_true(@dock.active_file(failed.dock) is None)
    assert_eq(failed.notifications.length(), 1)
    assert_eq(
      failed.notifications[0].message,
      "Unable to load the current review: Git is unavailable",
    )
  }
}
