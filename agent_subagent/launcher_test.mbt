///|
/// Launcher tests against SCRIPTED children: a shell script that reads its
/// request line, finds its `--result-file` and `--session` among the
/// arguments the launcher appends, and `result FIELDS` writes a result
/// answering its request (whose id is the child's session).
let preamble : String =
  #|read line
  #|while [ $# -gt 0 ]; do
  #|  case "$1" in
  #|    --result-file) RESULT=$2; shift ;;
  #|    --session) SESSION=$2; shift ;;
  #|  esac
  #|  shift
  #|done
  #|result() { printf '{"version":1,"request_id":"%s",%s}' "$SESSION" "$1" > "$RESULT"; }
  #|

///|
let usage_fields : String =
  #|"usage":{"prompt_tokens":185,"completion_tokens":15,"total_tokens":200,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":185},"steps":3

///|
/// One launcher over a fresh store, and the job events its runtime emitted.
struct Harness {
  launcher : @agent_subagent.Launcher
  runtime : @bgjobs.BgJobRuntime
  root : String
  events : Array[@protocol.JobRecord]
}

///|
async fn[X] harness(
  group : @async.TaskGroup[X],
  script : String,
  max_live? : Int32,
  grace_ms? : Int32,
  delivery_timeout_ms? : Int32,
  reads~ : Bool = true,
) -> Harness {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  group.add_defer(() => @fs.rmdir(root, recursive=true))
  let events = []
  let runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), on_job_event=(
    _,
    record,
  ) => events.push(record))
  let launcher = @agent_subagent.Launcher(
    AgentTaskScope(group),
    runtime~,
    children=ChildSession(root~, parent="p"),
    program="sh",
    args=["-c", if reads { preamble + script } else { script }, "sh"],
    result_dir="\{root}/results",
    max_live?,
    grace_ms?,
    delivery_timeout_ms?,
  )
  { launcher, runtime, root, events, }
}

///|
fn accept(report : Json) -> Result[Json, String] {
  Ok(report)
}

///|
async fn Harness::start(
  self : Harness,
  validate? : (Json) -> Result[Json, String],
) -> (String, String) {
  match
    self.launcher.start(
      kind="explore",
      input={ "query": "q" },
      label="scout",
      launch=Direct,
      validate=validate.unwrap_or(accept),
    ) {
    Started(job_id~, session~) => (job_id, session)
    Busy => fail("unexpected Busy")
    Unavailable(reason) => fail("unexpected Unavailable: \{reason}")
  }
}

///|
/// Wait until a child has read its request and signalled it with
/// `touch "$RESULT.reading"`, so a teardown lands while it is truly live.
async fn Harness::reading(self : Harness) -> Unit {
  for _ in 0..<400 {
    let entries = @fs.readdir("\{self.root}/results") catch { _ => [] }
    if entries.any(name => name.has_suffix(".reading")) {
      return
    }
    @async.sleep(25)
  }
  fail("no child started reading")
}

///|
/// The child's settled subagent part, once its job is terminal.
async fn Harness::settled(
  self : Harness,
  job_id : String,
) -> @protocol.SubagentInfo {
  for _ in 0..<400 {
    if self.runtime.snapshot(job_id)
      is Some({ status: Exited(_) | Stopped, subagent: Some(info), .. }) {
      return info
    }
    @async.sleep(25)
  }
  fail("job \{job_id} did not settle")
}

///|
#cfg(not(platform="windows"))
async test "a child that reports is Captured, with its usage and stored report" {
  @async.with_task_group(group => {
    let h = harness(
      group,
      "result '\"status\":\"completed\",\"output\":{\"answer\":\"42\"},\{usage_fields}'",
    )
    let (job_id, session) = h.start()
    let info = h.settled(job_id)
    assert_eq(info.session, session)
    assert_true(info.outcome is Some(Captured))
    assert_true(
      info.usage
      is Some(
        Known(
          steps=Some(3),
          prompt_tokens=185,
          completion_tokens=15,
          source=Result,
          ..
        )
      ),
    )
    assert_true(info.report is Some(Stored))
    let stored = @json.parse(
      @fs.read_file("\{h.root}/sessions/\{session}/report.json").text(),
    )
    assert_eq(stored, { "answer": "42" })
    assert_true(h.launcher.report(session) is Some({ "answer": "42", .. }))
    // The result file is the launcher's to clean up; the slot is back.
    assert_true(@fs.readdir("\{h.root}/results") is [])
    assert_eq(h.launcher.live(), 0)
    // The job's record carries the subagent from its first event to its last.
    guard h.events is [first, .., last] else { fail("expected job events") }
    assert_true(first.subagent is Some({ outcome: None, .. }))
    assert_true(last.subagent is Some({ outcome: Some(Captured), .. }))
    assert_false(last.command.contains("--claim"))
  })
}

