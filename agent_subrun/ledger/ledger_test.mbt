///|
async test "allocations are consecutive and survive a restart, used or not" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  // The session's directory need not exist yet.
  let path = "\{dir}/sessions/p/subagents.jsonl"
  guard @ledger.Ledger::open(path, floor=1) is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  assert_eq(ledger.allocate(count=1, owner="engine"), 1)
  // A workflow's block: nothing has to use it for it to be taken.
  assert_eq(ledger.allocate(count=32, owner="workflow"), 2)
  assert_eq(ledger.allocate(count=1, owner="engine"), 34)
  ledger.close()
  // The engine is gone; no child session was ever created. A floor from
  // scanning sessions would say 1.
  guard @ledger.Ledger::open(path, floor=1) is Some(reopened) else {
    fail("the ledger must open again once its owner is gone")
  }
  assert_eq(reopened.allocate(count=1, owner="engine"), 35)
  reopened.close()
}

///|
async test "the floor wins when other evidence is ahead of the ledger" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/subagents.jsonl"
  // A session that already had children before it had a ledger.
  guard @ledger.Ledger::open(path, floor=8) is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  assert_eq(ledger.allocate(count=1, owner="engine"), 8)
  ledger.close()
  // And the ledger wins when it is ahead of the floor.
  guard @ledger.Ledger::open(path, floor=3) is Some(reopened) else {
    fail("the ledger must open again")
  }
  assert_eq(reopened.allocate(count=1, owner="engine"), 9)
  reopened.close()
}

///|
async test "a second owner is refused while the first lives" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/subagents.jsonl"
  guard @ledger.Ledger::open(path, floor=1) is Some(first) else {
    fail("a fresh ledger must open")
  }
  assert_true(@ledger.Ledger::open(path, floor=1) is None)
  // The refused attempt took nothing: the owner still allocates.
  assert_eq(first.allocate(count=1, owner="engine"), 1)
  first.close()
  // The lock file is still there. Its existence is not ownership.
  assert_true(@fs.exists("\{dir}/subagents.lock"))
  guard @ledger.Ledger::open(path, floor=1) is Some(second) else {
    fail("ownership must be free once the owner closed")
  }
  assert_eq(second.allocate(count=1, owner="engine"), 2)
  second.close()
}

///|
async test "a torn tail costs only itself" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/subagents.jsonl"
  guard @ledger.Ledger::open(path, floor=1) is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  assert_eq(ledger.allocate(count=4, owner="workflow"), 1)
  ledger.close()
  // A write that died part-way, inside a multi-byte character. No id was
  // returned for it, so what it would have allocated is still free.
  let file = @fs.open(path, mode=WriteOnly, append=true)
  file.write(
    b"{\"event\":\"allocated\",\"first\":5,\"count\":32,\"owner\":\"caf\xc3",
  )
  file.close()
  guard @ledger.Ledger::open(path, floor=1) is Some(reopened) else {
    fail("a ledger with a torn tail must still open")
  }
  assert_eq(reopened.allocate(count=1, owner="engine"), 5)
  reopened.close()
  // The record written after the torn tail is intact and counted.
  guard @ledger.Ledger::open(path, floor=1) is Some(again) else {
    fail("the ledger must open again")
  }
  assert_eq(again.allocate(count=1, owner="engine"), 6)
  again.close()
}

///|
async test "concurrent allocations in one process do not overlap" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  guard @ledger.Ledger::open("\{dir}/subagents.jsonl", floor=1) is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  let firsts : Array[Int] = []
  @async.with_task_group(group => {
    for _ in 0..<8 {
      group.spawn_bg(() => firsts.push(ledger.allocate(count=3, owner="x")))
    }
  })
  firsts.sort()
  assert_eq(firsts, [1, 4, 7, 10, 13, 16, 19, 22])
  ledger.close()
}

