///|
/// A store root with `session`'s directory already in place, plus the path its
/// record belongs at.
async fn record_fixture(session : String) -> (@pathx.Absolute, @pathx.Path) {
  let dir = @fs.tmpdir(prefix="openseek-record-")
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let path = @session_record.record_path(root, session)
  @fsx.ensure_dir(path.dirname())
  (root, path)
}

///|
fn header_line(session : String) -> String {
  "{\"version\":1,\"id\":\"\{session}\",\"system_prompt\":\"be brief\"}\n"
}

///|
fn event_line(sequence : Int, content : String) -> String {
  "{\"sequence\":\{sequence},\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"\{content}\"}}}\n"
}

///|
async fn write_record(path : @pathx.Path, text : String) -> Unit {
  @fs.write_file(path.to_string(), text, create_mode=CreateOrTruncate)
}

///|
async fn append_record(path : @pathx.Path, text : String) -> Unit {
  @fs.write_file(path.to_string(), text, create_mode=OpenOrCreate, append=true)
}

///|
/// The `Unreadable` detail one poll of `session` refuses with; "read" when the
/// poll succeeded, and any other failure rendered as itself.
async fn unreadable_detail(root : @pathx.Absolute, session : String) -> String {
  try {
    ignore(@session_record.Tail(root, session).poll())
    "read"
  } catch {
    @session_record.Unreadable(detail) => detail
    error => "\{error}"
  }
}

///|
async test "a record's header names the document its events belong to" {
  let (root, path) = record_fixture("s-1")
  write_record(path, header_line("s-1") + event_line(1, "one"))
  let tail = @session_record.Tail(root, "s-1")
  inspect(tail.poll().length(), content="1")
  let document = tail.document()
  debug_inspect(document.id, content="Some(\"s-1\")")
  debug_inspect(document.system_prompt, content="Some(\"be brief\")")
  debug_inspect(document.version, content="Some(1)")
  inspect(tail.watermark(), content="1")
}

///|
async test "read_text preserves the complete JSONL record" {
  let (root, path) = record_fixture("s-export")
  let text = header_line("s-export") + event_line(1, "one")
  write_record(path, text)
  assert_eq(@session_record.read_text(root, "s-export"), text)
}

///|
async test "a poll reports only what was appended since the last one" {
  let (root, path) = record_fixture("s-2")
  write_record(path, header_line("s-2") + event_line(1, "one"))
  let tail = @session_record.Tail(root, "s-2")
  inspect(tail.poll().length(), content="1")
  inspect(tail.poll().length(), content="0")
  append_record(path, event_line(2, "two") + event_line(3, "three"))
  let fresh = tail.poll()
  debug_inspect(fresh.map(event => event.sequence), content="[2, 3]")
  // The document is the whole log, not the increment.
  inspect(tail.document().events.unwrap_or([]).length(), content="3")
  inspect(tail.watermark(), content="3")
}

///|
async test "a final record that lost only its newline is taken once" {
  let (root, path) = record_fixture("s-3")
  let torn = event_line(2, "two").trim(chars="\n").to_owned()
  write_record(path, header_line("s-3") + event_line(1, "one") + torn)
  let tail = @session_record.Tail(root, "s-3")
  debug_inspect(tail.poll().map(event => event.sequence), content="[1, 2]")
  // The next append repairs the missing newline; the sequence check keeps the
  // repaired line from entering the log a second time.
  write_record(
    path,
    header_line("s-3") +
    event_line(1, "one") +
    event_line(2, "two") +
    event_line(3, "three"),
  )
  debug_inspect(tail.poll().map(event => event.sequence), content="[3]")
  inspect(tail.document().events.unwrap_or([]).length(), content="3")
}

///|
async test "a record torn mid-line waits for the rest of it" {
  let (root, path) = record_fixture("s-4")
  write_record(path, header_line("s-4") + "{\"sequence\":1,\"ts\":0,\"it")
  let tail = @session_record.Tail(root, "s-4")
  inspect(tail.poll().length(), content="0")
  inspect(tail.watermark(), content="0")
  write_record(path, header_line("s-4") + event_line(1, "one"))
  debug_inspect(tail.poll().map(event => event.sequence), content="[1]")
}

///|
async test "an absent record is not the same failure as an unreadable one" {
  let (root, path) = record_fixture("s-5")
  let absent = try {
    ignore(@session_record.Tail(root, "s-5").poll())
    "read"
  } catch {
    @session_record.Absent(_) => "absent"
    error => "\{error}"
  }
  inspect(absent, content="absent")
  write_record(path, "not a header\n" + event_line(1, "one"))
  let unreadable = unreadable_detail(root, "s-5")
  inspect(
    unreadable,
    content=(
      #|the session record holds a line that is not JSON: Invalid character 'o' at line 1, column 1
    ),
  )
}

///|
async test "a record holding another session is refused" {
  let (root, path) = record_fixture("s-6")
  write_record(path, header_line("s-other") + event_line(1, "one"))
  let refusal = unreadable_detail(root, "s-6")
  inspect(refusal, content="the session record holds s-other, not s-6")
}

