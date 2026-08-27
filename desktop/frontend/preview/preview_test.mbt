// State-transition and address-lexing tests for the browser subsystem. The
// package is command-free — navigation side effects live in the root — so
// every assertion is on returned state or parsed text.

///|
test "open_page stores caller-minted UUIDs and blank tabs have no url" {
  let first = "browser-a"
  let second = "browser-b"
  let state = @preview.open_page(@preview.State::empty(), id=first)
  let state = @preview.open_page(state, id=second, url="http://127.0.0.1:5173/")
  let blank = @preview.page(state, first).unwrap()
  assert_true(blank.url is None)
  assert_eq(blank.input, "")
  assert_false(blank.loading)
  let routed = @preview.page(state, second).unwrap()
  assert_true(routed.url == Some("http://127.0.0.1:5173/"))
  assert_eq(routed.input, "http://127.0.0.1:5173/")
  assert_true(routed.loading)
}

///|
test "close_page drops only its page" {
  let first = "browser-a"
  let second = "browser-b"
  let state = @preview.open_page(@preview.State::empty(), id=first)
  let state = @preview.open_page(state, id=second)
  let state = @preview.close_page(state, first)
  assert_true(@preview.page(state, first) is None)
  assert_true(@preview.page(state, second) is Some(_))
}

///|
test "navigate commits url, mirrors the draft, clears the failure" {
  let id = "browser-a"
  let state = @preview.open_page(@preview.State::empty(), id~)
  let state = @preview.update(
    @preview.Msg::LoadFailed(id~, url="http://x/", text="boom"),
    state,
  )
  let state = @preview.navigate(state, id, "http://127.0.0.1:8080/")
  let page = @preview.page(state, id).unwrap()
  assert_true(page.url == Some("http://127.0.0.1:8080/"))
  assert_eq(page.input, "http://127.0.0.1:8080/")
  assert_true(page.loading)
  assert_true(page.failure is None)
}

///|
test "update applies host events and is idempotent" {
  let id = "browser-a"
  let state = @preview.open_page(
    @preview.State::empty(),
    id~,
    url="http://localhost:5173/",
  )
  let msgs : Array[@preview.Msg] = [
    Navigated(id~, url="http://localhost:5173/app"),
    TitleUpdated(id~, title="Dev Server"),
    LoadingChanged(id~, loading=false),
  ]
  let mut current = state
  for msg in msgs {
    current = @preview.update(msg, current)
    // Idempotence: applying the same event twice settles on the same state.
    assert_true(@preview.update(msg, current) == current)
  }
  let page = @preview.page(current, id).unwrap()
  assert_true(page.url == Some("http://localhost:5173/app"))
  assert_eq(page.input, "http://localhost:5173/app")
  assert_eq(page.title, "Dev Server")
  assert_false(page.loading)
}

///|
test "a new document drops the title; a fragment jump keeps it" {
  let id = "browser-a"
  let state = @preview.open_page(
    @preview.State::empty(),
    id~,
    url="https://example.com/docs",
  )
  let titled = @preview.update(
    @preview.Msg::TitleUpdated(id~, title="Docs"),
    state,
  )
  // Same document, new anchor: the page never reloads, so no `TitleUpdated`
  // is coming and the title must survive.
  let anchored = @preview.update(
    @preview.Msg::Navigated(id~, url="https://example.com/docs#install"),
    titled,
  )
  assert_eq(@preview.page_label(@preview.page(anchored, id).unwrap()), "Docs")
  // A different document is a different page: labelling it "Docs" until some
  // title arrives (a failed load reports none) would name the wrong site.
  let moved = @preview.update(
    @preview.Msg::Navigated(id~, url="https://other.test/x"),
    anchored,
  )
  assert_eq(
    @preview.page_label(@preview.page(moved, id).unwrap()),
    "other.test",
  )
  // The address bar's own commit follows the same rule.
  let typed = @preview.navigate(titled, id, "https://example.com/guide")
  assert_eq(
    @preview.page_label(@preview.page(typed, id).unwrap()),
    "example.com",
  )
}

///|
test "a failure for a superseded URL never reaches the page" {
  let id = "browser-a"
  let state = @preview.open_page(
    @preview.State::empty(),
    id~,
    url="http://localhost:5173/",
  )
  // The user moves on before the old load's error is reported.
  let moved = @preview.navigate(state, id, "https://example.com/")
  let late = @preview.update(
    @preview.Msg::LoadFailed(
      id~,
      url="http://localhost:5173/",
      text="ERR_CONNECTION_REFUSED",
    ),
    moved,
  )
  assert_true(late == moved)
  // The current URL's own failure still shows.
  let failed = @preview.update(
    @preview.Msg::LoadFailed(
      id~,
      url="https://example.com/",
      text="ERR_NAME_NOT_RESOLVED",
    ),
    moved,
  )
  let page = @preview.page(failed, id).unwrap()
  assert_true(page.failure is Some(_))
  assert_false(page.loading)
}

