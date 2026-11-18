///|
fn step(
  state : @connectors.State,
  msg : @connectors.Msg,
) -> @connectors.State raise {
  let emit = @cmd.Emit(_ => @cmd.none)
  let (_, first) = @connectors.update(emit, msg, state, open_external=_ => {
    @cmd.none
  })
  let (_, second) = @connectors.update(emit, msg, state, open_external=_ => {
    @cmd.none
  })
  assert_true(first == second)
  first
}

///|
test "cancel fences a late successful OAuth poll and permits another login" {
  let initial = @connectors.State::empty()
  let starting = step(initial, Connect("github"))
  assert_true(step(starting, Connect("other")) == starting)
  let waiting = step(
    starting,
    Received(1, Some("github"), {
      connectors: [],
      error: None,
      authorization: Some({
        attempt: "attempt-1",
        url: "https://github.com/login/device",
        code: Some("ABCD"),
      }),
    }),
  )
  assert_true(step(waiting, Refresh) == waiting)
  let cancelling = step(waiting, Cancel)
  assert_true(
    step(
      cancelling,
      Received(1, Some("github"), {
        connectors: [],
        error: None,
        authorization: None,
      }),
    ) ==
    cancelling,
  )
  assert_true(step(cancelling, Poll(1, "github", "attempt-1")) == cancelling)
  let cancelled = step(
    cancelling,
    Received(2, Some("github"), {
      connectors: [],
      error: None,
      authorization: None,
    }),
  )
  assert_false(step(cancelled, Connect("github")) == cancelled)
}

///|
test "authorization error allows retry and refresh supersedes old list" {
  let loading = step(@connectors.State::empty(), Refresh)
  let ready = step(
    loading,
    Received(1, None, { connectors: [], error: None, authorization: None, }),
  )
  let starting = step(ready, Connect("github"))
  let expired = step(
    starting,
    Received(2, Some("github"), {
      connectors: [],
      authorization: None,
      error: Some("Authorization expired"),
    }),
  )
  assert_false(step(expired, Connect("github")) == expired)
  assert_true(
    step(
      starting,
      Received(1, None, { connectors: [], error: None, authorization: None, }),
    ) ==
    starting,
  )
  let changing = step(ready, Disconnect("github"))
  assert_true(step(changing, Connect("github")) == changing)
}

///|
test "only a successful empty list shows the empty state" {
  let initial = @connectors.State::empty()
  assert_false(initial.is_empty())
  let loading = step(initial, Refresh)
  assert_false(loading.is_empty())
  let failed = step(
    loading,
    Received(1, None, {
      connectors: [],
      authorization: None,
      error: Some("offline"),
    }),
  )
  assert_false(failed.is_empty())
  let retry = step(failed, Refresh)
  let empty = step(
    retry,
    Received(2, None, { connectors: [], authorization: None, error: None, }),
  )
  assert_true(empty.is_empty())
  let refreshing = step(empty, Refresh)
  let failed_again = step(
    refreshing,
    Received(3, None, {
      connectors: [],
      authorization: None,
      error: Some("read failed"),
    }),
  )
  assert_false(failed_again.is_empty())
}

///|
test "the authorization page opens once when connect returns not on polls" {
  let emit = @cmd.Emit(_ => @cmd.none)
  let opened : Array[String] = []
  let open_external = (url : String) => {
    opened.push(url)
    @cmd.none
  }
  let (_, starting) = @connectors.update(
    emit,
    Connect("github"),
    @connectors.State::empty(),
    open_external~,
  )
  let reply : @protocol.ConnectorReply = {
    connectors: [],
    error: None,
    authorization: Some({
      attempt: "login",
      url: "https://github.com/login/device",
      code: Some("ABCD"),
    }),
  }
  let (_, waiting) = @connectors.update(
    emit,
    Received(1, Some("github"), reply),
    starting,
    open_external~,
  )
  assert_eq(opened, ["https://github.com/login/device"])
  let (_, waiting_again) = @connectors.update(
    emit,
    Received(1, Some("github"), reply),
    waiting,
    open_external~,
  )
  assert_true(waiting_again == waiting)
  assert_eq(opened.length(), 1)
  let (_, cancelled) = @connectors.update(emit, Cancel, waiting, open_external~)
  let (_, stale) = @connectors.update(
    emit,
    Received(1, Some("github"), reply),
    cancelled,
    open_external~,
  )
  assert_true(stale == cancelled)
  assert_eq(opened.length(), 1)
}
