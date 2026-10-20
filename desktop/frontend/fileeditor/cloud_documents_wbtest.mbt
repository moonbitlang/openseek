///|
test "Cloud restores settled open documents through sync and explicit owner preparation" {
  let emit = test_emit()
  let a = cloud_ctx("account", "a", 1)
  let b = cloud_ctx("account", "b", 1)
  let path = a.resource(Relative("saved.txt")).unwrap()
  let pending = a.resource(Relative("pending.txt")).unwrap()
  let a = { ..a, open_files: [path, pending], active_file: Some(path), }
  let (state, _) = sync(emit, State::empty(), a)
  let state = {
    ..state,
    docs: Map([
      (path, loaded_doc("saved.txt")),
      (
        pending,
        { name: "pending.txt", state: TabLoading, review: None, stale: false, },
      ),
    ]),
  }
  let (away, _) = sync(emit, state, b)
  assert_true(away.docs.is_empty())
  let cached = away.cloud_documents.get(a.owner).unwrap()
  assert_true(cached.get(path) == state.docs.get(path))
  assert_false(cached.contains(pending))
  let (returned, _) = sync(emit, away, a)
  assert_true(returned.docs.get(path) == state.docs.get(path))
  assert_true(returned.docs.get(pending) is Some({ state: TabLoading, .. }))
  assert_false(returned.cloud_documents.contains(a.owner))
  assert_true(returned.request_epoch > state.request_epoch)
  let prepared = away.prepare_owner(a.owner, a.open_files, cloud_epoch=1)
  let (prepared, _) = sync(emit, prepared, a)
  assert_true(prepared.docs.get(path) == state.docs.get(path))
  let (_, closed) = close_document(
    emit,
    returned,
    a,
    path,
    next=None,
    was_active=true,
  )
  let (away, _) = sync(emit, closed, b)
  assert_false(away.cloud_documents.contains(a.owner))
  let (reopened, _) = sync(emit, away, a)
  assert_true(reopened.docs.get(path) is Some({ state: TabLoading, .. }))
}

///|
test "background Cloud completion invalidates cached documents even without a visible checkout" {
  let a = cloud_ctx("account", "a", 1)
  let path = a.resource(Relative("large.txt")).unwrap()
  let a = { ..a, open_files: [path], active_file: Some(path), }
  let (state, _) = sync(test_emit(), State::empty(), a)
  let state = { ..state, docs: Map([(path, loaded_doc("large.txt"))]), }
  let b = { ..test_ctx(), placement: None, }
  let (away, _) = sync(test_emit(), state, b)
  let (_, finished) = update(test_emit(), RunSettled(owner=a.owner), away, b)
  assert_true(finished.docs.is_empty())
  assert_true(
    finished.cloud_documents.get(a.owner).unwrap().get(path)
    is Some({ stale: true, .. }),
  )
  let (returned, _) = sync(test_emit(), finished, a)
  assert_true(
    returned.docs.get(path) is Some({ state: TabLoaded(..), stale: true, .. }),
  )
}

///|
test "Cloud cache retirement is scoped to one session or one account" {
  let a = @interop.Cloud(account="account", session="a")
  let b = @interop.Cloud(account="account", session="b")
  let other = @interop.Cloud(account="other", session="a")
  let docs = Map([
    (
      @resource.join_relative(
        @resource.cloud_root(@cloud.CloudOrigin, "account", "a").unwrap(),
        Relative("a.txt"),
      ),
      loaded_doc("a.txt"),
    ),
  ])
  let state = {
    ..State::empty(),
    owner: Some(a),
    docs,
    cloud_documents: Map([(b, docs), (other, Map([]))]),
  }
  let (deleted, _) = forget_cloud_files(state, "account", session="b")
  assert_true(deleted.docs == docs)
  assert_false(deleted.cloud_documents.contains(b))
  assert_true(deleted.cloud_documents.contains(other))
  let (signed_out, _) = forget_cloud_files(state, "account")
  assert_true(signed_out.docs.is_empty())
  assert_true(signed_out.request_epoch > state.request_epoch)
  assert_false(signed_out.cloud_documents.contains(b))
  assert_true(signed_out.cloud_documents.contains(other))
}
