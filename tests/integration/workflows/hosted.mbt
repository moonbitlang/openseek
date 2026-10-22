///|
/// A fake OpenSeek host for the bundled subagent workflows: it speaks the PTC
/// wire protocol (`OPENSEEK_PTC`) and answers `subagent`, `job_wait`,
/// `job_output` and `audit_context` from a script, the way the engine would,
/// recording every subagent start for the assertions. Reports are served in
/// small chunks, so the workflows' chunked reading is exercised too.
struct FakeHost {
  name : String
  mode : String
  // The engine's standing goal and baseline, as `audit_context` returns it.
  audit : Json
  // Every `subagent` call's arguments, in order.
  starts : Array[Json]
  // Each started child's report, or why it has none.
  reports : Map[String, Result[Json, String]]
  // The simplify sweep's host: jobs still running, which of them are
  // workers, each worker's worktree record, and the commits the scripted
  // workers report (by package directory, plus "head").
  running : Array[String]
  workers : Array[String]
  workspaces : Map[String, Json]
  fixture : Map[String, String]
}

///|
/// How much of a report one `job_output` reply carries here: small, so a
/// report takes several reads.
const ChunkChars : Int32 = 40

///|
fn reply(content : String, data? : Json, is_error~ : Bool = false) -> Json {
  let fields : Map[String, Json] = {
    "version": 1,
    "content": Json::string(content),
    "is_error": Json::boolean(is_error),
  }
  if data is Some(data) {
    fields["data"] = data
  }
  Json::object(fields)
}

///|
fn FakeHost::answer(
  self : FakeHost,
  name : String,
  arguments : Json,
) -> Json raise {
  match name {
    "audit_context" => reply("audit context", data=self.audit)
    "subagent" => {
      // "busy": every start is refused; "busy-last": the session fills up
      // just before the last one.
      let last = if self.name == "repo-map" { 2 } else { 3 }
      if self.mode == "busy" ||
        (self.mode == "busy-last" && self.starts.length() + 1 == last) {
        return reply("error: 4 subagents are already running", is_error=true)
      }
      // A swarm whose session fills up just as one lens starts.
      if (
          self.mode == "swarm-incomplete" &&
          arguments is { "label": "review:architecture", .. }
        ) ||
        (
          self.mode == "swarm-verifier-refused" &&
          arguments is { "label": String(label), .. } &&
          label.has_prefix("review:verify-")
        ) {
        return reply("error: 16 subagents are already running", is_error=true)
      }
      if self.mode == "simplify-refused" &&
        arguments is { "label": String(label), .. } &&
        label.has_prefix("simplify:review-") {
        return reply("error: 16 subagents are already running", is_error=true)
      }
      // The engine runs at most 8 workers at once and refuses a ninth.
      if self.name == "simplify" &&
        arguments is { "kind": "worker", .. } &&
        self.workers.filter(id => self.running.contains(id)).length() >= 8 {
        return reply("error: 8 workers are already running", is_error=true)
      }
      self.starts.push(arguments)
      let job = "job-\{self.starts.length()}"
      self.running.push(job)
      if arguments is { "kind": "worker", .. } {
        self.workers.push(job)
      }
      self.reports[job] = if self.name == "simplify" {
        self.simplify_child(job, arguments)
      } else {
        child_report(self.name, self.mode, job, arguments)
      }
      reply("started \{job}", data={ "job_id": job, "session": "p-sr-\{job}" })
    }
    "job_wait" => {
      guard arguments is { "job_ids": Array(ids), .. } else {
        return reply("error: job_ids", is_error=true)
      }
      // The sweep's host ends one job per wait, as a real session does
      // when its children finish at different times; the others end all.
      let waiting = [
        for id in ids if id is String(id) && self.running.contains(id) => id
      ]
      // A worker reported ended before its capture finished: every read
      // until the next wait sees its worktree still working.
      for id in ids {
        if id is String(id) &&
          !waiting.contains(id) &&
          self.fixture.get("capture:\{id}") is Some(captured) {
          self.fixture.remove("capture:\{id}")
          self.workspaces[id] = @json.parse(captured)
        }
      }
      if self.name != "simplify" {
        self.running.clear()
      } else if waiting is [first, ..] &&
        self.running.search(first) is Some(index) {
        ignore(self.running.remove(index))
      }
      let jobs : Array[Json] = ids.map(id => {
        "job_id": id,
        "state": if id is String(id) && self.running.contains(id) {
          "running"
        } else {
          "ended"
        },
        "outcome": "reported",
      })
      reply("waited", data={ "jobs": Json::array(jobs) })
    }
    "job_output" => {
      guard arguments is { "job_id": String(job), .. } &&
        self.reports.get(job) is Some(report) else {
        return reply("error: unknown job", is_error=true)
      }
      let offset = match arguments {
        { "offset": Number(offset, ..), .. } => offset.to_int()
        _ => 0
      }
      let usage : Json = {
        "kind": "known",
        "prompt_tokens": 10,
        "completion_tokens": 2,
        "source": "result",
      }
      let subagent : Map[String, Json] = { "usage": usage }
      if self.workspaces.get(job) is Some(workspace) {
        subagent["workspace"] = workspace
      }
      let subagent = Json::object(subagent)
      match report {
        Err(why) =>
          reply("no report", data={
            "job_id": job,
            "state": { "job_id": job, "state": "ended", "outcome": why },
            "subagent": subagent,
          })
        Ok(report) => {
          let text = report.stringify()
          let total = text.char_length()
          let chunk = String::from_iter(
            text.iter().drop(offset).take(ChunkChars),
          )
          reply("report", data={
            "job_id": job,
            "state": { "job_id": job, "state": "ended", "outcome": "reported" },
            "subagent": subagent,
            "report": {
              "chunk": chunk,
              "offset": offset,
              "total": total,
              "complete": offset + chunk.char_length() >= total,
            },
          })
        }
      }
    }
    _ => reply("PTC tool unavailable: \{name}", is_error=true)
  }
}

