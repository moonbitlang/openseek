///|
test "shared file observations refresh all local tabs once and remain pure" {
  let (state, first) = @preview.open_page(
    @preview.State::empty(),
    url="file:///tmp/report%20one.pdf",
  )
  let (state, second) = @preview.open_page(
    state,
    url="file:///tmp/report%20one.pdf#page=2",
  )
  let path = @resource.of_path(@interop.ChannelId::Local, "/tmp/report one.pdf").unwrap()
  assert_true(state.local_files() == [path])
  let observed = state.observe_file(path, @protocol.Present("1"))
  assert_true(observed == state.observe_file(path, @protocol.Present("1")))
  // Observing a file cannot mutate the original state or interrupt loading.
  let (_, untouched) = state.take_file_reloads()
  assert_true(untouched.is_empty())
  let (waiting, reloads) = observed.take_file_reloads()
  assert_true(reloads.is_empty())
  let loaded = @preview.update(LoadingChanged(id=first, loading=false), waiting)
  let loaded = @preview.update(LoadingChanged(id=second, loading=false), loaded)
  let (accepted, reloads) = loaded.take_file_reloads()
  assert_eq(reloads, [first, second])
  let (again, again_ids) = loaded.take_file_reloads()
  assert_true(accepted == again)
  assert_eq(again_ids, reloads)
  let settled = @preview.update(
    LoadingChanged(id=first, loading=false),
    accepted,
  )
  let (_, repeated) = settled
    .observe_file(path, @protocol.Present("1"))
    .take_file_reloads()
  assert_true(repeated.is_empty())
  let changed = settled.observe_file(path, @protocol.Present("2"))
  let (_, refresh) = changed.take_file_reloads()
  assert_eq(refresh, [first])
  // A remote host's identical pathname must not refresh a native local tab.
  let remote = @resource.of_path(
    @interop.ChannelId::Remote("device"),
    path.path,
  ).unwrap()
  assert_true(settled.observe_file(remote, @protocol.Present("3")) == settled)
}

///|
test "preview changes coalesce during loading and navigation retires observations" {
  let (state, id) = @preview.open_page(
    @preview.State::empty(),
    url="file:///tmp/a.pdf",
  )
  let path = @resource.of_path(@interop.ChannelId::Local, "/tmp/a.pdf").unwrap()
  let pending = state
    .observe_file(path, @protocol.Present("1"))
    .observe_file(path, @protocol.Present("2"))
  let fragment = @preview.update(
    Navigated(id~, url="file:///tmp/a.pdf#page=3"),
    pending,
  )
  let loaded = @preview.update(LoadingChanged(id~, loading=false), fragment)
  let (reloading, reloads) = loaded.take_file_reloads()
  assert_eq(reloads, [id])
  let settled = @preview.update(LoadingChanged(id~, loading=false), reloading)
  let (_, repeated) = settled
    .observe_file(path, @protocol.Present("2"))
    .take_file_reloads()
  assert_true(repeated.is_empty())
  let moved = @preview.navigate(pending, id, "file:///tmp/b.pdf")
  let moved = @preview.update(LoadingChanged(id~, loading=false), moved)
  let (_, stale) = moved
    .observe_file(path, @protocol.Present("3"))
    .take_file_reloads()
  assert_true(stale.is_empty())
  let closed = @preview.close_page(pending, id)
  assert_true(closed.local_files().is_empty())
  let (_, stale) = closed
    .observe_file(path, @protocol.Missing)
    .take_file_reloads()
  assert_true(stale.is_empty())
}

///|
test "preview stat failures stay distinct from missing files and recovery refreshes" {
  let (state, id) = @preview.open_page(
    @preview.State::empty(),
    url="file:///tmp/a.pdf",
  )
  let state = @preview.update(LoadingChanged(id~, loading=false), state)
  let path = @resource.of_path(@interop.ChannelId::Local, "/tmp/a.pdf").unwrap()
  let failed = state.observe_file(path, @protocol.Failed("permission denied"))
  assert_true(failed.files_to_check() == [path])
  assert_true(
    @preview.page(failed, id).unwrap().failure == Some("permission denied"),
  )
  let (_, reloads) = failed.take_file_reloads()
  assert_true(reloads.is_empty())
  let (missing, reloads) = failed
    .observe_file(path, @protocol.Missing)
    .take_file_reloads()
  assert_eq(reloads, [id])
  let missing = @preview.update(LoadingChanged(id~, loading=false), missing)
  let (_, repeated) = missing
    .observe_file(path, @protocol.Missing)
    .take_file_reloads()
  assert_true(repeated.is_empty())
  let (_, restored) = missing
    .observe_file(path, @protocol.Present("restored"))
    .take_file_reloads()
  assert_eq(restored, [id])
}

///|
test "failed reload commands release loading and retry unchanged files on the shared poll" {
  let (state, id) = @preview.open_page(
    @preview.State::empty(),
    url="file:///work/a.pdf",
  )
  let path = @resource.of_path(@interop.ChannelId::Local, "/work/a.pdf").unwrap()
  assert_true(state.files_to_check() == [path])
  let loaded = @preview.update(LoadingChanged(id~, loading=false), state)
  let (reloading, ids) = loaded
    .observe_file(path, @protocol.Present("1"))
    .take_file_reloads()
  assert_eq(ids, [id])
  assert_true(reloading.files_to_check().is_empty())
  let failure = @preview.ReloadFailed(
    id~,
    url="file:///work/a.pdf",
    message="command rejected",
  )
  let failed = @preview.update(failure, reloading)
  assert_true(failed == @preview.update(failure, reloading))
  assert_false(@preview.page(failed, id).unwrap().loading)
  assert_true(failed.files_to_check() == [path])
  let (_, immediate) = failed.take_file_reloads()
  assert_true(immediate.is_empty())
  let (retrying, retry) = failed
    .observe_file(path, @protocol.Present("1"))
    .take_file_reloads()
  assert_eq(retry, [id])
  assert_true(@preview.page(retrying, id).unwrap().failure is None)
  let moved = @preview.navigate(reloading, id, "file:///work/b.pdf")
  assert_true(@preview.update(failure, moved) == moved)
  let closed = @preview.close_page(reloading, id)
  assert_true(@preview.update(failure, closed) == closed)
}
