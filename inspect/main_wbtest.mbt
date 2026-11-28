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
    @fs.write_text(
      "\{sessions}/openseek_session-flat-a.jsonl",
      @fs.read_text(source_store.session_file(SessionId("flat-a"))),
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(
      "\{sessions}/openseek_session-flat-b.jsonl",
      @fs.read_text(source_store.session_file(SessionId("flat-b"))),
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(
      "\{sessions}/openseek_session-image-only.jsonl",
      @fs.read_text(source_store.session_file(SessionId("image-only"))),
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(
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
    let load = session_path_reply(
      catalog,
      "flat-a",
      request_path="/api/sessions/flat-a",
    )
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
    @fs.write_text(
      "\{copied_dir}/openseek_session-copied.jsonl",
      @fs.read_text(source_store.session_file(SessionId("copied"))),
      create_mode=CreateOrTruncate,
    )
    let catalog = session_catalog(copied_dir, [], ".openseek")
    let reply = session_list_reply(catalog)
    let text = reply.body
    assert_true(text.contains("\"id\":\"copied\""))
    assert_true(text.contains("\"is_marker\":false"))
    let rows = catalog.rows()
    guard rows is [row] else { fail("expected one copied row") }
    let load = session_path_reply(
      catalog,
      row.key,
      request_path="/api/sessions/\{row.key}",
    )
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
    @fs.write_text(
      "\{copied_dir}/openseek_session-marker-copy.jsonl",
      @fs.read_text(source_store.session_file(SessionId("marker-copy"))),
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
      catalog,
      "run%201/openseek_session-run%201.jsonl",
      request_path="/api/sessions/run%201/openseek_session-run%201.jsonl",
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
    @fs.mkdir(session_root, recursive=true, allow_existing=true)
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
        body.json() is { "identity": String(served), .. } && served == identity,
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
        @utf8.encode(
          "GET /api/sessions?t=\{token} HTTP/1.1\r\nHost: evil.example:\{port}\r\nConnection: close\r\n\r\n",
        ),
      )
      assert_eq(tcp.read_until(b"\r\n"), Some(b"HTTP/1.1 403 Forbidden"))
      // Other sessions never take over a busy port.
      let other = "\{root}/other/.openseek"
      @fs.mkdir(other, recursive=true, allow_existing=true)
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
      group.return_immediately()
    })
  })
}

///|
async test "an idle server exits and clears its own record" {
  @vfs.with_tmpdir(prefix="openseek-viz-idle-", root => {
    let session_root = "\{root}/.openseek"
    @fs.mkdir(session_root, recursive=true, allow_existing=true)
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
    let text = @fs.read_text(path) catch { _ => continue }
    if text.contains("name = \"moonbitlang/inspect\"") {
      manifest = text
      break
    }
  }
  assert_true(manifest.contains("version = \"\{inspect_version}\""))
}

///|
async test "a server exits once its session root is deleted" {
  @vfs.with_tmpdir(prefix="openseek-viz-root-", root => {
    let session_root = "\{root}/.openseek"
    @fs.mkdir(session_root, recursive=true, allow_existing=true)
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
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true) <| () => {
          @async.sleep(200)
          @fs.remove(session_root, recursive=true)
        }
        serve(
          server,
          { roots: [], },
          assets,
          access={ token, port, },
          idle_ms=0L,
          watch_root=session_root,
          root_check_ms=50,
        )
      })
    })
    assert_true(finished is Some(_))
  })
}

///|
async test "trajectory route folds a root session and its sub-run into one tree" {
  @vfs.with_tmpdir(prefix="openseek-viz-trajectory-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    let parent = @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("delegate")]))))
      .append(
        Assistant(
          AssistantMessage("", tool_calls=[
            ToolCall(id="c1", name="subagent", arguments="{}"),
          ]),
        ),
      )
      .append(
        Tool(
          ToolResult(tool_call_id="c1", tool_name="subagent", content=[
            Text("done"),
          ]),
        ),
      )
      .append(Terminal(Finished("done")))
    store.create(parent)
    let child = @agent_session.Session(SessionId("run-sr-1"), system_prompt="")
      .append(User(UserMessage(Content([Text("scout\nthen report")]))))
      .append(Assistant(AssistantMessage("found")))
      .append(Terminal(Finished("found")))
    store.create(child)
    // An unrelated session must not be folded in.
    store.create(
      @agent_session.Session(SessionId("other"), system_prompt="").append(
        User(UserMessage(Content([Text("x")]))),
      ),
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let reply = trajectory_reply(catalog, "run")
    inspect(reply.code, content="200")
    assert_true(reply.body.contains("\"root_session_id\":\"run\""))
    assert_true(reply.body.contains("\"session_id\":\"run-sr-1\""))
    assert_false(reply.body.contains("\"session_id\":\"other\""))
    assert_true(reply.body.contains("\"kind\":\"run\""))
    assert_true(reply.body.contains("\"kind\":\"turn\""))
    // The child's turn hangs under the parent's subagent span.
    let json = @json.parse(reply.body)
    guard json is { "spans": Array(spans), .. } else {
      fail("unexpected trajectory body")
    }
    let calls = [
      for span in spans if span
      is { "label": String(label), "id": String(id), .. } &&
      label.has_prefix("subagent") => id
    ]
    assert_eq(calls.length(), 1)
    let child_turns = [
      for span in spans if span
      is {
        "session_id": String("run-sr-1"),
        "kind": String("turn"),
        "parent_id": String(parent),
        ..
      } => parent
    ]
    assert_eq(child_turns.length(), 1)
    assert_eq(child_turns[0], calls[0])
    // A lane is labelled with the first line of its first prompt only: the
    // catalog carries the whole prompt, and a pasted brief must not fill it.
    let lane_titles = [
      for span in spans if span
      is {
        "session_id": String("run-sr-1"),
        "kind": String("turn"),
        "title": String(title),
        ..
      } => title
    ]
    assert_eq(lane_titles, ["scout"])
  })
}

