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
  { channel: @interop.ChannelId::Local, installed, }
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
test "a duplicate refresh while loading is a no-op" {
  let (_, opened) = @skills.State::empty().opening(emit(), input())
  let (_, ready, _) = opened.handle(
    emit(),
    @skills.CatalogLoaded(channel=@interop.ChannelId::Local, items=[
      market_item(),
    ]),
    input(),
  )
  let (_, refreshed, _) = ready.handle(emit(), @skills.RefreshCatalog, input())
  let (_, duplicate, _) = refreshed.handle(
    emit(),
    @skills.RefreshCatalog,
    input(),
  )
  assert_true(duplicate == refreshed)
}

///|
test "catalog completions cannot cross a device focus switch" {
  let (_, local_loading) = @skills.State::empty().opening(emit(), input())
  let remote_input : @skills.Input = { channel: other_device(), installed: [], }
  let (_, remote_loading) = local_loading.opening(emit(), remote_input)

  // Opening on the new device replaces the loading owner and issues that
  // device's request; neither kind of completion from the old device lands.
  assert_false(remote_loading == local_loading)
  let (_, ignored_loaded, _) = remote_loading.handle(
    emit(),
    @skills.CatalogLoaded(channel=@interop.ChannelId::Local, items=[
      market_item(),
    ]),
    remote_input,
  )
  assert_true(ignored_loaded == remote_loading)
  let (_, ignored_failed, _) = ignored_loaded.handle(
    emit(),
    @skills.CatalogFailed(
      channel=@interop.ChannelId::Local,
      message="old host offline",
    ),
    remote_input,
  )
  assert_true(ignored_failed == remote_loading)

  let (_, ready, _) = ignored_failed.handle(
    emit(),
    @skills.CatalogLoaded(channel=other_device(), items=[market_item()]),
    remote_input,
  )
  assert_false(ready == remote_loading)
}

///|
test "an install marks its entry busy exactly once" {
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded(channel=@interop.ChannelId::Local, items=[
      market_item(),
    ]),
    input(),
  )
  let (_, busy, outcome) = ready.handle(
    emit(),
    @skills.Install(market_item()),
    input(),
  )
  assert_true(outcome is None)

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
    @skills.CatalogLoaded(channel=@interop.ChannelId::Local, items=[
      market_item(),
    ]),
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
  assert_false(failed == retried)
}

///|
test "a result from another device settles without a local outcome" {
  let (_, ready, _) = @skills.State::empty().handle(
    emit(),
    @skills.CatalogLoaded(channel=@interop.ChannelId::Local, items=[
      market_item(),
    ]),
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
  assert_false(settled == busy)
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
  let (_, again, _) = busy.handle(
    emit(),
    @skills.Uninstall("acme-widget"),
    input(installed~),
  )
  assert_true(again == busy)
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
      { id: "handmade", name: "", description: "", source: "", },
      { id: "", name: "no-id", description: "", source: "", },
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
