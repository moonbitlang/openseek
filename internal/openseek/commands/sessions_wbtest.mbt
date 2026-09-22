///|
test "session listing rows are tab-separated and survive odd prompts" {
  assert_eq(
    compact_prompt_label("  fix the \n\t streaming   bug  "),
    "fix the streaming bug",
  )
  assert_eq(compact_prompt_label(""), "-")
  // Control characters cannot smuggle escape sequences into the listing:
  // ESC, BEL, and the C1 CSI all vanish while printable text survives.
  assert_eq(
    compact_prompt_label("\u{1b}[31mred\u{1b}]0;title\u{7}\u{9b}31m text"),
    "[31mred]0;title31m text",
  )
  let long = String::make(100, 'x')
  let label = compact_prompt_label(long)
  assert_true(label.has_suffix("…"))
  // 2026-06-10T03:14:07Z renders at minute precision.
  assert_eq(format_utc_minute(1_781_061_247), "2026-06-10 03:14")
}

///|
async test "session commands reject empty session root" {
  let parsed = @testkit.sessions_leaf_matches(
    sub="list",
    argv=["--session-root", ""],
    env=Map([]),
  )
  let _ = sessions_list(parsed) catch {
    error => {
      assert_true("\{error}".contains("--session-root"))
      return
    }
  }
  fail("empty session root accepted")
}

///|
async test "session list command does not require deepseek setup" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-list-", root => {
    let store = @store.SessionStore(root)
    store.create(Session(SessionId("b"), system_prompt="system"))
    store.create(Session(SessionId("a"), system_prompt="system"))
    let parsed = @testkit.sessions_leaf_matches(
      sub="list",
      argv=["--session-root", root],
      env=Map([]),
    )
    // Prints the listing and succeeds with no DeepSeek setup.
    sessions_list(parsed)
  })
}

///|
test "session list format defaults to text and rejects unknown values" {
  let default_format = @testkit.sessions_leaf_matches(
    sub="list",
    argv=[],
    env=Map([]),
  )
  assert_true(session_list_format(default_format) is Text)
  let json_format = @testkit.sessions_leaf_matches(
    sub="list",
    argv=["--format", "json"],
    env=Map([]),
  )
  assert_true(session_list_format(json_format) is Json)
  let bogus = @testkit.sessions_leaf_matches(
    sub="list",
    argv=["--format", "yaml"],
    env=Map([]),
  )
  let _ = session_list_format(bogus) catch {
    error => {
      assert_true("\{error}".contains("--format must be text or json"))
      return
    }
  }
  fail("unknown format accepted")
}

///|
async test "session list json reports titles newest first with husks last" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-list-json-", root => {
    let store = @store.SessionStore(root)
    let older : @agent_session.Session = Session(
      SessionId("older"),
      system_prompt="system",
    )
    store.create(
      older.append(
        User(UserMessage(Content([Text("  first question\nwith detail  ")]))),
      ),
    )
    store.set_title(SessionId("older"), "Renamed conversation")
    let newer : @agent_session.Session = Session(
      SessionId("newer"),
      system_prompt="system",
    )
    store.create(newer)
    // A directory with no session files at all still appears — last, with no
    // timestamp — matching the human-readable listing's behavior.
    @fs.mkdir("\{root}/sessions/husk", recursive=true)
    guard session_list_json(store) is Array(entries) else {
      fail("expected a JSON array")
    }
    assert_eq(entries.length(), 3)
    guard entries[0] is Object(newest) &&
      entries[1] is Object(oldest) &&
      entries[2] is Object(husk) else {
      fail("expected JSON objects")
    }
    assert_true(newest.get("id") is Some(String("newer")))
    assert_true(newest.get("title") is Some(String("")))
    assert_true(oldest.get("id") is Some(String("older")))
    assert_true(oldest.get("title") is Some(String("Renamed conversation")))
    guard store.listings().iter().find_first(row => row.id().value() == "older")
      is Some(older_listing) else {
      fail("expected older listing")
    }
    assert_true(
      format_session_listing(older_listing).has_suffix("\tRenamed conversation"),
    )
    guard oldest.get("updated_at_ms") is Some(Number(stamp, ..)) else {
      fail("expected updated_at_ms")
    }
    assert_true(stamp > 0)
    assert_true(husk.get("id") is Some(String("husk")))
    assert_true(husk.get("updated_at_ms") is Some(Null))
  })
}

///|
test "session title keeps the untruncated first line" {
  assert_eq(session_title("  first line\nsecond line  "), "first line")
  let long_line = "x".repeat(256)
  let title = session_title(long_line)
  assert_eq(title.char_length(), 256)
  assert_eq(title, long_line)
}

///|
test "mtime to unix millis preserves subsecond precision" {
  assert_eq(mtime_to_unix_millis(42L, 987654321), 42987L)
  assert_eq(mtime_to_unix_millis(42L, 999999), 42000L)
}

///|
async test "session compact command appends summary without api key" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-compact-", root => {
    let store = @store.SessionStore(root)
    let session = @agent_session.Session(
        SessionId("cli-test"),
        system_prompt="system",
      )
      .append(User(UserMessage(Content([Text("hello")]))))
      .append(Assistant(AssistantMessage("answer")))
    store.create(session)
    let summary_path = "\{root}/summary.txt"
    @fs.write_file(
      summary_path,
      "summarized turn",
      create_mode=CreateOrTruncate,
    )
    let parsed = @testkit.sessions_leaf_matches(
      sub="compact",
      argv=[
        "cli-test", "--session-root", root, "--file", summary_path, "--from", "1",
        "--to", "2",
      ],
      env=Map([]),
    )
    sessions_compact(parsed)
    let loaded = store.load(SessionId("cli-test"))
    assert_eq(loaded.events().length(), 3)
    guard loaded.events()[2].item() is Summary(summary) else {
      fail("expected summary")
    }
    assert_eq(summary.content(), "summarized turn")
  })
}

///|
async test "session compact file resolves relative to workspace root" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-compact-workspace-", workspace => {
    let session_root = "\{workspace}/.openseek"
    let store = @store.SessionStore(session_root)
    let session = @agent_session.Session(
        SessionId("cli-test"),
        system_prompt="system",
      )
      .append(User(UserMessage(Content([Text("hello")]))))
      .append(Assistant(AssistantMessage("answer")))
    store.create(session)
    @fs.write_file(
      "\{workspace}/summary.txt",
      "workspace summary",
      create_mode=CreateOrTruncate,
    )
    let parsed = @testkit.sessions_leaf_matches(
      sub="compact",
      argv=[
        "cli-test", "--dir", workspace, "--file", "summary.txt", "--from", "1", "--to",
        "2",
      ],
      env=Map([]),
    )
    sessions_compact(parsed)
    let loaded = store.load(SessionId("cli-test"))
    guard loaded.events()[2].item() is Summary(summary) else {
      fail("expected summary")
    }
    assert_eq(summary.content(), "workspace summary")
  })
}

///|
async test "session compaction rejects missing summary file" {
  let parsed = @testkit.sessions_leaf_matches(
    sub="compact",
    argv=["cli-test", "--from", "1", "--to", "2"],
    env=Map([]),
  )
  let _ = sessions_compact(parsed) catch {
    error => {
      assert_true("\{error}".contains("--file"))
      return
    }
  }
  fail("partial session compaction accepted")
}
