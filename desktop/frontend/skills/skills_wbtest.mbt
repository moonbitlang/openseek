///|
fn wb_skill(enabled~ : Bool, name~ : String = "widget") -> InstalledItem {
  {
    id: "acme-widget",
    name,
    description: "",
    source: "acme/widget@1.0.0",
    registry: Some({ module_name: "acme/widget", package_path: "", }),
    builtin: false,
    enabled,
  }
}

///|
fn wb_input(installed~ : Array[InstalledItem]) -> Input {
  {
    library: Host(@interop.ChannelId::Local),
    installed,
    choices: [
      { library: Host(@interop.ChannelId::Local), name: None, available: true, },
    ],
    locale: English,
  }
}

///|
fn wb_emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
/// The request number of the read a preview is waiting on.
fn wb_pending_request(preview : Preview) -> Int32 raise {
  match preview {
    Loading(request~, ..) => request
    _ => fail("expected a pending preview read")
  }
}

///|
test "enablement-only refresh preserves an open preview and its pending read" {
  let skill = wb_skill(enabled=true)
  let (_, loading, _) = State::empty().handle(
    wb_emit(),
    PreviewInstalled(skill),
    wb_input(installed=[skill]),
  )
  let request = wb_pending_request(loading.preview)
  let disabled = wb_skill(enabled=false)
  let (_, unchanged) = loading.sync_library(
    wb_emit(),
    wb_input(installed=[disabled]),
  )
  // The live mirror says disabled, but the document and the read it owns are
  // unchanged; renderers take enablement from the mirror, not from this target.
  assert_true(unchanged == loading)
  let (_, ready, _) = unchanged.handle(
    wb_emit(),
    PreviewLoaded(
      library=Host(@interop.ChannelId::Local),
      request~,
      target=Installed(skill),
      content="body",
    ),
    wb_input(installed=[disabled]),
  )
  guard ready.preview is Ready(content="body", ..) else {
    fail("the read issued before the toggle must still settle")
  }
  assert_true(ready.detail_open(Host(@interop.ChannelId::Local)))
}

///|
test "a library change to the document reloads it and drops the old read" {
  let skill = wb_skill(enabled=true)
  let (_, loading, _) = State::empty().handle(
    wb_emit(),
    PreviewInstalled(skill),
    wb_input(installed=[skill]),
  )
  let old_request = wb_pending_request(loading.preview)
  let renamed = wb_skill(enabled=true, name="renamed")
  let (_, reloading) = loading.sync_library(
    wb_emit(),
    wb_input(installed=[renamed]),
  )
  let next_request = wb_pending_request(reloading.preview)
  assert_eq(next_request, old_request + 1)
  // A reply for the pre-change snapshot is stale by target and by request.
  let (_, ignored, _) = reloading.handle(
    wb_emit(),
    PreviewLoaded(
      library=Host(@interop.ChannelId::Local),
      request=old_request,
      target=Installed(skill),
      content="stale",
    ),
    wb_input(installed=[renamed]),
  )
  assert_true(ignored == reloading)
  let (_, ready, _) = reloading.handle(
    wb_emit(),
    PreviewLoaded(
      library=Host(@interop.ChannelId::Local),
      request=next_request,
      target=Installed(renamed),
      content="fresh",
    ),
    wb_input(installed=[renamed]),
  )
  guard ready.preview is Ready(content="fresh", ..) else {
    fail("the replacement read must settle")
  }
}

///|
/// The protocol projections are package-private: the page's own tests are
/// the only caller, so they run here as whitebox tests rather than through an
/// export kept alive for a blackbox test file.
test "skill reply errors stay distinct from empty successful lists" {
  let message = "GET https://mooncakes.io/api/v0/skills returned HTTP 503"
  try catalog_from_reply(SkillsCatalogError(message)) catch {
    error => assert_eq(@interop.bridge_error_text(error), message)
  } noraise {
    _ => fail("expected a catalog reply error")
  }
  try installed_from_reply(InstalledSkillsError(message)) catch {
    error => assert_eq(@interop.bridge_error_text(error), message)
  } noraise {
    _ => fail("expected an installed skills reply error")
  }
  assert_true(catalog_from_reply(SkillsCatalog([])).is_empty())
  assert_true(
    installed_from_reply(InstalledSkills([], builtin_errors=[])).is_empty(),
  )
}

///|
test "catalog replies decode and skip odd entries" {
  let items = catalog_from_reply(
    SkillsCatalog([
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
    ]),
  )
  guard items is [item] else { fail("expected exactly one catalog item") }
  assert_eq(item.name, "acme/widget")
  assert_eq(item.module_name, "acme/widget")
  assert_eq(item.version, "1.0.0")
  assert_eq(item.description, "Build widgets fast.")
  assert_eq(source_label(item), "acme/widget@1.0.0")
}

///|
test "subpackage skills carry their package path in the source label" {
  let items = catalog_from_reply(
    SkillsCatalog([
      {
        name: "alice/alpha/cmd/run",
        module_name: "alice/alpha",
        package_path: "cmd/run",
        version: "0.2.0",
        description: "Run alpha commands",
        author: "",
        repository: "",
      },
    ]),
  )
  guard items is [item] else { fail("expected one catalog item") }
  assert_eq(source_label(item), "alice/alpha@0.2.0/cmd/run")
  assert_eq(item.author, "")
}
