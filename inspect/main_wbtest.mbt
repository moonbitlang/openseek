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
test "module_root_from_exe recovers the checkout from a moon build path" {
  @debug.debug_inspect(
    module_root_from_exe(
      "/Users/x/git/openseek/_build/native/release/build/moonbitlang/inspect/inspect.exe",
    ),
    content=(
      #|Some("/Users/x/git/openseek")
    ),
  )
  // moon run from a sibling directory passes a relative exe path.
  @debug.debug_inspect(
    module_root_from_exe(
      "../openseek/_build/native/release/build/moonbitlang/inspect/inspect.exe",
    ),
    content=(
      #|Some("../openseek")
    ),
  )
  // Run from the checkout root itself, the relative path has no prefix.
  @debug.debug_inspect(
    module_root_from_exe(
      "_build/native/release/build/moonbitlang/inspect/inspect.exe",
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
    shell_candidates("web", Some("/repo"), web_dir_explicit=false),
    content=(
      #|["web/index.html", "/repo/web/index.html"]
    ),
  )
  @debug.debug_inspect(
    shell_candidates("custom", None, web_dir_explicit=true),
    content=(
      #|["custom/index.html"]
    ),
  )
  @debug.debug_inspect(
    bundle_candidates("", "web", Some("/repo"), web_dir_explicit=false),
    content=(
      #|[
      #|  "",
      #|  "web/viz_app.js",
      #|  "_build/js/release/build/moonbitlang/openseek-viz-app/openseek-viz-app.js",
      #|  "_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js",
      #|  "/repo/web/viz_app.js",
      #|  "/repo/_build/js/release/build/moonbitlang/openseek-viz-app/openseek-viz-app.js",
      #|  "/repo/_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js",
      #|]
    ),
  )
  // An explicit --bundle stays the highest-priority candidate.
  @debug.debug_inspect(
    bundle_candidates("/x/app.js", "web", None, web_dir_explicit=true),
    content=(
      #|["/x/app.js", "web/viz_app.js"]
    ),
  )
}

///|
test "outside a checkout, only explicit asset paths are searched" {
  // Under moonx there is no checkout: the default `web/` and the CWD build
  // outputs belong to whatever project the user is in, so the binary's own
  // embedded copies must win over them.
  @debug.debug_inspect(
    shell_candidates("web", None, web_dir_explicit=false),
    content=(
      #|[]
    ),
  )
  @debug.debug_inspect(
    bundle_candidates("", "web", None, web_dir_explicit=false),
    content=(
      #|[""]
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
        User(UserMessage(Content([Text("copied prompt")]))),
      ),
    )
    source_store.create(
      @agent_session.Session(SessionId("image-only"), system_prompt="").append(
        User(
          UserMessage(
            Content([
              Image(
                @agent_session.Image::from_base64(
                  media_type="image/png",
                  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==",
                ),
              ),
            ]),
          ),
        ),
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
      "\{sessions}/openseek_session-image-only.jsonl",
      @fs.read_file(source_store.session_file(SessionId("image-only"))).text(),
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
    assert_true(text.contains("\"first_prompt\":\"[Image]\""))
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
      User(UserMessage(Content([Text("hi")]))),
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
      User(UserMessage(Content([Text("hi")]))),
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

///|
async test "session_envelope_reply answers unchanged while the size matches" {
  @vfs.with_tmpdir(prefix="openseek-viz-watch-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    let session = @agent_session.Session(SessionId("demo"), system_prompt="").append(
      User(UserMessage(Content([Text("hi")]))),
    )
    store.create(session)
    let path = store.session_file(SessionId("demo"))
    let full = session_envelope_reply(path)
    guard @json.parse(full.body) is { "events_bytes": Number(size, ..), .. } else {
      fail("expected events_bytes")
    }
    // The viewer already has every byte: no log in the reply.
    let same = session_envelope_reply(path, known_bytes=size.to_int64())
    guard @json.parse(same.body) is Object(fields) else {
      fail("expected JSON")
    }
    assert_true(fields.get("unchanged") is Some(True))
    assert_true(fields.get("events") is None)
    // A stale size gets the full log again.
    let stale = session_envelope_reply(path, known_bytes=1L)
    guard @json.parse(stale.body) is { "events": String(events), .. } else {
      fail("expected the full log")
    }
    inspect(events.length(), content="\{size.to_int()}")
  })
}

///|
async test "a second --ensure reuses the first; the token and Host gate the rest" {
  @vfs.with_tmpdir(prefix="openseek-viz-ensure-", root => {
    let session_root = "\{root}/.openseek"
    @fs.mkdir(session_root, recursive=true, allow_exist=true)
    let identity = server_identity(session_root, [])
    let ports = ensure_ports(identity)
    guard ensure_server(session_root, identity, ports)
      is Started(server, port, token) else {
      fail("expected the first --ensure to start a server")
    }
    // The record names this server and is only readable by its owner.
    assert_true(
      read_record(record_path(session_root)) is Some({ port: p, token: t, .. }) &&
      p == port &&
      t == token,
    )
    let assets : ViewerAssets = {
      shell: [],
      bundle: [],
      watch: false,
      identity,
    }
    let catalog : SessionCatalog = { roots: [], }
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true) <| () => {
        serve(server, catalog, assets, access={ token, port, }, idle_ms=0L)
      }
      guard ensure_server(session_root, identity, ports) is Reused(p2, t2) else {
        fail("expected the second --ensure to reuse the first")
      }
      assert_eq(p2, port)
      assert_eq(t2, token)
      let base = "http://127.0.0.1:\{port}"
      // /api/info is open, and names the sessions served.
      let (info, body) = @http.get("\{base}/api/info")
      assert_eq(info.code, 200)
      assert_true(
        @json.parse(body.text()) is { "identity": String(served), .. } &&
        served == identity,
      )
      // Everything else needs the token, as ?t= or the cookie it sets.
      let (denied, _) = @http.get("\{base}/api/sessions")
      assert_eq(denied.code, 403)
      let (allowed, _) = @http.get("\{base}/api/sessions?t=\{token}")
      assert_eq(allowed.code, 200)
      // Opening with ?t= leaves the token in an HttpOnly cookie for the page.
      assert_true(
        allowed.cookies
        .iter()
        .any(cookie => {
          cookie.name == "openseek_inspect_\{port}" &&
          cookie.value == token &&
          cookie.http_only &&
          cookie.path == Some("/")
        }),
      )
      let (by_cookie, _) = @http.get("\{base}/api/sessions", headers={
        "Cookie": "openseek_inspect_\{port}=\{token}",
      })
      assert_eq(by_cookie.code, 200)
      // A page on another site that rebinds its name to 127.0.0.1 is refused,
      // even with the token. The HTTP client always sends the URL's own Host,
      // so this request is written by hand.
      let tcp = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
      defer tcp.close()
      tcp.write(
        "GET /api/sessions?t=\{token} HTTP/1.1\r\nHost: evil.example:\{port}\r\nConnection: close\r\n\r\n",
      )
      assert_eq(tcp.read_until("\r\n"), Some("HTTP/1.1 403 Forbidden"))
      // Other sessions never take over a busy port.
      let other = "\{root}/other/.openseek"
      @fs.mkdir(other, recursive=true, allow_exist=true)
      let other_identity = server_identity(other, [])
      assert_true(other_identity != identity)
      let taken = try ensure_server(other, other_identity, [port]) catch {
        error => {
          assert_true("\{error}".contains("no free port"))
          None
        }
      } noraise {
        _ => Some(())
      }
      assert_true(taken is None)
      group.return_immediately(())
    })
  })
}