///|
async test "a header version this build does not read is refused" {
  let (root, path) = record_fixture("s-7")
  write_record(
    path,
    "{\"version\":2,\"id\":\"s-7\",\"system_prompt\":\"\"}\n" +
    event_line(1, "one"),
  )
  let refusal = unreadable_detail(root, "s-7")
  inspect(
    refusal,
    content="the session record uses session file version 2; this build reads version 1",
  )
}

///|
async test "an item kind this build does not know still enters the log" {
  let (root, path) = record_fixture("s-8")
  write_record(
    path,
    header_line("s-8") +
    "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"telepathy\",\"payload\":{}}}\n",
  )
  let tail = @session_record.Tail(root, "s-8")
  let fresh = tail.poll()
  inspect(fresh.length(), content="1")
  assert_true(fresh[0].item is Unknown(_))
}

///|
async test "a record replaced under the reader is read again from its head" {
  let (root, path) = record_fixture("s-9")
  write_record(
    path,
    header_line("s-9") + event_line(1, "one") + event_line(2, "two"),
  )
  let tail = @session_record.Tail(root, "s-9")
  inspect(tail.poll().length(), content="2")
  // A shorter file at the same path is a different record: everything it
  // holds is reported again, and the reader's own log is only what it says.
  write_record(path, header_line("s-9") + event_line(1, "uno"))
  debug_inspect(tail.poll().map(event => event.sequence), content="[1]")
  inspect(tail.document().events.unwrap_or([]).length(), content="1")
  inspect(tail.watermark(), content="1")
}

///|
async test "an event line longer than one read is folded in whole" {
  let (root, path) = record_fixture("s-11")
  // A tool result far larger than one read: its line is assembled from the
  // pieces several reads deliver, and arrives as one event.
  let huge = "x".repeat(400_000)
  write_record(
    path,
    header_line("s-11") + event_line(1, huge) + event_line(2, "after"),
  )
  let tail = @session_record.Tail(root, "s-11")
  let fresh = tail.poll()
  debug_inspect(fresh.map(event => event.sequence), content="[1, 2]")
  guard fresh[0].item is User(payload) else { fail("expected a user item") }
  inspect(payload.content.length(), content="400000")
}

///|
async test "a lock that cannot be taken is a failure, not an unlocked read" {
  let dir = @fs.tmpdir(prefix="openseek-record-lock-")
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  // The session's own directory is a regular file, so opening anything beneath
  // it raises ENOTDIR — a failure that is not "no lock file yet", and so must
  // not read on: a reader that could not take the lock has not established the
  // ordering that makes a complete line a durable commit.
  let session_dir = @session_record.record_path(root, "s-14").dirname()
  @fsx.ensure_dir(session_dir.dirname())
  @fs.write_file(session_dir.to_string(), "file", create_mode=CreateOrTruncate)
  let refusal = unreadable_detail(root, "s-14")
  // The message carries the temp path, so assert its stable halves: that the
  // lock is what failed — not the record read behind it — and why.
  assert_true(refusal.has_prefix("cannot take the session record's lock"))
  assert_true(refusal.contains("Not a directory"))
}

///|
async test "a line that is not UTF-8 is refused, not silently mangled" {
  let (root, path) = record_fixture("s-13")
  // A lone 0xFF cannot begin any UTF-8 sequence. Decoding it lossily would
  // turn it into U+FFFD, and the line would then parse — publishing a durable
  // commit whose text is not what the writer wrote.
  @fsx.write_bytes(
    path, b"{\"version\":1,\"id\":\"s-13\",\"system_prompt\":\"\"}\n{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"\xff\"}}}\n",
  )
  let refusal = unreadable_detail(root, "s-13")
  inspect(
    refusal,
    content=(
      #|the session record holds a line that is not UTF-8 at byte 65: <BytesView: [0xff, 0x22, 0x7d, 0x7d]>
    ),
  )
}

///|
async test "a poll waits for the writer to finish committing" {
  let (root, path) = record_fixture("s-12")
  write_record(path, header_line("s-12") + event_line(1, "one"))
  let tail = @session_record.Tail(root, "s-12")
  inspect(tail.poll().length(), content="1")
  // The store's writer holds this lock across its append and the fdatasync
  // that makes the append survive an OS crash. The bytes are already visible
  // in between; a reader that published them would be calling an event
  // durable before it is.
  let lock = @fs.open(
    path.dirname().join("session.lock").to_string(),
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  lock.lock(Exclusive)
  append_record(path, event_line(2, "two"))
  inspect(
    @async.with_timeout_opt(200, () => tail.poll().length()) is None,
    content="true",
  )
  lock.unlock()
  lock.close()
  // That timed-out poll was cancelled while waiting for the lock, which resets
  // the reader to the head — so this one replays the whole log. The follower's
  // own watermark is what keeps a replay off the wire.
  debug_inspect(tail.poll().map(event => event.sequence), content="[1, 2]")
}

///|
async test "read_document answers with the whole record at once" {
  let (root, path) = record_fixture("s-10")
  write_record(
    path,
    header_line("s-10") + event_line(1, "one") + event_line(2, "two"),
  )
  let document = @session_record.read_document(root, "s-10")
  debug_inspect(document.id, content="Some(\"s-10\")")
  debug_inspect(
    document.events.unwrap_or([]).map(event => event.sequence),
    content="[1, 2]",
  )
}
