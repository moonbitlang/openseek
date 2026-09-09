///|
/// A recursive marker catalog root at `<base>/<label>`, scanning
/// `<base>/<label>/sessions` — the shape every catalog fixture here uses.
fn marker_root(base : String, label : String) -> SessionRoot {
  {
    path: "\{base}/\{label}",
    scan_path: "\{base}/\{label}/sessions",
    label,
    recursive: true,
    is_marker: true,
  }
}

///|
/// Environment-dependent (needs a default route), so absence is accepted; but
/// whatever it returns must be a remotely-reachable IPv4 — never a loopback or
/// unspecified address, which is the whole point of filtering them out.
async test "local_lan_ip yields a routable IPv4 or None" {
  match local_lan_ip() {
    None => ()
    Some(ip) => {
      assert_true(!ip.is_empty())
      assert_true(ip.contains("."))
      assert_true(!ip.has_prefix("127."))
      assert_true(ip != "0.0.0.0")
    }
  }
}

///|
test "percent_decode passes plain segments through" {
  inspect(
    percent_decode("tui-20260610-124146-251"),
    content="tui-20260610-124146-251",
  )
}

///|
test "percent_decode resolves ASCII escapes" {
  inspect(percent_decode("with%20space"), content="with space")
  inspect(percent_decode("100%25"), content="100%")
  inspect(percent_decode("a%3Fb%23c"), content="a?b#c")
}

///|
test "percent_decode handles lowercase hex and UTF-8 byte sequences" {
  inspect(percent_decode("a%2fb"), content="a/b")
  inspect(percent_decode("%E4%B8%AD"), content="中")
}

///|
test "percent_decode leaves malformed escapes verbatim" {
  inspect(percent_decode("%zz"), content="%zz")
  inspect(percent_decode("tail%2"), content="tail%2")
  inspect(percent_decode("bare%"), content="bare%")
}

///|
test "module_root_from_exe recovers the checkout from a moon build path" {
  @debug.debug_inspect(
    module_root_from_exe(
      "/Users/x/git/openseek/_build/native/release/build/bobzhang/inspect/inspect.exe",
    ),
    content=(
      #|Some("/Users/x/git/openseek")
    ),
  )
  // moon run from a sibling directory passes a relative exe path.
  @debug.debug_inspect(
    module_root_from_exe(
      "../openseek/_build/native/release/build/bobzhang/inspect/inspect.exe",
    ),
    content=(
      #|Some("../openseek")
    ),
  )
  // Run from the checkout root itself, the relative path has no prefix.
  @debug.debug_inspect(
    module_root_from_exe(
      "_build/native/release/build/bobzhang/inspect/inspect.exe",
    ),
    content=(
      #|Some(".")
    ),
  )
  // An installed binary outside any moon build tree derives nothing.
  @debug.debug_inspect(
    module_root_from_exe("/usr/local/bin/inspect"),
    content=(
      #|None
    ),
  )
}

///|
test "asset candidates search cwd first, then the derived checkout" {
  @debug.debug_inspect(
    shell_candidates("web", Some("/repo")),
    content=(
      #|["web/index.html", "/repo/web/index.html"]
    ),
  )
  @debug.debug_inspect(
    shell_candidates("custom", None),
    content=(
      #|["custom/index.html"]
    ),
  )
  @debug.debug_inspect(
    bundle_candidates("", "web", Some("/repo")),
    content=(
      #|[
      #|  "",
      #|  "web/viz_app.js",
      #|  "_build/js/release/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|  "_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|  "/repo/web/viz_app.js",
      #|  "/repo/_build/js/release/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|  "/repo/_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|]
    ),
  )
  // An explicit --bundle stays the highest-priority candidate.
  @debug.debug_inspect(
    bundle_candidates("/x/app.js", "web", None),
    content=(
      #|[
      #|  "/x/app.js",
      #|  "web/viz_app.js",
      #|  "_build/js/release/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|  "_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|]
    ),
  )
}

///|
test "valid_session_id mirrors the store's id rules" {
  inspect(valid_session_id("tui-20260610-124146-251"), content="true")
  inspect(valid_session_id("with space"), content="true")
  inspect(valid_session_id(""), content="false")
  inspect(valid_session_id("."), content="false")
  inspect(valid_session_id(".."), content="false")
  inspect(valid_session_id("a/b"), content="false")
  inspect(valid_session_id("a\\b"), content="false")
}

