///|
fn cache_test_scope(session : String, root : String) -> SourceModelScope {
  {
    owner: { channel: Local, session, },
    root: Some(try! @common.Uri::parse(root)),
  }
}

///|
fn cache_test_acquire(
  cache : SourceModelCache,
  scope : SourceModelScope,
  path : String,
  content : String,
) -> SourceModelLease {
  let uri = try! @common.Uri::parse(path)
  cache.acquire(scope, uri, uri, content, () => {
    @model.TextModel(uri, "cache.js", "plaintext", 1, "cache", content)
  })
}

///|
test "source cache reuses identity only within owner resource and current content" {
  let cache = SourceModelCache()
  let scope = cache_test_scope("one", "memory://host/root")
  let a = cache_test_acquire(
    cache, scope, "memory://host/root/a.js", "one\r\ntwo",
  )
  let id = a.model.identity()
  let version = a.model.get_version_id()
  a.dispose()
  let b = cache_test_acquire(cache, scope, "memory://host/root/b.js", "other")
  b.dispose()
  let again = cache_test_acquire(
    cache, scope, "memory://host/root/a.js", "one\r\ntwo",
  )
  assert_eq(again.model.identity(), id)
  assert_eq(again.model.get_version_id(), version)
  again.dispose()
  let changed = cache_test_acquire(
    cache, scope, "memory://host/root/a.js", "changed",
  )
  assert_eq(changed.model.identity(), id)
  assert_true(changed.model.get_version_id() > version)
  assert_eq(changed.model.get_value(), "changed")
  changed.dispose()
  let different = cache_test_acquire(
    cache, scope, "memory://host/other/a.js", "changed",
  )
  assert_true(different.model.identity() != id)
  different.dispose()
  let new_owner = cache_test_acquire(
    cache,
    cache_test_scope("two", "memory://host/root"),
    "memory://host/root/a.js",
    "changed",
  )
  assert_true(new_owner.model.identity() != id)
  assert_true(a.model.is_disposed())
  new_owner.dispose()
  cache.clear()
  assert_true(new_owner.model.is_disposed())
}

///|
test "source cache evicts idle entries but retires borrowed models after the last lease" {
  let cache = SourceModelCache(max_entries=1, max_bytes=1)
  let scope = cache_test_scope("one", "memory://host/root")
  let a = cache_test_acquire(cache, scope, "memory://host/root/a.js", "first")
  let second_lease = cache_test_acquire(
    cache, scope, "memory://host/root/a.js", "first",
  )
  let b = cache_test_acquire(cache, scope, "memory://host/root/b.js", "second")
  assert_false(a.model.is_disposed())
  assert_false(b.model.is_disposed())
  cache.retire_document(a.model.uri)
  a.dispose()
  a.dispose()
  assert_false(second_lease.model.is_disposed())
  second_lease.dispose()
  assert_true(a.model.is_disposed())
  assert_false(b.model.is_disposed())
  b.dispose()
  assert_true(b.model.is_disposed())
  assert_eq(cache.entries.length(), 0)
}
