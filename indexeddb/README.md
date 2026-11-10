# moonbitlang/indexeddb

IndexedDB transactions and JSON storage for browser-based MoonBit applications.
The module targets JavaScript and depends only on MoonBit core and async. It
contains no application-specific database names, schemas, account policy,
authentication, retry, timeout, or cache behavior.

## Example

```mbt
let db = @indexeddb.open("notes", 1, upgrade=(db, _, previous) => {
  if previous == 0 {
    let notes = db.create_store("notes", key_path=Field("id"))
    ignore(notes.create_index("by_owner", Field("owner")))
  }
})
defer db.close()
let write = db.transaction(["notes"], ReadWrite)
ignore(write.store("notes").put({ "id": "welcome", "owner": "alice", "text": "Hello" }))
write.wait()
let read = db.transaction(["notes"], ReadOnly)
let request = read.store("notes").get(String("welcome"))
read.wait()
let note = request.result()
```

Use these calls inside an async function. Issue requests synchronously while a
transaction is active, then await `Transaction::wait` before reading results.
An aborted transaction raises `IndexedDBError`; it does not appear as an empty
result. Missing records return `None`, while stored JSON null returns
`Some(Json::null())`. Exceptions retain the browser error name and message.
Abort a transaction explicitly if the caller abandons it. Transaction activity
follows the [IndexedDB transaction lifecycle](https://w3c.github.io/IndexedDB/#transaction-lifecycle).

`Key` supports JSON-compatible string, numeric and compound array keys. Values
are JSON data; blobs, dates, binary keys and arbitrary structured-clone values
are outside this initial interface. Schema upgrades receive the database,
upgrade transaction and previous version. Connections close automatically on a
version change. A blocked open raises `BlockedError`; callers decide whether
to retry. Cancellation closes any late connection.

## Validation

The public-interface tests in `indexeddb_test.mbt` require real IndexedDB. They
are marked skipped in Node and executed by the repository's Chromium and WebKit
contract suite using the same compiled MoonBit tests:

```sh
moon check indexeddb --target js --deny-warn
moon test indexeddb --target js --build-only --include-skipped
cd desktop/e2e
npx playwright test indexeddb.spec.js
```

The browser suite uses the existing repository test server. See
[repository browser-test guidance](https://github.com/moonbitlang/openseek/blob/main/desktop/e2e/README.md) for browser installation and
frontend build prerequisites. `just desktop-test-browser` also builds these
contracts before running the suite.
