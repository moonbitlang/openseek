///|
#skip("Requires browser IndexedDB; desktop/e2e/tests/indexeddb.spec.js runs these contracts in real browsers.")
async test "committed JSON values distinguish missing records from null" {
  let db = @indexeddb.open("indexeddb-contract-values", 1, upgrade=(db, _, _) => {
    ignore(db.create_store("values"))
  })
  defer db.close()
  let write = db.transaction(["values"], ReadWrite)
  let store = write.store("values")
  ignore(store.put(Json::null(), key=String("null")))
  ignore(store.put({ "text": "saved" }, key=Number(7)))
  write.wait()
  let read = db.transaction(["values"], ReadOnly)
  let store = read.store("values")
  let missing = store.get(String("missing"))
  let null_value = store.get(String("null"))
  let record = store.get(Number(7))
  read.wait()
  assert_eq(missing.result(), None)
  assert_eq(null_value.result(), Some(Json::null()))
  assert_eq(record.result(), Some({ "text": "saved" }))
  let deletion = db.transaction(["values"], ReadWrite)
  ignore(deletion.store("values").delete(Number(7)))
  deletion.wait()
  let verify = db.transaction(["values"], ReadOnly)
  let gone = verify.store("values").get(Number(7))
  verify.wait()
  assert_eq(gone.result(), None)
}

///|
#skip("Requires browser IndexedDB; run through the browser contract suite.")
async test "schema upgrades retain data and compound indexes isolate deletion" {
  let first = @indexeddb.open("indexeddb-contract-upgrade", 1, upgrade=(
    db,
    _,
    old,
  ) => {
    assert_eq(old, 0)
    ignore(db.create_store("records", key_path=Field("id")))
  })
  let write = first.transaction(["records"], ReadWrite)
  let store = write.store("records")
  ignore(store.put({ "id": 1, "origin": "one", "user": "a" }))
  ignore(store.put({ "id": 2, "origin": "one", "user": "a" }))
  ignore(store.put({ "id": 3, "origin": "two", "user": "a" }))
  write.wait()
  first.close()
  let upgraded = @indexeddb.open("indexeddb-contract-upgrade", 2, upgrade=(
    _,
    tx,
    old,
  ) => {
    assert_eq(old, 1)
    ignore(
      tx.store("records").create_index("by_account", Fields(["origin", "user"])),
    )
  })
  defer upgraded.close()
  let read = upgraded.transaction(["records"], ReadOnly)
  let cannot_delete = try {
    ignore(read.store("records").index("by_account").delete_all())
    false
  } catch {
    @indexeddb.IndexedDBError(name="ReadOnlyError", ..) => true
    _ => false
  }
  assert_true(cannot_delete)
  let records = read
    .store("records")
    .index("by_account")
    .get_all(key=Array([String("one"), String("a")]))
  read.wait()
  assert_eq(
    records.result(),
    Some([
      { "id": 1, "origin": "one", "user": "a" },
      { "id": 2, "origin": "one", "user": "a" },
    ]),
  )
  let deletion = upgraded.transaction(["records"], ReadWrite)
  ignore(
    deletion
    .store("records")
    .index("by_account")
    .delete_all(key=Array([String("one"), String("a")])),
  )
  deletion.wait()
  let verify = upgraded.transaction(["records"], ReadOnly)
  let remaining = verify.store("records").index("by_account").get_all()
  verify.wait()
  assert_eq(
    remaining.result(),
    Some([{ "id": 3, "origin": "two", "user": "a" }]),
  )
}

///|
#skip("Requires browser IndexedDB; run through the browser contract suite.")
async test "aborted transactions roll back and report failure instead of missing data" {
  let db = @indexeddb.open("indexeddb-contract-abort", 1, upgrade=(db, _, _) => {
    ignore(db.create_store("values"))
  })
  defer db.close()
  let write = db.transaction(["values"], ReadWrite)
  ignore(write.store("values").put(Json(42), key=String("cancelled")))
  write.abort()
  let failed = try {
    write.wait()
    false
  } catch {
    @indexeddb.IndexedDBError(name="AbortError", ..) => true
    _ => false
  }
  assert_true(failed)
  let read = db.transaction(["values"], ReadOnly)
  let value = read.store("values").get(String("cancelled"))
  let unfinished = try {
    ignore(value.result())
    false
  } catch {
    @indexeddb.IndexedDBError(name="InvalidStateError", ..) => true
    _ => false
  }
  assert_true(unfinished)
  read.wait()
  assert_eq(value.result(), None)
  let read_only = db.transaction(["values"], ReadOnly)
  let rejected = try {
    ignore(read_only.store("values").put(Json(42), key=String("forbidden")))
    false
  } catch {
    @indexeddb.IndexedDBError(name="ReadOnlyError", ..) => true
    _ => false
  }
  assert_true(rejected)
  read_only.wait()
}

///|
priv suberror UpgradeRejected

///|
#skip("Requires browser IndexedDB; run through the browser contract suite.")
async test "a rejected schema upgrade preserves the callback error and can be retried" {
  let failed = try {
    ignore(
      @indexeddb.open("indexeddb-contract-reject", 1, upgrade=(db, _, _) => {
        ignore(db.create_store("incomplete"))
        raise UpgradeRejected
      }),
    )
    false
  } catch {
    UpgradeRejected => true
    _ => false
  }
  assert_true(failed)
  let db = @async.with_timeout(1000, () => {
    @indexeddb.open("indexeddb-contract-reject", 1, upgrade=(db, _, _) => {
      ignore(db.create_store("complete"))
    })
  })
  defer db.close()
  let read = db.transaction(["complete"], ReadOnly)
  read.wait()
}

///|
#external
priv type BlockingConnection

///|
extern "js" fn blocking_connection(
  name : String,
) -> @js_async.Promise[BlockingConnection] =
  #| name => new Promise((resolve, reject) => {
  #|   const request = indexedDB.open(name, 1);
  #|   request.onerror = () => reject(request.error);
  #|   request.onsuccess = () => resolve(request.result);
  #| })

///|
extern "js" fn BlockingConnection::close(self : BlockingConnection) -> Unit =
  #| db => db.close()

///|
#skip("Requires browser IndexedDB; run through the browser contract suite.")
async test "a blocked open cannot apply a late schema upgrade or leak its connection" {
  let blocker = blocking_connection("indexeddb-contract-blocked").wait()
  defer blocker.close()
  let mut late_upgrade = false
  let blocked = try {
    ignore(
      @indexeddb.open("indexeddb-contract-blocked", 2, upgrade=(_, _, _) => {
        late_upgrade = true
      }),
    )
    false
  } catch {
    @indexeddb.IndexedDBError(name="BlockedError", ..) => true
    _ => false
  }
  assert_true(blocked)
  blocker.close()
  let db = @async.with_timeout(1000, () => {
    @indexeddb.open("indexeddb-contract-blocked", 2, upgrade=(db, _, old) => {
      assert_eq(old, 1)
      ignore(db.create_store("valid"))
    })
  })
  defer db.close()
  assert_false(late_upgrade)
  let tx = db.transaction(["valid"], ReadOnly)
  tx.wait()
}