///|
/// The report a scripted child returns for `arguments`, checking first that
/// the workflow asked for what it should.
fn child_report(
  name : String,
  mode : String,
  job : String,
  arguments : Json,
) -> Result[Json, String] raise {
  if name == "review" {
    return Ok(review_report(mode, arguments))
  }
  if name == "review-swarm" {
    return swarm_child(mode, arguments)
  }
  let steps = if name == "repo-map" { 12 } else { 16 }
  assert_true(arguments is { "kind": "explore", .. })
  assert_true(
    arguments is { "max_steps": Number(value, ..), .. } &&
    value == steps.to_double(),
    msg=arguments.stringify(),
  )
  if name == "repo-map" {
    guard arguments is { "input": { "query": String(query), .. }, .. } else {
      fail("Missing query")
    }
    for
      expected in [
        "1 | orientation fixture", "[Excerpt truncated; read the file for the remainder.]",
        "sample/:", "real_implementation.mbt", "pkg.generated.mbti", "moon.pkg",
        "cmd/main/:", "main.mbt",
      ] {
      assert_true(query.contains(expected), msg=expected)
    }
    assert_false(query.contains("excluded tail"))
  }
  if mode == "partial" && job == "job-2" {
    return Err("failed: scripted child failure")
  }
  let file = match mode {
    "missing-file" => "absent.mbt"
    "directory" => "sample"
    "escape" => "escape.md"
    "traversal" => "../outside.md"
    _ => "cmd/main/main.mbt"
  }
  let line : Json = match mode {
    "bad-line" => 2
    "fractional-line" => 1.5
    _ => 1
  }
  let citations : Array[Json] = if mode == "no-citations" {
    []
  } else {
    [{ "file": file, "line": line }]
  }
  Ok({
    // Deliberately malformed empty answer tests the workflow's rejection.
    "answer": if mode == "empty" && job == "job-2" {
      ""
    } else {
      "offline evidence " + job
    },
    "citations": citations,
  })
}

///|
/// The review child: one `review` start carrying the criteria the script
/// resolved (its arguments, the engine's standing goal, or both) and a
/// baseline only when one was given, answered with a report in the review
/// contract's shape.
fn review_report(mode : String, arguments : Json) -> Json raise {
  guard arguments is { "kind": "review", "max_steps": 100, "input": input, .. } else {
    fail("unexpected review start: \{arguments.stringify()}")
  }
  let (goal, baseline) : (String, (String, Bool)?) = match mode {
    "baseline" => ("Check CSV CRLF handling", Some(("abc", true)))
    "standing" => ("Standing goal", Some(("def", false)))
    "focus" => ("Standing goal\n\nAudit focus:\nCheck CSV CRLF handling", None)
    "override" => ("Standing goal", Some(("abc", true)))
    _ => ("Check CSV CRLF handling", None)
  }
  guard input is { "goal": String(actual), .. } && actual == goal else {
    fail("unexpected criteria: \{input.stringify()}")
  }
  match baseline {
    Some((sha, dirty)) =>
      assert_true(
        input is { "sha": String(actual_sha), "dirty": actual_dirty, .. } &&
        actual_sha == sha &&
        actual_dirty == Json(dirty),
        msg=input.stringify(),
      )
    None => assert_false(input is { "sha": _, .. }, msg=input.stringify())
  }
  let finding : (String, String) -> Json = (severity, title) => {
    "file": "cmd/main/main.mbt",
    "line": 1,
    "severity": severity,
    "category": "correctness",
    "title": title,
    "detail": "offline fixture finding",
    "suggestion": null,
  }
  let findings : Array[Json] = if mode == "blockers" {
    [finding("blocker", "claim does not hold"), finding("high", "also this")]
  } else {
    []
  }
  {
    "schema_version": 1,
    "scope": { "base": "abc", "head": "WORKTREE", "files": [] },
    "findings": findings,
    "summary": "offline fixture report",
    "stats": {
      "files_reviewed": 0,
      "findings": findings.length(),
      "build": "skipped",
      "tests": "skipped",
    },
  }
}

