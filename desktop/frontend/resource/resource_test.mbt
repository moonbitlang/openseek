///|
test "channel resources use URI paths without browser filesystem conversion" {
  guard @resource.of_path(Remote("windows"), "/C:/work/a #.mbt") is Some(uri) else {
    fail("expected a Windows-drive resource URI")
  }
  assert_eq(uri.scheme, @resource.Scheme)
  assert_eq(uri.authority, "remote.windows")
  assert_eq(uri.path, "/c:/work/a #.mbt")
  assert_eq(uri.to_string(), "openseek://remote.windows/c%3A/work/a%20%23.mbt")
  assert_eq(@common.Uri::parse(uri.to_string()), uri)
}

///|
test "resource construction rejects relative and UNC transport paths" {
  let channel = @interop.ChannelId::Remote("device")
  assert_true(@resource.of_path(channel, "work/a.mbt") is None)
  assert_true(@resource.of_path(channel, "//server/share/a.mbt") is None)
}

///|
test "resource operations retain channel identity" {
  let local_channel : @interop.ChannelId = Local
  let remote : @interop.ChannelId = Remote("device")
  guard @resource.of_path(local_channel, "/work") is Some(root) &&
    @resource.of_path(local_channel, "/work/src/a.mbt") is Some(file) &&
    @resource.of_path(remote, "/work/src/a.mbt") is Some(foreign) else {
    fail("expected resource fixtures")
  }
  assert_true(@resource.contains(root, file))
  assert_false(@resource.contains(root, foreign))
  assert_eq(@resource.relative_to(file, root), Some(Relative("src/a.mbt")))
  assert_true(@resource.relative_to(foreign, root) is None)
  assert_eq(
    @resource.join_relative(root, Relative("src/../moon.mod")).path,
    "/work/moon.mod",
  )
  assert_eq(@resource.path_for(file, local_channel), Some("/work/src/a.mbt"))
  assert_true(@resource.path_for(file, remote) is None)
}

///|
test "Cloud resource identity binds origin, account and session without a Host channel" {
  let root = @resource.cloud_root("https://cloud.example", "Account", "session").unwrap()
  let file = @resource.join_relative(root, Relative("src/a #.mbt"))
  assert_true(@resource.channel(file) is None)
  assert_eq(@resource.relative_to(file, root), Some(Relative("src/a #.mbt")))
  assert_eq(@common.Uri::parse(file.to_string()), file)
  for
    other in [
      @resource.cloud_root("https://other.example", "Account", "session").unwrap(),
      @resource.cloud_root("https://cloud.example", "account", "session").unwrap(),
      @resource.cloud_root("https://cloud.example", "Account", "other").unwrap(),
    ] {
    assert_false(@resource.contains(other, file))
  }
  assert_false(@resource.contains(@resource.of_path(Local, "/").unwrap(), file))
}