///|
test "events for unknown pages are dropped" {
  let state = @preview.State::empty()
  let next = @preview.update(
    @preview.Msg::TitleUpdated(id="ghost", title="ghost"),
    state,
  )
  assert_true(next == state)
}

///|
test "load failure records and navigation label falls back sensibly" {
  let id = "browser-a"
  let state = @preview.open_page(
    @preview.State::empty(),
    id~,
    url="http://localhost:5173/",
  )
  let state = @preview.update(
    @preview.Msg::LoadFailed(id~, url="http://localhost:5173/", text="refused"),
    state,
  )
  let page = @preview.page(state, id).unwrap()
  assert_false(page.loading)
  assert_true(page.failure is Some(_))
  assert_eq(@preview.page_label(page), "localhost")
  let titled = @preview.update(
    @preview.Msg::TitleUpdated(id~, title="Docs"),
    state,
  )
  assert_eq(@preview.page_label(@preview.page(titled, id).unwrap()), "Docs")
  let blank = "browser-blank"
  let blank_state = @preview.open_page(state, id=blank)
  assert_eq(
    @preview.page_label(@preview.page(blank_state, blank).unwrap()),
    "New Tab",
  )
}

///|
test "host_of strips scheme, userinfo, and port" {
  assert_true(@preview.host_of("http://localhost:5173/x") == Some("localhost"))
  assert_true(
    @preview.host_of("https://User@Example.COM:8443?q=1") == Some("example.com"),
  )
  assert_true(@preview.host_of("http://[::1]:3000/") == Some("[::1]"))
  assert_true(@preview.host_of("http://127.0.0.1") == Some("127.0.0.1"))
  assert_true(@preview.host_of("ftp://x/") is None)
  assert_true(@preview.host_of("not a url") is None)
}

///|
test "is_web_url accepts http(s) with a host only" {
  assert_true(@preview.is_web_url("http://127.0.0.1:5173/"))
  assert_true(@preview.is_web_url("https://github.com/moonbit"))
  assert_true(@preview.is_web_url("HTTPS://Example.COM/x"))
  assert_false(@preview.is_web_url("mailto:someone@example.com"))
  assert_false(@preview.is_web_url("file:///etc/passwd"))
  assert_false(@preview.is_web_url("vscode://open?x=1"))
  assert_false(@preview.is_web_url("not a url"))
  // A bare scheme or hostless URL is not a page the host would load.
  assert_false(@preview.is_web_url("http://"))
  assert_false(@preview.is_web_url("https:///path"))
}

///|
test "is_loopback routes only this machine's hosts" {
  assert_true(@preview.is_loopback("http://localhost:5173/"))
  assert_true(@preview.is_loopback("http://127.0.0.1:8080/path"))
  assert_true(@preview.is_loopback("https://127.1.2.3/"))
  assert_true(@preview.is_loopback("http://[::1]:3000/"))
  assert_false(@preview.is_loopback("https://github.com/"))
  assert_false(@preview.is_loopback("https://localhost.evil.com/"))
  assert_false(@preview.is_loopback("mailto:someone@example.com"))
  // A `127.`-prefixed DNS name is somebody else's machine: only a dotted
  // quad in 127/8 is loopback, so these keep the https default.
  assert_false(@preview.is_loopback("https://127.example.com/"))
  assert_false(@preview.is_loopback("https://127.com/"))
  assert_false(@preview.is_loopback("https://127.0.0.1.evil.com/"))
  assert_false(@preview.is_loopback("https://127.0.0.256/"))
  assert_true(
    @preview.normalize_url("127.example.com") == Some("https://127.example.com"),
  )
}

///|
test "normalize_url prefixes bare hosts and rejects foreign schemes" {
  assert_true(
    @preview.normalize_url("http://example.com/x") ==
    Some("http://example.com/x"),
  )
  assert_true(
    @preview.normalize_url("  https://example.com  ") ==
    Some("https://example.com"),
  )
  assert_true(
    @preview.normalize_url("localhost:5173") == Some("http://localhost:5173"),
  )
  assert_true(
    @preview.normalize_url("127.0.0.1:8080/app") ==
    Some("http://127.0.0.1:8080/app"),
  )
  assert_true(
    @preview.normalize_url("example.com/docs") ==
    Some("https://example.com/docs"),
  )
  // A path colon is not a scheme; a scheme colon is.
  assert_true(
    @preview.normalize_url("example.com/a:b") == Some("https://example.com/a:b"),
  )
  assert_true(@preview.normalize_url("javascript:alert(1)") is None)
  assert_true(@preview.normalize_url("mailto:x@y.z") is None)
  assert_true(@preview.normalize_url("ftp://host/") is None)
  assert_true(@preview.normalize_url("") is None)
  assert_true(@preview.normalize_url("two words") is None)
  // A committed draft must be a URL the host will load: a bare scheme or a
  // hostless path normalizes to nothing rather than stranding the tab.
  assert_true(@preview.normalize_url("http://") is None)
  assert_true(@preview.normalize_url("/docs") is None)
}
