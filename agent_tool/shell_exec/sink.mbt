///|
/// Default inline cap: output at or below this many characters is shown inline;
/// larger output spills to a file and is rendered as a pointer plus a head
/// preview. Matches the `shell` tool's foreground default so a command reads the
/// same whether it runs in the foreground or the background.
pub let default_inline_cap : Int = 12000

///|
/// Default hard cap: the sink retains at most this many characters of full
/// output (across memory + the spill file), bounding disk even for a runaway
/// producer. The size watchdog is expected to kill a job well before this.
pub let default_hard_cap : Int = 20_000_000

///|
/// One owner for a single command's merged stdout+stderr, with a single
/// retention story so foreground and background never disagree. **Memory-first,
/// file-backed:** output is kept in memory up to `inline_cap`; past it the *full*
/// output spills to a file (`spill_path`) and only a bounded in-memory *head* is
/// kept for cheap inline rendering. The file is the source of truth for full
/// output, so a reader can ask for any window (`read_all` now; prefix/tail/range
/// later) without the sink pre-committing to one — that is what makes retention a
/// read-time decision instead of a policy baked into the buffer.
///
/// With no `spill_path` the sink is memory-only: it keeps the head and drops the
/// rest (bounded, never touches disk) — used by contexts that never need full
/// large output (tests, the scope-less `collect_shell_output`).
pub struct ShellOutputSink {
  // The first `inline_cap` characters, for inline rendering without a file read.
  priv head : StringBuilder
  priv mut head_chars : Int
  // Total decoded characters of full output (across memory + file), ≤ hard_cap.
  priv mut total_chars : Int
  // Trailing bytes of an incomplete UTF-8 sequence carried to the next chunk.
  priv mut pending : Bytes
  // Bumps whenever retained output grows, for poll change detection.
  priv mut seq : Int
  // Set once output was dropped at the hard cap.
  priv mut truncated : Bool
  // Set once any invalid (non-UTF-8 / binary) bytes were decoded lossily, so a
  // consumer can preserve the strict-decode "binary output" error rather than
  // silently showing replacement characters.
  priv mut had_invalid : Bool
  // Full-output spill file, opened lazily once output exceeds `inline_cap` and a
  // spill path is configured. None → memory-only (small output, or no path).
  priv mut file : @fs.File?
  // Bytes written to the file so far (== full output byte length once spilled).
  priv mut file_bytes : Int64
  // Where to spill; None → never spill (memory-only, head kept, rest dropped).
  priv spill_path : String?
  priv inline_cap : Int
  priv hard_cap : Int
}

///|
/// Create an empty sink. Non-positive caps are clamped to 1. With `spill_path`
/// set, output past `inline_cap` spills there; without it the sink is memory-only.
pub fn ShellOutputSink::new(
  inline_cap? : Int = default_inline_cap,
  hard_cap? : Int = default_hard_cap,
  spill_path? : String,
) -> ShellOutputSink {
  {
    head: StringBuilder(),
    head_chars: 0,
    total_chars: 0,
    pending: b"",
    seq: 0,
    truncated: false,
    had_invalid: false,
    file: None,
    file_bytes: 0,
    spill_path,
    inline_cap: if inline_cap > 0 {
      inline_cap
    } else {
      1
    },
    hard_cap: if hard_cap > 0 {
      hard_cap
    } else {
      1
    },
  }
}

///|
/// Feed a raw output chunk from the process reader, decoding UTF-8 across chunk
/// boundaries — an incomplete trailing sequence is carried to the next chunk.
pub async fn ShellOutputSink::append_chunk(
  self : ShellOutputSink,
  chunk : Bytes,
) -> Unit {
  let buffer = Buffer()
  buffer.write_bytes(self.pending)
  buffer.write_bytes(chunk)
  let (text, rest, invalid) = split_valid_utf8(buffer.to_bytes())
  self.pending = rest
  if invalid {
    self.had_invalid = true
  }
  self.append_text(text)
}

