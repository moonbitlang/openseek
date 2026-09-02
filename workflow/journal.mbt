///|
/// One journal record: an agent call's work identity and what it resolved
/// to. The journal is the workflow's durability seam — everything a resumed
/// run needs to skip re-paying for work already done rides these entries,
/// so the entry must lose nothing the live run knew (hence `AgentOutcome`,
/// the lossless envelope, and not just the value).
pub(all) struct JournalEntry {
  call : AgentCall
  outcome : AgentOutcome
} derive(Eq, ToJson, FromJson)

///|
pub extend JournalEntry with Eq::{equal, not_equal}

///|
pub extend JournalEntry with ToJson::{to_json}

///|
pub extend JournalEntry with FromJson::{from_json}

///|
/// The journal file is damaged somewhere other than its final line. A torn
/// TAIL is expected crash damage and is repaired on load; mid-file
/// corruption means the append-only contract was broken by something else
/// and must not be silently dropped.
pub suberror JournalCorrupted {
  JournalCorrupted(path~ : String, line~ : Int)
}

///|
pub extend JournalCorrupted with Show::{to_string, output}

///|
pub impl Show for JournalCorrupted with fn output(self, logger) {
  let JournalCorrupted(path~, line~) = self
  logger.write_string("journal \{path} is corrupt at line \{line}")
}

///|
/// The replay journal: prior-run entries consumed by WORK-IDENTITY match
/// as this run re-executes, plus an append-only record of this run's live
/// outcomes. Replay rules:
///
/// - a matching `Finished` entry replays its value — the work is not
///   re-paid, and neither the launch allowance nor `tokens_spent` is
///   charged (historical spend lives here, not in the fresh account);
/// - a matching `Skipped` entry replays as the same refusal — a human
///   declined this call once, and resume must not override that decision;
/// - any other failure does NOT replay: getting past it is what resume is
///   FOR, so the call runs live again (and consumes fresh launch
///   allowance — size `max_calls` with re-attempts in mind).
///
/// Identity is the call's work content — kind, input, max_steps, and
/// the workflow's replay scope — never the display label. Duplicate identical calls are intentional samples
/// (three identical verifiers), so matching consumes entries as a
/// multiset: each replay consumes one entry, in file order, and only LIVE
/// outcomes are recorded — replays are never re-appended, so entry counts
/// stay honest across any number of resume generations.
///
/// A file-backed journal assumes ONE writing workflow process per path:
/// appends are serialized within the process, not across processes.
pub struct Journal {
  priv prior : Array[JournalEntry]
  priv consumed : Array[Bool]
  priv path : String?
  priv recorded : Array[JournalEntry]
  priv write_lock : @async.Mutex
}

///|
/// A journal with no backing file: `prior` seeds replay (empty by
/// default, copied — later mutation of the argument cannot skew the
/// consumption bookkeeping), live outcomes accumulate in `recorded`. The
/// test-and-embed constructor.
pub fn Journal::in_memory(prior? : Array[JournalEntry] = []) -> Journal {
  let prior = prior.copy()
  {
    prior,
    consumed: Array::make(prior.length(), false),
    path: None,
    recorded: [],
    write_lock: Mutex(),
  }
}

///|
/// Open (or start) a file-backed journal: an append-only JSONL file, one
/// entry per line, accumulated across every generation of the run. A
/// missing file is an empty journal.
///
/// Crash honesty: a torn TAIL — an unparsable or undecodable final line,
/// or a final line missing its newline — is the signature of dying
/// mid-append. The damaged suffix is dropped from replay AND repaired on
/// disk (atomic rewrite-and-rename), so the next generation's appends
/// land on a clean boundary instead of concatenating onto torn bytes.
/// Damage anywhere else raises `JournalCorrupted`. Lines are split at the
/// byte level before UTF-8 decoding, so a tail torn mid-codepoint cannot
/// poison the healthy prefix.
pub async fn Journal::load(path : String) -> Journal {
  let prior : Array[JournalEntry] = []
  if @fs.exists(path) {
    let bytes = @fs.read_file(path).binary()
    let segments : Array[(Int, Int)] = []
    let mut start = 0
    for index in 0..<bytes.length() {
      if bytes[index] == b'\n' {
        segments.push((start, index))
        start = index + 1
      }
    }
    let terminated = start == bytes.length()
    if !terminated {
      segments.push((start, bytes.length()))
    }
    // An unterminated final line needs the on-disk repair even when its
    // content parses: the next append would otherwise fuse two entries.
    let mut needs_repair = !terminated
    for index, segment in segments {
      let (from, to) = segment
      let parsed : Result[JournalEntry?, Error] = Ok(parse_line(bytes[from:to])) catch {
        error => Err(error)
      }
      match parsed {
        Ok(Some(entry)) => prior.push(entry)
        Ok(None) => ()
        Err(_) if index == segments.length() - 1 => needs_repair = true
        Err(_) => raise JournalCorrupted(path~, line=index + 1)
      }
    }
    if needs_repair {
      let out = StringBuilder()
      for entry in prior {
        out.write_string(({ "v": 1, "e": entry.to_json() } : Json).stringify())
        out.write_char('\n')
      }
      let tmp = path + ".repair"
      @fs.write_file(tmp, out.to_string())
      @fs.rename(tmp, path, replace=true)
    }
  }
  {
    prior,
    consumed: Array::make(prior.length(), false),
    path: Some(path),
    recorded: [],
    write_lock: Mutex(),
  }
}

