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
      #|  "_build/js/release/build/cmd/viz_app/viz_app.js",
      #|  "_build/js/debug/build/cmd/viz_app/viz_app.js",
      #|  "/repo/web/viz_app.js",
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
