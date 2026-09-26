///|
async test "an invalid review deadline is rejected before the workspace is created" {
  @vfs.with_tmpdir(prefix="openseek-review-deadline-", root => {
    let workspace = "\{root}/project"
    let parsed = @testkit.run_matches(
      argv=["--review-deadline", "0", "--dir", workspace, "write", "MoonBit"],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = @run.run_task_command(parsed) catch {
      error => {
        assert_true(
          "\{error}".contains("--review-deadline must be a positive integer"),
        )
        assert_false(@fs.exists(workspace))
        return
      }
    }
    fail("an invalid review deadline started a run")
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
fn one_step_run(
  root : String,
  url : String,
  extra~ : Array[String],
) -> @argparse.Matches raise {
  @testkit.run_matches(
    argv=[
      "--max-steps", "1", "--no-session", "--dir", root, "--api-url", url, ..extra,
      "task",
    ],
    env={ "DEEPSEEK": "test-key" },
  )
}

///|
async fn read_result(path : String) -> @openseek_protocol.RunResult {
  @openseek_protocol.parse_run_result(@json.parse(@fs.read_file(path).text()))
}

///|
/// All cases in ONE test: each run opens the process-wide event sink and
/// drains it to stdout, and two runs from concurrently scheduled async tests
/// would write stdout at the same time.
async test "a single run exits successfully only when its turn completes" {
  @vfs.with_tmpdir(prefix="openseek-run-exit-", root => {
    let result_file = "\{root}/result.json"
    let usage : @openseek_protocol.Usage = {
      prompt_tokens: 10,
      completion_tokens: 5,
      total_tokens: 15,
      prompt_cache_hit_tokens: 0,
      prompt_cache_miss_tokens: 0,
    }
    @async.with_task_group() <| group => {
      guard scripted_provider(group, { "content": "done" }) is Some(url) else {
        return
      }
      // A stale result from an earlier run is replaced, never trusted.
      @fs.write_file(result_file, "stale", create_mode=CreateOrTruncate)
      @run.run_task_command(
        one_step_run("\{root}/complete", url, extra=[
          "--result-file", result_file,
        ]),
      )
      assert_eq(read_result(result_file), {
        status: Completed(output={ "answer": "done" }),
        session: None,
        usage: Some(usage),
      })
    }
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
      let _ = @run.run_task_command(
        one_step_run("\{root}/incomplete", url, extra=[
          "--result-file", result_file,
        ]),
      ) catch {
        error => {
          assert_true(
            "\{error}".contains("run did not complete: max steps exhausted"),
          )
          assert_eq(read_result(result_file), {
            status: MaxStepsExhausted,
            session: None,
            usage: Some(usage),
          })
          return
        }
      }
      fail("a run that exhausted its steps exited successfully")
    }
    // A resumed session: each run's usage covers only its own turn.
    @async.with_task_group() <| group => {
      guard scripted_provider(group, { "content": "done" }) is Some(url) else {
        return
      }
      let argv = [
        "--max-steps",
        "1",
        "--session",
        "resumed",
        "--session-root",
        "\{root}/sessions",
        "--dir",
        "\{root}/durable",
        "--api-url",
        url,
        "--result-file",
        result_file,
        "task",
      ]
      for _ in 0..<2 {
        @run.run_task_command(
          @testkit.run_matches(argv~, env={ "DEEPSEEK": "test-key" }),
        )
      }
      assert_eq(read_result(result_file), {
        status: Completed(output={ "answer": "done" }),
        session: Some("resumed"),
        usage: Some(usage),
      })
    }
    // A run that fails before its turn still says so, with no usage.
    let no_key = @testkit.run_matches(
      argv=[
        "--no-session",
        "--dir",
        "\{root}/no-key",
        "--result-file",
        result_file,
        "task",
      ],
      env={},
    )
    let _ = @run.run_task_command(no_key) catch {
      error => {
        guard read_result(result_file)
          is { status: Failed(reason~), session: None, usage: None, } else {
          fail("unexpected result for a keyless run")
        }
        // The same text the CLI prints after `error: `.
        assert_true(reason.has_prefix("an API key is required for "))
        assert_eq(reason, @cli.failure_message("\{error}").to_owned())
        return
      }
    }
    fail("a run without an API key exited successfully")
  })
}
