// A conversation's durable record, read the way the host reads it: directly.
//
// The engine's store keeps one conversation per file —
// `<root>/sessions/<id>/openseek_session-<id>.jsonl` — whose first line is a
// header record (`{version, id, system_prompt}`) and whose every later line is
// one committed event (`{sequence, ts, item}`). Writers only append to it, and
// the two operations that do not append (repairing a tail torn by a crash,
// rewriting a whole snapshot) go through a temp file and a rename, so a reader
// sees either the old file or the new one — never a half-written mix of both.
//
// That is what lets this reader tail the file without a subprocess: it
// consumes complete lines only, remembers the byte offset it stopped at, and
// folds each event in exactly once by its sequence number. A record that was
// replaced under it — one that shrank, or whose bytes at the offset are no
// longer the ones read there — is simply read again from its head, and the
// sequence check makes that re-read cost nothing but the reading.
//
// Reads take the store's own `session.lock` in shared mode, because a complete
// line is not yet a commit. The writer holds that lock exclusively across its
// append AND the fdatasync that makes it survive an OS crash; without the
// shared side a reader can see a newline-terminated line that is still only in
// the page cache, and publish as durable an event a power failure would take
// back.
//
// Lines decode into the desktop's own transcript types, whose unknown item
// kinds survive as `Unknown`: a record written by an engine newer than this
// build still reads here, which is not true of the engine's own reader.

///|
/// The header version this build reads. A record announcing any other version
/// is refused rather than guessed at — its event lines may mean something else
/// entirely.
const RecordVersion = 1

///|
/// The most one read takes from the file at once. A record that grew by a huge
/// tool result between polls arrives over several reads instead of one
/// allocation the size of the burst.
let record_chunk_bytes : Int64 = 128 * 1024

///|
/// How much of the last chunk is kept as the next poll's proof that the file
/// at the offset is still the file that was read. Short: it only has to be
/// long enough that a different record is unlikely to carry the same bytes at
/// the same position, and it is re-read in full on every poll.
const RecordAnchorBytes = 48

///|
/// Why a record could not be read.
///
/// `Absent` is kept apart from every other failure because a conversation
/// whose engine has not committed its first event yet is a normal state, and
/// because an absent record is the only proof that a departed writer left no
/// durable tail to drain.
///
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
pub(all) suberror RecordError {
  Absent(String)
  Unreadable(String)
} derive(Debug)

///|
impl Show for RecordError with fn output(self, logger) {
  match self {
    Absent(message) | Unreadable(message) => logger.write_string(message)
  }
}

///|
/// The file a session's events are appended to, in the store's layout.
pub fn record_path(root : @pathx.Absolute, session : String) -> @pathx.Path {
  root
  .join("sessions")
  .join(session)
  .join("openseek_session-\{session}.jsonl")
  .to_path()
}

///|
/// The lock the store serializes a session's writers on. It carries no id
/// suffix — it already lives inside the per-id directory.
fn lock_path(root : @pathx.Absolute, session : String) -> @pathx.Path {
  root.join("sessions").join(session).join("session.lock").to_path()
}

///|
/// Run `body` holding the record's lock in shared mode, which is what makes a
/// complete line a commit: the writer releases only after the fdatasync behind
/// its append has returned.
///
/// An absent lock file is the one failure that reads on: the store creates it
/// (`ensure_session_dir`, then `with_session_lock`) before any record byte
/// reaches the disk, so nothing has ever been committed here — and the first
/// write is an atomic rename rather than an append, so a writer arriving in the
/// meantime leaves no torn state to observe either. Every other failure raises:
/// a reader that could not take the lock has not established the ordering this
/// whole file rests on, and must say so rather than read on without it.
///
/// The lock is opened read-only and never created. A shared lock needs no write
/// access, which keeps a reader from adding files to the store and lets it read
/// a record that lives on read-only media.
async fn[T] with_shared_record_lock(
  path : @pathx.Path,
  body : async () -> T,
) -> T {
  let lock = @fs.open(path.to_string(), mode=ReadOnly, create_mode=OpenExisting) catch {
    error if @async.is_being_cancelled() => raise error
    @os_error.OSError(_) as error if error.is_ENOENT() => return body()
    error => raise Unreadable("cannot take the session record's lock: \{error}")
  }
  defer lock.close()
  lock.lock(Shared)
  defer lock.unlock()
  body()
}

