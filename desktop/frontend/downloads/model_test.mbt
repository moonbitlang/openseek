///|
fn loading() -> @downloads.Model {
  let (_, model) = @downloads.Model().load(@cmd.Emit(_ => @cmd.none))
  model
}

///|
test "a manifest lists installers in platform order and keeps its release page" {
  let body =
    #|{"version":"0.3.1","url":"https://example.com/r/0.3.1","platforms":{
    #|  "linux-x64":{"url":"https://example.com/linux.tar.gz"},
    #|  "freebsd-x64":{"url":"https://example.com/bsd.tar.gz"},
    #|  "browser":{"url":"https://example.com/console.tar.gz"},
    #|  "macos-arm64":{"url":"https://example.com/mac.tar.gz"},
    #|  "macos-arm64-dmg":{"url":"https://example.com/mac.dmg"},
    #|  "windows-x64":{"signature":"only"}
    #|}}
  let model = loading()
  let model = model.update(
    Fetched(generation=model.generation, status=200, body~),
  )
  guard model.release is Ready(version~, page_url~, targets~) else {
    fail("expected a ready release")
  }
  assert_eq(version, "0.3.1")
  assert_eq(page_url, "https://example.com/r/0.3.1")
  assert_eq(targets.map(target => (target.label, target.url)), [
    ("macOS · Apple Silicon", "https://example.com/mac.dmg"),
    ("Linux · x64", "https://example.com/linux.tar.gz"),
    ("freebsd-x64", "https://example.com/bsd.tar.gz"),
  ])
}

///|
test "a missing or malformed manifest falls back to the GitHub releases" {
  let model = loading()
  let generation = model.generation
  assert_true(
    model.update(Fetched(generation~, status=404, body="")).release
    is Unavailable,
  )
  assert_true(
    model.update(Fetched(generation~, status=200, body="{}")).release
    is Unavailable,
  )
  assert_true(model.update(FetchFailed(generation~)).release is Unavailable)
}

///|
test "a reply from an earlier fetch leaves the current one loading" {
  let first = loading()
  let (_, second) = first.load(@cmd.Emit(_ => @cmd.none))
  let body =
    #|{"version":"0.3.1","platforms":{}}
  let next = second.update(
    Fetched(generation=first.generation, status=200, body~),
  )
  assert_true(next.release is Loading)
}

///|
test "the dialog reuses a loaded list and retries an unreadable one" {
  let emit : @cmd.Emit[@downloads.Msg] = @cmd.Emit(_ => @cmd.none)
  let model = loading()
  let body =
    #|{"version":"0.3.1","platforms":{}}
  let ready = model.update(
    Fetched(generation=model.generation, status=200, body~),
  )
  let (_, reopened) = ready.open(emit)
  assert_true(reopened == ready)
  let failed = model.update(FetchFailed(generation=model.generation))
  let (_, retried) = failed.open(emit)
  assert_true(retried.release is Loading)
  assert_true(retried.generation > failed.generation)
}