///|
/// One line's entry, `None` for a blank line (also covers the `\r` a CRLF
/// writer leaves behind). Raises on undecodable bytes or unparsable JSON —
/// the caller decides whether that is a torn tail or corruption.
fn parse_line(segment : BytesView) -> JournalEntry? raise {
  let text = @utf8.decode(segment).trim()
  if text.is_empty() {
    return None
  }
  // Schema-versioned envelope: the storage format is an evolvable
  // contract of its own, never derived codec output blessed by accident.
  guard @json.parse(text.to_owned()) is { "v": Number(1, ..), "e": entry, .. } else {
    fail("journal line is not a v1 entry")
  }
  Some(@json.from_json(entry))
}

///|
/// This run's live outcomes, in completion order (a copy — the journal's
/// own bookkeeping cannot be skewed through it).
pub fn Journal::recorded(self : Journal) -> Array[JournalEntry] {
  self.recorded.copy()
}

///|
/// The prior-run entries replay draws from, in file order (a copy).
pub fn Journal::prior(self : Journal) -> Array[JournalEntry] {
  self.prior.copy()
}

///|
/// Two calls describe the same WORK: everything but the display label.
fn same_work(a : AgentCall, b : AgentCall) -> Bool {
  a.kind == b.kind &&
  a.input == b.input &&
  a.max_steps == b.max_steps &&
  a.scope == b.scope
}

///|
/// CLAIM the next replay candidate for one call, consuming it. Purely
/// synchronous — no suspension separates lookup from consumption, so
/// concurrent identical calls each claim a distinct entry. Selection
/// prefers successes (in file order); only when no unconsumed success
/// remains does the EARLIEST recorded skip stand in. The caller walks
/// candidates: a candidate its validator vetoes stays consumed, and the
/// next claim gets the next candidate — a stale generation must never
/// mask the valid one recorded after it. `release` rolls a claim back
/// when validation UNWINDS (cancellation, registry error): the entry was
/// neither served nor rejected, so it stays available.
fn Journal::claim(self : Journal, call : AgentCall) -> (Int, AgentOutcome)? {
  let mut skip_slot : Int? = None
  for index, entry in self.prior {
    if self.consumed[index] || !same_work(entry.call, call) {
      continue
    }
    match entry.outcome {
      Finished(..) => {
        self.consumed[index] = true
        return Some((index, entry.outcome))
      }
      DidNotFinish(failure=Skipped, ..) =>
        if skip_slot is None {
          skip_slot = Some(index)
        }
      DidNotFinish(..) => ()
    }
  }
  // No success to replay: a recorded human refusal still stands; any
  // other failure yields a live re-attempt.
  if skip_slot is Some(index) {
    self.consumed[index] = true
    return Some((index, self.prior[index].outcome))
  }
  None
}

///|
/// Roll back a claim whose validation unwound before deciding.
fn Journal::release(self : Journal, slot : Int) -> Unit {
  self.consumed[slot] = false
}

///|
/// Append one live outcome — to memory always, and through to the backing
/// file when there is one. Appends are serialized behind a mutex: one
/// entry's line may take several syscalls to write, and concurrent agent
/// completions must interleave at line granularity, never byte.
async fn Journal::record(self : Journal, entry : JournalEntry) -> Unit {
  self.recorded.push(entry)
  if self.path is Some(path) {
    self.write_lock.acquire()
    defer self.write_lock.release()
    // OpenOrCreate, not the default CreateOrTruncate: append must never
    // wipe the generations already on disk.
    @fs.write_file(
      path,
      ({ "v": 1, "e": entry.to_json() } : Json).stringify() + "\n",
      append=true,
      create_mode=OpenOrCreate,
    )
  }
}
