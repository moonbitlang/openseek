///|
async test "invalid review deadline is rejected before fleet workspaces are created" {
  @vfs.with_tmpdir(prefix="openseek-review-deadline-fleet-", root => {
    let source = "\{root}/project"
    @fs.mkdir(source, recursive=true)
    let parsed = @testkit.run_matches(
      argv=[
        "--review-deadline", "0", "--concurrency", "1", "--dir", source, "write",
        "MoonBit",
      ],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = @run.run_task_command(parsed) catch {
      error => {
        assert_true(
          "\{error}".contains("--review-deadline must be a positive integer"),
        )
        assert_false(@fs.exists("\{root}/project_run_1"))
        return
      }
    }
    fail("invalid review deadline started a fleet run")
  })
}

///|
/// Serve every chat request with the one streamed `delta`, and return the
/// endpoint URL — `None` where local TCP binds are not permitted.
async fn scripted_provider(
  group : @async.TaskGroup[Unit],
  delta : Json,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println("local TCP bind unavailable; skipping run exit test")
      return None
    }
    error => raise error
  }
  let chunk : Json = {
    "choices": [{ "delta": delta }],
    "usage": { "prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15 },
  }
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        ignore(body.read_all())
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write("data: \{chunk.stringify()}\n\n")
        conn.write("data: [DONE]\n\n")
      },
      max_connections=8,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
fn one_step_run(root : String, url : String) -> @argparse.Matches raise {
  @testkit.run_matches(
    argv=[
      "--max-steps", "1", "--no-session", "--dir", root, "--api-url", url, "task",
    ],
    env={ "DEEPSEEK": "test-key" },
  )
}

///|
async test "a single run that completes exits successfully" {
  @vfs.with_tmpdir(prefix="openseek-run-complete-", root => {
    @async.with_task_group() <| group => {
      guard scripted_provider(group, { "content": "done" }) is Some(url) else {
        return
      }
      @run.run_task_command(one_step_run(root, url))
    }
  })
}

///|
async test "a single run that does not complete fails like a fleet run" {
  @vfs.with_tmpdir(prefix="openseek-run-incomplete-", root => {
    @async.with_task_group() <| group => {
      // A tool call in the only step: the step budget runs out before the
      // model can answer.
      let delta : Json = {
        "tool_calls": [
          {
            "index": 0,
            "id": "call_1",
            "type": "function",
            "function": { "name": "no_such_tool", "arguments": "{}" },
          },
        ],
      }
      guard scripted_provider(group, delta) is Some(url) else { return }
      let _ = @run.run_task_command(one_step_run(root, url)) catch {
        error => {
          assert_true(
            "\{error}".contains("run did not complete: max steps exhausted"),
          )
          return
        }
      }
      fail("a run that exhausted its steps exited successfully")
    }
  })
}
