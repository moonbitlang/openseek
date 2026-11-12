///|
fn history_test_state() -> State {
  {
    ..State::empty(),
    user_id: Some("user"),
    epoch: 1,
    sessions: [live_test_session()],
    conversations: Map([
      (
        "session",
        { ..Conversation::empty(), loading: false, history_required: false, },
      ),
    ]),
  }
}

///|
/// One turn per page; turn `offset + 1` is labelled `t<offset + 1>`.
fn history_test_page(offset : Int32, generating~ : Bool = false) -> History {
  {
    settings: None,
    offset: Some(offset),
    etag: Some("etag-\{offset}"),
    prediction: None,
    generating,
    session: native_document([]),
    messages: [
      {
        task_id: "t\{offset + 1}",
        kind: "user",
        data: {},
        created_at: offset.to_double(),
        engine_sequence: None,
      },
    ],
  }
}

///|
fn State::history_test_latest(self : State, page : History) -> State {
  let reading = self.load("session", Some("fixture"), _ => @cmd.none).0
  metadata_update(reading, Loaded(1, "session", reading.sequence, page))
}

///|
fn State::history_test_older(self : State, page : History) -> State {
  let older = metadata_update(self, LoadOlder("session"))
  metadata_update(older, OlderLoaded(1, "session", older.sequence, page))
}

///|
fn State::history_test_turns(self : State) -> Array[String] {
  self.conversations["session"].records.map(record => record.task_id)
}

///|
fn State::history_test_older_offset(self : State) -> Int32? {
  self.conversations["session"].history_older_request.map(request => request.1)
}

///|
fn history_test_cached_three(tail_generating~ : Bool = false) -> State {
  history_test_state()
  .history_test_latest(history_test_page(2, generating=tail_generating))
  .history_test_older(history_test_page(1))
  .history_test_older(history_test_page(0))
}

///|
test "Cloud renders only turns contiguous with a latest page another device moved ahead" {
  let cached = history_test_cached_three()
  assert_eq(cached.history_test_turns(), ["t1", "t2", "t3"])
  assert_false(cached.conversations["session"].can_load_older_history())
  let moved = cached.history_test_latest(history_test_page(4))
  assert_eq(moved.history_test_turns(), ["t5"])
  assert_true(moved.conversations["session"].can_load_older_history())
  let older = metadata_update(moved, LoadOlder("session"))
  assert_eq(older.history_test_older_offset(), Some(3))
  let closed = metadata_update(
    older,
    OlderLoaded(1, "session", older.sequence, history_test_page(3)),
  )
  assert_eq(closed.history_test_turns(), ["t1", "t2", "t3", "t4", "t5"])
  assert_false(closed.conversations["session"].can_load_older_history())
  assert_true(
    closed.conversations["session"].extends_history_backward(
      older.conversations["session"],
    ),
  )
}

///|
test "Cloud rereads a cached turn that was still running before it rejoins" {
  let cached = history_test_cached_three(tail_generating=true)
  let moved = cached.history_test_latest(history_test_page(4))
  let fourth = moved.history_test_older(history_test_page(3))
  assert_eq(fourth.history_test_turns(), ["t4", "t5"])
  let older = metadata_update(fourth, LoadOlder("session"))
  assert_eq(older.history_test_older_offset(), Some(2))
  let closed = metadata_update(
    older,
    OlderLoaded(1, "session", older.sequence, history_test_page(2)),
  )
  assert_eq(closed.history_test_turns(), ["t1", "t2", "t3", "t4", "t5"])
}

///|
test "Cloud pages backward through adjoining cached turns without a request" {
  let state = history_test_state()
  let conversation = state.conversations["session"].with_history_window({
    lo: 3,
    pages: [history_test_page(3)],
    detached: Map([(1, history_test_page(1)), (2, history_test_page(2))]),
  })
  let state = state.replace("session", conversation)
  let sequence = state.sequence
  let older = metadata_update(state, LoadOlder("session"))
  assert_eq(older.sequence, sequence)
  assert_eq(older.history_test_older_offset(), None)
  assert_eq(older.history_test_turns(), ["t2", "t3", "t4"])
  assert_true(
    older.conversations["session"].extends_history_backward(conversation),
  )
  let first = metadata_update(older, LoadOlder("session"))
  assert_eq(first.history_test_older_offset(), Some(0))
}

///|
test "Cloud keeps an older read only while it still adjoins the window" {
  let latest = history_test_state().history_test_latest(history_test_page(4))
  let older = metadata_update(latest, LoadOlder("session"))
  let unchanged = older.history_test_latest(history_test_page(4))
  assert_eq(unchanged.history_test_older_offset(), Some(3))
  let moved = unchanged.history_test_latest(history_test_page(6))
  assert_eq(moved.history_test_older_offset(), None)
  assert_eq(moved.history_test_turns(), ["t7"])
  let stale = metadata_update(
    moved,
    OlderLoaded(1, "session", older.sequence, history_test_page(3)),
  )
  assert_eq(stale.history_test_turns(), ["t7"])
}

///|
test "Cloud latest page inside the window drops the turns after it" {
  let cached = history_test_cached_three()
  let shorter = cached.history_test_latest(history_test_page(1))
  assert_eq(shorter.history_test_turns(), ["t1", "t2"])
  assert_false(shorter.conversations["session"].can_load_older_history())
}
