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
async test "discover_session_roots scans recursively and skips heavy dirs" {
  let root = @fs.tmpdir(prefix="openseek-viz-scan-")
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
  @fs.rmdir(root, recursive=true)
}

///|
async test "discover_session_roots supports a custom root marker" {
  let root = @fs.tmpdir(prefix="openseek-viz-openroot-")
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
  @fs.rmdir(root, recursive=true)
}

///|
test "session catalog lookup supports composite and legacy keys" {
  let catalog : SessionCatalog = {
    roots: [
      {
        key: "0",
        path: "app/.openseek",
        label: "app/.openseek",
        store: @store.SessionStore("app/.openseek"),
      },
      {
        key: "1",
        path: "lib/.openseek",
        label: "lib/.openseek",
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
  let root = @fs.tmpdir(prefix="openseek-viz-list-")
  let app_store = @store.SessionStore("\{root}/app/.openseek")
  let lib_store = @store.SessionStore("\{root}/lib/.openseek")
  app_store.create(@agent_session.Session(SessionId("same"), system_prompt="a"))
  lib_store.create(@agent_session.Session(SessionId("same"), system_prompt="b"))
  let catalog : SessionCatalog = {
    roots: [
      {
        key: "0",
        path: "\{root}/app/.openseek",
        label: "app/.openseek",
        store: app_store,
      },
      {
        key: "1",
        path: "\{root}/lib/.openseek",
        label: "lib/.openseek",
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
  @fs.rmdir(root, recursive=true)
}