///|
/// Run the compiled workflow `artifact` with `args` in `cwd` against `host`
/// (or with no host at all), and return its exit code and output.
async fn run_against(
  host : FakeHost?,
  artifact : String,
  args : Array[String],
  cwd~ : String,
  extra_env? : Map[String, String],
) -> (Int32, String) {
  let env = clean_env()
  if extra_env is Some(extra) {
    for name, value in extra {
      env[name] = value
    }
  }
  @async.with_task_group(group => {
    if host is Some(host) {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.add_defer(() => server.close())
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(
          (head, body, conn) => {
            let authorized = head.headers
              .iter()
              .any(entry => {
                entry.0.to_string().to_lower() == "authorization" &&
                entry.1 == "Bearer fixture-token"
              })
            assert_true(authorized)
            let request = @json.parse(body.read_all().text())
            guard request
              is {
                "version": 1,
                "name": String(name),
                "arguments": arguments,
                ..
              } else {
              fail("malformed PTC request: \{request.stringify()}")
            }
            let answer = host.answer(name, arguments)
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            conn.write(answer.stringify())
            conn.end_response()
            conn.close()
          },
          // A client that hangs up after its answer is not a failure.
          allow_failure=true,
        )
      })
      let handoff : Json = {
        "version": 1,
        "url": "http://127.0.0.1:\{server.addr.port()}/call",
        "token": "fixture-token",
        "approval_tools": [],
      }
      env["OPENSEEK_PTC"] = handoff.stringify()
    }
    let result = @shell.Cmd(
      "moonrun",
      [artifact, "--", ..args],
      cwd~,
      env~,
      inherit_env=false,
    ).output(timeout_ms=60000)
    (result.exit_code(), result.stdout() + result.stderr())
  })
}

///|
fn fake_host(name : String, mode : String, audit~ : Json = null) -> FakeHost {
  {
    name,
    mode,
    audit,
    starts: [],
    reports: Map([]),
    running: [],
    workers: [],
    workspaces: Map([]),
    fixture: Map([]),
  }
}

///|
async fn verify_review(root : String, temp : String) -> Unit {
  let repo = temp + "/review-repository"
  @fs.mkdir(repo)
  let artifact = compile(root, temp, "review")
  for
    mode in [
      "success", "baseline", "blockers", "standing", "focus", "override", "missing",
      "no-criteria", "dirty-without-sha", "help", "invalid-audit", "invalid-baseline",
    ] {
    // The engine's standing goal, as audit_context answers.
    let audit : Json = match mode {
      "standing" | "override" =>
        { "goal": "Standing goal", "sha": "def", "dirty": false }
      "focus" => { "goal": "Standing goal" }
      "invalid-audit" => { "goal": 42 }
      "invalid-baseline" =>
        { "goal": "Standing goal", "sha": "def", "dirty": "false" }
      _ => null
    }
    let host = fake_host("review", mode, audit~)
    let args = match mode {
      "baseline" =>
        ["--sha", "abc", "--dirty", "--", "Check", "CSV", "CRLF", "handling"]
      "override" => ["--sha", "abc", "--dirty"]
      "standing" | "no-criteria" => []
      "dirty-without-sha" => ["--dirty", "Check CSV CRLF handling"]
      "help" => ["--help"]
      _ => ["Check CSV CRLF handling"]
    }
    let (code, output) = run_against(
      if mode == "missing" {
        None
      } else {
        Some(host)
      },
      artifact,
      args,
      cwd=repo,
    )
    let succeeds = match mode {
      "success" | "baseline" | "standing" | "focus" | "override" | "help" =>
        true
      _ => false
    }
    assert_eq(code == 0, succeeds, msg=output)
    let reviewed = match mode {
      "success" | "baseline" | "blockers" | "standing" | "focus" | "override" =>
        1
      _ => 0
    }
    assert_eq(host.starts.length(), reviewed, msg=output)
    let expected = match mode {
      "blockers" => "does not hold yet"
      "invalid-audit" => "invalid audit context"
      "invalid-baseline" => "invalid audit baseline"
      "missing" => "TransportError"
      "no-criteria" => "no criteria given"
      "dirty-without-sha" => "--dirty needs --sha"
      "help" => "usage:"
      _ => "findings=0 blockers=0 tokens=12"
    }
    assert_true(output.contains(expected), msg=output)
    assert_eq(
      output.contains("offline fixture report"),
      reviewed == 1,
      msg=output,
    )
    // The report is printed BEFORE the blocker exit, so the caller reads it.
    assert_eq(
      output.contains("findings=2 blockers=1"),
      mode == "blockers",
      msg=output,
    )
    println("review: \{mode} passed")
  }
  verify_review_swarm(repo, artifact)
}

