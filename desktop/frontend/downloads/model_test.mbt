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
  guard @downloads.Model::update(Fetched(status=200, body~))
    is Ready(version~, page_url~, targets~) else {
    fail("expected a ready release")
  }
  assert_eq(version, "0.3.1")
  assert_eq(page_url, "https://example.com/r/0.3.1")
  assert_eq(targets.map(target => (target.os, target.label, target.url)), [
    (MacOS, "macOS · Apple Silicon", "https://example.com/mac.dmg"),
    (Linux, "Linux · x64", "https://example.com/linux.tar.gz"),
  ])
}

///|
test "a missing or malformed manifest falls back to the GitHub releases" {
  assert_true(
    @downloads.Model::update(Fetched(status=404, body="")) is Unavailable,
  )
  assert_true(
    @downloads.Model::update(Fetched(status=200, body="{}")) is Unavailable,
  )
  assert_true(@downloads.Model::update(FetchFailed) is Unavailable)
}

///|
test "the dialog reuses a loaded list and retries an unreadable one" {
  let body =
    #|{"version":"0.3.1","url":"https://example.com/r","platforms":{}}
  let ready = @downloads.Model::update(Fetched(status=200, body~))
  let (_, reopened) = ready.open(@cmd.none)
  assert_true(reopened == ready)
  let (_, retried) = @downloads.Model::update(FetchFailed).open(@cmd.none)
  assert_true(retried is Loading)
}