///|
#cfg(not(platform="windows"))
async test "a report its kind rejects is Failed and is not kept" {
  @async.with_task_group(group => {
    let h = harness(
      group, "result '\"status\":\"completed\",\"output\":{\"answer\":7}'",
    )
    let (job_id, session) = h.start(validate=_ => Err("answer must be a string"))
    let info = h.settled(job_id)
    assert_true(
      info.outcome is Some(Failed("report rejected: answer must be a string")),
    )
    assert_true(info.report is None)
    assert_true(h.launcher.report(session) is None)
  })
}

///|
#cfg(not(platform="windows"))
async test "a result for another request is not this child's report" {
  @async.with_task_group(group => {
    let h = harness(
      group,
      (
        #|printf '{"version":1,"request_id":"other","status":"completed","output":{}}' > "$RESULT"
      ),
    )
    let (job_id, _) = h.start()
    let info = h.settled(job_id)
    guard info.outcome is Some(Failed(reason)) else {
      fail("expected Failed, got \{Repr(info.outcome)}")
    }
    assert_true(reason.contains("another request"))
  })
}

///|
#cfg(not(platform="windows"))
async test "a child that leaves no result is Failed by its exit code" {
  @async.with_task_group(group => {
    let h = harness(group, "exit 1")
    let (job_id, _) = h.start()
    let info = h.settled(job_id)
    assert_true(
      info.outcome is Some(Failed("exited with code 1 without a result")),
    )
    assert_true(info.usage is Some(Unavailable("the child left no result")))
  })
}

///|
#cfg(not(platform="windows"))
async test "a result's own ending is the outcome" {
  for
    (status, expected) in [
      ("\"status\":\"no_report\"", @protocol.SubagentOutcome::NoReport),
      ("\"status\":\"max_steps_exhausted\"", MaxSteps),
      ("\"status\":\"context_yield\",\"reason\":\"full\"", ContextYield),
      ("\"status\":\"failed\",\"reason\":\"no key\"", Failed("no key")),
    ] {
    @async.with_task_group(group => {
      let h = harness(group, "result '\{status}'")
      let (job_id, _) = h.start()
      let info = h.settled(job_id)
      assert_eq(info.outcome, Some(expected))
    })
  }
}

///|
/// A stop closes the child's stdin and gives it a grace: a child that
/// reports in that window is still Captured.
#cfg(not(platform="windows"))
async test "a report written during a stop's grace is Captured" {
  @async.with_task_group(group => {
    let h = harness(
      group,
      (
        #|cat >/dev/null
        #|result '"status":"completed","output":{"answer":"late"}'
      ),
    )
    let (job_id, _) = h.start()
    @async.sleep(200)
    assert_true(h.runtime.stop(job_id))
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Captured))
  })
}

///|
/// A child that ignores its closed stdin is killed when the grace runs out.
#cfg(not(platform="windows"))
async test "a child that outlasts the grace is Stopped" {
  @async.with_task_group(group => {
    let h = harness(group, "trap '' TERM; sleep 30", grace_ms=200)
    let (job_id, _) = h.start()
    @async.sleep(200)
    assert_true(h.runtime.stop(job_id))
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Stopped))
    assert_eq(h.launcher.live(), 0)
  })
}

///|
/// A child that never takes its request is stopped as undelivered.
#cfg(not(platform="windows"))
async test "a request the child never reads is not delivered" {
  @async.with_task_group(group => {
    // The request is far larger than a pipe holds, and the child never
    // reads, so writing it blocks until the delivery deadline.
    let h = harness(
      group,
      "sleep 30",
      grace_ms=100,
      delivery_timeout_ms=300,
      reads=false,
    )
    let big = "x".repeat(1_000_000)
    let started = h.launcher.start(
      kind="explore",
      input={ "query": big },
      label="never reads",
      launch=Direct,
      validate=accept,
    )
    guard started is Started(job_id~, ..) else { fail("expected Started") }
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Failed("request not delivered")))
  })
}

///|
#cfg(not(platform="windows"))
async test "a session's slots bound live children, and come back" {
  @async.with_task_group(group => {
    let h = harness(group, "cat >/dev/null", max_live=1, grace_ms=100)
    let (first, _) = h.start()
    assert_true(
      h.launcher.start(
        kind="explore",
        input={ "query": "q" },
        label="second",
        launch=Direct,
        validate=accept,
      )
      is Busy,
    )
    assert_true(h.runtime.stop(first))
    let _ = h.settled(first)
    let (second, _) = h.start()
    assert_true(h.runtime.stop(second))
  })
}