///|
test "explicit --session-root drops the default cwd scan" {
  // Default invocation keeps the `.` scan so nearby stores are discovered.
  let default_run = cli_command().parse(argv=[], env=Map([]))
  @debug.debug_inspect(
    effective_search_dirs(default_run),
    content=(
      #|["."]
    ),
  )
  // An explicit root means "serve this", not "this plus wherever I'm standing".
  let flag_root = cli_command().parse(
    argv=["--session-root", "/srv/app/.openseek"],
    env=Map([]),
  )
  @debug.debug_inspect(effective_search_dirs(flag_root), content="[]")
  // An explicit --search-dir always wins: both flags means root plus scans.
  let both = cli_command().parse(
    argv=["--session-root", "/srv/app/.openseek", "--search-dir", "/srv/lib"],
    env=Map([]),
  )
  @debug.debug_inspect(
    effective_search_dirs(both),
    content=(
      #|["/srv/lib"]
    ),
  )
}

///|
async test "discover_session_roots scans recursively and skips heavy dirs" {
  @vfs.with_tmpdir(prefix="openseek-viz-scan-", root => {
    @fs.mkdir("\{root}/app/.openseek/sessions", recursive=true)
    @fs.mkdir("\{root}/packages/lib/.openseek/sessions", recursive=true)
    @fs.mkdir("\{root}/.git/ignored/.openseek/sessions", recursive=true)
    @fs.mkdir("\{root}/node_modules/ignored/.openseek/sessions", recursive=true)
    @fs.mkdir("\{root}/.mooncakes/ignored/.openseek/sessions", recursive=true)
    @fs.mkdir("\{root}/_build/ignored/.openseek/sessions", recursive=true)
    let roots = discover_session_roots([root], ".openseek").map(source => {
      source.path.replace_all(old=root, new="<root>")
    })
    @debug.debug_inspect(
      roots,
      content=(
        #|["<root>/app/.openseek", "<root>/packages/lib/.openseek"]
      ),
    )
  })
}

///|
async test "discover_session_roots supports a custom root marker" {
  @vfs.with_tmpdir(prefix="openseek-viz-openroot-", root => {
    @fs.mkdir("\{root}/app/.openroot/sessions", recursive=true)
    @fs.mkdir("\{root}/app/.openseek/sessions", recursive=true)
    let roots = discover_session_roots([root], ".openroot").map(source => {
      source.path.replace_all(old=root, new="<root>")
    })
    @debug.debug_inspect(
      roots,
      content=(
        #|["<root>/app/.openroot"]
      ),
    )
  })
}

///|
async test "session_catalog scans a container session root for nested stores" {
  @vfs.with_tmpdir(prefix="openseek-viz-nested-", root => {
    // A directory of best-of-N run workspaces, each with its own nested store.
    @fs.mkdir("\{root}/A-1/.openseek/sessions/run", recursive=true)
    @fs.mkdir("\{root}/B-1/.openseek/sessions/run", recursive=true)
    let catalog = session_catalog(root, [], ".openseek")
    let paths = catalog.roots.map(r => {
      r.path.replace_all(old=root, new="<root>")
    })
    paths.sort()
    // The empty container itself is not announced; its nested stores are.
    @debug.debug_inspect(
      paths,
      content=(
        #|["<root>/A-1/.openseek", "<root>/B-1/.openseek"]
      ),
    )
  })
}

///|
async test "session_catalog serves a direct store named like the root marker" {
  @vfs.with_tmpdir(prefix="openseek-viz-direct-", root => {
    @fs.mkdir("\{root}/.openseek/sessions/run", recursive=true)
    let catalog = session_catalog("\{root}/.openseek", [], ".openseek")
    let paths = catalog.roots.map(r => {
      r.path.replace_all(old=root, new="<root>")
    })
    @debug.debug_inspect(
      paths,
      content=(
        #|["<root>/.openseek"]
      ),
    )
  })
}