///|
/// A finding in the review contract's shape.
fn swarm_finding(
  file : String,
  line : Int32?,
  severity : String,
  title : String,
) -> Json {
  // Absent optional fields are left out, as the contract's decoder needs.
  let fields : Map[String, Json] = {
    "file": Json::string(file),
    "severity": Json::string(severity),
    "category": "correctness",
    "title": Json::string(title),
    "detail": Json::string("detail of " + title),
  }
  if line is Some(line) {
    fields["line"] = Json::number(line.to_double())
  }
  Json::object(fields)
}

///|
/// A report in the review contract's shape.
fn swarm_report(
  findings : Array[Json],
  summary : String,
  build~ : String = "skipped",
  tests~ : String = "skipped",
  files~ : Array[String] = [],
) -> Json {
  {
    "schema_version": 1,
    "scope": {
      "base": "abc",
      "head": "WORKTREE",
      "files": Json::array(files.map(Json::string)),
    },
    "findings": Json::array(findings),
    "summary": summary,
    "stats": {
      "files_reviewed": Json::number(files.length().to_double()),
      "findings": Json::number(findings.length().to_double()),
      "build": build,
      "tests": tests,
    },
  }
}

///|
/// One swarm child: a lens reviewer (`review:<lens>`, 100 steps) answered
/// with that lens's scripted findings, or a verifier (`review:verify-N`, 40
/// steps) answered according to the allegation its brief names. Checks first
/// that the script framed each child as the design says.
fn swarm_child(mode : String, arguments : Json) -> Result[Json, String] raise {
  guard arguments
    is {
      "kind": "review",
      "label": String(label),
      "max_steps": Number(steps, ..),
      "input": { "goal": String(goal), .. } as input,
      ..
    } else {
    fail("unexpected swarm start: \{arguments.stringify()}")
  }
  // The baseline reaches every child, lens and verifier alike.
  if mode == "swarm-merge" {
    assert_true(
      input is { "sha": "abc", "dirty": true, .. },
      msg=input.stringify(),
    )
  } else {
    assert_false(input is { "sha": _, .. }, msg=input.stringify())
  }
  match label.strip_prefix("review:verify-") {
    Some(_) => {
      assert_eq(steps, 40.0)
      // The original criteria and the allegation, kept apart.
      assert_true(
        goal.contains(
          "## The criteria the work is held to (verbatim)\nCheck the cache",
        ),
        msg=goal,
      )
      assert_true(goal.contains("## The allegation"))
      // A merged claim is shown at its own finding's place: the blocker
      // architecture reported at line 12, not correctness's line 10.
      if goal.contains("Title: Range end off by one") {
        assert_true(
          goal.contains("File: src/a.mbt\nLine: 12\nSeverity claimed: blocker"),
          msg=goal,
        )
      }
      verifier_reply(goal)
    }
    None => {
      assert_eq(steps, 100.0)
      let lens = label.strip_prefix("review:").unwrap().to_owned()
      assert_true(goal.has_prefix("Check the cache"), msg=goal)
      assert_true(goal.contains("Review lens: \{lens}"), msg=goal)
      // Each lens carries its own focus paragraph and the closing rule.
      let focus = match lens {
        "correctness" => "concurrency and cancellation"
        "architecture" => "Layering and ownership"
        "tests" => "no test pins"
        "compatibility" => "Public API (.mbti)"
        "security" => "trust boundaries"
        _ => fail("unexpected lens \{lens}")
      }
      assert_true(goal.contains(focus), msg=goal)
      assert_true(
        goal.has_suffix(
          "Report only findings within this lens; other reviewers cover the rest.",
        ),
        msg=goal,
      )
      lens_reply(mode, lens)
    }
  }
}

