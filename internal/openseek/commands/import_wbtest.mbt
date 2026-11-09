///|
/// One exported session: a header naming `id`, then `events`.
fn export_log(
  id : String,
  events : Array[@agent_session.SessionEvent],
) -> String {
  let header : @log.SessionFileHeader = {
    id,
    system_prompt: "Working directory: /old/workspace",
  }
  let lines = [ToJson::to_json(header).stringify()]
  for event in events {
    lines.push(ToJson::to_json(event).stringify())
  }
  lines.join("\n") + "\n"
}

///|
/// A conversation `original` with one subrun, exported from `root`.
fn export_dataset(
  root~ : String = "/old/workspace/.openseek",
  child~ : String = "original-sr-1",
  parent_events? : String,
) -> String {
  let events = @agent_session.Session(
      SessionId("original"),
      system_prompt="unused",
    )
    .append(User(UserMessage(Content([Text("Hello from imported history")]))))
    .append(Terminal(Finished("done")))
    .events()
    .to_array()
  @viz_export.StandaloneExport("", "").json([
    Session(
      key="session-0",
      id="original",
      root~,
      root_label="old",
      is_marker=true,
      last_active=None,
      first_prompt="Imported test",
      events=parent_events.unwrap_or(export_log("original", events)),
    ),
    Session(
      key="session-1",
      id=child,
      root~,
      root_label="old",
      is_marker=true,
      last_active=None,
      first_prompt="",
      events=export_log(child, events),
    ),
  ])
}

///|
async fn import_matches(
  root : String,
  text : String,
  origin~ : String = "local",
) -> @argparse.Matches {
  let source = "\{root}/export.json"
  @fs.write_file(source, text, create_mode=CreateOrTruncate)
  @testkit.sessions_leaf_matches(
    sub="import",
    argv=[
      "--source", source, "--origin", origin, "--as", "copy", "--session-root", root,
    ],
    env=Map([]),
  )
}

///|
async test "session import rebinds the conversation prompt and renames subruns" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-import-", root => {
    sessions_import(import_matches(root, export_dataset()))
    let store = @store.SessionStore(root)
    let copy = store.load(SessionId("copy"))
    assert_eq(copy.last_sequence(), 2)
    // The exported prompt named the source's workspace; the imported one is
    // built for this store, with the new session's scratch directory.
    let scratch = Json::Json(store.scratch_dir(SessionId("copy"))).stringify()
    assert_true(copy.system_prompt().contains(scratch))
    assert_false(copy.system_prompt().contains("/old/workspace"))
    assert_eq(store.title(SessionId("copy")), Some("Imported test"))
    // Subruns keep their own prompts under the new conversation's id.
    let child = store.load(SessionId("copy-sr-1"))
    assert_eq(child.system_prompt(), "Working directory: /old/workspace")
    assert_eq(child.last_sequence(), 2)
    assert_eq(store.list().map(id => id.value()), ["copy", "copy-sr-1"])
  })
}

///|
async test "session import accepts exports only from the importer's origin" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-import-origin-", root => {
    let cases = [
      ("local", export_dataset(root="cloud://sessions/original"), "Cloud chats"),
      ("cloud", export_dataset(), "local workspace"),
    ]
    for case in cases {
      let (origin, text, expected) = case
      let message = try {
        sessions_import(import_matches(root, text, origin~))
        ""
      } catch {
        error => "\{error}"
      }
      assert_true(message.contains(expected))
    }
    sessions_import(
      import_matches(
        root,
        export_dataset(root="cloud://sessions/original"),
        origin="cloud",
      ),
    )
    assert_true(@store.SessionStore(root).exists(SessionId("copy")))
  })
}

///|
async test "session import refuses invalid exports without writing" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-import-invalid-", root => {
    let gap = "{\"version\":1,\"id\":\"original\",\"system_prompt\":\"\"}\n" +
      "{\"sequence\":2,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"text\":\"x\"}}}\n"
    for
      text in [
        "not json",
        "{}",
        "[]",
        export_dataset(
          parent_events="{\"version\":2,\"id\":\"original\",\"system_prompt\":\"\"}\n",
        ),
        export_dataset(
          parent_events="{\"version\":1,\"id\":\"original\",\"system_prompt\":\"\"}\n{partial",
        ),
        export_dataset(
          parent_events="{\"version\":1,\"id\":\"other\",\"system_prompt\":\"\"}\n",
        ),
        export_dataset(parent_events=gap),
        export_dataset(child="original-sr-1-sr-2"),
        export_dataset(child="original-sr-1/../../elsewhere"),
        export_dataset(child="unrelated"),
      ] {
      let refused = try {
        sessions_import(import_matches(root, text))
        false
      } catch {
        _ => true
      }
      assert_true(refused)
      assert_eq(@store.SessionStore(root).list(), [])
    }
  })
}

///|
async test "session import never replaces an existing session" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-import-existing-", root => {
    let store = @store.SessionStore(root)
    store.create(Session(SessionId("copy-sr-1"), system_prompt="kept"))
    let refused = try {
      sessions_import(import_matches(root, export_dataset()))
      false
    } catch {
      error => "\{error}".contains("already exists")
    }
    assert_true(refused)
    assert_eq(store.load(SessionId("copy-sr-1")).system_prompt(), "kept")
    assert_false(store.exists(SessionId("copy")))
  })
}
