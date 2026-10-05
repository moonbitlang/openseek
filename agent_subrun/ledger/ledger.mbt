// The ledger of one session's subagents: the authoritative allocator of
// child ordinals.
//
// A child's session is `<parent>-sr-N`. N used to come from a counter in the
// engine's memory, and a restarted engine recovered it by scanning the child
// sessions that already existed. That loses every ordinal handed out but not
// yet used: a workflow snippet is given a block of 32 before it starts, and
// if the engine dies while the snippet lives on, the next engine allocates
// from the same numbers and two children write one transcript.
//
// So an ordinal is made durable BEFORE it leaves the engine. Each allocation
// is one record appended and synced to `subagents.jsonl` in the parent's
// session directory, and the next ordinal is one past the highest recorded.
//
// One process owns a session's ledger at a time. It holds an exclusive lock
// on a file beside the ledger for as long as the ledger is open; a second
// opener is refused, not queued. Liveness is the kernel's lock and nothing
// else — not the lock file's existence, which outlives a crash.

///|
/// The lock file's name, beside the ledger. Dedicated: the session's own
/// `session.lock` is taken and released around every transcript write, and a
/// lifetime lock on it would stop ordinary persistence.
const LockName : String = "subagents.lock"

///|
/// One session's ledger, open and owned by this process.
struct Ledger {
  path : String
  /// Held, locked, for as long as the ledger is open.
  lock : @fs.File
  /// One allocation at a time: the read of `next`, the write and the advance
  /// are one step. `close` takes it too, so ownership is never released
  /// under an allocation that has chosen its ordinal and not yet written it.
  writes : @async.Mutex
  mut next : Int
  mut closed : Bool
  /// The directories whose entries the ledger's own existence depends on,
  /// innermost first. They are synced after the first record this process
  /// writes — whoever created the file, and whenever.
  dirs : Array[String]
  mut dirs_synced : Bool
  sync_dir : async (String) -> Unit
}

///|
/// Open the ledger at `path` and take ownership of it, or return `None` when
/// another opener already owns it.
///
/// `floor` is the lowest ordinal the caller knows to be unused by other
/// evidence — one past the highest child session that exists. The first
/// allocation is the greater of that and one past the highest ordinal the
/// ledger itself records, so a ledger added to a session that already has
/// children, and a session whose ledger lost a record, both start clear.
///
/// `dirs` is the chain of directories to make durable with the ledger,
/// innermost first; it defaults to the ledger's own directory. `sync_dir` is
/// a seam for tests.
///
/// Lines this build cannot read are passed over: a tail cut off by a write
/// that failed part-way was never an allocation that left the engine, since
/// an id is returned only after its record is written and synced.
pub async fn Ledger::open(
  path : String,
  floor~ : Int,
  dirs? : Array[String],
  sync_dir? : async (String) -> Unit = sync_dir_best_effort,
) -> Ledger? {
  let dir = @path.Path(path).dirname().to_string()
  @fs.mkdir(dir, recursive=true) catch {
    error => if !@fs.exists(dir) { raise error }
  }
  let lock = @fs.open(
    "\{dir}/\{LockName}",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  // From here every way out but success closes the file: a lock that
  // cannot be tried at all (not merely one that is held) must not leak a
  // descriptor on each attempt.
  errdefer lock.close()
  guard lock.try_lock(Exclusive) else {
    lock.close()
    return None
  }
  errdefer lock.unlock()
  let highest = highest_allocated(path)
  let next = if highest + 1 > floor { highest + 1 } else { floor }
  Some({
    path,
    lock,
    writes: Mutex(),
    next,
    closed: false,
    dirs: dirs.unwrap_or([dir]),
    dirs_synced: false,
    sync_dir,
  })
}

///|
/// Allocate `count` consecutive ordinals for `owner` and return the first.
///
/// The record is written and synced before this returns. If that fails this
/// raises and no allocation is returned: the caller has no id, and the same
/// ordinals are offered to the next allocation. (An attempt cut off after its
/// record landed leaves a record nobody was given; it only makes the next
/// engine skip those ordinals.) `owner` says who asked, for a reader of the
/// ledger; it changes nothing here.
///
/// Raises on a ledger that has been closed: ownership is gone, and an
/// ordinal chosen without it could be chosen again by the next owner.
pub async fn Ledger::allocate(
  self : Ledger,
  count~ : Int,
  owner~ : String,
) -> Int {
  guard count > 0 else { fail("an allocation needs a positive count") }
  self.writes.acquire()
  defer self.writes.release()
  guard !self.closed else { fail("the subagent ledger is closed") }
  let first = self.next
  let record : Json = {
    "event": "allocated",
    "first": first.to_json(),
    "count": count.to_json(),
    "owner": owner,
  }
  append(self.path, record)
  // The record's bytes are synced by the write. The file's own directory
  // entry — and those of any directories made for it — are synced here,
  // before the first id this process hands out, whether or not this process
  // created them: a file left by an attempt that died before this point was
  // never made durable by anyone.
  if !self.dirs_synced {
    for dir in self.dirs {
      (self.sync_dir)(dir)
    }
    self.dirs_synced = true
  }
  self.next = first + count
  first
}

///|
/// Give up ownership, once any allocation in flight has finished. Later
/// allocations on this ledger are refused. A process that exits without
/// calling this loses the lock all the same; this is for an engine that
/// stops running a session and keeps living.
pub async fn Ledger::close(self : Ledger) -> Unit {
  self.writes.acquire()
  defer self.writes.release()
  guard !self.closed else { return }
  self.closed = true
  self.lock.unlock()
  self.lock.close()
}

///|
/// Append one record durably. A tail left by a write that died part-way is
/// closed off first, so it damages only itself and not the record after it.
async fn append(path : String, record : Json) -> Unit {
  let file = @fs.open(
    path,
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    append=true,
    sync=Data,
  )
  defer file.close()
  let size = file.size()
  let torn = size > 0L && file.read_exactly_at(1, position=size - 1L) != b"\n"
  let line = (if torn { "\n" } else { "" }) + record.stringify() + "\n"
  file.write(line)
}

///|
/// Sync a directory so that the entries in it survive a power loss. Best
/// effort, like the session store's: where a directory cannot be opened or
/// synced, crash-consistency degrades for power loss only, never for a
/// process crash.
async fn sync_dir_best_effort(dir : String) -> Unit {
  let file = @fs.open(dir, mode=ReadOnly) catch { _ => return }
  defer file.close()
  file.sync() catch {
    _ => ()
  }
}

///|
/// The highest ordinal any readable allocation record covers, or 0 for a
/// ledger with none. The file is split into lines as bytes and each whole
/// line is decoded on its own, so a tail cut inside a character cannot spoil
/// the records before it.
async fn highest_allocated(path : String) -> Int {
  guard @fs.exists(path) else { return 0 }
  let bytes = @fs.read_file(path).binary()
  let mut highest = 0
  let mut start = 0
  for index in 0..<bytes.length() {
    guard bytes[index] == b'\n' else { continue }
    let line = bytes[start:index]
    start = index + 1
    let json = @json.parse(@utf8.decode(line)) catch { _ => continue }
    guard json
      is {
        "event": "allocated",
        "first": Number(first, ..),
        "count": Number(count, ..),
        ..
      } else {
      continue
    }
    let last = first.to_int() + count.to_int() - 1
    if last > highest {
      highest = last
    }
  }
  highest
}
