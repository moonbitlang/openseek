///|
async test "cached_listing_prompt invalidates when file size changes within the same timestamp" {
  let dir = @fs.tmpdir(prefix="openseek-listing-cache-size-")
  defer @fs.remove(dir, recursive=true)
  let store = @store.SessionStore(dir + "/.openseek")
  let id = @agent_session.SessionId("size-check")
  let session = @agent_session.Session(id, system_prompt="")
  store.create(session.append(User(UserMessage(Content([Text("Updated")])))))
  let path = store.session_file(id)
  let mtime = file_stamp(@fs.mtime(path))
  let ctime = file_stamp(@fs.ctime(path))
  let size = @fs.file_size(path)
  let identity = file_identity(path)
  if !(@async.platform is Linux) {
    assert_eq(identity, None)
  }
  let cache : Map[String, CachedListingPrompt] = Map([])
  cache[path] = { mtime, ctime, size: size - 1L, identity, text: "Stale", }
  assert_eq(cached_listing_prompt(cache, path, Some(mtime)), Some("Updated"))
  assert_eq(
    cache.get(path).map(entry => (entry.size, entry.text)),
    Some((size, "Updated")),
  )
}

///|
#cfg(platform="linux")
async test "cached_listing_prompt invalidates when Linux file identity changes within the same timestamp and size" {
  let dir = @fs.tmpdir(prefix="openseek-listing-cache-inode-")
  defer @fs.remove(dir, recursive=true)
  let store = @store.SessionStore(dir + "/.openseek")
  let id = @agent_session.SessionId("inode-check")
  let session = @agent_session.Session(id, system_prompt="")
  store.create(session.append(User(UserMessage(Content([Text("Before")])))))
  let path = store.session_file(id)
  guard file_identity(path) is Some((dev, ino)) else {
    fail("expected Linux file identity")
  }
  store.create(session.append(User(UserMessage(Content([Text("After!")])))))
  let after_identity = file_identity(path)
  assert_true(after_identity is Some(_))
  assert_not_eq(after_identity, Some((dev, ino)))
  let mtime = file_stamp(@fs.mtime(path))
  let ctime = file_stamp(@fs.ctime(path))
  let size = @fs.file_size(path)
  let cache : Map[String, CachedListingPrompt] = Map([])
  cache[path] = {
    mtime,
    ctime,
    size,
    identity: Some((dev, ino)),
    text: "Before",
  }
  assert_eq(cached_listing_prompt(cache, path, Some(mtime)), Some("After!"))
  assert_eq(
    cache.get(path).map(entry => (entry.identity, entry.text)),
    Some((after_identity, "After!")),
  )
}