///|
/// What each lens reports in each scenario.
fn lens_reply(mode : String, lens : String) -> Result[Json, String] {
  let a = "src/a.mbt"
  match (mode, lens) {
    ("swarm-merge", "correctness") =>
      Ok(
        swarm_report(
          [
            swarm_finding(a, Some(10), "high", "Off by one in range end"),
            swarm_finding(
              a,
              Some(11),
              "medium",
              "Missing error propagation on close",
            ),
            // One lens's two findings never merge, even with the same title.
            swarm_finding(a, Some(10), "high", "Off by one in range end"),
          ],
          "correctness summary",
          files=[a],
        ),
      )
    ("swarm-merge", "architecture") =>
      Ok(
        swarm_report(
          [
            // The same claim as correctness's, two lines away: merged.
            swarm_finding("./" + a, Some(12), "blocker", "Range end off by one"),
            // Another claim at the same place: kept apart.
            swarm_finding(a, Some(10), "high", "Unbounded cache growth"),
          ],
          "architecture summary",
          files=["src/b.mbt"],
        ),
      )
    ("swarm-merge", "tests") =>
      Ok(swarm_report([], "tests summary", build="pass", tests="fail"))
    ("swarm-refute-blocker", _) =>
      Ok(
        swarm_report(
          [swarm_finding(a, Some(3), "blocker", "Claimed deadlock in flush")],
          "one blocker",
        ),
      )
    ("swarm-unverified", "correctness") =>
      Ok(
        swarm_report(
          [
            swarm_finding(a, Some(1), "high", "Inconclusive claim"),
            swarm_finding(a, Some(40), "high", "Claim without verdict"),
            swarm_finding(a, Some(80), "high", "Unreported claim"),
          ],
          "correctness summary",
        ),
      )
    ("swarm-unverified", "tests") =>
      Ok(
        swarm_report(
          [
            swarm_finding(
              "src/b.mbt",
              None,
              "blocker",
              "Elsewhere confirmed claim",
            ),
            swarm_finding(
              "src/c.mbt",
              Some(5),
              "high",
              "Doubly confirmed claim",
            ),
          ],
          "tests summary",
        ),
      )
    ("swarm-incomplete", "correctness") =>
      Ok(
        swarm_report(
          [swarm_finding(a, Some(2), "medium", "A medium finding")],
          "correctness summary",
        ),
      )
    ("swarm-incomplete", "tests") => Err("failed: step limit")
    ("swarm-verify-cap", "correctness") =>
      Ok(
        swarm_report(
          [
            swarm_finding(a, Some(2), "high", "A high finding"),
            swarm_finding(a, Some(30), "blocker", "Claimed deadlock in flush"),
          ],
          "correctness summary",
        ),
      )
    ("swarm-verifier-refused", _) =>
      Ok(
        swarm_report(
          [swarm_finding(a, Some(3), "blocker", "Claimed deadlock in flush")],
          "one blocker",
        ),
      )
    ("swarm-none", _) => Err("failed: step limit")
    ("swarm-verdict-format", _) =>
      Ok(
        swarm_report(
          [
            swarm_finding(a, Some(1), "high", "Literal newline claim"),
            swarm_finding(a, Some(3), "high", "Period claim"),
            swarm_finding(a, Some(5), "high", "Glued claim"),
            swarm_finding(a, Some(20), "high", "Compound claim"),
            swarm_finding(a, Some(40), "high", "Trailing words claim"),
          ],
          "correctness summary",
        ),
      )
    ("swarm-verify-off" | "swarm-budget" | "swarm-under-budget", "correctness") =>
      Ok(
        swarm_report(
          [swarm_finding(a, Some(2), "high", "A high finding")],
          "correctness summary",
        ),
      )
    _ => Ok(swarm_report([], "\{lens} found nothing"))
  }
}

