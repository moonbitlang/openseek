///|
async fn new_store() -> @store.SessionStore {
  let root = @fs.tmpdir(prefix="openseek-session-store-")
  SessionStore(root)
}

///|
fn session_events_jsonl(session : @agent_session.Session) -> String {
  let builder = StringBuilder()
  for event in session.events() {
    builder <+ "\{event.to_json().stringify()}\n"
  }
  builder.to_string()
}

///|
fn session_header_jsonl(
  session : @agent_session.Session,
  allow_event_log_ahead? : Bool = true,
) -> String {
  let events_text = session_events_jsonl(session)
  let header : Json = {
    "version": 1,
    "id": session.id(),
    "system_prompt": session.system_prompt(),
    "last_sequence": session.last_sequence(),
    "event_log_length": events_text.length(),
    "event_log_hash": Hash::hash(events_text[:]),
    "allow_event_log_ahead": allow_event_log_ahead,
  }
  header.stringify()
}

///|
async test "store creates and loads a session from header and event log" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("hello")))
    .append(Terminal(Finished("done")))
  store.create(session)
  assert_true(store.exists(SessionId("s1")))
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.id().value(), "s1")
  assert_eq(loaded.system_prompt(), "system")
  assert_eq(loaded.events().length(), 2)
  assert_eq(loaded.last_sequence(), 2)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store lists known sessions" {
  let store = new_store()
  assert_eq(store.list().length(), 0)
  store.create(Session(SessionId("b"), system_prompt="system"))
  store.create(Session(SessionId("a"), system_prompt="system"))
  let ids = [ for id in store.list() => id.value() ]
  assert_eq(ids.length(), 2)
  assert_eq(ids[0], "a")
  assert_eq(ids[1], "b")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store picks the most recently active session as latest" {
  let store = new_store()
  assert_true(store.latest() is None)
  store.create(Session(SessionId("first"), system_prompt="system"))
  // Filesystem mtimes need a beat between writes to order reliably.
  @async.sleep(50)
  store.create(Session(SessionId("second"), system_prompt="system"))
  guard store.latest() is Some(id) else { fail("expected a latest session") }
  assert_eq(id.value(), "second")
  // Appending to the older session makes it the most recently active again.
  @async.sleep(50)
  let first = store.load(SessionId("first"))
  let _ = store.append(first, User(UserMessage("more")))
  guard store.latest() is Some(id) else { fail("expected a latest session") }
  assert_eq(id.value(), "first")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "listings order by recency and keep husk directories visible" {
  let store = new_store()
  let older : @agent_session.Session = Session(
    SessionId("older"),
    system_prompt="system",
  )
  store.create(older.append(User(UserMessage("  first\n prompt  here "))))
  @async.sleep(50)
  store.create(Session(SessionId("newer"), system_prompt="system"))
  // A directory with neither header nor event log — e.g. an interrupted
  // creation — has no stamp to order by but must stay discoverable.
  @fs.mkdir("\{store.root()}/sessions/husk", recursive=true)
  let listings = store.listings()
  assert_eq(listings.length(), 3)
  assert_eq(listings[0].id().value(), "newer")
  assert_true(listings[0].last_active_unix_seconds() is Some(_))
  assert_eq(listings[0].first_prompt(), "")
  assert_eq(listings[1].id().value(), "older")
  assert_eq(listings[1].first_prompt(), "  first\n prompt  here ")
  assert_eq(listings[2].id().value(), "husk")
  assert_true(listings[2].last_active_unix_seconds() is None)
  assert_eq(listings[2].first_prompt(), "")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "latest skips a torn newest session in favor of a loadable one" {
  let store = new_store()
  store.create(Session(SessionId("valid"), system_prompt="system"))
  @async.sleep(50)
  store.create(Session(SessionId("torn"), system_prompt="system"))
  // Simulate a crash between the event-log write and the header write: the
  // newest directory stats fine but cannot be loaded.
  @fs.remove("\{store.root()}/sessions/torn/session.json")
  guard store.latest() is Some(id) else { fail("expected a latest session") }
  assert_eq(id.value(), "valid")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store propagates non-missing list errors" {
  let store = new_store()
  @fs.write_file(
    "\{store.root()}/sessions",
    "not a directory",
    create_mode=CreateOrTruncate,
  )
  let _ = store.list() catch {
    error => {
      assert_true("\{error}" != "")
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("list error was silently treated as empty")
}

///|
async test "store appends one event without rewriting the in-memory caller value" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  store.create(session)
  let next = store.append(session, User(UserMessage("first")))
  assert_eq(session.events().length(), 0)
  assert_eq(next.events().length(), 1)
  let after = store.append(next, Runtime(RuntimeNotice("update")))
  let loaded = store.load(SessionId("s1"))
  assert_eq(after.events().length(), 2)
  assert_eq(loaded.events().length(), 2)
  guard loaded.events()[1].item() is Runtime(notice) else {
    fail("expected runtime notice")
  }
  assert_eq(notice.content(), "update")
  // The store stamps each appended event with the wall clock, and the stamp
  // survives a reload.
  assert_true(loaded.events()[0].unix_ms() > 0)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store rejects stale snapshots before appending" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  store.create(session)
  ignore(store.append(session, User(UserMessage("first"))))
  let _ = store.append(session, Runtime(RuntimeNotice("stale"))) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      let loaded = store.load(SessionId("s1"))
      assert_eq(loaded.events().length(), 1)
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("stale append was accepted")
}

///|
async test "store rejects divergent snapshots with the same sequence" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("first")),
  )
  let divergent = @agent_session.Session(
    SessionId("s1"),
    system_prompt="changed system",
    events=session.events(),
  )
  store.create(session)
  let _ = store.append(divergent, Runtime(RuntimeNotice("stale"))) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      let loaded = store.load(SessionId("s1"))
      assert_eq(loaded.system_prompt(), "system")
      assert_eq(loaded.events().length(), 1)
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("divergent same-sequence append was accepted")
}