///|
/// Session teardown ends a live child the same graceful way: its stdin
/// closes, and a report it writes then still counts.
#cfg(not(platform="windows"))
async test "session teardown gives a live child its grace" {
  let events : Array[@protocol.JobRecord] = []
  @async.with_task_group(group => {
    let h = harness(
      group,
      (
        #|touch "$RESULT.reading"
        #|cat >/dev/null
        #|result '"status":"completed","output":{"answer":"at shutdown"}'
      ),
    )
    group.add_defer(() => {
      @async.protect_from_cancel(() => h.runtime.finalize())
      for record in h.events {
        events.push(record)
      }
    })
    let _ = h.start()
    h.reading()
    fail("tear the session down")
  }) catch {
    _ => ()
  }
  guard events is [.., last] else { fail("expected job events") }
  guard last.subagent is Some({ outcome: Some(Captured), .. }) else {
    fail("expected Captured, got \{Repr(last.subagent)}")
  }
}

///|
/// A start cancelled before its child exists gives its slot back.
#cfg(not(platform="windows"))
async test "a cancelled start does not keep its slot" {
  @async.with_task_group(group => {
    let h = harness(group, "result '\"status\":\"no_report\"'", max_live=1)
    let outcome = @async.with_timeout_opt(0, () => h.start())
    if outcome is Some((job_id, _)) {
      // The start won the race; let it finish.
      let _ = h.settled(job_id)
    }
    for _ in 0..<100 {
      if h.launcher.live() == 0 {
        break
      }
      @async.sleep(10)
    }
    assert_eq(h.launcher.live(), 0)
  })
}

///|
/// A stop that interrupts a blocked request write is the child's end: the
/// write fails because of the stop, not first.
#cfg(not(platform="windows"))
async test "a stop during delivery is Stopped, not undelivered" {
  @async.with_task_group(group => {
    let h = harness(group, "sleep 30", grace_ms=100, reads=false)
    let big = "x".repeat(1_000_000)
    let started = h.launcher.start(
      kind="explore",
      input={ "query": big },
      label="blocked",
      launch=Direct,
      validate=accept,
    )
    guard started is Started(job_id~, ..) else { fail("expected Started") }
    @async.sleep(100)
    assert_true(h.runtime.stop(job_id))
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Stopped))
  })
}

///|
/// Teardown keeps draining a child's output through its grace: a child that
/// writes a lot after its stdin closes still reports, instead of dying on a
/// closed pipe.
#cfg(not(platform="windows"))
async test "teardown drains a child that writes during its grace" {
  let events : Array[@protocol.JobRecord] = []
  @async.with_task_group(group => {
    let h = harness(
      group,
      (
        #|touch "$RESULT.reading"
        #|cat >/dev/null
        #|i=0
        #|while [ $i -lt 20000 ]; do echo "winding down $i"; i=$((i+1)); done
        #|result '"status":"completed","output":{"answer":"after output"}'
      ),
    )
    group.add_defer(() => {
      @async.protect_from_cancel(() => h.runtime.finalize())
      for record in h.events {
        events.push(record)
      }
    })
    let _ = h.start()
    h.reading()
    fail("tear the session down")
  }) catch {
    _ => ()
  }
  guard events is [.., last] else { fail("expected job events") }
  guard last.subagent is Some({ outcome: Some(Captured), .. }) else {
    fail("expected Captured, got \{Repr(last.subagent)}")
  }
}

///|
/// Missing counts stay missing, and another request's account is not this
/// child's.
#cfg(not(platform="windows"))
async test "usage reports only what this child's result says" {
  @async.with_task_group(group => {
    let h = harness(
      group, "result '\"status\":\"no_report\",\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3,\"prompt_cache_hit_tokens\":0,\"prompt_cache_miss_tokens\":1}'",
    )
    let (job_id, _) = h.start()
    let info = h.settled(job_id)
    assert_true(
      info.usage
      is Some(Known(steps=None, prompt_tokens=1, completion_tokens=2, ..)),
    )
  })
  @async.with_task_group(group => {
    let h = harness(
      group,
      (
        #|printf '{"version":1,"request_id":"other","status":"no_report","usage":{"prompt_tokens":9,"completion_tokens":9,"total_tokens":18,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":9},"steps":4}' > "$RESULT"
      ),
    )
    let (job_id, _) = h.start()
    let info = h.settled(job_id)
    assert_true(info.usage is Some(Unavailable(_)))
  })
}