///|
/// Feed already-decoded text. Writes the full output to the spill file (once past
/// `inline_cap`), keeps the first `inline_cap` characters in the memory head, and
/// drops output past `hard_cap` (setting `truncated`). `seq` bumps when retained
/// output grows.
pub async fn ShellOutputSink::append_text(
  self : ShellOutputSink,
  text : String,
) -> Unit {
  guard text != "" else { return }
  guard !self.truncated else { return }
  let room_hard = self.hard_cap - self.total_chars
  guard room_hard > 0 else {
    self.truncated = true
    return
  }
  let text = if text.char_length() <= room_hard {
    text
  } else {
    self.truncated = true
    prefix_chars(text, room_hard)
  }
  // Full output → spill file. Open lazily the first time total output would pass
  // the inline cap, seeding the file with everything buffered so far (the head,
  // which holds all output while total ≤ inline_cap). A file-open/write failure
  // degrades to memory-only (the head) rather than losing the run.
  if self.spill_path is Some(path) {
    if self.file is None &&
      self.total_chars + text.char_length() > self.inline_cap {
      self.open_spill(path)
    }
    if self.file is Some(file) {
      let bytes = @utf8.encode(text)
      file.write_at(bytes, position=self.file_bytes) catch {
        _ => ()
      }
      self.file_bytes += bytes.length().to_int64()
    }
  }
  // Head: keep the first inline_cap characters.
  let room_head = self.inline_cap - self.head_chars
  if room_head > 0 {
    let piece = if text.char_length() <= room_head {
      text
    } else {
      prefix_chars(text, room_head)
    }
    self.head.write_string(piece)
    self.head_chars += piece.char_length()
  }
  self.total_chars += text.char_length()
  self.seq += 1
}

///|
/// Open the spill file and seed it with the output buffered so far.
async fn ShellOutputSink::open_spill(
  self : ShellOutputSink,
  path : String,
) -> Unit {
  // ReadWrite so the same descriptor serves both the streaming writes and later
  // `read_all` reads (a create/write-only handle cannot be read). CreateOrTruncate
  // gives a fresh file (the path is unique per job id).
  let file = @fs.open(path, mode=ReadWrite, create_mode=CreateOrTruncate) catch {
    _ => return
  }
  let seed = @utf8.encode(self.head.to_string())
  file.write_at(seed, position=0) catch {
    _ => {
      file.close()
      return
    }
  }
  self.file = Some(file)
  self.file_bytes = seed.length().to_int64()
}

///|
/// Flush any incomplete trailing UTF-8 bytes at end of stream (decoded lossily),
/// so a multi-byte character that never completed is surfaced rather than lost.
pub async fn ShellOutputSink::finish(self : ShellOutputSink) -> Unit {
  guard self.pending.length() > 0 else { return }
  // A non-empty pending buffer at end of stream is an incomplete (or invalid)
  // sequence — strict decoding would have rejected it, so mark it binary.
  self.had_invalid = true
  let text = @utf8.decode_lossy(self.pending)
  self.pending = b""
  self.append_text(text)
}

///|
/// Release the spill file descriptor. Reads after this fall back to the head.
pub fn ShellOutputSink::close(self : ShellOutputSink) -> Unit {
  if self.file is Some(file) {
    file.close()
    self.file = None
  }
}

///|
/// Close and delete the spill file — for a retained execution that completed in
/// the foreground (never adopted as a background job), so its temp file does not
/// leak. Full output is no longer readable after this (the head remains).
pub async fn ShellOutputSink::discard(self : ShellOutputSink) -> Unit {
  guard self.file is Some(_) else { return }
  self.close()
  if self.spill_path is Some(path) {
    @fs.remove(path) catch {
      _ => ()
    }
  }
}

///|
/// Total full-output length in characters (≤ hard_cap).
pub fn ShellOutputSink::size(self : ShellOutputSink) -> Int {
  self.total_chars
}

///|
/// Output version, bumped whenever retained output grows.
pub fn ShellOutputSink::seq(self : ShellOutputSink) -> Int {
  self.seq
}

///|
/// Whether full output was dropped at the hard cap.
pub fn ShellOutputSink::truncated(self : ShellOutputSink) -> Bool {
  self.truncated
}

///|
/// Whether any invalid (non-UTF-8 / binary) bytes were decoded — the consumer
/// may surface this as a "binary output" error instead of showing replacements.
pub fn ShellOutputSink::had_invalid_utf8(self : ShellOutputSink) -> Bool {
  self.had_invalid
}

///|
/// The in-memory head: the first `inline_cap` characters. This is the *full*
/// output when it fits inline; otherwise a preview. Synchronous.
pub fn ShellOutputSink::head(self : ShellOutputSink) -> String {
  self.head.to_string()
}

///|
/// Whether output exceeded the inline cap (so a consumer should render a pointer,
/// and full output lives in the spill file).
pub fn ShellOutputSink::over_inline_cap(self : ShellOutputSink) -> Bool {
  self.total_chars > self.inline_cap
}

