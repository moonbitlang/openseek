///|
fn wb_skill(enabled~ : Bool, name~ : String = "widget") -> InstalledItem {
  {
    id: "acme-widget",
    name,
    description: "",
    source: "acme/widget@1.0.0",
    registry: Some({ module_name: "acme/widget", package_path: "", }),
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