///|
/// One reader's place in one session's record.
struct Tail {
  session : String
  path : @pathx.Path
  // The store's per-session lock, taken shared for the length of a read.
  lock : @pathx.Path
  // Bytes read so far: where the next read starts.
  mut offset : Int64
  // The bytes that end at `offset`, re-checked at their own position before
  // that offset is trusted again. The store repairs a torn tail by renaming a
  // temp file over the record, and the replacement carries the newly appended
  // event too — so it is usually LONGER than what was read, and a length check
  // alone cannot see it.
  mut anchor : Bytes
  // Bytes after the last newline read: a read can land mid-line, and half a
  // record is not a commit. Held as bytes, not text, so a chunk boundary
  // inside a multi-byte character cannot corrupt the line it belongs to — and
  // in the pieces they arrived in, so a line longer than one read is joined
  // once at its end rather than re-copied by every read that extends it.
  carry : Array[Bytes]
  // The header's fields, adopted when its line is read. `id` doubles as
  // whether that has happened: every header carries one.
  mut id : String?
  mut system_prompt : String?
  // Every event folded in, oldest first. The document a `session.load` answers
  // with is this array — not another read of the file.
  events : Array[@protocol.SessionEvent]
  // The highest sequence folded in, and therefore what makes re-reading free
  // of consequences: the same line can arrive any number of times and enters
  // the log exactly once.
  mut watermark : Int
}

///|
/// A reader positioned at the head of `session`'s record under `root`. Nothing
/// is read until the first `poll`.
pub fn Tail::Tail(root : @pathx.Absolute, session : String) -> Tail {
  {
    session,
    path: record_path(root, session),
    lock: lock_path(root, session),
    offset: 0,
    anchor: b"",
    carry: [],
    id: None,
    system_prompt: None,
    events: [],
    watermark: 0,
  }
}

///|
/// Everything committed since the last successful poll, oldest first.
///
/// The read runs under the record's shared lock, so every event returned here
/// is one the writer has already made durable.
///
/// Any failure — a vanished record, a read that died mid-chunk, a line this
/// build cannot read, a cancelled wait for the lock — resets the reader to the
/// record's head, so a poll never leaves it half-consumed. The next poll then
/// reports the whole log as fresh, which is why the caller keeps its own
/// frontier: a reader that may replay is cheaper to reason about than one that
/// has to unwind a partial read.
pub async fn Tail::poll(self : Tail) -> Array[@protocol.SessionEvent] {
  errdefer self.rewind()
  with_shared_record_lock(self.lock, () => self.read_forward())
}

///|
/// Everything read so far, in the shape `session.load` answers with.
///
/// The events are copied: the caller may still be encoding this document when
/// the next poll folds another event into the reader's own log.
pub fn Tail::document(self : Tail) -> @protocol.SessionDocument {
  {
    version: if self.id is Some(_) {
      Some(RecordVersion)
    } else {
      None
    },
    id: self.id,
    system_prompt: self.system_prompt,
    events: Some(self.events.copy()),
  }
}

///|
/// The highest sequence folded in; 0 for a record with no events.
pub fn Tail::watermark(self : Tail) -> Int {
  self.watermark
}

///|
/// The whole record, read once. This is what a conversation no follower is
/// watching answers `session.load` with, and it needs neither the engine
/// binary nor a running writer.
pub async fn read_document(
  root : @pathx.Absolute,
  session : String,
) -> @protocol.SessionDocument {
  let tail = Tail(root, session)
  ignore(tail.poll())
  tail.document()
}

