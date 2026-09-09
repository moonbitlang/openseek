///|
/// Exercise the hosted process contract offline. The fixture rejects the
/// scout-shaped input and verifies the review criteria and step envelope.
async test "hosted review carries criteria and returns a structured report" {
  let dir = @fs.tmpdir(prefix="hosted-review-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let child = "\{dir}/review.mbtx"
  @fs.write_file(
    child,
    (
      #|import {
      #|  "moonbitlang/async",
      #|  "moonbitlang/async/stdio",
      #|  "moonbitlang/core/json",
      #|}
      #|async fn main {
      #|  guard @stdio.stdin.read_until("\n") is Some(line) else { return }
      #|  let request = @json.parse(line)
      #|  guard request is {
      #|    "workflow_contract": 1,
      #|    "kind": "review",
      #|    "max_steps": 100,
      #|    "input": { "goal": "Check CSV CRLF handling", "sha": "abc", "dirty": true, .. },
      #|    ..
      #|  } else { fail("unexpected review request") }
      #|  let response : Json = { "subrun_report": {
      #|    "schema_version": 1,
      #|    "scope": { "base": "abc", "head": "WORKTREE", "files": [] },
      #|    "findings": [],
      #|    "summary": "offline fixture report",
      #|    "stats": { "files_reviewed": 0, "findings": 0, "build": "skipped", "tests": "skipped" },
      #|  }}
      #|  println(response.stringify())
      #|}
    ),
  )
  guard @hosted.parse({
      "v": 1,
      "exe": "moon",
      "child_args": ["run", child],
      "child_id": "review-test-sr-{n}",
      "ids": [1, 1],
      "journal": "\{dir}/journal.jsonl",
      "events": "\{dir}/events.jsonl",
    })
    is Some(ctx) else {
    fail("expected hosted context")
  }
  let json = ctx.run(wf => {
    wf.agent_call(
      kind="review",
      input={ "goal": "Check CSV CRLF handling", "sha": "abc", "dirty": true },
      label="CSV review",
      max_steps=100,
    )
  })
  guard @agent_review.ReviewReport::parse(json) is Ok(report) else {
    fail("expected review report")
  }
  assert_eq(report.validate(), [])
  assert_eq(report.finding_count(), 0)
  let journal = @fs.read_file("\{dir}/journal.jsonl").text()
  assert_true(journal.contains("review-test-sr-1"))
  let events = @fs.read_file("\{dir}/events.jsonl").text()
  assert_true(events.contains("\"status\":\"captured\""))
}
