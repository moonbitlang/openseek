///|
test "enablement-only refresh preserves an open preview and its pending read" {
  let skill = test_skill(enabled=true)
  let (_, loading, _) = State::empty().handle(
    test_emit(),
    PreviewInstalled(skill),
    test_input(installed=[skill]),
  )
  let request = test_pending_request(loading.preview)
  let disabled = test_skill(enabled=false)
  let (_, unchanged) = loading.sync_library(
    test_emit(),
    test_input(installed=[disabled]),
  )
  // The live mirror says disabled, but the document and the read it owns are
  // unchanged; renderers take enablement from the mirror, not from this target.
  assert_true(unchanged == loading)
  let (_, ready, _) = unchanged.handle(
    test_emit(),
    PreviewLoaded(
      channel=@interop.ChannelId::Local,
      request~,
      target=Installed(skill),
      content="body",
    ),
    test_input(installed=[disabled]),
  )
  guard ready.preview is Ready(content="body", ..) else {
    fail("the read issued before the toggle must still settle")
  }
  assert_true(ready.detail_open(@interop.ChannelId::Local))
}

///|
test "a library change to the document reloads it and drops the old read" {
  let skill = test_skill(enabled=true)
  let (_, loading, _) = State::empty().handle(
    test_emit(),
    PreviewInstalled(skill),
    test_input(installed=[skill]),
  )
  let old_request = test_pending_request(loading.preview)
  let renamed = test_skill(enabled=true, name="renamed")
  let (_, reloading) = loading.sync_library(
    test_emit(),
    test_input(installed=[renamed]),
  )
  let next_request = test_pending_request(reloading.preview)
  assert_eq(next_request, old_request + 1)
  // A reply for the pre-change snapshot is stale by target and by request.
  let (_, ignored, _) = reloading.handle(
    test_emit(),
    PreviewLoaded(
      channel=@interop.ChannelId::Local,
      request=old_request,
      target=Installed(skill),
      content="stale",
    ),
    test_input(installed=[renamed]),
  )
  assert_true(ignored == reloading)
  let (_, ready, _) = reloading.handle(
    test_emit(),
    PreviewLoaded(
      channel=@interop.ChannelId::Local,
      request=next_request,
      target=Installed(renamed),
      content="fresh",
    ),
    test_input(installed=[renamed]),
  )
  guard ready.preview is Ready(content="fresh", ..) else {
    fail("the replacement read must settle")
  }
}
