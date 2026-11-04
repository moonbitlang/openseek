///|
test "a late desktop cache read cannot replace a fresh Cloud page" {
  let state = progress_test_state()
  let (disk, _, _) = update(
    state,
    Open("session"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
    desktop_history=true,
  )
  let disk_request = disk.conversations["session"].request
  let network = disk.load("session", Some("fixture"), _ => @cmd.none).0
  let page : History = {
    session: native_document([]),
    messages: [],
    offset: Some(0),
    etag: Some("fresh"),
    generating: false,
    prediction: None,
  }
  let fresh = metadata_update(
    network,
    Loaded(state.epoch, "session", network.sequence, page),
  )
  let late = metadata_update(
    fresh,
    DiskHistoryLoaded(
      state.epoch,
      "session",
      disk_request,
      Some({ ..page, etag: Some("stale"), }),
    ),
  )
  assert_eq(late.conversations["session"].history_etag, Some("fresh"))
  assert_eq(late.sequence, fresh.sequence)
}
