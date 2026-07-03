///|
async fn new_store() -> @store.SessionStore {
  let root = @fs.tmpdir(prefix="openseek-session-store-")
  SessionStore(root)
}

///|
fn session_file(store : @store.SessionStore, id : String) -> String {
  "\{store.root()}/sessions/\{id}/openseek_session-\{id}.jsonl"
}

///|
fn legacy_session_file(store : @store.SessionStore, id : String) -> String {
  "\{store.root()}/sessions/\{id}/openseek_session.jsonl"
}

///|
/// Lay down a session in the pre-suffix layout: create it normally, then move
/// the jsonl to the legacy fixed name.
async fn create_legacy_layout_session(
  store : @store.SessionStore,
  session : @agent_session.Session,
) -> Unit {
  store.create(session)
  let id = session.id().value()
  @fs.rename(session_file(store, id), legacy_session_file(store, id))
}

///|
async test "store creates and loads a session from one session file" {
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
async test "store writes the header record on the first line" {
  let store = new_store()
  store.create(Session(SessionId("s1"), system_prompt="system"))
  let text = @fs.read_file(session_file(store, "s1")).text()
  assert_eq(
    text, "{\"version\":1,\"id\":\"s1\",\"system_prompt\":\"system\"}\n",
  )
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 0)
  assert_eq(loaded.system_prompt(), "system")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store creates different sessions concurrently under one root" {
  let store = new_store()
  ignore(
    @async.all(
      [
        for id in ["a", "b", "c", "d"] => {
          () => store.create(Session(SessionId(id), system_prompt="system"))
        }
      ],
    ),
  )
  let ids = [ for id in store.list() => id.value() ]
  json_inspect(ids, content=["a", "b", "c", "d"])
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store creates different sessions concurrently under a missing root" {
  let parent = @fs.tmpdir(prefix="openseek-session-store-race-")
  let store : @store.SessionStore = SessionStore("\{parent}/missing-root")
  ignore(
    @async.all(
      [
        for id in ["a", "b", "c", "d", "e", "f", "g", "h"] => {
          () => store.create(Session(SessionId(id), system_prompt="system"))
        }
      ],
    ),
  )
  let ids = [ for id in store.list() => id.value() ]
  json_inspect(ids, content=["a", "b", "c", "d", "e", "f", "g", "h"])
  @fs.rmdir(parent, recursive=true)
}

