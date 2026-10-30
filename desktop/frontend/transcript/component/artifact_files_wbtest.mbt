///|
test "late artifact responses cannot update another session or workspace" {
  let original = {
    ..base_input(),
    current_project: @resource.of_path(Local, "/one"),
  }
  let reference = "artifact://chart.html"
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
      Ok({ path: "/old/chart.html", content: Some("old"), }),
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
      Ok({ path: "/old/chart.html", content: Some("old"), }),
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
  let reference = "artifact://chart.html"
  let (loading, _) = ArtifactFileCache::empty().begin_read(
    owner, reference, emit,
  )
  let (duplicate, _) = loading.begin_read(owner, reference, emit)
  assert_true(duplicate == loading)
  let ready = loading.settle(
    reference,
    Ok({ path: "/artifact/chart.html", content: Some("first"), }),
  )
  assert_true(ready.0.get(reference) is Some(ReadyArtifact("first")))
  assert_true(
    ready.settle(
      reference,
      Ok({ path: "/artifact/chart.html", content: Some("late"), }),
    ) ==
    ready,
  )
}