///|
async test "an idle server exits and clears its own record" {
  @vfs.with_tmpdir(prefix="openseek-viz-idle-", root => {
    let session_root = "\{root}/.openseek"
    @fs.mkdir(session_root, recursive=true, allow_exist=true)
    let identity = server_identity(session_root, [])
    guard ensure_server(session_root, identity, ensure_ports(identity))
      is Started(server, port, token) else {
      fail("expected a server")
    }
    let assets : ViewerAssets = {
      shell: [],
      bundle: [],
      watch: false,
      identity,
    }
    let finished = @async.with_timeout_opt(5000, () => {
      serve(
        server,
        { roots: [], },
        assets,
        access={ token, port, },
        idle_ms=200L,
        on_exit=() => remove_own_record(session_root, port, token),
      )
    })
    assert_true(finished is Some(_))
    assert_true(read_record(record_path(session_root)) is None)
  })
}

///|
async test "inspect_version matches moon.mod" {
  // Tests run from the module or the workspace root, depending on the build.
  let mut manifest = ""
  for path in ["moon.mod", "inspect/moon.mod"] {
    let text = @fs.read_file(path).text() catch { _ => continue }
    if text.contains("name = \"moonbitlang/inspect\"") {
      manifest = text
      break
    }
  }
  assert_true(manifest.contains("version = \"\{inspect_version}\""))
}