///|
/// A verifier's answer, chosen by the allegation's title.
fn verifier_reply(goal : String) -> Result[Json, String] {
  let title = match
    goal.split("\n").find_first(line => line.has_prefix("Title: ")) {
    Some(line) => line.strip_prefix("Title: ").unwrap().to_owned()
    None => return Err("the verifier brief names no title: \{goal}")
  }
  let restated = swarm_finding("src/a.mbt", Some(10), "low", title)
  match title {
    // A verifier may not re-grade: "low" here must not demote the blocker.
    "Off by one in range end" | "Range end off by one" =>
      Ok(swarm_report([restated], "VERDICT: CONFIRMED\nreproduced it"))
    "Unbounded cache growth" | "Claimed deadlock in flush" =>
      Ok(
        swarm_report([], "VERDICT: REFUTED\nthe cache is bounded by its caller"),
      )
    "A high finding" =>
      Ok(
        swarm_report(
          [swarm_finding("src/a.mbt", Some(2), "high", title)],
          "VERDICT: CONFIRMED\nreproduced it",
        ),
      )
    // What a live verifier wrote: a literal backslash-n after the token.
    "Literal newline claim" =>
      Ok(
        swarm_report(
          [swarm_finding("src/a.mbt", Some(1), "high", title)],
          "VERDICT: CONFIRMED\\n\\nreproduced it",
        ),
      )
    "Period claim" =>
      Ok(swarm_report([], "VERDICT: REFUTED.\nthe code checks it"))
    // A token run into a word, a hedge between two verdicts, and a token
    // with more words on its line are no verdicts.
    "Glued claim" => Ok(swarm_report([], "VERDICT: REFUTEDLY not"))
    "Compound claim" =>
      Ok(swarm_report([], "VERDICT: REFUTED/INCONCLUSIVE\ncould not run it"))
    "Trailing words claim" =>
      Ok(swarm_report([], "VERDICT: REFUTED or maybe not"))
    "Inconclusive claim" =>
      Ok(swarm_report([], "VERDICT: INCONCLUSIVE\nno way to run it"))
    "Claim without verdict" => Ok(swarm_report([], "looked around, unsure"))
    "Unreported claim" => Err("failed: step limit")
    "Elsewhere confirmed claim" =>
      // Confirmed, but about a different file than the allegation's.
      Ok(swarm_report([restated], "VERDICT: CONFIRMED\nyes"))
    "Doubly confirmed claim" =>
      Ok(
        swarm_report(
          [
            swarm_finding("src/c.mbt", Some(5), "high", title),
            swarm_finding("src/c.mbt", Some(6), "high", "and another"),
          ],
          "VERDICT: CONFIRMED\nyes",
        ),
      )
    _ => Err("unexpected allegation: \{title}")
  }
}

