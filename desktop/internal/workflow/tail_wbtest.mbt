///|
/// A journal line exactly as `moonbitlang/workflow` 0.7.0 writes one for a
/// call that finished: the entry under `e`, the outcome as a tagged array,
/// and the child's session id as `attempt_id`.
let finished_line : String =
  #|{"v":1,"e":{"call":{"kind":"explore","input":{"query":"who calls Y?"},"label":"scout:y","scope":""},"outcome":["Finished",{"value":{"answer":"..."},"attempt":{"attempt_id":"run7-sr-6","steps_used":7,"prompt_tokens":11,"completion_tokens":5}}],"phase":"survey","started_at":1788535817640,"finished_at":1788535817648}}

///|
/// A call that timed out: `DidNotFinish` with a unit failure and the attempt
/// it still cost.
let timed_out_line : String =
  #|{"v":1,"e":{"call":{"kind":"worker","input":{},"label":"edit:a","scope":""},"outcome":["DidNotFinish",{"failure":["TimedOut"],"attempt":{"attempt_id":"run7-sr-7","steps_used":40,"prompt_tokens":900,"completion_tokens":100,"cost_usd":0.02}}],"phase":"apply"}}

///|
/// A call refused before launch: no attempt, no child, nothing to point at.
let skipped_line : String =
  #|{"v":1,"e":{"call":{"kind":"explore","input":{},"label":"scout:z","scope":""},"outcome":["DidNotFinish",{"failure":["Skipped"],"attempt":null}],"phase":"survey"}}

///|
test "journal lines become ledger rows keyed by the child's session" {
  guard parse_journal(finished_line, workflow="wf-5", session="run7")
    is Some(row) else {
    fail("a finished entry must parse")
  }
  assert_eq(row.child, "run7-sr-6")
  assert_eq(row.kind, "explore")
  assert_eq(row.label, "scout:y")
  assert_eq(row.phase, Some("survey"))
  assert_eq(row.status, "captured")
  assert_eq(row.steps, 7)
  assert_eq(row.prompt_tokens, 11)
  assert_eq(row.completion_tokens, 5)
  assert_eq(row.cost_usd, None)
  assert_eq(row.started_at, Some(1788535817640.0))
  assert_eq(row.finished_at, Some(1788535817648.0))
  // A failure keeps the contract's snake_case vocabulary, and its spend.
  guard parse_journal(timed_out_line, workflow="wf-5", session="run7")
    is Some(row) else {
    fail("a timed-out entry must parse")
  }
  assert_eq(row.status, "timed_out")
  assert_eq(row.steps, 40)
  assert_eq(row.cost_usd, Some(0.02))
  assert_eq(row.started_at, None)
  // A refused call launched nothing: there is no child for a per-subagent
  // view to point at, and the sidecar never reported one.
  assert_true(
    parse_journal(skipped_line, workflow="wf-5", session="run7") is None,
  )
  // Unknown lines are not rows.
  assert_true(
    parse_journal("{\"v\":2}", workflow="wf-5", session="run7") is None,
  )
  assert_true(
    parse_journal("not json", workflow="wf-5", session="run7") is None,
  )
}

///|
test "sidecar lines are launches and finishes, carrying the child's session" {
  let started_line : String =
    #|{"event":"agent_started","child":"run7-sr-5","kind":"explore","label":"scout:x"}
  guard parse_sidecar(started_line) is Some(Ok(started)) else {
    fail("a started line must parse")
  }
  assert_eq(started, { child: "run7-sr-5", kind: "explore", label: "scout:x", })
  let finished_line : String =
    #|{"event":"agent_finished","child":"run7-sr-5","status":"captured","steps":12,"tokens":3400}
  guard parse_sidecar(finished_line) is Some(Err(finished)) else {
    fail("a finished line must parse")
  }
  assert_eq(finished, {
    child: "run7-sr-5",
    status: "captured",
    steps: 12,
    tokens: 3400,
  })
  assert_true(parse_sidecar("{\"event\":\"phase\"}") is None)
}

///|
/// The tail reads only what was appended, survives a poll landing mid-line,
/// and starts over when the file it was reading is replaced by a shorter one.
async test "a file tail reads appended lines exactly once" {
  let dir = @fs.tmpdir(prefix="workflow-tail-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let path = "\{dir}/events.jsonl"
  let tail : FileTail = { path, offset: 0, carry: b"", }
  // Nothing yet: not an error, just nothing.
  assert_eq(tail.poll(), [])
  @fs.write_file(path, "one\ntwo\n", create_mode=CreateOrTruncate)
  assert_eq(tail.poll(), ["one", "two"])
  assert_eq(tail.poll(), [])
  // A partial line waits for its newline.
  @fs.write_file(path, "thr", append=true, create_mode=OpenOrCreate)
  assert_eq(tail.poll(), [])
  @fs.write_file(path, "ee\n", append=true, create_mode=OpenOrCreate)
  assert_eq(tail.poll(), ["three"])
  // Replaced by something shorter: re-read from the head.
  @fs.write_file(path, "new\n", create_mode=CreateOrTruncate)
  assert_eq(tail.poll(), ["new"])
}

///|
async test "follow_run reports launches, finishes and ledger rows in file order" {
  let dir = @fs.tmpdir(prefix="workflow-follow-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let events = "\{dir}/events.jsonl"
  let journal = "\{dir}/journal.jsonl"
  let seen : Array[String] = []
  @async.with_task_group() <| group => {
    let tail = group.spawn(no_wait=true, allow_failure=true, () => {
      follow_run(
        workflow="wf-5",
        session="run7",
        journal~,
        events~,
        on_child_started=started => seen.push("started \{started.child}"),
        on_child_finished=finished => {
          seen.push("finished \{finished.child} \{finished.status}")
        },
        on_entry=entry => seen.push("entry \{entry.child} \{entry.status}"),
      )
    })
    let started : String =
      #|{"event":"agent_started","child":"run7-sr-6","kind":"explore","label":"scout:y"}
    @fs.write_file(events, started + "\n", create_mode=CreateOrTruncate)
    @async.sleep(2200)
    let ended : String =
      #|{"event":"agent_finished","child":"run7-sr-6","status":"captured","steps":7,"tokens":16}
    @fs.write_file(events, ended + "\n", append=true, create_mode=OpenOrCreate)
    @fs.write_file(journal, finished_line + "\n", create_mode=CreateOrTruncate)
    @async.sleep(2200)
    tail.cancel()
  }
  assert_eq(seen, [
    "started run7-sr-6", "finished run7-sr-6 captured", "entry run7-sr-6 captured",
  ])
}