///|
/// The spill file's path, if output spilled to disk; `None` for memory-only.
pub fn ShellOutputSink::spill_path(self : ShellOutputSink) -> String? {
  if self.file is Some(_) {
    self.spill_path
  } else {
    None
  }
}

///|
/// The full retained output. Reads the spill file when output spilled; otherwise
/// returns the in-memory head (which is the full output for a small command). On
/// a read error it degrades to the head rather than raising.
pub async fn ShellOutputSink::read_all(self : ShellOutputSink) -> String {
  match self.file {
    Some(file) => {
      let bytes = file.read_exactly_at(self.file_bytes.to_int(), position=0) catch {
        _ => return self.head.to_string()
      }
      @utf8.decode_lossy(bytes)
    }
    None => self.head.to_string()
  }
}

///|
/// The last `n` characters of full output — a window onto the *recent* output of
/// a (possibly still-running) job, read from the tail of the spill file so a
/// poller sees progress rather than the unchanging prefix. Degrades to the head
/// on a read error or a memory-only sink.
pub async fn ShellOutputSink::read_tail(
  self : ShellOutputSink,
  n : Int,
) -> String {
  guard n > 0 else { return "" }
  match self.file {
    Some(file) => {
      // Read a byte window sized for `n` UTF-8 chars (≤ 4 bytes each) from the
      // file tail, decode lossily (a partial lead byte at the window start
      // becomes a replacement char, dropped when we keep the last `n`), then keep
      // the last `n` characters.
      let want = n.to_int64() * 4 + 4
      let start = if self.file_bytes > want {
        self.file_bytes - want
      } else {
        0
      }
      let len = (self.file_bytes - start).to_int()
      let bytes = file.read_exactly_at(len, position=start) catch {
        _ => return self.head.to_string()
      }
      last_chars(@utf8.decode_lossy(bytes), n)
    }
    None => last_chars(self.head.to_string(), n)
  }
}

///|
/// The last `n` characters of `text` (or all of it if shorter).
fn last_chars(text : String, n : Int) -> String {
  let len = text.char_length()
  if len <= n {
    text
  } else {
    match text.offset_of_nth_char(len - n) {
      Some(start) => "\{text[start:]}"
      None => text
    }
  }
}

///|
/// First `n` characters of `text` (assumes `n < text.char_length()`).
fn prefix_chars(text : String, n : Int) -> String {
  match text.offset_of_nth_char(n) {
    Some(end) => "\{text[:end]}"
    None => text
  }
}

///|
/// Split `bytes` into the longest valid-UTF-8 prefix (decoded lossily) and the
/// trailing bytes of an incomplete multi-byte sequence to carry to the next
/// chunk. A malformed (not merely incomplete) trailing sequence is surfaced now
/// rather than held for a completion that can never be valid.
fn split_valid_utf8(bytes : Bytes) -> (String, Bytes, Bool) {
  let end = bytes.length() - incomplete_suffix_len(bytes)
  let tail = Buffer()
  tail.write_bytes(bytes[end:])
  // Strict-decode the complete prefix; on invalid bytes fall back to lossy and
  // report it, so the caller can preserve the "binary output" error. A valid
  // prefix (the common case) decodes once.
  let (text, invalid) = (@utf8.decode(bytes[:end]), false) catch {
    _ => (@utf8.decode_lossy(bytes[:end]), true)
  }
  (text, tail.to_bytes(), invalid)
}

///|
fn incomplete_suffix_len(bytes : Bytes) -> Int {
  let len = bytes.length()
  let lookback = if len < 3 { len } else { 3 }
  for i in 0..<lookback {
    let pos = len - 1 - i
    let b = bytes[pos].to_int()
    if b < 0x80 {
      return 0
    }
    if b >= 0xC0 {
      let expected = utf8_sequence_len(b)
      let have = len - pos
      guard expected != 0 && expected > have else { return 0 }
      for j in 1..<have {
        let (lo, hi) = continuation_range(b, j)
        let cb = bytes[pos + j].to_int()
        if cb < lo || cb > hi {
          return 0
        }
      }
      return have
    }
  }
  0
}

///|
fn utf8_sequence_len(b : Int) -> Int {
  match b {
    0xF0..=0xF4 => 4
    0xE0..=0xEF => 3
    0xC2..=0xDF => 2
    _ => 0
  }
}

///|
fn continuation_range(lead : Int, j : Int) -> (Int, Int) {
  match (j, lead) {
    (1, 0xE0) => (0xA0, 0xBF)
    (1, 0xED) => (0x80, 0x9F)
    (1, 0xF0) => (0x90, 0xBF)
    (1, 0xF4) => (0x80, 0x8F)
    _ => (0x80, 0xBF)
  }
}

