///|
test "late artifact responses cannot update another session or workspace" {
  let original = {
    ..base_input(),
    current_project: @resource.of_path(Local, "/one"),
  }
  let reference = "scratch/artifact/chart.html"
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (files, _) = ArtifactFileCache::empty().begin_read(
    original.artifact_owner(),
    reference,
    emit,
  )
  let model = { ..pinned_model(original), artifact_files: files, }
  let next = { ..original, active_session: "other", }
  let (ignored, _) = model.update(
    next,
    ArtifactResolved(
      original.artifact_owner(),
      reference,
      Ok(
        @protocol.Content(
          content="old",
          absolute="/work/page.html",
          sig="fixture",
        ),
      ),
    ),
    emit,
  )
  assert_true(ignored.artifact_files.0.is_empty())
  let same_id_other_workspace = {
    ..original,
    current_project: @resource.of_path(Local, "/two"),
  }
  assert_true(
    original.artifact_owner().key() !=
    same_id_other_workspace.artifact_owner().key(),
  )
  let (ignored, _) = model.update(
    same_id_other_workspace,
    ArtifactResolved(
      original.artifact_owner(),
      reference,
      Ok(
        @protocol.Content(
          content="old",
          absolute="/work/page.html",
          sig="fixture",
        ),
      ),
    ),
    emit,
  )
  assert_true(ignored.artifact_files.0.is_empty())
}

///|
test "one artifact read supplies all repeated references without replacing settled content" {
  let owner = {
    ..base_input(),
    current_project: @resource.of_path(Local, "/work"),
  }.artifact_owner()
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let reference = "scratch/artifact/chart.html"
  let (loading, _) = ArtifactFileCache::empty().begin_read(
    owner, reference, emit,
  )
  let (duplicate, _) = loading.begin_read(owner, reference, emit)
  assert_true(duplicate == loading)
  let ready = loading.settle(
    reference,
    Ok(
      @protocol.Content(
        content="first",
        absolute="/work/page.html",
        sig="fixture",
      ),
    ),
  )
  assert_true(ready.0.get(reference) is Some(ReadyArtifact("first")))
  assert_true(
    ready.settle(
      reference,
      Ok(
        @protocol.Content(
          content="late",
          absolute="/work/page.html",
          sig="fixture",
        ),
      ),
    ) ==
    ready,
  )
}

///|
test "artifact follow-ups decode the question and the captured state" {
  let reference = "scratch/artifact/chart.html"
  let payload = "{\"title\":\"Selected settings\",\"state\":{\"workers\":8}}"
  let message = @js.Value::from_json({
    "prompt": "  Explain this result. ",
    "title": " Explain ",
  })
  assert_true(
    decode_artifact_followup(reference, payload, message)
    is Some(
      RequestFollowup(
        prompt="Explain this result.",
        title="Explain",
        snapshot=Some(snapshot)
      )
    ) &&
    snapshot.state == { "workers": 8 },
  )
  let invalid_messages : Array[Json] = [
    { "prompt": " \n ", "title": "Explain" },
    { "prompt": "Explain this result.", "title": 42 },
  ]
  for invalid in invalid_messages {
    assert_true(
      decode_artifact_followup(
        reference,
        payload,
        @js.Value::from_json(invalid),
      )
      is None,
    )
  }
}