///|
/// The complete committed JSONL record, including its header line.
///
/// Standalone visualizer exports need the original text because their bundled
/// parser must see exactly what the live `/api/sessions/<key>` endpoint would
/// serve. The shared store lock spans the whole read, so the returned text
/// cannot include an append whose durability sync has not completed.
pub async fn read_text(root : @pathx.Absolute, session : String) -> String {
  let path = record_path(root, session)
  let lock = lock_path(root, session)
  with_shared_record_lock(lock, async fn() {
    @fs.read_file(path.to_string()).text() catch {
      error if @async.is_being_cancelled() => raise error
      @os_error.OSError(_) as error if error.is_ENOENT() =>
        raise Absent("no durable record at \{path}")
      error => raise Unreadable("cannot read the session record: \{error}")
    }
  })
}

///|
/// Read from the offset to the end of the file, folding in every complete line
/// on the way. Mutates as it goes; `poll` owns the reset that a failure needs.
async fn Tail::read_forward(self : Tail) -> Array[@protocol.SessionEvent] {
  let file = @fs.open(self.path.to_string(), mode=ReadOnly) catch {
    error if @async.is_being_cancelled() => raise error
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      raise Absent("no durable record at \{self.path}")
    error => raise Unreadable("cannot open the session record: \{error}")
  }
  defer file.close()
  let size = file.size() catch {
    error if @async.is_being_cancelled() => raise error
    error => raise Unreadable("cannot measure the session record: \{error}")
  }
  if size < self.offset || !anchored_at(file, self.offset, self.anchor) {
    self.rewind()
  }
  let fresh : Array[@protocol.SessionEvent] = []
  while self.offset < size {
    let remaining = size - self.offset
    let take = @cmp.minimum(remaining, record_chunk_bytes)
    let chunk = file.read_exactly_at(take.to_int(), position=self.offset) catch {
      error if @async.is_being_cancelled() => raise error
      error => raise Unreadable("cannot read the session record: \{error}")
    }
    self.offset += take
    self.anchor = anchor_of(chunk)
    let mut line_start = 0
    for index in 0..<chunk.length() {
      if chunk[index] != b'\n' {
        continue
      }
      let segment = chunk[line_start:index]
      // Only a chunk's first line can have begun in an earlier read, and it is
      // the one place carried pieces are copied. Every later line in the chunk
      // is read where it lies.
      let line = if self.carry.is_empty() {
        self.consume(segment)
      } else {
        let joined = join_carry(self.carry, segment)
        self.carry.clear()
        self.consume(joined)
      }
      if line is Some(event) {
        fresh.push(event)
      }
      line_start = index + 1
    }
    if line_start < chunk.length() {
      self.carry.push(chunk[line_start:].to_owned())
    }
  }
  // A final record that decodes but lost only its newline — a write torn
  // exactly at the boundary — is content the store's own reader keeps and its
  // next append repairs. Take it too, without consuming the bytes: the
  // sequence check drops the duplicate when the repaired line arrives with its
  // newline, and a JSON object cannot grow into a different valid one.
  if !self.carry.is_empty() {
    let torn = self.consume(join_carry(self.carry, b"")) catch {
      // Bytes no writer has committed yet are not news, and not a defect.
      _ => None
    }
    if torn is Some(event) {
      fresh.push(event)
    }
  }
  fresh
}

///|
/// The pieces of one line that spans reads, joined into the line itself. This
/// is the only copy they take: keeping them apart until a newline arrives is
/// what makes a line longer than one read cost its own length, not its length
/// once per read that extended it.
fn join_carry(parts : Array[Bytes], tail : BytesView) -> Bytes {
  let line = @buffer.Buffer()
  for part in parts {
    line.write_bytes(part)
  }
  line.write_bytes(tail)
  line.to_bytes()
}