///|
/// Ownership must outlast an allocation that has chosen its ordinal and is
/// still writing. The allocation is held mid-flight here — inside its
/// directory sync, after the record is written and before the id is
/// returned — and while it is, a close stays pending and another opener
/// stays refused. A close that merely flagged the ledger and unlocked at
/// once would let that opener in and hand out the same ordinal.
async test "close stays pending while an allocation is in flight" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/subagents.jsonl"
  let mut in_flight = false
  let mut release = false
  guard @ledger.Ledger::open(path, floor=1, sync_dir=_ => {
      in_flight = true
      while !release {
        @async.sleep(2)
      }
    })
    is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  let allocated : Array[Int] = []
  let mut closed = false
  @async.with_task_group(group => {
    group.spawn_bg(() => allocated.push(ledger.allocate(count=1, owner="a")))
    while !in_flight {
      @async.sleep(2)
    }
    group.spawn_bg(() => {
      ledger.close()
      closed = true
    })
    // Long enough for a close that did not wait to have finished.
    @async.sleep(60)
    assert_false(closed)
    assert_eq(allocated, [])
    assert_true(@ledger.Ledger::open(path, floor=1) is None)
    release = true
  })
  assert_eq(allocated, [1])
  assert_true(closed)
  // Closed: nothing more from this ledger, and closing again is harmless.
  try ledger.allocate(count=1, owner="late") catch {
    error => assert_true("\{error}".contains("closed"))
  } noraise {
    _ => fail("a closed ledger must not allocate")
  }
  ledger.close()
  // The next owner sees exactly the one allocation that was returned.
  guard @ledger.Ledger::open(path, floor=1) is Some(next) else {
    fail("ownership must be free once the owner closed")
  }
  assert_eq(next.allocate(count=1, owner="b"), 2)
  next.close()
}

///|
/// The first allocation creates the ledger file and then fails before the
/// directories that hold it are synced. No id escapes that failure, and the
/// retry — on the same ledger, with the file now already there — still owes
/// the whole chain and syncs all of it before it returns an id.
async test "a first allocation that fails after creating the file leaves the sync owed" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/sessions/p/subagents.jsonl"
  let chain = ["\{dir}/sessions/p", "\{dir}/sessions", dir]
  let synced : Array[String] = []
  let mut failing = true
  guard @ledger.Ledger::open(path, floor=1, dirs=chain, sync_dir=d => {
      // The first attempt dies part-way down the chain.
      if failing && d == chain[1] {
        fail("power is about to go")
      }
      synced.push(d)
    })
    is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  assert_false(@fs.exists(path))
  let escaped = try ledger.allocate(count=3, owner="workflow") catch {
    _ => None
  } noraise {
    first => Some(first)
  }
  assert_true(escaped is None)
  // The file was created and its record written; only the innermost
  // directory was synced before the failure.
  assert_true(@fs.exists(path))
  assert_eq(synced, [chain[0]])
  failing = false
  synced.clear()
  // The retry is offered the same ordinals, and completes the full chain —
  // not just the part the failed attempt had not reached — before returning.
  assert_eq(ledger.allocate(count=3, owner="workflow"), 1)
  assert_eq(synced, chain)
  assert_eq(ledger.allocate(count=1, owner="engine"), 4)
  assert_eq(synced, chain)
  ledger.close()
  // The record the failed attempt left behind is counted like any other: it
  // names ordinals nobody was given, and the next owner starts past them.
  guard @ledger.Ledger::open(path, floor=1) is Some(reopened) else {
    fail("the ledger must open again")
  }
  assert_eq(reopened.allocate(count=1, owner="engine"), 5)
  reopened.close()
}