///|
async test "trajectory route refuses an unknown or invalid run" {
  @vfs.with_tmpdir(prefix="openseek-viz-trajectory-miss-", root => {
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let missing = trajectory_reply(catalog, "nope")
    inspect(missing.code, content="404")
    let invalid = trajectory_reply(catalog, "../etc")
    inspect(invalid.code, content="400")
  })
}

///|
async test "a poll with the previous cursor answers unchanged, and a write invalidates it" {
  @vfs.with_tmpdir(prefix="openseek-viz-cursor-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("delegate")]))))
      .append(Assistant(AssistantMessage("done")))
      .append(Terminal(Finished("done"))),
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let first = trajectory_reply(catalog, "run")
    inspect(first.code, content="200")
    let cursor = match @json.parse(first.body) {
      { "cursor": String(token), .. } => token
      _ => fail("the first reply must carry a cursor")
    }
    // The same files: no document, just the acknowledgement.
    let again = trajectory_reply(catalog, "run", cursor~)
    inspect(again.code, content="200")
    assert_true(again.body.contains("\"unchanged\":true"))
    assert_false(again.body.contains("\"spans\""))
    // A write moves the stamp, so the old cursor no longer matches.
    @fs.write_text(
      store.session_file(SessionId("run")),
      "\n",
      create_mode=OpenOrCreate,
      append=true,
    )
    let changed = trajectory_reply(catalog, "run", cursor~)
    inspect(changed.code, content="200")
    assert_true(changed.body.contains("\"spans\""))
    let next = match @json.parse(changed.body) {
      { "cursor": String(token), .. } => token
      _ => fail("a fresh reply must carry a cursor")
    }
    assert_true(next != cursor)
    // And the new cursor is honoured in turn.
    let settled = trajectory_reply(catalog, "run", cursor=next)
    assert_true(settled.body.contains("\"unchanged\":true"))
  })
}

///|
async test "a run is folded from its own store only" {
  @vfs.with_tmpdir(prefix="openseek-viz-store-", root => {
    let mine = @store.SessionStore("\{root}/a")
    mine.create(
      @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("mine")]))))
      .append(Terminal(Finished("done"))),
    )
    // The same run id in a second store, with a child of its own: `<root>-sr-N`
    // ids are only unique per store, so none of this may join the timeline.
    let other = @store.SessionStore("\{root}/b")
    other.create(
      @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("theirs")]))))
      .append(
        Assistant(
          AssistantMessage("", tool_calls=[
            ToolCall(id="c1", name="subagent", arguments="{}"),
          ]),
        ),
      )
      .append(
        Tool(
          ToolResult(tool_call_id="c1", tool_name="subagent", content=[
            Text("done"),
          ]),
        ),
      )
      .append(Terminal(Finished("done"))),
    )
    other.create(
      @agent_session.Session(SessionId("run-sr-1"), system_prompt="")
      .append(User(UserMessage(Content([Text("theirs too")]))))
      .append(Terminal(Finished("done"))),
    )
    let catalog : SessionCatalog = {
      roots: [marker_root(root, "a"), marker_root(root, "b")],
    }
    let reply = trajectory_reply(catalog, "run")
    inspect(reply.code, content="200")
    assert_false(reply.body.contains("run-sr-1"))
    let trace = @trajectory.parse_trajectory(@json.parse(reply.body)) catch {
      _ => fail("the reply must be a trajectory document")
    }
    assert_eq(trace.stats.session_count, 1)
    assert_eq(trace.sessions[0].session_id, "run")
  })
}

