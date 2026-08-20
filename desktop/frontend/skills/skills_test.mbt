// The page's contract as the shell sees it: what it draws, what it asks the
// root for, and what a reply from a device that is no longer focused may do.
// Nothing here reads inside `State` — a run is built by driving the same
// entry points `frontend` drives.

///|
fn emit() -> @cmd.Emit[@skills.Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
fn other_device() -> @interop.ChannelId {
  @interop.ChannelId::Remote("d_b")
}

///|
fn input(installed? : Array[@skills.InstalledItem] = []) -> @skills.Input {
  { channel: @interop.ChannelId::Local, installed }
}

///|
fn market_item(
  version? : String = "1.0.0",
  package_path? : String = "",
) -> @skills.MarketItem {
  {
    name: "acme/widget",
    module_name: "acme/widget",
    package_path,
    version,
    description: "Build widgets fast.",
    author: "acme",
    repository: "",
  }
}

///|
/// The page as the browser would see it. `component` is the only rendering
/// entry the shell has, so the tests use it too.
#warnings("-alert_unstable")
fn markup(state : @skills.State, input : @skills.Input) -> String {
  @rabbita.render_to_string(() => {
    @skills.component(
      @rabbita.Val::constant(input),
      @rabbita.Val::constant(state),
      emit(),
    )
  })
}

///|
test "the catalog is fetched once per app run" {
  let (_, opened) = @skills.State::empty().opening(emit(), input())
  assert_true(markup(opened, input()).contains("Loading the skill catalog…"))

  // Reopening with a loaded catalog keeps it instead of asking again.
  let (_, ready, _) = opened.handle(
    emit(),
    @skills.CatalogLoaded([market_item()]),
    input(),
  )
  let (_, reopened) = ready.opening(emit(), input())
  assert_true(markup(reopened, input()).contains("acme/widget"))

  // Only a failure refetches — and reopening drops the stale notice with it.
  let (_, failed, _) = ready.handle(
    emit(),
    @skills.CatalogFailed("offline"),
    input(),
  )
  let stale = failed.with_notice("library unreadable")
  assert_true(markup(stale, input()).contains("library unreadable"))
  let (_, retried) = stale.opening(emit(), input())
  let retried_markup = markup(retried, input())
  assert_true(retried_markup.contains("Loading the skill catalog…"))
  assert_false(retried_markup.contains("library unreadable"))
}

///|
test "the search query filters both lists" {
  let installed : Array[@skills.InstalledItem] = [
    { id: "gadget", name: "gadget", description: "", source: "" },
  ]
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded([market_item()]),
    input(installed~),
  )
  let (_, typed, _) = ready.handle(
    emit(),
    @skills.QueryChanged("widget"),
    input(installed~),
  )
  let filtered = markup(typed, input(installed~))
  assert_true(filtered.contains("acme/widget"))
  assert_false(filtered.contains(">gadget<"))
  assert_true(filtered.contains("No installed skill matches the search."))

  // A blank query keeps everything; the filter is not sticky state.
  let (_, cleared, _) = typed.handle(
    emit(),
    @skills.QueryChanged(""),
    input(installed~),
  )
  assert_true(markup(cleared, input(installed~)).contains(">gadget<"))
}

///|
test "an install marks its entry busy exactly once" {
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded([market_item()]),
    input(),
  )
  let (_, busy, outcome) = ready.handle(
    emit(),
    @skills.Install(market_item()),
    input(),
  )
  assert_true(outcome is None)
  assert_true(markup(busy, input()).contains("Installing…"))

  // A second click while in flight is a no-op.
  let (_, again, _) = busy.handle(
    emit(),
    @skills.Install(market_item()),
    input(),
  )
  assert_true(again == busy)
}

///|
test "a settled install releases its entry and asks for a library re-read" {
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded([market_item()]),
    input(),
  )
  let (_, busy, _) = ready.handle(
    emit(),
    @skills.Install(market_item()),
    input(),
  )
  let (_, done, outcome) = busy.handle(
    emit(),
    @skills.ActionDone(
      channel=@interop.ChannelId::Local,
      key="acme/widget@1.0.0",
      error="",
    ),
    input(),
  )
  guard outcome is Some(LibraryChanged(channel~)) else {
    fail("a successful install should report the library change")
  }
  assert_true(channel == @interop.ChannelId::Local)
  assert_false(markup(done, input()).contains("Installing…"))

  // A failure surfaces as the page's notice instead, and reports nothing.
  let (_, retried, _) = done.handle(
    emit(),
    @skills.Install(market_item()),
    input(),
  )
  let (_, failed, failure_outcome) = retried.handle(
    emit(),
    @skills.ActionDone(
      channel=@interop.ChannelId::Local,
      key="acme/widget@1.0.0",
      error="digest mismatch",
    ),
    input(),
  )
  assert_true(failure_outcome is None)
  assert_true(markup(failed, input()).contains("digest mismatch"))
}