///|
async test "store validates invalid ids before creating directories" {
  let parent = @fs.tmpdir(prefix="openseek-session-store-invalid-")
  let root = "\{parent}/missing-root"
  let store : @store.SessionStore = SessionStore(root)
  let _ = store.create(Session(SessionId("../bad"), system_prompt="system")) catch {
    error => {
      assert_true("\{error}".contains("path separators"))
      assert_true(!@fs.exists("\{root}/sessions"))
      @fs.rmdir(parent, recursive=true)
      return
    }
  }
  @fs.rmdir(parent, recursive=true)
  fail("invalid session id accepted")
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
  // A directory with no session file — e.g. an interrupted creation or an
  // incompatible layout — has no stamp to order by but must stay discoverable.
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
async test "latest skips a corrupt newest session in favor of a loadable one" {
  let store = new_store()
  store.create(Session(SessionId("valid"), system_prompt="system"))
  @async.sleep(50)
  store.create(Session(SessionId("corrupt"), system_prompt="system"))
  // The newest directory stats fine but cannot be loaded.
  @fs.write_file(
    session_file(store, "corrupt"),
    "not a header line\n",
    create_mode=CreateOrTruncate,
  )
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
async test "first append creates the session file with its header" {
  let store = new_store()
  // No create(): the CLI resumes-or-starts sessions whose first durable write
  // is an append. The header line and the first event must land together.
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let next = store.append(session, User(UserMessage("first")))
  assert_eq(next.events().length(), 1)
  let text = @fs.read_file(session_file(store, "s1")).text()
  assert_true(
    text.has_prefix(
      "{\"version\":1,\"id\":\"s1\",\"system_prompt\":\"system\"}\n",
    ),
  )
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.system_prompt(), "system")
  assert_eq(loaded.events().length(), 1)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "store serializes concurrent first appends from empty snapshots" {
  let store = new_store()
  // Two writers race to be the first durable write for the same id. The
  // exclusive lock serializes them; the loser sees the winner's file and gets
  // a stale-snapshot error instead of clobbering the first event.
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let results : Array[String] = []
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
  assert_eq(results.filter(r => r == "ok").length(), 1)
  assert_eq(results.filter(r => r == "stale").length(), 1)
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 1)
  assert_eq(loaded.last_sequence(), 1)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "chained appends on returned values persist every event" {
  // The common agent loop: each append's return value feeds the next call,
  // which is exactly the shape the fingerprint fast path accelerates.
  let store = new_store()
  let mut session = @agent_session.Session(
    SessionId("s1"),
    system_prompt="system",
  )
  store.create(session)
  for step in 0..<5 {
    session = store.append(session, Runtime(RuntimeNotice("step \{step}")))
  }
  assert_eq(session.last_sequence(), 5)
  let events = store.load(SessionId("s1")).events()
  assert_eq(events.length(), 5)
  for index in 0..<events.length() {
    let event = events[index]
    assert_eq(event.sequence(), index + 1)
    guard event.item() is Runtime(notice) else { fail("expected notice") }
    assert_eq(notice.content(), "step \{index}")
  }
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "another store instance's write defeats the fingerprint fast path" {
  // store_a syncs a snapshot, then store_b (another process, in effect)
  // appends. store_a's snapshot is physically the value it last synced, so
  // only the on-disk fingerprint reveals the divergence.
  let store_a = new_store()
  let store_b : @store.SessionStore = SessionStore(store_a.root())
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  store_a.create(session)
  let from_a = store_a.append(session, User(UserMessage("from a")))
  let loaded_by_b = store_b.load(SessionId("s1"))
  ignore(store_b.append(loaded_by_b, Runtime(RuntimeNotice("from b"))))
  let _ = store_a.append(from_a, Runtime(RuntimeNotice("stale from a"))) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      let loaded = store_a.load(SessionId("s1"))
      assert_eq(loaded.events().length(), 2)
      @fs.rmdir(store_a.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store_a.root(), recursive=true)
  fail("stale append past the fast path was accepted")
}

///|
async test "a same-size rewrite by another store is still detected" {
  let store_a = new_store()
  let store_b : @store.SessionStore = SessionStore(store_a.root())
  let session = @agent_session.Session(
    SessionId("s1"),
    system_prompt="prompt A",
  )
  store_a.create(session)
  // Same byte length, different content: the size component of the
  // fingerprint cannot see this rewrite — only its timestamps can (mtime,
  // plus ctime, which user space cannot forge). Filesystem mtimes need a
  // beat between writes to order reliably.
  @async.sleep(50)
  store_b.create(Session(SessionId("s1"), system_prompt="prompt B"))
  let _ = store_a.append(session, User(UserMessage("stale"))) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      assert_eq(store_a.load(SessionId("s1")).system_prompt(), "prompt B")
      @fs.rmdir(store_a.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store_a.root(), recursive=true)
  fail("same-size rewrite slipped past the fingerprint fast path")
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
async test "store rejects non-empty snapshots when the session file is missing" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("hello")),
  )
  store.create(session)
  @fs.remove(session_file(store, "s1"))
  let _ = store.append(session, Runtime(RuntimeNotice("more"))) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("append onto a missing session file was accepted")
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
async test "store fails load when the session file is missing" {
  let store = new_store()
  store.create(Session(SessionId("s1"), system_prompt="system"))
  @fs.remove(session_file(store, "s1"))
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}" != "")
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("missing session file was accepted")
}

///|
async test "store rejects a session file without a header record" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let (_, event) = session.append_event(User(UserMessage("first")))
  @fs.mkdir("\{store.root()}/sessions/s1", recursive=true)
  // A bare event log — the pre-header layout, or a file whose header line was
  // lost — must fail loudly rather than load with a fabricated identity.
  @fs.write_file(
    session_file(store, "s1"),
    "\{event.to_json().stringify()}\n",
    create_mode=CreateOrTruncate,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("does not start with a header record"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("header-less session file was accepted")
}

///|
async test "store rejects a malformed header line" {
  let store = new_store()
  @fs.mkdir("\{store.root()}/sessions/s1", recursive=true)
  @fs.write_file(
    session_file(store, "s1"),
    "not json at all\n",
    create_mode=CreateOrTruncate,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("does not start with a header line"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("malformed header line was accepted")
}

///|
async test "store rejects a header whose id does not match the directory" {
  let store = new_store()
  store.create(Session(SessionId("other"), system_prompt="system"))
  @fs.mkdir("\{store.root()}/sessions/s1", recursive=true)
  @fs.write_file(
    session_file(store, "s1"),
    @fs.read_file(session_file(store, "other")).text(),
    create_mode=CreateOrTruncate,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("session header id mismatch"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("mismatched header id was accepted")
}

///|
async test "load drops a torn trailing record without mutating the file" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("first")),
  )
  store.create(session)
  // A crash mid-append leaves a half-written last line. The uncommitted tail
  // is dropped so the session stays resumable, and load itself is read-only.
  @fs.write_file(
    session_file(store, "s1"),
    "{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"assi",
    create_mode=OpenOrCreate,
    append=true,
  )
  let text_before = @fs.read_file(session_file(store, "s1")).text()
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 1)
  assert_eq(loaded.last_sequence(), 1)
  assert_eq(@fs.read_file(session_file(store, "s1")).text(), text_before)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "load keeps a complete final record that lost only its newline" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let (_, event) = session.append_event(User(UserMessage("first")))
  store.create(session)
  // The append was torn exactly at the newline boundary: the record is whole.
  @fs.write_file(
    session_file(store, "s1"),
    event.to_json().stringify(),
    create_mode=OpenOrCreate,
    append=true,
  )
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 1)
  guard loaded.events()[0].item() is User(message) else {
    fail("expected the unterminated user event")
  }
  assert_eq(message.content(), "first")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "append repairs a torn tail before persisting the next event" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("first")),
  )
  store.create(session)
  @fs.write_file(
    session_file(store, "s1"),
    "{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"assi",
    create_mode=OpenOrCreate,
    append=true,
  )
  let resumed = store.load(SessionId("s1"))
  let next = store.append(resumed, Runtime(RuntimeNotice("recovered")))
  assert_eq(next.events().length(), 2)
  assert_eq(next.last_sequence(), 2)
  // The rewrite discarded the torn bytes and terminated every line.
  let text = @fs.read_file(session_file(store, "s1")).text()
  assert_true(text.has_suffix("\n"))
  assert_true(!text.contains("assi"))
  let reloaded = store.load(SessionId("s1"))
  assert_eq(reloaded.events().length(), 2)
  assert_eq(reloaded.last_sequence(), 2)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "append repairs and keeps a complete unterminated final event" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let (_, event) = session.append_event(User(UserMessage("first")))
  store.create(session)
  @fs.write_file(
    session_file(store, "s1"),
    event.to_json().stringify(),
    create_mode=OpenOrCreate,
    append=true,
  )
  let resumed = store.load(SessionId("s1"))
  assert_eq(resumed.events().length(), 1)
  let next = store.append(resumed, Runtime(RuntimeNotice("second")))
  assert_eq(next.last_sequence(), 2)
  let text = @fs.read_file(session_file(store, "s1")).text()
  assert_true(text.has_suffix("\n"))
  let reloaded = store.load(SessionId("s1"))
  assert_eq(reloaded.events().length(), 2)
  guard reloaded.events()[0].item() is User(message) else {
    fail("expected the recovered user event to survive the repair")
  }
  assert_eq(message.content(), "first")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "append rejects a stale snapshot against an unterminated durable event" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let (_, event) = session.append_event(User(UserMessage("first")))
  store.create(session)
  // Another writer committed an event; only its newline is missing. The
  // pre-commit empty snapshot is stale, and tail repair must not become a
  // path that discards that writer's data.
  @fs.write_file(
    session_file(store, "s1"),
    event.to_json().stringify(),
    create_mode=OpenOrCreate,
    append=true,
  )
  let _ = store.append(session, Runtime(RuntimeNotice("stale"))) catch {
    error => {
      assert_true("\{error}".contains("stale session snapshot"))
      let loaded = store.load(SessionId("s1"))
      assert_eq(loaded.events().length(), 1)
      guard loaded.events()[0].item() is User(message) else {
        fail("expected the durable user event to survive")
      }
      assert_eq(message.content(), "first")
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("stale append onto an unterminated durable event was accepted")
}

///|
async test "load tolerates unterminated tails in every torn shape" {
  let store = new_store()
  // Valid JSON that is not a valid event: torn exactly inside the payload in
  // a way that still balances braces.
  store.create(Session(SessionId("json"), system_prompt="system"))
  @fs.write_file(
    session_file(store, "json"),
    "{\"not\":\"an event\"}",
    create_mode=OpenOrCreate,
    append=true,
  )
  assert_eq(store.load(SessionId("json")).events().length(), 0)
  // Whitespace-only unterminated tail.
  let one_event = @agent_session.Session(
    SessionId("blank"),
    system_prompt="system",
  ).append(User(UserMessage("hello")))
  store.create(one_event)
  @fs.write_file(
    session_file(store, "blank"),
    "   ",
    create_mode=OpenOrCreate,
    append=true,
  )
  assert_eq(store.load(SessionId("blank")).events().length(), 1)
  // Torn garbage after zero events.
  store.create(Session(SessionId("zero"), system_prompt="system"))
  @fs.write_file(
    session_file(store, "zero"),
    "{\"seq",
    create_mode=OpenOrCreate,
    append=true,
  )
  assert_eq(store.load(SessionId("zero")).events().length(), 0)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "load keeps a header-only file that lost its newline" {
  let store = new_store()
  // `create` can never produce this (tmp+rename is atomic), but the tolerance
  // rule is uniform: in a zero-event file the header is the final record.
  @fs.mkdir("\{store.root()}/sessions/s1", recursive=true)
  @fs.write_file(
    session_file(store, "s1"),
    "{\"version\":1,\"id\":\"s1\",\"system_prompt\":\"system\"}",
    create_mode=CreateOrTruncate,
  )
  let loaded = store.load(SessionId("s1"))
  assert_eq(loaded.events().length(), 0)
  assert_eq(loaded.system_prompt(), "system")
  // The next append terminates the header line as it persists the event.
  ignore(store.append(loaded, User(UserMessage("first"))))
  let text = @fs.read_file(session_file(store, "s1")).text()
  assert_true(text.has_suffix("\n"))
  assert_eq(store.load(SessionId("s1")).events().length(), 1)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "compact repairs a torn tail before persisting the summary" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(Assistant(AssistantMessage("second")))
  store.create(session)
  @fs.write_file(
    session_file(store, "s1"),
    "{\"sequence\":3,\"ts\":0,\"item\":{\"kind\":\"runt",
    create_mode=OpenOrCreate,
    append=true,
  )
  let resumed = store.load(SessionId("s1"))
  let compacted = store.compact(
    resumed,
    content="first two events",
    from_sequence=1,
    to_sequence=2,
  )
  assert_eq(compacted.events().length(), 3)
  let text = @fs.read_file(session_file(store, "s1")).text()
  assert_true(text.has_suffix("\n"))
  assert_true(!text.contains("runt"))
  assert_eq(store.load(SessionId("s1")).events().length(), 3)
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "latest can resume a session whose newest write was torn" {
  let store = new_store()
  store.create(Session(SessionId("older"), system_prompt="system"))
  @async.sleep(50)
  let newest = @agent_session.Session(
    SessionId("newest"),
    system_prompt="system",
  ).append(User(UserMessage("hello")))
  store.create(newest)
  @fs.write_file(
    session_file(store, "newest"),
    "{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"assi",
    create_mode=OpenOrCreate,
    append=true,
  )
  guard store.latest() is Some(id) else { fail("expected a latest session") }
  assert_eq(id.value(), "newest")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "load still fails on corruption that is not a torn tail" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("first")),
  )
  store.create(session)
  // Terminated garbage is interior-style corruption, not an interrupted
  // append: something after the bad line committed a newline.
  @fs.write_file(
    session_file(store, "s1"),
    "not an event\n",
    create_mode=OpenOrCreate,
    append=true,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}" != "")
      // A bad line with valid lines after it fails the same way.
      let (_, event) = session.append_event(Runtime(RuntimeNotice("later")))
      @fs.write_file(
        session_file(store, "s1"),
        "\{event.to_json().stringify()}\n",
        create_mode=OpenOrCreate,
        append=true,
      )
      let _ = store.load(SessionId("s1")) catch {
        error => {
          assert_true("\{error}" != "")
          @fs.rmdir(store.root(), recursive=true)
          return
        }
      }
      @fs.rmdir(store.root(), recursive=true)
      fail("interior corruption was accepted")
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("terminated garbage line was accepted")
}

///|
async test "store propagates unreadable session files instead of dropping history" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage("hello")),
  )
  store.create(session)
  let path = session_file(store, "s1")
  @fs.remove(path)
  @fs.mkdir(path)
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}" != "")
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("unreadable session file was silently accepted")
}

