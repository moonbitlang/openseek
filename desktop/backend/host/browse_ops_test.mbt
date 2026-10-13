///|
async test "folder picker creates a direct child for parent path spellings" {
  let actor = @engine.new_engine_actor("unused-test-engine")
  let endpoints = @host.endpoints(
    @host.new_host_state("unused-test-engine"),
    HostConnection(),
    actor.manager(),
    () => (),
  )
  guard endpoints
    .iter()
    .filter(endpoint => endpoint.name() == "fs.browse")
    .next()
    is Some(browse) else {
    fail("fs.browse endpoint missing")
  }
  guard endpoints
    .iter()
    .filter(endpoint => endpoint.name() == "fs.create_directory")
    .next()
    is Some(create) else {
    fail("fs.create_directory endpoint missing")
  }
  for suffix in ["", "/", "//", "/./"] {
    let dir = @fs.tmpdir(prefix="openseek-picker-create-")
    defer @fs.rmdir(dir, recursive=true)
    let listing : @protocol.BrowseDirectoryReply = @json.from_json(
      browse.invoke({ "path": dir + suffix }),
    )
    guard listing is Listing(path=parent, ..) else {
      fail("expected parent listing: \{Repr(listing)}")
    }
    let reply : @protocol.BrowseDirectoryReply = @json.from_json(
      create.invoke({ "parent": parent, "name": "icu4c" }),
    )
    guard reply is Listing(path~, entries~, ..) else {
      fail("expected created folder listing: \{Repr(reply)}")
    }
    assert_eq(Some(path), @pathx.Path(dir + "/icu4c").resolve().to_uri_path())
    assert_true(entries.is_empty())
    assert_true(@fs.kind(dir + "/icu4c") is Directory)
    for name in ["", " ", ".", "..", "../outside", "a/b", "a\\b", "icu4c"] {
      let rejected : @protocol.BrowseDirectoryReply = @json.from_json(
        create.invoke({ "parent": parent, "name": name }),
      )
      assert_true(rejected is BrowseError(_))
    }
  }
}
