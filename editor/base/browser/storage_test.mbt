///|
extern "js" fn install_storage(mode : String) -> () -> Unit =
  #| mode => {
  #|   const previous = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  #|   const values = new Map();
  #|   const fail = () => { throw new Error('storage denied'); };
  #|   const storage = {
  #|     getItem: key => mode === 'read-failure' ? fail() : values.get(key) ?? null,
  #|     setItem: (key, value) => mode === 'write-failure' ? fail() : values.set(key, value),
  #|     removeItem: key => mode === 'write-failure' ? fail() : values.delete(key),
  #|   };
  #|   Object.defineProperty(globalThis, 'localStorage', { configurable: true,
  #|     get: () => mode === 'denied' ? fail() : mode === 'missing' ? undefined : storage });
  #|   return () => {
  #|     if (previous) Object.defineProperty(globalThis, 'localStorage', previous);
  #|     else delete globalThis.localStorage;
  #|   };
  #| }

///|
test "storage preserves absent, empty, and removed values" {
  let restore = install_storage("normal")
  defer restore()
  assert_true(@browser.local_storage_get("theme") is Ok(None))
  assert_true(@browser.local_storage_set("theme", "") is Ok(_))
  assert_true(@browser.local_storage_get("theme") is Ok(Some("")))
  assert_true(@browser.local_storage_set("theme", "dark") is Ok(_))
  assert_true(@browser.local_storage_get("theme") is Ok(Some("dark")))
  assert_true(@browser.local_storage_remove("theme") is Ok(_))
  assert_true(@browser.local_storage_get("theme") is Ok(None))
}

///|
test "storage unavailable and denied are failures rather than missing keys" {
  for mode in ["missing", "denied", "read-failure"] {
    let restore = install_storage(mode)
    defer restore()
    match @browser.local_storage_get("theme") {
      Err(Unavailable) => assert_eq(mode, "missing")
      Err(AccessFailed(message)) =>
        assert_true(message.contains("storage denied"))
      Ok(_) => fail("expected a storage failure")
    }
  }
}

///|
test "storage write and remove failures remain observable" {
  let restore = install_storage("write-failure")
  defer restore()
  assert_true(
    @browser.local_storage_set("theme", "dark") is Err(AccessFailed(_)),
  )
  assert_true(@browser.local_storage_remove("theme") is Err(AccessFailed(_)))
}

///|
test "URL resolution normalizes relative links and reports invalid URLs" {
  assert_true(
    @browser.resolve_url("../a", base="https://example.com/docs/b")
    is Ok(("https://example.com/a", "https:")),
  )
  assert_true(
    @browser.resolve_url("mailto:test@example.com")
    is Ok(("mailto:test@example.com", "mailto:")),
  )
  assert_true(@browser.resolve_url("http://[") is Err(_))
  assert_true(@browser.resolve_url("relative") is Err(_))
}