///|
async test "session_catalog serves a non-marker direct store without duplicates" {
  @vfs.with_tmpdir(prefix="openseek-viz-non-marker-store-", root => {
    let store = @store.SessionStore("\{root}/store")
    store.create(Session(SessionId("only"), system_prompt=""))
    let catalog = session_catalog("\{root}/store", [], ".openseek")
    let rows = catalog.rows()
    guard rows is [row] else { fail("expected one direct-store row") }
    inspect(row.id, content="only")
    inspect(row.root, content="\{root}/store")
  })
}

///|
async test "session listing uses jsonl files and ignores junk entries" {
  @vfs.with_tmpdir(prefix="openseek-viz-flat-jsonl-", root => {
    let source_store = @store.SessionStore("\{root}/source/.openseek")
    source_store.create(Session(SessionId("flat-a"), system_prompt=""))
    source_store.create(
      @agent_session.Session(SessionId("flat-b"), system_prompt="").append(
        User(UserMessage("copied prompt")),
      ),
    )
    let sessions = "\{root}/.openseek/sessions"
    @fs.mkdir(sessions, recursive=true)
    @fs.write_file(
      "\{sessions}/openseek_session-flat-a.jsonl",
      @fs.read_file(source_store.session_file(SessionId("flat-a"))).text(),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{sessions}/openseek_session-flat-b.jsonl",
      @fs.read_file(source_store.session_file(SessionId("flat-b"))).text(),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{sessions}/.DS_Store",
      "not a session",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{sessions}/tui-20260705-131715-289", recursive=true)
    let catalog = session_catalog("\{root}/.openseek", [], ".openseek")
    let reply = session_list_reply(catalog)
    let text = reply.body
    assert_true(text.contains("\"id\":\"flat-a\""))
    assert_true(text.contains("\"id\":\"flat-b\""))
    assert_true(text.contains("\"first_prompt\":\"copied prompt\""))
    assert_true(!text.contains(".DS_Store"))
    assert_true(!text.contains("tui-20260705-131715-289"))
    let load = session_path_reply(catalog, "flat-a")
    inspect(load.code, content="200")
    guard @json.parse(load.body) is Object(fields) else {
      fail("expected envelope JSON")
    }
    guard fields.get("events") is Some(String(events)) else {
      fail("expected events text")
    }
    assert_true(events.contains("\"id\":\"flat-a\""))
  })
}

///|
async test "session_catalog serves a direct directory of copied jsonl files" {
  @vfs.with_tmpdir(prefix="openseek-viz-jsonl-dir-", root => {
    let source_store = @store.SessionStore("\{root}/source/.openseek")
    source_store.create(Session(SessionId("copied"), system_prompt=""))
    let copied_dir = "\{root}/copied"
    @fs.mkdir(copied_dir, recursive=true)
    @fs.write_file(
      "\{copied_dir}/openseek_session-copied.jsonl",
      @fs.read_file(source_store.session_file(SessionId("copied"))).text(),
      create_mode=CreateOrTruncate,
    )
    let catalog = session_catalog(copied_dir, [], ".openseek")
    let reply = session_list_reply(catalog)
    let text = reply.body
    assert_true(text.contains("\"id\":\"copied\""))
    assert_true(text.contains("\"is_marker\":false"))
    let rows = catalog.rows()
    guard rows is [row] else { fail("expected one copied row") }
    let load = session_path_reply(catalog, row.key)
    inspect(load.code, content="200")
  })
}

///|
async test "session_catalog serves marker-named copied jsonl directories" {
  @vfs.with_tmpdir(prefix="openseek-viz-marker-jsonl-", root => {
    let source_store = @store.SessionStore("\{root}/source/.openseek")
    source_store.create(Session(SessionId("marker-copy"), system_prompt=""))
    let copied_dir = "\{root}/.openseek"
    @fs.mkdir(copied_dir, recursive=true)
    @fs.write_file(
      "\{copied_dir}/openseek_session-marker-copy.jsonl",
      @fs.read_file(source_store.session_file(SessionId("marker-copy"))).text(),
      create_mode=CreateOrTruncate,
    )
    let catalog = session_catalog(copied_dir, [], ".openseek")
    let reply = session_list_reply(catalog)
    let text = reply.body
    assert_true(text.contains("\"id\":\"marker-copy\""))
  })
}

///|
async test "session catalog lookup supports stable and legacy keys" {
  @vfs.with_tmpdir(prefix="openseek-viz-lookup-", root => {
    let app_store = @store.SessionStore("\{root}/app/.openseek")
    let lib_store = @store.SessionStore("\{root}/lib/.openseek")
    app_store.create(Session(SessionId("legacy"), system_prompt=""))
    lib_store.create(Session(SessionId("demo"), system_prompt=""))
    let catalog : SessionCatalog = {
      roots: [
        marker_root(root, "app/.openseek"),
        marker_root(root, "lib/.openseek"),
      ],
    }
    let rows = catalog.rows()
    let mut demo_key = ""
    for row in rows {
      if row.id == "demo" {
        demo_key = row.key
      }
    }
    guard demo_key != "" else { fail("expected demo key") }
    guard catalog.lookup(demo_key) is Some(row) else {
      fail("expected stable key lookup")
    }
    inspect(row.root, content="\{root}/lib/.openseek")
    inspect(row.id, content="demo")
    app_store.create(Session(SessionId("newer"), system_prompt=""))
    guard catalog.lookup(demo_key) is Some(row) else {
      fail("expected stable key lookup after file addition")
    }
    inspect(row.root, content="\{root}/lib/.openseek")
    inspect(row.id, content="demo")
    guard catalog.lookup("legacy") is Some(row) else {
      fail("expected legacy lookup")
    }
    inspect(row.root, content="\{root}/app/.openseek")
    inspect(row.id, content="legacy")
    guard catalog.lookup("9|missing") is None else {
      fail("unexpected missing root lookup")
    }
  })
}

///|
async test "session_list_reply includes root metadata and stable keys" {
  @vfs.with_tmpdir(prefix="openseek-viz-list-", root => {
    let app_store = @store.SessionStore("\{root}/app/.openseek")
    let lib_store = @store.SessionStore("\{root}/lib/.openseek")
    app_store.create(Session(SessionId("same"), system_prompt="a"))
    lib_store.create(Session(SessionId("same"), system_prompt="b"))
    let catalog : SessionCatalog = {
      roots: [
        marker_root(root, "app/.openseek"),
        marker_root(root, "lib/.openseek"),
      ],
    }
    let reply = session_list_reply(catalog)
    let text = reply.body
    let rows = catalog.rows()
    assert_eq(rows.length(), 2)
    assert_true(rows[0].key.has_prefix("file-"))
    assert_true(rows[1].key.has_prefix("file-"))
    assert_true(rows[0].key != rows[1].key)
    assert_true(text.contains("\"root_label\":\"app/.openseek\""))
    assert_true(text.contains("\"root_label\":\"lib/.openseek\""))
    // The marker flag rides along so the sidebar can group by directory.
    assert_true(text.contains("\"is_marker\":true"))
  })
}

///|
async test "raw session file route decodes the file segment like the key" {
  @vfs.with_tmpdir(prefix="openseek-viz-raw-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    // An id with a space forces percent-encoding in both URL segments.
    let session = @agent_session.Session(SessionId("run 1"), system_prompt="").append(
      User(UserMessage("hi")),
    )
    store.create(session)
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let reply = session_path_reply(
      catalog, "run%201/openseek_session-run%201.jsonl",
    )
    inspect(reply.code, content="200")
    assert_true(reply.body.contains("\"id\":\"run 1\""))
  })
}

///|
async test "session_envelope_reply includes event log byte size" {
  @vfs.with_tmpdir(prefix="openseek-viz-envelope-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    let session = @agent_session.Session(SessionId("demo"), system_prompt="").append(
      User(UserMessage("hi")),
    )
    store.create(session)
    let reply = session_envelope_reply(store.session_file(SessionId("demo")))
    guard @json.parse(reply.body) is Object(fields) else {
      fail("expected JSON object")
    }
    guard fields.get("events") is Some(String(events_text)) else {
      fail("expected events")
    }
    guard fields.get("events_bytes") is Some(Number(size, ..)) else {
      fail("expected events_bytes")
    }
    inspect(size.to_int(), content="\{events_text.length()}")
    assert_true(size.to_int() > 0)
  })
}
