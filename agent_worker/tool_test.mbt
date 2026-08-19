///|
/// Mock-endpoint harness for the CHILD-side worker execution (`run_child`
/// runs the worker's turn in this process, exactly as `openseek subrun
/// worker` will in a child process). The parent-side spawn/reap path is
/// covered by the runner's own tests with scripted children.
async fn bind_test_server(skip_message : String) -> @http.Server? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println(skip_message)
      return None
    }
    error => raise error
  }
  Some(server)
}

///|
async fn worker_test_server(
  group : @async.TaskGroup[Unit],
  handle : (Json) -> String raise,
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping worker test")
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        assert_eq(request.path, "/chat/completions")
        let payload = handle(@json.parse(body.read_all().text()))
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write("data: \{payload}\n\n")
        conn.write("data: [DONE]\n\n")
      },
      max_connections=8,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
fn sse_tool_call(name : String, arguments : Json, total_tokens : Int) -> String {
  (
    {
      "choices": [
        {
          "delta": {
            "tool_calls": [
              {
                "index": 0,
                "id": "call_1",
                "type": "function",
                "function": { "name": name, "arguments": arguments.stringify() },
              },
            ],
          },
        },
      ],
      "usage": {
        "prompt_tokens": total_tokens - 1_000,
        "completion_tokens": 1_000,
        "total_tokens": total_tokens,
      },
    } : Json).stringify()
}

///|
fn good_report_json() -> Json {
  {
    "schema_version": 1,
    "status": "done",
    "summary": "fixed the deprecated call",
    "verification": "moon check clean",
  }
}

///|
/// A realistic worker geometry inside one tmpdir: a repo root (denied), a
/// nested worker tree (allowed), and an admin dir below the denied root.
async fn with_worker_fixture(body : async (Json) -> Unit) -> Unit {
  @vfs.with_tmpdir(prefix="openseek-worker-kind-", dir => {
    let root = @fs.realpath(dir)
    @fs.mkdir("\{root}/w")
    @fs.mkdir("\{root}/w/lib")
    @vfs.write_text("\{root}/w/lib", "a.txt", "seed\n")
    @vfs.write_text("\{root}/w", "outside.txt", "keep\n")
    @fs.mkdir("\{root}/gitadmin")
    let input : Json = {
      "task": "Fix the placeholder in lib/a.txt.",
      "worker_root": "\{root}/w",
      "worker_admin_dir": "\{root}/gitadmin",
      "deny_roots": [root],
      "allowed_paths": ["lib"],
      "base_oid": "0123456789abcdef0123456789abcdef01234567",
    }
    body(input)
  })
}

///|
async test "run_child runs a confined worker to a captured report" {
  with_worker_fixture(input => {
    @async.with_task_group() <| group => {
      let mut calls = 0
      let handle : (Json) -> String raise = _request => {
        calls += 1
        if calls == 1 {
          // First model turn: edit inside the allowed prefix.
          sse_tool_call(
            "edit",
            {
              "path": "lib/a.txt",
              "old_string": "seed",
              "new_string": "fixed",
              "start_line": 1,
            },
            50_000,
          )
        } else {
          sse_tool_call("submit_result", good_report_json(), 60_000)
        }
      }
      guard worker_test_server(group, handle) is Some(url) else { return }
      guard @agent_worker.run_child(
          input,
          api_key="test-key",
          model=Deepseek(V4Flash),
          max_steps=8,
          api_url=url,
        )
        is Ok(Some(report)) else {
        fail("expected a captured report")
      }
      assert_eq(report.status, "done")
      // The in-scope edit really landed.
      guard input is { "worker_root": String(worker_root), .. } else {
        fail("fixture input")
      }
      assert_eq(@fs.read_file("\{worker_root}/lib/a.txt").text(), "fixed\n")
    }
  })
}

///|
async test "run_child wires the write scope into the file tools" {
  with_worker_fixture(input => {
    @async.with_task_group() <| group => {
      let mut calls = 0
      let mut blocked_result = ""
      let handle : (Json) -> String raise = request => {
        calls += 1
        if calls == 1 {
          // First model turn: try to edit OUTSIDE the allowed prefix.
          sse_tool_call(
            "edit",
            {
              "path": "outside.txt",
              "old_string": "keep",
              "new_string": "gone",
              "start_line": 1,
            },
            50_000,
          )
        } else {
          // The second request carries the first tool's result back to the
          // model; capture it for the assertion below.
          if calls == 2 {
            blocked_result = request.stringify()
          }
          sse_tool_call(
            "submit_result",
            {
              "schema_version": 1,
              "status": "partial",
              "summary": "fixed what was in scope",
              "verification": "moon check clean",
            },
            60_000,
          )
        }
      }
      guard worker_test_server(group, handle) is Some(url) else { return }
      guard @agent_worker.run_child(
          input,
          api_key="test-key",
          model=Deepseek(V4Flash),
          max_steps=8,
          api_url=url,
        )
        is Ok(Some(report)) else {
        fail("expected a captured report")
      }
      assert_eq(report.status, "partial")
      assert_true(blocked_result.contains("write blocked"))
      // Nothing reached the out-of-scope file.
      guard input is { "worker_root": String(worker_root), .. } else {
        fail("fixture input")
      }
      assert_eq(@fs.read_file("\{worker_root}/outside.txt").text(), "keep\n")
    }
  })
}

///|
async test "run_child refuses malformed input without a model call" {
  guard @agent_worker.run_child(
      { "task": "x" },
      api_key="unused",
      model=Deepseek(V4Flash),
      max_steps=2,
      api_url="http://127.0.0.1:1/unused",
    )
    is Err(reason) else {
    fail("expected an input rejection")
  }
  assert_true(reason.contains("worker_root"))
}

///|
test "worker input parse validates every field" {
  let good : Json = {
    "task": "t",
    "worker_root": "/w",
    "worker_admin_dir": "/g/a",
    "deny_roots": ["/g"],
    "allowed_paths": ["lib"],
    "base_oid": "abc",
  }
  guard @agent_worker.WorkerInput::parse(good) is Ok(parsed) else {
    fail("expected a valid input")
  }
  assert_eq(parsed.allowed_paths, ["lib"])
  for
    bad in (
      [
        { "worker_root": "/w" },
        variant(task="  "),
        variant(worker_root="relative"),
        variant(deny_roots=[]),
        variant(allowed_paths=[]),
        variant(base_oid=""),
      ] : Array[Json]) {
    guard @agent_worker.WorkerInput::parse(bad) is Err(_) else {
      fail("expected a rejection for \{bad.stringify()}")
    }
  }
}

///|
fn variant(
  task? : String = "t",
  worker_root? : String = "/w",
  deny_roots? : Array[Json] = ["/g"],
  allowed_paths? : Array[Json] = ["lib"],
  base_oid? : String = "abc",
) -> Json {
  {
    "task": task,
    "worker_root": worker_root,
    "worker_admin_dir": "/g/a",
    "deny_roots": deny_roots,
    "allowed_paths": allowed_paths,
    "base_oid": base_oid,
  }
}