///|
async test "a child session appearing invalidates the cursor" {
  @vfs.with_tmpdir(prefix="openseek-viz-cursor-child-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("delegate")]))))
      .append(Terminal(Finished("done"))),
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let first = trajectory_reply(catalog, "run")
    let cursor = match @json.parse(first.body) {
      { "cursor": String(token), .. } => token
      _ => fail("the first reply must carry a cursor")
    }
    // A run that spawns its first child while the root sits still: the new file
    // is a lane the old cursor cannot know about.
    store.create(
      @agent_session.Session(SessionId("run-sr-1"), system_prompt="")
      .append(User(UserMessage(Content([Text("scout")]))))
      .append(Terminal(Finished("done"))),
    )
    let changed = trajectory_reply(catalog, "run", cursor~)
    inspect(changed.code, content="200")
    assert_false(changed.body.contains("\"unchanged\""))
    let trace = @trajectory.parse_trajectory(@json.parse(changed.body)) catch {
      _ => fail("a changed run must send a document")
    }
    assert_eq(trace.stats.session_count, 2)
  })
}

///|
async test "an export bakes one timeline per run it holds" {
  @vfs.with_tmpdir(prefix="openseek-viz-export-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("delegate")]))))
      .append(Terminal(Finished("done"))),
    )
    store.create(
      @agent_session.Session(SessionId("run-sr-1"), system_prompt="")
      .append(User(UserMessage(Content([Text("scout the parser")]))))
      .append(Terminal(Finished("done"))),
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let rows = catalog.rows()
    let runs = @viz_export.bake_runs(
      [
        for row in rows => {
          @viz_export.RunSource(
            id=row.id,
            store=row.root,
            first_prompt=row.first_prompt,
            text=read_text_lossy(row.path),
          )
        }
      ],
    )
    // Two files, one run: the document is keyed by the root the viewer asks for.
    assert_eq(runs.length(), 1)
    assert_eq(runs[0].root_id, "run")
    let trace = @trajectory.parse_trajectory(@json.parse(runs[0].body)) catch {
      _ => fail("the baked document must parse as a trajectory")
    }
    assert_eq(trace.stats.session_count, 2)
    // Lane labels come from the prompt, exactly as the served route labels them.
    assert_true(runs[0].body.contains("scout the parser"))
  })
}

///|
test "files_token changes when file size changes at identical mtime" {
  let a = files_token([("/tmp/a.jsonl", 100L, 0, 10L)])
  let b = files_token([("/tmp/a.jsonl", 100L, 0, 20L)])
  assert_not_eq(a, b)
}

///|
async test "trajectory_reply discovers non-sr child sessions via tool result" {
  @vfs.with_tmpdir(prefix="openseek-viz-custom-child-", root => {
    let store = @store.SessionStore("\{root}/.openseek")
    store.create(
      @agent_session.Session(SessionId("run"), system_prompt="")
      .append(User(UserMessage(Content([Text("delegate")]))))
      .append(
        Assistant(
          AssistantMessage("", tool_calls=[
            ToolCall(id="c1", name="subagent", arguments="{}"),
          ]),
        ),
      )
      .append(
        Tool(
          ToolResult(
            tool_call_id="c1",
            tool_name="subagent",
            content=[Text("ok")],
            data=Json::object({ "session": Json("worker-custom") }),
          ),
        ),
      )
      .append(Terminal(Finished("done"))),
    )
    store.create(
      @agent_session.Session(SessionId("worker-custom"), system_prompt="")
      .append(User(UserMessage(Content([Text("custom worker prompt")]))))
      .append(Terminal(Finished("ok"))),
    )
    let catalog : SessionCatalog = { roots: [marker_root(root, ".openseek")], }
    let reply = trajectory_reply(catalog, "run")
    inspect(reply.code, content="200")
    let trace = @trajectory.parse_trajectory(@json.parse(reply.body)) catch {
      _ => fail("expected trajectory document")
    }
    assert_eq(trace.stats.session_count, 2)
    assert_true(reply.body.contains("custom worker prompt"))
    let cursor = match @json.parse(reply.body) {
      { "cursor": String(token), .. } => token
      _ => fail("expected cursor")
    }
    let unchanged = trajectory_reply(catalog, "run", cursor~)
    assert_true(unchanged.body.contains("\"unchanged\":true"))
    let resolved = trajectory_reply(catalog, "worker-custom", resolve_root=true)
    inspect(resolved.code, content="200")
    let resolved_trace = @trajectory.parse_trajectory(
      @json.parse(resolved.body),
    ) catch {
      _ => fail("expected resolved trajectory document")
    }
    assert_eq(resolved_trace.root_session_id, "run")
    assert_eq(resolved_trace.stats.session_count, 2)
  })
}