///|
/// Fold one complete line in, returning the event it committed. The header
/// line and blank padding commit nothing; a line this build cannot read at all
/// is a defect in the record, not something to skip past.
fn Tail::consume(
  self : Tail,
  line : BytesView,
) -> @protocol.SessionEvent? raise RecordError {
  // Strict, like the store's own reader: bytes that are not UTF-8 are a defect
  // to report, not one to paper over. Decoding them lossily would hand clients
  // a durable commit whose text silently differs from the record's — and, on
  // the unterminated-tail path below, could turn a line cut mid-character into
  // a plausible-looking event.
  let text = @utf8.decode(line) catch {
    // `Malformed` carries the whole suffix from the offending byte onward, and
    // one line can be hundreds of kilobytes — say where it went wrong, and show
    // only the bytes that did.
    Malformed(rest) =>
      raise Unreadable(
        "the session record holds a line that is not UTF-8 at byte \{line.length() - rest.length()}: \{@debug.Repr(if rest.length() > 4 { rest[:4] } else { rest })}",
      )
  }
  let text = text.trim(chars="\r\n \t").to_owned()
  if text.is_empty() {
    return None
  }
  let json = @json.parse(text) catch {
    error =>
      raise Unreadable(
        "the session record holds a line that is not JSON: \{error}",
      )
  }
  guard self.id is Some(_) else {
    self.adopt_header(json)
    return None
  }
  let event : @protocol.SessionEvent = @json.from_json(json) catch {
    error =>
      raise Unreadable(
        "the session record holds a line this build cannot read: \{error}",
      )
  }
  // Already folded in: what makes a re-read — after a repair, a replaced file,
  // or an offset that turned out to be wrong — cost nothing.
  if event.sequence <= self.watermark {
    return None
  }
  self.watermark = event.sequence
  self.events.push(event)
  Some(event)
}

///|
/// Adopt the record's header: the identity and system prompt the events that
/// follow belong to. Refusing a header whose id is not this session's is what
/// keeps a file swapped in from elsewhere from being read as this transcript.
fn Tail::adopt_header(self : Tail, json : Json) -> Unit raise RecordError {
  match json {
    { "version": Number(version, ..), .. } if version.to_int() != RecordVersion =>
      raise Unreadable(
        "the session record uses session file version \{version.to_int()}; this build reads version \{RecordVersion}",
      )
    {
      "version": Number(_, ..),
      "id": String(id),
      "system_prompt": String(system_prompt),
      ..
    } => {
      guard id == self.session else {
        raise Unreadable("the session record holds \{id}, not \{self.session}")
      }
      self.id = Some(id)
      self.system_prompt = Some(system_prompt)
    }
    _ =>
      raise Unreadable("the session record does not start with a header record")
  }
}

///|
/// Forget where this reader was and everything it read there. The next poll
/// rebuilds the whole log from the record's head.
fn Tail::rewind(self : Tail) -> Unit {
  self.offset = 0
  self.anchor = b""
  self.carry.clear()
  self.id = None
  self.system_prompt = None
  self.events.clear()
  self.watermark = 0
}

///|
/// The tail of a chunk, kept as the next poll's positional continuity check.
fn anchor_of(chunk : Bytes) -> Bytes {
  if chunk.length() <= RecordAnchorBytes {
    chunk
  } else {
    chunk[chunk.length() - RecordAnchorBytes:].to_owned()
  }
}

///|
/// Whether the bytes ending at `offset` are still the ones read there. An
/// empty anchor (nothing read yet) is vacuously true; a read that fails
/// reports false, which costs one re-read from the head.
async fn anchored_at(file : @fs.File, offset : Int64, anchor : Bytes) -> Bool {
  if anchor.length() == 0 {
    return true
  }
  let start = offset - anchor.length().to_int64()
  if start < 0 {
    return false
  }
  let seen = file.read_exactly_at(anchor.length(), position=start) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  seen == anchor
}

///|
pub extend RecordError with Debug::{to_repr}