///|
test "a result that outlived a focus switch speaks for nothing on screen" {
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded([market_item()]),
    input(),
  )
  let (_, busy, _) = ready.handle(
    emit(),
    @skills.Install(market_item()),
    input(),
  )
  let (_, settled, outcome) = busy.handle(
    emit(),
    @skills.ActionDone(
      channel=other_device(),
      key="acme/widget@1.0.0",
      error="digest mismatch",
    ),
    input(),
  )
  // The busy entry is still released — the request is over either way — but
  // the old host's failure never becomes this page's notice.
  assert_true(outcome is None)
  let settled_markup = markup(settled, input())
  assert_false(settled_markup.contains("digest mismatch"))
  assert_false(settled_markup.contains("Installing…"))
}

///|
test "uninstall is keyed by the library id and deduplicated" {
  let installed : Array[@skills.InstalledItem] = [
    {
      id: "acme-widget",
      name: "widget",
      description: "",
      source: "acme/widget@1.0.0",
    },
  ]
  let (_, busy, _) = @skills.State::empty().handle(
    emit(),
    @skills.Uninstall("acme-widget"),
    input(installed~),
  )
  assert_true(markup(busy, input(installed~)).contains("Removing…"))
  let (_, again, _) = busy.handle(
    emit(),
    @skills.Uninstall("acme-widget"),
    input(installed~),
  )
  assert_true(again == busy)
}

///|
test "the library decides which catalog rows still offer an install" {
  let installed : Array[@skills.InstalledItem] = [
    {
      id: "acme-widget",
      name: "widget",
      description: "",
      source: "acme/widget@1.0.0",
    },
  ]
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded([market_item()]),
    input(installed~),
  )
  assert_true(markup(ready, input(installed~)).contains("✓ Installed"))

  // An older install keeps the button alive as the upgrade path.
  let (_, newer, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded([market_item(version="2.0.0")]),
    input(installed~),
  )
  assert_true(markup(newer, input(installed~)).contains(">Install<"))
}

///|
test "hand-written skills are listed but never offered for removal" {
  let installed : Array[@skills.InstalledItem] = [
    { id: "handmade", name: "handmade", description: "", source: "" },
  ]
  let listed = markup(@skills.State::empty(), input(installed~))
  assert_true(listed.contains("hand-written"))
  assert_false(listed.contains(">Uninstall<"))
}

///|
test "the search box declares form focus ownership" {
  let rendered = markup(@skills.State::empty(), input())
  assert_true(rendered.contains("class=\"skills-search\""))
  assert_true(rendered.contains("data-focus-owner=\"\""))
  assert_true(rendered.contains("data-focus-target=\"\""))
  // Every rendered form element must choose one side of the contract — the
  // page owns this check now that the shell's sweep no longer reaches it.
  for tag in ["<input", "<textarea", "<select"] {
    let parts = rendered.split(tag).collect()
    for index, part in parts {
      if index > 0 {
        guard part.split_once(">") is Some((opening, _)) else {
          fail("unterminated form element in rendered markup")
        }
        assert_true(
          opening.contains("data-focus-owner") ||
          opening.contains("data-focus-target"),
        )
      }
    }
  }
}

///|
test "catalog replies decode and skip odd entries" {
  let items = @skills.catalog_from_reply({
    skills: [
      {
        name: "acme/widget",
        module_name: "acme/widget",
        package_path: "",
        version: "1.0.0",
        description: "Build widgets fast.",
        author: "acme",
        repository: "https://example.com/acme/widget",
      },
      {
        name: "odd",
        module_name: "",
        package_path: "",
        version: "1.0.0",
        description: "",
        author: "",
        repository: "",
      },
    ],
  })
  guard items is [item] else { fail("expected exactly one catalog item") }
  assert_eq(item.name, "acme/widget")
  assert_eq(item.module_name, "acme/widget")
  assert_eq(item.version, "1.0.0")
  assert_eq(item.description, "Build widgets fast.")
  assert_eq(@skills.source_label(item), "acme/widget@1.0.0")
}

///|
test "subpackage skills carry their package path in the source label" {
  let items = @skills.catalog_from_reply({
    skills: [
      {
        name: "alice/alpha/cmd/run",
        module_name: "alice/alpha",
        package_path: "cmd/run",
        version: "0.2.0",
        description: "Run alpha commands",
        author: "",
        repository: "",
      },
    ],
  })
  guard items is [item] else { fail("expected one catalog item") }
  assert_eq(@skills.source_label(item), "alice/alpha@0.2.0/cmd/run")
  assert_eq(item.author, "")
}

///|
test "installed skill replies decode, with name falling back to id" {
  let items = @skills.installed_from_reply({
    skills: [
      {
        id: "acme-widget",
        name: "widget",
        description: "Build widgets fast.",
        source: "acme/widget@1.0.0",
      },
      { id: "handmade", name: "", description: "", source: "" },
      { id: "", name: "no-id", description: "", source: "" },
    ],
  })
  guard items is [widget, handmade] else {
    fail("expected two installed items")
  }
  assert_eq(widget.id, "acme-widget")
  assert_eq(widget.name, "widget")
  assert_eq(widget.source, "acme/widget@1.0.0")
  assert_eq(handmade.name, "handmade")
  assert_eq(handmade.source, "")
}