///|
async test "store names an unsupported session file version on load" {
  let store = new_store()
  @fs.mkdir("\{store.root()}/sessions/s1", recursive=true)
  @fs.write_file(
    session_file(store, "s1"),
    "{\"version\":2,\"id\":\"s1\",\"system_prompt\":\"system\"}\n",
    create_mode=CreateOrTruncate,
  )
  let _ = store.load(SessionId("s1")) catch {
    error => {
      assert_true("\{error}".contains("unsupported session file version 2"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("version-2 session file was accepted")
}

///|
async test "store rejects session ids containing NUL" {
  let store = new_store()
  let _ = store.exists(SessionId("bad\u{0}id")) catch {
    error => {
      assert_true("\{error}".contains("NUL"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("NUL in session id accepted")
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
async test "store reads sessions written in the legacy fixed-name layout" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("old"), system_prompt="system").append(
    User(UserMessage("hello")),
  )
  create_legacy_layout_session(store, session)
  // A fresh store instance sees only the legacy file.
  let reader : @store.SessionStore = SessionStore(store.root())
  let loaded = reader.load(SessionId("old"))
  assert_eq(loaded.events().length(), 1)
  assert_eq(loaded.system_prompt(), "system")
  // Read-only surfaces resolve the legacy path without renaming anything.
  assert_eq(
    reader.session_file(SessionId("old")),
    legacy_session_file(store, "old"),
  )
  let listings = reader.listings()
  assert_eq(listings.length(), 1)
  assert_true(listings[0].last_active_unix_seconds() is Some(_))
  assert_eq(listings[0].first_prompt(), "hello")
  guard reader.latest() is Some(id) else { fail("expected a latest session") }
  assert_eq(id.value(), "old")
  assert_true(@fs.exists(legacy_session_file(store, "old")))
  assert_false(@fs.exists(session_file(store, "old")))
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "append migrates a legacy session file to the id-suffixed name" {
  let store = new_store()
  let session = @agent_session.Session(SessionId("old"), system_prompt="system").append(
    User(UserMessage("hello")),
  )
  create_legacy_layout_session(store, session)
  let writer : @store.SessionStore = SessionStore(store.root())
  let resumed = writer.load(SessionId("old"))
  let next = writer.append(resumed, Runtime(RuntimeNotice("migrated")))
  assert_eq(next.events().length(), 2)
  assert_false(@fs.exists(legacy_session_file(store, "old")))
  assert_true(@fs.exists(session_file(store, "old")))
  let reloaded = writer.load(SessionId("old"))
  assert_eq(reloaded.events().length(), 2)
  guard reloaded.events()[0].item() is User(message) else {
    fail("expected the pre-migration event to survive")
  }
  assert_eq(message.content(), "hello")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "create replaces a legacy session file instead of leaving both layouts" {
  let store = new_store()
  create_legacy_layout_session(
    store,
    Session(SessionId("old"), system_prompt="system"),
  )
  let writer : @store.SessionStore = SessionStore(store.root())
  writer.create(Session(SessionId("old"), system_prompt="rewritten"))
  assert_false(@fs.exists(legacy_session_file(store, "old")))
  assert_eq(writer.load(SessionId("old")).system_prompt(), "rewritten")
  @fs.rmdir(store.root(), recursive=true)
}

///|
async test "writes fail loudly when both session file layouts exist" {
  let store = new_store()
  let session = @agent_session.Session(
    SessionId("both"),
    system_prompt="system",
  )
  store.create(session)
  // A second file in the other layout is ambiguous corruption: refusing to
  // write beats guessing which file is the session.
  @fs.write_file(
    legacy_session_file(store, "both"),
    @fs.read_file(session_file(store, "both")).text(),
    create_mode=CreateOrTruncate,
  )
  let _ = store.append(session, User(UserMessage("boom"))) catch {
    error => {
      assert_true("\{error}".contains("both session file layouts"))
      @fs.rmdir(store.root(), recursive=true)
      return
    }
  }
  @fs.rmdir(store.root(), recursive=true)
  fail("ambiguous double-layout store accepted a write")
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
