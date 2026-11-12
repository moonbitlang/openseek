///|
fn opened() -> @download_dialog.Model {
  let (_, model) = @download_dialog.Model().open(@cmd.Emit(_ => @cmd.none))
  model
}

///|
test "a manifest lists installers in platform order and keeps its release page" {
  let body =
    #|{"version":"0.3.1","url":"https://example.com/r/0.3.1","platforms":{
    #|  "linux-x64":{"url":"https://example.com/linux.tar.gz"},
    #|  "freebsd-x64":{"url":"https://example.com/bsd.tar.gz"},
    #|  "macos-arm64":{"url":"https://example.com/mac.tar.gz"},
    #|  "macos-arm64-dmg":{"url":"https://example.com/mac.dmg"},
    #|  "windows-x64":{"signature":"only"}
    #|}}
  let model = opened()
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
  let model = opened()
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
test "a reply from an earlier opening leaves the current one loading" {
  let first = opened()
  let (_, second) = first.open(@cmd.Emit(_ => @cmd.none))
  let body =
    #|{"version":"0.3.1","platforms":{}}
  let next = second.update(
    Fetched(generation=first.generation, status=200, body~),
  )
  assert_true(next.release is Loading)
}
