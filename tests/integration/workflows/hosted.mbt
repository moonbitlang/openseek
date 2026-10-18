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
      self.starts.push(arguments)
      let job = "job-\{self.starts.length()}"
      self.reports[job] = child_report(self.name, self.mode, job, arguments)
      reply("started \{job}", data={ "job_id": job, "session": "p-sr-\{job}" })
    }
    "job_wait" => {
      guard arguments is { "job_ids": Array(ids), .. } else {
        return reply("error: job_ids", is_error=true)
      }
      let jobs : Array[Json] = ids.map(id => {
        "job_id": id,
        "state": "ended",
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
      match report {
        Err(why) =>
          reply("no report", data={
            "job_id": job,
            "state": { "job_id": job, "state": "ended", "outcome": why },
            "subagent": { "usage": usage },
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
            "subagent": { "usage": usage },
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
) -> (Int32, String) {
  let env = clean_env()
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
  { name, mode, audit, starts: [], reports: Map([]), }
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