///|
/// The ledger file's directory entry is made durable before the first id
/// this process hands out — whoever created the file. A file left behind by
/// an attempt that died before syncing was made durable by nobody.
async test "the directory chain is synced with the first record, once" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/sessions/p/subagents.jsonl"
  let chain = ["\{dir}/sessions/p", "\{dir}/sessions", dir]
  let synced : Array[String] = []
  // What an earlier attempt that created the file and then died leaves.
  @fs.mkdir("\{dir}/sessions/p", recursive=true)
  @fs.write_file(path, "", create_mode=CreateNew)
  guard @ledger.Ledger::open(path, floor=1, dirs=chain, sync_dir=d => {
      synced.push(d)
    })
    is Some(ledger) else {
    fail("the ledger must open")
  }
  // Opening allocates nothing and syncs nothing.
  assert_eq(synced, [])
  assert_eq(ledger.allocate(count=1, owner="engine"), 1)
  assert_eq(synced, chain)
  assert_eq(ledger.allocate(count=1, owner="engine"), 2)
  assert_eq(synced, chain)
  ledger.close()
}

///|
/// A record that cannot be written returns no id, and the retry is offered
/// the same ordinal — with the directory sync still owed, because the failed
/// attempt never got that far.
#cfg(not(platform="windows"))
async test "a failed write returns no id and the retry starts clean" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/subagents.jsonl"
  let synced : Array[String] = []
  guard @ledger.Ledger::open(path, floor=1, sync_dir=d => synced.push(d))
    is Some(ledger) else {
    fail("a fresh ledger must open")
  }
  assert_eq(ledger.allocate(count=1, owner="engine"), 1)
  assert_eq(synced, [dir])
  // The ledger turns read-only under its owner: the append cannot open it.
  @fs.chmod(path, 0o444)
  let refused = try ledger.allocate(count=4, owner="workflow") catch {
    _ => true
  } noraise {
    _ => false
  }
  @fs.chmod(path, 0o644)
  guard refused else {
    // Running as a user the mode does not bind (root): nothing to observe.
    println("skipped: a read-only file is still writable here")
    ledger.close()
    return
  }
  // Nothing was allocated by the failure: the same ordinals come next.
  assert_eq(ledger.allocate(count=4, owner="workflow"), 2)
  ledger.close()
  guard @ledger.Ledger::open(path, floor=1) is Some(reopened) else {
    fail("the ledger must open again")
  }
  assert_eq(reopened.allocate(count=1, owner="engine"), 6)
  reopened.close()
}

///|
/// Ownership is the kernel's lock, held by a PROCESS: another process that
/// holds it refuses us, and when that process dies without cleaning up, the
/// lock file stays and ownership is free.
#cfg(not(platform="windows"))
async test "another process's lock refuses us until that process is gone" {
  let dir = @fs.tmpdir(prefix="openseek-ledger-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/subagents.jsonl"
  let holder =
    #|import fcntl, sys
    #|f = open(sys.argv[1], "a+")
    #|fcntl.flock(f, fcntl.LOCK_EX)
    #|print("locked", flush=True)
    #|sys.stdin.read()
  let probe = @process.run("python3", ["-c", "import fcntl"]) catch { _ => 1 }
  guard probe == 0 else {
    println("skipped: python3 with fcntl is not available")
    return
  }
  @async.with_task_group(group => {
    let (reader, stdout) = @process.read_from_process()
    let (stdin, writer) = @process.write_to_process()
    let other = group.spawn(allow_failure=true, () => {
      @process.run(
        "python3",
        ["-c", holder, "\{dir}/subagents.lock"],
        stdin~,
        stdout~,
      )
    })
    guard reader.read_until("\n") is Some("locked") else {
      fail("the other process never took the lock")
    }
    assert_true(@ledger.Ledger::open(path, floor=1) is None)
    // The other process is killed where it stands: no unlock, no cleanup.
    other.cancel()
    ignore(other.wait()) catch {
      _ => ()
    }
    writer.close()
    reader.close()
    assert_true(@fs.exists("\{dir}/subagents.lock"))
    guard @ledger.Ledger::open(path, floor=1) is Some(ledger) else {
      fail("ownership must be free once its holder is dead")
    }
    assert_eq(ledger.allocate(count=1, owner="engine"), 1)
    ledger.close()
  })
}