///|
/// Swarm mode against the fake host: who starts, what merges, how each
/// verdict is read, and when the run fails.
async fn verify_review_swarm(repo : String, artifact : String) -> Unit {
  let criteria = "Check the cache"
  for
    mode in [
      "swarm-merge", "swarm-refute-blocker", "swarm-unverified", "swarm-incomplete",
      "swarm-verify-off", "swarm-verify-cap", "swarm-budget", "swarm-under-budget",
      "swarm-lens-text", "swarm-verifier-refused", "swarm-none", "swarm-verdict-format",
      "swarm-unknown-lens", "swarm-verify-alone", "swarm-bad-number", "swarm-duplicate-lens",
    ] {
    let host = fake_host("review-swarm", mode)
    let args = match mode {
      "swarm-merge" => ["--sha", "abc", "--dirty", "--swarm", "--", criteria]
      "swarm-refute-blocker" => ["--lens", "correctness", criteria]
      "swarm-unverified" =>
        ["--lens", "correctness", "--lens", "tests", criteria]
      "swarm-incomplete" => ["--swarm", criteria]
      "swarm-verify-off" => ["--swarm", "--verify", "0", criteria]
      "swarm-verify-cap" => ["--lens", "correctness", "--verify", "1", criteria]
      "swarm-budget" => ["--swarm", "--max-tokens", "30", criteria]
      "swarm-under-budget" => ["--swarm", "--max-tokens", "1000", criteria]
      "swarm-lens-text" =>
        ["--lens", "compatibility", "--lens", "security", criteria]
      "swarm-verifier-refused" | "swarm-none" | "swarm-verdict-format" =>
        ["--lens", "correctness", criteria]
      "swarm-bad-number" => ["--swarm", "--verify", "9", criteria]
      "swarm-duplicate-lens" => ["--lens", "tests", "--lens", "tests", criteria]
      "swarm-unknown-lens" => ["--lens", "style", criteria]
      _ => ["--verify", "2", criteria]
    }
    let (code, output) = run_against(Some(host), artifact, args, cwd=repo)
    let labels = host.starts.map(start => {
      match start {
        { "label": String(label), .. } => label
        _ => ""
      }
    })
    let (succeeds, started, expected) : (Bool, Array[String], Array[String]) = match
      mode {
      "swarm-merge" =>
        (
          false,
          [
            "review:correctness", "review:architecture", "review:tests", "review:verify-1",
            "review:verify-2", "review:verify-3",
          ],
          [
            // The merged claim keeps the blocker; the verifier's "low" is
            // ignored. Correctness's repeated finding stays its own claim.
            "findings=3 blockers=1 tokens=72 lenses=3/3 verified=2 refuted=1 unverified=1",
            "[found by: correctness, architecture]", "Refuted: Unbounded cache growth (src/a.mbt:10): the cache is bounded by its caller",
            "\"files\":[\"src/a.mbt\",\"src/b.mbt\"]", "\"build\":\"pass\"", "\"tests\":\"fail\"",
            "lens tests: reported, findings=0, files=0, tokens=12", "1 blocker finding(s)",
            "[verified] detail of Off by one in range end", "[unverified]\"",
          ],
        )
      "swarm-refute-blocker" =>
        (
          true,
          ["review:correctness", "review:verify-1"],
          ["findings=0 blockers=0 tokens=24 lenses=1/1 verified=0 refuted=1"],
        )
      "swarm-unverified" =>
        (
          false,
          [
            "review:correctness", "review:tests", "review:verify-1", "review:verify-2",
            "review:verify-3", "review:verify-4", "review:verify-5",
          ],
          [
            "findings=5 blockers=1 tokens=84 lenses=2/2 verified=0 refuted=0 unverified=5",
            "[unverified: inconclusive]", "[unverified: no verdict line]", "[unverified: the verdict did not match its findings]",
            "[unverified: the verifier did not report: failed: step limit]",
          ],
        )
      "swarm-incomplete" =>
        (
          false,
          ["review:correctness", "review:tests"],
          [
            "lens architecture: not started: error: 16 subagents are already running",
            "lens tests: no report: failed: step limit", "A medium finding", "2 lens(es) did not report: the review is incomplete",
          ],
        )
      "swarm-verify-off" =>
        (
          true,
          ["review:correctness", "review:architecture", "review:tests"],
          ["verified=0 refuted=0 unverified=1"],
        )
      "swarm-verify-cap" =>
        (
          // One verifier, and it goes to the blocker listed second.
          true,
          ["review:correctness", "review:verify-1"],
          [
            "findings=1 blockers=0 tokens=24 lenses=1/1 verified=0 refuted=1 unverified=1",
            "Refuted: Claimed deadlock in flush (src/a.mbt:30)",
          ],
        )
      "swarm-budget" =>
        (
          true,
          ["review:correctness", "review:architecture", "review:tests"],
          [
            "verify: skipped, the lenses spent 36 tokens of --max-tokens 30", "unverified=1",
          ],
        )
      "swarm-under-budget" =>
        (
          true,
          [
            "review:correctness", "review:architecture", "review:tests", "review:verify-1",
          ],
          [
            "verified=1 refuted=0 unverified=0", "[verified] detail of A high finding",
          ],
        )
      "swarm-lens-text" =>
        (
          true,
          ["review:compatibility", "review:security"],
          [
            "findings=0 blockers=0 tokens=24 lenses=2/2 verified=0 refuted=0 unverified=0",
          ],
        )
      "swarm-verifier-refused" =>
        (
          // A refused verifier leaves its blocker standing.
          false,
          ["review:correctness"],
          [
            "[unverified: the verifier was not started: error: 16 subagents are already running]",
            "1 blocker finding(s)",
          ],
        )
      "swarm-none" =>
        (
          false,
          ["review:correctness"],
          [
            "lens correctness: no report: failed: step limit", "no lens reported: the review did not run",
          ],
        )
      "swarm-verdict-format" =>
        (
          true,
          [
            "review:correctness", "review:verify-1", "review:verify-2", "review:verify-3",
            "review:verify-4", "review:verify-5",
          ],
          [
            "findings=4 blockers=0 tokens=72 lenses=1/1 verified=1 refuted=1 unverified=3",
            "[verified] detail of Literal newline claim", "Refuted: Period claim (src/a.mbt:3): the code checks it",
            "[unverified: no verdict line]",
          ],
        )
      "swarm-bad-number" => (false, [], ["--verify takes a number from 0 to 8"])
      "swarm-duplicate-lens" => (false, [], ["--lens tests given twice"])
      "swarm-unknown-lens" =>
        (
          false,
          [],
          [
            "unknown lens style: the lenses are correctness, architecture, tests, compatibility, security",
          ],
        )
      _ =>
        (
          false,
          [],
          ["--verify and --max-tokens apply only with --swarm or --lens"],
        )
    }
    assert_eq(code == 0, succeeds, msg=output)
    assert_eq(labels, started, msg=output)
    for part in expected {
      assert_true(
        output.contains(part),
        msg="\{mode}: missing \{part}\n\{output}",
      )
    }
    // The merged report is a real ReviewReport: the engine's own parser and
    // validator accept it.
    let report = output
      .split("\n")
      .find_first(line => line.has_prefix("{\"schema_version\""))
    let reports = match mode {
      "swarm-none"
      | "swarm-unknown-lens"
      | "swarm-verify-alone"
      | "swarm-bad-number"
      | "swarm-duplicate-lens" => false
      _ => true
    }
    assert_eq(report is Some(_), reports, msg=output)
    if report is Some(line) {
      match @agent_review.ReviewReport::parse(@json.parse(line.to_owned())) {
        Ok(parsed) => assert_eq(parsed.validate(), [], msg=line.to_owned())
        Err(why) => fail("\{mode}: the merged report does not parse: \{why}")
      }
    }
    // The report first, then the lens lines, the refutations, the verdict.
    if mode == "swarm-merge" {
      let at = (part : String) => output.find(part).unwrap_or(-1)
      let order = [
        at("{\"schema_version\""),
        at("lens correctness:"),
        at("Refuted:"),
        at("findings=3 blockers="),
      ]
      assert_true(
        order[0] >= 0 &&
        order[0] < order[1] &&
        order[1] < order[2] &&
        order[2] < order[3],
        msg=output,
      )
    }
    println("review: \{mode} passed")
  }
}