///|
async test "store rejects mixed header and event log from interrupted rewrites" {
  let store = new_store()
  let original = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("old")),
  )
  let rewrite = @agent_session.Session(
    SessionId("s1"),
    system_prompt="rewritten system",
  ).append(User(UserMessage("new")))
  store.create(original)
  @fs.write_file(
    "\{store.root()}/sessions/s1/session.json",
    session_header_jsonl(rewrite),
    create_mode=CreateOrTruncate,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("fingerprint mismatch"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("mixed rewrite header and event log was accepted")
}

///|
async test "store rejects stale tails after interrupted prefix rewrites" {
  let store = new_store()
  let original = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(Runtime(RuntimeNotice("stale tail")))
  let rewrite = @agent_session.Session(SessionId("s1"), system_prompt="system")
  store.create(original)
  @fs.write_file(
    "\{store.root()}/sessions/s1/session.json",
    session_header_jsonl(rewrite, allow_event_log_ahead=false),
    create_mode=CreateOrTruncate,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("stale tail after replacement"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("stale tail from interrupted prefix rewrite was accepted")
}

///|
async test "store serializes concurrent appends from the same snapshot" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let results : Array[String] = []
  store.create(session)
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      try store.append(session, User(UserMessage("first"))) catch {
        error => {
          assert_true("\{error}".contains("stale session snapshot"))
          results.push("stale")
        }
      } noraise {
        _ => results.push("ok")
      }
    }
    group.spawn_bg() <| () => {
      try store.append(session, Runtime(RuntimeNotice("second"))) catch {
        error => {
          assert_true("\{error}".contains("stale session snapshot"))
          results.push("stale")
        }
      } noraise {
        _ => results.push("ok")
      }
    }
  }
  let mut ok = 0
  let mut stale = 0
  for result in results {
    if result == "ok" {
      ok += 1
    } else if result == "stale" {
      stale += 1
    }
  }
  let loaded = store.load(SessionId("s1"))
  assert_eq(ok, 1)
  assert_eq(stale, 1)
  assert_eq(loaded.events().length(), 1)
  assert_eq(loaded.last_sequence(), 1)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store rejects stale snapshots before compacting" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(Assistant(AssistantMessage("second")))
  store.create(session)
  ignore(store.append(session, Runtime(RuntimeNotice("new durable tail"))))
  let _ = store.compact(
    session,
    content="first two events",
    from_sequence=1,
    to_sequence=2,
  ) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      let loaded = store.load(SessionId("s1"))
      assert_eq(loaded.events().length(), 3)
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("stale compact was accepted")
}

///|
async test "store loads when the append-only log is ahead of the header" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let (_, event) = session.append_event(User(UserMessage("first")))
  store.create(session)
  @fs.write_file(
    "\{store.root()}/sessions/s1/events.jsonl",
    "\{event.to_json().stringify()}\n",
    create_mode=OpenOrCreate,
    append=true,
  )
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.system_prompt(), "system")
  assert_eq(loaded.events().length(), 1)
  assert_eq(loaded.last_sequence(), 1)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store loads an empty session when the event log is missing" {
  let store = new_store()
  store.create(Session(SessionId("s1"), system_prompt="system"))
  @fs.remove("\{store.root()}/sessions/s1/events.jsonl")
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 0)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store rejects missing event logs for non-empty sessions" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("hello")),
  )
  store.create(session)
  @fs.remove("\{store.root()}/sessions/s1/events.jsonl")
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("fingerprint mismatch"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("missing non-empty event log was accepted")
}

///|
async test "store propagates unreadable event logs instead of dropping history" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("hello")),
  )
  store.create(session)
  let event_log = "\{store.root()}/sessions/s1/events.jsonl"
  @fs.remove(event_log)
  @fs.mkdir(event_log)
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}" != "")
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("unreadable event log was silently accepted")
}

///|
async test "store rejects path-like session ids" {
  let store = new_store()
  let _ = store.exists(SessionId("../bad")) catch {
    error => {
      assert_true("\{error}".contains("path separators"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  fail("invalid session id accepted")
}

///|
async test "store compacts by appending a durable summary" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(Assistant(AssistantMessage("second")))
  store.create(session)
  let compacted = store.compact(
    session,
    content="first two events",
    from_sequence=1,
    to_sequence=2,
  )
  assert_eq(compacted.events().length(), 3)
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 3)
  guard loaded.events()[2].item() is Summary(summary) else {
    fail("expected summary")
  }
  assert_eq(summary.content(), "first two events")
  assert_eq(loaded.chat_messages().length(), 2)
  @fs.rmdir(store.root(), recursive=true)
}
