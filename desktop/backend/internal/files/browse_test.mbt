///|
async test "folder picker creates a direct child for parent path spellings" {
  for suffix in ["", "/", "//", "/./"] {
    let dir = @fs.tmpdir(prefix="openseek-picker-create-")
    defer @fs.rmdir(dir, recursive=true)
    let listing = @files.browse({ path: Some(dir + suffix), })
    guard listing is Listing(path=parent, ..) else {
      fail("expected parent listing: \{Repr(listing)}")
    }
    let reply = @files.create_directory({ parent, name: "icu4c", })
    guard reply is Listing(path~, entries~, ..) else {
      fail("expected created folder listing: \{Repr(reply)}")
    }
    assert_eq(Some(path), @pathx.Path(dir + "/icu4c").resolve().to_uri_path())
    assert_true(entries.is_empty())
    assert_true(@fs.kind(dir + "/icu4c") is Directory)
    for name in ["", " ", ".", "..", "../outside", "a/b", "a\\b", "icu4c"] {
      assert_true(@files.create_directory({ parent, name, }) is BrowseError(_))
    }
  }
}