///|
async fn verify_hosted(root : String, temp : String) -> Unit {
  let repo = temp + "/repository"
  @fs.mkdir(repo)
  @fs.mkdir(repo + "/sample")
  @fs.mkdir(repo + "/cmd/main", recursive=true)
  write(repo + "/justfile", "check:\n    moon check\n")
  write(
    repo + "/README.md",
    "orientation fixture\n" + String::make(5000, 'x') + "excluded tail",
  )
  write(repo + "/sample/moon.pkg", "")
  write(repo + "/sample/real_implementation.mbt", "")
  write(repo + "/sample/pkg.generated.mbti", "package \"sample\"\n")
  write(repo + "/cmd/main/moon.pkg", "")
  write(repo + "/cmd/main/main.mbt", "fn main {}\n")
  write(temp + "/outside.md", "outside\n")
  @fs.symlink(target=temp + "/outside.md", repo + "/escape.md")
  for name in ["change-review", "repo-map"] {
    let artifact = compile(root, temp, name)
    let expected_calls = if name == "repo-map" { 2 } else { 3 }
    let modes = ["success", "partial", "missing", "busy", "busy-last"]
    if name == "repo-map" {
      modes.append([
        "empty", "bad-line", "fractional-line", "missing-file", "directory", "escape",
        "traversal", "no-citations", "no-recipes",
      ])
    }
    for mode in modes {
      if mode == "no-recipes" {
        @fs.remove(repo + "/justfile")
      }
      let host = fake_host(name, mode)
      let (code, output) = run_against(
        if mode == "missing" {
          None
        } else {
          Some(host)
        },
        artifact,
        [],
        cwd=repo,
      )
      assert_eq(
        code == 0,
        mode == "success" || mode == "no-recipes",
        msg=output,
      )
      let started = match mode {
        "missing" | "busy" => 0
        "busy-last" => expected_calls - 1
        _ => expected_calls
      }
      assert_eq(host.starts.length(), started, msg=output)
      if mode != "missing" && mode != "busy" {
        assert_true(output.contains("scouts=\{expected_calls}"), msg=output)
        // Every child that ran is counted, reported or not: 12 tokens each.
        assert_true(output.contains("tokens=\{started * 12}"), msg=output)
        assert_eq(
          occurrences(output, "offline evidence"),
          if mode == "partial" || mode == "empty" || mode == "busy-last" {
            expected_calls - 1
          } else {
            expected_calls
          },
          msg=output,
        )
        if name == "repo-map" {
          assert_true(
            output.contains("Validation recipes (not executed)"),
            msg=output,
          )
          assert_true(
            output.contains(
              if mode == "no-recipes" {
                "No root justfile found"
              } else {
                "check:\n    moon check"
              },
            ),
            msg=output,
          )
        }
      }
      match mode {
        "partial" | "empty" =>
          assert_true(output.contains("INCOMPLETE:"), msg=output)
        "missing" => assert_true(output.contains("TransportError"), msg=output)
        "busy" | "busy-last" =>
          assert_true(
            output.contains("INCOMPLETE: could not start"),
            msg=output,
          )
        "bad-line"
        | "fractional-line"
        | "missing-file"
        | "directory"
        | "escape"
        | "traversal" => assert_true(output.contains("UNVERIFIED:"), msg=output)
        "success" if name == "repo-map" =>
          assert_eq(occurrences(output, "CHECKED:"), 2, msg=output)
        _ => ()
      }
      println("\{name}: \{mode} passed")
    }
  }
}