///|
async test "small output stays in memory, no file" {
  let sink = ShellOutputSink::new(inline_cap=100)
  sink.append_text("hello")
  assert_eq(sink.head(), "hello")
  assert_eq(sink.read_all(), "hello")
  assert_eq(sink.size(), 5)
  assert_false(sink.over_inline_cap())
  assert_true(sink.spill_path() is None)
  assert_false(sink.truncated())
}

///|
async test "output over the inline cap spills; read_all returns everything, head previews" {
  let path = "/tmp/openseek-sink-spill-1.out"
  let sink = ShellOutputSink::new(inline_cap=4, hard_cap=1000, spill_path=path)
  sink.append_text("abcdefghij")
  assert_true(sink.over_inline_cap())
  assert_true(sink.spill_path() is Some(_))
  // Head is the first inline_cap chars (a preview); read_all is the full output.
  assert_eq(sink.head(), "abcd")
  assert_eq(sink.read_all(), "abcdefghij")
  assert_eq(sink.size(), 10)
  sink.close()
}

///|
async test "the spill file is seeded with output buffered before the spill" {
  let path = "/tmp/openseek-sink-spill-2.out"
  let sink = ShellOutputSink::new(inline_cap=4, hard_cap=1000, spill_path=path)
  sink.append_text("ab") // total 2, under inline cap: memory only, no file yet
  assert_false(sink.over_inline_cap())
  sink.append_text("cdef") // total 6 > 4: spill, seeding the file with "ab"
  assert_eq(sink.read_all(), "abcdef") // seed + new chunk, in order
  assert_eq(sink.head(), "abcd")
  sink.close()
}

///|
async test "memory-only (no spill path) keeps the head and drops the rest" {
  let sink = ShellOutputSink::new(inline_cap=4, hard_cap=1000)
  sink.append_text("abcdefghij")
  assert_true(sink.over_inline_cap())
  assert_true(sink.spill_path() is None)
  // No file: read_all is the bounded head, not the full output.
  assert_eq(sink.read_all(), "abcd")
  assert_eq(sink.size(), 10) // size still reports what was produced
}

///|
async test "output over the hard cap truncates" {
  let sink = ShellOutputSink::new(inline_cap=2, hard_cap=5)
  sink.append_text("abc")
  sink.append_text("defgh") // total 8 > 5
  assert_true(sink.truncated())
  assert_eq(sink.size(), 5)
  let seq_before = sink.seq()
  sink.append_text("xyz") // dropped, no seq bump
  assert_eq(sink.seq(), seq_before)
}

///|
async test "append_chunk decodes utf-8 across a chunk boundary" {
  let sink = ShellOutputSink::new(inline_cap=100)
  // "café" = 63 61 66 C3 A9, split between é's lead and continuation byte.
  sink.append_chunk(([0x63, 0x61, 0x66, 0xC3] : Bytes))
  sink.append_chunk(([0xA9] : Bytes))
  assert_eq(sink.head(), "café")
}

///|
async test "finish flushes an incomplete trailing sequence lossily" {
  let sink = ShellOutputSink::new(inline_cap=100)
  sink.append_chunk(([0x68, 0x69, 0xC3] : Bytes))
  assert_eq(sink.head(), "hi")
  sink.finish()
  assert_true(sink.size() >= 3)
}

///|
test "split_valid_utf8 surfaces corrupt trailing bytes instead of hiding them" {
  let bytes : Bytes = [0x68, 0x69, 0xff]
  let (text, rest, _) = split_valid_utf8(bytes)
  assert_true(rest.length() == 0)
  assert_true(text.has_prefix("hi"))
  assert_true(text.char_length() >= 3)
}

///|
test "split_valid_utf8 does not carry malformed multi-byte prefixes" {
  let (t1, r1, _) = split_valid_utf8(([0x78, 0xE0, 0x80] : Bytes))
  assert_true(r1.length() == 0)
  assert_true(t1.has_prefix("x"))
  let (t2, r2, _) = split_valid_utf8(([0x78, 0xF4, 0x90] : Bytes))
  assert_true(r2.length() == 0)
  assert_true(t2.has_prefix("x"))
  let (t3, r3, _) = split_valid_utf8(([0x78, 0xE0, 0xA0] : Bytes))
  assert_true(t3 == "x")
  assert_true(r3.length() == 2)
}
