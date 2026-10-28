///|
fn wb_skill(
  enabled~ : Bool,
  name~ : String = "widget",
  builtin~ : Bool = false,
) -> InstalledItem {
  {
    id: "acme-widget",
    name,
    description: "",
    source: "acme/widget@1.0.0",
    registry: Some({ module_name: "acme/widget", package_path: "", }),
    builtin,
    enabled,
  }
}

///|
fn wb_input(installed~ : Array[InstalledItem]) -> Input {
  { channel: @interop.ChannelId::Local, installed, }
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
  let (_, loading, resolution) = State::empty().open_detail(
    wb_emit(),
    wb_input(installed=[skill]),
    InstalledRef(skill.id),
  )
  assert_true(resolution is Opened)
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
      channel=@interop.ChannelId::Local,
      request~,
      target=Installed(skill),
      content="body",
    ),
    wb_input(installed=[disabled]),
  )
  guard ready.preview is Ready(content="body", ..) else {
    fail("the read issued before the toggle must still settle")
  }
  assert_true(ready.detail() == Some(InstalledRef(skill.id)))
}

///|
test "a library change to the document reloads it and drops the old read" {
  let skill = wb_skill(enabled=true)
  let (_, loading, _) = State::empty().open_detail(
    wb_emit(),
    wb_input(installed=[skill]),
    InstalledRef(skill.id),
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
      channel=@interop.ChannelId::Local,
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
      channel=@interop.ChannelId::Local,
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
test "builtin actions retain enablement and updates but never uninstall" {
  let skill = wb_skill(enabled=false, builtin=true)
  let input = wb_input(installed=[skill])
  let initial = State::empty()
  let target = installed_menu_target(input.channel, skill)
  assert_true(
    installed_menu(English, initial, input, target, wb_emit()) is None,
  )
  // Also refuse a stale menu payload whose builtin marker predates a refresh.
  for payload in [skill, { ..skill, builtin: false, }] {
    let (_, unchanged, outcome) = initial.handle(
      wb_emit(),
      Uninstall(payload),
      input,
    )
    assert_true(unchanged == initial && outcome is None)
  }
  let (_, toggling, _) = initial.handle(
    wb_emit(),
    ToggleEnabled(skill.id),
    input,
  )
  assert_true(toggling.pending_enabled(input.channel, skill.id))
  assert_true(
    toggling.busy is [{ action: SettingEnabled(enabled=true, ..), .. }],
  )
  let candidate : MarketItem = {
    name: "widget",
    module_name: "acme/widget",
    package_path: "",
    version: "1.1.0",
    description: "",
    author: "acme",
    repository: "",
  }
  let (_, available, _) = initial.handle(
    wb_emit(),
    CatalogLoaded(channel=input.channel, items=[candidate]),
    input,
  )
  guard installed_menu(English, available, input, target, wb_emit())
    is Some(menu) else {
    fail("builtin updates remain available")
  }
  guard menu.entries is [Action(action)] else {
    fail(
      "builtin menu contains just Update, without an empty separator or Uninstall",
    )
  }
  assert_eq(action.label, "Update to 1.1.0")
  assert_true(action.enabled && !action.destructive)
  let (_, updating, _) = available.handle(wb_emit(), Update(candidate), input)
  assert_true(
    updating.pending_action(input.channel, ("acme/widget", ""))
    is Some(Updating(..)),
  )
  assert_false(updating.pending_enabled(input.channel, skill.id))
}

///|
test "builtin startup errors are host-owned notices even without an installation" {
  let input = wb_input(installed=[])
  let error : @protocol.BuiltinSkillError = {
    registry: { module_name: "acme/widget", package_path: "", },
    message: "Registry offline: reload the catalog and install manually",
  }
  let initial = State::empty().with_builtin_errors(input.channel, [error])
  assert_eq(notice_views(initial, input, None).length(), 1)
  let (_, opened) = initial.opening(wb_emit(), input)
  assert_eq(notice_views(opened, input, None).length(), 1)
  let other = { ..input, channel: @interop.ChannelId::Remote("other"), }
  assert_eq(notice_views(opened, other, None).length(), 0)
  let replacement = { ..error, message: "Download failed", }
  let replaced = opened.with_builtin_errors(input.channel, [replacement])
  assert_true(
    replaced.notices
    is [BuiltinSyncFailed(error={ message: "Download failed", .. }, ..)],
  )
  assert_eq(notice_views(replaced, input, None).length(), 1)
  let cleared = replaced.with_builtin_errors(input.channel, [])
  assert_eq(notice_views(cleared, input, None).length(), 0)
}
