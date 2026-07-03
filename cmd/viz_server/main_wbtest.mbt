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
      "/Users/x/git/openseek/_build/native/release/build/cmd/viz_server/viz_server.exe",
    ),
    content=(
      #|Some("/Users/x/git/openseek")
    ),
  )
  // moon run from a sibling directory passes a relative exe path.
  @debug.debug_inspect(
    module_root_from_exe(
      "../openseek/_build/native/release/build/cmd/viz_server/viz_server.exe",
    ),
    content=(
      #|Some("../openseek")
    ),
  )
  // Run from the checkout root itself, the relative path has no prefix.
  @debug.debug_inspect(
    module_root_from_exe(
      "_build/native/release/build/cmd/viz_server/viz_server.exe",
    ),
    content=(
      #|Some(".")
    ),
  )
  // An installed binary outside any moon build tree derives nothing.
  @debug.debug_inspect(
    module_root_from_exe("/usr/local/bin/viz_server"),
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
      #|  "_build/js/release/build/cmd/viz_app/viz_app.js",
      #|  "_build/js/debug/build/cmd/viz_app/viz_app.js",
      #|  "/repo/web/viz_app.js",
      #|  "/repo/_build/js/release/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|  "/repo/_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
      #|  "/repo/_build/js/release/build/cmd/viz_app/viz_app.js",
      #|  "/repo/_build/js/debug/build/cmd/viz_app/viz_app.js",
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
      #|  "_build/js/release/build/cmd/viz_app/viz_app.js",
      #|  "_build/js/debug/build/cmd/viz_app/viz_app.js",
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
  let default_run = cli_command().parse(argv=[], env={})
  @debug.debug_inspect(
    effective_search_dirs(default_run),
    content=(
      #|["."]
    ),
  )
  // An explicit root means "serve this", not "this plus wherever I'm standing".
  let flag_root = cli_command().parse(
    argv=["--session-root", "/srv/app/.openseek"],
    env={},
  )
  @debug.debug_inspect(effective_search_dirs(flag_root), content="[]")
  // The env var counts as explicit too.
  let env_root = cli_command().parse(argv=[], env={
    "OPENSEEK_SESSION_ROOT": "/srv/app/.openseek",
  })
  @debug.debug_inspect(effective_search_dirs(env_root), content="[]")
  // An explicit --search-dir always wins: both flags means root plus scans.
  let both = cli_command().parse(
    argv=["--session-root", "/srv/app/.openseek", "--search-dir", "/srv/lib"],
    env={},
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
    let roots = discover_session_roots([root], ".openseek").map(path => {
      path.replace_all(old=root, new="<root>")
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
    let roots = discover_session_roots([root], ".openroot").map(path => {
      path.replace_all(old=root, new="<root>")
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
test "session catalog lookup supports composite and legacy keys" {
  let catalog : SessionCatalog = {
    roots: [
      {
        key: "0",
        path: "app/.openseek",
        label: "app/.openseek",
        is_marker: true,
        store: @store.SessionStore("app/.openseek"),
      },
      {
        key: "1",
        path: "lib/.openseek",
        label: "lib/.openseek",
        is_marker: true,
        store: @store.SessionStore("lib/.openseek"),
      },
    ],
  }
  guard catalog.lookup("1|demo") is Some((root, id)) else {
    fail("expected composite lookup")
  }
  inspect(root.path, content="lib/.openseek")
  inspect(id, content="demo")
  guard catalog.lookup("legacy") is Some((root, id)) else {
    fail("expected legacy lookup")
  }
  inspect(root.path, content="app/.openseek")
  inspect(id, content="legacy")
  guard catalog.lookup("9|missing") is None else {
    fail("unexpected missing root lookup")
  }
}

///|
async test "session_list_reply includes root metadata and composite keys" {
  @vfs.with_tmpdir(prefix="openseek-viz-list-", root => {
    let app_store = @store.SessionStore("\{root}/app/.openseek")
    let lib_store = @store.SessionStore("\{root}/lib/.openseek")
    app_store.create(
      @agent_session.Session(SessionId("same"), system_prompt="a"),
    )
    lib_store.create(
      @agent_session.Session(SessionId("same"), system_prompt="b"),
    )
    let catalog : SessionCatalog = {
      roots: [
        {
          key: "0",
          path: "\{root}/app/.openseek",
          label: "app/.openseek",
          is_marker: true,
          store: app_store,
        },
        {
          key: "1",
          path: "\{root}/lib/.openseek",
          label: "lib/.openseek",
          is_marker: true,
          store: lib_store,
        },
      ],
    }
    let reply = session_list_reply(catalog)
    let text = reply.body
    assert_true(text.contains("\"key\":\"0|same\""))
    assert_true(text.contains("\"key\":\"1|same\""))
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
    let catalog : SessionCatalog = {
      roots: [
        {
          key: "0",
          path: "\{root}/.openseek",
          label: ".openseek",
          is_marker: true,
          store,
        },
      ],
    }
    let reply = session_path_reply(
      catalog, "0%7Crun%201/openseek_session-run%201.jsonl",
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
    let reply = session_envelope_reply(store, SessionId("demo"))
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
